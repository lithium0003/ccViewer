//
//  pCloudStorage.swift
//  RemoteCloud
//
//  Created by rei8 on 2019/04/26.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import AuthenticationServices
import os.log
import CoreData

public class pCloudStorage: NetworkStorage, URLSessionDataDelegate {
    public override func getStorageType() -> CloudStorages {
        return .pCloud
    }
    
    var webAuthSession: ASWebAuthenticationSession?
    let uploadSemaphore = Semaphore(value: 5)

    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .pCloud)
        storageName = name
    }
    
    private let clientid = SecretItems.pCloud.client_id
    private let secret = SecretItems.pCloud.client_secret
    private let callbackUrlScheme = SecretItems.pCloud.callbackUrlScheme
    private let redirect = "\(SecretItems.pCloud.callbackUrlScheme)://oauth2redirect"

    override var authURL: URL {
        let url = "https://my.pcloud.com/oauth2/authorize?client_id=\(clientid)&response_type=code&redirect_uri=\(redirect)"
        return URL(string: url)!
    }
    override var authCallback: ASWebAuthenticationSession.Callback {
        ASWebAuthenticationSession.Callback.customScheme(callbackUrlScheme)
    }
    override var additionalHeaderFields: [String: String] {
        return [:]
    }

    override func signIn(_ successURL: URL) async throws -> Bool {
        let oauthToken = NSURLComponents(string: (successURL.absoluteString))?.queryItems?.filter({$0.name == "code"}).first
        
        if let oauthTokenString = oauthToken?.value {
            return await getToken(oauthToken: oauthTokenString)
        }
        return false
    }

    override func getToken(oauthToken: String) async -> Bool {
        os_log("%{public}@", log: log, type: .debug, "getToken(pCloud:\(storageName ?? ""))")

        var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/oauth2_token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        let post = "client_id=\(clientid)&client_secret=\(secret)&code=\(oauthToken)"
        let postData = post.data(using: .ascii, allowLossyConversion: false)!
        let postLength = "\(postData.count)"
        request.setValue(postLength, forHTTPHeaderField: "Content-Length")
        request.httpBody = postData
    
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            guard let json = object as? [String: Any] else {
                return false
            }
            print(json)
            guard let accessToken = json["access_token"] as? String else {
                return false
            }
            guard let userId = json["userid"] as? Int else {
                return false
            }
            await saveToken(accessToken: accessToken, accountId: String(userId))
            return true
        }
        catch {
            print(error)
        }
        return false
    }

    override func checkToken() async -> Bool {
        return await accessToken() != ""
    }
    
    func saveToken(accessToken: String, accountId: String) async -> Void {
        if let name = storageName {
            guard accessToken != "" && accountId != "" else {
                return
            }
            os_log("%{public}@", log: log, type: .info, "saveToken")
            cacheTokenDate = Date()
            cache_accessToken = accessToken
            _ = await setKeyChain(key: "\(name)_accessToken", value: accessToken)
            _ = await setKeyChain(key: "\(name)_accountId", value: accountId)
        }
    }

    public override func logout() async {
        if let name = storageName {
            let _ = await delKeyChain(key: "\(name)_accountId")
        }
        await super.logout()
    }
    
    override func revokeToken(token: String) async -> Bool {
        os_log("%{public}@", log: log, type: .debug, "revokeToken(pCloud:\(storageName ?? ""))")
    
        var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/logout")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
    
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            guard let json = object as? [String: Any] else {
                return false
            }
            print(json)
            guard let result = json["result"] as? Int else {
                return false
            }
            return result == 0
        }
        catch {
            print(error)
        }
        return false
    }

    override func isAuthorized() async -> Bool {
        var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/userinfo")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            guard let json = object as? [String: Any] else {
                return false
            }
            if let result = json["result"] as? Int, result == 0 {
                return true
            }
        }
        catch {
            print(error)
        }
        return false
    }

    func listFolder(folderId: Int) async -> [[String:Any]]? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "listFolder(pCloud:\(storageName ?? ""))")

                let url = "https://api.pcloud.com/listfolder?folderid=\(folderId)&timeformat=timestamp"

                var request: URLRequest = URLRequest(url: URL(string: url)!)
                request.httpMethod = "GET"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")

                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let result = json["result"] as? Int, result == 0 else {
                    print(json)
                    throw RetryError.Retry
                }
                guard let metadata = json["metadata"] as? [String: Any] else {
                    print(json)
                    throw RetryError.Retry
                }
                guard let contents = metadata["contents"] as? [[String: Any]] else {
                    print(json)
                    throw RetryError.Retry
                }
                return contents
            })
        }
        catch {
            return nil
        }
    }
    
    func storeItem(item: [String: Any], parentFileId: String? = nil, parentPath: String? = nil, context: NSManagedObjectContext) {
        guard let id = item["id"] as? String else {
            return
        }
        guard let name = item["name"] as? String else {
            return
        }
        guard let ctime = item["created"] as? Int else {
            return
        }
        guard let mtime = item["modified"] as? Int else {
            return
        }
        guard let folder = item["isfolder"] as? Bool else {
            return
        }
        let size = item["size"] as? Int64 ?? 0
        let hashint = item["hash"] as? Int
        
        context.performAndWait {
            var prevParent: String?
            var prevPath: String?
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
            if let result = try? context.fetch(fetchRequest) {
                for object in result {
                    if let item = object as? RemoteData {
                        prevPath = item.path
                        let component = prevPath?.components(separatedBy: "/")
                        prevPath = component?.dropLast().joined(separator: "/")
                        prevParent = item.parent
                    }
                    context.delete(object as! NSManagedObject)
                }
            }
            
            let newitem = RemoteData(context: context)
            newitem.storage = self.storageName
            newitem.id = id
            newitem.name = name
            let comp = name.components(separatedBy: ".")
            if comp.count >= 1 {
                newitem.ext = comp.last!.lowercased()
            }
            newitem.cdate = Date(timeIntervalSince1970: TimeInterval(ctime))
            newitem.mdate = Date(timeIntervalSince1970: TimeInterval(mtime))
            newitem.folder = folder
            newitem.size = size
            newitem.hashstr = (hashint == nil) ? "" : String(hashint!)
            newitem.parent = (parentFileId == nil) ? prevParent : parentFileId
            if parentFileId == "" {
                newitem.path = "\(self.storageName ?? ""):/\(name)"
            }
            else {
                if let path = (parentPath == nil) ? prevPath : parentPath {
                    newitem.path = "\(path)/\(name)"
                }
            }
        }
    }

    override func listChildren(fileId: String, path: String) async {
        let viewContext = CloudFactory.shared.data.viewContext
        let storage = storageName ?? ""
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest) {
                for object in result {
                    viewContext.delete(object as! NSManagedObject)
                }
            }
        }
        let folderId: Int
        if fileId == "" {
            folderId = 0
        }
        else if fileId.starts(with: "d") {
            folderId = Int(fileId.dropFirst()) ?? 0
        }
        else {
            return
        }
        if let items = await listFolder(folderId: folderId) {
            for item in items {
                storeItem(item: item, parentFileId: fileId, parentPath: path, context: viewContext)
            }
            await viewContext.perform {
                try? viewContext.save()
            }
        }
    }

    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil) async throws -> Data? {
        let id: Int
        if fileId.starts(with: "f") {
            id = Int(fileId.dropFirst()) ?? 0
        }
        else {
            return nil
        }

        if let cache = await CloudFactory.shared.cache.getCache(storage: storageName!, id: fileId, offset: start ?? 0, size: length ?? -1) {
            if let data = try? Data(contentsOf: cache) {
                os_log("%{public}@", log: log, type: .debug, "hit cache(pCloud:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                return data
            }
        }

        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "readFile(pCloud:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")

                var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/getfilelink?fileid=\(id)")!)
                request.httpMethod = "GET"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")

                let (data, _) = try await URLSession.shared.data(for: request)
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let result = json["result"] as? Int, result == 0 else {
                    print(json)
                    throw RetryError.Retry
                }
                guard let hosts = json["hosts"] as? [String], hosts.count > 0 else {
                    print(json)
                    throw RetryError.Retry
                }
                guard let path = json["path"] as? String else {
                    print(json)
                    throw RetryError.Retry
                }
                let downLink = "https://" + hosts.first! + path

                var request2: URLRequest = URLRequest(url: URL(string: downLink)!)
                request2.httpMethod = "GET"
                request2.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                let s = start ?? 0
                if length == nil {
                    request2.setValue("bytes=\(s)-", forHTTPHeaderField: "Range")
                }
                else {
                    request2.setValue("bytes=\(s)-\(s+length!-1)", forHTTPHeaderField: "Range")
                }

                guard let (data2, _) = try? await URLSession.shared.data(for: request2) else {
                    throw RetryError.Retry
                }
                if let length, data2.count != length {
                    throw RetryError.Retry
                }
                await CloudFactory.shared.cache.saveCache(storage: storageName!, id: fileId, offset: start ?? 0, data: data2)
                return data2
            })
        }
        catch {
            return nil
        }
    }

    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await NetworkRemoteItem(path: path)
    }

    func createfolder(folderid: Int, name: String) async -> [String: Any]? {
        do {
            return try await callWithRetry(action: { [self] in
                let body = "folderid=\(folderid)&name=\(name)&timeformat=timestamp"
                var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/createfolder")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.httpBody = body.data(using: .utf8)

                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let result = json["result"] as? Int, result == 0 else {
                    print(json)
                    throw RetryError.Retry
                }
                guard let metadata = json["metadata"] as? [String: Any] else {
                    print(json)
                    throw RetryError.Retry
                }
                return metadata
            })
        }
        catch {
            return nil
        }
    }
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        guard parentId.starts(with: "d") || parentId == "" else {
            return nil
        }

        os_log("%{public}@", log: log, type: .debug, "makeFolder(pCloud:\(storageName ?? "") \(parentId) \(newname)")
        let id = Int(parentId.dropFirst()) ?? 0

        let metadata = await createfolder(folderid: id, name: newname)
        guard let metadata = metadata, let newid = metadata["id"] as? String else {
            return nil
        }

        let viewContext = CloudFactory.shared.data.viewContext
        storeItem(item: metadata, parentFileId: parentId, parentPath: parentPath, context: viewContext)
        await viewContext.perform {
            try? viewContext.save()
        }
        return newid
    }
    
    func deletefolderrecursive(folderId: Int) async -> Bool {
        do {
            return try await callWithRetry(action: { [self] in
                let body = "folderid=\(folderId)"
                var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/deletefolderrecursive")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.httpBody = body.data(using: .utf8)

                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let result = json["result"] as? Int, result == 0 else {
                    print(json)
                    throw RetryError.Retry
                }
                return true
            })
        }
        catch {
            return false
        }
    }

    func deletefile(fileId: Int) async -> Bool {
        do {
            return try await callWithRetry(action: { [self] in
                let body = "fileid=\(fileId)"
                var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/deletefile")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.httpBody = body.data(using: .utf8)

                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let result = json["result"] as? Int, result == 0 else {
                    print(json)
                    throw RetryError.Retry
                }
                return true
            })
        }
        catch {
            return false
        }
    }

    override func deleteItem(fileId: String) async -> Bool {
        os_log("%{public}@", log: log, type: .debug, "deleteItem(pCloud:\(storageName ?? "") \(fileId)")
        
        if fileId.starts(with: "f") {
            let id = Int(fileId.dropFirst()) ?? 0
            guard await deletefile(fileId: id) else {
                return false
            }
            let viewContext = CloudFactory.shared.data.viewContext
            let storage = storageName ?? ""
            await viewContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                if let result = try? viewContext.fetch(fetchRequest) {
                    for object in result {
                        viewContext.delete(object as! NSManagedObject)
                    }
                }
            }
            deleteChildRecursive(parent: fileId, context: viewContext)
            await viewContext.perform {
                try? viewContext.save()
            }
            return true
        }
        else if fileId.starts(with: "d") {
            let id = Int(fileId.dropFirst()) ?? 0
            guard await deletefolderrecursive(folderId: id) else {
                return false
            }
            let viewContext = CloudFactory.shared.data.viewContext
            let storage = storageName ?? ""
            await viewContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                if let result = try? viewContext.fetch(fetchRequest) {
                    for object in result {
                        viewContext.delete(object as! NSManagedObject)
                    }
                }
            }
            deleteChildRecursive(parent: fileId, context: viewContext)
            await viewContext.perform {
                try? viewContext.save()
            }
            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
            return true
        }
        return false
    }
    
    func renamefile(fileId: Int, toFolderId: Int? = nil, toName: String? = nil) async -> [String: Any]? {
        guard toFolderId != nil || toName != nil else {
            return nil
        }
        do {
            return try await callWithRetry(action: { [self] in
                var rename = "fileid=\(fileId)&timeformat=timestamp"
                if let toFolderId = toFolderId {
                    rename += "&tofolderid=\(toFolderId)"
                }
                if let toName = toName {
                    rename += "&toname=\(toName)"
                }
                var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/renamefile")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.httpBody = rename.data(using: .utf8)

                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let result = json["result"] as? Int, result == 0 else {
                    print(json)
                    throw RetryError.Retry
                }
                guard let metadata = json["metadata"] as? [String: Any] else {
                    print(json)
                    throw RetryError.Retry
                }
                return metadata
            })
        }
        catch {
            return nil
        }
    }

    func renamefolder(folderId: Int, toFolderId: Int? = nil, toName: String? = nil) async -> [String: Any]? {
        guard toFolderId != nil || toName != nil else {
            return nil
        }
        do {
            return try await callWithRetry(action: { [self] in
                var rename = "folderid=\(folderId)&timeformat=timestamp"
                if let toFolderId = toFolderId {
                    rename += "&tofolderid=\(toFolderId)"
                }
                if let toName = toName {
                    rename += "&toname=\(toName)"
                }
                var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/renamefolder")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.httpBody = rename.data(using: .utf8)

                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let result = json["result"] as? Int, result == 0 else {
                    print(json)
                    throw RetryError.Retry
                }
                guard let metadata = json["metadata"] as? [String: Any] else {
                    print(json)
                    throw RetryError.Retry
                }
                return metadata
            })
        }
        catch {
            return nil
        }
    }

    override func renameItem(fileId: String, newname: String) async -> String? {
        os_log("%{public}@", log: log, type: .debug, "renameItem(pCloud:\(storageName ?? "") \(fileId) \(newname)")
        
        if fileId.starts(with: "f") {
            let id = Int(fileId.dropFirst()) ?? 0
            guard let metadata = await renamefile(fileId: id, toName: newname), let newid = metadata["id"] as? String else {
                return nil
            }
            let viewContext = CloudFactory.shared.data.viewContext
            storeItem(item: metadata, context: viewContext)
            await viewContext.perform {
                try? viewContext.save()
            }
            return newid
        }
        else if fileId.starts(with: "d") {
            let id = Int(fileId.dropFirst()) ?? 0
            guard let metadata = await renamefolder(folderId: id, toName: newname), let newid = metadata["id"] as? String else {
                return nil
            }
            let viewContext = CloudFactory.shared.data.viewContext
            storeItem(item: metadata, context: viewContext)
            await viewContext.perform {
                try? viewContext.save()
            }
            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
            return newid
        }
        return nil
    }

    override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        if fromParentId == toParentId {
            return nil
        }
        if !(fromParentId == "" || fromParentId.starts(with: "d")) || !(toParentId == "" || toParentId.starts(with: "d")) {
            return nil
        }
        let toId = Int(toParentId.dropFirst()) ?? 0
        
        os_log("%{public}@", log: log, type: .debug, "moveItem(pCloud:\(storageName ?? "") \(fileId) \(fromParentId) \(toParentId)")
        
        if fileId.starts(with: "d") {
            let id = Int(fileId.dropFirst()) ?? 0
            guard let metadata = await renamefolder(folderId: id, toFolderId: toId), let newid = metadata["id"] as? String else {
                return nil
            }
            var toParentPath = ""
            if toParentId != "" {
                toParentPath = await getParentPath(parentId: toParentId) ?? toParentPath
            }
            let viewContext = CloudFactory.shared.data.viewContext
            storeItem(item: metadata, parentFileId: toParentId, parentPath: toParentPath, context: viewContext)
            await viewContext.perform {
                try? viewContext.save()
            }
            return newid
        }
        else if fileId.starts(with: "f") {
            let id = Int(fileId.dropFirst()) ?? 0
            guard let metadata = await renamefile(fileId: id, toFolderId: toId), let newid = metadata["id"] as? String else {
                return nil
            }
            var toParentPath = ""
            if toParentId != "" {
                toParentPath = await getParentPath(parentId: toParentId) ?? toParentPath
            }
            let viewContext = CloudFactory.shared.data.viewContext
            storeItem(item: metadata, parentFileId: toParentId, parentPath: toParentPath, context: viewContext)
            await viewContext.perform {
                try? viewContext.save()
            }
            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
            return newid
        }
        return nil
    }

    override func uploadFile(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        defer {
            try? FileManager.default.removeItem(at: target)
        }
        
        guard parentId == "" || parentId.starts(with: "d") else {
            return nil
        }
        let folderId = Int(parentId.dropFirst()) ?? 0
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "uploadFile(pCloud:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")

                let attr = try FileManager.default.attributesOfItem(atPath: target.path(percentEncoded: false))
                let fileSize = attr[.size] as! UInt64

                var parentPath = "\(storageName ?? ""):/"
                if parentId != "" {
                    parentPath = await getParentPath(parentId: parentId) ?? parentPath
                }
                let handle = try FileHandle(forReadingFrom: target)
                defer {
                    try? handle.close()
                }
                let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(Int.random(in: 0...0xffffffff))")
                
                var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/uploadfile")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                let boundary = "Boundary-\(UUID().uuidString)"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                
                let boundaryText = "--\(boundary)\r\n"
                var body = Data()
                var footer = Data()
                
                body.append(boundaryText.data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"folderid\"\r\n\r\n".data(using: .utf8)!)
                body.append(String(folderId).data(using: .utf8)!)
                body.append("\r\n".data(using: .utf8)!)
                body.append(boundaryText.data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"timeformat\"\r\n\r\n".data(using: .utf8)!)
                body.append("timestamp".data(using: .utf8)!)
                body.append("\r\n".data(using: .utf8)!)
                
                body.append(boundaryText.data(using: .utf8)!)
                body.append("Content-Disposition: form-data; filename=\"\(uploadname)\"\r\n".data(using: .utf8)!)
                body.append("Content-Length: \(fileSize)\r\n\r\n".data(using: .utf8)!)
                //file body is here
                footer.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
                
                guard let stream = OutputStream(url: tmpurl, append: false) else {
                    throw RetryError.Retry
                }
                defer {
                    try? FileManager.default.removeItem(at: tmpurl)
                }
                stream.open()
                do {
                    defer {
                        stream.close()
                    }
                    if body.withUnsafeBytes({
                        stream.write($0.baseAddress!, maxLength: body.count)
                    }) < body.count {
                        throw RetryError.Retry
                    }
                    var offset = 0
                    while offset < fileSize {
                        guard let srcData = try handle.read(upToCount: 100*320*1024) else {
                            throw RetryError.Retry
                        }
                        offset += srcData.count
                        if srcData.withUnsafeBytes({
                            stream.write($0.baseAddress!, maxLength: srcData.count)
                        }) < srcData.count {
                            throw RetryError.Retry
                        }
                    }
                    if footer.withUnsafeBytes({
                        stream.write($0.baseAddress!, maxLength: footer.count)
                    }) < footer.count {
                        throw RetryError.Retry
                    }
                }
                
                let attr2 = try FileManager.default.attributesOfItem(atPath: tmpurl.path)
                let fileSize2 = attr2[.size] as! UInt64
                try await progress?(0, Int64(fileSize2))

                await uploadProgressManeger.setCallback(url: request.url!, total: Int64(fileSize2), callback: progress)
                defer {
                    Task { await uploadProgressManeger.removeCallback(url: request.url!) }
                }

                guard let (data, _) = try? await URLSession.shared.upload(for: request, fromFile: tmpurl, delegate: self) else {
                    throw RetryError.Retry
                }
                guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let result = object["result"] as? Int, result == 0 else {
                    print(object)
                    throw RetryError.Retry
                }
                guard let metadatas = object["metadata"] as? [[String: Any]], let metadata = metadatas.first else {
                    print(object)
                    throw RetryError.Retry
                }
                guard let newid = metadata["id"] as? String else {
                    print(object)
                    throw RetryError.Retry
                }
                let viewContext = CloudFactory.shared.data.viewContext
                storeItem(item: metadata, parentFileId: parentId, parentPath: parentPath, context: viewContext)
                await viewContext.perform {
                    try? viewContext.save()
                }
                try await progress?(Int64(fileSize2), Int64(fileSize2))
                return newid
            }, semaphore: uploadSemaphore, maxCall: 3)
        }
        catch {
            return nil
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if let url = task.originalRequest?.url {
            Task {
                do {
                    try await uploadProgressManeger.progress(url: url, currnt: totalBytesSent)
                }
                catch {
                    task.cancel()
                }
            }
        }
    }
}

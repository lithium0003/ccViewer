//
//  OneDriveStorage.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/03/20.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import AuthenticationServices
import os.log
import CoreData

public class OneDriveStorage: NetworkStorage, URLSessionDataDelegate {
    public override func getStorageType() -> CloudStorages {
        return .OneDrive
    }
    
    var webAuthSession: ASWebAuthenticationSession?
    let uploadSemaphore = Semaphore(value: 5)
    
    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .OneDrive)
        storageName = name
    }
    
    private let clientid = SecretItems.OneDrive.client_id
    private let callbackUrlScheme = SecretItems.OneDrive.callbackUrlScheme
    private let redirect = "\(SecretItems.OneDrive.callbackUrlScheme)://auth"
    private let scope = "user.read files.readwrite.all offline_access".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    private let apiEndPoint = "https://graph.microsoft.com/v1.0/me/drive"
    
    override var authURL: URL {
        let url = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=\(clientid)&scope=\(scope)&response_type=code&redirect_uri=\(redirect)"
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
        os_log("%{public}@", log: log, type: .debug, "getToken(onedrive:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let post = "client_id=\(clientid)&redirect_uri=\(redirect)&code=\(oauthToken)&scope=\(scope)&grant_type=authorization_code"
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
            //print(json)
            guard let accessToken = json["access_token"] as? String else {
                return false
            }
            guard let refreshToken = json["refresh_token"] as? String else {
                return false
            }
            guard let expires_in = json["expires_in"] as? Int else {
                return false
            }
            tokenLife = TimeInterval(expires_in)
            await saveToken(accessToken: accessToken, refreshToken: refreshToken)
            return true
        }
        catch {
            print(error)
        }
        return false
    }
    
    override func refreshToken() async -> Bool {
        os_log("%{public}@", log: log, type: .debug, "refreshToken(onedrive:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let post = "client_id=\(clientid)&redirect_uri=\(redirect)&refresh_token=\(await getRefreshToken())&scope=\(scope)&grant_type=refresh_token"
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
            //print(json)
            guard let accessToken = json["access_token"] as? String else {
                return false
            }
            guard let expires_in = json["expires_in"] as? Int else {
                return false
            }
            tokenLife = TimeInterval(expires_in)
            await saveToken(accessToken: accessToken, refreshToken: getRefreshToken())
            return true
        }
        catch {
            print(error)
        }
        return false
    }
    
    override func isAuthorized() async -> Bool {
        guard apiEndPoint != "" else {
            return false
        }
        var request: URLRequest = URLRequest(url: URL(string: "\(apiEndPoint)/root")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            guard let json = object as? [String: Any] else {
                return false
            }
            if let _ = json["id"] as? String {
                return true
            }
            else{
                print(json)
                return false
            }
        }
        catch {
            print(error)
        }
        return false
    }
    
    override func checkToken() async -> Bool {
        if await super.checkToken(), apiEndPoint != "" {
            return true
        }
        return false
    }
    
    func listFiles(itemId: String, nextLink: String) async -> [[String:Any]]? {
        let action = { [self] () async throws -> [[String:Any]]? in
            os_log("%{public}@", log: log, type: .debug, "listFiles(onedrive:\(storageName ?? ""))")

            let fields = "id,name,size,createdDateTime,lastModifiedDateTime,folder,file"
            
            let path = (itemId == "") ? "root" : "items/\(itemId)"
            let url: String
            if nextLink == "" {
                url = "\(self.apiEndPoint)/\(path)/children?select=\(fields)"
            }
            else {
                url = nextLink
            }
            var request: URLRequest = URLRequest(url: URL(string: url)!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            guard let json = object as? [String: Any] else {
                throw RetryError.Retry
            }
            if let e = json["error"] {
                print(e)
                throw RetryError.Retry
            }
            let nextLink = json["@odata.nextLink"] as? String ?? ""
            if nextLink != "" {
                if var files = await listFiles(itemId: itemId, nextLink: nextLink) {
                    if let newfiles = json["value"] as? [[String: Any]] {
                        files += newfiles
                    }
                    return files
                }
            }
            return json["value"] as? [[String: Any]]
        }
        do {
            if nextLink != "" {
                return try await action()
            }
            else {
                return try await callWithRetry(action: action)
            }
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
        guard let ctime = item["createdDateTime"] as? String else {
            return
        }
        guard let mtime = item["lastModifiedDateTime"] as? String else {
            return
        }
        let folder = item["folder"] as? [String: Any]
        let file = item["file"] as? [String: Any]
        let size = item["size"] as? Int64 ?? 0
        let hashstr = ""
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        let formatter2 = ISO8601DateFormatter()
        
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
            if let d1 = formatter.date(from: ctime) {
                newitem.cdate = d1
            }
            else if let d2 = formatter2.date(from: ctime) {
                newitem.cdate = d2
            }
            if let d3 = formatter.date(from: mtime) {
                newitem.mdate = d3
            }
            else if let d4 = formatter2.date(from: mtime) {
                newitem.mdate = d4
            }
            newitem.folder = folder != nil && file == nil
            newitem.size = size
            newitem.hashstr = hashstr
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
        if let items = await listFiles(itemId: fileId, nextLink: "") {
            for item in items {
                storeItem(item: item, parentFileId: fileId, parentPath: path, context: viewContext)
            }
            await viewContext.perform {
                try? viewContext.save()
            }
        }
    }
    
    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil) async throws -> Data? {
        if let cache = await CloudFactory.shared.cache.getCache(storage: storageName!, id: fileId, offset: start ?? 0, size: length ?? -1) {
            if let data = try? Data(contentsOf: cache) {
                os_log("%{public}@", log: log, type: .debug, "hit cache(OneDrive:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                return data
            }
        }
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "readFile(onedrive:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")

                var request: URLRequest = URLRequest(url: URL(string: "\(apiEndPoint)/items/\(fileId)")!)
                request.httpMethod = "GET"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    throw RetryError.Retry
                }
                if let e = json["error"] {
                    print(e)
                    throw RetryError.Retry
                }
                let downLink = json["@microsoft.graph.downloadUrl"] as? String ?? ""
                if downLink == "" {
                    throw RetryError.Retry
                }
                
                try await Task.sleep(for: .milliseconds(Int((Double.random(in: 0..<callWait)) * 1000)))
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
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "makeFolder(onedrive:\(storageName ?? "") \(parentId) \(newname)")

                let path = (parentId == "") ? "root" : "items/\(parentId)"
                let url = "\(self.apiEndPoint)/\(path)/children"
                
                var request: URLRequest = URLRequest(url: URL(string: url)!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                
                let jsondata: [String: Any] = [
                    "name": newname,
                    "folder": [String: Any](),
                    "@microsoft.graph.conflictBehavior": "fail"
                ]
                
                guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                    throw RetryError.Retry
                }
                request.httpBody = postData
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let id = json["id"] as? String else {
                    throw RetryError.Retry
                }
                let viewContext = CloudFactory.shared.data.viewContext
                let storage = storageName ?? ""
                await viewContext.perform {
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, storage)
                    if let result = try? viewContext.fetch(fetchRequest) {
                        for object in result {
                            viewContext.delete(object as! NSManagedObject)
                        }
                    }
                }
                storeItem(item: json, parentFileId: parentId, parentPath: parentPath, context: viewContext)
                await viewContext.perform {
                    try? viewContext.save()
                }
                return id
            })
        }
        catch {
            return nil
        }
    }
    
    override func deleteItem(fileId: String) async -> Bool {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "deleteItem(onedrive:\(storageName ?? "") \(fileId)")

                let url = "\(apiEndPoint)/items/\(fileId)"
                
                var request: URLRequest = URLRequest(url: URL(string: url)!)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                
                guard let (data, response) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    print(response)
                    throw RetryError.Retry
                }
                guard httpResponse.statusCode == 204 else {
                    print(String(data: data, encoding: .utf8) ?? "")
                    throw RetryError.Retry
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
            })
        }
        catch {
            return false
        }
    }
    
    func getFile(fileId: String, parentId: String? = nil, parentPath: String? = nil) async -> Bool {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "getFile(onedrive:\(storageName ?? ""))")

                let fields = "id,name,size,createdDateTime,lastModifiedDateTime,folder,file"
                
                let path = (fileId == "") ? "root" : "items/\(fileId)"
                let url = "\(apiEndPoint)/\(path)?select=\(fields)"
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
                if let e = json["error"] {
                    print(e)
                    throw RetryError.Retry
                }
                let viewContext = CloudFactory.shared.data.viewContext
                storeItem(item: json, parentFileId: parentId, parentPath: parentPath, context: viewContext)
                await viewContext.perform {
                    try? viewContext.save()
                }
                return true
            })
        }
        catch {
            return false
        }
    }
    
    func getRootId() async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "getRootId(onedrive:\(storageName ?? ""))")

                let fields = "id"
                
                let url = "\(apiEndPoint)/root?select=\(fields)"
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
                if let e = json["error"] {
                    print(e)
                    throw RetryError.Retry
                }
                if let id = json["id"] as? String {
                    return id
                }
                throw RetryError.Retry
            })
        }
        catch {
            return nil
        }
    }
    
    func updateItem(fileId: String, json: [String: Any], parentId: String? = nil, parentPath: String? = nil) async -> String? {
        do {
            let newid = try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "updateItem(onedrive:\(storageName ?? "") \(fileId)")

                let url = "\(apiEndPoint)/items/\(fileId)"
                
                var request: URLRequest = URLRequest(url: URL(string: url)!)
                request.httpMethod = "PATCH"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                
                guard let postData = try? JSONSerialization.data(withJSONObject: json) else {
                    throw RetryError.Retry
                }
                request.httpBody = postData
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let id = json["id"] as? String else {
                    print(json)
                    throw RetryError.Retry
                }
                if await getFile(fileId: id, parentId: parentId, parentPath: parentPath) {
                    return id
                }
                throw RetryError.Retry
            })
            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
            return newid
        }
        catch {
            return nil
        }
    }
    
    override func renameItem(fileId: String, newname: String) async -> String? {
        let json: [String: Any] = ["name": newname]
        return await updateItem(fileId: fileId, json: json)
    }
    
    override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        if fromParentId == toParentId {
            return nil
        }
        if toParentId == "" {
            guard let rootId = await getRootId() else {
                return nil
            }
            let json: [String: Any] = ["parentReference": ["id": rootId]]
            return await updateItem(fileId: fileId, json: json, parentId: toParentId)
        }
        else {
            var toParentPath = ""
            let viewContext = CloudFactory.shared.data.viewContext
            let storage = storageName ?? ""
            await viewContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", toParentId, storage)
                if let result = try? viewContext.fetch(fetchRequest) {
                    if let items = result as? [RemoteData] {
                        toParentPath = items.first?.path ?? ""
                    }
                }
            }
            let json: [String: Any] = ["parentReference": ["id": toParentId]]
            return await updateItem(fileId: fileId, json: json, parentId: toParentId, parentPath: toParentPath)
        }
    }
    
    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await NetworkRemoteItem(path: path)
    }

    override func uploadFile(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        defer {
            try? FileManager.default.removeItem(at: target)
        }
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "uploadFile(onedrive:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")

                var parentPath = "\(storageName ?? ""):/"
                if parentId != "" {
                    parentPath = await getParentPath(parentId: parentId) ?? parentPath
                }
                let handle = try FileHandle(forReadingFrom: target)
                defer {
                    try? handle.close()
                }

                let attr = try FileManager.default.attributesOfItem(atPath: target.path(percentEncoded: false))
                let fileSize = attr[.size] as! UInt64
                try await progress?(0, Int64(fileSize))

                let path = (parentId == "") ? "root" : "items/\(parentId)"
                var allowedCharacterSet = CharacterSet.alphanumerics
                allowedCharacterSet.insert(charactersIn: "-._~")
                let encoded_name = uploadname.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)
                let url = "\(apiEndPoint)/\(path):/\(encoded_name!):/createUploadSession"
                var request: URLRequest = URLRequest(url: URL(string: url)!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                let json: [String: Any] = [
                    "@microsoft.graph.conflictBehavior": "rename"]
                let postData = try? JSONSerialization.data(withJSONObject: json)
                request.httpBody = postData
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let uploadUrl = object["uploadUrl"] as? String else {
                    throw RetryError.Retry
                }

                await uploadProgressManeger.setCallback(url: URL(string: uploadUrl)!, total: Int64(fileSize), callback: progress)
                defer {
                    Task { await uploadProgressManeger.removeCallback(url: URL(string: uploadUrl)!) }
                }

                var offset = 0
                var eof = false
                while !eof  {
                    guard let srcData = try handle.read(upToCount: 100*320*1024) else {
                        throw RetryError.Retry
                    }
                    if srcData.count < 100*320*1024 {
                        eof = true
                    }
                    
                    var request2: URLRequest = URLRequest(url: URL(string: uploadUrl)!)
                    request2.httpMethod = "PUT"
                    request2.setValue("bytes \(offset)-\(offset+srcData.count-1)/\(fileSize)", forHTTPHeaderField: "Content-Range")
                    offset += srcData.count
                    
                    guard let (data2, _) = try? await URLSession.shared.upload(for: request2, from: srcData, delegate: self) else {
                        throw RetryError.Retry
                    }
                    await uploadProgressManeger.setOffset(url: URL(string: uploadUrl)!, offset: Int64(offset))
                    guard let object = try? JSONSerialization.jsonObject(with: data2, options: []) as? [String: Any] else {
                        throw RetryError.Retry
                    }
                    if let e = object["error"] as? [String: Any] {
                        print(e)
                        
                        var request3 = URLRequest(url: URL(string: uploadUrl)!)
                        request3.httpMethod = "GET"
                        
                        guard let (data3, _) = try? await URLSession.shared.data(for: request3) else {
                            throw RetryError.Retry
                        }
                        guard let object = try? JSONSerialization.jsonObject(with: data3, options: []) as? [String: Any] else {
                            throw RetryError.Retry
                        }
                        guard let nextExpectedRanges = object["nextExpectedRanges"] as? [String] else {
                            throw RetryError.Retry
                        }
                        let reqOffset = Int(nextExpectedRanges.first?.replacingOccurrences(of: #"(\d+)-\d+"#, with: "$1", options: .regularExpression) ?? "0") ?? 0
                        
                        print(reqOffset)
                        
                        if offset != reqOffset {
                            try handle.seek(toOffset: UInt64(reqOffset))
                            offset = reqOffset
                        }
                        await uploadProgressManeger.setOffset(url: URL(string: uploadUrl)!, offset: Int64(offset))
                        eof = false
                        continue
                    }
                    if let nextExpectedRanges = object["nextExpectedRanges"] as? [String] {
                        print(nextExpectedRanges)
                        continue
                    }
                    else {
                        guard let id = object["id"] as? String else {
                            throw RetryError.Retry
                        }
                        print(id)
                        let viewContext = CloudFactory.shared.data.viewContext
                        storeItem(item: object, parentFileId: parentId, parentPath: parentPath, context: viewContext)
                        await viewContext.perform {
                            try? viewContext.save()
                            print("done")
                        }
                        try await progress?(Int64(fileSize), Int64(fileSize))
                        return id
                    }
                }
                throw RetryError.Retry
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

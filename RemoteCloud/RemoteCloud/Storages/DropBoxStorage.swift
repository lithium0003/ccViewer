//
//  DropBoxStorage.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/03/20.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import AuthenticationServices
import os.log
import CoreData
import CryptoKit

public class DropBoxStorage: NetworkStorage, URLSessionDataDelegate {
    public override func getStorageType() -> CloudStorages {
        return .DropBox
    }

    let uploadSemaphore = Semaphore(value: 5)

    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .DropBox)
        storageName = name
    }
    
    var code_verifier = ""
    let clientid = SecretItems.Dropbox.client_id
    let callbackUrlScheme = SecretItems.Dropbox.callbackUrlScheme
    
    override var authURL: URL {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        for _ in 0..<64 {
            code_verifier += String(chars.randomElement()!)
        }
        let hash = SHA256.hash(data: code_verifier.data(using: .utf8)!)
        let base64 = Data(hash.map({ $0 })).base64EncodedString()
        let code_challenge = base64.replacing("+", with: "-").replacing("/", with: "_").replacing("=", with: "")
        let url = "https://www.dropbox.com/oauth2/authorize?client_id=\(clientid)&response_type=code&token_access_type=offline&redirect_uri=\(callbackUrlScheme)://dropbox_callback&code_challenge=\(code_challenge)&code_challenge_method=S256"
        return URL(string: url)!
    }
    override var authCallback: ASWebAuthenticationSession.Callback {
        ASWebAuthenticationSession.Callback.customScheme(SecretItems.Dropbox.callbackUrlScheme)
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
        os_log("%{public}@", log: log, type: .debug, "getToken(dropbox:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://api.dropboxapi.com/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let post = "code=\(oauthToken)&grant_type=authorization_code&redirect_uri=\(callbackUrlScheme)://dropbox_callback&code_verifier=\(code_verifier)&client_id=\(clientid)"
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
        os_log("%{public}@", log: log, type: .debug, "refreshToken(dropbox:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://api.dropboxapi.com/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let post = "refresh_token=\(await getRefreshToken())&client_id=\(clientid)&grant_type=refresh_token"
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
    
    override func revokeToken(token: String) async -> Bool {
        os_log("%{public}@", log: log, type: .debug, "revokeToken(dropbox:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/auth/token/revoke")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let response = response as? HTTPURLResponse {
                if response.statusCode == 200 {
                    os_log("%{public}@", log: self.log, type: .info, "revokeToken(dropbox:\(storageName ?? "")) success")
                    return true
                }
            }
        }
        catch {
            print(error)
        }
        return false
    }
    
    class func namePatch(_ name: String) -> String {
        if !name.contains(where: { $0.unicodeScalars.first?.value ?? 0 < 0x20 }) {
            return name
        }
        return String(name.map{
            if let value = $0.unicodeScalars.first?.value {
                if value < 0x20 {
                    return Character(UnicodeScalar(0x2400 | value)!)
                }
            }
            return $0
        })
    }

    func storeItem(item: [String: Any], parentFileId: String? = nil, parentPath: String? = nil, context: NSManagedObjectContext) {
        let formatter = ISO8601DateFormatter()
        
        guard let id = item["id"] as? String else {
            return
        }
        if id == parentFileId {
            return
        }
        guard let name = item["name"] as? String else {
            return
        }
        let tag = item[".tag"] as? String ?? ""
        guard let path_display = item["path_display"] as? String else {
            return
        }
        let ctime = item["server_modified"] as? String
        let mtime = item["client_modified"] as? String
        let size = item["size"] as? Int64 ?? 0
        let hashstr = item["content_hash"] as? String ?? ""
        
        context.performAndWait {
            var prevParent: String?
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
            if let result = try? context.fetch(fetchRequest) {
                for object in result {
                    if let item = object as? RemoteData {
                        prevParent = item.parent
                    }
                    context.delete(object as! NSManagedObject)
                }
            }
            
            
            let newitem = RemoteData(context: context)
            newitem.storage = self.storageName
            newitem.id = id
            newitem.name = DropBoxStorage.namePatch(name)
            let comp = name.components(separatedBy: ".")
            if comp.count >= 1 {
                newitem.ext = comp.last!.lowercased()
            }
            newitem.cdate = formatter.date(from: ctime ?? "")
            newitem.mdate = formatter.date(from: mtime ?? "")
            newitem.folder = tag == "folder"
            newitem.size = size
            newitem.hashstr = hashstr
            newitem.parent = (parentFileId == nil) ? prevParent : parentFileId
            newitem.path = "\(self.storageName ?? ""):\(path_display)"
        }
    }
    
    func listFolder(path: String, cursor: String = "") async -> [[String:Any]]? {
        let action = { [self] () async throws -> [[String:Any]]? in
            os_log("%{public}@", log: log, type: .debug, "listFolder(dropbox:\(storageName ?? ""))")

            let url: String
            if cursor == "" {
                url = "https://api.dropboxapi.com/2/files/list_folder"
            }
            else {
                url = "https://api.dropboxapi.com/2/files/list_folder/continue"
            }

            var request: URLRequest = URLRequest(url: URL(string: url)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let jsondata: [String: Any]
            if cursor == "" {
                jsondata = ["path": path,
                            "limit": 2000]
            }
            else {
                jsondata = ["cursor": cursor,
                            "limit": 2000]
            }
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
            if let e = json["error"] {
                print(e)
                throw RetryError.Retry
            }
            let hasMore = json["has_more"] as? Bool ?? false
            let cursor = json["cursor"] as? String ?? ""
            if !hasMore {
                return json["entries"] as? [[String: Any]]
            }
            let files = await listFolder(path: "", cursor: cursor)
            if var files = files {
                if let newfiles = json["entries"] as? [[String: Any]] {
                    files += newfiles
                }
                return files
            }
            else {
                return json["entries"] as? [[String: Any]]
            }
        }
        do {
            if cursor == "" {
                return try await callWithRetry(action: action)
            }
            else {
                return try await action()
            }
        }
        catch {
            return nil
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
        let result = await listFolder(path: fileId)
        if let items = result {
            for item in items {
                storeItem(item: item, parentFileId: fileId, context: viewContext)
            }
            await viewContext.perform {
                try? viewContext.save()
            }
        }
    }
    
    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil) async throws -> Data? {
        if let cache = await CloudFactory.shared.cache.getCache(storage: storageName!, id: fileId, offset: start ?? 0, size: length ?? -1) {
            if let data = try? Data(contentsOf: cache) {
                os_log("%{public}@", log: log, type: .debug, "hit cache(dropbox:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                return data
            }
        }
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "readFile(dropbox:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                var request: URLRequest = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                
                let jsondata: [String: Any] = ["path": fileId]
                guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                    throw RetryError.Retry
                }
                request.setValue(String(bytes: postData, encoding: .utf8) ?? "", forHTTPHeaderField: "Dropbox-API-Arg")
                let s = start ?? 0
                if length == nil {
                    request.setValue("bytes=\(s)-", forHTTPHeaderField: "Range")
                }
                else {
                    request.setValue("bytes=\(s)-\(s+length!-1)", forHTTPHeaderField: "Range")
                }
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                if let length, data.count != length {
                    throw RetryError.Retry
                }
                await CloudFactory.shared.cache.saveCache(storage: storageName!, id: fileId, offset: start ?? 0, data: data)
                return data
            })
        }
        catch {
            return nil
        }
    }
    
    func getMetadata(fileId: String, parentId: String? = nil, parentPath: String? = nil, callCount: Int = 0) async -> Bool {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "getMetadata(dropbox:\(storageName ?? "") \(fileId)")
                var request: URLRequest = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/get_metadata")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let jsondata: [String: Any] = [
                    "path": fileId,
                    "include_media_info": false,
                    "include_deleted": false,
                    "include_has_explicit_shared_members": false]
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
                if let e = json["error"] {
                    print(e)
                    throw RetryError.Retry
                }
                let viewContext = CloudFactory.shared.data.viewContext
                storeItem(item: json, parentFileId: parentId, context: viewContext)
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

    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                let prefix = "\(storageName ?? ""):"
                let fixpath = String(parentPath.dropFirst(prefix.count))
                os_log("%{public}@", log: log, type: .debug, "makeFolder(dropbox:\(storageName ?? "") \(parentId) \(newname)")

                let url = "https://api.dropboxapi.com/2/files/create_folder_v2"
                
                var request: URLRequest = URLRequest(url: URL(string: url)!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let jsondata: [String: Any] = ["path": "\(fixpath)/\(newname)", "autorename": false]
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
                guard let metadata = json["metadata"] as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let id = metadata["id"] as? String else {
                    throw RetryError.Retry
                }
                _ = await getMetadata(fileId: id, parentId: parentId, parentPath: parentPath)
                return id
            })
        }
        catch {
            return nil
        }
    }

    override func deleteItem(fileId: String) async -> Bool {
        do {
            let ret = try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "deleteItem(dropbox:\(storageName ?? "") \(fileId)")

                let url = "https://api.dropboxapi.com/2/files/delete_v2"
                
                var request: URLRequest = URLRequest(url: URL(string: url)!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let jsondata: [String: Any] = ["path": "\(fileId)"]
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
                guard let metadata = json["metadata"] as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let id = metadata["id"] as? String else {
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
                deleteChildRecursive(parent: id, context: viewContext)
                await viewContext.perform {
                    try? viewContext.save()
                }
                return true
            })
            if ret {
                await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
            }
            return ret
        }
        catch {
            return false
        }
    }

    override func renameItem(fileId: String, newname: String) async -> String? {
        var parentId: String? = nil
        let viewContext = CloudFactory.shared.data.viewContext
        let storage = storageName ?? ""
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest) as? [RemoteData] {
                if let item = result.first {
                    parentId = item.parent
                }
            }
        }
        if let parentId = parentId {
            let newid = await renameItem(fileId: fileId, parentId: parentId, newname: newname)
            if newid != nil {
                await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
            }
            return newid
        }
        else {
            return nil
        }
    }
    
    func renameItem(fileId: String, parentId: String, newname: String) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "renameItem(dropbox:\(storageName ?? "") \(fileId) \(newname)")

                let url = "https://api.dropboxapi.com/2/files/move_v2"
                
                var request: URLRequest = URLRequest(url: URL(string: url)!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let jsondata: [String: Any] = [
                    "from_path": fileId,
                    "to_path": "\(parentId)/\(newname)",
                    "allow_shared_folder": false,
                    "autorename": false,
                    "allow_ownership_transfer": false]
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
                guard let metadata = json["metadata"] as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let id = metadata["id"] as? String else {
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
                storeItem(item: metadata, parentFileId: parentId, context: viewContext)
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

    override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        if fromParentId == toParentId {
            return nil
        }
        var orgname: String? = nil
        
        let viewContext = CloudFactory.shared.data.viewContext
        let storage = storageName ?? ""
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest) as? [RemoteData] {
                if let item = result.first {
                    orgname = item.name
                }
            }
        }
        if let orgname = orgname {
            let newid = await moveItem(fileId: fileId, orgname: orgname, toParentId: toParentId)
            if newid != nil {
                await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
            }
            return newid
        }
        else {
            return nil
        }
    }
    
    func moveItem(fileId: String, orgname: String, toParentId: String) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "moveItem(dropbox:\(storageName ?? "") \(fileId) ->\(toParentId)")

                let url = "https://api.dropboxapi.com/2/files/move_v2"
                
                var request: URLRequest = URLRequest(url: URL(string: url)!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let jsondata: [String: Any] = [
                    "from_path": fileId,
                    "to_path": "\(toParentId)/\(orgname)",
                    "allow_shared_folder": false,
                    "autorename": false,
                    "allow_ownership_transfer": false]
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
                guard let metadata = json["metadata"] as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let id = metadata["id"] as? String else {
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
                storeItem(item: metadata, parentFileId: toParentId, context: viewContext)
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
        os_log("%{public}@", log: log, type: .debug, "uploadFile(dropbox:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")
        
        var parentPath = ""
        let viewContext = CloudFactory.shared.data.viewContext
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, self.storageName ?? "")
            if let result = try? viewContext.fetch(fetchRequest) {
                if let items = result as? [RemoteData] {
                    parentPath = items.first?.path ?? ""
                }
            }
        }
        let p = "\(self.storageName ?? ""):"
        if parentPath.hasPrefix(p) {
            parentPath = String(parentPath.dropFirst(p.count))
        }
        let attr = try FileManager.default.attributesOfItem(atPath: target.path)
        let fileSize = attr[.size] as! UInt64
        try await progress?(0, Int64(fileSize))

        if fileSize < 150*1000*1000 {
            return try await uploadShortFile(parentId: parentId, parentPath: parentPath, uploadname: uploadname, target: target, progress: progress)
        }
        else {
            return try await uploadLongFile(parentId: parentId, parentPath: parentPath, uploadname: uploadname, target: target, progress: progress)
        }
    }
    
    func uploadShortFile(parentId: String, parentPath: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                let attr = try FileManager.default.attributesOfItem(atPath: target.path)
                let fileSize = attr[.size] as! UInt64

                let url = "https://content.dropboxapi.com/2/files/upload"

                var request: URLRequest = URLRequest(url: URL(string: url)!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                
                let jsondata = "{\"path\":\"\(parentId)/\(self.convertUnicode(uploadname))\",\"mode\":\"add\",\"autorename\":true,\"mute\":false,\"strict_conflict\":false}";
                
                request.setValue(jsondata, forHTTPHeaderField: "Dropbox-API-Arg")
                guard let postData = try? Data(contentsOf: target) else {
                    throw RetryError.Retry
                }
                request.httpBody = postData
                
                await uploadProgressManeger.setCallback(url: request.url!, total: Int64(fileSize), callback: progress)
                defer {
                    Task { await uploadProgressManeger.removeCallback(url: request.url!) }
                }
                
                guard let (data, _) = try? await URLSession.shared.data(for: request, delegate: self) else {
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
                storeItem(item: json, parentFileId: parentId, context: viewContext)
                await viewContext.perform {
                    try? viewContext.save()
                    print("done")
                }
                try await progress?(Int64(fileSize), Int64(fileSize))
                return id
            }, semaphore: uploadSemaphore)
        }
        catch {
            return nil
        }
    }
    
    func uploadLongFile(parentId: String, parentPath: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                let attr = try FileManager.default.attributesOfItem(atPath: target.path(percentEncoded: false))
                let fileSize = attr[.size] as! UInt64

                let handle = try FileHandle(forReadingFrom: target)
                defer {
                    try? handle.close()
                }

                var session_id = ""
                var offset = 0
                var eof = false
                while !eof {
                    guard let srcData = try handle.read(upToCount: 32*1024*1024) else {
                        throw RetryError.Retry
                    }
                    
                    var request: URLRequest
                    if session_id == "" {
                        let url = "https://content.dropboxapi.com/2/files/upload_session/start"

                        request = URLRequest(url: URL(string: url)!)
                        request.httpMethod = "POST"
                        request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                        
                        let jsondata: [String: Any] = [
                            "close": false]
                        guard let argData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                            throw RetryError.Retry
                        }
                        request.setValue(String(data: argData, encoding: .utf8) ?? "", forHTTPHeaderField: "Dropbox-API-Arg")
                    }
                    else if srcData.count == 32*1024*1024 {
                        let url = "https://content.dropboxapi.com/2/files/upload_session/append_v2"

                        request = URLRequest(url: URL(string: url)!)
                        request.httpMethod = "POST"
                        request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                        
                        let jsondata: [String: Any] = [
                            "cursor": [
                                "session_id": session_id,
                                "offset": offset
                            ],
                            "close": false]
                        guard let argData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                            throw RetryError.Retry
                        }
                        request.setValue(String(data: argData, encoding: .utf8) ?? "", forHTTPHeaderField: "Dropbox-API-Arg")
                    }
                    else {
                        eof = true
                        let url = "https://content.dropboxapi.com/2/files/upload_session/finish"

                        request = URLRequest(url: URL(string: url)!)
                        request.httpMethod = "POST"
                        request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                        
                        let jsondata = "{\"cursor\":{\"session_id\":\"\(session_id)\",\"offset\":\(offset)},\"commit\": {\"path\":\"\(parentId)/\(self.convertUnicode(uploadname))\",\"mode\":\"add\",\"autorename\":true,\"mute\":false,\"strict_conflict\":false}}";
                        request.setValue(jsondata, forHTTPHeaderField: "Dropbox-API-Arg")
                    }
                    await uploadProgressManeger.setCallback(url: request.url!, total: Int64(fileSize), callback: progress)
                    defer {
                        Task { await uploadProgressManeger.removeCallback(url: request.url!) }
                    }
                    await uploadProgressManeger.setOffset(url: request.url!, offset: Int64(offset))
                    offset += srcData.count
                    
                    guard let (data, _) = try? await URLSession.shared.upload(for: request, from: srcData, delegate: self) else {
                        throw RetryError.Retry
                    }
                    if let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if let e = object["error"] as? [String: Any] {
                            print(e)
                            guard let correct_offset = e["correct_offset"] as? Int else {
                                throw RetryError.Retry
                            }
                            print(correct_offset)
                            if correct_offset != offset {
                                try handle.seek(toOffset: UInt64(correct_offset))
                                offset = correct_offset
                            }
                        }
                        if let s = object["session_id"] as? String {
                            session_id = s
                        }
                        if eof {
                            guard let id = object["id"] as? String else {
                                print(object)
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
                            storeItem(item: object, parentFileId: parentId, context: viewContext)
                            await viewContext.perform {
                                try? viewContext.save()
                                print("done")
                            }
                            try await progress?(Int64(fileSize), Int64(fileSize))
                            return id
                        }
                    }
                }
                throw RetryError.Retry
            }, semaphore: uploadSemaphore, maxCall: 3)
        }
        catch {
            return nil
        }
    }
    
    func convertUnicode(_ str: String) -> String {
        return str.flatMap({ $0.unicodeScalars }).map({ $0.escaped(asASCII: true).replacingOccurrences(of: #"\\u\{([0-9a-fA-F]+)\}"#, with: #"\\u$1"#, options: .regularExpression) }).joined()
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

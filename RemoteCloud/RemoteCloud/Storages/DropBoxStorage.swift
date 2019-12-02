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

public class DropBoxStorage: NetworkStorage, URLSessionTaskDelegate, URLSessionDataDelegate {
    public override func getStorageType() -> CloudStorages {
        return .DropBox
    }
    
    var cache_accountId = ""
    var accountId: String {
        if let name = storageName {
            if let id = getKeyChain(key: "\(name)_accountId") {
                if cacheTokenDate == tokenDate {
                    cache_accountId = id
                }
                else {
                    if setKeyChain(key: "\(name)_accountId", value: cache_accountId) {
                        tokenDate = cacheTokenDate
                    }
                }
            }
            return cache_accountId
        }
        else {
            return ""
        }
    }

    var webAuthSession: ASWebAuthenticationSession?
    let uploadSemaphore = DispatchSemaphore(value: 5)

    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .DropBox)
        storageName = name
    }
    
    override func authorize(onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "authorize(dropbox:\(storageName ?? ""))")
        
        let client = SecretItems.Dropbox.client_id
        let callbackUrlScheme = SecretItems.Dropbox.callbackUrlScheme
        let url = "https://www.dropbox.com/oauth2/authorize?client_id=\(client)&response_type=token&redirect_uri=\(callbackUrlScheme)://dropbox_callback"
        let authURL = URL(string: url);
        
        self.webAuthSession = ASWebAuthenticationSession(url: authURL!, callbackURLScheme: callbackUrlScheme, completionHandler: { (callBack:URL?, error:Error?) in
            
            // handle auth response
            guard error == nil, let successURL = callBack else {
                onFinish?(false)
                return
            }
            
            guard let access_token = NSURLComponents(string: (successURL.absoluteString.replacingOccurrences(of: "#", with: "?")))?.queryItems?.filter({$0.name == "access_token"}).first?.value else {
                onFinish?(false)
                return
            }
            guard let account_id = NSURLComponents(string: (successURL.absoluteString.replacingOccurrences(of: "#", with: "?")))?.queryItems?.filter({$0.name == "account_id"}).first?.value else {
                onFinish?(false)
                return
            }

            self.saveToken(accessToken: access_token, accountId: account_id)
            onFinish?(true)
        })
        if #available(iOS 13.0, *) {
            self.webAuthSession?.presentationContextProvider = self
        }

        self.webAuthSession?.start()
    }

    override func checkToken(onFinish: ((Bool) -> Void)?) -> Void {
        if accessToken != "" {
            onFinish?(true)
        }
        else {
            onFinish?(false)
        }
    }
    
    func saveToken(accessToken: String, accountId: String) -> Void {
        if let name = storageName {
            guard accessToken != "" && accountId != "" else {
                return
            }
            os_log("%{public}@", log: log, type: .info, "saveToken")
            cacheTokenDate = Date()
            cache_accessToken = accessToken
            if setKeyChain(key: "\(name)_accessToken", value: accessToken) && setKeyChain(key: "\(name)_accountId", value: accountId) {
                tokenDate = Date()
            }
        }
    }
    
    public override func logout() {
        if let name = storageName {
            let _ = delKeyChain(key: "\(name)_accountId")
        }
        super.logout()
    }

    override func revokeToken(token: String, onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "revokeToken(dropbox:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/auth/token/revoke")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print(error.localizedDescription)
                onFinish?(false)
                return
            }
            if let response = response as? HTTPURLResponse {
                if response.statusCode == 200 {
                    os_log("%{public}@", log: self.log, type: .info, "revokeToken(dropbox:\(self.storageName ?? "")) success")
                    onFinish?(true)
                }
                else {
                    onFinish?(false)
                }
            }
            else {
                onFinish?(false)
            }
        }
        task.resume()
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
        
        context.perform {
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
            newitem.name = name
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
    
    func listFolder(path: String, cursor: String, callCount: Int = 0, onFinish: (([[String:Any]]?)->Void)?) {
        if lastCall.timeIntervalSinceNow > -self.callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                self.listFolder(path: path, cursor: cursor, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "listFolder(dropbox:\(storageName ?? ""))")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            let url: String
            if cursor == "" {
                url = "https://api.dropboxapi.com/2/files/list_folder"
            }
            else {
                url = "https://api.dropboxapi.com/2/files/list_folder/continue"
            }
            
            var request: URLRequest = URLRequest(url: URL(string: url)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
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
                onFinish?(nil)
                return
            }
            request.httpBody = postData

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                self.callSemaphore.signal()
                do {
                    guard let data = data else {
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
                        onFinish?(json["entries"] as? [[String: Any]])
                    }
                    else {
                        self.listFolder(path: "", cursor: cursor) { files in
                            if var files = files {
                                if let newfiles = json["entries"] as? [[String: Any]] {
                                    files += newfiles
                                }
                                onFinish?(files)
                            }
                            else {
                                onFinish?(json["entries"] as? [[String: Any]])
                            }
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                            self.listFolder(path: path, cursor: cursor, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    onFinish?(nil)
                } catch let e {
                    print(e)
                    onFinish?(nil)
                    return
                }
            }
            task.resume()
        }
    }

    override func ListChildren(fileId: String, path: String, onFinish: (() -> Void)?) {
        listFolder(path: fileId, cursor: "") { result in
            if let items = result {
                let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
                
                for item in items {
                    self.storeItem(item: item, parentFileId: fileId, context: backgroundContext)
                }
                backgroundContext.perform {
                    try? backgroundContext.save()
                    DispatchQueue.global().async {
                        onFinish?()
                    }
                }
            }
            else {
                onFinish?()
            }
        }
    }

    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil, callCount: Int = 0, onFinish: ((Data?) -> Void)?) {
        
        if let cache = CloudFactory.shared.cache.getCache(storage: storageName!, id: fileId, offset: start ?? 0, size: length ?? -1) {
            if let data = try? Data(contentsOf: cache) {
                os_log("%{public}@", log: log, type: .debug, "hit cache(dropbox:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                onFinish?(data)
                return
            }
        }

        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+callWait+Double.random(in: 0..<0.5)) {
                self.readFile(fileId: fileId, start: start, length: length, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        lastCall = Date()
        os_log("%{public}@", log: log, type: .debug, "readFile(dropbox:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
            var request: URLRequest = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            
            let jsondata: [String: Any] = ["path": fileId]
            guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                onFinish?(nil)
                return
            }
            request.setValue(String(bytes: postData, encoding: .utf8) ?? "", forHTTPHeaderField: "Dropbox-API-Arg")
            if start != nil || length != nil {
                let s = start ?? 0
                if length == nil {
                    request.setValue("bytes=\(s)-", forHTTPHeaderField: "Range")
                }
                else {
                    request.setValue("bytes=\(s)-\(s+length!-1)", forHTTPHeaderField: "Range")
                }
            }

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                self.callSemaphore.signal()
                var waittime = self.callWait
                if let error = error {
                    print(error)
                    if (error as NSError).code == -1009 {
                        waittime += 30
                    }
                }
                if let l = length {
                    if data?.count ?? 0 != l {
                        if callCount > 50 {
                            onFinish?(data)
                            return
                        }
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait+Double.random(in: 0..<waittime)) {
                            self.readFile(fileId: fileId, start: start, length: length, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                }
                onFinish?(data)
            }
            task.resume()
        }
    }
    
    func getMetadata(fileId: String, parentId: String? = nil, parentPath: String? = nil, callCount: Int = 0, onFinish: ((Bool)->Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(false)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+callWait) {
                self.getMetadata(fileId: fileId, parentId: parentId, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "getMetadata(dropbox:\(storageName ?? "") \(fileId)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(false)
                return
            }
            
            var request: URLRequest = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/get_metadata")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let jsondata: [String: Any] = [
                "path": fileId,
                "include_media_info": false,
                "include_deleted": false,
                "include_has_explicit_shared_members": false]
            guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                self.callSemaphore.signal()
                onFinish?(false)
                return
            }
            request.httpBody = postData

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                self.callSemaphore.signal()
                do {
                    guard let data = data else {
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
                    let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
                    self.storeItem(item: json, parentFileId: parentId, context: backgroundContext)
                    backgroundContext.perform {
                        try? backgroundContext.save()
                        DispatchQueue.global().async {
                            onFinish?(true)
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                            self.getMetadata(fileId: fileId, parentId: parentId, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    onFinish?(false)
                }
                catch let e {
                    print(e)
                    onFinish?(false)
                }
            }
            task.resume()
        }
    }

    public override func makeFolder(parentId: String, parentPath: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+callWait) {
                self.makeFolder(parentId: parentId, parentPath: parentPath, newname: newname, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        let prefix = "\(self.storageName ?? ""):"
        let fixpath = String(parentPath.dropFirst(prefix.count))
        os_log("%{public}@", log: log, type: .debug, "makeFolder(dropbox:\(storageName ?? "") \(parentId) \(newname)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            let url = "https://api.dropboxapi.com/2/files/create_folder_v2"
            
            var request: URLRequest = URLRequest(url: URL(string: url)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let jsondata: [String: Any] = ["path": "\(fixpath)/\(newname)", "autorename": false]
            guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            request.httpBody = postData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                self.callSemaphore.signal()
                do {
                    if let error = error {
                        print(error)
                        throw RetryError.Failed
                    }
                    guard let data = data else {
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
                    DispatchQueue.global().async {
                        self.getMetadata(fileId: id, parentId: parentId, parentPath: parentPath) { success in
                            if success {
                                onFinish?(id)
                            }
                            else {
                                onFinish?(nil)
                            }
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                            self.makeFolder(parentId: parentId, parentPath: parentPath, newname: newname, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    onFinish?(nil)
                }
                catch let e {
                    print(e)
                    onFinish?(nil)
                }
            }
            task.resume()
        }
    }

    override func deleteItem(fileId: String, callCount: Int = 0, onFinish: ((Bool) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(false)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+callWait) {
                self.deleteItem(fileId: fileId, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "deleteItem(dropbox:\(storageName ?? "") \(fileId)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(false)
                return
            }
            let url = "https://api.dropboxapi.com/2/files/delete_v2"
            
            var request: URLRequest = URLRequest(url: URL(string: url)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let jsondata: [String: Any] = ["path": "\(fileId)"]
            guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                self.callSemaphore.signal()
                onFinish?(false)
                return
            }
            request.httpBody = postData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                self.callSemaphore.signal()
                do {
                    if let error = error {
                        print(error)
                        throw RetryError.Failed
                    }
                    guard let data = data else {
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
                    let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
                    backgroundContext.perform {
                        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
                        if let result = try? backgroundContext.fetch(fetchRequest) {
                            for object in result {
                                backgroundContext.delete(object as! NSManagedObject)
                            }
                        }
                    }
                    self.deleteChildRecursive(parent: id, context: backgroundContext)
                    backgroundContext.perform {
                        try? backgroundContext.save()
                        DispatchQueue.global().async {
                            onFinish?(true)
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                            self.deleteItem(fileId: fileId, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    onFinish?(false)
                }
                catch let e {
                    print(e)
                    onFinish?(false)
                }
            }
            task.resume()
        }
    }

    override func renameItem(fileId: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        
        var parentId: String? = nil
        if Thread.isMainThread {
            let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
            if let result = try? viewContext.fetch(fetchRequest) as? [RemoteData] {
                if let item = result.first {
                    parentId = item.parent
                }
            }
        }
        else {
            DispatchQueue.main.sync {
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                if let result = try? viewContext.fetch(fetchRequest) as? [RemoteData] {
                    if let item = result.first {
                        parentId = item.parent
                    }
                }
            }
        }
        DispatchQueue.global().async {
            if let parentId = parentId {
                self.renameItem(fileId: fileId, parentId: parentId, newname: newname, onFinish: onFinish)
            }
            else {
                onFinish?(nil)
            }
        }
    }

    func renameItem(fileId: String, parentId: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+callWait) {
                self.renameItem(fileId: fileId, parentId: parentId, newname: newname, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "renameItem(dropbox:\(storageName ?? "") \(fileId) \(newname)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            let url = "https://api.dropboxapi.com/2/files/move_v2"
            
            var request: URLRequest = URLRequest(url: URL(string: url)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let jsondata: [String: Any] = [
                "from_path": fileId,
                "to_path": "\(parentId)/\(newname)",
                "allow_shared_folder": false,
                "autorename": false,
                "allow_ownership_transfer": false]
            guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            request.httpBody = postData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                self.callSemaphore.signal()
                do {
                    if let error = error {
                        print(error)
                        throw RetryError.Failed
                    }
                    guard let data = data else {
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
                    let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
                    backgroundContext.perform {
                        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                        if let result = try? backgroundContext.fetch(fetchRequest) {
                            for object in result {
                                backgroundContext.delete(object as! NSManagedObject)
                            }
                        }
                    }
                    self.storeItem(item: metadata, parentFileId: parentId, context: backgroundContext)
                    backgroundContext.perform {
                        try? backgroundContext.save()
                        DispatchQueue.global().async {
                            onFinish?(id)
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                            self.renameItem(fileId: fileId, parentId: parentId, newname: newname, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    onFinish?(nil)
                }
                catch let e {
                    print(e)
                    onFinish?(nil)
                }
            }
            task.resume()
        }
    }

    override func moveItem(fileId: String, fromParentId: String, toParentId: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if fromParentId == toParentId {
            onFinish?(nil)
            return
        }
        var orgname: String? = nil
        
        if Thread.isMainThread {
            let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
            if let result = try? viewContext.fetch(fetchRequest) as? [RemoteData] {
                if let item = result.first {
                    orgname = item.name
                }
            }
        }
        else {
            DispatchQueue.main.sync {
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                if let result = try? viewContext.fetch(fetchRequest) as? [RemoteData] {
                    if let item = result.first {
                        orgname = item.name
                    }
                }
            }
        }
        DispatchQueue.global().async {
            if let orgname = orgname {
                self.moveItem(fileId: fileId, orgname: orgname, toParentId: toParentId, onFinish: onFinish)
            }
            else {
                onFinish?(nil)
            }
        }
    }
    
    func moveItem(fileId: String, orgname: String, toParentId: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+callWait) {
                self.moveItem(fileId: fileId, orgname: orgname, toParentId: toParentId, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "moveItem(dropbox:\(storageName ?? "") \(fileId) ->\(toParentId)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            let url = "https://api.dropboxapi.com/2/files/move_v2"
            
            var request: URLRequest = URLRequest(url: URL(string: url)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let jsondata: [String: Any] = [
                "from_path": fileId,
                "to_path": "\(toParentId)/\(orgname)",
                "allow_shared_folder": false,
                "autorename": false,
                "allow_ownership_transfer": false]
            guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            request.httpBody = postData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                self.callSemaphore.signal()
                do {
                    if let error = error {
                        print(error)
                        throw RetryError.Failed
                    }
                    guard let data = data else {
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
                    let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
                    backgroundContext.perform {
                        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                        if let result = try? backgroundContext.fetch(fetchRequest) {
                            for object in result {
                                backgroundContext.delete(object as! NSManagedObject)
                            }
                        }
                    }
                    self.storeItem(item: metadata, parentFileId: toParentId, context: backgroundContext)
                    backgroundContext.perform {
                        try? backgroundContext.save()
                        DispatchQueue.global().async {
                            onFinish?(id)
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                            self.moveItem(fileId: fileId, orgname: orgname, toParentId: toParentId, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    onFinish?(nil)
                }
                catch let e {
                    print(e)
                    onFinish?(nil)
                }
            }
            task.resume()
        }
    }
    
    public override func getRaw(fileId: String) -> RemoteItem? {
        return NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) -> RemoteItem? {
        return NetworkRemoteItem(path: path)
    }

    override func uploadFile(parentId: String, sessionId: String, uploadname: String, target: URL, onFinish: ((String?)->Void)?) {
        os_log("%{public}@", log: log, type: .debug, "uploadFile(dropbox:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")
        
        var parentPath = ""
        if Thread.isMainThread {
            let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, self.storageName ?? "")
            if let result = try? viewContext.fetch(fetchRequest) {
                if let items = result as? [RemoteData] {
                    parentPath = items.first?.path ?? ""
                }
            }
            let p = "\(self.storageName ?? ""):"
            if parentPath.hasPrefix(p) {
                parentPath = String(parentPath.dropFirst(p.count))
            }
        }
        else {
            DispatchQueue.main.sync {
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, self.storageName ?? "")
                if let result = try? viewContext.fetch(fetchRequest) {
                    if let items = result as? [RemoteData] {
                        parentPath = items.first?.path ?? ""
                    }
                }
                let p = "\(self.storageName ?? ""):"
                if parentPath.hasPrefix(p) {
                    parentPath = String(parentPath.dropFirst(p.count))
                }
            }
        }
        DispatchQueue.global().async {
            do {
                let attr = try FileManager.default.attributesOfItem(atPath: target.path)
                let fileSize = attr[.size] as! UInt64
                
                UploadManeger.shared.UploadFixSize(identifier: sessionId, size: Int(fileSize))
                
                if fileSize < 150*1000*1000 {
                    self.uploadShortFile(parentId: parentId, sessionId: sessionId, parentPath: parentPath, uploadname: uploadname, target: target, onFinish: onFinish)
                }
                else {
                    self.uploadLongFile(parentId: parentId, sessionId: sessionId, parentPath: parentPath, uploadname: uploadname, target: target, onFinish: onFinish)
                }
            }
            catch {
                onFinish?(nil)
                return
            }
        }
    }
    
    func uploadShortFile(parentId: String, sessionId: String, parentPath: String, uploadname: String, target: URL, onFinish: ((String?)->Void)?) {
        uploadSemaphore.wait()
        checkToken() { success in
            let onFinish: (String?)->Void = { id in
                self.uploadSemaphore.signal()
                onFinish?(id)
            }
            guard success else {
                onFinish(nil)
                return
            }
            let url = "https://content.dropboxapi.com/2/files/upload"
            
            var request: URLRequest = URLRequest(url: URL(string: url)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            
            let jsondata = "{\"path\":\"\(parentId)/\(self.convertUnicode(uploadname))\",\"mode\":\"add\",\"autorename\":true,\"mute\":false,\"strict_conflict\":false}";
            
            request.setValue(jsondata, forHTTPHeaderField: "Dropbox-API-Arg")
            guard let postData = try? Data(contentsOf: target) else {
                onFinish(nil)
                return
            }
            request.httpBody = postData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                do {
                    if let error = error {
                        print(error)
                        onFinish(nil)
                        return
                    }
                    guard let data = data else {
                        onFinish(nil)
                        return
                    }
                    let object = try JSONSerialization.jsonObject(with: data, options: [])
                    guard let json = object as? [String: Any] else {
                        onFinish(nil)
                        return
                    }
                    print(json)
                    guard let id = json["id"] as? String else {
                        onFinish(nil)
                        return
                    }
                    let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
                    backgroundContext.perform {
                        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
                        if let result = try? backgroundContext.fetch(fetchRequest) {
                            for object in result {
                                backgroundContext.delete(object as! NSManagedObject)
                            }
                        }
                    }
                    self.storeItem(item: json, parentFileId: parentId, context: backgroundContext)
                    backgroundContext.perform {
                        try? backgroundContext.save()
                        print("done")
                        DispatchQueue.global().async {
                            onFinish(id)
                        }
                    }
                }
                catch let e {
                    print(e)
                }
            }
            task.resume()
        }
    }

    func uploadLongFile(parentId: String, sessionId: String, parentPath: String, uploadname: String, target: URL, onFinish: ((String?)->Void)?) {
        guard let targetStream = InputStream(url: target) else {
            onFinish?(nil)
            return
        }
        targetStream.open()

        var buf:[UInt8] = [UInt8](repeating: 0, count: 32*1024*1024)
        let len = targetStream.read(&buf, maxLength: buf.count)

        uploadSemaphore.wait()
        checkToken() { success in
            let onFinish: (String?)->Void = { id in
                self.uploadSemaphore.signal()
                onFinish?(id)
            }
            guard success else {
                onFinish(nil)
                return
            }
            let url = "https://content.dropboxapi.com/2/files/upload_session/start"
            
            var request: URLRequest = URLRequest(url: URL(string: url)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            
            let jsondata: [String: Any] = [
                "close": false]
            guard let argData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                onFinish(nil)
                return
            }
            request.setValue(String(data: argData, encoding: .utf8) ?? "", forHTTPHeaderField: "Dropbox-API-Arg")
            let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(Int.random(in: 0...0xffffffff))")
            try? Data(bytes: buf, count: len).write(to: tmpurl)

            let config = URLSessionConfiguration.background(withIdentifier: "\(Bundle.main.bundleIdentifier!).\(self.storageName ?? "").\(Int.random(in: 0..<0xffffffff))")
            //config.isDiscretionary = true
            config.sessionSendsLaunchEvents = true
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.sessions += [session]

            let task = session.uploadTask(with: request, fromFile: tmpurl)
            let taskId = (session.configuration.identifier ?? "") + ".\(task.taskIdentifier)"
            self.taskQueue.async {
                self.task_upload[taskId] = ["data": Data(), "target": targetStream, "parentId": parentId, "parentPath": parentPath, "uploadname": uploadname, "offset": len, "tmpfile": tmpurl, "orgtarget": target, "accessToken": self.accessToken, "session": sessionId]
                self.onFinsh_upload[taskId] = onFinish
                task.resume()
            }
        }
    }
        
    var task_upload = [String: [String: Any]]()
    var onFinsh_upload = [String: ((String?)->Void)?]()
    var sessions = [URLSession]()
    let taskQueue = DispatchQueue(label: "taskDict")

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        CloudFactory.shared.urlSessionDidFinishCallback?(session)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let taskId = (session.configuration.identifier ?? "") + ".\(dataTask.taskIdentifier)"
        if var taskdata = taskQueue.sync(execute: { self.task_upload[taskId] })  {
            guard var recvData = taskdata["data"] as? Data else {
                return
            }
            recvData.append(data)
            taskdata["data"] = recvData
            taskQueue.async {
                self.task_upload[taskId] = taskdata
            }
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        print("\(bytesSent) / \(totalBytesSent) / \(totalBytesExpectedToSend)")
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskId = (session.configuration.identifier ?? "") + ".\(task.taskIdentifier)"
        guard let taskdata = taskQueue.sync(execute: {
            self.task_upload.removeValue(forKey: taskId)
        }) else {
            return
        }
        guard let onFinish = taskQueue.sync(execute: {
            self.onFinsh_upload.removeValue(forKey: taskId)
        }) else {
            print("onFinish not found")
            return
        }
        guard let token = taskdata["accessToken"] as? String else {
            onFinish?(nil)
            return
        }
        if let tmpfile = taskdata["tmpfile"] as? URL {
            try? FileManager.default.removeItem(at: tmpfile)
        }
        guard var targetStream = taskdata["target"] as? InputStream else {
            do {
                if let error = error {
                    print(error)
                    throw RetryError.Failed
                }
                guard let httpResponse = task.response as? HTTPURLResponse else {
                    print(task.response ?? "")
                    throw RetryError.Failed
                }
                guard let data = taskdata["data"] as? Data else {
                    print(httpResponse)
                    throw RetryError.Failed
                }
                print(String(data: data, encoding: .utf8) ?? "")
                guard let parentId = taskdata["parentId"] as? String else {
                    throw RetryError.Failed
                }
                guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    print(httpResponse)
                    throw RetryError.Failed
                }
                if let e = object["error"] as? [String: Any] {
                    print(e)
                    throw RetryError.Failed
                }
                guard let id = object["id"] as? String else {
                    print(object)
                    throw RetryError.Failed
                }
                let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
                backgroundContext.perform {
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
                    if let result = try? backgroundContext.fetch(fetchRequest) {
                        for object in result {
                            backgroundContext.delete(object as! NSManagedObject)
                        }
                    }
                }
                self.storeItem(item: object, parentFileId: parentId, context: backgroundContext)
                backgroundContext.perform {
                    try? backgroundContext.save()
                    print("done")
                    DispatchQueue.global().async {
                        onFinish?(id)
                    }
                }
                self.sessions.removeAll(where: { $0.configuration.identifier == session.configuration.identifier })
                session.finishTasksAndInvalidate()
            }
            catch {
                onFinish?(nil)
            }
            return
        }
        guard let orgtarget = taskdata["orgtarget"] as? URL else {
            targetStream.close()
            onFinish?(nil)
            return
        }
        do {
            guard var offset = taskdata["offset"] as? Int else {
                throw RetryError.Failed
            }
            guard let parentId = taskdata["parentId"] as? String else {
                throw RetryError.Failed
            }
            guard let parentPath = taskdata["parentPath"] as? String else {
                throw RetryError.Failed
            }
            guard let uploadname = taskdata["uploadname"] as? String else {
                throw RetryError.Failed
            }
            guard let sessionId = taskdata["session"] as? String else {
                throw RetryError.Failed
            }
            if let error = error {
                print(error)
                throw RetryError.Failed
            }
            guard let httpResponse = task.response as? HTTPURLResponse else {
                print(task.response ?? "")
                throw RetryError.Failed
            }
            guard let data = taskdata["data"] as? Data else {
                print(httpResponse)
                throw RetryError.Failed
            }
            print(String(data: data, encoding: .utf8) ?? "")
            let session_id: String
            if let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                if let e = object["error"] as? [String: Any] {
                    print(e)
                    guard let correct_offset = e["correct_offset"] as? Int else {
                        throw RetryError.Failed
                    }
                    print(correct_offset)
                    if correct_offset != offset {
                        guard let tstream = InputStream(url: orgtarget) else {
                            throw RetryError.Failed
                        }
                        targetStream.close()
                        targetStream = tstream
                        targetStream.open()
                        
                        offset = 0
                        while offset < correct_offset {
                            var buflen = correct_offset - offset
                            if buflen > 1024*1024 {
                                buflen = 1024*1024
                            }
                            var buf:[UInt8] = [UInt8](repeating: 0, count: buflen)
                            let len = targetStream.read(&buf, maxLength: buf.count)
                            if len <= 0 {
                                print(targetStream.streamError!)
                                throw RetryError.Failed
                            }
                            offset += len
                        }
                    }
                }
                if let s = object["session_id"] as? String {
                    session_id = s
                }
                else if let s2 = taskdata["session_id"] as? String {
                    session_id = s2
                }
                else {
                    throw RetryError.Failed
                }
            }
            else {
                guard let s = taskdata["session_id"] as? String else {
                    throw RetryError.Failed
                }
                session_id = s
            }
            var buf:[UInt8] = [UInt8](repeating: 0, count: 32*1024*1024)
            let len = targetStream.read(&buf, maxLength: buf.count)

            UploadManeger.shared.UploadProgress(identifier: sessionId, possition: offset)

            if len == 32*1024*1024 {
                let url = "https://content.dropboxapi.com/2/files/upload_session/append_v2"
                
                var request: URLRequest = URLRequest(url: URL(string: url)!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                
                let jsondata: [String: Any] = [
                    "cursor": [
                        "session_id": session_id,
                        "offset": offset
                    ],
                    "close": false]
                guard let argData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                    throw RetryError.Failed
                }
                request.setValue(String(data: argData, encoding: .utf8) ?? "", forHTTPHeaderField: "Dropbox-API-Arg")
                let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(Int.random(in: 0...0xffffffff))")
                try? Data(bytes: buf, count: len).write(to: tmpurl)

                let task = session.uploadTask(with: request, fromFile: tmpurl)
                let taskId = (session.configuration.identifier ?? "") + ".\(task.taskIdentifier)"
                taskQueue.async {
                    self.task_upload[taskId] = ["data": Data(), "session_id": session_id, "target": targetStream, "parentId": parentId, "parentPath": parentPath, "uploadname": uploadname, "offset": len+offset, "tmpfile": tmpurl, "orgtarget": orgtarget, "accessToken": token, "session": sessionId]
                    self.onFinsh_upload[taskId] = onFinish
                    task.resume()
                }
            }
            else {
                targetStream.close()
                try? FileManager.default.removeItem(at: orgtarget)
                let url = "https://content.dropboxapi.com/2/files/upload_session/finish"
                
                var request: URLRequest = URLRequest(url: URL(string: url)!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                
                let jsondata = "{\"cursor\":{\"session_id\":\"\(session_id)\",\"offset\":\(offset)},\"commit\": {\"path\":\"\(parentId)/\(self.convertUnicode(uploadname))\",\"mode\":\"add\",\"autorename\":true,\"mute\":false,\"strict_conflict\":false}}";
                request.setValue(jsondata, forHTTPHeaderField: "Dropbox-API-Arg")
                let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(Int.random(in: 0...0xffffffff))")
                try? Data(bytes: buf, count: len).write(to: tmpurl)

                let task = session.uploadTask(with: request, fromFile: tmpurl)
                let taskId = (session.configuration.identifier ?? "") + ".\(task.taskIdentifier)"
                taskQueue.async {
                    self.task_upload[taskId] = ["data": Data(), "parentId": parentId, "tmpfile": tmpurl, "accessToken": token]
                    self.onFinsh_upload[taskId] = onFinish
                    task.resume()
                }
            }
        }
        catch {
            try? FileManager.default.removeItem(at: orgtarget)
            targetStream.close()
            onFinish?(nil)
        }
    }
    
    func convertUnicode(_ str: String) -> String {
        return str.flatMap({ $0.unicodeScalars }).map({ $0.escaped(asASCII: true).replacingOccurrences(of: #"\\u\{([0-9a-fA-F]+)\}"#, with: #"\\u$1"#, options: .regularExpression) }).joined()
    }
}

@available(iOS 13.0, *)
extension DropBoxStorage: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.topViewController()!.view.window!
    }
}

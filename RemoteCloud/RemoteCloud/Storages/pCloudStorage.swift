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

public class pCloudStorage: NetworkStorage, URLSessionTaskDelegate, URLSessionDataDelegate {
    public override func getStorageType() -> CloudStorages {
        return .pCloud
    }
    
    var webAuthSession: ASWebAuthenticationSession?
    
    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .pCloud)
        storageName = name
    }
    
    private let clientid = SecretItems.pCloud.client_id
    private let secret = SecretItems.pCloud.client_secret
    private let callbackUrlScheme = SecretItems.pCloud.callbackUrlScheme
    private let redirect = "\(SecretItems.pCloud.callbackUrlScheme)://oauth2redirect"

    override func authorize(onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "authorize(pCloud:\(storageName ?? ""))")
        
        let url = "https://my.pcloud.com/oauth2/authorize?client_id=\(clientid)&response_type=code&redirect_uri=\(redirect)"
        let authURL = URL(string: url);
        
        self.webAuthSession = ASWebAuthenticationSession.init(url: authURL!, callbackURLScheme: callbackUrlScheme, completionHandler: { (callBack:URL?, error:Error?) in
            
            // handle auth response
            guard error == nil, let successURL = callBack else {
                onFinish?(false)
                return
            }
            
            let oauthToken = NSURLComponents(string: (successURL.absoluteString))?.queryItems?.filter({$0.name == "code"}).first
            
            if let oauthTokenString = oauthToken?.value {
                self.getToken(oauthToken: oauthTokenString, onFinish: onFinish)
            }
            else{
                onFinish?(false)
            }
        })
        
        self.webAuthSession?.start()
    }

    override func getToken(oauthToken: String, onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "getToken(pCloud:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/oauth2_token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let post = "client_id=\(clientid)&client_secret=\(secret)&code=\(oauthToken)"
        var postData = post.data(using: .ascii, allowLossyConversion: false)!
        let postLength = "\(postData.count)"
        request.setValue(postLength, forHTTPHeaderField: "Content-Length")
        request.httpBody = postData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                onFinish?(false)
                return
            }
            do {
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    onFinish?(false)
                    return
                }
                print(json)
                guard let accessToken = json["access_token"] as? String else {
                    onFinish?(false)
                    return
                }
                guard let userId = json["userid"] as? Int else {
                    onFinish?(false)
                    return
                }
                self.saveToken(accessToken: accessToken, accountId: String(userId))
                onFinish?(true)
            } catch let e {
                print(e)
                onFinish?(false)
                return
            }
        }
        task.resume()
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
        os_log("%{public}@", log: log, type: .debug, "revokeToken(pCloud:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/logout")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print(error.localizedDescription)
                onFinish?(false)
                return
            }
            guard let data = data else {
                onFinish?(false)
                return
            }
            do {
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    onFinish?(false)
                    return
                }
                print(json)
                guard let result = json["result"] as? Int else {
                    onFinish?(false)
                    return
                }
                if result == 0 {
                    onFinish?(true)
                }
                else {
                    onFinish?(false)
                }
            } catch let e {
                print(e)
                onFinish?(false)
                return
            }
        }
        task.resume()
    }

    override func isAuthorized(onFinish: ((Bool) -> Void)?) -> Void {
        var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/userinfo")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                onFinish?(false)
                return
            }
            do {
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    onFinish?(false)
                    return
                }
                if let result = json["result"] as? Int, result == 0 {
                    onFinish?(true)
                }
                else{
                    print(json)
                    onFinish?(false)
                }
            } catch let e {
                print(e)
                onFinish?(false)
                return
            }
        }
        task.resume()
    }

    func listFolder(folderId: Int, callCount: Int = 0, onFinish: (([[String:Any]]?)->Void)?) {
        if lastCall.timeIntervalSinceNow > -self.callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                self.listFolder(folderId: folderId, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "listFolder(pCloud:\(storageName ?? ""))")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            let url = "https://api.pcloud.com/listfolder?folderid=\(folderId)&timeformat=timestamp"
            
            var request: URLRequest = URLRequest(url: URL(string: url)!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            
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
                    onFinish?(contents)
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                            self.listFolder(folderId: folderId, callCount: callCount+1, onFinish: onFinish)
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
    
    func storeItem(item: [String: Any], parentFileId: String? = nil, parentPath: String? = nil, group: DispatchGroup?) {
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
        
        group?.enter()
        DispatchQueue.main.async {
            let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
            
            var prevParent: String?
            var prevPath: String?
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
            if let result = try? viewContext.fetch(fetchRequest) {
                for object in result {
                    if let item = object as? RemoteData {
                        prevPath = item.path
                        let component = prevPath?.components(separatedBy: "/")
                        prevPath = component?.dropLast().joined(separator: "/")
                        prevParent = item.parent
                    }
                    viewContext.delete(object as! NSManagedObject)
                }
            }
            
            let newitem = RemoteData(context: viewContext)
            newitem.storage = self.storageName
            newitem.id = id
            newitem.name = name
            let comp = name.components(separatedBy: ".")
            if comp.count >= 1 {
                newitem.ext = comp.last!
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
            group?.leave()
        }
        
    }

    override func ListChildren(fileId: String, path: String, onFinish: (() -> Void)?) {
        let folderId: Int
        if fileId == "" {
            folderId = 0
        }
        else if fileId.starts(with: "d") {
            folderId = Int(fileId.dropFirst()) ?? 0
        }
        else {
            onFinish?()
            return
        }
        listFolder(folderId: folderId) { result in
            if let items = result {
                let group = DispatchGroup()
                
                for item in items {
                    self.storeItem(item: item, parentFileId: fileId, parentPath: path, group: group)
                }
                group.notify(queue: .main){
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    try? viewContext.save()
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

    func getLink(fileId: Int, start: Int64? = nil, length: Int64? = nil, callCount: Int = 0, onFinish: ((Data?) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -self.callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                self.getLink(fileId: fileId, start: start, length: length, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        self.lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
            var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/getfilelink?fileid=\(fileId)")!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            
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
                    DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                        self.getBody(downLink: downLink, start: start, length: length, onFinish: onFinish)
                    }
                }
                catch RetryError.Retry {
                    if callCount < 20 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait+Double.random(in: 0..<self.callWait)) {
                            self.getLink(fileId: fileId, start: start, length: length, callCount: callCount+1, onFinish: onFinish)
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
    
    func getBody(downLink: String, start: Int64? = nil, length: Int64? = nil, callCount: Int = 0, onFinish: ((Data?) -> Void)?) {
        self.lastCall = Date()
        checkToken() { success in
            guard success else {
                onFinish?(nil)
                return
            }
            var request: URLRequest = URLRequest(url: URL(string: downLink)!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
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
                if let error = error {
                    print(error)
                }
                if let l = length {
                    if data?.count ?? 0 != l {
                        if callCount < 50 {
                            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                                self.getBody(downLink: downLink, start: start, length: length, callCount: callCount+1, onFinish: onFinish)
                            }
                            return
                        }
                    }
                }
                onFinish?(data)
            }
            task.resume()
        }
    }
    
    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil, callCount: Int = 0, onFinish: ((Data?) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "readFile(pCloud:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
        
        let id: Int
        if fileId.starts(with: "f") {
            id = Int(fileId.dropFirst()) ?? 0
        }
        else {
            onFinish?(nil)
            return
        }
        getLink(fileId: id, start: start, length: length, onFinish: onFinish)
    }

    public override func getRaw(fileId: String) -> RemoteItem? {
        return NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) -> RemoteItem? {
        return NetworkRemoteItem(path: path)
    }

    func createfolder(folderid: Int, name: String, callCount: Int = 0, onFinish: (([String: Any]?) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -self.callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                self.createfolder(folderid: folderid, name: name, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        self.lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
            let body = "folderid=\(folderid)&name=\(name)&timeformat=timestamp"
            var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/createfolder")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = body.data(using: .utf8)
            
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
                    guard let result = json["result"] as? Int, result == 0 else {
                        print(json)
                        throw RetryError.Retry
                    }
                    guard let metadata = json["metadata"] as? [String: Any] else {
                        print(json)
                        throw RetryError.Retry
                    }
                    onFinish?(metadata)
                }
                catch RetryError.Retry {
                    if callCount < 20 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait+Double.random(in: 0..<self.callWait)) {
                            self.createfolder(folderid: folderid, name: name, callCount: callCount+1, onFinish: onFinish)
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
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        
        if parentId.starts(with: "d") || parentId == "" {
            os_log("%{public}@", log: log, type: .debug, "makeFolder(pCloud:\(storageName ?? "") \(parentId) \(newname)")

            let id = Int(parentId.dropFirst()) ?? 0
            createfolder(folderid: id, name: newname) { metadata in
                guard let metadata = metadata, let newid = metadata["id"] as? String else {
                    onFinish?(nil)
                    return
                }
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    self.storeItem(item: metadata, parentFileId: parentId, parentPath: parentPath, group: group)
                    group.leave()
                }
                group.notify(queue: .main) {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    try? viewContext.save()
                    DispatchQueue.global().async {
                        onFinish?(newid)
                    }
                }
            }
        }
        else {
            onFinish?(nil)
        }
    }
    
    func deletefolderrecursive(folderId: Int, callCount: Int = 0, onFinish: ((Bool) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -self.callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(false)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                self.deletefolderrecursive(folderId: folderId, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        self.lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(false)
                return
            }
            
            let body = "folderid=\(folderId)"
            var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/deletefolderrecursive")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = body.data(using: .utf8)
            
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
                    guard let result = json["result"] as? Int, result == 0 else {
                        print(json)
                        throw RetryError.Retry
                    }
                    onFinish?(true)
                }
                catch RetryError.Retry {
                    if callCount < 20 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait+Double.random(in: 0..<self.callWait)) {
                            self.deletefolderrecursive(folderId: folderId, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    onFinish?(false)
                } catch let e {
                    print(e)
                    onFinish?(false)
                    return
                }
            }
            task.resume()
        }
    }

    func deletefile(fileId: Int, callCount: Int = 0, onFinish: ((Bool) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -self.callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(false)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                self.deletefile(fileId: fileId, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        self.lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(false)
                return
            }
            
            let body = "fileid=\(fileId)"
            var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/deletefile")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = body.data(using: .utf8)
            
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
                    guard let result = json["result"] as? Int, result == 0 else {
                        print(json)
                        throw RetryError.Retry
                    }
                    onFinish?(true)
                }
                catch RetryError.Retry {
                    if callCount < 20 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait+Double.random(in: 0..<self.callWait)) {
                            self.deletefile(fileId: fileId, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    onFinish?(false)
                } catch let e {
                    print(e)
                    onFinish?(false)
                    return
                }
            }
            task.resume()
        }
    }

    override func deleteItem(fileId: String, callCount: Int = 0, onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "deleteItem(pCloud:\(storageName ?? "") \(fileId)")
        
        if fileId.starts(with: "f") {
            let id = Int(fileId.dropFirst()) ?? 0
            deletefile(fileId: id){ success in
                guard success else {
                    onFinish?(false)
                    return
                }
                DispatchQueue.main.async {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                    if let result = try? viewContext.fetch(fetchRequest) {
                        for object in result {
                            viewContext.delete(object as! NSManagedObject)
                        }
                    }
                    
                    self.deleteChildRecursive(parent: fileId)
                    
                    try? viewContext.save()
                    DispatchQueue.global().async {
                        onFinish?(true)
                    }
                }
            }
        }
        else if fileId.starts(with: "d") {
            let id = Int(fileId.dropFirst()) ?? 0
            deletefolderrecursive(folderId: id) { success in
                guard success else {
                    onFinish?(false)
                    return
                }
                DispatchQueue.main.async {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                    if let result = try? viewContext.fetch(fetchRequest) {
                        for object in result {
                            viewContext.delete(object as! NSManagedObject)
                        }
                    }

                    self.deleteChildRecursive(parent: fileId)
                    
                    try? viewContext.save()
                    DispatchQueue.global().async {
                        onFinish?(true)
                    }
                }
            }
        }
        else {
            onFinish?(false)
        }
    }
    
    func renamefile(fileId: Int, toFolderId: Int? = nil, toName: String? = nil, callCount: Int = 0, onFinish: (([String: Any]?) -> Void)?) {
        
        guard toFolderId != nil || toName != nil else {
            onFinish?(nil)
            return
        }
        
        if lastCall.timeIntervalSinceNow > -self.callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                self.renamefile(fileId: fileId, toFolderId: toFolderId, toName: toName, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        self.lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
            var rename = "fileid=\(fileId)&timeformat=timestamp"
            if let toFolderId = toFolderId {
                rename += "&tofolderid=\(toFolderId)"
            }
            if let toName = toName {
                rename += "&toname=\(toName)"
            }
            var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/renamefile")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = rename.data(using: .utf8)
            
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
                    guard let result = json["result"] as? Int, result == 0 else {
                        print(json)
                        throw RetryError.Retry
                    }
                    guard let metadata = json["metadata"] as? [String: Any] else {
                        print(json)
                        throw RetryError.Retry
                    }
                    onFinish?(metadata)
                }
                catch RetryError.Retry {
                    if callCount < 20 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait+Double.random(in: 0..<self.callWait)) {
                            self.renamefile(fileId: fileId, toFolderId: toFolderId, toName: toName, callCount: callCount+1, onFinish: onFinish)
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

    func renamefolder(folderId: Int, toFolderId: Int? = nil, toName: String? = nil, callCount: Int = 0, onFinish: (([String: Any]?) -> Void)?) {
        
        guard toFolderId != nil || toName != nil else {
            onFinish?(nil)
            return
        }
        
        if lastCall.timeIntervalSinceNow > -self.callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                self.renamefolder(folderId: folderId, toFolderId: toFolderId, toName: toName, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        self.lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
            var rename = "folderid=\(folderId)&timeformat=timestamp"
            if let toFolderId = toFolderId {
                rename += "&tofolderid=\(toFolderId)"
            }
            if let toName = toName {
                rename += "&toname=\(toName)"
            }
            var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/renamefolder")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = rename.data(using: .utf8)
            
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
                    guard let result = json["result"] as? Int, result == 0 else {
                        print(json)
                        throw RetryError.Retry
                    }
                    guard let metadata = json["metadata"] as? [String: Any] else {
                        print(json)
                        throw RetryError.Retry
                    }
                    onFinish?(metadata)
                }
                catch RetryError.Retry {
                    if callCount < 20 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait+Double.random(in: 0..<self.callWait)) {
                            self.renamefolder(folderId: folderId, toFolderId: toFolderId, toName: toName, callCount: callCount+1, onFinish: onFinish)
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

    override func renameItem(fileId: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "renameItem(pCloud:\(storageName ?? "") \(fileId) \(newname)")
        
        if fileId.starts(with: "f") {
            let id = Int(fileId.dropFirst()) ?? 0
            renamefile(fileId: id, toName: newname) { metadata in
                guard let metadata = metadata, let newid = metadata["id"] as? String else {
                    onFinish?(nil)
                    return
                }
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    self.storeItem(item: metadata, group: group)
                    group.leave()
                }
                group.notify(queue: .main) {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    try? viewContext.save()
                    DispatchQueue.global().async {
                        onFinish?(newid)
                    }
                }
            }
        }
        else if fileId.starts(with: "d") {
            let id = Int(fileId.dropFirst()) ?? 0
            renamefolder(folderId: id, toName: newname) { metadata in
                guard let metadata = metadata, let newid = metadata["id"] as? String else {
                    onFinish?(nil)
                    return
                }
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    self.storeItem(item: metadata, group: group)
                    group.leave()
                }
                group.notify(queue: .main) {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    try? viewContext.save()
                    DispatchQueue.global().async {
                        onFinish?(newid)
                    }
                }
            }
        }
        else {
            onFinish?(nil)
        }
    }
    
    override func moveItem(fileId: String, fromParentId: String, toParentId: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if fromParentId == toParentId {
            onFinish?(nil)
            return
        }
        if !(fromParentId == "" || fromParentId.starts(with: "d")) || !(toParentId == "" || toParentId.starts(with: "d")) {
            onFinish?(nil)
            return
        }
        let toId = Int(toParentId.dropFirst()) ?? 0
        
        os_log("%{public}@", log: log, type: .debug, "moveItem(pCloud:\(storageName ?? "") \(fileId) \(fromParentId) \(toParentId)")
        
        if fileId.starts(with: "d") {
            let id = Int(fileId.dropFirst()) ?? 0
            renamefolder(folderId: id, toFolderId: toId) { metadata in
                guard let metadata = metadata, let newid = metadata["id"] as? String else {
                    onFinish?(nil)
                    return
                }
                let group = DispatchGroup()
                var toParentPath = ""
                if toParentId != "" {
                    group.enter()
                    DispatchQueue.main.async {
                        defer { group.leave() }
                        
                        let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                        
                        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", toParentId, self.storageName ?? "")
                        if let result = try? viewContext.fetch(fetchRequest) {
                            if let items = result as? [RemoteData] {
                                toParentPath = items.first?.path ?? ""
                            }
                        }
                    }
                }
                group.enter()
                DispatchQueue.global().async {
                    self.storeItem(item: metadata, parentFileId: toParentId, parentPath: toParentPath, group: group)
                    group.leave()
                }
                group.notify(queue: .main) {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    try? viewContext.save()
                    DispatchQueue.global().async {
                        onFinish?(newid)
                    }
                }
            }
        }
        else if fileId.starts(with: "f") {
            let id = Int(fileId.dropFirst()) ?? 0
            renamefile(fileId: id, toFolderId: toId) { metadata in
                guard let metadata = metadata, let newid = metadata["id"] as? String else {
                    onFinish?(nil)
                    return
                }
                let group = DispatchGroup()
                var toParentPath = ""
                if toParentId != "" {
                    group.enter()
                    DispatchQueue.main.async {
                        defer { group.leave() }
                        
                        let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                        
                        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", toParentId, self.storageName ?? "")
                        if let result = try? viewContext.fetch(fetchRequest) {
                            if let items = result as? [RemoteData] {
                                toParentPath = items.first?.path ?? ""
                            }
                        }
                    }
                }
                group.enter()
                DispatchQueue.global().async {
                    self.storeItem(item: metadata, parentFileId: toParentId, parentPath: toParentPath, group: group)
                    group.leave()
                }
                group.notify(queue: .main) {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    try? viewContext.save()
                    DispatchQueue.global().async {
                        onFinish?(newid)
                    }
                }
            }
        }
        else {
            onFinish?(nil)
        }
    }
    
    override func uploadFile(parentId: String, uploadname: String, target: URL, onFinish: ((String?)->Void)?) {
        os_log("%{public}@", log: log, type: .debug, "uploadFile(pCloud:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")
        
        guard parentId == "" || parentId.starts(with: "d") else {
            try? FileManager.default.removeItem(at: target)
            onFinish?(nil)
            return
        }
        let folderId = Int(parentId.dropFirst()) ?? 0

        let fileSize: UInt64
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: target.path)
            fileSize = attr[.size] as! UInt64
        }
        catch {
            try? FileManager.default.removeItem(at: target)
            onFinish?(nil)
            return
        }

        guard let targetStream = InputStream(url: target) else {
            try? FileManager.default.removeItem(at: target)
            onFinish?(nil)
            return
        }
        targetStream.open()

        let group = DispatchGroup()
        var parentPath = "\(storageName ?? ""):/"
        if parentId != "" {
            group.enter()
            DispatchQueue.main.async {
                defer { group.leave() }
                
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, self.storageName ?? "")
                if let result = try? viewContext.fetch(fetchRequest) {
                    if let items = result as? [RemoteData] {
                        parentPath = items.first?.path ?? ""
                    }
                }
            }
        }
        group.notify(queue: .global()){
            self.checkToken() { success in
                guard success else {
                    targetStream.close()
                    try? FileManager.default.removeItem(at: target)
                    onFinish?(nil)
                    return
                }
                
                var request: URLRequest = URLRequest(url: URL(string: "https://api.pcloud.com/uploadfile")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
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
                
                let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(Int.random(in: 0...0xffffffff))")
                guard let outStream = OutputStream(url: tmpurl, append: false) else {
                    onFinish?(nil)
                    return
                }
                outStream.open()
                
                guard body.withUnsafeBytes({ pointer in
                    outStream.write(pointer.bindMemory(to: UInt8.self).baseAddress!, maxLength: pointer.count)
                }) == body.count else {
                    outStream.close()
                    try? FileManager.default.removeItem(at: tmpurl)
                    targetStream.close()
                    try? FileManager.default.removeItem(at: target)
                    onFinish?(nil)
                    return
                }
                
                var offset = 0
                while offset < fileSize {
                    var buflen = Int(fileSize) - offset
                    if buflen > 1024*1024 {
                        buflen = 1024*1024
                    }
                    var buf:[UInt8] = [UInt8](repeating: 0, count: buflen)
                    let len = targetStream.read(&buf, maxLength: buf.count)
                    if len <= 0 || outStream.write(buf, maxLength: len) != len {
                        print(targetStream.streamError!)
                        outStream.close()
                        try? FileManager.default.removeItem(at: tmpurl)
                        targetStream.close()
                        try? FileManager.default.removeItem(at: target)
                        onFinish?(nil)
                        return
                    }
                    offset += len
                }

                guard footer.withUnsafeBytes({ pointer in
                    outStream.write(pointer.bindMemory(to: UInt8.self).baseAddress!, maxLength: pointer.count)
                }) == footer.count else {
                    outStream.close()
                    try? FileManager.default.removeItem(at: tmpurl)
                    targetStream.close()
                    try? FileManager.default.removeItem(at: target)
                    onFinish?(nil)
                    return
                }

                targetStream.close()
                outStream.close()
                
                let config = URLSessionConfiguration.background(withIdentifier: "\(Bundle.main.bundleIdentifier!).\(self.storageName ?? "").\(Int.random(in: 0..<0xffffffff))")
                config.isDiscretionary = true
                config.sessionSendsLaunchEvents = true
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                self.sessions += [session]
                
                let task = session.uploadTask(with: request, fromFile: tmpurl)
                let taskid = task.taskIdentifier
                self.task_upload[taskid] = ["data": Data(), "tmpfile": tmpurl, "parentId": parentId, "parentPath": parentPath]
                self.onFinsh_upload[taskid] = onFinish
                task.resume()
            }
        }
    }

    var task_upload = [Int: [String: Any]]()
    var onFinsh_upload = [Int: ((String?)->Void)?]()
    var sessions = [URLSession]()
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        urlSessionDidFinishCallback?(session)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if var taskdata = self.task_upload[dataTask.taskIdentifier] {
            guard var recvData = taskdata["data"] as? Data else {
                return
            }
            recvData.append(data)
            taskdata["data"] = recvData
            self.task_upload[dataTask.taskIdentifier] = taskdata
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        print("\(bytesSent) / \(totalBytesSent) / \(totalBytesExpectedToSend)")
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        print("d \(bytesWritten) / \(totalBytesWritten) / \(totalBytesExpectedToWrite)")
    }
    

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let taskdata = self.task_upload.removeValue(forKey: task.taskIdentifier) else {
            print(task.response ?? "")
            return
        }
        guard let onFinish = self.onFinsh_upload.removeValue(forKey: task.taskIdentifier) else {
            print("onFinish not found")
            return
        }
        if let tmp = taskdata["tmpfile"] as? URL {
            try? FileManager.default.removeItem(at: tmp)
        }
        do {
            guard let parentId = taskdata["parentId"] as? String, let parentPath = taskdata["parentPath"] as? String else {
                print(task.response ?? "")
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
            guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                throw RetryError.Failed
            }
            guard let result = object["result"] as? Int, result == 0 else {
                print(object)
                throw RetryError.Failed
            }
            guard let metadatas = object["metadata"] as? [[String: Any]], let metadata = metadatas.first else {
                print(object)
                throw RetryError.Failed
            }
            guard let newid = metadata["id"] as? String else {
                print(object)
                throw RetryError.Failed
            }
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                self.storeItem(item: metadata, parentFileId: parentId, parentPath: parentPath, group: group)
                group.leave()
            }
            group.notify(queue: .main) {
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                try? viewContext.save()
                DispatchQueue.global().async {
                    onFinish?(newid)
                }
            }

        }
        catch {
            onFinish?(nil)
        }
    }
}

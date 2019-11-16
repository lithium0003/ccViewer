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

public class OneDriveStorage: NetworkStorage, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate {
    public override func getStorageType() -> CloudStorages {
        return .OneDrive
    }
    
    var webAuthSession: ASWebAuthenticationSession?
    
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

    override func authorize(onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "authorize(onedrive:\(storageName ?? ""))")
        
        let url = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=\(clientid)&scope=\(scope)&response_type=code&redirect_uri=\(redirect)"
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
        if #available(iOS 13.0, *) {
            self.webAuthSession?.presentationContextProvider = self
            self.webAuthSession?.prefersEphemeralWebBrowserSession = true
        }

        self.webAuthSession?.start()
    }

    override func getToken(oauthToken: String, onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "getToken(onedrive:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let post = "client_id=\(clientid)&redirect_uri=\(redirect)&code=\(oauthToken)&scope=\(scope)&grant_type=authorization_code"
        let postData = post.data(using: .ascii, allowLossyConversion: false)!
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
                //print(json)
                guard let accessToken = json["access_token"] as? String else {
                    onFinish?(false)
                    return
                }
                guard let refreshToken = json["refresh_token"] as? String else {
                    onFinish?(false)
                    return
                }
                guard let expires_in = json["expires_in"] as? Int else {
                    onFinish?(false)
                    return
                }
                self.tokenLife = TimeInterval(expires_in)
                self.saveToken(accessToken: accessToken, refreshToken: refreshToken)
                onFinish?(true)
            } catch let e {
                print(e)
                onFinish?(false)
                return
            }
        }
        task.resume()
    }

    override func refreshToken(onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "refreshToken(onedrive:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let post = "client_id=\(clientid)&redirect_uri=\(redirect)&refresh_token=\(refreshToken)&scope=\(scope)&grant_type=refresh_token"
        let postData = post.data(using: .ascii, allowLossyConversion: false)!
        let postLength = "\(postData.count)"
        request.setValue(postLength, forHTTPHeaderField: "Content-Length")
        request.httpBody = postData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                onFinish?(true)
                return
            }
            do {
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    onFinish?(false)
                    return
                }
                guard let accessToken = json["access_token"] as? String else {
                    onFinish?(false)
                    return
                }
                guard let expires_in = json["expires_in"] as? Int else {
                    onFinish?(false)
                    return
                }
                self.tokenLife = TimeInterval(expires_in)
                self.saveToken(accessToken: accessToken, refreshToken: self.refreshToken)
                onFinish?(true)
            } catch let e {
                print(e)
                onFinish?(true)
                return
            }
        }
        task.resume()
    }

    override func isAuthorized(onFinish: ((Bool) -> Void)?) -> Void {
        guard apiEndPoint != "" else {
            onFinish?(false)
            return
        }
        var request: URLRequest = URLRequest(url: URL(string: "\(apiEndPoint)/root")!)
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
                if let _ = json["id"] as? String {
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
    
    func listFiles(itemId: String, nextLink: String, callCount: Int = 0, onFinish: (([[String:Any]]?)->Void)?) {
        if lastCall.timeIntervalSinceNow > -self.callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
           DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                self.listFiles(itemId: itemId, nextLink: nextLink, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "listFiles(onedrive:\(storageName ?? ""))")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            guard self.apiEndPoint != "" else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
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
                    if let e = json["error"] {
                        print(e)
                        throw RetryError.Retry
                    }
                    let nextLink = json["@odata.nextLink"] as? String ?? ""
                    if nextLink == "" {
                        onFinish?(json["value"] as? [[String: Any]])
                    }
                    else {
                        self.listFiles(itemId: itemId, nextLink: nextLink, callCount: callCount) { files in
                            if var files = files {
                                if let newfiles = json["value"] as? [[String: Any]] {
                                    files += newfiles
                                }
                                onFinish?(files)
                            }
                            else {
                                onFinish?(json["value"] as? [[String: Any]])
                            }
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                            self.listFiles(itemId: itemId, nextLink: nextLink, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    onFinish?(nil)
                } catch let e {
                    print(e)
                    onFinish?(nil)
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
            group?.leave()
        }

    }
    
    override func ListChildren(fileId: String, path: String, onFinish: (() -> Void)?) {
        listFiles(itemId: fileId, nextLink: "") { result in
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

    
    func getLink(fileId: String, start: Int64? = nil, length: Int64? = nil, callCount: Int = 0, onFinish: ((Data?) -> Void)?) {
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
            guard self.apiEndPoint != "" else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
            var request: URLRequest = URLRequest(url: URL(string: "\(self.apiEndPoint)/items/\(fileId)")!)
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
                    if let e = json["error"] {
                        print(e)
                        throw RetryError.Retry
                    }
                    let downLink = json["@microsoft.graph.downloadUrl"] as? String ?? ""
                    if downLink == "" {
                        throw RetryError.Retry
                    }
                    else {
                        DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                            self.getBody(downLink: downLink, start: start, length: length, onFinish: onFinish)
                        }
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
        os_log("%{public}@", log: log, type: .debug, "readFile(onedrive:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
        
        getLink(fileId: fileId, start: start, length: length, onFinish: onFinish)
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
        os_log("%{public}@", log: log, type: .debug, "makeFolder(onedrive:\(storageName ?? "") \(parentId) \(newname)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            guard self.apiEndPoint != "" else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
            let path = (parentId == "") ? "root" : "items/\(parentId)"
            let url = "\(self.apiEndPoint)/\(path)/children"
            
            var request: URLRequest = URLRequest(url: URL(string: url)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

            let jsondata: [String: Any] = [
                "name": newname,
                "folder": [String: Any](),
                "@microsoft.graph.conflictBehavior": "fail"
            ]
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
                    guard let id = json["id"] as? String else {
                        throw RetryError.Retry
                    }
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.main.async {
                        let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                        
                        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
                        if let result = try? viewContext.fetch(fetchRequest) {
                            for object in result {
                                viewContext.delete(object as! NSManagedObject)
                            }
                        }
                        self.storeItem(item: json, parentFileId: parentId, parentPath: parentPath, group: group)
                        group.leave()
                    }
                    group.notify(queue: .main) {
                        let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                        try? viewContext.save()
                        DispatchQueue.global().async {
                            onFinish?(id)
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
        os_log("%{public}@", log: log, type: .debug, "deleteItem(onedrive:\(storageName ?? "") \(fileId)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(false)
                return
            }
            guard self.apiEndPoint != "" else {
                self.callSemaphore.signal()
                onFinish?(false)
                return
            }
            
            let url = "\(self.apiEndPoint)/items/\(fileId)"
            
            var request: URLRequest = URLRequest(url: URL(string: url)!)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                self.callSemaphore.signal()
                do {
                    if let error = error {
                        print(error)
                        throw RetryError.Failed
                    }
                    guard let httpResponse = response as? HTTPURLResponse else {
                        print(response ?? "")
                        throw RetryError.Failed
                    }
                    if httpResponse.statusCode == 204 {
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
                        return
                    }
                    if let data = data {
                        print(String(data: data, encoding: .utf8) ?? "")
                    }
                    throw RetryError.Retry
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                            self.deleteItem(fileId: fileId, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    onFinish?(false)
                    return
                }
                catch let e {
                    print(e)
                    onFinish?(false)
                    return
                }
            }
            task.resume()
        }
    }
    
    func getFile(fileId: String, parentId: String? = nil, parentPath: String? = nil, callCount: Int = 0, onFinish: ((Bool)->Void)?) {
        if lastCall.timeIntervalSinceNow > -self.callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(false)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                self.getFile(fileId: fileId, parentId: parentId, parentPath: parentPath, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "getFile(onedrive:\(storageName ?? ""))")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(false)
                return
            }
            guard self.apiEndPoint != "" else {
                self.callSemaphore.signal()
                onFinish?(false)
                return
            }
            
            let fields = "id,name,size,createdDateTime,lastModifiedDateTime,folder,file"
            
            let path = (fileId == "") ? "root" : "items/\(fileId)"
            let url = "\(self.apiEndPoint)/\(path)?select=\(fields)"
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
                    if let e = json["error"] {
                        print(e)
                        throw RetryError.Retry
                    }
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        self.storeItem(item: json, parentFileId: parentId, parentPath: parentPath, group: group)
                        group.leave()
                    }
                    group.notify(queue: .main) {
                        let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                        try? viewContext.save()
                        DispatchQueue.global().async {
                            onFinish?(true)
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                            self.getFile(fileId: fileId, parentId: parentId, parentPath: parentPath, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    onFinish?(false)
                } catch let e {
                    print(e)
                    onFinish?(false)
                }
            }
            task.resume()
        }
    }
    
    func getRootId(callCount: Int = 0, onFinish: ((String?)->Void)?) {
        if lastCall.timeIntervalSinceNow > -self.callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                self.getRootId(callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "getRootId(onedrive:\(storageName ?? ""))")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            guard self.apiEndPoint != "" else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
            let fields = "id"
            
            let url = "\(self.apiEndPoint)/root?select=\(fields)"
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
                    if let e = json["error"] {
                        print(e)
                        throw RetryError.Retry
                    }
                    if let id = json["id"] as? String {
                        DispatchQueue.global().async {
                            onFinish?(id)
                        }
                        return
                    }
                    throw RetryError.Retry
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+self.callWait) {
                            self.getRootId(callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    onFinish?(nil)
                } catch let e {
                    print(e)
                    onFinish?(nil)
                }
            }
            task.resume()
        }
    }

    func updateItem(fileId: String, json: [String: Any], parentId: String? = nil, parentPath: String? = nil, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+5) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+callWait) {
                self.updateItem(fileId: fileId, json: json, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "updateItem(onedrive:\(storageName ?? "") \(fileId)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            guard self.apiEndPoint != "" else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
            let url = "\(self.apiEndPoint)/items/\(fileId)"
            
            var request: URLRequest = URLRequest(url: URL(string: url)!)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            
            guard let postData = try? JSONSerialization.data(withJSONObject: json) else {
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
                    guard let id = json["id"] as? String else {
                        print(json)
                        throw RetryError.Retry
                    }
                    DispatchQueue.global().async {
                        self.getFile(fileId: id, parentId: parentId, parentPath: parentPath) { s in
                            if s {
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
                            self.updateItem(fileId: fileId, json: json, callCount: callCount+1, onFinish: onFinish)
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

    override func renameItem(fileId: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        let json: [String: Any] = ["name": newname]
        updateItem(fileId: fileId, json: json, onFinish: onFinish)
    }
    
    override func moveItem(fileId: String, fromParentId: String, toParentId: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if fromParentId == toParentId {
            onFinish?(nil)
            return
        }
        if toParentId == "" {
            getRootId() { rootId in
                let json: [String: Any] = ["parentReference": ["id": rootId]]
                self.updateItem(fileId: fileId, json: json, parentId: toParentId, onFinish: onFinish)
            }
        }
        else {
            var toParentPath = ""
            let group = DispatchGroup()
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
            group.notify(queue: .global()) {
                let json: [String: Any] = ["parentReference": ["id": toParentId]]
                self.updateItem(fileId: fileId, json: json, parentId: toParentId, parentPath: toParentPath, onFinish: onFinish)
            }
        }
    }
    
    public override func getRaw(fileId: String) -> RemoteItem? {
        return NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) -> RemoteItem? {
        return NetworkRemoteItem(path: path)
    }

    override func uploadFile(parentId: String, sessionId: String, uploadname: String, target: URL, onFinish: ((String?)->Void)?) {
        os_log("%{public}@", log: log, type: .debug, "uploadFile(onedrive:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")
        
        guard let targetStream = InputStream(url: target) else {
            onFinish?(nil)
            return
        }
        targetStream.open()
        
        var buf:[UInt8] = [UInt8](repeating: 0, count: 100*320*1024)
        let len = targetStream.read(&buf, maxLength: buf.count)

        var parentPath = "\(storageName ?? ""):/"
        let group = DispatchGroup()
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
        group.notify(queue: .global()) {
            self.checkToken() { success in
                do {
                    guard success else {
                        throw RetryError.Failed
                    }
                    guard self.apiEndPoint != "" else {
                        throw RetryError.Failed
                    }
                    let attr = try FileManager.default.attributesOfItem(atPath: target.path)
                    let fileSize = attr[.size] as! UInt64
                    
                    UploadManeger.shared.UploadFixSize(identifier: sessionId, size: Int(fileSize))
                    
                    let path = (parentId == "") ? "root" : "items/\(parentId)"
                    var allowedCharacterSet = CharacterSet.alphanumerics
                    allowedCharacterSet.insert(charactersIn: "-._~")
                    let encoded_name = uploadname.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)
                    let url = "\(self.apiEndPoint)/\(path):/\(encoded_name!):/createUploadSession"
                    var request: URLRequest = URLRequest(url: URL(string: url)!)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                    let json: [String: Any] = [
                            "@microsoft.graph.conflictBehavior": "rename"]
                    let postData = try? JSONSerialization.data(withJSONObject: json)
                    request.httpBody = postData
                    
                    let task = URLSession.shared.dataTask(with: request) {data, response, error in
                        do {
                            if let error = error {
                                print(error)
                                throw RetryError.Failed
                            }
                            guard let data = data else {
                                print(response!)
                                throw RetryError.Failed
                            }
                            print(String(data: data, encoding: .utf8) ?? "")
                            guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                                throw RetryError.Failed
                            }
                            guard let uploadUrl = object["uploadUrl"] as? String else {
                                throw RetryError.Failed
                            }

                            var request: URLRequest = URLRequest(url: URL(string: uploadUrl)!)
                            request.httpMethod = "PUT"

                            let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(Int.random(in: 0...0xffffffff))")
                            try? Data(bytes: buf, count: len).write(to: tmpurl)

                            request.setValue("bytes 0-\(len-1)/\(fileSize)", forHTTPHeaderField: "Content-Range")

                            #if !targetEnvironment(macCatalyst)
                            let config = URLSessionConfiguration.background(withIdentifier: "\(Bundle.main.bundleIdentifier!).\(self.storageName ?? "").\(Int.random(in: 0..<0xffffffff))")
                            //config.isDiscretionary = true
                            config.sessionSendsLaunchEvents = true
                            #else
                            let config = URLSessionConfiguration.default
                            #endif
                            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                            self.sessions += [session]

                            let task = session.uploadTask(with: request, fromFile: tmpurl)
                            let taskid = task.taskIdentifier
                            self.task_upload[taskid] = ["target": targetStream, "data": Data(), "upload": uploadUrl, "parentId": parentId, "parentPath": parentPath, "offset": len, "size": Int(fileSize), "tmpfile": tmpurl, "orgtarget": target, "session": sessionId]
                            self.onFinsh_upload[taskid] = onFinish
                            task.resume()
                        }
                        catch {
                            targetStream.close()
                            try? FileManager.default.removeItem(at: target)
                            onFinish?(nil)
                        }
                    }
                    task.resume()
                }
                catch {
                    targetStream.close()
                    try? FileManager.default.removeItem(at: target)
                    onFinish?(nil)
                }
            }
        }
    }
    
    var task_upload = [Int: [String: Any]]()
    var onFinsh_upload = [Int: ((String?)->Void)?]()
    var sessions = [URLSession]()
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        CloudFactory.shared.urlSessionDidFinishCallback?(session)
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
        guard let target = taskdata["orgtarget"] as? URL else {
            print(task.response ?? "")
            onFinish?(nil)
            return
        }
        guard let targetStream = taskdata["target"] as? InputStream else {
            print(task.response ?? "")
            onFinish?(nil)
            return
        }
        if let tmp = taskdata["tmpfile"] as? URL {
            try? FileManager.default.removeItem(at: tmp)
        }
        do {
            guard let uploadUrl = taskdata["upload"] as? String, let offset = taskdata["offset"] as? Int, let fileSize = taskdata["size"] as? Int else {
                print(task.response ?? "")
                throw RetryError.Failed
            }
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
            guard let sessionId = taskdata["session"] as? String else {
                throw RetryError.Failed
            }
            print(String(data: data, encoding: .utf8) ?? "")
            guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                throw RetryError.Failed
            }
            if let e = object["error"] as? [String: Any] {
                print(e)

                DispatchQueue.global().async {
                    targetStream.close()
                }

                var request: URLRequest = URLRequest(url: URL(string: uploadUrl)!)
                request.httpMethod = "GET"

                let task = session.downloadTask(with: request)
                let taskid = task.taskIdentifier
                self.task_upload[taskid] = ["upload": uploadUrl, "parentId": parentId, "parentPath": parentPath, "size": fileSize, "orgtarget": target, "session": sessionId]
                self.onFinsh_upload[taskid] = onFinish
                task.resume()
                return
            }
            if let nextExpectedRanges = object["nextExpectedRanges"] as? [String] {
                print(nextExpectedRanges)
                var buf:[UInt8] = [UInt8](repeating: 0, count: 100*320*1024)
                let len = targetStream.read(&buf, maxLength: buf.count)

                var request: URLRequest = URLRequest(url: URL(string: uploadUrl)!)
                request.httpMethod = "PUT"
                
                let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(Int.random(in: 0...0xffffffff))")
                try? Data(bytes: buf, count: len).write(to: tmpurl)
                
                request.setValue("bytes \(offset)-\(offset+len-1)/\(fileSize)", forHTTPHeaderField: "Content-Range")

                let task = session.uploadTask(with: request, fromFile: tmpurl)
                let taskid = task.taskIdentifier
                self.task_upload[taskid] = ["target": targetStream, "data": Data(), "upload": uploadUrl, "parentId": parentId, "parentPath": parentPath, "offset": offset+len, "size": fileSize, "tmpfile": tmpurl, "orgtarget": target, "session": sessionId]
                self.onFinsh_upload[taskid] = onFinish
                task.resume()
            }
            else {
                guard let id = object["id"] as? String else {
                    throw RetryError.Failed
                }
                print(id)
                DispatchQueue.global().async {
                    targetStream.close()
                    try? FileManager.default.removeItem(at: target)
                }
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    self.storeItem(item: object, parentFileId: parentId, parentPath: parentPath, group: group)
                    group.leave()
                }
                group.notify(queue: .main) {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    try? viewContext.save()
                    print("done")
                    
                    self.sessions.removeAll(where: { $0.configuration.identifier == session.configuration.identifier })
                    session.finishTasksAndInvalidate()
                    
                    onFinish?(id)
                }
            }
        }
        catch {
            targetStream.close()
            try? FileManager.default.removeItem(at: target)
            onFinish?(nil)
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskdata = self.task_upload.removeValue(forKey: downloadTask.taskIdentifier) else {
            return
        }
        guard let onFinish = self.onFinsh_upload.removeValue(forKey: downloadTask.taskIdentifier) else {
            print("onFinish not found")
            return
        }
        guard let target = taskdata["orgtarget"] as? URL else {
            onFinish?(nil)
            return
        }
        do {
            guard let uploadUrl = taskdata["upload"] as? String, let fileSize = taskdata["size"] as? Int else {
                throw RetryError.Failed
            }
            guard let parentId = taskdata["parentId"] as? String, let parentPath = taskdata["parentPath"] as? String else {
                throw RetryError.Failed
            }
            guard let sessionId = taskdata["session"] as? String else {
                throw RetryError.Failed
            }
            let data = try Data(contentsOf: location)
            print(String(data: data, encoding: .utf8) ?? "")
            guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                throw RetryError.Failed
            }
            guard let nextExpectedRanges = object["nextExpectedRanges"] as? [String] else {
                throw RetryError.Failed
            }
            let reqOffset = Int(nextExpectedRanges.first?.replacingOccurrences(of: #"(\d+)-\d+"#, with: "$1", options: .regularExpression) ?? "0") ?? 0
            
            UploadManeger.shared.UploadProgress(identifier: sessionId, possition: reqOffset)

            guard let targetStream = InputStream(url: target) else {
                return
            }
            targetStream.open()

            var offset = 0
            while offset < reqOffset {
                var buflen = reqOffset - offset
                if buflen > 1024*1024 {
                    buflen = 1024*1024
                }
                var buf:[UInt8] = [UInt8](repeating: 0, count: buflen)
                let len = targetStream.read(&buf, maxLength: buf.count)
                if len <= 0 {
                    print(targetStream.streamError!)
                    targetStream.close()
                    throw RetryError.Failed
                }
                offset += len
            }
            
            var buf:[UInt8] = [UInt8](repeating: 0, count: 100*320*1024)
            let len = targetStream.read(&buf, maxLength: buf.count)

            var request: URLRequest = URLRequest(url: URL(string: uploadUrl)!)
            request.httpMethod = "PUT"
            
            let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(Int.random(in: 0...0xffffffff))")
            try? Data(bytes: buf, count: len).write(to: tmpurl)
            
            request.setValue("bytes \(offset)-\(offset+len-1)/\(fileSize)", forHTTPHeaderField: "Content-Range")
            
            let task = session.uploadTask(with: request, fromFile: tmpurl)
            let taskid = task.taskIdentifier
            self.task_upload[taskid] = ["target": targetStream, "data": Data(), "upload": uploadUrl, "parentId": parentId, "parentPath": parentPath, "offset": offset+len, "size": fileSize, "tmpfile": tmpurl, "orgtarget": target, "session": sessionId]
            self.onFinsh_upload[taskid] = onFinish
            task.resume()
        }
        catch {
            onFinish?(nil)
            try? FileManager.default.removeItem(at: target)
        }
    }
}

@available(iOS 13.0, *)
extension OneDriveStorage: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.topViewController()!.view.window!
    }
}

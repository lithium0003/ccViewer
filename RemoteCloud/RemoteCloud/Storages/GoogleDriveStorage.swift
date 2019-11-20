//
//  GoogleDriveStorage.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/10.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import AuthenticationServices
import os.log
import CoreData

public class GoogleDriveStorage: NetworkStorage, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate {

    public override func getStorageType() -> CloudStorages {
        return .GoogleDrive
    }

    var webAuthSession: ASWebAuthenticationSession?
    var spaces = "drive"

    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .GoogleDrive)
        storageName = name
        rootName = "root"
    }
    
    override func isAuthorized(onFinish: ((Bool) -> Void)?) -> Void {
        var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/about?fields=kind")!)
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
                if let _ = json["kind"] as? String {
                    onFinish?(true)
                }
                else{
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
    
    override func authorize(onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "authorize(google:\(storageName ?? ""))")
        
        let scope = "https://www.googleapis.com/auth/drive https://www.googleapis.com/auth/drive.metadata".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        let callbackUrlScheme = SecretItems.Google.callbackUrlScheme
        let clientid = SecretItems.Google.client_id
        let url = "https://accounts.google.com/o/oauth2/v2/auth?scope=\(scope ?? "")&response_type=code&redirect_uri=\(callbackUrlScheme):/oauth2redirect&client_id=\(clientid)"
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
        }

        self.webAuthSession?.start()
    }
    
    override func getToken(oauthToken: String, onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "getToken(google:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v4/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let callbackUrlScheme = SecretItems.Google.callbackUrlScheme
        let clientid = SecretItems.Google.client_id
        let post = "code=\(oauthToken)&redirect_uri=\(callbackUrlScheme):/oauth2redirect&client_id=\(clientid)&grant_type=authorization_code"
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
        os_log("%{public}@", log: log, type: .debug, "refreshToken(google:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v4/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let clientid = SecretItems.Google.client_id
        let post = "refresh_token=\(refreshToken)&client_id=\(clientid)&grant_type=refresh_token"
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

    func refreshTokenBackground(session: URLSession, info: [String: Any], rToken: String, onFinish: ((String?)->Void)?) {
        os_log("%{public}@", log: log, type: .debug, "refreshToken(google:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v4/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let clientid = SecretItems.Google.client_id
        let post = "refresh_token=\(rToken)&client_id=\(clientid)&grant_type=refresh_token"
        let postData = post.data(using: .ascii, allowLossyConversion: false)!
        let postLength = "\(postData.count)"
        request.setValue(postLength, forHTTPHeaderField: "Content-Length")
        request.httpBody = postData
        
        let downloadTask = session.downloadTask(with: request)
        let taskid = downloadTask.taskIdentifier
        self.task_upload[taskid] = info
        self.task_upload[taskid]?["refresh"] = rToken
        self.onFinsh_upload[taskid] = onFinish
        downloadTask.resume()
    }

    override func revokeToken(token: String, onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "revokeToken(google:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://accounts.google.com/o/oauth2/revoke?token=\(token)")!)
        request.httpMethod = "GET"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print(error.localizedDescription)
                onFinish?(false)
                return
            }
            if let response = response as? HTTPURLResponse {
                if response.statusCode == 200 {
                    os_log("%{public}@", log: self.log, type: .info, "revokeToken(google:\(self.storageName ?? "")) success")
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
    
    func listFiles(q: String, pageToken: String, teamDrive: String? = nil, callCount: Int = 0, onFinish: (([[String:Any]]?)->Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+Double.random(in: 0..<callWait)) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<callWait)) {
                self.listFiles(q: q, pageToken: pageToken, teamDrive: teamDrive, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "listFiles(google:\(storageName ?? ""))")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
            let fields = "nextPageToken,incompleteSearch,files(id,mimeType,name,trashed,parents,viewedByMeTime,modifiedTime,createdTime,md5Checksum,size)"
            
            let team: String
            if let teamDrive = teamDrive {
                team = "driveId=\(teamDrive)&corpora=drive&includeItemsFromAllDrives=true&supportsAllDrives=true&"
            }
            else {
                team = ""
            }
            var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?\(team)pageSize=1000&fields=\(fields)&spaces=\(self.spaces)&q=\(q)&pageToken=\(pageToken)")!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
            
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
                    if let e = json["error"] {
                        if let eobj = e as? [String: Any] {
                            if let ecode = eobj["code"] as? Int, ecode == 401 {
                                os_log("%{public}@", log: self.log, type: .debug, "Invalid token (google:\(self.storageName ?? ""))")
                                self.cacheTokenDate = Date(timeIntervalSince1970: 0)
                                self.tokenDate = Date(timeIntervalSince1970: 0)
                            }
                        }
                        print(e)
                        throw RetryError.Retry
                    }
                    let nextPageToken = json["nextPageToken"] as? String ?? ""
                    if nextPageToken == "" {
                        onFinish?(json["files"] as? [[String: Any]])
                    }
                    else {
                        self.listFiles(q: q, pageToken: nextPageToken, teamDrive: teamDrive, callCount: callCount) { files in
                            if var files = files {
                                if let newfiles = json["files"] as? [[String: Any]] {
                                    files += newfiles
                                }
                                onFinish?(files)
                            }
                            else {
                                onFinish?(json["files"] as? [[String: Any]])
                            }
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 100 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                            self.listFiles(q: q, pageToken: pageToken, teamDrive: teamDrive, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    print("retry > 100")
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

    func listTeamdrives(q: String, pageToken: String, callCount: Int = 0, onFinish: (([[String:Any]]?)->Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+Double.random(in: 0..<callWait)) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<callWait)) {
                self.listTeamdrives(q: q, pageToken: pageToken, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "listTeamdrives(google:\(storageName ?? ""))")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }

            var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/drives?q=\(q)&pageToken=\(pageToken)")!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
            
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
                    if let e = json["error"] {
                        print(e)
                        throw RetryError.Retry
                    }
                    let nextPageToken = json["nextPageToken"] as? String ?? ""
                    if nextPageToken == "" {
                        onFinish?(json["drives"] as? [[String: Any]])
                    }
                    else {
                        self.listTeamdrives(q: q, pageToken: nextPageToken, callCount: callCount) { drives in
                            if var drives = drives {
                                if let newfiles = json["drives"] as? [[String: Any]] {
                                    drives += newfiles
                                }
                                onFinish?(drives)
                            }
                            else {
                                onFinish?(json["drives"] as? [[String: Any]])
                            }
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 100 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                            self.listTeamdrives(q: q, pageToken: pageToken, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                    print("retry > 100")
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

    func storeItem(item: [String: Any], parentFileId: String? = nil, parentPath: String? = nil, teamID: String? = nil, group: DispatchGroup?) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)

        guard let id = item["id"] as? String else {
            return
        }
        guard let name = item["name"] as? String else {
            return
        }
        guard let ctime = item["createdTime"] as? String else {
            return
        }
        guard let mtime = item["modifiedTime"] as? String else {
            return
        }
        guard let mimeType = item["mimeType"] as? String else {
            return
        }
        guard let trashed = item["trashed"] as? Int else {
            return
        }
        let size = Int64(item["size"] as? String ?? "0") ?? 0
        let hashstr = item["md5Checksum"] as? String ?? ""
        
        let fixId: String
        if let teamid = teamID {
            fixId = "\(teamid) \(id)"
        }
        else {
            fixId = id
        }

        group?.enter()
        DispatchQueue.main.async {
            let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
            
            var prevParent: String?
            var prevPath: String?
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fixId, self.storageName ?? "")
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
            
            if trashed == 0 {
                let newitem = RemoteData(context: viewContext)
                newitem.storage = self.storageName
                newitem.id = fixId
                newitem.name = name
                let comp = name.components(separatedBy: ".")
                if comp.count >= 1 {
                    newitem.ext = comp.last!.lowercased()
                }
                newitem.cdate = formatter.date(from: ctime)
                newitem.mdate = formatter.date(from: mtime)
                newitem.folder = mimeType == "application/vnd.google-apps.folder"
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
            group?.leave()
        }
    }

    func storeRootItems(group: DispatchGroup?) {
        group?.enter()
        DispatchQueue.main.async {
            let viewContext = CloudFactory.shared.data.persistentContainer.viewContext

            let fetchRequest1 = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest1.predicate = NSPredicate(format: "parent == %@ && storage == %@", "", self.storageName ?? "")
            if let result = try? viewContext.fetch(fetchRequest1) {
                for object in result {
                    viewContext.delete(object as! NSManagedObject)
                }
            }

            let items = ["mydrive","teamdrives"]
            let names = [items[0]: "myDrive", items[1]: "teamDrives"]
            
            for id in items {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
                if let result = try? viewContext.fetch(fetchRequest) {
                    if result.count > 0 {
                        continue
                    }
                }

                let newitem = RemoteData(context: viewContext)
                newitem.storage = self.storageName
                newitem.id = id
                newitem.name = names[id]
                newitem.ext = ""
                newitem.cdate = nil
                newitem.mdate = nil
                newitem.folder = true
                newitem.size = 0
                newitem.hashstr = ""
                newitem.parent = ""
                newitem.path = "\(self.storageName ?? ""):/\(names[id]!)"
            }
            group?.leave()
        }
    }

    func storeTeamDriveItem(item: [String: Any], group: DispatchGroup?) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        
        guard let id = item["id"] as? String else {
            return
        }
        guard let name = item["name"] as? String else {
            return
        }
        
        group?.enter()
        DispatchQueue.main.async {
            let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", "\(id) \(id)", self.storageName ?? "")
            if let result = try? viewContext.fetch(fetchRequest) {
                for object in result {
                    viewContext.delete(object as! NSManagedObject)
                }
            }
            
            let newitem = RemoteData(context: viewContext)
            newitem.storage = self.storageName
            newitem.id = "\(id) \(id)"
            newitem.name = name
            newitem.ext = ""
            newitem.cdate = nil
            newitem.mdate = nil
            newitem.folder = true
            newitem.size = 0
            newitem.hashstr = ""
            newitem.parent = "teamdrives"
            newitem.path = "\(self.storageName ?? ""):/teamDrives/\(name)"
            group?.leave()
        }
    }

    override func ListChildren(fileId: String, path: String, onFinish: (() -> Void)?) {
        if spaces == "appDataFolder" {
            let fixFileId = (fileId == "") ? rootName : fileId
            listFiles(q: "'\(fixFileId)'+in+parents", pageToken: "") { result in
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
            return
        }
        if fileId == "" {
            let group = DispatchGroup()
            storeRootItems(group: group)
            group.notify(queue: .main){
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                try? viewContext.save()
                DispatchQueue.global().async {
                    onFinish?()
                }
            }
            return
        }
        if fileId == "teamdrives" {
            listTeamdrives(q: "", pageToken: "") { result in
                if let items = result {
                    let group = DispatchGroup()
                    
                    for item in items {
                        self.storeTeamDriveItem(item: item, group: group)
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
            return
        }
        if fileId.contains(" ") {
            // team drive
            let comp = fileId.components(separatedBy: " ")
            let teamId = comp[0]
            let fixFileId = comp[1]
            listFiles(q: "'\(fixFileId)'+in+parents", pageToken: "", teamDrive: teamId) { result in
                if let items = result {
                    let group = DispatchGroup()
                    
                    for item in items {
                        self.storeItem(item: item, parentFileId: fileId, parentPath: path, teamID: teamId, group: group)
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
        else {
            let fixFileId = (fileId == "mydrive") ? rootName : fileId
            listFiles(q: "'\(fixFileId)'+in+parents", pageToken: "") { result in
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
    }
    
    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil, callCount: Int = 0, onFinish: ((Data?) -> Void)?) {
        if let cache = CloudFactory.shared.cache.getCache(storage: storageName!, id: fileId, offset: start ?? 0, size: length ?? -1) {
            if let data = try? Data(contentsOf: cache) {
                os_log("%{public}@", log: log, type: .debug, "hit cache(google:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                onFinish?(data)
                return
            }
        }
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+Double.random(in: 0..<callWait)) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                self.readFile(fileId: fileId, start: start, length: length, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        self.lastCall = Date()
        os_log("%{public}@", log: log, type: .debug, "readFile(google:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            let fixFileId: String
            if fileId.contains(" ") {
                let comp = fileId.components(separatedBy: " ")
                fixFileId = comp[1]
            }
            else {
                fixFileId = fileId
            }
            var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fixFileId)?alt=media")!)
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
                            print("retry > 50")
                            onFinish?(data)
                            return
                        }
                        DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<waittime)) {
                            self.readFile(fileId: fileId, start: start, length: length, callCount: callCount+1, onFinish: onFinish)
                        }
                        return
                    }
                }
                if let d = data {
                    CloudFactory.shared.cache.saveCache(storage: self.storageName!, id: fileId, offset: start ?? 0, data: d)
                }
                onFinish?(data)
            }
            task.resume()
        }
    }
    
    func createDrive(newname: String, requestId: String? = nil, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+Double.random(in: 0..<callWait)) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                self.createDrive(newname: newname, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "createDrive(google:\(storageName ?? "") \(newname)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
            let requestId_new: String
            if let requestId_old = requestId {
                requestId_new = requestId_old
            }
            else {
                requestId_new = UUID().uuidString
            }
            var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/drives?requestId=\(requestId_new)")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

            let json: [String: Any] = ["name": newname]
            let postData = try? JSONSerialization.data(withJSONObject: json)
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
                    if let e = json["error"] {
                        print(e)
                        throw RetryError.Retry
                    }
                    guard let id = json["id"] as? String else {
                        throw RetryError.Retry
                    }
                    
                    let group = DispatchGroup()
                    self.storeTeamDriveItem(item: json, group: group)
                    group.notify(queue: .main){
                        let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                        try? viewContext.save()
                        DispatchQueue.global().async {
                            onFinish?(id)
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                            self.createDrive(newname: newname, requestId: requestId_new, callCount: callCount+1, onFinish: onFinish)
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
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        let fixParentId: String
        var teamID: String? = nil
        if parentId.contains(" ") {
            let comp = parentId.components(separatedBy: " ")
            teamID = comp[0]
            fixParentId = comp[1]
        }
        else if parentId == "" {
            fixParentId = rootName
        }
        else if parentId == "mydrive" {
            fixParentId = rootName
        }
        else {
            fixParentId = parentId
        }
        if fixParentId == "" {
            onFinish?(nil)
            return
        }
        if fixParentId == "teamdrives" {
            createDrive(newname: newname, onFinish: onFinish)
            return
        }
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+Double.random(in: 0..<callWait)) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                self.makeFolder(parentId: fixParentId, parentPath: parentPath, newname: newname, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "makeFolder(google:\(storageName ?? "") \(parentId) \(newname)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?supportsTeamDrives=true")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

            let json: [String: Any] = ["name": newname, "parents": [fixParentId], "mimeType": "application/vnd.google-apps.folder"]
            let postData = try? JSONSerialization.data(withJSONObject: json)
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
                    if let e = json["error"] {
                        print(e)
                        throw RetryError.Retry
                    }
                    guard let id = json["id"] as? String else {
                        throw RetryError.Retry
                    }
                    let fixId: String
                    if let teamID = teamID {
                        fixId = "\(teamID) \(id)"
                    }
                    else {
                        fixId = id
                    }
                    DispatchQueue.global().async {
                        self.getFile(fileId: fixId, parentId: parentId, parentPath: parentPath) { success in
                            if success {
                                onFinish?(fixId)
                            }
                            else {
                                onFinish?(nil)
                            }
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
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

    func getFile(fileId: String, parentId: String? = nil, parentPath: String? = nil, callCount: Int = 0, onFinish: ((Bool)->Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+Double.random(in: 0..<callWait)) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(false)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<callWait)) {
                self.getFile(fileId: fileId, parentId: parentId, parentPath: parentPath, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "getFile(google:\(storageName ?? "") \(fileId)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(false)
                return
            }
            
            let fields = "id,mimeType,name,trashed,parents,viewedByMeTime,modifiedTime,createdTime,md5Checksum,size"
            
            let fixFileId: String
            if fileId.contains(" ") {
                let comp = fileId.components(separatedBy: " ")
                fixFileId = comp[1]
            }
            else {
                fixFileId = fileId
            }
            var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fixFileId)?fields=\(fields)&supportsTeamDrives=true")!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
            
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
                        let teamID: String?
                        if fileId.contains(" ") {
                            let comp = fileId.components(separatedBy: " ")
                            teamID = comp[0]
                        }
                        else {
                            teamID = nil
                        }
                        self.storeItem(item: json, parentFileId: parentId, parentPath: parentPath, teamID: teamID, group: group)
                        group.leave()
                    }
                    group.notify(queue: .main){
                        let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                        try? viewContext.save()
                        DispatchQueue.global().async {
                            onFinish?(true)
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 10 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                            self.getFile(fileId: fileId, parentId: parentId, parentPath: parentPath, callCount: callCount+1, onFinish: onFinish)
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

    func getFileBackground(session: URLSession, fileId: String, parentId: String, parentPath: String, aToken: String, rToken: String, onFinish: ((String?)->Void)?) {
        guard Date() < tokenDate + tokenLife - 5*60, rToken != "" else {
            refreshTokenBackground(session: session, info: ["getFileId": fileId, "parentId": parentId, "parentPath": parentPath], rToken: rToken, onFinish: onFinish)
            return
        }

        os_log("%{public}@", log: log, type: .debug, "getFile(google:\(storageName ?? "") \(fileId)")
        
        let fields = "id,mimeType,name,trashed,parents,viewedByMeTime,modifiedTime,createdTime,md5Checksum,size"
        
        let fixFileId: String
        if fileId.contains(" ") {
            let comp = fileId.components(separatedBy: " ")
            fixFileId = comp[1]
        }
        else {
            fixFileId = fileId
        }
        var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fixFileId)?fields=\(fields)&supportsTeamDrives=true")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(aToken)", forHTTPHeaderField: "Authorization")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        let downloadTask = session.downloadTask(with: request)
        let taskid = downloadTask.taskIdentifier
        self.task_upload[taskid] = ["parentId": parentId, "parentPath": parentPath]
        self.onFinsh_upload[taskid] = onFinish
        downloadTask.resume()
    }

    func updateFile(fileId: String, metadata: [String: Any], callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+Double.random(in: 0..<callWait)) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<callWait)) {
                self.updateFile(fileId: fileId, metadata: metadata, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "updateFile(google:\(storageName ?? "") \(fileId)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
            let fixFileId: String
            if fileId.contains(" ") {
                let comp = fileId.components(separatedBy: " ")
                fixFileId = comp[1]
            }
            else {
                fixFileId = fileId
            }
            var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fixFileId)?supportsTeamDrives=true")!)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            let postData = try? JSONSerialization.data(withJSONObject: metadata)
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
                    guard let id = json["id"] as? String else {
                        throw RetryError.Retry
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now()+1) {
                        let fixId: String
                        if fileId.contains(" ") {
                            let comp = fileId.components(separatedBy: " ")
                            fixId = "\(comp[0]) \(id)"
                        }
                        else {
                            fixId = id
                        }
                        self.getFile(fileId: fixId) { s in
                            if s {
                                onFinish?(fixId)
                            }
                            else {
                                onFinish?(nil)
                            }
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 100 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                            self.updateFile(fileId: fileId, metadata: metadata, callCount: callCount+1, onFinish: onFinish)
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
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+Double.random(in: 0..<callWait)) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<callWait)) {
                self.moveItem(fileId: fileId, fromParentId: fromParentId, toParentId: toParentId, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        if toParentId == fromParentId {
            callSemaphore.signal()
            onFinish?(nil)
            return
        }
        var targetId = fileId
        if fileId.contains(" ") {
            // teamdrive
            let comp = fileId.components(separatedBy: " ")
            let driveId = comp[0]
            let fixFileId = comp[1]
            if driveId == fixFileId {
                callSemaphore.signal()
                onFinish?(nil)
                return
            }
            targetId = fixFileId
        }
        let toParentFix: String
        if toParentId.contains(" ") {
            let comp = toParentId.components(separatedBy: " ")
            toParentFix = comp[1]
        }
        else {
            toParentFix = (toParentId == "") ? rootName : toParentId
        }
        var toParentPath: String?
        let formParentFix: String
        if fromParentId.contains(" ") {
            let comp = fromParentId.components(separatedBy: " ")
            formParentFix = comp[1]
        }
        else {
            formParentFix = (fromParentId == "") ? rootName : fromParentId
        }

        let group = DispatchGroup()
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
        group.notify(queue: .global()){
            os_log("%{public}@", log: self.log, type: .debug, "moveItem(google:\(self.storageName ?? "") \(formParentFix)->\(toParentFix)")
            self.lastCall = Date()
            self.checkToken() { success in
                guard success else {
                    self.callSemaphore.signal()
                    onFinish?(nil)
                    return
                }
                
                var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(targetId)?addParents=\(toParentFix)&removeParents=\(formParentFix)&supportsTeamDrives=true")!)
                request.httpMethod = "PATCH"
                request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
                request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                let json: [String: Any] = [:]
                let postData = try? JSONSerialization.data(withJSONObject: json)
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
                        guard let id = json["id"] as? String else {
                            throw RetryError.Retry
                        }
                        DispatchQueue.global().async {
                            let fixId: String
                            if fileId.contains(" ") {
                                // teamdrive
                                let comp = fileId.components(separatedBy: " ")
                                let driveId = comp[0]
                                fixId = "\(driveId) \(id)"
                            }
                            else {
                                fixId = id
                            }
                            self.getFile(fileId: fixId, parentId: toParentId, parentPath: toParentPath) { s in
                                if s {
                                    onFinish?(fixId)
                                }
                                else {
                                    onFinish?(nil)
                                }
                            }
                        }
                    }
                    catch RetryError.Retry {
                        if callCount < 100 {
                            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                                self.moveItem(fileId: fileId, fromParentId: fromParentId, toParentId: toParentId, callCount: callCount+1, onFinish: onFinish)
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
    }

    func deleteDrive(driveId: String, callCount: Int = 0, onFinish: ((Bool) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+Double.random(in: 0..<callWait)) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(false)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<callWait)) {
                self.deleteDrive(driveId: driveId, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "deleteDrive(google:\(storageName ?? "") \(driveId)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(false)
                return
            }
            
            var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/drives/\(driveId)")!)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                self.callSemaphore.signal()
                do {
                    guard let data = data else {
                        throw RetryError.Retry
                    }
                    if data.count == 0 {
                        DispatchQueue.main.async {
                            let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                            
                            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", "\(driveId) \(driveId)", self.storageName ?? "")
                            if let result = try? viewContext.fetch(fetchRequest) {
                                for object in result {
                                    viewContext.delete(object as! NSManagedObject)
                                }
                            }
                            try? viewContext.save()

                            DispatchQueue.global().async {
                                onFinish?(true)
                            }
                        }
                        return
                    }
                    let object = try JSONSerialization.jsonObject(with: data, options: [])
                    guard let json = object as? [String: Any] else {
                        throw RetryError.Retry
                    }
                    if let e = json["error"] {
                        print(e)
                        throw RetryError.Retry
                    }
                    print(json)
                    throw RetryError.Retry
                }
                catch RetryError.Retry {
                    if callCount < 5 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                            self.deleteDrive(driveId: driveId, callCount: callCount+1, onFinish: onFinish)
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
    
    override func deleteItem(fileId: String, callCount: Int = 0, onFinish: ((Bool) -> Void)?) {
        if fileId == "" || fileId == "mydrive" || fileId == "teamdrives" {
            onFinish?(false)
            return
        }
        if fileId.contains(" ") {
            let comp = fileId.components(separatedBy: " ")
            let driveId = comp[0]
            let fixFileId = comp[1]
            if driveId == fixFileId {
                deleteDrive(driveId: driveId) { success in
                    guard success else {
                        onFinish?(false)
                        return
                    }
                    
                    DispatchQueue.main.async {
                        let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                        
                        self.deleteChildRecursive(parent: driveId)
                        
                        try? viewContext.save()
                        DispatchQueue.global().async {
                            onFinish?(true)
                        }
                    }
                }
            }
            else {
                let json: [String: Any] = ["trashed": true]
                updateFile(fileId: fileId, metadata: json) { id in
                    guard let id = id else {
                        onFinish?(false)
                        return
                    }
                    DispatchQueue.main.async {
                        let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                        
                        self.deleteChildRecursive(parent: id)
                        
                        try? viewContext.save()
                        DispatchQueue.global().async {
                            onFinish?(true)
                        }
                    }
                }
            }
        }
        else {
            let json: [String: Any] = ["trashed": true]
            updateFile(fileId: fileId, metadata: json) { id in
                guard let id = id else {
                    onFinish?(false)
                    return
                }
                DispatchQueue.main.async {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    
                    self.deleteChildRecursive(parent: id)
                    
                    try? viewContext.save()
                    DispatchQueue.global().async {
                        onFinish?(true)
                    }
                }
            }
        }
    }

    func updateDrive(driveId: String, metadata: [String: Any], callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if lastCall.timeIntervalSinceNow > -callWait || callSemaphore.wait(wallTimeout: .now()+Double.random(in: 0..<callWait)) == .timedOut {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                onFinish?(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<callWait)) {
                self.updateDrive(driveId: driveId, metadata: metadata, callCount: callCount+1, onFinish: onFinish)
            }
            return
        }
        os_log("%{public}@", log: log, type: .debug, "updateDrive(google:\(storageName ?? "") \(driveId)")
        lastCall = Date()
        checkToken() { success in
            guard success else {
                self.callSemaphore.signal()
                onFinish?(nil)
                return
            }
            
            var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/drives/\(driveId)")!)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            let postData = try? JSONSerialization.data(withJSONObject: metadata)
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
                    guard let id = json["id"] as? String else {
                        throw RetryError.Retry
                    }
                    
                    let group = DispatchGroup()
                    self.storeTeamDriveItem(item: json, group: group)
                    group.notify(queue: .main){
                        let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                        try? viewContext.save()
                        DispatchQueue.global().async {
                            onFinish?(id)
                        }
                    }
                }
                catch RetryError.Retry {
                    if callCount < 100 {
                        DispatchQueue.global().asyncAfter(deadline: .now()+Double.random(in: 0..<self.callWait)) {
                            self.updateDrive(driveId: driveId, metadata: metadata, callCount: callCount+1, onFinish: onFinish)
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
        if fileId == "" || fileId == "mydrive" || fileId == "teamdrives" {
            onFinish?(nil)
            return
        }
        let json: [String: Any] = ["name": newname]
        if fileId.contains(" ") {
            // teamdrive
            let comp = fileId.components(separatedBy: " ")
            let driveId = comp[0]
            let fixFileId = comp[1]
            if driveId == fixFileId {
                updateDrive(driveId: driveId, metadata: json, onFinish: onFinish)
            }
            else {
                updateFile(fileId: fileId, metadata: json, onFinish: onFinish)
            }
        }
        else {
            updateFile(fileId: fileId, metadata: json, onFinish: onFinish)
        }
    }
    
    override func changeTime(fileId: String, newdate: Date, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        if fileId == "" || fileId == "mydrive" || fileId == "teamdrives" {
            onFinish?(nil)
            return
        }
        if fileId.contains(" ") {
            // teamdrive
            let comp = fileId.components(separatedBy: " ")
            let driveId = comp[0]
            let fixFileId = comp[1]
            if driveId == fixFileId {
                onFinish?(nil)
                return
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        let json: [String: Any] = ["modifiedTime": formatter.string(from: newdate)]
        updateFile(fileId: fileId, metadata: json, onFinish: onFinish)
    }
    
    public override func getRaw(fileId: String) -> RemoteItem? {
        return NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) -> RemoteItem? {
        return NetworkRemoteItem(path: path)
    }
    
    override func uploadFile(parentId: String, sessionId: String, uploadname: String, target: URL, onFinish: ((String?)->Void)?) {
        if parentId == "teamdrives" {
            onFinish?(nil)
            return
        }
        if rootName == "root" && parentId == "" {
            onFinish?(nil)
            return
        }
        var fixParentId = parentId
        var parentPath = "\(storageName ?? ""):/"
        if parentId == "mydrive" {
            fixParentId = rootName
            parentPath = "\(storageName ?? ""):/myDrive/"
        }
        else if parentId == "" {
            fixParentId = rootName
            parentPath = "\(storageName ?? ""):/"
        }
        else if parentId.contains(" ") {
            let comp = parentId.components(separatedBy: " ")
            fixParentId = comp[1]
        }

        os_log("%{public}@", log: log, type: .debug, "uploadFile(google:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")

        guard let targetStream = InputStream(url: target) else {
            onFinish?(nil)
            return
        }
        targetStream.open()
        
        var buf:[UInt8] = [UInt8](repeating: 0, count: 32*1024*1024)
        let len = targetStream.read(&buf, maxLength: buf.count)
        
        let group = DispatchGroup()
        if fixParentId != rootName {
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
                    let attr = try FileManager.default.attributesOfItem(atPath: target.path)
                    let fileSize = attr[.size] as! UInt64

                    UploadManeger.shared.UploadFixSize(identifier: sessionId, size: Int(fileSize))
                    
                    var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsTeamDrives=true")!)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
                    request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                    let json: [String: Any] = [
                        "name": uploadname,
                        "parents": [fixParentId]
                    ]
                    let postData = try? JSONSerialization.data(withJSONObject: json)
                    request.httpBody = postData

                    let task = URLSession.shared.dataTask(with: request) {data, response, error in
                        do {
                            if let error = error {
                                print(error)
                                throw RetryError.Failed
                            }
                            guard let httpResponse = response as? HTTPURLResponse else {
                                print(response ?? "")
                                throw RetryError.Failed
                            }
                            guard let location = httpResponse.allHeaderFields["Location"] as? String else {
                                throw RetryError.Failed
                            }
                            
                            let uploadUrl = URL(string: location)!
                            var request2: URLRequest = URLRequest(url: uploadUrl)
                            request2.httpMethod = "PUT"
                            
                            let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(Int.random(in: 0...0xffffffff))")
                            try? Data(bytes: buf, count: len).write(to: tmpurl)
                            
                            request2.setValue("bytes 0-\(len-1)/\(fileSize)", forHTTPHeaderField: "Content-Range")

                            #if !targetEnvironment(macCatalyst)
                            let config = URLSessionConfiguration.background(withIdentifier: "\(Bundle.main.bundleIdentifier!).\(self.storageName ?? "").\(Int.random(in: 0..<0xffffffff))")
                            //config.isDiscretionary = true
                            config.sessionSendsLaunchEvents = true
                            #else
                            let config = URLSessionConfiguration.default
                            #endif
                            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                            self.sessions += [session]
                            
                            let task2 = session.uploadTask(with: request2, fromFile: tmpurl)
                            let taskid = task2.taskIdentifier
                            self.task_upload[taskid] = ["target": targetStream, "data": Data(),"upload": uploadUrl, "parentId": parentId, "parentPath": parentPath, "aToken": self.accessToken, "rToken": self.refreshToken, "offset": len, "size": Int(fileSize), "tmpfile": tmpurl, "orgtarget": target, "session": sessionId]
                            self.onFinsh_upload[taskid] = onFinish
                            task2.resume()
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
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let taskdata = self.task_upload.removeValue(forKey: task.taskIdentifier) else {
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
        guard var targetStream = taskdata["target"] as? InputStream else {
            print(task.response ?? "")
            onFinish?(nil)
            return
        }
        if let tmp = taskdata["tmpfile"] as? URL {
            try? FileManager.default.removeItem(at: tmp)
        }
        do {
            guard let uploadUrl = taskdata["upload"] as? URL, var offset = taskdata["offset"] as? Int, let fileSize = taskdata["size"] as? Int else {
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
            guard let aToken = taskdata["aToken"] as? String, let rToken = taskdata["rToken"] as? String else {
                throw RetryError.Failed
            }
            guard let sessionId = taskdata["session"] as? String else {
                throw RetryError.Failed
            }
            switch httpResponse.statusCode {
            case 200...201:
                if let target = taskdata["target"] as? URL {
                    try? FileManager.default.removeItem(at: target)
                }
                guard let data = taskdata["data"] as? Data else {
                    print(httpResponse)
                    throw RetryError.Failed
                }
                print(String(data: data, encoding: .utf8) ?? "")
                guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    throw RetryError.Failed
                }
                guard let id = object["id"] as? String else {
                    throw RetryError.Failed
                }
                guard let parentId = taskdata["parentId"] as? String, let parentPath = taskdata["parentPath"] as? String else {
                    throw RetryError.Failed
                }
                self.getFileBackground(session: session, fileId: id, parentId: parentId, parentPath: parentPath, aToken: aToken, rToken: rToken, onFinish: onFinish)
            case 308:
                guard let range = httpResponse.allHeaderFields["Range"] as? String else {
                    throw RetryError.Failed
                }
                print("308 resume \(range)")
                if Int(range.replacingOccurrences(of: #"bytes=(\d+)-\d+"#, with: "$1", options: .regularExpression)) ?? -1 != 0 {
                    throw RetryError.Failed
                }
                let reqOffset = (Int(range.replacingOccurrences(of: #"bytes=\d+-(\d+)"#, with: "$1", options: .regularExpression)) ?? -1) + 1

                print(reqOffset)
                UploadManeger.shared.UploadProgress(identifier: sessionId, possition: reqOffset)
                
                if offset != reqOffset {
                    guard let tstream = InputStream(url: target) else {
                        throw RetryError.Failed
                    }
                    targetStream.close()
                    targetStream = tstream
                    targetStream.open()
                    
                    offset = 0
                    while offset < reqOffset {
                        var buflen = reqOffset - offset
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
                
                var buf:[UInt8] = [UInt8](repeating: 0, count: 32*1024*1024)
                let len = targetStream.read(&buf, maxLength: buf.count)
                
                var request: URLRequest = URLRequest(url: uploadUrl)
                request.httpMethod = "PUT"
                
                let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(Int.random(in: 0...0xffffffff))")
                try? Data(bytes: buf, count: len).write(to: tmpurl)
                
                request.setValue("bytes \(offset)-\(offset+len-1)/\(fileSize)", forHTTPHeaderField: "Content-Range")
                
                let task = session.uploadTask(with: request, fromFile: tmpurl)
                let taskid = task.taskIdentifier
                self.task_upload[taskid] = ["target": targetStream, "data": Data(),"upload": uploadUrl, "parentId": parentId, "parentPath": parentPath, "aToken": aToken, "rToken": rToken, "offset": offset+len, "size": fileSize, "tmpfile": tmpurl, "orgtarget": target, "session": sessionId]
                self.onFinsh_upload[taskid] = onFinish
                task.resume()

            case 404:
                print("404 start from begining")

                guard let tstream = InputStream(url: target) else {
                    throw RetryError.Failed
                }
                targetStream.close()
                targetStream = tstream
                targetStream.open()

                offset = 0
                UploadManeger.shared.UploadProgress(identifier: sessionId, possition: 0)

                var buf:[UInt8] = [UInt8](repeating: 0, count: 32*1024*1024)
                let len = targetStream.read(&buf, maxLength: buf.count)
                
                var request: URLRequest = URLRequest(url: uploadUrl)
                request.httpMethod = "PUT"
                
                let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(Int.random(in: 0...0xffffffff))")
                try? Data(bytes: buf, count: len).write(to: tmpurl)
                
                request.setValue("bytes \(offset)-\(offset+len-1)/\(fileSize)", forHTTPHeaderField: "Content-Range")
                
                let task = session.uploadTask(with: request, fromFile: tmpurl)
                let taskid = task.taskIdentifier
                self.task_upload[taskid] = ["target": targetStream, "data": Data(),"upload": uploadUrl, "parentId": parentId, "parentPath": parentPath, "aToken": aToken, "rToken": rToken, "offset": offset+len, "size": fileSize, "tmpfile": tmpurl, "orgtarget": target, "session": sessionId]
                self.onFinsh_upload[taskid] = onFinish
                task.resume()
                
            default:
                print("\(httpResponse.statusCode) resume request")
                print("\(httpResponse.allHeaderFields)")
                if let data = taskdata["data"] as? Data {
                    print(String(bytes: data, encoding: .utf8) ?? "")
                }
                
                guard let tstream = InputStream(url: target) else {
                    throw RetryError.Failed
                }
                targetStream.close()
                targetStream = tstream
                targetStream.open()

                UploadManeger.shared.UploadProgress(identifier: sessionId, possition: 0)

                var request: URLRequest = URLRequest(url: uploadUrl)
                request.httpMethod = "PUT"
                request.setValue("bytes */\(fileSize)", forHTTPHeaderField: "Content-Range")

                let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(Int.random(in: 0...0xffffffff))")
                try? Data().write(to: tmpurl)

                let task = session.uploadTask(with: request, fromFile: tmpurl)
                let taskid = task.taskIdentifier
                self.task_upload[taskid] = ["target": targetStream, "data": Data(),"upload": uploadUrl, "parentId": parentId, "parentPath": parentPath, "aToken": aToken, "rToken": rToken, "offset": 0, "size": fileSize, "tmpfile": tmpurl, "orgtarget": target, "session": sessionId]
                self.onFinsh_upload[taskid] = onFinish
                task.resume()
                
            }
        }
        catch {
            targetStream.close()
            try? FileManager.default.removeItem(at: target)
            onFinish?(nil)
        }
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
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskdata = self.task_upload.removeValue(forKey: downloadTask.taskIdentifier) else {
            return
        }
        guard let onFinish = self.onFinsh_upload.removeValue(forKey: downloadTask.taskIdentifier) else {
            print("onFinish not found")
            return
        }
        guard let httpResponse = downloadTask.response as? HTTPURLResponse else {
            print(downloadTask.response ?? "")
            onFinish?(nil)
            return
        }
        if taskdata["location"] as? String == nil, let _ = taskdata["target"] as? URL, let _ = httpResponse.allHeaderFields["Location"] as? String {

            self.task_upload[downloadTask.taskIdentifier] = taskdata
            self.onFinsh_upload[downloadTask.taskIdentifier] = onFinish
            return
        }
        do {
            let data = try Data(contentsOf: location)
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            if let rToken = taskdata["refresh"] as? String {
                guard let json = object as? [String: Any] else {
                    onFinish?(nil)
                    return
                }
                guard let accessToken = json["access_token"] as? String else {
                    onFinish?(nil)
                    return
                }
                
                if let getItemId = taskdata["getItemId"] as? String {
                    guard let parentId = taskdata["parentId"] as? String else {
                        onFinish?(nil)
                        return
                    }
                    guard let parentPath = taskdata["parentPath"] as? String else {
                        onFinish?(nil)
                        return
                    }
                    getFileBackground(session: session, fileId: getItemId, parentId: parentId, parentPath: parentPath, aToken: accessToken, rToken: rToken, onFinish: onFinish)
                }
                return
            }
            guard let parentId = taskdata["parentId"] as? String, let parentPath = taskdata["parentPath"] as? String else {
                onFinish?(nil)
                return
            }
            guard let json = object as? [String: Any] else {
                onFinish?(nil)
                return
            }
            if let e = json["error"] {
                print(e)
                onFinish?(nil)
                return
            }
            guard let id = json["id"] as? String else {
                onFinish?(nil)
                return
            }
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                self.storeItem(item: json, parentFileId: parentId, parentPath: parentPath, group: group)
                group.leave()
            }
            group.notify(queue: .main){
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                try? viewContext.save()
                print("done")
                
                self.sessions.removeAll(where: { $0.configuration.identifier == session.configuration.identifier })
                session.finishTasksAndInvalidate()
                
                onFinish?(id)
            }
        }
        catch let e {
            onFinish?(nil)
            print(e)
        }
    }
}

public class GoogleDriveStorageCustom: GoogleDriveStorage {
    var code_verifier: String = ""
    var client_id: String = ""
    var client_secret: String = ""
    
    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .GoogleDrive)
        storageName = name
        rootName = "root"
        if let scope = self.getKeyChain(key: "\(self.storageName ?? "")_clientscope") {
            if scope.contains("drive.appfolder") {
                spaces = "appDataFolder"
                rootName = "appDataFolder"
            }
        }
        if refreshToken != "" {
            refreshToken() { success in
                // ignore error
            }
        }
    }

    override public func logout() {
        if let name = storageName {
            let _ = delKeyChain(key: "\(name)_clientid")
            let _ = delKeyChain(key: "\(name)_clientsecret")
            let _ = delKeyChain(key: "\(name)_clientscope")
        }
        super.logout()
    }

    override func authorize(onFinish: ((Bool) -> Void)?) {
        DispatchQueue.main.async {
            if let clientid = self.getKeyChain(key: "\(self.storageName ?? "")_clientid"), let secret = self.getKeyChain(key: "\(self.storageName ?? "")_clientsecret"), let scope = self.getKeyChain(key: "\(self.storageName ?? "")_clientscope") {
                if scope.contains("drive.appfolder") {
                    self.spaces = "appDataFolder"
                    self.rootName = "appDataFolder"
                }
                self.customAuthorize(clientid: clientid, secret: secret, scope: scope, onFinish: onFinish)
                return
            }
            
            if let controller = UIApplication.topViewController() {
                let customizeView = ViewControllerGoogleCustom()
                customizeView.onCancel = {
                    onFinish?(false)
                }
                customizeView.onFinish = { clientid, secret, scope in
                    if scope.contains("drive.appfolder") {
                        self.spaces = "appDataFolder"
                        self.rootName = "appDataFolder"
                    }
                    guard clientid != "", secret != "", let scope = scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                        DispatchQueue.main.async {
                            super.authorize(onFinish: onFinish)
                        }
                        return
                    }
                    
                    let _ = self.setKeyChain(key: "\(self.storageName ?? "")_clientid", value: clientid)
                    let _ = self.setKeyChain(key: "\(self.storageName ?? "")_clientsecret", value: secret)
                    let _ = self.setKeyChain(key: "\(self.storageName ?? "")_clientscope", value: scope)

                    DispatchQueue.global().async {
                        self.customAuthorize(clientid: clientid, secret: secret, scope: scope, onFinish: onFinish)
                    }
                }
                controller.navigationController?.pushViewController(customizeView, animated: true)
            }
            else {
                onFinish?(false)
            }
        }
    }
    
    func customAuthorize(clientid: String, secret: String, scope: String, onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "authorize(google:\(storageName ?? ""))")
        
        code_verifier = ""
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        for _ in 0..<64 {
            code_verifier += String(chars.randomElement()!)
        }
        client_id = clientid
        client_secret = secret
        
        let url = "https://accounts.google.com/o/oauth2/v2/auth?client_id=\(clientid)&redirect_uri=urn:ietf:wg:oauth:2.0:oob&response_type=code&scope=\(scope)&code_challenge_method=plain&code_challenge=\(code_verifier)"
        let authURL = URL(string: url)
        
        DispatchQueue.main.async {
            if let controller = UIApplication.topViewController() {
                let codeView = ViewControllerGoogleCode()
                codeView.onCancel = {
                    onFinish?(false)
                }
                codeView.onFinish = { code in
                    guard code != "" else {
                        onFinish?(false)
                        return
                    }
                    DispatchQueue.global().async {
                        self.customGetToken(oauthToken: code, onFinish: onFinish)
                    }
                }
                controller.navigationController?.pushViewController(codeView, animated: true)
            }
            else {
                onFinish?(false)
            }
            
            UIApplication.shared.open(authURL!)
        }
    }
    
    func customGetToken(oauthToken: String, onFinish: ((Bool) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "getToken(google:\(storageName ?? ""))")
        
        guard let clientid = self.getKeyChain(key: "\(self.storageName ?? "")_clientid"), let secret = self.getKeyChain(key: "\(self.storageName ?? "")_clientsecret") else {
            onFinish?(false)
            return
        }

        var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v4/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let post = "code=\(oauthToken)&redirect_uri=urn:ietf:wg:oauth:2.0:oob&client_id=\(clientid)&client_secret=\(secret)&grant_type=authorization_code&code_verifier=\(code_verifier)"
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
        guard let clientid = self.getKeyChain(key: "\(self.storageName ?? "")_clientid"), let secret = self.getKeyChain(key: "\(self.storageName ?? "")_clientsecret") else {
            super.refreshToken(onFinish: onFinish)
            return
        }
        
        os_log("%{public}@", log: log, type: .debug, "refreshToken(google:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v4/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let post = "refresh_token=\(refreshToken)&client_id=\(clientid)&client_secret=\(secret)&grant_type=refresh_token"
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

    override func refreshTokenBackground(session: URLSession, info: [String: Any], rToken: String, onFinish: ((String?)->Void)?) {
        guard client_id != "" && client_secret != "" else {
            super.refreshTokenBackground(session: session, info: info, rToken: rToken, onFinish: onFinish)
            return
        }
        
        os_log("%{public}@", log: log, type: .debug, "refreshToken(google:\(storageName ?? ""))")
        
        var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v4/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let post = "refresh_token=\(rToken)&client_id=\(client_id)&client_secret=\(client_secret)&grant_type=refresh_token"
        let postData = post.data(using: .ascii, allowLossyConversion: false)!
        let postLength = "\(postData.count)"
        request.setValue(postLength, forHTTPHeaderField: "Content-Length")
        request.httpBody = postData
        
        let downloadTask = session.downloadTask(with: request)
        let taskid = downloadTask.taskIdentifier
        self.task_upload[taskid] = info
        self.task_upload[taskid]?["refresh"] = rToken
        self.onFinsh_upload[taskid] = onFinish
        downloadTask.resume()
    }
}

class ViewControllerGoogleCode: UIViewController, UITextFieldDelegate {
    var textCode: UITextField!

    var onCancel: (()->Void)!
    var onFinish: ((String)->Void)!
    var done: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Enter code"
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        
        let stackView1 = UIStackView()
        stackView1.axis = .horizontal
        stackView1.alignment = .center
        stackView1.spacing = 20
        stackView.insertArrangedSubview(stackView1, at: 0)
        stackView1.widthAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.widthAnchor, multiplier: 1.0).isActive = true
        
        let label = UILabel()
        label.text = "Code"
        stackView1.insertArrangedSubview(label, at: 0)
        
        textCode = UITextField()
        textCode.borderStyle = .roundedRect
        textCode.delegate = self
        textCode.clearButtonMode = .whileEditing
        textCode.returnKeyType = .done
        textCode.placeholder = "code"
        stackView1.insertArrangedSubview(textCode, at: 1)
        let widthConstraint = textCode.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        widthConstraint.priority = .defaultHigh
        widthConstraint.isActive = true
        
        let stackView5 = UIStackView()
        stackView5.axis = .horizontal
        stackView5.alignment = .center
        stackView5.spacing = 20
        stackView.insertArrangedSubview(stackView5, at: 1)
        
        let button1 = UIButton(type: .system)
        button1.setTitle("Done", for: .normal)
        button1.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView5.insertArrangedSubview(button1, at: 0)
        
        let button2 = UIButton(type: .system)
        button2.setTitle("Cancel", for: .normal)
        button2.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView5.insertArrangedSubview(button2, at: 1)
    }
    
    @objc func buttonEvent(_ sender: UIButton) {
        if sender.currentTitle == "Done" {
            done = true
            onFinish(textCode.text ?? "")
        }
        else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    override func willMove(toParent parent: UIViewController?) {
        if parent == nil && !done {
            onCancel()
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        done = true
        onFinish(textCode.text ?? "")
        return true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if textCode.isFirstResponder {
            textCode.resignFirstResponder()
        }
    }

}

class ViewControllerGoogleCustom: UIViewController, UITextFieldDelegate, UIPickerViewDelegate, UIPickerViewDataSource {
    var textClientId: UITextField!
    var textSecret: UITextField!
    var stackView: UIStackView!
    var customizeId: Bool = false

    var onCancel: (()->Void)!
    var onFinish: ((String, String, String)->Void)!
    var done: Bool = false
    
    let scopes = ["drive","drive.readonly","drive.file","drive.appfolder","drive.metadata.readonly"]
    var scope = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Google ClientID"
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
        
        stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        let stackView3 = UIStackView()
        stackView3.axis = .horizontal
        stackView3.alignment = .center
        stackView3.spacing = 20
        stackView.insertArrangedSubview(stackView3, at: 0)
        
        let label3 = UILabel()
        label3.text = "Customize client"
        stackView3.insertArrangedSubview(label3, at: 0)
        
        let switchCustomize = UISwitch()
        switchCustomize.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
        customizeId = switchCustomize.isOn
        stackView3.insertArrangedSubview(switchCustomize, at: 1)

        let stackView1 = UIStackView()
        stackView1.axis = .horizontal
        stackView1.alignment = .center
        stackView1.spacing = 20
        stackView.insertArrangedSubview(stackView1, at: 1)
        stackView1.widthAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.widthAnchor, multiplier: 1.0).isActive = true

        let label = UILabel()
        label.text = "ClientID"
        stackView1.insertArrangedSubview(label, at: 0)
        
        textClientId = UITextField()
        textClientId.borderStyle = .roundedRect
        textClientId.delegate = self
        textClientId.clearButtonMode = .whileEditing
        textClientId.returnKeyType = .done
        textClientId.placeholder = "clientID"
        stackView1.insertArrangedSubview(textClientId, at: 1)
        let widthConstraint = textClientId.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        widthConstraint.priority = .defaultHigh
        widthConstraint.isActive = true

        (stackView.arrangedSubviews[1]).isHidden = !switchCustomize.isOn

        let stackView2 = UIStackView()
        stackView2.axis = .horizontal
        stackView2.alignment = .center
        stackView2.spacing = 20
        stackView.insertArrangedSubview(stackView2, at: 2)
        stackView2.widthAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.widthAnchor, multiplier: 1.0).isActive = true

        let label2 = UILabel()
        label2.text = "Secret"
        stackView2.insertArrangedSubview(label2, at: 0)
        
        textSecret = UITextField()
        textSecret.borderStyle = .roundedRect
        textSecret.delegate = self
        textSecret.clearButtonMode = .whileEditing
        textSecret.returnKeyType = .done
        textSecret.isSecureTextEntry = true
        textSecret.placeholder = "ClientSecret"
        stackView2.insertArrangedSubview(textSecret, at: 1)
        let widthConstraint2 = textSecret.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        widthConstraint2.priority = .defaultHigh
        widthConstraint2.isActive = true
        
        (stackView.arrangedSubviews[2]).isHidden = !switchCustomize.isOn

        let scopePicker = UIPickerView()
        scopePicker.dataSource = self
        scopePicker.delegate = self
        stackView.insertArrangedSubview(scopePicker, at: 3)

        (stackView.arrangedSubviews[3]).isHidden = !switchCustomize.isOn

        let stackView5 = UIStackView()
        stackView5.axis = .horizontal
        stackView5.alignment = .center
        stackView5.spacing = 20
        stackView.insertArrangedSubview(stackView5, at: 4)
        
        let button1 = UIButton(type: .system)
        button1.setTitle("Next", for: .normal)
        button1.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView5.insertArrangedSubview(button1, at: 0)
        
        let button2 = UIButton(type: .system)
        button2.setTitle("Cancel", for: .normal)
        button2.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView5.insertArrangedSubview(button2, at: 1)
    }
    
    @objc func buttonEvent(_ sender: UIButton) {
        if sender.currentTitle == "Next" {
            done = true
            if customizeId && scope != "" {
                onFinish(textClientId.text ?? "", textSecret.text ?? "", "https://www.googleapis.com/auth/\(scope)")
            }
            else {
                onFinish("", "", "")
            }
        }
        else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    override func willMove(toParent parent: UIViewController?) {
        if parent == nil && !done {
            onCancel()
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        done = true
        if customizeId && scope != "" {
            onFinish(textClientId.text ?? "", textSecret.text ?? "", "https://www.googleapis.com/auth/\(scope)")
        }
        else {
            onFinish("", "", "")
        }
        return true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if textClientId.isFirstResponder {
            textClientId.resignFirstResponder()
        }
        if textSecret.isFirstResponder {
            textSecret.resignFirstResponder()
        }
    }
    
    @objc func switchValueChanged(aSwitch: UISwitch) {
        (stackView.arrangedSubviews[1]).isHidden = !aSwitch.isOn
        (stackView.arrangedSubviews[2]).isHidden = !aSwitch.isOn
        (stackView.arrangedSubviews[3]).isHidden = !aSwitch.isOn
        customizeId = aSwitch.isOn
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return scopes.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return scopes[row]
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        scope = scopes[row]
    }
}

@available(iOS 13.0, *)
extension GoogleDriveStorage: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.topViewController()!.view.window!
    }
}

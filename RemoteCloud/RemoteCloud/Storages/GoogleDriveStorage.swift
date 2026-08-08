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
import SwiftUI
import CryptoKit
import GoogleSignIn

struct GoogleLoginView: View {
    let authContinuation: CheckedContinuation<Bool, Never>
    let scopes: [String]

    var body: some View {
        Color.clear
            .task {
                try? await Task.sleep(for: .seconds(1))
                Task { @MainActor in
                    do {
                        guard let rootViewController = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController else { return }
                        try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController, hint: nil, additionalScopes: scopes)
                        authContinuation.resume(returning: true)
                    } catch {
                        // Respond to any authorization errors.
                        print(error)
                        authContinuation.resume(returning: false)
                    }
                }
            }
    }
}

public class GoogleDriveStorage: NetworkStorage, URLSessionDataDelegate {

    public override func getStorageType() -> CloudStorages {
        return .GoogleDrive
    }

    let uploadSemaphore = Semaphore(value: 5)
    let scope = [
        "https://www.googleapis.com/auth/drive",
    ]
    var spaces = ""
    
    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .GoogleDrive)
        storageName = name
        rootName = "root"
    }
    
    override func isAuthorized() async -> Bool {
        GIDSignIn.sharedInstance.currentUser != nil
    }

    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        if await checkToken() {
            return true
        }
        if await isAuthorized() {
            return true
        }
        let authRet = await withCheckedContinuation { authContinuation in
            Task {
                let presentRet = await withCheckedContinuation { continuation in
                    callback(GoogleLoginView(authContinuation: authContinuation, scopes: scope), continuation)
                }
                guard presentRet else {
                    authContinuation.resume(returning: false)
                    return
                }
            }
        }
        return authRet
    }

    public override func logout() async {
        GIDSignIn.sharedInstance.signOut()
        await super.logout()
    }

    override func accessToken() async -> String {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            return ""
        }
        return currentUser.accessToken.tokenString
    }

    override func getRefreshToken() async -> String {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            return ""
        }
        return currentUser.refreshToken.tokenString
    }

    override func checkToken() async -> Bool {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            let task = Task { @MainActor in
                guard let rootViewController = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController else { return false }
                do {
                    try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController, hint: nil, additionalScopes: scope)
                }
                catch {
                    print(error)
                    return false
                }
                guard GIDSignIn.sharedInstance.currentUser != nil else {
                    return false
                }
                return true
            }
            return await task.value
        }
        do {
            try await currentUser.refreshTokensIfNeeded()
            return true
        }
        catch {
            print(error)
            return false
        }
    }
    
    func listFiles(q: String, pageToken: String, teamDrive: String? = nil) async -> [[String:Any]]? {
        let action = { [self] () async throws -> [[String:Any]]? in
            os_log("%{public}@", log: log, type: .debug, "listFiles(google:\(storageName ?? ""))")

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
            request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
            request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

            guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                throw RetryError.Retry
            }
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            guard let json = object as? [String: Any] else {
                throw RetryError.Retry
            }

            if let e = json["error"] {
                if let eobj = e as? [String: Any] {
                    if let ecode = eobj["code"] as? Int, ecode == 401 {
                        os_log("%{public}@", log: self.log, type: .debug, "Invalid token (google:\(storageName ?? ""))")
                        await tokenCache.clear()
                    }
                }
                print(e)
                throw RetryError.Retry
            }
            let nextPageToken = json["nextPageToken"] as? String ?? ""
            if nextPageToken != "" {
                let files = await listFiles(q: q, pageToken: nextPageToken, teamDrive: teamDrive)
                if var files = files {
                    if let newfiles = json["files"] as? [[String: Any]] {
                        files += newfiles
                    }
                    return files
                }
            }
            return json["files"] as? [[String: Any]]
        }
        do {
            if pageToken != "" {
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

    func listTeamdrives(q: String, pageToken: String) async -> [[String:Any]]? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "listTeamdrives(google:\(storageName ?? ""))")

                var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/drives?q=\(q)&pageToken=\(pageToken)")!)
                request.httpMethod = "GET"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard let json = object as? [String: Any] else {
                    throw RetryError.Retry
                }

                if let e = json["error"] {
                    if let eobj = e as? [String: Any] {
                        if let ecode = eobj["code"] as? Int, ecode == 401 {
                            os_log("%{public}@", log: self.log, type: .debug, "Invalid token (google:\(storageName ?? ""))")
                            await tokenCache.clear()
                        }
                    }
                    print(e)
                    throw RetryError.Retry
                }
                let nextPageToken = json["nextPageToken"] as? String ?? ""
                if nextPageToken != "" {
                    let files = await listTeamdrives(q: q, pageToken: nextPageToken)
                    if var files = files {
                        if let newfiles = json["drives"] as? [[String: Any]] {
                            files += newfiles
                        }
                        return files
                    }
                }
                return json["drives"] as? [[String: Any]]
            })
        }
        catch {
            return nil
        }
    }

    func storeItem(item: [String: Any], existingItem: RemoteData? = nil, parentFileId: String? = nil, parentPath: String? = nil, teamID: String? = nil, context: NSManagedObjectContext) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        
        guard let id = item["id"] as? String,
              let name = item["name"] as? String,
              let ctime = item["createdTime"] as? String,
              let mtime = item["modifiedTime"] as? String,
              let mimeType = item["mimeType"] as? String else {
            return
        }
        
        let isTrashed: Bool
        if let tBool = item["trashed"] as? Bool {
            isTrashed = tBool
        } else if let tInt = item["trashed"] as? Int {
            isTrashed = (tInt != 0)
        } else {
            isTrashed = false
        }
        
        let size = Int64(item["size"] as? String ?? "0") ?? 0
        let hashstr = item["md5Checksum"] as? String ?? ""
        
        let fixId: String = (teamID != nil) ? "\(teamID!) \(id)" : id
        
        if isTrashed {
            if let existing = existingItem {
                GoogleDriveStorage.cascadeDelete(item: existing, in: context)
            }
            return
        }
        
        let targetItem: RemoteData
        if let existing = existingItem {
            targetItem = existing
            targetItem.hashstr = nil
            targetItem.subinfo = nil
            targetItem.subid = nil
            targetItem.substart = 0
            targetItem.subend = 0
            targetItem.baseId = nil
            targetItem.baseStorage = nil
        } else {
            targetItem = RemoteData(context: context)
        }
        
        targetItem.storage = self.storageName
        targetItem.id = fixId
        targetItem.name = name
        let comp = name.components(separatedBy: ".")
        if comp.count >= 1 {
            targetItem.ext = comp.last!.lowercased()
        }
        targetItem.cdate = formatter.date(from: ctime)
        targetItem.mdate = formatter.date(from: mtime)
        targetItem.folder = mimeType == "application/vnd.google-apps.folder"
        targetItem.size = size
        targetItem.hashstr = hashstr
        
        targetItem.parent = (parentFileId == nil) ? targetItem.parent : parentFileId
        if parentFileId == "" {
            targetItem.path = "\(self.storageName ?? ""):/\(name)"
        } else {
            let pPath = (parentPath == nil) ? targetItem.path?.components(separatedBy: "/").dropLast().joined(separator: "/") : parentPath
            if let pPath = pPath {
                targetItem.path = "\(pPath)/\(name)"
            }
        }
    }
    
    func storeRootItems(context: NSManagedObjectContext) {
        let items = ["mydrive", "teamdrives"]
        let names = ["mydrive": "myDrive", "teamdrives": "teamDrives"]
        
        for id in items {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
            fetchRequest.fetchLimit = 1
            let existing = (try? context.fetch(fetchRequest))?.first
            
            let targetItem = existing ?? RemoteData(context: context)
            targetItem.storage = self.storageName
            targetItem.id = id
            targetItem.name = names[id]
            targetItem.ext = ""
            targetItem.cdate = nil
            targetItem.mdate = nil
            targetItem.folder = true
            targetItem.size = 0
            targetItem.hashstr = nil
            targetItem.parent = ""
            targetItem.path = "\(self.storageName ?? ""):/\(names[id]!)"
        }
        
        let fetchRequest1 = NSFetchRequest<RemoteData>(entityName: "RemoteData")
        fetchRequest1.predicate = NSPredicate(format: "parent == %@ && storage == %@", "", self.storageName ?? "")
        if let results = try? context.fetch(fetchRequest1) {
            for object in results {
                if !items.contains(object.id ?? "") {
                    GoogleDriveStorage.cascadeDelete(item: object, in: context)
                }
            }
        }
    }
    
    func storeTeamDriveItem(item: [String: Any], existingItem: RemoteData? = nil, context: NSManagedObjectContext) {
        guard let id = item["id"] as? String, let name = item["name"] as? String else { return }
        
        let targetItem: RemoteData
        if let existing = existingItem {
            targetItem = existing
        } else {
            targetItem = RemoteData(context: context)
        }
        
        targetItem.storage = self.storageName
        targetItem.id = "\(id) \(id)"
        targetItem.name = name
        targetItem.ext = ""
        targetItem.cdate = nil
        targetItem.mdate = nil
        targetItem.folder = true
        targetItem.size = 0
        targetItem.hashstr = nil
        targetItem.parent = "teamdrives"
        targetItem.path = "\(self.storageName ?? ""):/teamDrives/\(name)"
    }
    
    override func listChildren(fileId: String, path: String) async {
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        
        var networkItems: [[String: Any]]? = nil
        var isTeamDriveList = false
        
        if fileId == "" {
            await viewContext.perform {
                self.storeRootItems(context: viewContext)
                try? viewContext.save()
            }
            return
        } else if fileId == "teamdrives" {
            networkItems = await listTeamdrives(q: "", pageToken: "")
            isTeamDriveList = true
        } else if spaces == "appDataFolder" {
            let fixFileId = (fileId == "") ? rootName : fileId
            networkItems = await listFiles(q: "'\(fixFileId)'+in+parents", pageToken: "")
        } else if fileId.contains(" ") {
            let comp = fileId.components(separatedBy: " ")
            let teamId = comp[0]
            let fixFileId = comp[1]
            networkItems = await listFiles(q: "'\(fixFileId)'+in+parents", pageToken: "", teamDrive: teamId)
        } else {
            let fixFileId = (fileId == "mydrive") ? rootName : fileId
            networkItems = await listFiles(q: "'\(fixFileId)'+in+parents", pageToken: "")
        }
        
        guard let items = networkItems else { return }
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", fileId, storage)
            let existingItems = (try? viewContext.fetch(fetchRequest)) ?? []
            
            var existingDict = [String: RemoteData]()
            for item in existingItems {
                if let id = item.id {
                    existingDict[id] = item
                }
            }
            
            if isTeamDriveList {
                for item in items {
                    if let id = item["id"] as? String {
                        let fixId = "\(id) \(id)"
                        let existing = existingDict.removeValue(forKey: fixId)
                        self.storeTeamDriveItem(item: item, existingItem: existing, context: viewContext)
                    }
                }
            } else {
                let teamID: String? = fileId.contains(" ") ? fileId.components(separatedBy: " ")[0] : nil
                for item in items {
                    if let id = item["id"] as? String {
                        let fixId = (teamID != nil) ? "\(teamID!) \(id)" : id
                        let existing = existingDict.removeValue(forKey: fixId)
                        self.storeItem(item: item, existingItem: existing, parentFileId: fileId, parentPath: path, teamID: teamID, context: viewContext)
                    }
                }
            }
            
            for (_, orphan) in existingDict {
                GoogleDriveStorage.cascadeDelete(item: orphan, in: viewContext)
            }
            
            try? viewContext.save()
        }
    }
    
    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil) async throws -> Data? {
        if let cache = await CloudFactory.shared.cache.getCache(storage: storageName!, id: fileId, offset: start ?? 0, size: length ?? -1) {
            if let data = try? Data(contentsOf: cache) {
                os_log("%{public}@", log: log, type: .debug, "hit cache(google:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                return data
            }
        }
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "readFile(google:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")

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
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
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
    
    func createDrive(newname: String, requestId: String? = nil) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "createDrive(google:\(storageName ?? "") \(newname)")
                
                let requestId_new: String
                if let requestId_old = requestId {
                    requestId_new = requestId_old
                }
                else {
                    requestId_new = UUID().uuidString
                }
                var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/drives?requestId=\(requestId_new)")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                
                let json: [String: Any] = ["name": newname]
                let postData = try? JSONSerialization.data(withJSONObject: json)
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
                guard let id = json["id"] as? String else {
                    throw RetryError.Retry
                }
                
                let viewContext = CloudFactory.shared.data.backgroundContext
                await viewContext.perform {
                    self.storeTeamDriveItem(item: json, context: viewContext)
                    try? viewContext.save()
                }
                return id
            })
        }
        catch {
            return nil
        }
    }
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
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
            return nil
        }
        if fixParentId == "teamdrives" {
            return await createDrive(newname: newname)
        }
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "makeFolder(google:\(storageName ?? "") \(parentId) \(newname)")

                var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?supportsTeamDrives=true")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

                let json: [String: Any] = ["name": newname, "parents": [fixParentId], "mimeType": "application/vnd.google-apps.folder"]
                let postData = try? JSONSerialization.data(withJSONObject: json)
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
                guard let id = json["id"] as? String else {
                    throw RetryError.Retry
                }
                let fixId: String = (teamID != nil) ? "\(teamID!) \(id)" : id
                
                if await getFile(fileId: fixId, parentId: parentId, parentPath: parentPath) {
                    return fixId
                }
                return nil
            })
        }
        catch {
            return nil
        }
    }

    func getFile(fileId: String, parentId: String? = nil, parentPath: String? = nil, objectID: NSManagedObjectID? = nil) async -> Bool {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "getFile(google:\(storageName ?? "") \(fileId)")
                let fields = "id,mimeType,name,trashed,parents,viewedByMeTime,modifiedTime,createdTime,md5Checksum,size"
                
                let fixFileId: String
                let teamID: String?
                if fileId.contains(" ") {
                    let comp = fileId.components(separatedBy: " ")
                    teamID = comp[0]
                    fixFileId = comp[1]
                }
                else {
                    teamID = nil
                    fixFileId = fileId
                }
                
                var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fixFileId)?fields=\(fields)&supportsTeamDrives=true")!)
                request.httpMethod = "GET"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
                
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
                
                let viewContext = CloudFactory.shared.data.backgroundContext
                await viewContext.perform {
                    var existing: RemoteData? = nil
                    if let objID = objectID {
                        existing = try? viewContext.existingObject(with: objID) as? RemoteData
                    } else {
                        let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                        fetchRequest.fetchLimit = 1
                        existing = (try? viewContext.fetch(fetchRequest))?.first
                    }
                    
                    self.storeItem(item: json, existingItem: existing, parentFileId: parentId, parentPath: parentPath, teamID: teamID, context: viewContext)
                    try? viewContext.save()
                }
                return true
            })
        }
        catch {
            return false
        }
    }
    
    func updateFile(fileId: String, metadata: [String: Any], objectID: NSManagedObjectID? = nil) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "updateFile(google:\(storageName ?? "") \(fileId)")
                
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
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
                request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                let postData = try? JSONSerialization.data(withJSONObject: metadata)
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
                guard let id = json["id"] as? String else {
                    throw RetryError.Retry
                }
                let fixId: String = fileId.contains(" ") ? "\(fileId.components(separatedBy: " ")[0]) \(id)" : id
                
                try? await Task.sleep(for: .seconds(1))
                if await getFile(fileId: fixId, objectID: objectID) {
                    return fixId
                }
                return nil
            })
        }
        catch {
            return nil
        }
    }
    
    override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        if toParentId == fromParentId {
            return nil
        }
        var targetId = fileId
        if fileId.contains(" ") {
            // teamdrive
            let comp = fileId.components(separatedBy: " ")
            let driveId = comp[0]
            let fixFileId = comp[1]
            if driveId == fixFileId {
                return nil
            }
            targetId = fixFileId
        }
        do {
            return try await callWithRetry(action: { [self] in
                let toParentFix: String = toParentId.contains(" ") ? toParentId.components(separatedBy: " ")[1] : ((toParentId == "") ? rootName : toParentId)
                let formParentFix: String = fromParentId.contains(" ") ? fromParentId.components(separatedBy: " ")[1] : ((fromParentId == "") ? rootName : fromParentId)
                
                var toParentPath: String?
                var targetObjectID: NSManagedObjectID? = nil
                let viewContext = CloudFactory.shared.data.backgroundContext
                let storage = storageName ?? ""
                
                await viewContext.perform {
                    let fetchRequest1 = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                    fetchRequest1.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                    fetchRequest1.fetchLimit = 1
                    targetObjectID = (try? viewContext.fetch(fetchRequest1))?.first?.objectID
                    
                    if toParentId != "" {
                        let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", toParentId, storage)
                        fetchRequest.fetchLimit = 1
                        toParentPath = (try? viewContext.fetch(fetchRequest))?.first?.path
                    }
                }
                os_log("%{public}@", log: log, type: .debug, "moveItem(google:\(storageName ?? "") \(formParentFix)->\(toParentFix)")
                
                var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(targetId)?addParents=\(toParentFix)&removeParents=\(formParentFix)&supportsTeamDrives=true")!)
                request.httpMethod = "PATCH"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
                request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                let json: [String: Any] = [:]
                let postData = try? JSONSerialization.data(withJSONObject: json)
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
                guard let id = json["id"] as? String else {
                    throw RetryError.Retry
                }
                let fixId: String = fileId.contains(" ") ? "\(fileId.components(separatedBy: " ")[0]) \(id)" : id
                
                if await getFile(fileId: fixId, parentId: toParentId, parentPath: toParentPath, objectID: targetObjectID) {
                    await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
                    return fixId
                }
                return nil
            })
        }
        catch {
            return nil
        }
    }
    
    func deleteDrive(driveId: String) async -> Bool {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "deleteDrive(google:\(storageName ?? "") \(driveId)")
                
                var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/drives/\(driveId)")!)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                if data.count == 0 {
                    return await CloudFactory.shared.data.persistentContainer.performBackgroundTask { context in
                        let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", "\(driveId) \(driveId)", self.storageName ?? "")
                        fetchRequest.fetchLimit = 1
                        if let existing = (try? context.fetch(fetchRequest))?.first {
                            GoogleDriveStorage.cascadeDelete(item: existing, in: context)
                        }
                        try? context.save()
                        return true
                    }
                }
                return false
            })
        }
        catch {
            return false
        }
    }
    
    override func deleteItem(fileId: String) async -> Bool {
        if fileId == "" || fileId == "mydrive" || fileId == "teamdrives" {
            return false
        }
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        var targetObjectID: NSManagedObjectID? = nil
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
            fetchRequest.fetchLimit = 1
            targetObjectID = (try? viewContext.fetch(fetchRequest))?.first?.objectID
        }
        
        if fileId.contains(" ") {
            let comp = fileId.components(separatedBy: " ")
            let driveId = comp[0]
            let fixFileId = comp[1]
            if driveId == fixFileId {
                guard await deleteDrive(driveId: driveId) else {
                    return false
                }
                await viewContext.perform {
                    if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                        GoogleDriveStorage.cascadeDelete(item: existing, in: viewContext)
                    }
                    try? viewContext.save()
                }
                return true
            }
        }
        
        let json: [String: Any] = ["trashed": true]
        guard let _ = await updateFile(fileId: fileId, metadata: json, objectID: targetObjectID) else {
            return false
        }
        
        await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
        return true
    }
    
    func updateDrive(driveId: String, metadata: [String: Any], objectID: NSManagedObjectID? = nil) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "updateDrive(google:\(storageName ?? "") \(driveId)")
                
                var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/drives/\(driveId)")!)
                request.httpMethod = "PATCH"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
                request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                let postData = try? JSONSerialization.data(withJSONObject: metadata)
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
                guard let id = json["id"] as? String else {
                    throw RetryError.Retry
                }
                let viewContext = CloudFactory.shared.data.backgroundContext
                await viewContext.perform {
                    var existing: RemoteData? = nil
                    if let objID = objectID {
                        existing = try? viewContext.existingObject(with: objID) as? RemoteData
                    } else {
                        let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", "\(driveId) \(driveId)", self.storageName ?? "")
                        fetchRequest.fetchLimit = 1
                        existing = (try? viewContext.fetch(fetchRequest))?.first
                    }
                    self.storeTeamDriveItem(item: json, existingItem: existing, context: viewContext)
                    try? viewContext.save()
                }
                return id
            })
        }
        catch {
            return nil
        }
    }
    
    override func renameItem(fileId: String, newname: String) async -> String? {
        if fileId == "" || fileId == "mydrive" || fileId == "teamdrives" {
            return nil
        }
        
        var targetObjectID: NSManagedObjectID? = nil
        let viewContext = CloudFactory.shared.data.backgroundContext
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
            fetchRequest.fetchLimit = 1
            targetObjectID = (try? viewContext.fetch(fetchRequest))?.first?.objectID
        }
        
        let json: [String: Any] = ["name": newname]
        if fileId.contains(" ") {
            let comp = fileId.components(separatedBy: " ")
            let driveId = comp[0]
            let fixFileId = comp[1]
            if driveId == fixFileId {
                let newid = await updateDrive(driveId: driveId, metadata: json, objectID: targetObjectID)
                if newid != nil {
                    await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
                }
                return newid
            }
        }
        let newid = await updateFile(fileId: fileId, metadata: json, objectID: targetObjectID)
        if newid != nil {
            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
        }
        return newid
    }
    
    override func changeTime(fileId: String, newdate: Date) async -> String? {
        if fileId == "" || fileId == "mydrive" || fileId == "teamdrives" {
            return nil
        }
        if fileId.contains(" ") {
            let comp = fileId.components(separatedBy: " ")
            let driveId = comp[0]
            let fixFileId = comp[1]
            if driveId == fixFileId {
                return nil
            }
        }
        
        var targetObjectID: NSManagedObjectID? = nil
        let viewContext = CloudFactory.shared.data.backgroundContext
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
            fetchRequest.fetchLimit = 1
            targetObjectID = (try? viewContext.fetch(fetchRequest))?.first?.objectID
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        let json: [String: Any] = ["modifiedTime": formatter.string(from: newdate)]
        return await updateFile(fileId: fileId, metadata: json, objectID: targetObjectID)
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
        
        if parentId == "teamdrives" {
            return nil
        }
        if rootName == "root" && parentId == "" {
            return nil
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
        if fixParentId != rootName {
            parentPath = await getParentPath(parentId: parentId) ?? parentPath
        }
        
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "uploadFile(google:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")
                
                let handle = try FileHandle(forReadingFrom: target)
                defer {
                    try? handle.close()
                }
                
                let attr = try FileManager.default.attributesOfItem(atPath: target.path(percentEncoded: false))
                let fileSize = attr[.size] as! UInt64
                try await progress?(0, Int64(fileSize))
                
                var request: URLRequest = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsTeamDrives=true")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
                request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
                request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                let json: [String: Any] = [
                    "name": uploadname,
                    "parents": [fixParentId]
                ]
                let postData = try? JSONSerialization.data(withJSONObject: json)
                request.httpBody = postData
                
                guard let (_, response) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    print(response)
                    throw RetryError.Retry
                }
                guard let location = httpResponse.allHeaderFields["Location"] as? String else {
                    throw RetryError.Retry
                }
                
                let uploadUrl = URL(string: location)!
                var request2: URLRequest = URLRequest(url: uploadUrl)
                request2.httpMethod = "PUT"
                
                await uploadProgressManeger.setCallback(url: uploadUrl, total: Int64(fileSize), callback: progress)
                defer {
                    Task { await uploadProgressManeger.removeCallback(url: uploadUrl) }
                }
                
                var offset = 0
                var eof = false
                while !eof {
                    guard let srcData = try handle.read(upToCount: 32*1024*1024) else {
                        throw RetryError.Retry
                    }
                    if srcData.count < 32*1024*1024 {
                        eof = true
                    }
                    request2.setValue("bytes \(offset)-\(offset+srcData.count-1)/\(fileSize)", forHTTPHeaderField: "Content-Range")
                    await uploadProgressManeger.setOffset(url: uploadUrl, offset: Int64(offset))
                    offset += srcData.count
                    
                    guard let (data2, response2) = try? await URLSession.shared.upload(for: request2, from: srcData, delegate: self) else {
                        throw RetryError.Retry
                    }
                    guard let httpResponse = response2 as? HTTPURLResponse else {
                        print(response2)
                        throw RetryError.Retry
                    }
                    switch httpResponse.statusCode {
                    case 200...201:
                        print(String(data: data2, encoding: .utf8) ?? "")
                        guard let object = try? JSONSerialization.jsonObject(with: data2, options: []) as? [String: Any] else {
                            throw RetryError.Retry
                        }
                        guard let id = object["id"] as? String else {
                            throw RetryError.Retry
                        }
                        if await getFile(fileId: id, parentId: parentId, parentPath: parentPath) {
                            try await progress?(Int64(fileSize), Int64(fileSize))
                            return id
                        }
                    case 308:
                        guard let range = httpResponse.allHeaderFields["Range"] as? String else {
                            throw RetryError.Retry
                        }
                        print("308 resume \(range)")
                        if Int(range.replacingOccurrences(of: #"bytes=(\d+)-\d+"#, with: "$1", options: .regularExpression)) ?? -1 != 0 {
                            throw RetryError.Retry
                        }
                        let reqOffset = (Int(range.replacingOccurrences(of: #"bytes=\d+-(\d+)"#, with: "$1", options: .regularExpression)) ?? -1) + 1
                        
                        print(reqOffset)
                        
                        if offset != reqOffset {
                            try handle.seek(toOffset: UInt64(reqOffset))
                            offset = reqOffset
                        }
                        eof = false
                        continue
                    case 404:
                        print("404 start from begining")
                        
                        try handle.seek(toOffset: 0)
                        offset = 0
                        eof = false
                        continue
                        
                    default:
                        print("\(httpResponse.statusCode) resume request")
                        print("\(httpResponse.allHeaderFields)")
                        
                        try handle.seek(toOffset: 0)
                        offset = 0
                        eof = false
                        continue
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
    
    public override func targetIsMovable(srcFileId: String, dstFileId: String) async -> Bool {
        if srcFileId == "" || srcFileId == "mydrive" || srcFileId == "teamdrives" {
            return false
        }
        if srcFileId.contains(" "), dstFileId.contains(" ") {
            let scomp = srcFileId.components(separatedBy: " ")
            let dcomp = dstFileId.components(separatedBy: " ")
            return scomp[0] == dcomp[0]
        }
        if !srcFileId.contains(" "), !dstFileId.contains(" ") {
            return true
        }
        return false
    }
}

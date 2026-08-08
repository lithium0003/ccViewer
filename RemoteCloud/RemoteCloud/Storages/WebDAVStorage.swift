//
//  WebDAVStorage.swift
//  RemoteCloud
//
//  Created by rei8 on 2019/11/22.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import os.log
import CoreData
import SwiftUI
import AuthenticationServices

struct WebDAVLoginView: View {
    let authContinuation: CheckedContinuation<Bool, Never>
    let callback: (String, String, String) async -> Bool
    let onDismiss: () -> Void
    @State var ok = false

    @State var textURI = ""
    @State var textUser = ""
    @State var textPass = ""

    var body: some View {
        ZStack {
            Form {
                Section("URL") {
                    TextField("https://localhost/webdav/", text: $textURI)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section("Username") {
                    TextField("(Optional)", text: $textUser)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section("Password") {
                    SecureField("(Optional)", text: $textPass)
                }
                Button("Connect") {
                    if textURI.isEmpty {
                        return
                    }
                    ok = true
                    Task {
                        if await callback(textURI, textUser, textPass) {
                            authContinuation.resume(returning: true)
                        }
                        else {
                            authContinuation.resume(returning: false)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(ok)

            if ok {
                ProgressView()
                    .padding(30)
                    .background {
                        Color(uiColor: .systemBackground)
                            .opacity(0.9)
                    }
                    .scaleEffect(3)
                    .cornerRadius(10)
            }
        }
        .onDisappear {
            if ok { return }
            onDismiss()
        }
    }
}

public class WebDAVStorage: NetworkStorage, URLSessionTaskDelegate, URLSessionDataDelegate {
    
    public override func getStorageType() -> CloudStorages {
        return .WebDAV
    }

    var cache_accessUsername = ""
    func accessUsername() async -> String {
        if cache_accessUsername != "" {
            return cache_accessUsername
        }
        if let name = storageName {
            if let user = await getKeyChain(key: "\(name)_accessUsername") {
                cache_accessUsername = user
            }
            return cache_accessUsername
        }
        else {
            return ""
        }
    }

    var cache_accessPassword = ""
    func accessPassword() async -> String {
        if cache_accessPassword != "" {
            return cache_accessPassword
        }
        if let name = storageName {
            if let pass = await getKeyChain(key: "\(name)_accessPassword") {
                cache_accessPassword = pass
            }
            return cache_accessPassword
        }
        else {
            return ""
        }
    }

    var cache_accessURI = ""
    func accessURI() async -> String {
        if cache_accessURI != "" {
            return cache_accessURI
        }
        if let name = storageName {
            if let uri = await getKeyChain(key: "\(name)_accessURI") {
                cache_accessURI = uri
            }
            return cache_accessURI
        }
        else {
            return ""
        }
    }
    
    var acceptRange: Bool?
    let checkSemaphore = Semaphore(value: 1)
    let uploadSemaphore = Semaphore(value: 5)

    actor ReadingChecker {
        var readinglist: [URL] = []
        
        func isReading(url: URL) -> Bool {
            return readinglist.contains(url)
        }
        
        func start(url: URL) {
            readinglist.append(url)
        }
        
        func finish(url: URL) {
            readinglist.removeAll(where: { $0 == url })
        }
    }
    let wholeReading = ReadingChecker()
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let authMethod = challenge.protectionSpace.authenticationMethod
        guard authMethod == NSURLAuthenticationMethodHTTPBasic || authMethod == NSURLAuthenticationMethodHTTPDigest else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        guard challenge.previousFailureCount < 3 else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        let credential = URLCredential(user: cache_accessUsername, password: cache_accessPassword, persistence: .forSession)
        completionHandler(.useCredential, credential)
    }
    
    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .WebDAV)
        storageName = name
    }

    func checkServer(uri: String) async throws -> Bool {
        guard let url = URL(string: uri) else {
            return false
        }
        _ = await accessUsername()
        _ = await accessPassword()
        
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        
        let (_, response) = try await URLSession.shared.data(for: request, delegate: self)
        guard let response = response as? HTTPURLResponse else {
            return false
        }
        
        guard (200...299).contains(response.statusCode) else {
            print("HTTP Status: \(response.statusCode)")
            return false
        }
        
        return true
    }

    func authCallcack(_ uri: String, _ user: String, _ pass: String) async -> Bool {
        let _ = await setKeyChain(key: "\(storageName ?? "")_accessURI", value: uri)
        let _ = await setKeyChain(key: "\(storageName ?? "")_accessUsername", value: user)
        let _ = await setKeyChain(key: "\(storageName ?? "")_accessPassword", value: pass)
        do {
            return try await checkServer(uri: uri)
        }
        catch {
            print(error)
            return false
        }
    }

    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        let authRet = await withCheckedContinuation { authContinuation in
            Task {
                let presentRet = await withCheckedContinuation { continuation in
                    callback(WebDAVLoginView(authContinuation: authContinuation, callback: authCallcack, onDismiss: {
                        authContinuation.resume(returning: false)
                    }), continuation)
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
        if let name = storageName {
            let _ = await delKeyChain(key: "\(name)_accessURI")
            let _ = await delKeyChain(key: "\(name)_accessUsername")
            let _ = await delKeyChain(key: "\(name)_accessPassword")
        }
        await super.logout()
    }

    override func checkToken() async -> Bool {
        _ = await accessUsername()
        _ = await accessPassword()
        return true
    }

    func storeItem(item: [String: Any], existingItem: RemoteData? = nil, parentFileId: String? = nil, parentPath: String? = nil, accessUriPath: String?, context: NSManagedObjectContext) {
        guard let id = item["href"] as? String else { return }
        
        if id.removingPercentEncoding == parentFileId?.removingPercentEncoding { return }
        if let idURL = URL(string: id), let apath = accessUriPath, idURL.path == apath { return }
        
        guard let propstat = item["propstat"] as? [String: Any], let prop = propstat["prop"] as? [String: String] else { return }
        
        let name: String
        if let dispname = prop["displayname"] {
            name = dispname
        } else {
            guard let idURL = URL(string: id), let orgname = idURL.lastPathComponent.removingPercentEncoding else { return }
            name = orgname
        }
        
        let ctime = prop["creationdate"] ?? prop["Win32CreationTime"]
        let mtime = prop["lastmodified"] ?? prop["getlastmodified"] ?? prop["Win32LastModifiedTime"]
        let size = Int64(prop["getcontentlength"] ?? "0")
        let folder = prop["resourcetype"] == "collection"
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let formatter2 = ISO8601DateFormatter()
        
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
        targetItem.id = id
        targetItem.name = name
        
        let comp = name.components(separatedBy: ".")
        if comp.count >= 1 {
            targetItem.ext = comp.last!.lowercased()
        } else {
            targetItem.ext = ""
        }
        
        targetItem.cdate = formatter.date(from: ctime ?? "") ?? formatter2.date(from: ctime ?? "")
        targetItem.mdate = formatter.date(from: mtime ?? "") ?? formatter2.date(from: mtime ?? "")
        targetItem.folder = folder
        targetItem.size = size ?? 0
        
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
    
    class DAVcollectionParser: NSObject, XMLParserDelegate {
        var continuation: CheckedContinuation<[[String:Any]]?, Never>?
        
        var response: [[String: Any]] = []
        var curElement: [String] = []
        var curProp: [String: Any] = [:]
        var prop: [String: String] = [:]
        
        func parserDidStartDocument(_ parser: XMLParser) {
            print("parser Start")
        }
        
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            switch elementName {
            case let str where str.hasSuffix(":multistatus"):
                print("start")
            case let str where str.hasSuffix(":response"):
                response.append([:])
            case let str where str.hasSuffix(":propstat"):
                curProp = [:]
            case let str where str.hasSuffix(":prop"):
                prop = [:]
            case let str where str.hasSuffix(":resourcetype"):
                prop["resourcetype"] = ""
            case let str where str.hasSuffix(":collection"):
                prop["resourcetype"] = "collection"
            default:
                break
            }
            curElement.append(elementName)
        }
        
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            //print(string)
            switch curElement.last {
            case let str where str?.hasSuffix(":href") ?? false:
                response[response.count-1]["href"] = (response[response.count-1]["href"] as? String ?? "") + string
            case let str where str?.hasSuffix(":status") ?? false:
                curProp["status"] = string
            case let str where str?.hasSuffix(":getlastmodified") ?? false:
                prop["getlastmodified"] = string
            case let str where str?.hasSuffix(":lastmodified") ?? false:
                prop["lastmodified"] = string
            case let str where str?.hasSuffix(":displayname") ?? false:
                prop["displayname"] = (prop["displayname"] ?? "") + string
            case let str where str?.hasSuffix(":getcontentlength") ?? false:
                prop["getcontentlength"] = string
            case let str where str?.hasSuffix(":creationdate") ?? false:
                prop["creationdate"] = string
            case let str where str?.hasSuffix(":Win32CreationTime") ?? false:
                prop["Win32CreationTime"] = string
            case let str where str?.hasSuffix(":Win32LastModifiedTime") ?? false:
                prop["Win32LastModifiedTime"] = string
            default:
                break
            }
        }
        
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case let str where str.hasSuffix(":multistatus"):
                print("end")
            case let str where str.hasSuffix(":propstat"):
                response[response.count-1]["propstat"] = curProp
            case let str where str.hasSuffix(":prop"):
                curProp["prop"] = prop
            default:
                break
            }
            curElement = curElement.dropLast()
        }
        
        func parserDidEndDocument(_ parser: XMLParser) {
            print("parser End")
            continuation?.resume(returning: response)
        }
        
        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
            print(parseError.localizedDescription)
            continuation?.resume(returning: nil)
        }
    }

    func listFolder(path: String) async -> [[String:Any]]? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "listFolder(WebDAV:\(storageName ?? ""))")

                var request: URLRequest
                guard var url = await URL(string: accessURI()) else {
                    return nil
                }
                if path != "" {
                    guard let pathURL = URL(string: path) else {
                        return nil
                    }
                    if pathURL.host != nil {
                        url = pathURL
                    }
                    else {
                        var allowedCharacterSet = CharacterSet.alphanumerics
                        allowedCharacterSet.insert(charactersIn: "-._~")
                        let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                        let p2: String
                        if p.first == "/" {
                            p2 = String(p.joined(separator: "/").dropFirst())
                        }
                        else {
                            p2 = p.joined(separator: "/")
                        }
                        guard let u = URL(string: p2, relativeTo: url) else {
                            return nil
                        }
                        url = u
                    }
                }
                //print(url)
                request = URLRequest(url: url)

                request.httpMethod = "PROPFIND"
                request.setValue("1", forHTTPHeaderField: "Depth")
                request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
                
                let reqStr = [
                    "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                    "<D:propfind xmlns:D=\"DAV:\">",
                    "<D:allprop/>",
                    "</D:propfind>",
                ].joined(separator: "\r\n")+"\r\n"
                request.httpBody = reqStr.data(using: .utf8)
                
                guard let (data, _) = try? await URLSession.shared.data(for: request, delegate: self) else {
                    throw RetryError.Retry
                }
                return await withCheckedContinuation { continuation in
                    let parser: XMLParser? = XMLParser(data: data)
                    let dav = DAVcollectionParser()
                    dav.continuation = continuation
                    parser?.delegate = dav
                    parser?.parse()
                }
            })
        }
        catch {
            return nil
        }
    }

    override func listChildren(fileId: String, path: String) async {
        guard let items = await listFolder(path: fileId) else { return }
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        let accessUriStr = await accessURI()
        let accessUriPath = URL(string: accessUriStr)?.path
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", fileId, storage)
            let existingItems = (try? viewContext.fetch(fetchRequest)) ?? []
            
            var existingDict = [String: RemoteData]()
            for item in existingItems {
                if let id = item.id { existingDict[id] = item }
            }
            
            for item in items {
                if let id = item["href"] as? String {
                    let existing = existingDict.removeValue(forKey: id)
                    self.storeItem(item: item, existingItem: existing, parentFileId: fileId, parentPath: path, accessUriPath: accessUriPath, context: viewContext)
                }
            }
            
            for (_, orphan) in existingDict {
                WebDAVStorage.cascadeDelete(item: orphan, in: viewContext)
            }
            try? viewContext.save()
        }
    }
    
    func checkAcceptRange(fileId: String) async {
        if acceptRange != nil { return }
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "checkAcceptRange(WebDAV:\(storageName ?? "") \(fileId)")
                
                var request: URLRequest
                guard var url = await URL(string: accessURI()) else { return }
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else { return }
                    if pathURL.host != nil {
                        url = pathURL
                    } else {
                        var allowedCharacterSet = CharacterSet.alphanumerics
                        allowedCharacterSet.insert(charactersIn: "-._~")
                        let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                        let p2: String = p.first == "/" ? String(p.joined(separator: "/").dropFirst()) : p.joined(separator: "/")
                        guard let u = URL(string: p2, relativeTo: url) else { return }
                        url = u
                    }
                }
                
                request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                
                guard let (_, response) = try? await URLSession.shared.data(for: request, delegate: self),
                      let httpResponse = response as? HTTPURLResponse else {
                    throw RetryError.Retry
                }
                guard httpResponse.statusCode == 200 else {
                    throw RetryError.Retry
                }
                guard let accept = httpResponse.allHeaderFields["Accept-Ranges"] as? String ?? httpResponse.allHeaderFields["accept-ranges"] as? String else {
                    acceptRange = false
                    return
                }
                acceptRange = accept.lowercased().contains("bytes")
            }, semaphore: checkSemaphore, maxCall: 1)
        }
        catch {
            acceptRange = false
            return
        }
    }
    
    func readRangeRead(fileId: String, start: Int64? = nil, length: Int64? = nil) async throws -> Data? {
        if let cache = await CloudFactory.shared.cache.getCache(storage: storageName!, id: fileId, offset: start ?? 0, size: length ?? -1) {
            if let data = try? Data(contentsOf: cache) {
                os_log("%{public}@", log: log, type: .debug, "hit cache(WebDAV:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                return data
            }
        }
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "readFile(WebDAV:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                
                var request: URLRequest
                guard var url = await URL(string: accessURI()) else { return nil }
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else { return nil }
                    if pathURL.host != nil {
                        url = pathURL
                    } else {
                        var allowedCharacterSet = CharacterSet.alphanumerics
                        allowedCharacterSet.insert(charactersIn: "-._~")
                        let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                        let p2: String = p.first == "/" ? String(p.joined(separator: "/").dropFirst()) : p.joined(separator: "/")
                        guard let u = URL(string: p2, relativeTo: url) else { return nil }
                        url = u
                    }
                }
                
                request = URLRequest(url: url)
                let s = start ?? 0
                if length == nil {
                    request.setValue("bytes=\(s)-", forHTTPHeaderField: "Range")
                } else {
                    request.setValue("bytes=\(s)-\(s+length!-1)", forHTTPHeaderField: "Range")
                }
                
                guard let (data, _) = try? await URLSession.shared.data(for: request, delegate: self) else {
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
    
    func readWholeRead(fileId: String, start: Int64? = nil, length: Int64? = nil) async throws -> Data? {
        if let data = await CloudFactory.shared.cache.getPartialFile(storage: storageName!, id: fileId, offset: start ?? 0, size: length ?? -1) {
            os_log("%{public}@", log: log, type: .debug, "hit cache(WebDAV:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
            return data
        }
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "readFile(WebDAV:\(storageName ?? "") \(fileId) whole read \(start ?? 0) \(length ?? -1)")
                
                guard var url = await URL(string: accessURI()) else { return nil }
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else { return nil }
                    if pathURL.host != nil {
                        url = pathURL
                    } else {
                        var allowedCharacterSet = CharacterSet.alphanumerics
                        allowedCharacterSet.insert(charactersIn: "-._~")
                        let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                        let p2: String = p.first == "/" ? String(p.joined(separator: "/").dropFirst()) : p.joined(separator: "/")
                        guard let u = URL(string: p2, relativeTo: url) else { return nil }
                        url = u
                    }
                }
                
                let request = URLRequest(url: url)
                if await wholeReading.isReading(url: url) {
                    try await Task.sleep(for: .seconds(1))
                    throw RetryError.Retry
                }
                
                do {
                    return try await withThrowingTaskGroup(of: Data?.self) { group in
                        group.addTask { [self] in
                            guard let (data, _) = try? await URLSession.shared.data(for: request, delegate: self) else {
                                throw RetryError.Retry
                            }
                            await CloudFactory.shared.cache.saveFile(storage: self.storageName!, id: fileId, data: data)
                            let s = Int(start ?? 0)
                            if let len = length, s+Int(len) < data.count {
                                return data.subdata(in: s..<(s+Int(len)))
                            } else {
                                return data.subdata(in: s..<data.count)
                            }
                        }
                        group.addTask {
                            try await Task.sleep(for: .seconds(30))
                            throw CancellationError()
                        }
                        let d = try await group.next()!
                        group.cancelAll()
                        return d
                    }
                }
                catch RetryError.Retry {
                    throw RetryError.Retry
                }
            })
        }
        catch {
            return nil
        }
    }

    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil) async throws -> Data? {
        if let acceptRange = acceptRange {
            if acceptRange {
                return try await readRangeRead(fileId: fileId, start: start, length: length)
            } else {
                return try await readWholeRead(fileId: fileId, start: start, length: length)
            }
        } else {
            await checkAcceptRange(fileId: fileId)
            return try await readFile(fileId: fileId, start: start, length: length)
        }
    }

    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await NetworkRemoteItem(path: path)
    }
 
    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "makeFolder(WebDAV:\(storageName ?? "") \(parentId) \(newname)")
                
                guard var url = await URL(string: accessURI()) else { return nil }
                if parentId != "" {
                    guard let pathURL = URL(string: parentId) else { return nil }
                    if pathURL.host != nil {
                        url = pathURL
                    } else {
                        var allowedCharacterSet = CharacterSet.alphanumerics
                        allowedCharacterSet.insert(charactersIn: "-._~")
                        let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                        let p2: String = p.first == "/" ? String(p.joined(separator: "/").dropFirst()) : p.joined(separator: "/")
                        guard let u = URL(string: p2, relativeTo: url) else { return nil }
                        url = u
                    }
                }
                url.appendPathComponent(newname, isDirectory: true)
                
                var request = URLRequest(url: url)
                request.httpMethod = "MKCOL"
                
                var request2 = URLRequest(url: url)
                request2.httpMethod = "PROPFIND"
                request2.setValue("0", forHTTPHeaderField: "Depth")
                request2.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
                
                let reqStr = [
                    "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                    "<D:propfind xmlns:D=\"DAV:\">",
                    "<D:allprop/>",
                    "</D:propfind>",
                ].joined(separator: "\r\n")+"\r\n"
                request2.httpBody = reqStr.data(using: .utf8)
                
                guard let (_, response1) = try? await URLSession.shared.data(for: request, delegate: self),
                      let httpResponse1 = response1 as? HTTPURLResponse else {
                    throw RetryError.Retry
                }
                guard httpResponse1.statusCode == 201 else {
                    print(httpResponse1)
                    throw RetryError.Retry
                }
                
                let (data, _) = try await URLSession.shared.data(for: request2, delegate: self)
                let result = await withCheckedContinuation { continuation in
                    let parser: XMLParser? = XMLParser(data: data)
                    let dav = DAVcollectionParser()
                    dav.continuation = continuation
                    parser?.delegate = dav
                    parser?.parse()
                }
                
                if let item = result?.first, let id = item["href"] as? String {
                    let viewContext = CloudFactory.shared.data.backgroundContext
                    let accessUriStr = await accessURI()
                    let accessUriPath = URL(string: accessUriStr)?.path
                    
                    await viewContext.perform {
                        let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
                        fetchRequest.fetchLimit = 1
                        let existing = (try? viewContext.fetch(fetchRequest))?.first
                        
                        self.storeItem(item: item, existingItem: existing, parentFileId: parentId, parentPath: parentPath, accessUriPath: accessUriPath, context: viewContext)
                        try? viewContext.save()
                    }
                    return id
                }
                return nil
            })
        }
        catch {
            return nil
        }
    }
    
    override func deleteItem(fileId: String) async -> Bool {
        var targetObjectID: NSManagedObjectID? = nil
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            targetObjectID = (try? viewContext.fetch(fetchRequest))?.first?.objectID
        }
        
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "deleteItem(WebDAV:\(storageName ?? "") \(fileId)")
                
                guard var url = await URL(string: accessURI()) else { return false }
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else { return false }
                    if pathURL.host != nil {
                        url = pathURL
                    } else {
                        var allowedCharacterSet = CharacterSet.alphanumerics
                        allowedCharacterSet.insert(charactersIn: "-._~")
                        let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                        let p2: String = p.first == "/" ? String(p.joined(separator: "/").dropFirst()) : p.joined(separator: "/")
                        guard let u = URL(string: p2, relativeTo: url) else { return false }
                        url = u
                    }
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                
                guard let (_, response) = try? await URLSession.shared.data(for: request, delegate: self),
                      let httpResponse = response as? HTTPURLResponse else {
                    throw RetryError.Retry
                }
                guard httpResponse.statusCode == 204 || httpResponse.statusCode == 404 else {
                    throw RetryError.Retry
                }
                
                await viewContext.perform {
                    if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                        WebDAVStorage.cascadeDelete(item: existing, in: viewContext)
                    }
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
    
    override func renameItem(fileId: String, newname: String) async -> String? {
        var targetObjectID: NSManagedObjectID? = nil
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        var prevParent: String? = nil
        var prevPath: String? = nil
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            if let item = (try? viewContext.fetch(fetchRequest))?.first {
                targetObjectID = item.objectID
                prevParent = item.parent
                let pathComp = item.path?.components(separatedBy: "/")
                prevPath = pathComp?.dropLast().joined(separator: "/")
            }
        }
        
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "renameItem(WebDAV:\(storageName ?? "") \(fileId) \(newname)")
                
                guard var url = await URL(string: accessURI()) else { return nil }
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else { return nil }
                    if pathURL.host != nil {
                        url = pathURL
                    } else {
                        var allowedCharacterSet = CharacterSet.alphanumerics
                        allowedCharacterSet.insert(charactersIn: "-._~")
                        let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                        let p2: String = p.first == "/" ? String(p.joined(separator: "/").dropFirst()) : p.joined(separator: "/")
                        guard let u = URL(string: p2, relativeTo: url) else { return nil }
                        url = u
                    }
                }
                var destURL = url
                destURL.deleteLastPathComponent()
                destURL.appendPathComponent(newname)
                
                var request = URLRequest(url: url)
                request.httpMethod = "MOVE"
                request.setValue(destURL.absoluteString, forHTTPHeaderField: "Destination")
                
                var request2 = URLRequest(url: destURL)
                request2.httpMethod = "PROPFIND"
                request2.setValue("0", forHTTPHeaderField: "Depth")
                request2.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
                
                let reqStr = [
                    "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                    "<D:propfind xmlns:D=\"DAV:\">",
                    "<D:allprop/>",
                    "</D:propfind>",
                ].joined(separator: "\r\n")+"\r\n"
                request2.httpBody = reqStr.data(using: .utf8)
                
                guard let (_, response1) = try? await URLSession.shared.data(for: request, delegate: self),
                      let httpResponse1 = response1 as? HTTPURLResponse else {
                    throw RetryError.Retry
                }
                guard httpResponse1.statusCode == 201 else {
                    throw RetryError.Retry
                }
                
                let (data, _) = try await URLSession.shared.data(for: request2, delegate: self)
                let result = await withCheckedContinuation { continuation in
                    let parser: XMLParser? = XMLParser(data: data)
                    let dav = DAVcollectionParser()
                    dav.continuation = continuation
                    parser?.delegate = dav
                    parser?.parse()
                }
                
                if let item = result?.first, let id = item["href"] as? String {
                    let accessUriStr = await accessURI()
                    let accessUriPath = URL(string: accessUriStr)?.path
                    
                    await viewContext.perform {
                        if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                            WebDAVStorage.cascadeDelete(item: existing, in: viewContext)
                        }
                        self.storeItem(item: item, existingItem: nil, parentFileId: prevParent, parentPath: prevPath, accessUriPath: accessUriPath, context: viewContext)
                        try? viewContext.save()
                    }
                    await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
                    return id
                }
                return nil
            })
        }
        catch {
            return nil
        }
    }
    
    override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        if toParentId == fromParentId { return nil }
        
        var toParentPath: String?
        if toParentId != "" {
            toParentPath = await getParentPath(parentId: toParentId) ?? ""
        }
        
        var targetObjectID: NSManagedObjectID? = nil
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            targetObjectID = (try? viewContext.fetch(fetchRequest))?.first?.objectID
        }
        
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: self.log, type: .debug, "moveItem(WebDAV:\(storageName ?? "") \(fromParentId)->\(toParentId)")
                
                guard var url = await URL(string: accessURI()) else { return nil }
                var destURL = url
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else { return nil }
                    if pathURL.host != nil {
                        url = pathURL
                    } else {
                        var allowedCharacterSet = CharacterSet.alphanumerics
                        allowedCharacterSet.insert(charactersIn: "-._~")
                        let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                        let p2: String = p.first == "/" ? String(p.joined(separator: "/").dropFirst()) : p.joined(separator: "/")
                        guard let u = URL(string: p2, relativeTo: url) else { return nil }
                        url = u
                    }
                }
                if toParentId != "" {
                    guard let pathURL = URL(string: toParentId) else { return nil }
                    if pathURL.host != nil {
                        destURL = pathURL
                    } else {
                        var allowedCharacterSet = CharacterSet.alphanumerics
                        allowedCharacterSet.insert(charactersIn: "-._~")
                        let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                        let p2: String = p.first == "/" ? String(p.joined(separator: "/").dropFirst()) : p.joined(separator: "/")
                        guard let u = URL(string: p2, relativeTo: destURL) else { return nil }
                        destURL = u
                    }
                }
                let name = url.lastPathComponent
                destURL.appendPathComponent(name)
                
                var request = URLRequest(url: url)
                request.httpMethod = "MOVE"
                request.setValue(destURL.absoluteString, forHTTPHeaderField: "Destination")
                
                var request2 = URLRequest(url: destURL)
                request2.httpMethod = "PROPFIND"
                request2.setValue("0", forHTTPHeaderField: "Depth")
                request2.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
                
                let reqStr = [
                    "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                    "<D:propfind xmlns:D=\"DAV:\">",
                    "<D:allprop/>",
                    "</D:propfind>",
                ].joined(separator: "\r\n")+"\r\n"
                request2.httpBody = reqStr.data(using: .utf8)
                
                guard let (_, response1) = try? await URLSession.shared.data(for: request, delegate: self),
                      let httpResponse1 = response1 as? HTTPURLResponse else {
                    throw RetryError.Retry
                }
                guard httpResponse1.statusCode == 201 else {
                    throw RetryError.Retry
                }
                
                let (data, _) = try await URLSession.shared.data(for: request2, delegate: self)
                let result = await withCheckedContinuation { continuation in
                    let parser: XMLParser? = XMLParser(data: data)
                    let dav = DAVcollectionParser()
                    dav.continuation = continuation
                    parser?.delegate = dav
                    parser?.parse()
                }
                
                if let item = result?.first, let id = item["href"] as? String {
                    let accessUriStr = await accessURI()
                    let accessUriPath = URL(string: accessUriStr)?.path
                    
                    await viewContext.perform {
                        if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                            WebDAVStorage.cascadeDelete(item: existing, in: viewContext)
                        }
                        self.storeItem(item: item, existingItem: nil, parentFileId: toParentId, parentPath: toParentPath, accessUriPath: accessUriPath, context: viewContext)
                        try? viewContext.save()
                    }
                    await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
                    return id
                }
                return nil
            })
        }
        catch {
            return nil
        }
    }
    
    override func changeTime(fileId: String, newdate: Date) async -> String? {
        var targetObjectID: NSManagedObjectID? = nil
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            targetObjectID = (try? viewContext.fetch(fetchRequest))?.first?.objectID
        }
        
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: self.log, type: .debug, "changeTime(WebDAV:\(self.storageName ?? "") \(fileId) \(newdate)")
                
                guard var url = await URL(string: accessURI()) else { return nil }
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else { return nil }
                    if pathURL.host != nil {
                        url = pathURL
                    } else {
                        var allowedCharacterSet = CharacterSet.alphanumerics
                        allowedCharacterSet.insert(charactersIn: "-._~")
                        let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                        let p2: String = p.first == "/" ? String(p.joined(separator: "/").dropFirst()) : p.joined(separator: "/")
                        guard let u = URL(string: p2, relativeTo: url) else { return nil }
                        url = u
                    }
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "PROPFIND"
                request.setValue("0", forHTTPHeaderField: "Depth")
                request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
                
                let reqStr = [
                    "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                    "<D:propfind xmlns:D=\"DAV:\">",
                    "<D:allprop/>",
                    "</D:propfind>",
                ].joined(separator: "\r\n")+"\r\n"
                request.httpBody = reqStr.data(using: .utf8)
                
                guard let (data, _) = try? await URLSession.shared.data(for: request, delegate: self) else {
                    throw RetryError.Retry
                }
                
                let result = await withCheckedContinuation { continuation in
                    let parser: XMLParser? = XMLParser(data: data)
                    let dav = DAVcollectionParser()
                    dav.continuation = continuation
                    parser?.delegate = dav
                    parser?.parse()
                }
                guard let result = result else { throw RetryError.Retry }
                
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                formatter.timeZone = TimeZone(identifier: "GMT")
                let formatter2 = ISO8601DateFormatter()
                
                var reqStr2: String?
                if let item = result.first, let propstat = item["propstat"] as? [String: Any], let prop = propstat["prop"] as? [String: String] {
                    
                    let lastmodified: (String)->String = { date in
                        [
                            "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                            "<D:propertyupdate xmlns:D=\"DAV:\">",
                            "<D:set><D:prop><D:lastmodified>\(date)</D:lastmodified></D:prop></D:set>",
                            "</D:propertyupdate>",
                        ].joined(separator: "\r\n")+"\r\n"
                    }
                    let win32lastmodified: (String)->String = { date in
                        [
                            "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                            "<D:propertyupdate xmlns:D=\"DAV:\" xmlns:Z=\"urn:schemas-microsoft-com:\">",
                            "<D:set><D:prop><Z:Win32LastModifiedTime>\(date)</Z:Win32LastModifiedTime></D:prop></D:set>",
                            "</D:propertyupdate>",
                        ].joined(separator: "\r\n")+"\r\n"
                    }
                    
                    if let mtime = prop["getlastmodified"] {
                        if formatter.date(from: mtime) != nil {
                            reqStr2 = lastmodified(formatter.string(from: newdate))
                        } else if formatter2.date(from: mtime) != nil {
                            reqStr2 = lastmodified(formatter2.string(from: newdate))
                        } else {
                            reqStr2 = lastmodified(formatter.string(from: newdate))
                        }
                    } else if let mtime = prop["Win32LastModifiedTime"] {
                        if formatter.date(from: mtime) != nil {
                            reqStr2 = win32lastmodified(formatter.string(from: newdate))
                        } else if formatter2.date(from: mtime) != nil {
                            reqStr2 = win32lastmodified(formatter2.string(from: newdate))
                        } else {
                            reqStr2 = win32lastmodified(formatter.string(from: newdate))
                        }
                    } else {
                        reqStr2 = lastmodified(formatter.string(from: newdate))
                    }
                }
                guard let reqStr3 = reqStr2 else { throw RetryError.Retry }
                
                var request2 = URLRequest(url: url)
                request2.httpMethod = "PROPPATCH"
                request2.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request2.httpBody = reqStr3.data(using: .utf8)
                
                guard let (data2, _) = try? await URLSession.shared.data(for: request2, delegate: self) else {
                    throw RetryError.Retry
                }
                let result2 = await withCheckedContinuation { continuation in
                    let parser: XMLParser? = XMLParser(data: data2)
                    let dav = DAVcollectionParser()
                    dav.continuation = continuation
                    parser?.delegate = dav
                    parser?.parse()
                }
                
                guard let result2 = result2, let item2 = result2.first,
                      let propstat2 = item2["propstat"] as? [String: Any],
                      let status = propstat2["status"] as? String, status.contains("200") else {
                    throw RetryError.Retry
                }
                
                let (data3, _) = try await URLSession.shared.data(for: request, delegate: self)
                let result3 = await withCheckedContinuation { continuation in
                    let parser: XMLParser? = XMLParser(data: data3)
                    let dav = DAVcollectionParser()
                    dav.continuation = continuation
                    parser?.delegate = dav
                    parser?.parse()
                }
                guard let result3 = result3 else { return nil }
                
                if let item = result3.first, let id = item["href"] as? String {
                    let accessUriStr = await accessURI()
                    let accessUriPath = URL(string: accessUriStr)?.path
                    
                    await viewContext.perform {
                        var existing: RemoteData? = nil
                        if let objID = targetObjectID {
                            existing = try? viewContext.existingObject(with: objID) as? RemoteData
                        }
                        // 親IDやパスは既存のものを引き継ぐため、変更なしの場合はnilを渡して既存を利用させます
                        self.storeItem(item: item, existingItem: existing, parentFileId: nil, parentPath: nil, accessUriPath: accessUriPath, context: viewContext)
                        try? viewContext.save()
                    }
                    return id
                }
                return nil
            })
        }
        catch {
            return nil
        }
    }
    
    override func uploadFile(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        defer {
            try? FileManager.default.removeItem(at: target)
        }
        
        let attr = try FileManager.default.attributesOfItem(atPath: target.path(percentEncoded: false))
        let fileSize = attr[.size] as! UInt64
        try await progress?(0, Int64(fileSize))
        
        guard var url = await URL(string: accessURI()) else { return nil }
        if parentId != "" {
            guard let pathURL = URL(string: parentId) else { return nil }
            if pathURL.host != nil {
                url = pathURL
            } else {
                var allowedCharacterSet = CharacterSet.alphanumerics
                allowedCharacterSet.insert(charactersIn: "-._~")
                let p = pathURL.pathComponents.map({ $0 == "/" ? "/" :  $0.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet)! })
                let p2: String = p.first == "/" ? String(p.joined(separator: "/").dropFirst()) : p.joined(separator: "/")
                guard let u = URL(string: p2, relativeTo: url) else { return nil }
                url = u
            }
        }
        url.appendPathComponent(uploadname)
        
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "uploadFile(WebDAV:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")
                
                var parentPath = "\(storageName ?? ""):/"
                if parentId != "" {
                    parentPath = await getParentPath(parentId: parentId) ?? parentPath
                }
                
                var request: URLRequest = URLRequest(url: url)
                request.httpMethod = "PUT"
                
                var request2 = URLRequest(url: url)
                request2.httpMethod = "PROPFIND"
                request2.setValue("0", forHTTPHeaderField: "Depth")
                request2.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
                
                let reqStr = [
                    "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                    "<D:propfind xmlns:D=\"DAV:\">",
                    "<D:allprop/>",
                    "</D:propfind>",
                ].joined(separator: "\r\n")+"\r\n"
                request2.httpBody = reqStr.data(using: .utf8)
                
                await uploadProgressManeger.setCallback(url: url, total: Int64(fileSize), callback: progress)
                defer {
                    Task { await uploadProgressManeger.removeCallback(url: url) }
                }
                
                guard (try? await URLSession.shared.upload(for: request, fromFile: target, delegate: self)) != nil else {
                    throw RetryError.Retry
                }
                
                let (data2, _) = try await URLSession.shared.data(for: request2, delegate: self)
                let result = await withCheckedContinuation { continuation in
                    let parser: XMLParser? = XMLParser(data: data2)
                    let dav = DAVcollectionParser()
                    dav.continuation = continuation
                    parser?.delegate = dav
                    parser?.parse()
                }
                
                if let item = result?.first, let id = item["href"] as? String {
                    let viewContext = CloudFactory.shared.data.backgroundContext
                    let accessUriStr = await accessURI()
                    let accessUriPath = URL(string: accessUriStr)?.path
                    
                    await viewContext.perform {
                        let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
                        fetchRequest.fetchLimit = 1
                        let existing = (try? viewContext.fetch(fetchRequest))?.first
                        
                        self.storeItem(item: item, existingItem: existing, parentFileId: parentId, parentPath: parentPath, accessUriPath: accessUriPath, context: viewContext)
                        try? viewContext.save()
                    }
                    try await progress?(Int64(fileSize), Int64(fileSize))
                    return id
                }
                return nil
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

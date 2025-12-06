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
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "OPTIONS"
        let (_, response) = try await URLSession.shared.data(for: request, delegate: self)

        guard let response = response as? HTTPURLResponse else {
            return false
        }
        guard response.statusCode == 200 else {
            print(response)
            return false
        }

        guard let allow = response.allHeaderFields["Allow"] as? String ?? response.allHeaderFields["allow"] as? String else {
            print(response)
            return false
        }
        guard allow.lowercased().contains("propfind") else {
            print(allow)
            return false
        }
        guard let dav = response.allHeaderFields["Dav"] as? String ?? response.allHeaderFields["dav"] as? String ??
            response.allHeaderFields["DAV"] as? String else {
            print(response)
            return false
        }
        guard dav.contains("1") else {
            print(dav)
            return false
        }
        
        request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response2) = try await URLSession.shared.data(for: request, delegate: self)

        guard let response2 = response2 as? HTTPURLResponse else {
            return false
        }
        guard response2.statusCode == 200 else {
            print(response2)
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

    func storeItem(item: [String: Any], parentFileId: String? = nil, parentPath: String? = nil, context: NSManagedObjectContext) async {
        guard let id = item["href"] as? String else {
            return
        }
        if id.removingPercentEncoding == parentFileId?.removingPercentEncoding {
            return
        }
        if let idURL = URL(string: id), let aurl = await URL(string: accessURI()), idURL.path == aurl.path {
            return
        }
        guard let propstat = item["propstat"] as? [String: Any] else {
            return
        }
        guard let prop = propstat["prop"] as? [String: String] else {
            return
        }
        let name: String
        if let dispname = prop["displayname"] {
            name = dispname
        }
        else {
            guard let idURL = URL(string: id) else {
                return
            }
            guard let orgname = idURL.lastPathComponent.removingPercentEncoding else {
                return
            }
            name = orgname
        }
        let ctime = prop["creationdate"] ?? prop["Win32CreationTime"]
        let mtime = prop["lastmodified"] ?? prop["getlastmodified"] ?? prop["Win32LastModifiedTime"]
        let size = Int64(prop["getcontentlength"] ?? "0")
        let folder = prop["resourcetype"] == "collection"
        
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

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let formatter2 = ISO8601DateFormatter()

            let newitem = RemoteData(context: context)
            newitem.storage = self.storageName
            newitem.id = id
            newitem.name = name
            let comp = name.components(separatedBy: ".")
            if comp.count >= 1 {
                newitem.ext = comp.last!.lowercased()
            }
            newitem.cdate = formatter.date(from: ctime ?? "") ?? formatter2.date(from: ctime ?? "")
            newitem.mdate = formatter.date(from: mtime ?? "") ?? formatter2.date(from: mtime ?? "")
            newitem.folder = folder
            newitem.size = size ?? 0
            newitem.hashstr = ""
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
        if let items = await listFolder(path: fileId) {
            for item in items {
                await storeItem(item: item, parentFileId: fileId, parentPath: path, context: viewContext)
            }
            await viewContext.perform {
                try? viewContext.save()
            }
        }
    }

    func checkAcceptRange(fileId: String) async {
        if acceptRange != nil {
            return
        }

        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "checkAcceptRange(WebDAV:\(storageName ?? "") \(fileId)")

                var request: URLRequest
                guard var url = await URL(string: accessURI()) else {
                    return
                }
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else {
                        return
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
                            return
                        }
                        url = u
                    }
                }
                //print(url)
                request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                
                guard let (_, response) = try? await URLSession.shared.data(for: request, delegate: self) else {
                    throw RetryError.Retry
                }
                guard let response = response as? HTTPURLResponse else {
                    throw RetryError.Retry
                }
                guard response.statusCode == 200 else {
                    print(response)
                    throw RetryError.Retry
                }
                guard let accept = response.allHeaderFields["Accept-Ranges"] as? String ?? response.allHeaderFields["accept-ranges"] as? String else {
                    print(response)
                    throw RetryError.Retry
                }
                if accept.lowercased().contains("bytes") {
                    acceptRange = true
                }
                else {
                    acceptRange = false
                }
            }, semaphore: checkSemaphore)
        }
        catch {
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
                guard var url = await URL(string: accessURI()) else {
                    return nil
                }
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else {
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
                let s = start ?? 0
                if length == nil {
                    request.setValue("bytes=\(s)-", forHTTPHeaderField: "Range")
                }
                else {
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

                guard var url = await URL(string: accessURI()) else {
                    return nil
                }
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else {
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

                var request: URLRequest
                request = URLRequest(url: url)

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
                            }
                            else {
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
            }
            else {
                return try await readWholeRead(fileId: fileId, start: start, length: length)
            }
        }
        else {
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

                guard var url = await URL(string: accessURI()) else {
                    return nil
                }
                if parentId != "" {
                    guard let pathURL = URL(string: parentId) else {
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
                url.appendPathComponent(newname, isDirectory: true)
                //print(url)

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

                guard let (_, response1) = try? await URLSession.shared.data(for: request, delegate: self) else {
                    throw RetryError.Retry
                }
                guard let response1 = response1 as? HTTPURLResponse else {
                    throw RetryError.Retry
                }
                guard response1.statusCode == 201 else {
                    print(response1)
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
                guard let result = result else {
                    return nil
                }
                if let item = result.first, let id = item["href"] as? String {
                    let viewContext = CloudFactory.shared.data.viewContext
                    await storeItem(item: item, parentFileId: parentId, parentPath: parentPath, context: viewContext)
                    await viewContext.perform {
                        try? viewContext.save()
                    }
                    return id
                }
                else {
                    return nil
                }
            })
        }
        catch {
            return nil
        }
    }

    override func deleteItem(fileId: String) async -> Bool {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "deleteItem(WebDAV:\(storageName ?? "") \(fileId)")

                guard var url = await URL(string: accessURI()) else {
                    return false
                }
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else {
                        return false
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
                            return false
                        }
                        url = u
                    }
                }
                //print(url)
                
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                
                guard let (_, response) = try? await URLSession.shared.data(for: request, delegate: self) else {
                    throw RetryError.Retry
                }
                guard let response = response as? HTTPURLResponse else {
                    throw RetryError.Retry
                }
                guard response.statusCode == 204 || response.statusCode == 404 else {
                    print(response)
                    throw RetryError.Retry
                }
                let viewContext = CloudFactory.shared.data.viewContext
                await viewContext.perform {
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
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
    
    override func renameItem(fileId: String, newname: String) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "renameItem(WebDAV:\(storageName ?? "") \(fileId) \(newname)")

                guard var url = await URL(string: accessURI()) else {
                    return nil
                }
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else {
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
                var destURL = url
                destURL.deleteLastPathComponent()
                destURL.appendPathComponent(newname)
                //print(url)
                //print(destURL)

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

                guard let (_, response1) = try? await URLSession.shared.data(for: request, delegate: self) else {
                    throw RetryError.Retry
                }
                guard let response1 = response1 as? HTTPURLResponse else {
                    throw RetryError.Retry
                }
                guard response1.statusCode == 201 else {
                    print(response1)
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
                guard let result = result else {
                    return nil
                }
                if let item = result.first, let id = item["href"] as? String {
                    var prevParent: String?
                    var prevPath: String?

                    let viewContext = CloudFactory.shared.data.viewContext
                    await viewContext.perform {
                        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
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
                    }
                    deleteChildRecursive(parent: fileId, context: viewContext)
                    await storeItem(item: item, parentFileId: prevParent, parentPath: prevPath, context: viewContext)
                    await viewContext.perform {
                        try? viewContext.save()
                    }
                    await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
                    return id
                }
                else {
                    return nil
                }
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

        var toParentPath: String?
        if toParentId != "" {
            toParentPath = await getParentPath(parentId: toParentId) ?? ""
        }

        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: self.log, type: .debug, "moveItem(WebDAV:\(storageName ?? "") \(fromParentId)->\(toParentId)")

                guard var url = await URL(string: accessURI()) else {
                    return nil
                }
                var destURL = url
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else {
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
                if toParentId != "" {
                    guard let pathURL = URL(string: toParentId) else {
                        return nil
                    }
                    if pathURL.host != nil {
                        destURL = pathURL
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
                        guard let u = URL(string: p2, relativeTo: destURL) else {
                            return nil
                        }
                        destURL = u
                    }
                }
                let name = url.lastPathComponent
                destURL.appendPathComponent(name)
                //print(url)
                //print(destURL)
                
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

                guard let (_, response1) = try? await URLSession.shared.data(for: request, delegate: self) else {
                    throw RetryError.Retry
                }
                guard let response1 = response1 as? HTTPURLResponse else {
                    throw RetryError.Retry
                }
                guard response1.statusCode == 201 else {
                    print(response1)
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
                guard let result = result else {
                    return nil
                }
                if let item = result.first, let id = item["href"] as? String {
                    let viewContext = CloudFactory.shared.data.viewContext
                    deleteChildRecursive(parent: fileId, context: viewContext)
                    await storeItem(item: item, parentFileId: toParentId, parentPath: toParentPath, context: viewContext)
                    await viewContext.perform {
                        try? viewContext.save()
                    }
                    await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
                    return id
                }
                else {
                    return nil
                }
            })
        }
        catch {
            return nil
        }
    }
    
    override func changeTime(fileId: String, newdate: Date) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: self.log, type: .debug, "changeTime(WebDAV:\(self.storageName ?? "") \(fileId) \(newdate)")

                guard var url = await URL(string: accessURI()) else {
                    return nil
                }
                if fileId != "" {
                    guard let pathURL = URL(string: fileId) else {
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
                let lastmodified: (String)->String = { date in
                    [
                        "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                        "<D:propertyupdate xmlns:D=\"DAV:\">",
                        "<D:set>",
                        "<D:prop>",
                        "<D:lastmodified>\(date)</D:lastmodified>",
                        "</D:prop>",
                        "</D:set>",
                        "</D:propertyupdate>",
                    ].joined(separator: "\r\n")+"\r\n"
                }
                let win32lastmodified: (String)->String = { date in
                    [
                        "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                        "<D:propertyupdate xmlns:D=\"DAV:\" xmlns:Z=\"urn:schemas-microsoft-com:\">",
                        "<D:set>",
                        "<D:prop>",
                        "<Z:Win32LastModifiedTime>\(date)</Z:Win32LastModifiedTime>",
                        "</D:prop>",
                        "</D:set>",
                        "</D:propertyupdate>",
                    ].joined(separator: "\r\n")+"\r\n"
                }
                let result = await withCheckedContinuation { continuation in
                    let parser: XMLParser? = XMLParser(data: data)
                    let dav = DAVcollectionParser()
                    dav.continuation = continuation
                    parser?.delegate = dav
                    parser?.parse()
                }
                guard let result = result else {
                    throw RetryError.Retry
                }
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                formatter.timeZone = TimeZone(identifier: "GMT")
                let formatter2 = ISO8601DateFormatter()
                var reqStr2: String?
                if let item = result.first, let propstat = item["propstat"] as? [String: Any], let prop = propstat["prop"] as? [String: String] {
                    if let mtime = prop["getlastmodified"] {
                        if formatter.date(from: mtime) != nil {
                            reqStr2 = lastmodified(formatter.string(from: newdate))
                        }
                        else if formatter2.date(from: mtime) != nil {
                            reqStr2 = lastmodified(formatter2.string(from: newdate))
                        }
                        else {
                            reqStr2 = lastmodified(formatter.string(from: newdate))
                        }
                    }
                    else if let mtime = prop["Win32LastModifiedTime"] {
                        if formatter.date(from: mtime) != nil {
                            reqStr2 = win32lastmodified(formatter.string(from: newdate))
                        }
                        else if formatter2.date(from: mtime) != nil {
                            reqStr2 = win32lastmodified(formatter2.string(from: newdate))
                        }
                        else {
                            reqStr2 = win32lastmodified(formatter.string(from: newdate))
                        }
                    }
                    else {
                        reqStr2 = lastmodified(formatter.string(from: newdate))
                    }
                }
                guard let reqStr3 = reqStr2 else {
                    throw RetryError.Retry
                }

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
                guard let result2 = result2 else {
                    throw RetryError.Retry
                }
                guard let item = result2.first else {
                    throw RetryError.Retry
                }
                guard let propstat = item["propstat"] as? [String: Any] else {
                    throw RetryError.Retry
                }
                guard let status = propstat["status"] as? String else {
                    throw RetryError.Retry
                }
                guard status.contains("200") else {
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
                guard let result3 = result3 else {
                    return nil
                }
                if let item = result3.first, let id = item["href"] as? String {
                    let viewContext = CloudFactory.shared.data.viewContext
                    await storeItem(item: item, parentFileId: nil, parentPath: nil, context: viewContext)
                    await viewContext.perform {
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

        guard var url = await URL(string: accessURI()) else {
            return nil
        }
        if parentId != "" {
            guard let pathURL = URL(string: parentId) else {
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
                guard let result = result else {
                    return nil
                }
                if let item = result.first, let id = item["href"] as? String {
                    let viewContext = CloudFactory.shared.data.viewContext
                    await storeItem(item: item, parentFileId: parentId, parentPath: parentPath, context: viewContext)
                    await viewContext.perform {
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

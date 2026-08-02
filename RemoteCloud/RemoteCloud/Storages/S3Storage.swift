//
//  FilenStorage.swift
//  RemoteCloud
//
//  Created by rei8 on 2019/11/22.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CryptoKit
import os.log
import CoreData
import SwiftUI
import AuthenticationServices
internal import UniformTypeIdentifiers

struct S3LoginView: View {
    let authContinuation: CheckedContinuation<Bool, Never>
    // Endpoint, AccessKey, SecretKey, Region, Bucket, PathStyle
    let callback: (String, String, String, String, String, Bool) async -> String?
    let onDismiss: () -> Void
    
    @State private var ok = false
    @State private var errorMessage = ""
    @State private var isPresent = false

    @State private var textEndpoint = ""
    @State private var textAccessKey = ""
    @State private var textSecretKey = ""
    @State private var textRegion = ""
    @State private var textBucket = ""
    @State private var usePathStyle = false // path style (e.g. MinIO)

    var body: some View {
        ZStack {
            Form {
                Section(header: Text("Server Info")) {
                    TextField("Endpoint (e.g. https://s3.ap-northeast-1.amazonaws.com)", text: $textEndpoint)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                    
                    TextField("Region (e.g. us-east-1, auto)", text: $textRegion)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    
                    TextField("Bucket Name", text: $textBucket)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                
                Section(header: Text("Credentials")) {
                    TextField("Access Key ID", text: $textAccessKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    
                    SecureField("Secret Access Key", text: $textSecretKey)
                }
                
                Section(header: Text("Advanced Options")) {
                    Toggle("Use Path-Style Access", isOn: $usePathStyle)
                    Text("Enable this for MinIO or local S3 compatible servers.")
                        .foregroundColor(.secondary)
                }
                
                Button("Connect") {
                    if textEndpoint.isEmpty || textAccessKey.isEmpty || textSecretKey.isEmpty || textBucket.isEmpty {
                        errorMessage = "Please fill in all required fields."
                        isPresent.toggle()
                        return
                    }
                    
                    ok = true
                    Task {
                        // Regionが空の場合は自動的に "us-east-1" などを設定するのもありです
                        let regionToUse = textRegion.isEmpty ? "us-east-1" : textRegion
                        
                        if let error = await callback(textEndpoint, textAccessKey, textSecretKey, regionToUse, textBucket, usePathStyle) {
                            errorMessage = error
                            isPresent.toggle()
                            ok = false
                        } else {
                            authContinuation.resume(returning: true)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(ok)
            .alert("Error", isPresented: $isPresent) {
                Button(role: .cancel) {
                    ok = false
                }
            } message: {
                Text(errorMessage)
            }

            if ok {
                ProgressView("Connecting...")
                    .padding(30)
                    .background(Color(uiColor: .systemBackground).opacity(0.9))
                    .cornerRadius(10)
                    .shadow(radius: 10)
            }
        }
        .onDisappear {
            if ok { return }
            onDismiss()
        }
    }
}

public class S3Storage: NetworkStorage, URLSessionDataDelegate {
    
    public override func getStorageType() -> CloudStorages {
        return .S3
    }
    
    var cache_endpoint = ""
    var cache_accessKey = ""
    var cache_secretKey = ""
    var cache_region = ""
    var cache_bucket = ""
    var cache_pathStyle: Bool? = nil
    
    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .S3)
        storageName = name
    }
    
    func getEndpoint() async -> String {
        if !cache_endpoint.isEmpty { return cache_endpoint }
        if let name = storageName, let val = await getKeyChain(key: "\(name)_endpoint") { cache_endpoint = val }
        return cache_endpoint
    }
    
    func getAccessKey() async -> String {
        if !cache_accessKey.isEmpty { return cache_accessKey }
        if let name = storageName, let val = await getKeyChain(key: "\(name)_accessKey") { cache_accessKey = val }
        return cache_accessKey
    }
    
    func getSecretKey() async -> String {
        if !cache_secretKey.isEmpty { return cache_secretKey }
        if let name = storageName, let val = await getKeyChain(key: "\(name)_secretKey") { cache_secretKey = val }
        return cache_secretKey
    }
    
    func getRegion() async -> String {
        if !cache_region.isEmpty { return cache_region }
        if let name = storageName, let val = await getKeyChain(key: "\(name)_region") { cache_region = val }
        return cache_region
    }
    
    func getBucket() async -> String {
        if !cache_bucket.isEmpty { return cache_bucket }
        if let name = storageName, let val = await getKeyChain(key: "\(name)_bucket") { cache_bucket = val }
        return cache_bucket
    }
    
    func getPathStyle() async -> Bool {
        if let cache = cache_pathStyle { return cache }
        if let name = storageName, let val = await getKeyChain(key: "\(name)_pathStyle") {
            cache_pathStyle = (val == "true")
        } else {
            cache_pathStyle = false
        }
        return cache_pathStyle!
    }
    
    override func checkToken() async -> Bool {
        let ep = await getEndpoint()
        let ak = await getAccessKey()
        let sk = await getSecretKey()
        let bk = await getBucket()
        return !ep.isEmpty && !ak.isEmpty && !sk.isEmpty && !bk.isEmpty
    }
    
    public override func logout() async {
        if let name = storageName {
            let _ = await delKeyChain(key: "\(name)_endpoint")
            let _ = await delKeyChain(key: "\(name)_accessKey")
            let _ = await delKeyChain(key: "\(name)_secretKey")
            let _ = await delKeyChain(key: "\(name)_region")
            let _ = await delKeyChain(key: "\(name)_bucket")
            let _ = await delKeyChain(key: "\(name)_pathStyle")
        }
        cache_endpoint = ""
        cache_accessKey = ""
        cache_secretKey = ""
        cache_region = ""
        cache_bucket = ""
        cache_pathStyle = nil
        
        await super.logout()
    }
    
    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        
        let authRet = await withCheckedContinuation { authContinuation in
            Task {
                let presentRet = await withCheckedContinuation { continuation in
                    callback(S3LoginView(authContinuation: authContinuation, callback: authCallback, onDismiss: {
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
    
    func authCallback(_ endpoint: String, _ accessKey: String, _ secretKey: String, _ region: String, _ bucket: String, _ pathStyle: Bool) async -> String? {
        
        cache_endpoint = endpoint
        cache_accessKey = accessKey
        cache_secretKey = secretKey
        cache_region = region
        cache_bucket = bucket
        cache_pathStyle = pathStyle
        
        let testResult = await listFolder(path: "")
        
        if testResult == nil {
            cache_endpoint = ""
            cache_accessKey = ""
            cache_secretKey = ""
            cache_region = ""
            cache_bucket = ""
            cache_pathStyle = nil
            
            return "Connection failed. Please check your endpoint, credentials, or bucket name."
        }
        
        let name = storageName ?? ""
        let _ = await setKeyChain(key: "\(name)_endpoint", value: endpoint)
        let _ = await setKeyChain(key: "\(name)_accessKey", value: accessKey)
        let _ = await setKeyChain(key: "\(name)_secretKey", value: secretKey)
        let _ = await setKeyChain(key: "\(name)_region", value: region)
        let _ = await setKeyChain(key: "\(name)_bucket", value: bucket)
        let _ = await setKeyChain(key: "\(name)_pathStyle", value: pathStyle ? "true" : "false")
        
        return nil
    }
    
    // MARK: - ファイル一覧のUI反映 (CoreDataへの保存)
    
    override func listChildren(fileId: String, path: String) async {
        let viewContext = CloudFactory.shared.data.viewContext
        let storage = storageName ?? ""
        
        // 1. CoreData内の古いキャッシュ(同じ親フォルダを持つ要素)をクリア
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest) {
                for object in result {
                    viewContext.delete(object as! NSManagedObject)
                }
            }
        }
        
        // 2. S3から最新のリストを取得
        if let items = await listFolder(path: fileId) {
            
            // 3. 取得したアイテムをCoreDataに書き込む
            for item in items {
                await storeItem(item: item, parentId: fileId, parentPath: path, context: viewContext)
            }
            
            // 4. 変更を保存してUIを更新
            await viewContext.perform {
                try? viewContext.save()
            }
        }
    }
    
    private func storeItem(item: [String: Any], parentId: String, parentPath: String, context: NSManagedObjectContext) async {
        guard let id = item["id"] as? String,
              let name = item["name"] as? String,
              let isFolder = item["isFolder"] as? Bool else {
            return
        }
        
        var mtime = Date(timeIntervalSince1970: 0)
        var size = 0
        
        if let lastModified = item["lastModified"] as? Int {
            mtime = Date(timeIntervalSince1970: Double(lastModified) / 1000.0)
        }
        if let s = item["size"] as? Int {
            size = s
        }
        
        await context.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
            if let result = try? context.fetch(fetchRequest) {
                for object in result {
                    context.delete(object as! NSManagedObject)
                }
            }
            
            let newitem = RemoteData(context: context)
            newitem.storage = self.storageName
            newitem.id = id
            newitem.name = name
            
            let comp = name.components(separatedBy: ".")
            if comp.count > 1 && !isFolder {
                newitem.ext = comp.last!.lowercased()
            } else {
                newitem.ext = ""
            }
            
            newitem.cdate = mtime
            newitem.mdate = mtime
            newitem.folder = isFolder
            newitem.size = Int64(size)
            
            newitem.parent = parentId
            if parentId == "" {
                newitem.path = "\(self.storageName ?? ""):/\(name)"
            } else {
                newitem.path = "\(parentPath)/\(name)"
            }
        }
    }
    
    func downloadChunk(fileId: String, range: ClosedRange<Int64>) async -> Data? {
        do {
            let headers = ["Range": "bytes=\(range.lowerBound)-\(range.upperBound)"]
            return try await sendS3Request(method: "GET", path: fileId, additionalHeaders: headers)
        } catch {
            os_log("%{public}@", log: log, type: .error, "S3 Download Error: \(error.localizedDescription)")
            return nil
        }
    }
    
    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await S3RemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await S3RemoteItem(path: path)
    }
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        do {
            os_log("%{public}@", log: log, type: .debug, "makeFolder(S3:\(storageName ?? "")) newname: \(newname)")
            
            var newPrefix = ""
            if parentId.isEmpty || parentId == "/" {
                newPrefix = "\(newname)/"
            } else {
                let cleanParent = parentId.hasSuffix("/") ? parentId : "\(parentId)/"
                newPrefix = "\(cleanParent)\(newname)/"
            }
            
            let emptyData = Data()
            let _ = try await sendS3Request(method: "PUT", path: newPrefix, body: emptyData)
            
            return newPrefix
        } catch {
            os_log("%{public}@", log: log, type: .error, "makeFolder Error: \(error.localizedDescription)")
            return nil
        }
    }
    
    public override func deleteItem(fileId: String) async -> Bool {
        guard let item = await CloudFactory.shared.data.getData(storage: storageName ?? "", fileId: fileId) else {
            return false
        }
        
        if item.folder {
            return await deleteDir(fileId: fileId)
        } else {
            return await deleteFile(fileId: fileId)
        }
    }
    
    // MARK: remove file
    func deleteFile(fileId: String) async -> Bool {
        do {
            os_log("%{public}@", log: log, type: .debug, "deleteFile(S3:\(storageName ?? "")) \(fileId)")
            
            let _ = try await sendS3Request(method: "DELETE", path: fileId)
            
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
                try? viewContext.save()
            }
            
            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
            
            return true
        } catch {
            os_log("%{public}@", log: log, type: .error, "deleteFile Error: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: remove folder
    func deleteDir(fileId: String) async -> Bool {
        do {
            os_log("%{public}@", log: log, type: .debug, "deleteDir(S3:\(storageName ?? "")) \(fileId)")
            
            var allKeys: [String] = []
            var isTruncated = true
            var continuationToken: String? = nil
            
            while isTruncated {
                var queryItems = [
                    URLQueryItem(name: "list-type", value: "2"),
                    URLQueryItem(name: "prefix", value: fileId)
                ]
                if let token = continuationToken {
                    queryItems.append(URLQueryItem(name: "continuation-token", value: token))
                }
                
                let xmlData = try await sendS3Request(method: "GET", path: "", queryItems: queryItems)
                let parser = S3AllKeysParser(data: xmlData)
                parser.parse()
                
                allKeys.append(contentsOf: parser.keys)
                isTruncated = parser.isTruncated
                continuationToken = parser.nextContinuationToken
            }
            
            if !allKeys.isEmpty {
                let chunkSize = 1000
                for i in stride(from: 0, to: allKeys.count, by: chunkSize) {
                    let end = min(i + chunkSize, allKeys.count)
                    let chunk = Array(allKeys[i..<end])
                    try await deleteMultipleObjects(keys: chunk)
                }
            } else {
                let _ = try await sendS3Request(method: "DELETE", path: fileId)
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
            
        } catch {
            os_log("%{public}@", log: log, type: .error, "deleteDir Error: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Multi-Object Delete
    
    private func deleteMultipleObjects(keys: [String]) async throws {
        guard !keys.isEmpty else { return }
        
        var xmlString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Delete>\n<Quiet>true</Quiet>\n"
        for key in keys {
            let escapedKey = escapeXML(key)
            xmlString += "<Object><Key>\(escapedKey)</Key></Object>\n"
        }
        xmlString += "</Delete>"
        
        guard let xmlData = xmlString.data(using: .utf8) else { return }
        
        let md5Hash = Insecure.MD5.hash(data: xmlData)
        let md5Base64 = Data(md5Hash).base64EncodedString()
        
        let queryItems = [URLQueryItem(name: "delete", value: "")]
        let headers = [
            "Content-MD5": md5Base64,
            "Content-Type": "application/xml"
        ]
        
        let _ = try await sendS3Request(
            method: "POST",
            path: "",
            queryItems: queryItems,
            additionalHeaders: headers,
            body: xmlData
        )
    }
    
    private func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    // MARK: - rename
    
    public override func renameItem(fileId: String, newname: String) async -> String? {
        if fileId.isEmpty { return nil }
        
        let viewContext = CloudFactory.shared.data.viewContext
        let storage = storageName ?? ""
        var isFolder = false
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest) as? [RemoteData] {
                if let item = result.first {
                    isFolder = item.folder
                }
            }
        }
        
        let newid = isFolder ? await renameDir(fileId: fileId, newname: newname) : await renameFile(fileId: fileId, newname: newname)
        
        if newid != nil {
            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
            
            await viewContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                if let result = try? viewContext.fetch(fetchRequest) as? [RemoteData] {
                    for object in result {
                        viewContext.delete(object)
                    }
                }
                
                if isFolder {
                    self.deleteChildRecursive(parent: fileId, context: viewContext)
                }
                
                try? viewContext.save()
            }
        }
        
        return newid
    }
    
    // MARK: rename file
    private func renameFile(fileId: String, newname: String) async -> String? {
        do {
            os_log("%{public}@", log: log, type: .debug, "renameFile(S3:\(storageName ?? "")) \(fileId) -> \(newname)")
            
            let components = fileId.components(separatedBy: "/")
            var newPath = ""
            if components.count > 1 {
                let parentPath = components.dropLast().joined(separator: "/")
                newPath = "\(parentPath)/\(newname)"
            } else {
                newPath = newname
            }
            
            let bucket = await getBucket()
            let copySource = "/\(bucket)/\(fileId)"
            let encodedSource = s3PercentEncode(copySource, isPath: true)
            let headers = ["x-amz-copy-source": encodedSource]
            
            // copy to new path
            let _ = try await sendS3Request(method: "PUT", path: newPath, additionalHeaders: headers, body: Data())
            
            // delete old path
            let _ = try await sendS3Request(method: "DELETE", path: fileId)
            
            return newPath
            
        } catch {
            os_log("%{public}@", log: log, type: .error, "renameFile Error: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: rename folder
    private func renameDir(fileId: String, newname: String) async -> String? {
        do {
            os_log("%{public}@", log: log, type: .debug, "renameDir(S3:\(storageName ?? "")) \(fileId) -> \(newname)")
            
            var components = fileId.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if components.last == "" { components.removeLast() }
            if components.isEmpty { return nil }
            
            components.removeLast()
            let parentPath = components.joined(separator: "/")
            let newPrefix = parentPath.isEmpty ? "\(newname)/" : "\(parentPath)/\(newname)/"
            
            var allKeys: [String] = []
            var isTruncated = true
            var continuationToken: String? = nil
            
            while isTruncated {
                var queryItems = [
                    URLQueryItem(name: "list-type", value: "2"),
                    URLQueryItem(name: "prefix", value: fileId)
                ]
                if let token = continuationToken { queryItems.append(URLQueryItem(name: "continuation-token", value: token)) }
                
                let xmlData = try await sendS3Request(method: "GET", path: "", queryItems: queryItems)
                let parser = S3AllKeysParser(data: xmlData)
                parser.parse()
                allKeys.append(contentsOf: parser.keys)
                isTruncated = parser.isTruncated
                continuationToken = parser.nextContinuationToken
            }
            
            let bucket = await getBucket()
            let maxConcurrentTasks = 10
            
            var successfulOldKeys: [String] = []
            
            await withTaskGroup(of: String?.self) { group in
                for (index, oldKey) in allKeys.enumerated() {
                    if index >= maxConcurrentTasks {
                        if let successKey = await group.next() as? String {
                            successfulOldKeys.append(successKey)
                        }
                    }
                    
                    group.addTask {
                        let suffix = oldKey.dropFirst(fileId.count)
                        let newKey = "\(newPrefix)\(suffix)"
                        
                        let copySource = "/\(bucket)/\(oldKey)"
                        let encodedSource = self.s3PercentEncode(copySource, isPath: true)
                        let headers = ["x-amz-copy-source": encodedSource]
                        
                        do {
                            let _ = try await self.sendS3Request(method: "PUT", path: newKey, additionalHeaders: headers, body: Data())
                            return oldKey // return if success
                        } catch {
                            os_log("%{public}@", log: self.log, type: .error, "Failed to copy inner file: \(oldKey)")
                            return nil
                        }
                    }
                }
                
                for await result in group {
                    if let successKey = result {
                        successfulOldKeys.append(successKey)
                    }
                }
            }
            
            if !successfulOldKeys.isEmpty {
                let chunkSize = 1000
                for i in stride(from: 0, to: successfulOldKeys.count, by: chunkSize) {
                    let end = min(i + chunkSize, successfulOldKeys.count)
                    let chunk = Array(successfulOldKeys[i..<end])
                    try? await deleteMultipleObjects(keys: chunk)
                }
            }
            
            return newPrefix
            
        } catch {
            os_log("%{public}@", log: log, type: .error, "renameDir Error: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Move
    
    public override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        if fileId.isEmpty { return nil }
        if fromParentId == toParentId {
            return nil
        }

        let viewContext = CloudFactory.shared.data.viewContext
        let storage = storageName ?? ""
        var isFolder = false
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest) as? [RemoteData] {
                if let item = result.first {
                    isFolder = item.folder
                }
            }
        }
        
        let newid = isFolder ? await moveDir(fileId: fileId, toParentId: toParentId) : await moveFile(fileId: fileId, toParentId: toParentId)
        
        if newid != nil {
            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
            
            await viewContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                if let result = try? viewContext.fetch(fetchRequest) as? [RemoteData] {
                    for object in result {
                        viewContext.delete(object)
                    }
                }
                
                if isFolder {
                    self.deleteChildRecursive(parent: fileId, context: viewContext)
                }
                
                try? viewContext.save()
            }
        }
        
        return newid
    }
    
    // MARK: move file
    private func moveFile(fileId: String, toParentId: String) async -> String? {
        do {
            os_log("%{public}@", log: log, type: .debug, "moveFile(S3:\(storageName ?? "")) \(fileId) -> \(toParentId)")
            
            let fileName = (fileId as NSString).lastPathComponent
            var newPrefix = toParentId
            if newPrefix.hasPrefix("/") { newPrefix = String(newPrefix.dropFirst()) }
            if !newPrefix.isEmpty && !newPrefix.hasSuffix("/") { newPrefix += "/" }
            let newKey = "\(newPrefix)\(fileName)"
            
            let bucket = await getBucket()
            let copySource = "/\(bucket)/\(fileId)"
            let encodedSource = s3PercentEncode(copySource, isPath: true)
            let headers = ["x-amz-copy-source": encodedSource]
            
            // copy new
            let _ = try await sendS3Request(method: "PUT", path: newKey, additionalHeaders: headers, body: Data())
            
            // remove old
            let _ = try await sendS3Request(method: "DELETE", path: fileId)
            
            return newKey
            
        } catch {
            os_log("%{public}@", log: log, type: .error, "moveFile Error: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: move folder
    private func moveDir(fileId: String, toParentId: String) async -> String? {
        do {
            os_log("%{public}@", log: log, type: .debug, "moveDir(S3:\(storageName ?? "")) \(fileId) -> \(toParentId)")
            
            var components = fileId.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if components.last == "" { components.removeLast() }
            guard let folderName = components.last else { return nil } // ルートは移動不可
            
            var newParentPrefix = toParentId
            if newParentPrefix.hasPrefix("/") { newParentPrefix = String(newParentPrefix.dropFirst()) }
            if !newParentPrefix.isEmpty && !newParentPrefix.hasSuffix("/") { newParentPrefix += "/" }
            let newPrefix = "\(newParentPrefix)\(folderName)/"
            
            var allKeys: [String] = []
            var isTruncated = true
            var continuationToken: String? = nil
            
            while isTruncated {
                var queryItems = [
                    URLQueryItem(name: "list-type", value: "2"),
                    URLQueryItem(name: "prefix", value: fileId)
                ]
                if let token = continuationToken { queryItems.append(URLQueryItem(name: "continuation-token", value: token)) }
                
                let xmlData = try await sendS3Request(method: "GET", path: "", queryItems: queryItems)
                let parser = S3AllKeysParser(data: xmlData)
                parser.parse()
                allKeys.append(contentsOf: parser.keys)
                isTruncated = parser.isTruncated
                continuationToken = parser.nextContinuationToken
            }
            
            let bucket = await getBucket()
            let maxConcurrentTasks = 10
            var successfulOldKeys: [String] = []
            
            await withTaskGroup(of: String?.self) { group in
                for (index, oldKey) in allKeys.enumerated() {
                    if index >= maxConcurrentTasks {
                        if let successKey = await group.next() as? String {
                            successfulOldKeys.append(successKey)
                        }
                    }
                    
                    group.addTask {
                        let suffix = oldKey.dropFirst(fileId.count)
                        let newKey = "\(newPrefix)\(suffix)"
                        
                        let copySource = "/\(bucket)/\(oldKey)"
                        let encodedSource = self.s3PercentEncode(copySource, isPath: true)
                        let headers = ["x-amz-copy-source": encodedSource]
                        
                        do {
                            let _ = try await self.sendS3Request(method: "PUT", path: newKey, additionalHeaders: headers, body: Data())
                            return oldKey
                        } catch {
                            os_log("%{public}@", log: self.log, type: .error, "Failed to copy inner file during move: \(oldKey)")
                            return nil
                        }
                    }
                }
                for await result in group {
                    if let successKey = result { successfulOldKeys.append(successKey) }
                }
            }
            
            if !successfulOldKeys.isEmpty {
                let chunkSize = 1000
                for i in stride(from: 0, to: successfulOldKeys.count, by: chunkSize) {
                    let end = min(i + chunkSize, successfulOldKeys.count)
                    let chunk = Array(successfulOldKeys[i..<end])
                    try? await deleteMultipleObjects(keys: chunk)
                }
            }
            
            return newPrefix
            
        } catch {
            os_log("%{public}@", log: log, type: .error, "moveDir Error: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - file upload
    
    public override func uploadFile(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        defer { try? FileManager.default.removeItem(at: target) }
        
        var prefix = parentId
        if prefix.hasPrefix("/") { prefix = String(prefix.dropFirst()) }
        if !prefix.isEmpty && !prefix.hasSuffix("/") { prefix += "/" }
        let newKey = "\(prefix)\(uploadname)"
        
        let ext = (uploadname as NSString).pathExtension
        let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: target.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        let chunkSize: Int = 5 * 1024 * 1024 // need chunk size >5MiB
        
        try await progress?(0, fileSize)
        
        if fileSize <= Int64(chunkSize) {
            let fileData = try Data(contentsOf: target)
            let headers = ["Content-Type": mimeType, "Content-Length": "\(fileSize)"]
            let _ = try await sendS3Request(method: "PUT", path: newKey, additionalHeaders: headers, body: fileData)
            try await progress?(fileSize, fileSize)
            return newKey
            
        } else {
            var currentUploadId: String? = nil
            do {
                let initXml = try await sendS3Request(method: "POST", path: newKey, queryItems: [URLQueryItem(name: "uploads", value: "")], additionalHeaders: ["Content-Type": mimeType])
                let parser = S3MultipartUploadParser(data: initXml)
                guard let uploadId = parser.uploadId else {
                    throw NSError(domain: "S3", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to init multipart"])
                }
                currentUploadId = uploadId
                
                var parts: [(Int, String)] = []
                let fileHandle = try FileHandle(forReadingFrom: target)
                defer { try? fileHandle.close() }
                
                var partNumber = 1
                var uploadedSize: Int64 = 0
                
                while uploadedSize < fileSize {
                    let readSize = min(Int64(chunkSize), fileSize - uploadedSize)
                    guard let chunkData = try fileHandle.read(upToCount: Int(readSize)) else { break }
                    
                    let query = [
                        URLQueryItem(name: "partNumber", value: "\(partNumber)"),
                        URLQueryItem(name: "uploadId", value: uploadId)
                    ]
                    
                    let (_, response) = try await sendS3RequestWithResponse(method: "PUT", path: newKey, queryItems: query, body: chunkData)
                    
                    guard let etag = response.allHeaderFields["Etag"] as? String ?? response.allHeaderFields["ETag"] as? String else {
                        throw NSError(domain: "S3", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing ETag in response"])
                    }
                    
                    parts.append((partNumber, etag))
                    uploadedSize += Int64(chunkData.count)
                    partNumber += 1
                    
                    try await progress?(uploadedSize, fileSize)
                }
                
                var xmlString = "<CompleteMultipartUpload>\n"
                for part in parts {
                    xmlString += "<Part><PartNumber>\(part.0)</PartNumber><ETag>\(part.1)</ETag></Part>\n"
                }
                xmlString += "</CompleteMultipartUpload>"
                
                let completeQuery = [URLQueryItem(name: "uploadId", value: uploadId)]
                guard let xmlBody = xmlString.data(using: .utf8) else { throw URLError(.badURL) }
                
                let _ = try await sendS3Request(method: "POST", path: newKey, queryItems: completeQuery, additionalHeaders: ["Content-Type": "application/xml"], body: xmlBody)
                
                return newKey
                
            } catch {
                if let uid = currentUploadId {
                    let abortQuery = [URLQueryItem(name: "uploadId", value: uid)]
                    let _ = try? await sendS3Request(method: "DELETE", path: newKey, queryItems: abortQuery)
                }
                throw error
            }
        }
    }
}

struct SigV4Signer {

    private static func hmac(key: [UInt8], stringData: String) -> [UInt8] {
        let symmetricKey = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringData.utf8), using: symmetricKey)
        return Array(signature)
    }
    
    static func generateAuthorizationHeader(
        accessKey: String,
        secretKey: String,
        region: String,
        service: String = "s3",
        dateString: String,      // "20260721"
        amzDateString: String,   // "20260721T111154Z"
        httpMethod: String,
        canonicalURI: String,
        canonicalQueryString: String,
        canonicalHeaders: String,
        signedHeaders: String,
        payloadHash: String      // SHA256(Hex)
    ) -> String {
        
        let canonicalRequest = [
            httpMethod,
            canonicalURI,
            canonicalQueryString,
            canonicalHeaders.trimmingCharacters(in: .newlines),
            "",
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")
        
        let canonicalRequestData = Data(canonicalRequest.utf8)
        let canonicalRequestHash = SHA256.hash(data: canonicalRequestData)
            .compactMap { String(format: "%02x", $0) }
            .joined()
        
        let credentialScope = "\(dateString)/\(region)/\(service)/aws4_request"
        let stringToSign = """
        AWS4-HMAC-SHA256
        \(amzDateString)
        \(credentialScope)
        \(canonicalRequestHash)
        """
        
        let initialKey = Array("AWS4\(secretKey)".utf8)
        let kDate    = hmac(key: initialKey, stringData: dateString)
        let kRegion  = hmac(key: kDate,      stringData: region)
        let kService = hmac(key: kRegion,    stringData: service)
        let kSigning = hmac(key: kService,   stringData: "aws4_request")
        
        let signatureBytes = hmac(key: kSigning, stringData: stringToSign)
        let signature = signatureBytes
            .map { String(format: "%02x", $0) }
            .joined()
        
        return "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }
}

extension S3Storage {
    
    // MARK: - S3 common request function
    
    /// Send API request to S3
    /// - Parameters:
    ///   - method: HTTP method (GET, PUT, POST, DELETE, HEAD)
    ///   - path: object key or path (e.g.: "/folder/file.txt" or "")
    ///   - queryItems: query parameter (e.g.: "?list-type=2"  is [URLQueryItem(name: "list-type", value: "2")])
    ///   - additionalHeaders: additional header (e.g.: ["Range": "bytes=0-1023"])
    ///   - body: request body (PUT or POST)
    /// - Returns: response data
    func sendS3Request(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        additionalHeaders: [String: String] = [:],
        body: Data? = nil
    ) async throws -> Data {
        
        let endpoint = await getEndpoint()
        let accessKey = await getAccessKey()
        let secretKey = await getSecretKey()
        let region = await getRegion()
        let bucket = await getBucket()
        let usePathStyle = await getPathStyle()
        
        guard var urlComponents = URLComponents(string: endpoint) else {
            throw NSError(domain: "S3Storage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Endpoint URL"])
        }
        
        var normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        if usePathStyle {
            // Path-Style: https://endpoint.com/bucket/path
            normalizedPath = "/\(bucket)\(normalizedPath)"
        } else {
            // Virtual Hosted-Style: https://bucket.endpoint.com/path
            if let host = urlComponents.host {
                urlComponents.host = "\(bucket).\(host)"
            }
        }
        
        let encodedPath = s3PercentEncode(normalizedPath, isPath: true)
        urlComponents.percentEncodedPath = encodedPath
        
        if !queryItems.isEmpty {
            let sortedQueries = queryItems.sorted { $0.name < $1.name }
            urlComponents.percentEncodedQuery = sortedQueries.map {
                let key = s3PercentEncode($0.name, isPath: false)
                let value = s3PercentEncode($0.value ?? "", isPath: false)
                return "\(key)=\(value)"
            }.joined(separator: "&")
        }
        
        guard let url = urlComponents.url else {
            throw NSError(domain: "S3Storage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to construct URL"])
        }
        
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: now)
        
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDateString = dateFormatter.string(from: now)
        
        let payloadHash: String
        if let body = body, !body.isEmpty {
            payloadHash = SHA256.hash(data: body).compactMap { String(format: "%02x", $0) }.joined()
        } else {
            // SHA256 for empty body
            payloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        }
        
        var headers: [String: String] = additionalHeaders
        headers["Host"] = url.host
        headers["x-amz-date"] = amzDateString
        headers["x-amz-content-sha256"] = payloadHash
        

        let sortedHeaderKeys = headers.keys.map { $0.lowercased() }.sorted()
        let signedHeaders = sortedHeaderKeys.joined(separator: ";")
        
        let canonicalHeaders = sortedHeaderKeys.map { key in
            let value = headers.first(where: { $0.key.lowercased() == key })?.value.trimmingCharacters(in: .whitespaces) ?? ""
            return "\(key):\(value)\n"
        }.joined()
        
        let canonicalQueryString = urlComponents.percentEncodedQuery ?? ""
        
        let authorization = SigV4Signer.generateAuthorizationHeader(
            accessKey: accessKey,
            secretKey: secretKey,
            region: region,
            dateString: dateString,
            amzDateString: amzDateString,
            httpMethod: method,
            canonicalURI: encodedPath,
            canonicalQueryString: canonicalQueryString,
            canonicalHeaders: canonicalHeaders,
            signedHeaders: signedHeaders,
            payloadHash: payloadHash
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        
        os_log("%{public}@", log: log, type: .debug, "S3 Request: \(method) \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown S3 Error"
            os_log("%{public}@", log: log, type: .error, "S3 Error \(httpResponse.statusCode): \(errorMsg)")
            throw NSError(domain: "S3Storage", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        return data
    }

    func sendS3RequestWithResponse(method: String, path: String, queryItems: [URLQueryItem] = [], additionalHeaders: [String: String] = [:], body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        
        let endpoint = await getEndpoint()
        let accessKey = await getAccessKey()
        let secretKey = await getSecretKey()
        let region = await getRegion()
        let bucket = await getBucket()
        let usePathStyle = await getPathStyle()
        
        guard var urlComponents = URLComponents(string: endpoint) else {
            throw NSError(domain: "S3Storage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Endpoint URL"])
        }
        
        var normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        if usePathStyle {
            // Path-Style: https://endpoint.com/bucket/path
            normalizedPath = "/\(bucket)\(normalizedPath)"
        } else {
            // Virtual Hosted-Style: https://bucket.endpoint.com/path
            if let host = urlComponents.host {
                urlComponents.host = "\(bucket).\(host)"
            }
        }
        
        let encodedPath = s3PercentEncode(normalizedPath, isPath: true)
        urlComponents.percentEncodedPath = encodedPath
        
        if !queryItems.isEmpty {
            let sortedQueries = queryItems.sorted { $0.name < $1.name }
            urlComponents.percentEncodedQuery = sortedQueries.map {
                let key = s3PercentEncode($0.name, isPath: false)
                let value = s3PercentEncode($0.value ?? "", isPath: false)
                return "\(key)=\(value)"
            }.joined(separator: "&")
        }
        
        guard let url = urlComponents.url else {
            throw NSError(domain: "S3Storage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to construct URL"])
        }
        
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: now)
        
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDateString = dateFormatter.string(from: now)
        
        let payloadHash: String
        if let body = body, !body.isEmpty {
            payloadHash = SHA256.hash(data: body).compactMap { String(format: "%02x", $0) }.joined()
        } else {
            // SHA256 for empty body
            payloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        }
        
        var headers: [String: String] = additionalHeaders
        headers["Host"] = url.host
        headers["x-amz-date"] = amzDateString
        headers["x-amz-content-sha256"] = payloadHash
        
        
        let sortedHeaderKeys = headers.keys.map { $0.lowercased() }.sorted()
        let signedHeaders = sortedHeaderKeys.joined(separator: ";")
        
        let canonicalHeaders = sortedHeaderKeys.map { key in
            let value = headers.first(where: { $0.key.lowercased() == key })?.value.trimmingCharacters(in: .whitespaces) ?? ""
            return "\(key):\(value)\n"
        }.joined()
        
        let canonicalQueryString = urlComponents.percentEncodedQuery ?? ""
        
        let authorization = SigV4Signer.generateAuthorizationHeader(
            accessKey: accessKey,
            secretKey: secretKey,
            region: region,
            dateString: dateString,
            amzDateString: amzDateString,
            httpMethod: method,
            canonicalURI: encodedPath,
            canonicalQueryString: canonicalQueryString,
            canonicalHeaders: canonicalHeaders,
            signedHeaders: signedHeaders,
            payloadHash: payloadHash
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        
        os_log("%{public}@", log: log, type: .debug, "S3 Request: \(method) \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "S3", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw NSError(domain: "S3", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        return (data, httpResponse)
    }
    
    // MARK: - helper function
    
    private func s3PercentEncode(_ string: String, isPath: Bool) -> String {
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-_.~")
        
        if isPath {
            allowedCharacters.insert("/")
        }
        
        return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? string
    }
}

extension S3Storage {
    
    // MARK: - ListObjectsV2 API
    
    /// get file/folder list in specified path
    /// - Parameter path: folder path to get ("" or "/" if root)
    func listFolder(path: String) async -> [[String: Any]]? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "listFolder(S3:\(storageName ?? "")) path: \(path)")
                
                // remove prefix "/"
                var prefix = path
                if prefix.hasPrefix("/") {
                    prefix = String(prefix.dropFirst())
                }
                // add last "/"
                if !prefix.isEmpty && !prefix.hasSuffix("/") {
                    prefix += "/"
                }
                
                let queryItems: [URLQueryItem] = [
                    URLQueryItem(name: "list-type", value: "2"),
                    URLQueryItem(name: "delimiter", value: "/"),
                    URLQueryItem(name: "prefix", value: prefix)
                ]
                
                let xmlData = try await sendS3Request(method: "GET", path: "", queryItems: queryItems)
                
                let parser = S3ListParser(data: xmlData, currentPrefix: prefix)
                parser.parse()
                
                return parser.results
            })
        } catch {
            os_log("%{public}@", log: log, type: .error, "ListObjectsV2 Error: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - S3 XML Parser

class S3ListParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private let currentPrefix: String
    var results: [[String: Any]] = []
    
    private var currentElement = ""
    private var currentValue = ""
    
    // 現在パース中のオブジェクト情報
    private var currentItem: [String: Any]?
    
    init(data: Data, currentPrefix: String) {
        self.parser = XMLParser(data: data)
        self.currentPrefix = currentPrefix
        super.init()
        self.parser.delegate = self
    }
    
    func parse() {
        parser.parse()
    }
    
    // start tag
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentValue = ""
        
        if elementName == "Contents" || elementName == "CommonPrefixes" {
            currentItem = [:]
        }
    }
    
    // tag contents
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }
    
    // end tag
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if elementName == "Contents" {
            // file
            if let item = currentItem, let key = item["id"] as? String {
                // exclude prefix (file itself)
                if key != currentPrefix {
                    var finalItem = item
                    finalItem["isFolder"] = false
                    results.append(finalItem)
                }
            }
            currentItem = nil
        } else if elementName == "CommonPrefixes" {
            // folder
            if let item = currentItem, (item["id"] as? String) != nil {
                var finalItem = item
                finalItem["isFolder"] = true
                results.append(finalItem)
            }
            currentItem = nil
        }
        
        // property mapping
        if currentItem != nil {
            switch elementName {
            case "Key":
                currentItem?["id"] = value
                currentItem?["name"] = (value as NSString).lastPathComponent
                currentItem?["parent"] = currentPrefix
            case "Prefix":
                if currentElement == "Prefix" && currentItem != nil {
                    let cleanPrefix = value.hasSuffix("/") ? String(value.dropLast()) : value
                    currentItem?["id"] = value
                    currentItem?["name"] = (cleanPrefix as NSString).lastPathComponent
                    currentItem?["parent"] = currentPrefix
                }
            case "Size":
                currentItem?["size"] = Int(value) ?? 0
            case "LastModified":
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: value) {
                    currentItem?["lastModified"] = Int(date.timeIntervalSince1970 * 1000)
                }
            default:
                break
            }
        }
    }
}

// MARK: - S3 All Keys Parser (remove recurently)

class S3AllKeysParser: NSObject, XMLParserDelegate {
    var keys: [String] = []
    var isTruncated = false
    var nextContinuationToken: String? = nil
    
    private let parser: XMLParser
    private var currentElement = ""
    private var currentValue = ""
    
    init(data: Data) {
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }
    
    func parse() {
        parser.parse()
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentValue = ""
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch elementName {
        case "Key":
            keys.append(value)
        case "IsTruncated":
            isTruncated = (value.lowercased() == "true")
        case "NextContinuationToken":
            nextContinuationToken = value
        default:
            break
        }
    }
}

// MARK: - S3 Multipart Upload Parser
class S3MultipartUploadParser: NSObject, XMLParserDelegate {
    var uploadId: String?
    
    private var currentElement = ""
    private var currentValue = ""
    
    init(data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentValue = ""
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if currentElement == "UploadId" {
            self.uploadId = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

public class S3RemoteItem: RemoteItem {
    let remoteStorage: S3Storage

    override init?(storage: String, id: String) async {
        guard let s = await CloudFactory.shared.storageList.get(storage) as? S3Storage else {
            return nil
        }
        remoteStorage = s
        await super.init(storage: storage, id: id)
    }
    
    public override func open() async -> RemoteStream {
        return await RemoteS3Stream(remote: self)
    }
}

public class RemoteS3Stream: SlotStream {
    let chunkSize: Int64 = 1024*1024
    let remote: S3RemoteItem
    
    init(remote: S3RemoteItem) async {
        self.remote = remote
        await super.init(size: remote.size)
    }
    
    override func setLive(_ live: Bool) {
        if !live {
            let sem = DispatchSemaphore(value: 0)
            Task {
                defer {
                    sem.signal()
                }
                await remote.cancel()
            }
            sem.wait()
        }
    }
    
    override func subFillBuffer(pos: ClosedRange<Int64>) async {
        guard await initialized.wait(timeout: .seconds(60)) == .success else {
            error = true
            return
        }
        guard pos.lowerBound >= 0 && pos.upperBound < size else {
            return
        }
        
        let len = min(size - 1, pos.upperBound) - pos.lowerBound + 1
        let slot_start = Int(pos.lowerBound / chunkSize)
        let slot_count = Int(len / chunkSize) + 1
        
        for s in slot_start..<slot_count + slot_start {
            let start = Int64(s) * chunkSize
            let end = min(start + chunkSize - 1, size - 1)
            
            if await !buffer.dataAvailable(pos: start...end) {
                if let data = await remote.remoteStorage.downloadChunk(fileId: remote.id, range: start...end) {
                    await buffer.store(pos: start, data: data)
                } else {
                    error = true
                    break
                }
            }
        }
    }
}

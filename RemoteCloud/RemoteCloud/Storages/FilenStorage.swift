//
//  FilenStorage.swift
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
import CommonCrypto
import CryptoKit
internal import UniformTypeIdentifiers

struct FilenLoginView: View {
    let authContinuation: CheckedContinuation<Bool, Never>
    let callback: (String, String, String) async -> String?
    let onDismiss: () -> Void
    @State var ok = false

    @State var textEmail = ""
    @State var textPass = ""
    @State var textCode = ""
    @State var useTwoFactorCode = false
    @State var errorMessage = ""
    @State var isPresent = false

    var body: some View {
        ZStack {
            Form {
                Section("email") {
                    TextField("user@example.com", text: $textEmail)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section("Password") {
                    SecureField("password", text: $textPass)
                }
                Section("twoFactorCode") {
                    Toggle("Use twoFactor Login", isOn: $useTwoFactorCode)
                    TextField("XXXXXX", text: $textCode)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .disabled(!useTwoFactorCode)
                }
                Button("Connect") {
                    if textEmail.isEmpty {
                        return
                    }
                    if !useTwoFactorCode {
                        textCode = "XXXXXX"
                    }
                    ok = true
                    Task {
                        if let error = await callback(textEmail, textPass, textCode) {
                            errorMessage = error
                            isPresent.toggle()
                        }
                        else {
                            authContinuation.resume(returning: true)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(ok)
            .alert("Error", isPresented: $isPresent) {
                Button(role: .confirm) {
                    ok = false
                }
            } message: {
                Text(errorMessage)
            }

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

public class FilenStorage: NetworkStorage, URLSessionDataDelegate {
    
    public override func getStorageType() -> CloudStorages {
        return .Filen
    }
    
    let uploadSemaphore = Semaphore(value: 5)
    
    var cache_apiKey = ""
    var cache_baseFolder = ""
    var cache_masterKeys = ""
    
    func apiKey() async -> String {
        if cache_apiKey != "" {
            return cache_apiKey
        }
        if let name = storageName {
            if let key = await getKeyChain(key: "\(name)_accessApiKey") {
                cache_apiKey = key
            }
            return cache_apiKey
        }
        else {
            return ""
        }
    }
    
    func baseFolder() async -> String {
        if cache_baseFolder != "" {
            return cache_baseFolder
        }
        if let name = storageName {
            if let uuid = await getKeyChain(key: "\(name)_accessBaseFolder") {
                cache_baseFolder = uuid
            }
            return cache_baseFolder
        }
        else {
            return ""
        }
    }
    
    func masterKeys() async -> [String] {
        if cache_masterKeys != "" {
            return cache_masterKeys.components(separatedBy: "|").reversed()
        }
        if let name = storageName {
            if let key = await getKeyChain(key: "\(name)_accessMasterKeys") {
                cache_masterKeys = key
            }
            return cache_masterKeys.components(separatedBy: "|").reversed()
        }
        else {
            return []
        }
    }
    
    override func checkToken() async -> Bool {
        if await apiKey().isEmpty {
            return false
        }
        if await baseFolder().isEmpty {
            return false
        }
        return true
    }
    
    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .Filen)
        storageName = name
    }
    
    func data2hex(_ data: Data) -> String {
        var hex = ""
        let table = Array("0123456789abcdef")
        for d in data {
            let hi = (Int(d) & 0xF0) >> 4
            let lo = (Int(d) & 0x0F)
            hex += String(table[hi]) + String(table[lo])
        }
        return hex
    }
    
    func str2Data(_ str: some StringProtocol) -> Data {
        var data = Data()
        var tmp: UInt8 = 0
        for (i, c) in str.enumerated() {
            if c >= "0" && c <= "9" {
                tmp |= c.asciiValue! - Character("0").asciiValue!
            }
            else if c >= "a" && c <= "f" {
                tmp |= c.asciiValue! - Character("a").asciiValue! + 10
            }
            else if c >= "A" && c <= "F" {
                tmp |= c.asciiValue! - Character("A").asciiValue! + 10
            }
            else {
                continue
            }
            if i % 2 == 1 {
                data.append(tmp)
                tmp = 0
            }
            else {
                tmp <<= 4
            }
        }
        return data
    }
    
    func pbkdf2(password: String, salt: Data, iterations: UInt32) -> Data {
        let saltBuffer = [UInt8](salt)
        let hashedLen = Int(CC_SHA512_DIGEST_LENGTH)
        var hashed = Data(count: hashedLen)
        
        let result = hashed.withUnsafeMutableBytes { (body: UnsafeMutableRawBufferPointer) -> Int32 in
            if let baseAddress = body.baseAddress, body.count > 0 {
                let data = baseAddress.assumingMemoryBound(to: UInt8.self)
                return CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                            password, password.count,
                                            saltBuffer, saltBuffer.count,
                                            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                                            iterations,
                                            data, hashedLen)
            }
            return Int32(kCCMemoryFailure)
        }
        
        guard result == kCCSuccess else { fatalError("pbkdf2 error") }
        
        return hashed
    }
    
    func pbkdf2(key: String) -> Data {
        let saltBuffer = [UInt8](key.data(using: .utf8)!)
        let hashedLen = Int(CC_SHA256_DIGEST_LENGTH)
        var hashed = Data(count: hashedLen)
        
        let result = hashed.withUnsafeMutableBytes { (body: UnsafeMutableRawBufferPointer) -> Int32 in
            if let baseAddress = body.baseAddress, body.count > 0 {
                let data = baseAddress.assumingMemoryBound(to: UInt8.self)
                return CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                            key, key.count,
                                            saltBuffer, saltBuffer.count,
                                            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                                            1,
                                            data, hashedLen)
            }
            return Int32(kCCMemoryFailure)
        }
        
        guard result == kCCSuccess else { fatalError("pbkdf2 error") }
        
        return hashed
    }
    
    func sha512(_ str: String) -> Data {
        return sha512(str.data(using: .utf8)!)
    }
    
    func sha512(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA512(bytes.baseAddress!, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }
    
    func sha1(_ str: String) -> Data {
        return sha1(str.data(using: .utf8)!)
    }
    
    func sha1(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.baseAddress!, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }
    
    func hashFn(_ str: String) -> String {
        data2hex(sha1(data2hex(sha512(str.lowercased()))))
    }
    
    func generateRandomString(_ length: Int) -> String {
        let base64Charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return ""
        }
        return bytes.map({ String(base64Charset[Int($0) % base64Charset.count]) }).joined()
    }
    
    func generateRandomBytes(_ length: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return Data()
        }
        return Data(bytes)
    }
    
    func generateRandomHexString(_ length: Int) -> String {
        data2hex(generateRandomBytes(length))
    }
    
    func decodeMetadata(key: String, metadata: String) async -> String? {
        if metadata.prefix(3) == "002" {
            guard metadata.count > 15+16 else { return nil }
            let keyBuffer = pbkdf2(key: key)
            guard let ivBuffer = metadata.dropFirst(3).prefix(12).data(using: .utf8) else { return nil }
            guard let encrypted = Data(base64Encoded: String(metadata.dropFirst(15))) else { return nil }
            let authTag = encrypted.suffix(16)
            let cipherText = encrypted[0..<encrypted.count-16]
            guard let decipher = try? AES.GCM.SealedBox(nonce: .init(data: ivBuffer), ciphertext: cipherText, tag: authTag) else { return nil }
            guard let plain = try? AES.GCM.open(decipher, using: .init(data: keyBuffer)) else { return nil }
            return String(data: plain, encoding: .utf8)
        }
        else if metadata.prefix(3) == "003" {
            guard key.count == 64 else { return nil }
            guard metadata.count > 27+16 else { return nil }
            let keyBuffer = str2Data(key)
            let ivBuffer = str2Data(metadata.dropFirst(3).prefix(24))
            guard let encrypted = Data(base64Encoded: String(metadata.dropFirst(27))) else { return nil }
            let authTag = encrypted.suffix(16)
            let cipherText = encrypted[0..<encrypted.count-16]
            guard let decipher = try? AES.GCM.SealedBox(nonce: .init(data: ivBuffer), ciphertext: cipherText, tag: authTag) else { return nil }
            guard let plain = try? AES.GCM.open(decipher, using: .init(data: keyBuffer)) else { return nil }
            return String(data: plain, encoding: .utf8)
        }
        return nil
    }
    
    func encodeMetadata(key: String, metadata: String) async -> String? {
        var version = 3
        if key.count != 64 || !key.allSatisfy({ "0123456789ABCDEFabcdef".contains($0) }) {
            version = 2
        }
        if (version == 2) {
            let iv = generateRandomString(12)
            let ivBuffer = iv.data(using: .utf8)!
            let keyBuffer = pbkdf2(key: key)
            let dataBuffer = metadata.data(using: .utf8)!
            guard let cipher = try? AES.GCM.seal(dataBuffer, using: .init(data: keyBuffer), nonce: .init(data: ivBuffer)) else { return nil }
            let ciphertext = cipher.ciphertext + cipher.tag
            return "002\(iv)\(ciphertext.base64EncodedString())"
        }
        else if(version == 3) {
            let ivBuffer = generateRandomBytes(12)
            let keyBuffer = str2Data(key)
            let dataBuffer = metadata.data(using: .utf8)!
            guard let cipher = try? AES.GCM.seal(dataBuffer, using: .init(data: keyBuffer), nonce: .init(data: ivBuffer)) else { return nil }
            let ciphertext = cipher.ciphertext + cipher.tag
            return "003\(data2hex(ivBuffer))\(ciphertext.base64EncodedString())"
        }
        return nil
    }
    
    func authCallcack(_ email: String, _ pass: String, _ code: String) async -> String? {
        let (data, message) = await getAuthInfo(email: email)
        guard let authVersion = data["authVersion"] as? Int, authVersion == 2 else {
            return message + " authVersion is not 2"
        }
        guard let salt = data["salt"] as? String else {
            return message + " salt error"
        }
        let saltData = salt.data(using: .utf8)!
        let derivedKey = pbkdf2(password: pass, salt: saltData, iterations: 200000)
        let derivedMasterKeys = data2hex(derivedKey[0..<derivedKey.count/2])
        let derivedPassword = derivedKey[derivedKey.count/2..<derivedKey.count]
        let hashedPassword = sha512(data2hex(derivedPassword))
        let (data2, message2) = await login(email: email, password: data2hex(hashedPassword), twoFactorCode: code, authVersion: authVersion)
        guard let apiKey = data2["apiKey"] as? String else {
            return message2 + " apiKey error"
        }
        guard let masterKeys = data2["masterKeys"] as? String else {
            return message2 + " masterKeys error"
        }
        guard let plainMasterKeys = await decodeMetadata(key: derivedMasterKeys, metadata: masterKeys) else {
            return message2 + " masterKeys decode error"
        }
        let _ = await setKeyChain(key: "\(storageName ?? "")_accessApiKey", value: apiKey)
        let _ = await setKeyChain(key: "\(storageName ?? "")_accessDerivedMasterKeys", value: derivedMasterKeys)
        let _ = await setKeyChain(key: "\(storageName ?? "")_accessMasterKeys", value: plainMasterKeys)
        let _ = await setKeyChain(key: "\(storageName ?? "")_accessBaseFolder", value: await getBaseFolder())
        return nil
    }
    
    func login(email: String, password: String, twoFactorCode: String, authVersion: Int) async -> ([String: Any], String) {
        var request: URLRequest = URLRequest(url: URL(string: "https://gateway.filen.io/v3/login")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let jsondata: [String: Any] = [
            "email": email,
            "password": password,
            "twoFactorCode": twoFactorCode,
            "authVersion": authVersion,
        ]
        guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
            return ([:], "internal error")
        }
        request.httpBody = postData
        
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return ([:], "network error")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return ([:], "response error")
        }
        guard let json = object as? [String: Any] else {
            return ([:], "response error")
        }
        let message = json["message"] as? String ?? "unknown error"
        guard let code = json["code"] as? String, code == "login_success" else {
            return ([:], message)
        }
        guard let d = json["data"] as? [String: Any] else {
            return ([:], message)
        }
        return (d, message)
    }
    
    func getAuthInfo(email: String) async -> ([String: Any], String) {
        var request: URLRequest = URLRequest(url: URL(string: "https://gateway.filen.io/v3/auth/info")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let jsondata: [String: Any] = ["email": email]
        guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
            return ([:], "internal error")
        }
        request.httpBody = postData
        
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return ([:], "network error")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return ([:], "response error")
        }
        guard let json = object as? [String: Any] else {
            return ([:], "response error")
        }
        let message = json["message"] as? String ?? "unknown error"
        guard let dataField = json["data"] as? [String: Any] else {
            return ([:], message)
        }
        return (dataField, message)
    }
    
    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        let authRet = await withCheckedContinuation { authContinuation in
            Task {
                let presentRet = await withCheckedContinuation { continuation in
                    callback(FilenLoginView(authContinuation: authContinuation, callback: authCallcack, onDismiss: {
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
            let _ = await delKeyChain(key: "\(name)_accessApiKey")
            let _ = await delKeyChain(key: "\(name)_accessDerivedMasterKeys")
            let _ = await delKeyChain(key: "\(name)_accessMasterKeys")
            let _ = await delKeyChain(key: "\(name)_accessBaseFolder")
        }
        await super.logout()
    }
    
    func getBaseFolder() async -> String {
        var request: URLRequest = URLRequest(url: URL(string: "https://gateway.filen.io/v3/user/baseFolder")!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(await apiKey())", forHTTPHeaderField: "Authorization")
        
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return ""
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return ""
        }
        guard let json = object as? [String: Any] else {
            return ""
        }
        guard let status = json["status"] as? Bool, status else {
            return ""
        }
        guard let dataField = json["data"] as? [String: Any] else {
            return ""
        }
        guard let uuid = dataField["uuid"] as? String else {
            return ""
        }
        return uuid
    }
    
    func storeItem(item: [String: Any], parentPath: String? = nil, context: NSManagedObjectContext) async {
        guard let id = item["uuid"] as? String else {
            return
        }
        guard let name = item["name"] as? String else {
            return
        }
        guard let parent = item["parent"] as? String else {
            return
        }
        guard let isFolder = item["isFolder"] as? Bool else {
            return
        }
        var ctime = Date(timeIntervalSince1970: 0)
        var mtime = Date(timeIntervalSince1970: 0)
        var hashstr = ""
        var size = 0
        let baseId = await baseFolder()
        if let lastModified = item["lastModified"] as? Int {
            mtime = Date(timeIntervalSince1970: Double(lastModified)/1000)
        }
        else if let timestamp = item["timestamp"] as? Int {
            mtime = Date(timeIntervalSince1970: Double(timestamp))
        }
        if let creation = item["creation"] as? Int {
            ctime = Date(timeIntervalSince1970: Double(creation)/1000)
        }
        if let hash = item["hash"] as? String {
            hashstr = hash
        }
        if let s = item["size"] as? Int {
            size = s
        }
        
        await context.perform {
            var prevPath: String?
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
            if let result = try? context.fetch(fetchRequest) {
                for object in result {
                    if let item = object as? RemoteData {
                        prevPath = item.path
                        let component = prevPath?.components(separatedBy: "/")
                        prevPath = component?.dropLast().joined(separator: "/")
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
            newitem.cdate = ctime
            newitem.mdate = mtime
            newitem.folder = isFolder
            newitem.size = Int64(size)
            newitem.hashstr = hashstr
            newitem.parent = parent == baseId ? "" : parent
            if parent == baseId {
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
        if let items = await listFolder(fileId: fileId) {
            for item in items {
                await storeItem(item: item, parentPath: path, context: viewContext)
            }
            await viewContext.perform {
                try? viewContext.save()
            }
        }
    }
    
    func listFolder(fileId: String) async -> [[String:Any]]? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "listFolder(Filen:\(storageName ?? ""))")
                
                var request: URLRequest = URLRequest(url: URL(string: "https://gateway.filen.io/v3/dir/content")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(await apiKey())", forHTTPHeaderField: "Authorization")
                
                let jsondata: [String: Any] = await ["uuid": fileId == "" ? baseFolder() : fileId]
                guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                    return nil
                }
                request.httpBody = postData
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    return nil
                }
                guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    return nil
                }
                guard let json = object as? [String: Any] else {
                    return nil
                }
                print(json)
                guard let dataField = json["data"] as? [String: Any] else {
                    return nil
                }
                var result = [[String: Any]]()
                if let uploads = dataField["uploads"] as? [[String: Any]] {
                    for item in uploads {
                        guard let uuid = item["uuid"] as? String else {
                            continue
                        }
                        guard let metadata = item["metadata"] as? String else {
                            continue
                        }
                        guard let bucket = item["bucket"] as? String else {
                            continue
                        }
                        guard let region = item["region"] as? String else {
                            continue
                        }
                        guard let parent = item["parent"] as? String else {
                            continue
                        }
                        guard let chunks = item["chunks"] as? Int else {
                            continue
                        }
                        guard let version = item["version"] as? Int else {
                            continue
                        }
                        for key in await masterKeys() {
                            if let plainMetadata = await decodeMetadata(key: key, metadata: metadata) {
                                guard let plainObject = try? JSONSerialization.jsonObject(with: plainMetadata.data(using: .utf8)!, options: []) else {
                                    continue
                                }
                                guard var itemJson = plainObject as? [String: Any] else {
                                    continue
                                }
                                itemJson["uuid"] = uuid
                                itemJson["bucket"] = bucket
                                itemJson["region"] = region
                                itemJson["parent"] = parent
                                itemJson["isFolder"] = false
                                itemJson["chunks"] = chunks
                                itemJson["version"] = version
                                result.append(itemJson)
                                break
                            }
                        }
                    }
                }
                if let folders = dataField["folders"] as? [[String: Any]] {
                    for item in folders {
                        guard let uuid = item["uuid"] as? String else {
                            continue
                        }
                        guard let encrypedName = item["name"] as? String else {
                            continue
                        }
                        guard let parent = item["parent"] as? String else {
                            continue
                        }
                        guard let timestamp = item["timestamp"] as? Int else {
                            continue
                        }
                        for key in await masterKeys() {
                            if let plainMetadata = await decodeMetadata(key: key, metadata: encrypedName) {
                                guard let plainObject = try? JSONSerialization.jsonObject(with: plainMetadata.data(using: .utf8)!, options: []) else {
                                    continue
                                }
                                guard var itemJson = plainObject as? [String: Any] else {
                                    continue
                                }
                                itemJson["uuid"] = uuid
                                itemJson["parent"] = parent
                                itemJson["timestamp"] = timestamp
                                itemJson["isFolder"] = true
                                result.append(itemJson)
                                break
                            }
                        }
                    }
                }
                return result
            })
        }
        catch {
            return nil
        }
    }
    
    func getFileInfo(fileId: String) async -> [String:Any]? {
        guard !fileId.isEmpty else { return nil }
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "getFileInfo(Filen:\(storageName ?? ""))")
                
                var request: URLRequest = URLRequest(url: URL(string: "https://gateway.filen.io/v3/file")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(await apiKey())", forHTTPHeaderField: "Authorization")
                
                let jsondata: [String: Any] = ["uuid": fileId]
                guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                    return nil
                }
                request.httpBody = postData
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    return nil
                }
                guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    return nil
                }
                guard let json = object as? [String: Any] else {
                    return nil
                }
                guard var dataField = json["data"] as? [String: Any] else {
                    return nil
                }
                guard let metadata = dataField["metadata"] as? String else {
                    return nil
                }
                for key in await masterKeys() {
                    if let plainMetadata = await decodeMetadata(key: key, metadata: metadata) {
                        guard let plainObject = try? JSONSerialization.jsonObject(with: plainMetadata.data(using: .utf8)!, options: []) else {
                            continue
                        }
                        guard let itemJson = plainObject as? [String: Any] else {
                            continue
                        }
                        dataField.merge(itemJson, uniquingKeysWith: { $1 })
                        break
                    }
                }
                return dataField
            })
        }
        catch {
            return nil
        }
    }
    
    func downloadChunk(fileinfo: [String:Any], chunk: Int) async -> Data? {
        guard let region = fileinfo["region"] as? String else {
            return nil
        }
        guard let bucket = fileinfo["bucket"] as? String else {
            return nil
        }
        guard let uuid = fileinfo["uuid"] as? String else {
            return nil
        }
        if let cache = await CloudFactory.shared.cache.getCache(storage: storageName!, id: uuid, offset: Int64(chunk * 1024 * 1024), size: -1) {
            if let data = try? Data(contentsOf: cache) {
                os_log("%{public}@", log: log, type: .debug, "hit cache(Filen:\(storageName ?? "") \(uuid) \(chunk)")
                return data
            }
        }
        let hosts = ["egest.filen.io","egest.filen.net"] + (1...6).map({ "egest.filen-\($0).net" })
        let host = hosts.randomElement()!
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "downloadChunk(Filen:\(storageName ?? "") \(uuid) \(chunk))")
                
                var request: URLRequest = URLRequest(url: URL(string: "https://\(host)/\(region)/\(bucket)/\(uuid)/\(chunk)")!)
                request.httpMethod = "GET"
                request.setValue("Bearer \(await apiKey())", forHTTPHeaderField: "Authorization")
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    throw RetryError.Retry
                }
                guard !data.isEmpty else {
                    throw RetryError.Retry
                }
                await CloudFactory.shared.cache.saveCache(storage: storageName!, id: uuid, offset: Int64(chunk * 1024 * 1024), data: data)
                return data
            })
        }
        catch {
            return nil
        }
    }
    
    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await FilenRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await FilenRemoteItem(path: path)
    }
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        do {
            guard let key = await masterKeys().first else { return nil }
            guard let json = try? JSONSerialization.data(withJSONObject: ["name": newname]) else { return nil }
            guard let metadataEncrypted = await encodeMetadata(key: key, metadata: String(data: json, encoding: .utf8)!) else { return nil }
            let nameHashed = hashFn(newname)
            let uuid = UUID().uuidString.lowercased()
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "makeFolder(Filen:\(storageName ?? "")) \(newname)")
                
                var request: URLRequest = URLRequest(url: URL(string: "https://gateway.filen.io/v3/dir/create")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(await apiKey())", forHTTPHeaderField: "Authorization")
                
                let jsondata: [String: Any] = await [
                    "uuid": uuid,
                    "name": metadataEncrypted,
                    "nameHashed": nameHashed,
                    "parent": parentId == "" ? baseFolder(): parentId,
                ]
                guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                    return nil
                }
                request.httpBody = postData
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    return nil
                }
                guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    return nil
                }
                guard let json = object as? [String: Any] else {
                    return nil
                }
                guard let dataField = json["data"] as? [String: Any] else {
                    return nil
                }
                guard let newid = dataField["uuid"] as? String else {
                    return nil
                }
                return newid
            })
        }
        catch {
            return nil
        }
    }
    
    func deleteFile(fileId: String) async -> Bool {
        do {
            let ret = try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "deleteFile(Filen:\(storageName ?? "") \(fileId)")
                
                var request: URLRequest = URLRequest(url: URL(string: "https://gateway.filen.io/v3/file/trash")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(await apiKey())", forHTTPHeaderField: "Authorization")
                
                let jsondata: [String: Any] = [
                    "uuid": fileId,
                ]
                guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                    return false
                }
                request.httpBody = postData
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    return false
                }
                guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    return false
                }
                guard let json = object as? [String: Any] else {
                    return false
                }
                guard let status = json["status"] as? Bool, status else {
                    return false
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
    
    func deleteDir(fileId: String) async -> Bool {
        do {
            let ret = try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "deleteDir(Filen:\(storageName ?? "") \(fileId)")
                
                var request: URLRequest = URLRequest(url: URL(string: "https://gateway.filen.io/v3/dir/trash")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(await apiKey())", forHTTPHeaderField: "Authorization")
                
                let jsondata: [String: Any] = [
                    "uuid": fileId,
                ]
                guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                    return false
                }
                request.httpBody = postData
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    return false
                }
                guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    return false
                }
                guard let json = object as? [String: Any] else {
                    return false
                }
                guard let status = json["status"] as? Bool, status else {
                    return false
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
    
    override func deleteItem(fileId: String) async -> Bool {
        guard let item = await CloudFactory.shared.data.getData(storage: storageName ?? "", fileId: fileId) else { return false }
        if item.folder {
            return await deleteDir(fileId: fileId)
        }
        else {
            return await deleteFile(fileId: fileId)
        }
    }
    
    override func renameItem(fileId: String, newname: String) async -> String? {
        if fileId == "" { return nil }
        
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
        if isFolder {
            let newid = await renameDir(fileId: fileId, newname: newname)
            if newid != nil {
                await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
            }
            return newid
        }
        else {
            let newid = await renameFile(fileId: fileId, newname: newname)
            if newid != nil {
                await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
            }
            return newid
        }
    }
    
    func renameFile(fileId: String, newname: String) async -> String? {
        guard let oldInfo = await getFileInfo(fileId: fileId) else { return nil }
        guard let key = await masterKeys().first else { return nil }
        
        let nameHashed = hashFn(newname)
        let json1: [String: Any] = [
            "name": newname,
            "size": oldInfo["size"] as! Int,
            "mime": oldInfo["mime"] as! String,
            "lastModified": oldInfo["lastModified"] as! Int,
            "creation": oldInfo["creation"] as! Int,
            "hash": oldInfo["hash"] as! String,
            "key": oldInfo["key"] as! String,
            "chunks": oldInfo["chunks"] as! Int,
            "region": oldInfo["region"] as! String,
            "bucket": oldInfo["bucket"] as! String,
            "version": oldInfo["version"] as! Int,
        ]
        guard let json1data = try? JSONSerialization.data(withJSONObject: json1) else { return nil }
        guard let metadataEncrypted = await encodeMetadata(key: key, metadata: String(data: json1data, encoding: .utf8)!) else { return nil }
        guard let json2data = try? JSONSerialization.data(withJSONObject: ["name": newname]) else { return nil }
        guard let nameEncrypted = await encodeMetadata(key: oldInfo["key"] as! String, metadata: String(data: json2data, encoding: .utf8)!) else { return nil }
        
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "renameFile(Filen:\(storageName ?? "")) \(newname)")
                
                var request: URLRequest = URLRequest(url: URL(string: "https://gateway.filen.io/v3/file/rename")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(await apiKey())", forHTTPHeaderField: "Authorization")
                
                let jsondata: [String: Any] = [
                    "uuid": fileId,
                    "name": nameEncrypted,
                    "metadata": metadataEncrypted,
                    "nameHashed": nameHashed,
                ]
                guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                    return nil
                }
                request.httpBody = postData
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    return nil
                }
                guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    return nil
                }
                guard let json = object as? [String: Any] else {
                    return nil
                }
                guard let status = json["status"] as? Bool, status else {
                    return nil
                }
                return fileId
            })
        }
        catch {
            return nil
        }
    }
    
    func renameDir(fileId: String, newname: String) async -> String? {
        guard let key = await masterKeys().first else { return nil }
        
        let nameHashed = hashFn(newname)
        guard let jsondata = try? JSONSerialization.data(withJSONObject: ["name": newname]) else { return nil }
        guard let metadataEncrypted = await encodeMetadata(key: key, metadata: String(data: jsondata, encoding: .utf8)!) else { return nil }
        
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "renameDir(Filen:\(storageName ?? "")) \(newname)")
                
                var request: URLRequest = URLRequest(url: URL(string: "https://gateway.filen.io/v3/dir/rename")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(await apiKey())", forHTTPHeaderField: "Authorization")
                
                let jsondata: [String: Any] = [
                    "uuid": fileId,
                    "name": metadataEncrypted,
                    "nameHashed": nameHashed,
                ]
                guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                    return nil
                }
                request.httpBody = postData
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    return nil
                }
                guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    return nil
                }
                guard let json = object as? [String: Any] else {
                    return nil
                }
                guard let status = json["status"] as? Bool, status else {
                    return nil
                }
                return fileId
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
        
        if isFolder {
            let newid = await moveDir(fileId: fileId, toParentId: toParentId == "" ? baseFolder() : toParentId)
            if newid != nil {
                await CloudFactory.shared.cache.remove(storage: storageName!, id: fromParentId)
                await CloudFactory.shared.cache.remove(storage: storageName!, id: toParentId)
                deleteChildRecursive(parent: fromParentId, context: viewContext)
                deleteChildRecursive(parent: toParentId, context: viewContext)
                await viewContext.perform {
                    try? viewContext.save()
                }
            }
            return newid
        }
        else {
            let newid = await moveFile(fileId: fileId, toParentId: toParentId == "" ? baseFolder() : toParentId)
            if newid != nil {
                await CloudFactory.shared.cache.remove(storage: storageName!, id: fromParentId)
                await CloudFactory.shared.cache.remove(storage: storageName!, id: toParentId)
                deleteChildRecursive(parent: fromParentId, context: viewContext)
                deleteChildRecursive(parent: toParentId, context: viewContext)
                await viewContext.perform {
                    try? viewContext.save()
                }
            }
            return newid
        }
    }
    
    func moveFile(fileId: String, toParentId: String) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "moveFile(Filen:\(storageName ?? "")) \(toParentId)")
                
                var request: URLRequest = URLRequest(url: URL(string: "https://gateway.filen.io/v3/file/move")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(await apiKey())", forHTTPHeaderField: "Authorization")
                
                let jsondata: [String: Any] = [
                    "uuid": fileId,
                    "to": toParentId,
                ]
                guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                    return nil
                }
                request.httpBody = postData
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    return nil
                }
                guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    return nil
                }
                guard let json = object as? [String: Any] else {
                    return nil
                }
                guard let status = json["status"] as? Bool, status else {
                    return nil
                }
                return fileId
            })
        }
        catch {
            return nil
        }
    }
    
    func moveDir(fileId: String, toParentId: String) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "moveDir(Filen:\(storageName ?? "")) \(toParentId)")

                var request: URLRequest = URLRequest(url: URL(string: "https://gateway.filen.io/v3/dir/move")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(await apiKey())", forHTTPHeaderField: "Authorization")
                
                let jsondata: [String: Any] = [
                    "uuid": fileId,
                    "to": toParentId,
                ]
                guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
                    return nil
                }
                request.httpBody = postData
                
                guard let (data, _) = try? await URLSession.shared.data(for: request) else {
                    return nil
                }
                guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    return nil
                }
                guard let json = object as? [String: Any] else {
                    return nil
                }
                guard let status = json["status"] as? Bool, status else {
                    return nil
                }
                return fileId
            })
        }
        catch {
            return nil
        }
    }

    func encryptData(data: Data, key: String) -> Data? {
        var version = 3
        if key.count != 64 || !key.allSatisfy({ "0123456789ABCDEFabcdef".contains($0) }) {
            version = 2
        }
        if version == 2 {
            let iv = generateRandomString(12)
            let ivBuffer = iv.data(using: .utf8)!

            guard let cipher = try? AES.GCM.seal(data, using: .init(data: key.data(using: .utf8)!), nonce: .init(data: ivBuffer)) else { return nil }
            let ciphertext = cipher.ciphertext + cipher.tag
            
            return ivBuffer + ciphertext
        }
        else if version == 3 {
            let ivBuffer = generateRandomBytes(12)
            let keyBuffer = str2Data(key)
            
            guard let cipher = try? AES.GCM.seal(data, using: .init(data: keyBuffer), nonce: .init(data: ivBuffer)) else { return nil }
            let ciphertext = cipher.ciphertext + cipher.tag
            
            return ivBuffer + ciphertext
        }
        return nil
    }
    
    func processFile(target: URL, key: String) -> (url: URL, pos: [Int], digest: [UInt8])? {
        let crypttarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
        
        guard let input = InputStream(url: target) else {
            return nil
        }
        input.open()
        defer {
            input.close()
        }
        guard let output = OutputStream(url: crypttarget, append: false) else {
            return nil
        }
        output.open()
        defer {
            output.close()
        }

        var context = CC_SHA512_CTX()
        CC_SHA512_Init(&context)

        // body
        var buffer = [UInt8](repeating: 0, count: 1*1024*1024)
        var len = 0
        var encryptedLen = 0
        var pos: [Int] = []
        repeat {
            len = input.read(&buffer, maxLength: buffer.count)
            if len < 0 {
                print(input.streamError ?? "")
                return nil
            }
            let plainData = Data(buffer[0..<len])
            CC_SHA512_Update(&context, &buffer, CC_LONG(len))

            guard let encryptedData = encryptData(data: plainData, key: key) else {
                return nil
            }
            pos.append(encryptedLen)
            encryptedLen += encryptedData.count

            let outLength = encryptedData.withUnsafeBytes { ptr in
                output.write(ptr.baseAddress!, maxLength: encryptedData.count)
            }
            guard outLength == encryptedData.count else {
                return nil
            }
        } while len == 1*1024*1024
        pos.append(encryptedLen)

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        CC_SHA512_Final(&digest, &context)
        
        return (url: crypttarget, pos: pos, digest: digest)
    }

    override func uploadFile(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        defer {
            try? FileManager.default.removeItem(at: target)
        }
        guard let key = await masterKeys().first else { return nil }
        guard let ext = uploadname.components(separatedBy: ".").last else { return nil }
        let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        let hosts = ["ingest.filen.io","ingest.filen.net"] + (1...6).map({ "ingest.filen-\($0).net" })
        let attr = try FileManager.default.attributesOfItem(atPath: target.path(percentEncoded: false))
        let fileSize = attr[.size] as! UInt64
        let modifiedDate = attr[.modificationDate] as! Date
        let creationDate = attr[.creationDate] as! Date
        os_log("%{public}@", log: log, type: .debug, "uploadFile(dropbox:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")
        
        let fileUUID = UUID().uuidString.lowercased()
        let encryptionKey = generateRandomHexString(32)
        let rm = generateRandomString(32)
        let uploadKey = generateRandomString(32)
        let parentId = await parentId == "" ? getBaseFolder() : parentId

        guard let (url, pos, hash) = processFile(target: target, key: encryptionKey) else { return nil }
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        let chunks = pos.count-1
        var doneCount = 0
        let api_key = await apiKey()
        try await progress?(0, Int64(pos.last!))
        await withTaskGroup { group in
            var count = 0
            for chunk in 0..<chunks {
                if Task.isCancelled {
                    break
                }
                group.addTask { ()->(Int, String)? in
                    guard let handle = try? FileHandle(forReadingFrom: url) else {
                        return nil
                    }
                    defer {
                        try? handle.close()
                    }
                    try? handle.seek(toOffset: UInt64(pos[chunk]))
                    guard let srcData = try? handle.read(upToCount: pos[chunk+1]-pos[chunk]) else {
                        return nil
                    }
                    let chunkHash = SHA512.hash(data: srcData).map({ String(format: "%02x", $0) }).joined()
                    let host = hosts.randomElement()!
                    let url = URL(string: "https://\(host)/v3/upload")!.appending(queryItems: [
                        .init(name: "uuid", value: fileUUID),
                        .init(name: "index", value: "\(chunk)"),
                        .init(name: "parent", value: parentId),
                        .init(name: "uploadKey", value: uploadKey),
                        .init(name: "hash", value: chunkHash),
                    ])

                    var request: URLRequest = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(api_key)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                    
                    guard let (data, _) = try? await URLSession.shared.upload(for: request, from: srcData) else {
                        return nil
                    }
                    return (chunk, String(data: data, encoding: .utf8)!)
                }
                count += 1
                while count > 10 {
                    if let next = await group.next(), let (i, str) = next {
                        print(i, str)
                        doneCount += 1
                        do {
                            try await progress?(Int64(pos[doneCount]), Int64(pos.last!))
                        }
                        catch {
                            print(error)
                            return
                        }
                    }
                    count -= 1
                }
            }
            while count > 0 {
                if Task.isCancelled {
                    break
                }
                if let next = await group.next(), let (i, str) = next {
                    print(i, str)
                    doneCount += 1
                    do {
                        try await progress?(Int64(pos[doneCount]), Int64(pos.last!))
                    }
                    catch {
                        print(error)
                        return
                    }
                }
                count -= 1
            }
        }
        guard chunks == doneCount else { return nil }

        guard let nameEncrypted = await encodeMetadata(key: encryptionKey, metadata: uploadname) else { return nil }
        guard let mimeEncrypted = await encodeMetadata(key: encryptionKey, metadata: mimeType) else { return nil }
        guard let sizeEncrypted = await encodeMetadata(key: encryptionKey, metadata: "\(fileSize)") else { return nil }
        let metadataJson: [String: Any] = [
            "name": uploadname,
            "size": fileSize,
            "mime": mimeType,
            "key": encryptionKey,
            "lastModified": Int(modifiedDate.timeIntervalSince1970 * 1000),
            "creation": Int(creationDate.timeIntervalSince1970 * 1000),
            "hash": hash.map({ String(format: "%02x", $0) }).joined(),
        ]
        guard let metadataData = try? JSONSerialization.data(withJSONObject: metadataJson) else {
            return nil
        }
        guard let metadata = await encodeMetadata(key: key, metadata: String(data: metadataData, encoding: .utf8)!) else { return nil }
        let hashFilename = hashFn(uploadname)

        var request: URLRequest = URLRequest(url: URL(string: "https://gateway.filen.io/v3/upload/done")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(await apiKey())", forHTTPHeaderField: "Authorization")
        
        let jsondata: [String: Any] = [
            "uuid": fileUUID,
            "name": nameEncrypted,
            "nameHashed": hashFilename,
            "size": sizeEncrypted,
            "chunks": chunks,
            "mime": mimeEncrypted,
            "rm": rm,
            "metadata": metadata,
            "version": 3,
            "uploadKey": uploadKey,
        ]
        guard let postData = try? JSONSerialization.data(withJSONObject: jsondata) else {
            return nil
        }
        request.httpBody = postData
        
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }
        guard let json = object as? [String: Any] else {
            return nil
        }
        print(json)
        guard let status = json["status"] as? Bool, status else {
            return nil
        }
        return fileUUID
    }
}

public class FilenRemoteItem: RemoteItem {
    let remoteStorage: FilenStorage

    override init?(storage: String, id: String) async {
        guard let s = await CloudFactory.shared.storageList.get(storage) as? FilenStorage else {
            return nil
        }
        remoteStorage = s
        await super.init(storage: storage, id: id)
    }
    
    public override func open() async -> RemoteStream {
        return await RemoteFilenStream(remote: self)
    }
}

public class RemoteFilenStream: SlotStream {
    let chunkSize = 1024*1024
    let remote: FilenRemoteItem
    var info: [String: Any] = [:]
    
    init(remote: FilenRemoteItem) async {
        self.remote = remote
        await super.init(size: remote.size)
    }
    
    override func setLive(_ live: Bool) {
        if !live {
            Task {
                await remote.cancel()
            }
        }
    }
    
    override func fillHeader() async {
        if let info = await remote.remoteStorage.getFileInfo(fileId: remote.id) {
            self.info = info
        }
        else {
            print("error on getinfo")
            error = true
        }
        await super.fillHeader()
    }
    
    override func subFillBuffer(pos: ClosedRange<Int64>) async {
        guard await initialized.wait(timeout: .seconds(60)) == .success else {
            error = true
            return
        }
        guard pos.lowerBound >= 0 && pos.upperBound < size else {
            return
        }
        let len = min(size-1, pos.upperBound) - pos.lowerBound + 1
        
        let slot_start = Int(pos.lowerBound) / chunkSize
        let slot_count = Int(len) / chunkSize + 1
        for s in slot_start..<slot_count+slot_start {
            let start = Int64(s) * Int64(chunkSize)
            if await !buffer.dataAvailable(pos: start...start+Int64(chunkSize)) {
                await decodeAndFill(chunk: s)
            }
        }
    }

    func str2Data(_ str: some StringProtocol) -> Data {
        var data = Data()
        var tmp: UInt8 = 0
        for (i, c) in str.enumerated() {
            if c >= "0" && c <= "9" {
                tmp |= c.asciiValue! - Character("0").asciiValue!
            }
            else if c >= "a" && c <= "f" {
                tmp |= c.asciiValue! - Character("a").asciiValue! + 10
            }
            else if c >= "A" && c <= "F" {
                tmp |= c.asciiValue! - Character("A").asciiValue! + 10
            }
            else {
                continue
            }
            if i % 2 == 1 {
                data.append(tmp)
                tmp = 0
            }
            else {
                tmp <<= 4
            }
        }
        return data
    }

    func decodeData(key: String, data: Data) async -> Data? {
        var version = 3
        if key.count != 64 || !key.allSatisfy({ "0123456789ABCDEFabcdef".contains($0) }) {
            version = 2
        }
        for v in (2...version).reversed() {
            if v == 3 {
                guard data.count >= 12+16 else { return nil }
                let keyBuffer = str2Data(key)
                let iv = data[0..<12]
                let encData = data[12..<data.count]
                let authTag = encData.suffix(16)
                let ciphertext = encData.dropLast(16)
                guard let decipher = try? AES.GCM.SealedBox(nonce: .init(data: iv), ciphertext: ciphertext, tag: authTag) else { continue }
                guard let plain = try? AES.GCM.open(decipher, using: .init(data: keyBuffer)) else { continue }
                return plain
            }
            if v == 2 {
                guard data.count >= 12+16 else { return nil }
                guard let keyBuffer = key.data(using: .utf8) else { continue }
                let iv = data[0..<12]
                let encData = data[12..<data.count]
                let authTag = encData.suffix(16)
                let ciphertext = encData.dropLast(16)
                guard let decipher = try? AES.GCM.SealedBox(nonce: .init(data: iv), ciphertext: ciphertext, tag: authTag) else { continue }
                guard let plain = try? AES.GCM.open(decipher, using: .init(data: keyBuffer)) else { continue }
                return plain
            }
        }
        return nil
    }

    func decodeAndFill(chunk: Int) async {
        guard let key = info["key"] as? String else { return }
        guard let version = info["version"] as? Int, version == 2 || version == 3 else { return }
        guard let data = await remote.remoteStorage.downloadChunk(fileinfo: info, chunk: chunk) else {
            error = true
            return
        }
        guard let plain = await decodeData(key: key, data: data) else { return }
        await buffer.store(pos: Int64(chunk * chunkSize), data: plain)
    }
}

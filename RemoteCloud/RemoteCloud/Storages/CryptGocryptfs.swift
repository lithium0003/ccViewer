//
//  CryptGocryptfs.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/03/15.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CommonCrypto
import CoreData
import os.log
import CryptoKit
import Security
import SwiftUI
import AuthenticationServices
internal import UniformTypeIdentifiers

struct PasswordGocryptfsView: View {
    let callback: (String, Bool) async -> Void
    let onDismiss: () -> Void
    @State var ok = false

    @State var isPresented = false
    @State var isAlertPresented = false
    @State var isAlertPresented2 = false

    @State var confPassword = ""
    @State var box = Data()
    @State var crypt_config = [String: [String: String]]()
    
    @State var showPassword = false

    @State var password = ""
    @State var filenameEncryption = true

    var body: some View {
        ZStack {
            Form {
                Text("CryptGocryptfs configuration")
                Section("Password") {
                    HStack {
                        if showPassword {
                            TextField("password", text: $password)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        }
                        else {
                            SecureField("password", text: $password)
                        }
                        Button {
                            showPassword.toggle()
                        } label: {
                            if showPassword {
                                Image(systemName: "eye.slash")
                            }
                            else {
                                Image(systemName: "eye")
                                    .tint(.gray)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section("Encrypt filename") {
                    Toggle("Filename encryption", isOn: $filenameEncryption)
                }
                Button("Select root folder") {
                    ok = true
                    Task {
                        await callback(password, filenameEncryption)
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

struct GocryptfsConf: Codable {
    let Creator: String?
    let EncryptedKey: String
    let ScryptObject: ScryptParams
    let Version: Int
    let FeatureFlags: [String]
    
    struct ScryptParams: Codable {
        let Salt: String
        let N: Int
        let R: Int
        let P: Int
        let KeyLen: Int
    }
}

func parseGocryptfsConf(confData: Data) -> GocryptfsConf? {
    let decoder = JSONDecoder()
    
    do {
        let conf = try decoder.decode(GocryptfsConf.self, from: confData)
        return conf
    } catch {
        print(error)
        return nil
    }
}

public class CryptGocryptfs: ChildStorage {
    
    public override func getStorageType() -> CloudStorages {
        return .CryptGocryptfs
    }

    var name_aes: AES_EME?
    var name_encryption = true
    var dataKey: [UInt8] = []
    var nameKey: [UInt8] = []

    static let fileHeaderVersion: [UInt8] = [0, 2]
    static let fileHeaderSize: Int64 = 18
    static let blockNonceSize: Int64 = 16
    static let blockTagSize: Int64 = 16
    static let blockDataSize: Int64 = 4 * 1024
    static let chunkSize: Int64 = 16 + 4 * 1024 + 16

    override public init(name: String) async {
        await super.init(name: name)
        service = CloudFactory.getServiceName(service: .CryptGocryptfs)
        storageName = name
        if await getKeyChain(key: "\(storageName ?? "")_password") != nil, let filenameEncryption = await getKeyChain(key: "\(storageName ?? "")_namecrypt") {
            if filenameEncryption == "off" {
                name_encryption = false
            }
            else {
                name_encryption = true
            }
        }
        if let dataKeyStr = await getKeyChain(key: "\(storageName ?? "")_dataKey"), let data = Data(base64Encoded: dataKeyStr) {
            dataKey = Array(data)
        }
        if let nameKeyStr = await getKeyChain(key: "\(storageName ?? "")_nameKey"), let data = Data(base64Encoded: nameKeyStr) {
            nameKey = Array(data)
            name_aes = AES_EME(key: nameKey)
        }
    }

    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        let authRet = await withCheckedContinuation { authContinuation in
            Task {
                let presentRet = await withCheckedContinuation { continuation in
                    callback(PasswordGocryptfsView(callback: { password, filenameEncryption in
                        if await super.auth(callback: callback, webAuthenticationSession: webAuthenticationSession, selectItem: selectItem) {
                            
                            let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_password", value: password)
                            let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_namecrypt", value: filenameEncryption ? "on" : "off")
                            authContinuation.resume(returning: true)
                        }
                        else {
                            authContinuation.resume(returning: false)
                        }
                    }, onDismiss: {
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

    override public func logout() async {
        if let name = storageName {
            let _ = await delKeyChain(key: "\(name)_password")
            let _ = await delKeyChain(key: "\(name)_namecrypt")
            let _ = await delKeyChain(key: "\(name)_dataKey")
            let _ = await delKeyChain(key: "\(name)_nameKey")
        }
        await super.logout()
    }

    func findParentStorage(baseId: String = "") async -> [RemoteDataDTO] {
        let fixId = baseId == "" ? baseRootFileId: baseId
        let cached = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: fixId)
        if cached.isEmpty {
            await CloudFactory.shared.storageList.get(baseRootStorage)?.list(fileId: fixId)
            return await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: fixId)
        }
        else {
            return cached
        }
    }

    class func CalcEncryptedSize(org_size: Int64) -> Int64 {
        if org_size < 1 {
            return fileHeaderSize
        }
        
        let chunk_num = org_size / blockDataSize
        let last_chunk_size = org_size % blockDataSize
    
        return fileHeaderSize + chunkSize * chunk_num + (blockNonceSize + blockTagSize + last_chunk_size)
    }

    class func CalcDecryptedSize(crypt_size: Int64) -> Int64 {
        let size = crypt_size - fileHeaderSize
        if size <= 0 {
            return size
        }
        
        let chunk_num = size / chunkSize;
        let last_chunk_size = size % chunkSize;
        
        if last_chunk_size == 0 {
            return chunk_num * blockDataSize
        }
        if last_chunk_size < blockNonceSize + blockTagSize {
            return -1
        }
        
        return chunk_num * blockDataSize + last_chunk_size - (blockNonceSize + blockTagSize)
    }

    private class func storeItem(parentId: String, item: RemoteDataDTO, name: String, isFolder: Bool, id: String, path: String, storage: String, baseStorage: String, existingItem: RemoteData? = nil, context: NSManagedObjectContext) {
        let newid = id
        let newname = name
        let newcdate = item.cdate
        let newmdate = item.mdate
        let newfolder = isFolder
        let newsize = CalcDecryptedSize(crypt_size: item.size)
        
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
        
        targetItem.storage = storage
        targetItem.id = newid
        targetItem.name = newname
        
        let comp = newname.components(separatedBy: ".")
        if comp.count >= 1 {
            targetItem.ext = comp.last!.lowercased()
        } else {
            targetItem.ext = ""
        }
        
        targetItem.cdate = newcdate
        targetItem.mdate = newmdate
        targetItem.folder = newfolder
        targetItem.size = newsize
        targetItem.hashstr = nil
        targetItem.parent = parentId
        
        targetItem.baseStorage = baseStorage
        targetItem.baseId = id
        
        if parentId == "" {
            targetItem.path = "\(storage):/\(newname)"
        } else {
            targetItem.path = "\(path)/\(newname)"
        }
    }
    
    func encodeBase64(input: [UInt8]) -> String {
        if input.isEmpty {
            return ""
        }
        return Data(input).base64EncodedString().replacing("+", with: "-").replacing("/", with: "_").replacing("=", with: "")
    }

    func decodeBase64(input: String) -> Data? {
        let len = input.count
        let padlen = ((len / 4) + 1) * 4 - len
        var inchar = Array(input)
        inchar.append(contentsOf: [Character](repeating: "=", count: padlen))
        return Data(base64Encoded: String(inchar).replacing("-", with: "+").replacing("_", with: "/"))
    }

    private func encryptFileName(clearString: String, diriv: [UInt8]) -> String? {
        guard let clearData = clearString.data(using: .utf8) else {
            return nil
        }
        return encryptFileName(clearData: clearData, diriv: diriv)
    }

    private func encryptFileName(clearData: Data, diriv: [UInt8]) -> String? {
        let paddedBytes = padPKCS7(data: [UInt8](clearData))
        
        guard let encryptedData = name_aes?.encode(input: Data(paddedBytes), tweek: diriv) else {
            return nil
        }

        return encodeBase64(input: Array(encryptedData))
    }
    
    private func decryptFileName(cipherData: Data, diriv: [UInt8]) -> String? {
        decryptFileName(cipherString: String(data: cipherData, encoding: .utf8)!, diriv: diriv)
    }

    private func decryptFileName(cipherString: String, diriv: [UInt8]) -> String? {
        guard let ciphertext = decodeBase64(input: cipherString) else {
            return nil
        }
        guard let decryptedData = name_aes?.decode(input: ciphertext, tweek: diriv) else {
            return nil
        }
        
        guard let unpaddedData = unpadPKCS7(data: Array(decryptedData)) else {
            return nil
        }
        
        return String(data: Data(unpaddedData), encoding: .utf8)
    }

    private func padPKCS7(data: [UInt8]) -> [UInt8] {
        let blockSize = 16
        let padLength = blockSize - (data.count % blockSize)
        let padByte = UInt8(padLength)
        
        var padded = data
        padded.append(contentsOf: [UInt8](repeating: padByte, count: padLength))
        return padded
    }
    
    private func unpadPKCS7(data: [UInt8]) -> [UInt8]? {
        guard !data.isEmpty else { return nil }
        let padLength = Int(data.last!)
        
        guard padLength > 0, padLength <= 16, padLength <= data.count else {
            return nil
        }
        
        for i in 0..<padLength {
            if data[data.count - 1 - i] != UInt8(padLength) {
                return nil
            }
        }
        
        return Array(data[0..<(data.count - padLength)])
    }
    
    func subListChildren(fileId: String, path: String) async {
        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return
        }
        let fixFileId = (fileId == "") ? baseRootFileId : fileId
        let items = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: fixFileId)
        
        var processedItems: [(id: String, name: String, item: RemoteDataDTO)] = []
        
        if name_encryption, let dirivItem = items.first(where: { $0.name == "gocryptfs.diriv" }), let dirivId = dirivItem.id {
            guard let diriv = try? await bs.read(fileId: dirivId) else { return }
            let dirIV = Array(diriv)
            
            var longMap: [String: String] = [:]
            for itemData in items {
                if let name = itemData.name, let id = itemData.id {
                    if name.hasPrefix("gocryptfs.longname."), !name.hasSuffix(".name") {
                        longMap[name] = id
                    }
                }
            }
            
            for itemData in items {
                if let id = itemData.id, let rawName = itemData.name {
                    if rawName == "gocryptfs.conf" || rawName == "gocryptfs.diriv" { continue }
                    
                    if rawName.hasPrefix("gocryptfs.longname.") {
                        if rawName.hasSuffix(".name") {
                            guard let nameData = try? await bs.read(fileId: id) else { continue }
                            let longRawName = String(rawName.dropLast(5))
                            guard let longid = longMap[longRawName], let bodyitem = await CloudFactory.shared.data.getData(storage: baseRootFileId, fileId: longid) else { continue }
                            
                            let finalName = decryptFileName(cipherData: nameData, diriv: dirIV) ?? (bodyitem.name ?? "")
                            processedItems.append((id: longid, name: finalName, item: bodyitem))
                        }
                    } else {
                        let finalName = decryptFileName(cipherData: rawName.data(using: .utf8)!, diriv: dirIV) ?? (itemData.name ?? "")
                        processedItems.append((id: id, name: finalName, item: itemData))
                    }
                }
            }
        } else {
            for itemData in items {
                if let id = itemData.id, let name = itemData.name {
                    if name == "gocryptfs.conf" { continue }
                    processedItems.append((id: id, name: name, item: itemData))
                }
            }
        }
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storageNameStr = storageName ?? ""
        let baseStorageName = baseRootStorage
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", fileId, storageNameStr)
            let existingItems = (try? viewContext.fetch(fetchRequest)) ?? []
            
            var existingDict = [String: RemoteData]()
            for item in existingItems {
                if let id = item.id { existingDict[id] = item }
            }
            
            for processed in processedItems {
                let existing = existingDict.removeValue(forKey: processed.id)
                CryptGocryptfs.storeItem(parentId: fileId, item: processed.item, name: processed.name, isFolder: processed.item.folder, id: processed.id, path: path, storage: storageNameStr, baseStorage: baseStorageName, existingItem: existing, context: viewContext)
            }
            
            for (_, orphan) in existingDict {
                CryptGocryptfs.cascadeDelete(item: orphan, in: viewContext)
            }
            
            try? viewContext.save()
        }
    }
    
    func createGocryptfsConf(password: String) async -> Data? {
        let scryptN = 65536
        let scryptR = 8
        let scryptP = 1
        let keyLen = 32
        
        var saltBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else { return nil }
        let saltBase64 = Data(saltBytes).base64EncodedString()
        
        var masterKeyBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, masterKeyBytes.count, &masterKeyBytes) == errSecSuccess else { return nil }
        
        let passwordBytes = [UInt8](password.data(using: .utf8)!)
        let kekBytes = SCrypt.ComputeDerivedKey(key: passwordBytes, salt: saltBytes, cost: scryptN, blockSize: scryptR, derivedKeyLength: keyLen)
        let kekSymmetric = SymmetricKey(data: kekBytes)
        
        let dataKeyInfo = "AES-GCM file content encryption".data(using: .utf8)!
        let confKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: kekSymmetric, info: dataKeyInfo, outputByteCount: 32)
        
        var nonceBytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, nonceBytes.count, &nonceBytes) == errSecSuccess else { return nil }
        let nonceData = Data(nonceBytes)
        
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let aad = Data(repeating: 0, count: 8)
            
            let sealedBox = try AES.GCM.seal(Data(masterKeyBytes), using: confKey, nonce: nonce, authenticating: aad)
            
            var encryptedKeyData = Data()
            encryptedKeyData.append(nonceData)
            encryptedKeyData.append(sealedBox.ciphertext)
            encryptedKeyData.append(sealedBox.tag)
            let encryptedKeyBase64 = encryptedKeyData.base64EncodedString()
            
            var featureFlags: [String] = [
                "GCMIV128",
                "HKDF"
            ]
            if name_encryption {
                featureFlags.append(contentsOf: [
                    "DirIV",
                    "EMENames",
                    "LongNames",
                    "Raw64"
                ])
            }

            let confDict: [String: Any] = [
                "Creator": "CryptCloudViewer 1.0",
                "EncryptedKey": encryptedKeyBase64,
                "ScryptObject": [
                    "Salt": saltBase64,
                    "N": scryptN,
                    "R": scryptR,
                    "P": scryptP,
                    "KeyLen": keyLen
                ],
                "Version": 2,
                "FeatureFlags": featureFlags
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: confDict, options: [.prettyPrinted, .sortedKeys])

            let masterKey = SymmetricKey(data: masterKeyBytes)

            // for file contents
            let dataKeyInfo = "AES-GCM file content encryption".data(using: .utf8)!
            let derivedDataKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, info: dataKeyInfo, outputByteCount: 32)
                    
            // for file name
            let nameKeyInfo = "EME filename encryption".data(using: .utf8)!
            let derivedNameKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, info: nameKeyInfo, outputByteCount: 32)
                    
            dataKey = [UInt8](derivedDataKey.withUnsafeBytes { Data($0) })
            nameKey = [UInt8](derivedNameKey.withUnsafeBytes { Data($0) })
                    
            name_aes = AES_EME(key: nameKey)

            guard await setKeyChain(key: "\(storageName ?? "")_dataKey", value: Data(dataKey).base64EncodedString()) else {
                return nil
            }
            guard await setKeyChain(key: "\(storageName ?? "")_nameKey", value: Data(nameKey).base64EncodedString()) else {
                return nil
            }

            return jsonData
        } catch {
            print(error)
            return nil
        }
    }

    func saveRootConfig() async {
        let password = await getKeyChain(key: "\(storageName ?? "")_password") ?? ""
        if let filenameEncryption = await getKeyChain(key: "\(storageName ?? "")_namecrypt") {
            if filenameEncryption == "off" {
                name_encryption = false
            }
            else {
                name_encryption = true
            }
        }
        guard let confData = await createGocryptfsConf(password: password) else {
            return
        }
        
        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return
        }

        let conftarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
        let ivtarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
        let newDirIVData = generateDirIV()
        do {
            try confData.write(to: conftarget)
            guard try await bs.upload(parentId: baseRootFileId, uploadname: "gocryptfs.conf", target: conftarget) != nil else {
                try FileManager.default.removeItem(at: conftarget)
                return
            }
            if name_encryption {
                try newDirIVData.write(to: ivtarget)
                guard try await bs.upload(parentId: baseRootFileId, uploadname: "gocryptfs.diriv", target: ivtarget) != nil else {
                    try FileManager.default.removeItem(at: ivtarget)
                    return
                }
            }
        }
        catch {
            print(error)
            return
        }
    }
    
    func loadRootConfig() async {
        let items = await findParentStorage()
        if items.isEmpty {
            await saveRootConfig()
            return
        }
        guard let confitem = items.first(where: { $0.name == "gocryptfs.conf" }), let confid = confitem.id else {
            return
        }
        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return
        }
        guard let downloadedData = try? await bs.read(fileId: confid) else {
            return
        }
        
        guard let conf = parseGocryptfsConf(confData: downloadedData) else {
            return
        }
        guard let saltData = Data(base64Encoded: conf.ScryptObject.Salt) else {
            return
        }
        guard let encryptedKeyData = Data(base64Encoded: conf.EncryptedKey) else {
            return
        }

        let saltBytes = [UInt8](saltData)
        let encryptedKeyBytes = [UInt8](encryptedKeyData)

        let password = await getKeyChain(key: "\(storageName ?? "")_password") ?? ""
        let passwordBytes = [UInt8](password.data(using: .utf8) ?? Data())

        let kekBytes = SCrypt.ComputeDerivedKey(
            key: passwordBytes,
            salt: saltBytes,
            cost: conf.ScryptObject.N,
            blockSize: conf.ScryptObject.R,
            derivedKeyLength: conf.ScryptObject.KeyLen
        )
        let kekSymmetric = SymmetricKey(data: kekBytes)

        let dataKeyInfo = "AES-GCM file content encryption".data(using: .utf8)!
        let confKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: kekSymmetric, info: dataKeyInfo, outputByteCount: 32)
        
        // AES-GCM
        let nonceData = encryptedKeyBytes[0..<16]
        let ciphertext = encryptedKeyBytes[16..<48]
        let tag = encryptedKeyBytes[48..<64]

        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let aad = Data(repeating: 0, count: 8)

            let masterKeyData = try AES.GCM.open(sealedBox, using: confKey, authenticating: aad)

            // HKDF-SHA256
            let masterKey = SymmetricKey(data: masterKeyData)
                
            // for file contents
            let dataKeyInfo = "AES-GCM file content encryption".data(using: .utf8)!
            let derivedDataKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, info: dataKeyInfo, outputByteCount: 32)
                    
            // for file name
            let nameKeyInfo = "EME filename encryption".data(using: .utf8)!
            let derivedNameKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, info: nameKeyInfo, outputByteCount: 32)
                    
            dataKey = [UInt8](derivedDataKey.withUnsafeBytes { Data($0) })
            nameKey = [UInt8](derivedNameKey.withUnsafeBytes { Data($0) })
                    
            name_aes = AES_EME(key: nameKey)
                    
            if conf.FeatureFlags.contains("PlaintextNames") {
                name_encryption = false
            } else {
                name_encryption = true
            }

            guard await setKeyChain(key: "\(storageName ?? "")_dataKey", value: Data(dataKey).base64EncodedString()) else {
                return
            }
            guard await setKeyChain(key: "\(storageName ?? "")_nameKey", value: Data(nameKey).base64EncodedString()) else {
                return
            }
        } catch {
            print(error)
            return
        }
    }
    
    override func listChildren(fileId: String, path: String) async {
        os_log("%{public}@", log: log, type: .debug, "ListChildren(cryptgocryptfs:\(storageName ?? "")) \(fileId)")
        await recoverBaseRootIfNeeded()
        let fixFileId = (fileId == "") ? baseRootFileId : fileId
        
        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return
        }
        await bs.list(fileId: fixFileId)
        
        if fileId == "" {
            await loadRootConfig()
        }
        
        await subListChildren(fileId: fileId, path: path)
    }

    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await CryptGocryptfsRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await CryptGocryptfsRemoteItem(path: path)
    }

    private func generateDirIV() -> Data {
        var iv = [UInt8](repeating: 0, count: 16)
        let result = SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv)
        
        if result == errSecSuccess {
            return Data(iv)
        } else {
            print("fail to make random")
            return Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        }
    }
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        os_log("%{public}@", log: log, type: .debug, "makeFolder(\(String(describing: type(of: self))):\(storageName ?? "") \(parentId)(\(parentPath)) \(newname)")
        
        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return nil
        }
        let fixParentId = parentId == "" ? baseRootFileId : parentId
        
        let items = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: fixParentId)
        let storage = storageName ?? ""
        let baseStorage = baseRootStorage
        
        var createdBaseId: String? = nil
        
        if name_encryption, let dirivItem = items.first(where: { $0.name == "gocryptfs.diriv" }), let dirivId = dirivItem.id {
            guard let diriv = try? await bs.read(fileId: dirivId) else { return nil }
            let dirIV = Array(diriv)
            
            guard let encryptedName = encryptFileName(clearString: newname, diriv: dirIV) else { return nil }
            let newDirIVData = generateDirIV()
            
            if encryptedName.count <= 175 {
                guard let newBaseId = await bs.mkdir(parentId: fixParentId, newname: encryptedName) else { return nil }
                
                let ivtarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
                do {
                    try newDirIVData.write(to: ivtarget)
                    guard try await bs.upload(parentId: newBaseId, uploadname: "gocryptfs.diriv", target: ivtarget) != nil else {
                        try FileManager.default.removeItem(at: ivtarget)
                        return nil
                    }
                } catch {
                    print(error)
                    return nil
                }
                createdBaseId = newBaseId
                
            } else {
                guard let nameData = encryptedName.data(using: .utf8) else { return nil }
                
                let hashDigest = SHA256.hash(data: nameData)
                let hashData = Data(hashDigest)
                let hashBase64 = encodeBase64(input: Array(hashData))
                let baseName = "gocryptfs.longname.\(hashBase64)"
                let nameFileName = "\(baseName).name"
                
                let nametarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
                do {
                    try nameData.write(to: nametarget)
                    guard try await bs.upload(parentId: fixParentId, uploadname: nameFileName, target: nametarget) != nil else {
                        try FileManager.default.removeItem(at: nametarget)
                        return nil
                    }
                } catch {
                    print(error)
                    return nil
                }
                
                guard let newBaseId = await bs.mkdir(parentId: fixParentId, newname: baseName) else { return nil }
                
                let ivtarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
                do {
                    try newDirIVData.write(to: ivtarget)
                    guard try await bs.upload(parentId: newBaseId, uploadname: "gocryptfs.diriv", target: ivtarget) != nil else {
                        try FileManager.default.removeItem(at: ivtarget)
                        return nil
                    }
                } catch {
                    print(error)
                    return nil
                }
                createdBaseId = newBaseId
            }
        } else {
            createdBaseId = await bs.mkdir(parentId: fixParentId, newname: newname)
        }
        
        guard let newBaseId = createdBaseId else { return nil }
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        return await viewContext.perform {
            var ret: String?
            
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
            fetchRequest.fetchLimit = 1
            
            if let results = try? viewContext.fetch(fetchRequest), let item = results.first {
                let newid = item.id!
                let newcdate = item.cdate
                let newmdate = item.mdate
                let newfolder = item.folder
                let newsize = CryptGocryptfs.CalcDecryptedSize(crypt_size: item.size)
                
                let existingFetch = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                existingFetch.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                existingFetch.fetchLimit = 1
                if let existingResults = try? viewContext.fetch(existingFetch), let existing = existingResults.first {
                    CryptGocryptfs.cascadeDelete(item: existing, in: viewContext)
                }
                
                let targetItem = RemoteData(context: viewContext)
                targetItem.storage = storage
                targetItem.id = newid
                targetItem.name = newname
                
                let comp = newname.components(separatedBy: ".")
                if comp.count >= 1 {
                    targetItem.ext = comp.last!.lowercased()
                } else {
                    targetItem.ext = ""
                }
                
                targetItem.cdate = newcdate
                targetItem.mdate = newmdate
                targetItem.folder = newfolder
                targetItem.size = newsize
                targetItem.hashstr = ""
                targetItem.parent = parentId
                
                targetItem.baseStorage = baseStorage
                targetItem.baseId = newBaseId
                
                if parentId == "" {
                    targetItem.path = "\(storage):/\(newname)"
                } else {
                    targetItem.path = "\(parentPath)/\(newname)"
                }
                
                ret = newid
            }
            try? viewContext.save()
            return ret
        }
    }
    
    override func deleteItem(fileId: String) async -> Bool {
        guard fileId != "" else {
            return false
        }
        os_log("%{public}@", log: log, type: .debug, "deleteItem(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId)")
        
        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return false
        }
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        var targetObjectID: NSManagedObjectID? = nil
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            if let item = (try? viewContext.fetch(fetchRequest))?.first {
                targetObjectID = item.objectID
            }
        }
        
        let fixFileId = fileId == "" ? baseRootFileId : fileId
        
        if let baseitem = await CloudFactory.shared.data.getData(storage: baseRootStorage, fileId: fixFileId), let name = baseitem.name, name.hasPrefix("gocryptfs.longname."), let parentId = baseitem.parent {
            let items = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: parentId)
            
            for item in items {
                if item.name == "\(name).name", let id = item.id {
                    guard await bs.delete(fileId: id) else {
                        return false
                    }
                    break
                }
            }
        }
        
        guard await bs.delete(fileId: fileId) else {
            return false
        }
        
        await viewContext.perform {
            if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                CryptGocryptfs.cascadeDelete(item: existing, in: viewContext)
            }
            try? viewContext.save()
        }
        
        return true
    }

    override func renameItem(fileId: String, newname: String) async -> String? {
        let newname = newname.precomposedStringWithCanonicalMapping
        guard fileId != "" else {
            return nil
        }
        
        os_log("%{public}@", log: log, type: .debug, "renameItem(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId)->\(newname)")
        
        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return nil
        }
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        let baseStorage = baseRootStorage
        
        var targetObjectID: NSManagedObjectID? = nil
        var parentId: String? = nil
        var oldItemProps: (cdate: Date?, mdate: Date?, size: Int64, folder: Bool, path: String?)? = nil
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            if let item = (try? viewContext.fetch(fetchRequest))?.first {
                targetObjectID = item.objectID
                parentId = item.parent
                oldItemProps = (item.cdate, item.mdate, item.size, item.folder, item.path)
            }
        }
        guard let pId = parentId else { return nil }
        
        var oldBaseName: String? = nil
        if oldBaseName == nil {
            if let baseitem = await CloudFactory.shared.data.getData(storage: baseStorage, fileId: fileId) {
                oldBaseName = baseitem.name
            } else {
                return nil
            }
        }
        guard let oldname = oldBaseName else { return nil }
        
        let items = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: pId)
        var ret: String?
        
        if name_encryption, let dirivItem = items.first(where: { $0.name == "gocryptfs.diriv" }), let dirivId = dirivItem.id {
            guard let diriv = try? await bs.read(fileId: dirivId) else { return nil }
            let dirIV = Array(diriv)
            
            // generate encrypted name
            guard let encryptedName = encryptFileName(clearString: newname, diriv: dirIV) else { return nil }
            
            if oldname.hasPrefix("gocryptfs.longname.") {
                for item in items {
                    if item.name == "\(oldname).name", let id = item.id {
                        guard await bs.delete(fileId: id) else { return nil }
                        break
                    }
                }
            }
            
            if encryptedName.count <= 175 {
                // short name
                ret = await bs.rename(fileId: fileId, newname: encryptedName)
            } else {
                // long name
                guard let nameData = encryptedName.data(using: .utf8) else { return nil }
                
                let hashDigest = SHA256.hash(data: nameData)
                let hashData = Data(hashDigest)
                
                let hashBase64 = encodeBase64(input: Array(hashData))
                let baseName = "gocryptfs.longname.\(hashBase64)"
                let nameFileName = "\(baseName).name"
                
                let nametarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
                do {
                    try nameData.write(to: nametarget)
                    guard try await bs.upload(parentId: pId, uploadname: nameFileName, target: nametarget) != nil else {
                        try FileManager.default.removeItem(at: nametarget)
                        return nil
                    }
                } catch {
                    print(error)
                    return nil
                }
                
                ret = await bs.rename(fileId: fileId, newname: baseName)
            }
        } else {
            ret = await bs.rename(fileId: fileId, newname: newname)
        }
        
        if let newId = ret {
            await viewContext.perform {
                if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                    CryptGocryptfs.cascadeDelete(item: existing, in: viewContext)
                }
                
                let newItem = RemoteData(context: viewContext)
                newItem.storage = storage
                newItem.id = newId
                newItem.name = newname
                
                let comp = newname.components(separatedBy: ".")
                newItem.ext = comp.count > 1 ? comp.last!.lowercased() : ""
                
                newItem.cdate = oldItemProps?.cdate
                newItem.mdate = oldItemProps?.mdate
                newItem.folder = oldItemProps?.folder ?? false
                newItem.size = oldItemProps?.size ?? 0
                newItem.parent = pId
                
                newItem.baseStorage = baseStorage
                newItem.baseId = newId
                
                if var pathcomp = oldItemProps?.path?.components(separatedBy: "/") {
                    pathcomp.removeLast()
                    pathcomp.append(newname)
                    newItem.path = pathcomp.joined(separator: "/")
                }
                
                try? viewContext.save()
            }
            await CloudFactory.shared.cache.remove(storage: storage, id: fileId)
        }
        
        return ret
    }
    
    override func changeTime(fileId: String, newdate: Date) async -> String? {
        guard fileId != "" else {
            return nil
        }
        
        os_log("%{public}@", log: log, type: .debug, "changeTime(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId)->\(newdate)")
        
        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return nil
        }
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        var targetObjectID: NSManagedObjectID? = nil
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            targetObjectID = (try? viewContext.fetch(fetchRequest))?.first?.objectID
        }
        
        let fixFileId = fileId == "" ? baseRootFileId : fileId
        
        guard let newBaseId = await bs.changeTime(fileId: fixFileId, newdate: newdate) else {
            return nil
        }
        
        let baseRootStorageStr = baseRootStorage
        await viewContext.perform {
            var newcdate: Date? = nil
            var newmdate: Date? = nil
            
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseRootStorageStr)
            fetchRequest.fetchLimit = 1
            if let results = try? viewContext.fetch(fetchRequest), let baseItem = results.first {
                newcdate = baseItem.cdate
                newmdate = baseItem.mdate
            }
            
            if let objID = targetObjectID, let pitem = try? viewContext.existingObject(with: objID) as? RemoteData {
                pitem.cdate = newcdate ?? newdate
                pitem.mdate = newmdate ?? newdate
                
                pitem.baseId = newBaseId
                
                try? viewContext.save()
            }
        }
        return fileId
    }
    
    func getOrgName(fileId: String) async -> String? {
        var orgname: String? = nil
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        return await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            if let results = try? viewContext.fetch(fetchRequest) {
                if let item = results.first {
                    orgname = item.name
                }
            }
            return orgname
        }
    }
    
    override public func targetIsMovable(srcFileId: String, dstFileId: String) async -> Bool {
        true
    }

    override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        guard fileId != "" else {
            return nil
        }
        guard fromParentId != toParentId else {
            return nil
        }
        
        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return nil
        }
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        let baseStorage = baseRootStorage
        
        var targetObjectID: NSManagedObjectID? = nil
        var oldItemProps: (cdate: Date?, mdate: Date?, size: Int64, folder: Bool, name: String)? = nil
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            if let item = (try? viewContext.fetch(fetchRequest))?.first {
                targetObjectID = item.objectID
                if let name = item.name {
                    oldItemProps = (item.cdate, item.mdate, item.size, item.folder, name)
                }
            }
        }
        
        guard let props = oldItemProps else { return nil }
        let orgname = props.name
        
        var toParentPath: String
        if toParentId != "" {
            guard let p = await getParentPath(parentId: toParentId) else {
                return nil
            }
            toParentPath = p
        } else {
            toParentPath = "\(storage):"
        }
        
        os_log("%{public}@", log: log, type: .debug, "moveItem(\(String(describing: type(of: self))):\(storage) \(fileId) \(fromParentId)->\(toParentId)")
        
        guard let baseitem = await CloudFactory.shared.data.getData(storage: baseStorage, fileId: fileId), let baseId = baseitem.id, let name = baseitem.name else {
            return nil
        }
        
        let fixFromParentId = fromParentId == "" ? baseRootFileId : fromParentId
        let fixToParentId = toParentId == "" ? baseRootFileId : toParentId
        let fromitems = await CloudFactory.shared.data.listData(storage: baseStorage, parentID: fixFromParentId)
        let toitems = await CloudFactory.shared.data.listData(storage: baseStorage, parentID: fixToParentId)
        
        var ret = await bs.move(fileId: baseId, fromParent: fixFromParentId, toParent: fixToParentId)
        if ret == nil {
            return nil
        }
        
        if name_encryption, let dirivItem = toitems.first(where: { $0.name == "gocryptfs.diriv" }), let dirivId = dirivItem.id {
            guard let diriv = try? await bs.read(fileId: dirivId) else {
                return nil
            }
            let dirIV = Array(diriv)
            
            guard let encryptedName = encryptFileName(clearString: orgname, diriv: dirIV) else {
                return nil
            }
            
            if name.hasPrefix("gocryptfs.longname.") {
                for item in fromitems {
                    if item.name == "\(name).name", let id = item.id {
                        guard await bs.delete(fileId: id) else {
                            return nil
                        }
                        break
                    }
                }
            }
            
            if encryptedName.count <= 175 {
                ret = await bs.rename(fileId: ret!, newname: encryptedName)
            } else {
                guard let nameData = encryptedName.data(using: .utf8) else { return nil }
                
                let hashDigest = SHA256.hash(data: nameData)
                let hashData = Data(hashDigest)
                
                let hashBase64 = encodeBase64(input: Array(hashData))
                let baseName = "gocryptfs.longname.\(hashBase64)"
                let nameFileName = "\(baseName).name"
                
                let nametarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
                do {
                    try nameData.write(to: nametarget)
                    guard try await bs.upload(parentId: fixToParentId, uploadname: nameFileName, target: nametarget) != nil else {
                        try FileManager.default.removeItem(at: nametarget)
                        return nil
                    }
                } catch {
                    print(error)
                    return nil
                }
                
                ret = await bs.rename(fileId: ret!, newname: baseName)
            }
        }
        
        if let newId = ret {
            await viewContext.perform {
                if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                    CryptGocryptfs.cascadeDelete(item: existing, in: viewContext)
                }
                
                let newItem = RemoteData(context: viewContext)
                newItem.storage = storage
                newItem.id = newId
                newItem.name = orgname
                
                let comp = orgname.components(separatedBy: ".")
                newItem.ext = comp.count > 1 ? comp.last!.lowercased() : ""
                
                newItem.cdate = props.cdate
                newItem.mdate = props.mdate
                newItem.folder = props.folder
                newItem.size = props.size
                newItem.parent = toParentId
                
                newItem.baseStorage = baseStorage
                newItem.baseId = newId
                newItem.path = "\(toParentPath)/\(orgname)"
                
                try? viewContext.save()
            }
            await CloudFactory.shared.cache.remove(storage: storage, id: fileId)
            return newId
        }
        
        return nil
    }
    
    override func readFile(fileId: String, start: Int64?, length: Int64?) async throws -> Data? {
        guard let s = await CloudFactory.shared.storageList.get(baseRootStorage) else {
            return nil
        }
        return try await s.read(fileId: fileId, start: start, length: length)
    }

    override func uploadFile(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        defer {
            try? FileManager.default.removeItem(at: target)
        }
        
        let uploadname = uploadname.precomposedStringWithCanonicalMapping
        os_log("%{public}@", log: log, type: .debug, "uploadFile(\(String(describing: type(of: self))):\(storageName ?? "") \(uploadname)->\(parentId) \(target)")
        
        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return nil
        }
        let parentPath = await getParentPath(parentId: parentId) ?? ""
        
        guard let crypttarget = processFile(target: target) else {
            return nil
        }
        
        let fixParentId = parentId == "" ? baseRootFileId : parentId
        
        let items = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: fixParentId)
        let storage = storageName ?? ""
        let baseStorage = baseRootStorage
        
        var createdBaseId: String? = nil
        
        if name_encryption, let dirivItem = items.first(where: { $0.name == "gocryptfs.diriv" }), let dirivId = dirivItem.id {
            guard let diriv = try? await bs.read(fileId: dirivId) else { return nil }
            let dirIV = Array(diriv)
            
            // generate encrypted name
            guard let encryptedName = encryptFileName(clearString: uploadname, diriv: dirIV) else { return nil }
            
            if encryptedName.count <= 175 {
                // short name
                guard let newBaseId = try? await bs.upload(parentId: fixParentId, uploadname: encryptedName, target: crypttarget, progress: progress) else {
                    return nil
                }
                createdBaseId = newBaseId
            } else {
                // long name
                guard let nameData = encryptedName.data(using: .utf8) else { return nil }
                
                let hashDigest = SHA256.hash(data: nameData)
                let hashData = Data(hashDigest)
                
                let hashBase64 = encodeBase64(input: Array(hashData))
                let baseName = "gocryptfs.longname.\(hashBase64)"
                let nameFileName = "\(baseName).name"
                
                let nametarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
                do {
                    try nameData.write(to: nametarget)
                    guard try await bs.upload(parentId: fixParentId, uploadname: nameFileName, target: nametarget) != nil else {
                        try FileManager.default.removeItem(at: nametarget)
                        return nil
                    }
                } catch {
                    print(error)
                    return nil
                }
                
                guard let newBaseId = try? await bs.upload(parentId: fixParentId, uploadname: baseName, target: crypttarget, progress: progress) else {
                    return nil
                }
                createdBaseId = newBaseId
            }
        } else {
            // raw create
            guard let newBaseId = try? await bs.upload(parentId: fixParentId, uploadname: uploadname, target: crypttarget, progress: progress) else {
                return nil
            }
            createdBaseId = newBaseId
        }
        guard let newBaseId = createdBaseId else { return nil }
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        return await viewContext.perform {
            var ret: String?
            
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
            fetchRequest.fetchLimit = 1
            
            if let results = try? viewContext.fetch(fetchRequest), let item = results.first {
                let newid = item.id!
                let newname = uploadname
                let newcdate = item.cdate
                let newmdate = item.mdate
                let newfolder = item.folder
                let newsize = CryptGocryptfs.CalcDecryptedSize(crypt_size: item.size)
                
                // 既存アイテムがあれば cascadeDelete で一掃する
                let existingFetch = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                existingFetch.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                existingFetch.fetchLimit = 1
                if let existingResults = try? viewContext.fetch(existingFetch), let existing = existingResults.first {
                    CryptGocryptfs.cascadeDelete(item: existing, in: viewContext)
                }
                
                let newitem = RemoteData(context: viewContext)
                newitem.storage = storage
                newitem.id = newid
                newitem.name = newname
                
                let comp = newname.components(separatedBy: ".")
                if comp.count >= 1 {
                    newitem.ext = comp.last!.lowercased()
                } else {
                    newitem.ext = ""
                }
                
                newitem.cdate = newcdate
                newitem.mdate = newmdate
                newitem.folder = newfolder
                newitem.size = newsize
                newitem.hashstr = ""
                newitem.parent = parentId
                
                newitem.baseStorage = baseStorage
                newitem.baseId = newBaseId
                
                if parentId == "" {
                    newitem.path = "\(storage):/\(newname)"
                } else {
                    newitem.path = "\(parentPath)/\(newname)"
                }
                
                ret = newid
            }
            try? viewContext.save()
            return ret
        }
    }
    
    override func processFile(target: URL) -> URL? {
        let key = SymmetricKey(data: dataKey)
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
        
        var fileID = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, fileID.count, &fileID) == errSecSuccess else {
            return nil
        }
        let fileIDData = Data(fileID)

        // header
        var magic = [UInt8](CryptGocryptfs.fileHeaderVersion)
        guard magic.count == output.write(&magic, maxLength: magic.count) else {
            return nil
        }
        
        guard fileID.count == output.write(&fileID, maxLength: fileID.count) else {
            return nil
        }
        
        var buffer = [UInt8](repeating: 0, count: Int(CryptGocryptfs.blockDataSize))
        var blockNumber: UInt64 = 0
        var len = 0
        repeat {
            len = input.read(&buffer, maxLength: buffer.count)
            if len < 0 {
                print(input.streamError ?? "")
                return nil
            }
            if len == 0 {
                break
            }

            let chunk = Data(bytes: &buffer, count: len)
            var nonceBytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, nonceBytes.count, &nonceBytes) == errSecSuccess else {
                return nil
            }
            let nonceData = Data(nonceBytes)
            var encryptedBlock = Data()

            do {
                let nonce = try AES.GCM.Nonce(data: nonceData)

                var aad = Data()
                var bnBigEndian = blockNumber.bigEndian
                withUnsafeBytes(of: &bnBigEndian) { bytes in
                    aad.append(contentsOf: bytes)
                }
                aad.append(fileIDData)

                let sealedBox = try AES.GCM.seal(chunk, using: key, nonce: nonce, authenticating: aad)
                encryptedBlock.append(nonceData)
                encryptedBlock.append(sealedBox.ciphertext)
                encryptedBlock.append(sealedBox.tag)
            } catch {
                print("block \(blockNumber) fail to encrypt: \(error)")
                return nil
            }

            var outbuf = [UInt8](encryptedBlock)
            guard outbuf.count == output.write(&outbuf, maxLength: outbuf.count) else {
                return nil
            }
            
            blockNumber += 1
        } while len == CryptGocryptfs.blockDataSize
        
        return crypttarget
    }
}

public class CryptGocryptfsRemoteItem: RemoteItem {
    let remoteStorage: CryptGocryptfs
    
    override init?(storage: String, id: String) async {
        guard let s = await CloudFactory.shared.storageList.get(storage) as? CryptGocryptfs else {
            return nil
        }
        remoteStorage = s
        await super.init(storage: storage, id: id)
    }
    
    public override func open() async -> RemoteStream {
        return await RemoteCryptGocryptfsStream(remote: self)
    }
}

public class RemoteCryptGocryptfsStream: SlotStream {
    let remote: CryptGocryptfsRemoteItem
    let OrignalLength: Int64
    let CryptedLength: Int64
    var fileID = [UInt8](repeating: 0, count: 16)
    let key: SymmetricKey
    
    init(remote: CryptGocryptfsRemoteItem) async {
        self.remote = remote
        OrignalLength = remote.size
        CryptedLength = CryptGocryptfs.CalcEncryptedSize(org_size: OrignalLength)
        key = SymmetricKey(data: remote.remoteStorage.dataKey)
        await super.init(size: OrignalLength)
    }
    
    override func cancelInternal() async {
        await remote.cancel()
    }
    
    override func fillHeader() async {
        guard let data = try? await remote.read(start: 0, length: CryptGocryptfs.fileHeaderSize) else {
            print("error on header null")
            await setError()
            await super.fillHeader()
            return
        }
        if !CryptGocryptfs.fileHeaderVersion.elementsEqual(data.prefix(CryptGocryptfs.fileHeaderVersion.count)) {
            print("error on header check")
            await super.fillHeader()
            await setError()
        }
        fileID.replaceSubrange(0..<fileID.count, with: data.dropFirst(CryptGocryptfs.fileHeaderVersion.count))
        await super.fillHeader()
    }
    
    override func subFillBuffer(pos: ClosedRange<Int64>) async {
        guard await initialized.wait(timeout: .seconds(10)) == .success else {
            await setError()
            return
        }
        
        let chunksize = CryptGocryptfs.chunkSize
        let orgBlocksize = CryptGocryptfs.blockDataSize
        let headersize = CryptGocryptfs.fileHeaderSize
        if await !buffer.dataAvailable(pos: pos) {
            guard pos.lowerBound >= 0 && pos.upperBound < size else {
                return
            }
            let len = min(size-1, pos.upperBound) - pos.lowerBound + 1
            let slot1 = pos.lowerBound / orgBlocksize
            let pos2 = slot1 * chunksize + headersize
            var clen = len / orgBlocksize * chunksize
            if len % orgBlocksize != 0 {
                clen += len % orgBlocksize + CryptGocryptfs.blockNonceSize + CryptGocryptfs.blockTagSize
            }
            guard pos2 >= 0 && pos2 < CryptedLength else {
                return
            }
            if pos2 + clen > CryptedLength {
                clen = CryptedLength - pos2
            }
            guard clen >= 0 && clen < CryptedLength else {
                return
            }
            guard let data = try? await remote.read(start: pos2, length: clen) else {
                print("error on readFile")
                await setError()
                return
            }
            var slot = slot1
            var plainBlock = Data()
            
            let dataStart = data.startIndex
            // offset: 0..<data.count as relative
            for offset in stride(from: 0, to: data.count, by: Int(chunksize)) {
                let chunkStart = dataStart + offset
                let chunkEnd = dataStart + min(offset + Int(chunksize), data.count)
                
                let chunk = data[chunkStart..<chunkEnd]
                guard chunk.count >= 32 else {
                    await setError()
                    return
                }
                
                let ivData = chunk.prefix(16)
                let tagData = chunk.suffix(16)
                let cipherData = chunk[chunk.startIndex + 16 ..< chunk.endIndex - 16]
                
                do {
                    let nonce = try AES.GCM.Nonce(data: ivData)
                    let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: cipherData, tag: tagData)
                    
                    var aad = Data()
                    var bnBigEndian = slot.bigEndian
                    withUnsafeBytes(of: &bnBigEndian) { bytes in
                        aad.append(contentsOf: bytes)
                    }
                    aad.append(contentsOf: fileID)
                    
                    let plainData = try AES.GCM.open(sealedBox, using: key, authenticating: aad)
                    plainBlock.append(plainData)
                    
                }
                catch let error1 {
                    print(error1)
                    await setError()
                    return
                }
                slot += 1
                guard !error else {
                    return
                }
            }
            await buffer.store(pos: pos.lowerBound, data: plainBlock)
        }
    }
}

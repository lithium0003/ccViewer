//
//  CryptRclone.swift
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

    let fileHeaderVersion: [UInt8] = [0, 2]
    let fileHeaderSize: Int64 = 18
    let blockNonceSize: Int64 = 16
    let blockTagSize: Int64 = 16
    let blockDataSize: Int64 = 4 * 1024
    let chunkSize: Int64 = 16 + 4 * 1024 + 16

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

    func findParentStorage(baseId: String = "") async -> [RemoteData] {
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

    func CalcEncryptedSize(org_size: Int64) -> Int64 {
        if org_size < 1 {
            return fileHeaderSize
        }
        
        let chunk_num = org_size / blockDataSize
        let last_chunk_size = org_size % blockDataSize
    
        return fileHeaderSize + chunkSize * chunk_num + (blockNonceSize + blockTagSize + last_chunk_size)
    }

    func CalcDecryptedSize(crypt_size: Int64) -> Int64 {
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

    func storeItem(parentId: String, item: RemoteItem, name: String, isFolder: Bool, id: String, path: String, context: NSManagedObjectContext) {
        os_log("%{public}@", log: log, type: .debug, "storeItem(cryptgocryptfs:\(storageName ?? "")) \(name)")
        
        context.performAndWait {
            let newid = id
            let newname = name
            let newcdate = item.cDate
            let newmdate = item.mDate
            let newfolder = isFolder
            let newsize = CalcDecryptedSize(crypt_size: item.size)

            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, self.storageName ?? "")
            if let result = try? context.fetch(fetchRequest) {
                for object in result {
                    context.delete(object as! NSManagedObject)
                }
            }
            
            let newitem = RemoteData(context: context)
            newitem.storage = self.storageName
            newitem.id = newid
            newitem.name = newname
            let comp = newname.components(separatedBy: ".")
            if comp.count >= 1 {
                newitem.ext = comp.last!.lowercased()
            }
            newitem.cdate = newcdate
            newitem.mdate = newmdate
            newitem.folder = newfolder
            newitem.size = newsize
            newitem.hashstr = ""
            newitem.parent = parentId
            if parentId == "" {
                newitem.path = "\(self.storageName ?? ""):/\(newname)"
            }
            else {
                newitem.path = "\(path)/\(newname)"
            }
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

        let viewContext = CloudFactory.shared.data.viewContext
        if name_encryption, let dirivItem = items.first(where: { $0.name == "gocryptfs.diriv" }), let dirivId = dirivItem.id {
            guard let diriv = try? await bs.read(fileId: dirivId) else {
                return
            }
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
                    // ignore files
                    if rawName == "gocryptfs.conf" {
                        continue
                    }
                    if rawName == "gocryptfs.diriv" {
                        continue
                    }
                    
                    // long names
                    if rawName.hasPrefix("gocryptfs.longname.") {
                        if rawName.hasSuffix(".name") {
                            guard let nameData = try? await bs.read(fileId: id) else {
                                continue
                            }
                            
                            let longRawName = String(rawName.dropLast(5))
                            guard let longid = longMap[longRawName], let bodyitem = await bs.get(fileId: longid) else {
                                continue
                            }
                            if let name = decryptFileName(cipherData: nameData, diriv: dirIV) {
                                storeItem(parentId: fileId, item: bodyitem, name: name, isFolder: bodyitem.isFolder, id: longid, path: path, context: viewContext)
                            }
                            else {
                                storeItem(parentId: fileId, item: bodyitem, name: bodyitem.name, isFolder: bodyitem.isFolder, id: longid, path: path, context: viewContext)
                            }
                        }
                    }
                    else {
                        guard let bodyitem = await bs.get(fileId: id) else {
                            continue
                        }
                        if let name = decryptFileName(cipherData: rawName.data(using: .utf8)!, diriv: dirIV) {
                            storeItem(parentId: fileId, item: bodyitem, name: name, isFolder: bodyitem.isFolder, id: id, path: path, context: viewContext)
                        }
                        else {
                            storeItem(parentId: fileId, item: bodyitem, name: bodyitem.name, isFolder: bodyitem.isFolder, id: id, path: path, context: viewContext)
                        }
                    }
                }
            }
        }
        else {
            // raw filename
            for itemData in items {
                if let id = itemData.id, let item = await bs.get(fileId: id) {
                    // ignore files
                    if item.name == "gocryptfs.conf" {
                        continue
                    }
                    storeItem(parentId: fileId, item: item, name: item.name, isFolder: item.isFolder, id: id, path: path, context: viewContext)
                }
            }
        }
        await viewContext.perform {
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
        await viewContext.perform {
            try? viewContext.save()
        }

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

        let viewContext = CloudFactory.shared.data.viewContext
        let items = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: fixParentId)
        var ret: String?
        let storage = storageName ?? ""
        let baseStorage = baseRootStorage
        if name_encryption, let dirivItem = items.first(where: { $0.name == "gocryptfs.diriv" }), let dirivId = dirivItem.id {
            guard let diriv = try? await bs.read(fileId: dirivId) else {
                return nil
            }
            let dirIV = Array(diriv)

            let decryptSize = { size in
                self.CalcDecryptedSize(crypt_size: size)
            }

            // generate encrypted name
            guard let encryptedName = encryptFileName(clearString: newname, diriv: dirIV) else {
                return nil
            }
            let newDirIVData = generateDirIV()
            if encryptedName.count <= 175 {
                // short name
                guard let newBaseId = await bs.mkdir(parentId: fixParentId, newname: encryptedName) else {
                    return nil
                }

                let ivtarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
                do {
                    try newDirIVData.write(to: ivtarget)
                    guard try await bs.upload(parentId: newBaseId, uploadname: "gocryptfs.diriv", target: ivtarget) != nil else {
                        try FileManager.default.removeItem(at: ivtarget)
                        return nil
                    }
                }
                catch {
                    print(error)
                    return nil
                }

                await viewContext.perform {
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
                    if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                        if let item = items.first {
                            let newid = item.id!
                            let newcdate = item.cdate
                            let newmdate = item.mdate
                            let newfolder = item.folder
                            let newsize = decryptSize(item.size)
                            
                            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                            if let result = try? viewContext.fetch(fetchRequest) {
                                for object in result {
                                    viewContext.delete(object as! NSManagedObject)
                                }
                            }
                            
                            let newitem = RemoteData(context: viewContext)
                            newitem.storage = storage
                            newitem.id = newid
                            newitem.name = newname
                            let comp = newname.components(separatedBy: ".")
                            if comp.count >= 1 {
                                newitem.ext = comp.last!.lowercased()
                            }
                            newitem.cdate = newcdate
                            newitem.mdate = newmdate
                            newitem.folder = newfolder
                            newitem.size = newsize
                            newitem.hashstr = ""
                            newitem.parent = parentId
                            if parentId == "" {
                                newitem.path = "\(storage):/\(newname)"
                            }
                            else {
                                newitem.path = "\(parentPath)/\(newname)"
                            }
                            ret = newid
                        }
                    }
                }
            }
            else {
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
                }
                catch {
                    print(error)
                    return nil
                }

                guard let newBaseId = await bs.mkdir(parentId: fixParentId, newname: baseName) else {
                    return nil
                }

                let ivtarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
                do {
                    try newDirIVData.write(to: ivtarget)
                    guard try await bs.upload(parentId: newBaseId, uploadname: "gocryptfs.diriv", target: ivtarget) != nil else {
                        try FileManager.default.removeItem(at: ivtarget)
                        return nil
                    }
                }
                catch {
                    print(error)
                    return nil
                }

                await viewContext.perform {
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
                    if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                        if let item = items.first {
                            let newid = item.id!
                            let newcdate = item.cdate
                            let newmdate = item.mdate
                            let newfolder = item.folder
                            let newsize = decryptSize(item.size)
                            
                            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                            if let result = try? viewContext.fetch(fetchRequest) {
                                for object in result {
                                    viewContext.delete(object as! NSManagedObject)
                                }
                            }
                            
                            let newitem = RemoteData(context: viewContext)
                            newitem.storage = storage
                            newitem.id = newid
                            newitem.name = newname
                            let comp = newname.components(separatedBy: ".")
                            if comp.count >= 1 {
                                newitem.ext = comp.last!.lowercased()
                            }
                            newitem.cdate = newcdate
                            newitem.mdate = newmdate
                            newitem.folder = newfolder
                            newitem.size = newsize
                            newitem.hashstr = ""
                            newitem.parent = parentId
                            if parentId == "" {
                                newitem.path = "\(storage):/\(newname)"
                            }
                            else {
                                newitem.path = "\(parentPath)/\(newname)"
                            }
                            ret = newid
                        }
                    }
                }
            }
        }
        else {
            // raw create
            guard let newBaseId = await bs.mkdir(parentId: fixParentId, newname: newname) else {
                return nil
            }
            let decryptSize = { size in
                self.CalcDecryptedSize(crypt_size: size)
            }

            await viewContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
                if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                    if let item = items.first {
                        let newid = item.id!
                        let newname = item.name!
                        let newcdate = item.cdate
                        let newmdate = item.mdate
                        let newfolder = item.folder
                        let newsize = decryptSize(item.size)
                        
                        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                        if let result = try? viewContext.fetch(fetchRequest) {
                            for object in result {
                                viewContext.delete(object as! NSManagedObject)
                            }
                        }
                        
                        let newitem = RemoteData(context: viewContext)
                        newitem.storage = storage
                        newitem.id = newid
                        newitem.name = newname
                        let comp = newname.components(separatedBy: ".")
                        if comp.count >= 1 {
                            newitem.ext = comp.last!.lowercased()
                        }
                        newitem.cdate = newcdate
                        newitem.mdate = newmdate
                        newitem.folder = newfolder
                        newitem.size = newsize
                        newitem.hashstr = ""
                        newitem.parent = parentId
                        if parentId == "" {
                            newitem.path = "\(storage):/\(newname)"
                        }
                        else {
                            newitem.path = "\(parentPath)/\(newname)"
                        }
                        ret = newid
                    }
                }
            }
        }
        await viewContext.perform {
            try? viewContext.save()
        }
        return ret
    }

    override func deleteItem(fileId: String) async -> Bool {
        guard fileId != "" else {
            return false
        }
        os_log("%{public}@", log: log, type: .debug, "deleteItem(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId)")

        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return false
        }
        let viewContext = CloudFactory.shared.data.viewContext
        let storage = storageName ?? ""
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
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                for item in items {
                    viewContext.delete(item)
                }
                try? viewContext.save()
            }
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
        let viewContext = CloudFactory.shared.data.viewContext
        guard let baseitem = await CloudFactory.shared.data.getData(storage: baseRootStorage, fileId: fileId), let parentId = baseitem.parent, let baseId = baseitem.id, let oldname = baseitem.name else {
            return nil
        }
        let items = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: parentId)
        var ret: String?
        let storage = storageName ?? ""
        if name_encryption, let dirivItem = items.first(where: { $0.name == "gocryptfs.diriv" }), let dirivId = dirivItem.id {
            guard let diriv = try? await bs.read(fileId: dirivId) else {
                return nil
            }
            let dirIV = Array(diriv)
            
            // generate encrypted name
            guard let encryptedName = encryptFileName(clearString: newname, diriv: dirIV) else {
                return nil
            }

            if oldname.hasPrefix("gocryptfs.longname.") {
                for item in items {
                    if item.name == "\(oldname).name", let id = item.id {
                        guard await bs.delete(fileId: id) else {
                            return nil
                        }
                        break
                    }
                }
            }
            
            if encryptedName.count <= 175 {
                // short name
                ret = await bs.rename(fileId: baseId, newname: encryptedName)
            }
            else {
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
                    guard try await bs.upload(parentId: parentId, uploadname: nameFileName, target: nametarget) != nil else {
                        try FileManager.default.removeItem(at: nametarget)
                        return nil
                    }
                }
                catch {
                    print(error)
                    return nil
                }

                ret = await bs.rename(fileId: baseId, newname: baseName)
            }
        }
        else {
            ret = await bs.rename(fileId: baseId, newname: newname)
        }
        if ret != nil {
            await viewContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                    if let item = items.first {
                        item.id = ret
                        item.name = newname
                        let comp = newname.components(separatedBy: ".")
                        if comp.count >= 1 {
                            item.ext = comp.last!.lowercased()
                        }
                        if var pathcomp = item.path?.components(separatedBy: "/") {
                            pathcomp.removeLast()
                            pathcomp.append(newname)
                            item.path = pathcomp.joined(separator: "/")
                        }
                    }
                }
                try? viewContext.save()
            }
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
        let fixFileId = fileId == "" ? baseRootFileId : fileId

        guard let newBaseId = await bs.chagetime(fileId: fixFileId, newdate: newdate) else {
            return nil
        }
        
        let viewContext = CloudFactory.shared.data.viewContext
        let baseRootStorage = baseRootStorage
        let storage = storageName ?? ""
        await viewContext.perform {
            var newcdate: Date? = nil
            var newmdate: Date? = nil
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseRootStorage)
            if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                if let baseItem = items.first {
                    newcdate = baseItem.cdate
                    newmdate = baseItem.mdate
                }
            }

            let fetchRequest2 = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest2.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest2), let items1 = result as? [RemoteData] {
                if let pitem = items1.first {
                    pitem.cdate = newcdate
                    pitem.mdate = newmdate
                    try? viewContext.save()
                }
            }
        }
        return fileId
    }

    func getOrgName(fileId: String) async -> String? {
        var orgname: String? = nil
        let viewContext = CloudFactory.shared.data.viewContext
        let storage = storageName ?? ""
        return await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                if let item = items.first {
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
        
        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return nil
        }
        
        guard let orgname = await getOrgName(fileId: fileId) else {
            return nil
        }
        
        guard fromParentId != toParentId else {
            return nil
        }
        
        var toParentPath: String
        if toParentId != "" {
            guard let p = await getParentPath(parentId: toParentId) else {
                return nil
            }
            toParentPath = p
        }
        else {
            toParentPath = "\(storageName ?? ""):"
        }
        
        os_log("%{public}@", log: log, type: .debug, "moveItem(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId) \(fromParentId)->\(toParentId)")

        guard let baseitem = await CloudFactory.shared.data.getData(storage: baseRootStorage, fileId: fileId), let baseId = baseitem.id, let name = baseitem.name else {
            return nil
        }

        let fixFromParentId = fromParentId == "" ? baseRootFileId : fromParentId
        let fixToParentId = toParentId == "" ? baseRootFileId : toParentId
        let fromitems = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: fixFromParentId)
        let toitems = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: fixToParentId)

        var ret = await bs.move(fileId: baseId, fromParent: fixFromParentId, toParent: fixToParentId)
        if ret == nil {
            return nil
        }
        if name_encryption, let dirivItem = toitems.first(where: { $0.name == "gocryptfs.diriv" }), let dirivId = dirivItem.id {
            guard let diriv = try? await bs.read(fileId: dirivId) else {
                return nil
            }
            let dirIV = Array(diriv)
            
            // generate encrypted name
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
                // short name
                ret = await bs.rename(fileId: ret!, newname: encryptedName)
            }
            else {
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
                    guard try await bs.upload(parentId: fixToParentId, uploadname: nameFileName, target: nametarget) != nil else {
                        try FileManager.default.removeItem(at: nametarget)
                        return nil
                    }
                }
                catch {
                    print(error)
                    return nil
                }

                ret = await bs.rename(fileId: ret!, newname: baseName)
            }
        }

        // register record
        let viewContext = CloudFactory.shared.data.viewContext
        let storage = storageName ?? ""
        return await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                if let item = items.first {
                    item.id = ret
                    item.parent = toParentId
                    item.path = "\(toParentPath)/\(item.name ?? "")"
                    try? viewContext.save()
                    return ret
                }
            }
            return nil
        }
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

        let viewContext = CloudFactory.shared.data.viewContext
        let items = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: fixParentId)
        var ret: String?
        let storage = storageName ?? ""
        let baseStorage = baseRootStorage
        if name_encryption, let dirivItem = items.first(where: { $0.name == "gocryptfs.diriv" }), let dirivId = dirivItem.id {
            guard let diriv = try? await bs.read(fileId: dirivId) else {
                return nil
            }
            let dirIV = Array(diriv)

            let decryptSize = { size in
                self.CalcDecryptedSize(crypt_size: size)
            }

            // generate encrypted name
            guard let encryptedName = encryptFileName(clearString: uploadname, diriv: dirIV) else {
                return nil
            }
            if encryptedName.count <= 175 {
                // short name
                guard let newBaseId = try? await bs.upload(parentId: fixParentId, uploadname: encryptedName, target: crypttarget, progress: progress) else {
                    return nil
                }

                await viewContext.perform {
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
                    if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                        if let item = items.first {
                            let newid = item.id!
                            let newname = uploadname
                            let newcdate = item.cdate
                            let newmdate = item.mdate
                            let newfolder = item.folder
                            let newsize = decryptSize(item.size)
                            
                            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                            if let result = try? viewContext.fetch(fetchRequest) {
                                for object in result {
                                    viewContext.delete(object as! NSManagedObject)
                                }
                            }
                            
                            let newitem = RemoteData(context: viewContext)
                            newitem.storage = storage
                            newitem.id = newid
                            newitem.name = newname
                            let comp = newname.components(separatedBy: ".")
                            if comp.count >= 1 {
                                newitem.ext = comp.last!.lowercased()
                            }
                            newitem.cdate = newcdate
                            newitem.mdate = newmdate
                            newitem.folder = newfolder
                            newitem.size = newsize
                            newitem.hashstr = ""
                            newitem.parent = parentId
                            if parentId == "" {
                                newitem.path = "\(storage):/\(newname)"
                            }
                            else {
                                newitem.path = "\(parentPath)/\(newname)"
                            }
                            ret = newid
                        }
                    }
                }
            }
            else {
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
                }
                catch {
                    print(error)
                    return nil
                }

                guard let newBaseId = try? await bs.upload(parentId: fixParentId, uploadname: baseName, target: crypttarget, progress: progress) else {
                    return nil
                }

                await viewContext.perform {
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
                    if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                        if let item = items.first {
                            let newid = item.id!
                            let newname = uploadname
                            let newcdate = item.cdate
                            let newmdate = item.mdate
                            let newfolder = item.folder
                            let newsize = decryptSize(item.size)
                            
                            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                            if let result = try? viewContext.fetch(fetchRequest) {
                                for object in result {
                                    viewContext.delete(object as! NSManagedObject)
                                }
                            }
                            
                            let newitem = RemoteData(context: viewContext)
                            newitem.storage = storage
                            newitem.id = newid
                            newitem.name = newname
                            let comp = newname.components(separatedBy: ".")
                            if comp.count >= 1 {
                                newitem.ext = comp.last!.lowercased()
                            }
                            newitem.cdate = newcdate
                            newitem.mdate = newmdate
                            newitem.folder = newfolder
                            newitem.size = newsize
                            newitem.hashstr = ""
                            newitem.parent = parentId
                            if parentId == "" {
                                newitem.path = "\(storage):/\(newname)"
                            }
                            else {
                                newitem.path = "\(parentPath)/\(newname)"
                            }
                            ret = newid
                        }
                    }
                }
            }
        }
        else {
            // raw create
            guard let newBaseId = try? await bs.upload(parentId: fixParentId, uploadname: uploadname, target: crypttarget, progress: progress) else {
                return nil
            }
            let decryptSize = { size in
                self.CalcDecryptedSize(crypt_size: size)
            }

            await viewContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
                if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                    if let item = items.first {
                        let newid = item.id!
                        let newname = item.name!
                        let newcdate = item.cdate
                        let newmdate = item.mdate
                        let newfolder = item.folder
                        let newsize = decryptSize(item.size)
                        
                        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                        if let result = try? viewContext.fetch(fetchRequest) {
                            for object in result {
                                viewContext.delete(object as! NSManagedObject)
                            }
                        }
                        
                        let newitem = RemoteData(context: viewContext)
                        newitem.storage = storage
                        newitem.id = newid
                        newitem.name = newname
                        let comp = newname.components(separatedBy: ".")
                        if comp.count >= 1 {
                            newitem.ext = comp.last!.lowercased()
                        }
                        newitem.cdate = newcdate
                        newitem.mdate = newmdate
                        newitem.folder = newfolder
                        newitem.size = newsize
                        newitem.hashstr = ""
                        newitem.parent = parentId
                        if parentId == "" {
                            newitem.path = "\(storage):/\(newname)"
                        }
                        else {
                            newitem.path = "\(parentPath)/\(newname)"
                        }
                        ret = newid
                    }
                }
            }
        }
        await viewContext.perform {
            try? viewContext.save()
        }
        return ret
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
        var magic = [UInt8](fileHeaderVersion)
        guard magic.count == output.write(&magic, maxLength: magic.count) else {
            return nil
        }
        
        guard fileID.count == output.write(&fileID, maxLength: fileID.count) else {
            return nil
        }
        
        var buffer = [UInt8](repeating: 0, count: Int(blockDataSize))
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
        } while len == blockDataSize
        
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
        CryptedLength = remote.remoteStorage.CalcEncryptedSize(org_size: OrignalLength)
        key = SymmetricKey(data: remote.remoteStorage.dataKey)
        await super.init(size: OrignalLength)
    }

    override func setLive(_ live: Bool) {
        if !live {
            Task {
                await remote.cancel()
            }
        }
    }

    override func fillHeader() async {
        guard let data = try? await remote.read(start: 0, length: remote.remoteStorage.fileHeaderSize) else {
            print("error on header null")
            error = true
            await super.fillHeader()
            return
        }
        if !remote.remoteStorage.fileHeaderVersion.elementsEqual(data.subdata(in: 0..<remote.remoteStorage.fileHeaderVersion.count)) {
            print("error on header check")
            await super.fillHeader()
            error = true
        }
        fileID.replaceSubrange(0..<fileID.count, with: data.subdata(in: remote.remoteStorage.fileHeaderVersion.count..<data.count))
        await super.fillHeader()
    }
    
    override func subFillBuffer(pos: ClosedRange<Int64>) async {
        guard await initialized.wait(timeout: .seconds(10)) == .success else {
            error = true
            return
        }

        let chunksize = remote.remoteStorage.chunkSize
        let orgBlocksize = remote.remoteStorage.blockDataSize
        let headersize = remote.remoteStorage.fileHeaderSize
        if await !buffer.dataAvailable(pos: pos) {
            guard pos.lowerBound >= 0 && pos.upperBound < size else {
                return
            }
            let len = min(size-1, pos.upperBound) - pos.lowerBound + 1
            let slot1 = pos.lowerBound / orgBlocksize
            let pos2 = slot1 * chunksize + headersize
            var clen = len / orgBlocksize * chunksize
            if len % orgBlocksize != 0 {
                clen += len % orgBlocksize + remote.remoteStorage.blockNonceSize + remote.remoteStorage.blockTagSize
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
                error = true
                return
            }
            var slot = slot1
            var plainBlock = Data()
            for start in stride(from: 0, to: data.count, by: Int(chunksize)) {
                autoreleasepool {
                    let end = (start+Int(chunksize) >= data.count) ? data.count : start+Int(chunksize)
                    let chunk = data.subdata(in: start..<end)
                    guard chunk.count >= 32 else {
                        error = true
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
                        error = true
                        return
                    }
                    slot += 1
                }
                guard !error else {
                    return
                }
            }
            await buffer.store(pos: pos.lowerBound, data: plainBlock)
        }
    }
}

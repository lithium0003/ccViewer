//
//  Cryptomator.swift
//  RemoteCloud
//
//  Created by rei8 on 2019/04/30.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CommonCrypto
import CoreData
import os.log
import SwiftUI
import AuthenticationServices
import CryptoKit

struct PasswordCryptometorView: View {
    let callback: (String) async -> Void
    let onDismiss: () -> Void
    @State var ok = false

    @State var showPassword = false
    @State var password = ""

    var body: some View {
        ZStack {
            Form {
                Text("CryptCryptometor configuration")
                Section("Password") {
                    HStack {
                        if showPassword {
                            TextField("password", text: $password)
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
                Button("Select root folder") {
                    ok = true
                    Task {
                        await callback(password)
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

public class Cryptomator: ChildStorage {
    
    fileprivate var encryptionMasterKey = [UInt8]()
    fileprivate var macMasterKey = [UInt8]()
    fileprivate var scryptSalt = [UInt8]()
    fileprivate var kek = [UInt8]()
    fileprivate var scryptCostParam = 32768
    fileprivate var scryptBlockSize = 8
    private var KEY_LEN_BYTES = 32
    
    var shorteningThreshold = 220
    var cipherCombo = "SIV_GCM"
    let DATA_DIR_NAME = "d"
    var masterkey_filename = "masterkey.cryptomator"
    let vault_cryptomator = "vault.cryptomator"
    let normal_ext = ".c9r"
    let shortened_ext = ".c9s"

    enum ItemType {
        case regular
        case directory
        case symlink
        case broken
    }
    
    public override func getStorageType() -> CloudStorages {
        return .Cryptomator
    }
    
    public override init(name: String) async {
        await super.init(name: name)
        service = CloudFactory.getServiceName(service: .Cryptomator)
        storageName = name
        
        if let password = await getKeyChain(key: "\(storageName ?? "")_password"), let datastr = await getKeyChain(key: "\(storageName ?? "")_masterKey"), let datastr2 = await getKeyChain(key: "\(storageName ?? "")_vault"){
            guard let data = datastr.data(using: .utf8) else {
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) else {
                return
            }
            guard let masterkey = json as? [String: Any] else {
                return
            }
            
            guard let (_, payload) = decodeJWT(datastr2) else { return }

            let jsondata = masterkey.merging(payload, uniquingKeysWith: { $1 })

            if await restoreMasterKeyFromJson(password: password, json: jsondata) {
                os_log("%{public}@", log: log, type: .debug, "restore_Key(cryptomator:\(storageName ?? "")) restore key success")
            }
            else {
                os_log("%{public}@", log: log, type: .debug, "restore_Key(cryptomator:\(storageName ?? "")) restore key failed")
            }
        }
    }

    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        let authRet = await withCheckedContinuation { authContinuation in
            Task {
                let presentRet = await withCheckedContinuation { continuation in
                    callback(PasswordCryptometorView(callback: { pass in
                        if await super.auth(callback: callback, webAuthenticationSession: webAuthenticationSession, selectItem: selectItem) {
                            let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_password", value: pass)
                            guard await self.generateKey() else {
                                authContinuation.resume(returning: false)
                                return
                            }
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
            let _ = await delKeyChain(key: "\(name)_masterKey")
            let _ = await delKeyChain(key: "\(name)_vault")
        }
        await super.logout()
    }
    
    func wrapKey(_ rawKey: [UInt8], kek: [UInt8]) -> [UInt8] {
        var wrappedKeyLen = CCSymmetricWrappedSize(CCWrappingAlgorithm(kCCWRAPAES), rawKey.count)
        var wrappedKey = [UInt8](repeating: 0x00, count: wrappedKeyLen)
        let status = CCSymmetricKeyWrap(CCWrappingAlgorithm(kCCWRAPAES), CCrfc3394_iv, CCrfc3394_ivLen, kek, kek.count, rawKey, rawKey.count, &wrappedKey, &wrappedKeyLen)
        if status == kCCSuccess {
            return wrappedKey
        } else {
            return []
        }
    }

    func unwrapKey(_ wrappedKey: [UInt8], kek: [UInt8]) -> [UInt8] {
        var unwrappedKeyLen = CCSymmetricUnwrappedSize(CCWrappingAlgorithm(kCCWRAPAES), wrappedKey.count)
        var unwrappedKey = [UInt8](repeating: 0x00, count: unwrappedKeyLen)
        let status = CCSymmetricKeyUnwrap(CCWrappingAlgorithm(kCCWRAPAES), CCrfc3394_iv, CCrfc3394_ivLen, kek, kek.count, wrappedKey, wrappedKey.count, &unwrappedKey, &unwrappedKeyLen)
        if status == kCCSuccess {
            assert(unwrappedKeyLen == kCCKeySizeAES256)
            return unwrappedKey
        } else {
            return []
        }
    }

    func HMACSign(_ message: [UInt8], key: [UInt8], alg: String) -> [UInt8] {
        guard ["HS256", "HS384", "HS512"].contains(alg) else {
            return []
        }
        
        var commonCryptoAlgorithm: CCHmacAlgorithm {
            switch alg {
            case "HS256":
                return CCHmacAlgorithm(kCCHmacAlgSHA256)
            case "HS384":
                return CCHmacAlgorithm(kCCHmacAlgSHA384)
            case "HS512":
                return CCHmacAlgorithm(kCCHmacAlgSHA512)
            default:
                fatalError()
            }
        }

        var commonCryptoDigestLength: Int32 {
            switch alg {
            case "HS256":
                return CC_SHA256_DIGEST_LENGTH
            case "HS384":
                return CC_SHA384_DIGEST_LENGTH
            case "HS512":
                return CC_SHA512_DIGEST_LENGTH
            default:
                fatalError()
            }
        }
        
        let context = UnsafeMutablePointer<CCHmacContext>.allocate(capacity: 1)
        defer { context.deallocate() }

        CCHmacInit(context, commonCryptoAlgorithm, key, size_t(key.count))
        CCHmacUpdate(context, message, size_t(message.count))
        var hmac = [UInt8](repeating: 0, count: Int(commonCryptoDigestLength))
        CCHmacFinal(context, &hmac)

        return hmac
    }

    func checkVaultVersion(versionMac: String, version: Int, macKey: [UInt8]) -> Bool {
        guard let storedVersionMac = Data(base64Encoded: versionMac), storedVersionMac.count == CC_SHA256_DIGEST_LENGTH else {
            return false
        }
        var calculatedVersionMac = [UInt8](repeating: 0x00, count: Int(CC_SHA256_DIGEST_LENGTH))
        let versionBytes = withUnsafeBytes(of: UInt32(version).bigEndian, Array.init)
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), macKey, macKey.count, versionBytes, versionBytes.count, &calculatedVersionMac)
        var diff: UInt8 = 0x00
        for i in 0 ..< calculatedVersionMac.count {
            diff |= calculatedVersionMac[i] ^ storedVersionMac[i]
        }
        return diff == 0x00
    }

    func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    func base64URLDecode(_ string: String) -> Data? {
        var stringtoDecode = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        // 文字数に応じて末に「=」を追加する
        switch stringtoDecode.count % 4 {
        case 2:
            stringtoDecode += "=="
        case 3:
            stringtoDecode += "="
        default:
            break
        }
        return Data(base64Encoded: stringtoDecode, options: [])
    }

    func encodeJWT(header: [String: Any], payload: [String: Any], key: [UInt8]) -> String {
        guard let alg = header["alg"] as? String else {
            return ""
        }
        guard let headerData = try? JSONSerialization.data(withJSONObject: header) else {
            return ""
        }
        let segment0 = base64URLEncode(headerData)
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            return ""
        }
        let segment1 = base64URLEncode(payloadData)
        let signatureInput = "\(segment0).\(segment1)"

        let sign = HMACSign([UInt8](signatureInput.data(using: .utf8)!), key: key, alg: alg)
        let segment2 = base64URLEncode(Data(sign))
        return "\(segment0).\(segment1).\(segment2)"
    }
    
    func decodeJWT(_ token: String) -> (header: [String: Any], payload: [String: Any])? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else {
            return nil
        }
        guard let headerData = base64URLDecode(String(segments[0])) else {
            return nil
        }
        guard let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            return nil
        }
        guard let payloadData = base64URLDecode(String(segments[1])) else {
            return nil
        }
        guard let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        return (header: header, payload: payload)
    }

    func verifyJWT(_ token: String, key: [UInt8], alg: String) -> Bool {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else {
            return false
        }
        let signatureInput = "\(segments[0]).\(segments[1])"

        guard let signature = base64URLDecode(String(segments[2])) else {
            return false
        }

        return HMACSign([UInt8](signatureInput.data(using: .utf8)!), key: key, alg: alg).elementsEqual(signature)
    }

    func generateMasterKey(password: String) -> (masterKey: [String: Any], vault: String)? {
        encryptionMasterKey = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, encryptionMasterKey.count, &encryptionMasterKey) == errSecSuccess else {
            return nil
        }
        macMasterKey = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, macMasterKey.count, &macMasterKey) == errSecSuccess else {
            return nil
        }
        scryptSalt = [UInt8](repeating: 0, count: 8)
        guard SecRandomCopyBytes(kSecRandomDefault, scryptSalt.count, &scryptSalt) == errSecSuccess else {
            return nil
        }
        let rawKey = encryptionMasterKey + macMasterKey
        let kek = SCrypt.ComputeDerivedKey(key: [UInt8](password.data(using: .utf8)!), salt: scryptSalt, cost: scryptCostParam, blockSize: scryptBlockSize, derivedKeyLength: KEY_LEN_BYTES)
        let wrappedEncryptionMasterKey = wrapKey(encryptionMasterKey, kek: kek)
        let wrappedMacMasterKey = wrapKey(macMasterKey, kek: kek)
        
        let version = 999
        var verValue = UInt32(version).bigEndian
        let verData = Data(bytes: &verValue, count: MemoryLayout.size(ofValue: verValue))
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), macMasterKey, macMasterKey.count, [UInt8](verData), verData.count, &result)
        
        let jsonData: [String: Any] = [
            "version": version,
            "scryptSalt": Data(scryptSalt).base64EncodedString(),
            "scryptCostParam": scryptCostParam,
            "scryptBlockSize": scryptBlockSize,
            "primaryMasterKey": Data(wrappedEncryptionMasterKey).base64EncodedString(),
            "hmacMasterKey": Data(wrappedMacMasterKey).base64EncodedString(),
            "versionMac": Data(result).base64EncodedString(),
        ]
        let header: [String: Any] = [
            "typ": "JWT",
            "alg": "HS256",
            "kid": "masterkeyfile:masterkey.cryptomator",
        ]
        let payload: [String: Any] = [
            "format": 8,
            "shorteningThreshold": shorteningThreshold,
            "jti": UUID().uuidString,
            "cipherCombo": cipherCombo,
        ]
        
        return (masterKey: jsonData, vault: encodeJWT(header: header, payload: payload, key: rawKey))
    }
    
    @concurrent
    func restoreMasterKeyFromJson(password: String, json: [String: Any]) async -> Bool {
        guard let costParam = json["scryptCostParam"] as? Int else {
            return false
        }
        scryptCostParam = costParam
        guard let blockSize = json["scryptBlockSize"] as? Int else {
            return false
        }
        scryptBlockSize = blockSize
        guard let saltstr = json["scryptSalt"] as? String else {
            return false
        }
        guard let salt = Data(base64Encoded: saltstr) else {
            return false
        }
        scryptSalt = [UInt8](salt)
        guard let pmkstr = json["primaryMasterKey"] as? String else {
            return false
        }
        guard let pmk = Data(base64Encoded: pmkstr) else {
            return false
        }
        let wrappedEncryptionMasterKey = [UInt8](pmk)
        guard let hmkstr = json["hmacMasterKey"] as? String else {
            return false
        }
        guard let hmk = Data(base64Encoded: hmkstr) else {
            return false
        }
        let wrappedMacMasterKey = [UInt8](hmk)
        guard let shorteningThreshold = json["shorteningThreshold"] as? Int else {
            return false
        }
        self.shorteningThreshold = shorteningThreshold
        guard let cipherCombo = json["cipherCombo"] as? String else {
            return false
        }
        self.cipherCombo = cipherCombo

        if kek.isEmpty {
            kek = SCrypt.ComputeDerivedKey(key: [UInt8](password.data(using: .utf8)!), salt: scryptSalt, cost: scryptCostParam, blockSize: scryptBlockSize, derivedKeyLength: KEY_LEN_BYTES)
        }
        encryptionMasterKey = unwrapKey(wrappedEncryptionMasterKey, kek: kek)
        macMasterKey = unwrapKey(wrappedMacMasterKey, kek: kek)
        return true
    }
        
    func loadMasterKey(password: String) async -> (Bool, Bool) {
        guard let json = await readMasterKey() else {
            return (false, false)
        }
        let ret = await restoreMasterKeyFromJson(password: password, json: json)
        return (true, ret)
    }
    
    @concurrent
    @discardableResult
    func generateKey() async -> Bool {
        let password = await getKeyChain(key: "\(storageName ?? "")_password") ?? ""
        let (loading, success) = await loadMasterKey(password: password)
        if loading {
            return success
        }
        let items = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: baseRootFileId)
        if items.contains(where: { $0.name == vault_cryptomator }) || items.contains(where: { $0.name == masterkey_filename }) {
            return false
        }
        guard let (json, jwt) = generateMasterKey(password: password) else {
            return false
        }
        async let t1 = await writeMasterKeyFile(json: json)
        async let t2 = await writeVaultCryptomatorFile(jwt: jwt)
        async let t3 = await makeRootFolder()
        
        let (s1,s2,s3) = await (t1, t2, t3)
        return s1 && s2 && s3
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

    func findParentStorage(path: ArraySlice<String>, baseId: String = "", expand: Bool = true) async -> [RemoteItem] {
        if path.count == 0 {
            guard let item = await CloudFactory.shared.storageList.get(baseRootStorage)?.get(fileId: baseId == "" ? baseRootFileId : baseId) else {
                return []
            }
            if item.isFolder && expand {
                let items = await findParentStorage(baseId: baseId == "" ? baseRootFileId : baseId)
                let ret = await withTaskGroup { group in
                    for id in items.compactMap({ $0.id }) {
                        group.addTask {
                            await CloudFactory.shared.storageList.get(self.baseRootStorage)?.get(fileId: id)
                        }
                    }
                    return await group.reduce(into: []) { result, item in
                        result.append(item)
                    }
                }.compactMap({ $0 })
                return ret
            }
            return [item]
        }
        let result = await findParentStorage(baseId: baseId)
        let p = path.prefix(1).map { $0 }
        for item in result {
            guard let name = item.name, let id = item.id else {
                continue
            }
            if name == p[0] {
                return await findParentStorage(path: path.dropFirst(), baseId: id, expand: expand)
            }
        }
        return []
    }

    func makeParentStorage(path: ArraySlice<String>, baseId: String = "") async -> RemoteItem? {
        if path.count == 0 {
            guard let item = await CloudFactory.shared.storageList.get(baseRootStorage)?.get(fileId: baseId == "" ? baseRootFileId : baseId) else {
                return nil
            }
            return item
        }
        let result = await findParentStorage(baseId: baseId)
        let p = path.prefix(1).map { $0 }
        for item in result {
            guard let name = item.name, let id = item.id else {
                continue
            }
            if name == p[0] {
                return await makeParentStorage(path: path.dropFirst(), baseId: id)
            }
        }
        guard let item = await CloudFactory.shared.storageList.get(self.baseRootStorage)?.get(fileId: baseId == "" ? self.baseRootFileId : baseId) else {
            return nil
        }
        guard let newid = await item.mkdir(newname: p[0]) else {
            return nil
        }
        return await makeParentStorage(path: path.dropFirst(), baseId: newid)
    }

    func writeMasterKeyFile(json: [String: Any]) async -> Bool {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        guard let jsonStr = String(bytes: jsonData, encoding: .utf8) else {
            return false
        }
        let _ = await setKeyChain(key: "\(storageName ?? "")_masterKey", value: jsonStr)
        
        // generate temp file for upload
        let tempTarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)

        try? jsonStr.write(to: tempTarget, atomically: true, encoding: .utf8)
        
        // upload masterkey file
        let id = try? await CloudFactory.shared.storageList.get(baseRootStorage)?.upload(parentId: baseRootFileId, uploadname: masterkey_filename, target: tempTarget, progress: nil)
        return id != nil
    }

    func writeVaultCryptomatorFile(jwt: String) async -> Bool {
        let _ = await setKeyChain(key: "\(storageName ?? "")_vault", value: jwt)

        // generate temp file for upload
        let tempTarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)

        try? jwt.write(to: tempTarget, atomically: true, encoding: .utf8)
        
        // upload masterkey file
        let id = try? await CloudFactory.shared.storageList.get(baseRootStorage)?.upload(parentId: baseRootFileId, uploadname: vault_cryptomator, target: tempTarget, progress: nil)
        return id != nil
    }

    func generateFileIdSuffix(data: [UInt8]) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(data, CC_LONG(data.count), &digest)
        let base16 = digest.map({String(format: "%02X", $0)}).joined()
        return "." + base16.prefix(4)
    }
    
    func readMasterKey() async -> [String: Any]? {
        if let datastr = await getKeyChain(key: "\(storageName ?? "")_masterKey"), let datastr2 = await getKeyChain(key: "\(storageName ?? "")_vault") {
            guard let data = datastr.data(using: .utf8) else {
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) else {
                return nil
            }
            guard let masterkey = json as? [String: Any] else {
                return nil
            }

            guard let (_, payload) = decodeJWT(datastr2) else { return nil }

            return masterkey.merging(payload, uniquingKeysWith: { $1 })
        }
        else {
            return await readMasterKeyFile()
        }
    }
    
    func readMasterKeyFile() async -> [String: Any]? {
        let password = await getKeyChain(key: "\(self.storageName ?? "")_password") ?? ""

        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return nil
        }
        let items = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: baseRootFileId)
        var vaultItem: RemoteItem? = nil
        for item in items {
            if item.name == vault_cryptomator, let id = item.id {
                vaultItem = await bs.get(fileId: id)
            }
        }
        guard let vaultItem else {
            return nil
        }
        guard let token = try? await vaultItem.read() else {
            return nil
        }

        guard let (header, payload) = decodeJWT(String(data: token, encoding: .utf8)!) else { return nil }
        guard let kid = header["kid"] as? String else { return nil }
        let name = kid.split(separator: ":")
        guard name.count == 2, name[0] == "masterkeyfile" else { return nil }
        masterkey_filename = String(name[1])

        var masterItem: RemoteItem? = nil
        for item in items {
            if item.name == masterkey_filename, let id = item.id {
                masterItem = await bs.get(fileId: id)
            }
        }
        guard let masterItem else {
            return nil
        }
        guard let masterkeyContent = try? await masterItem.read() else {
            return nil
        }

        guard let masterkey = try? JSONSerialization.jsonObject(with: masterkeyContent) as? [String: Any] else { return nil }
        guard let scryptSaltStr = masterkey["scryptSalt"] as? String else { return nil }
        guard let scryptSalt = Data(base64Encoded: scryptSaltStr) else { return nil }
        guard let scryptCostParam = masterkey["scryptCostParam"] as? Int else { return nil }
        guard let scryptBlockSize = masterkey["scryptBlockSize"] as? Int else { return nil }
        kek = SCrypt.ComputeDerivedKey(key: [UInt8](password.data(using: .utf8)!), salt: [UInt8](scryptSalt), cost: scryptCostParam, blockSize: scryptBlockSize, derivedKeyLength: KEY_LEN_BYTES)
        guard let encryptionMasterKeyStr = masterkey["primaryMasterKey"] as? String else { return nil }
        guard let wrappedEncryptionMasterKey = Data(base64Encoded: encryptionMasterKeyStr) else { return nil }
        guard let macMasterKeyStr = masterkey["hmacMasterKey"] as? String else { return nil }
        guard let wrappedMacMasterKey = Data(base64Encoded: macMasterKeyStr) else { return nil }
        let encryptionMasterKey = unwrapKey([UInt8](wrappedEncryptionMasterKey), kek: kek)
        let macMasterKey = unwrapKey([UInt8](wrappedMacMasterKey), kek: kek)
        guard let version = masterkey["version"] as? Int else { return nil }
        guard let versionMac = masterkey["versionMac"] as? String else { return nil }
        guard checkVaultVersion(versionMac: versionMac, version: version, macKey: macMasterKey) else { return nil }
        let rawKey = encryptionMasterKey + macMasterKey
        guard let alg = header["alg"] as? String else { return nil }
        guard verifyJWT(String(data: token, encoding: .utf8)!, key: rawKey, alg: alg) else { return nil }

        let json = masterkey.merging(payload, uniquingKeysWith: { $1 })
        let _ = await setKeyChain(key: "\(storageName ?? "")_masterKey", value: String(bytes: masterkeyContent, encoding: .utf8) ?? "")
        let _ = await setKeyChain(key: "\(storageName ?? "")_vault", value: String(bytes: token, encoding: .utf8) ?? "")
        return json
    }

    func storeItem(parentId: String, item: RemoteItem, name: String, isFolder: Bool, dirId: String, deflatedName: String, path: String, context: NSManagedObjectContext) {
        os_log("%{public}@", log: log, type: .debug, "storeItem(cryptomator:\(storageName ?? "")) \(name)")
        
        context.performAndWait {
            let newid = "\(dirId)/\(deflatedName)"
            let newname = name
            let newcdate = item.cDate
            let newmdate = item.mDate
            let newfolder = isFolder
            let newsize = self.ConvertDecryptSize(size: item.size)

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
            try? context.save()
        }
    }
    
    func subListChildren(dirId: String, fileId: String, path: String) async {
        guard let dirIdHash = resolveDirectory(dirId: dirId) else {
            return
        }
        let items = await findParentStorage(path: [DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))])
        let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
        for item in items {
            if item.name == "dirid.c9r" {
            }
            else if item.name.hasSuffix(shortened_ext) {
                // long name
                let subitems = await findParentStorage(path: [DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30)), item.name])
                guard let nameitem = subitems.first(where: { $0.name == "name.c9s" }) else {
                    continue
                }

                guard let namedata = try? await nameitem.read() else {
                    continue
                }
                guard let orgname = String(bytes: namedata, encoding: .utf8) else {
                    continue
                }

                guard let decryptedName = decryptFilename(ciphertextName: orgname.replacing(normal_ext, with: ""), dirId: dirId) else {
                    continue
                }

                if let diridItem = subitems.first(where: { $0.name == "dir.c9r" }) {
                    guard let dirdata = try? await diridItem.read() else {
                        continue
                    }
                    guard let subdirId = String(bytes: dirdata, encoding: .utf8) else {
                        continue
                    }
                    guard let subdirIdHash = resolveDirectory(dirId: subdirId) else {
                        return
                    }

                    guard let dirTargetItem = await findParentStorage(path: [DATA_DIR_NAME, String(subdirIdHash.prefix(2)), String(subdirIdHash.suffix(30))], expand: false).first else {
                        return
                    }

                    storeItem(parentId: fileId, item: dirTargetItem, name: decryptedName, isFolder: true, dirId: dirId, deflatedName: item.name+"/"+subdirId, path: path, context: backgroundContext)
                }
                else if let contentItem = subitems.first(where: { $0.name == "contents.c9r" }) {
                    storeItem(parentId: fileId, item: contentItem, name: decryptedName, isFolder: false, dirId: dirId, deflatedName: item.name, path: path, context: backgroundContext)
                }
            }
            else if item.name.hasSuffix(normal_ext) {
                guard let decryptedName = decryptFilename(ciphertextName: item.name.replacing(normal_ext, with: ""), dirId: dirId) else {
                    continue
                }
                if item.isFolder {
                    let subitems = await findParentStorage(path: [DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30)), item.name])

                    if let diridItem = subitems.first(where: { $0.name == "dir.c9r" }) {
                        guard let dirdata = try? await diridItem.read() else {
                            continue
                        }
                        guard let subdirId = String(bytes: dirdata, encoding: .utf8) else {
                            continue
                        }

                        guard let subdirIdHash = resolveDirectory(dirId: subdirId) else {
                            return
                        }

                        guard let dirTargetItem = await findParentStorage(path: [DATA_DIR_NAME, String(subdirIdHash.prefix(2)), String(subdirIdHash.suffix(30))], expand: false).first else {
                            return
                        }

                        storeItem(parentId: fileId, item: dirTargetItem, name: decryptedName, isFolder: true, dirId: dirId, deflatedName: item.name+"/"+subdirId, path: path, context: backgroundContext)
                    }
                }
                else {
                    storeItem(parentId: fileId, item: item, name: decryptedName, isFolder: false, dirId: dirId, deflatedName: item.name, path: path, context: backgroundContext)
                }
            }
        }
        await backgroundContext.perform {
            try? backgroundContext.save()
        }
    }
    
    override func listChildren(fileId: String, path: String) async {
        // fileId file: parentDirId/deflatedName
        // fileId dir: parentDirId/deflatedName/dirId
        os_log("%{public}@", log: log, type: .debug, "ListChildren(cryptomator:\(storageName ?? "")) \(fileId)")

        if fileId == "" {
            await subListChildren(dirId: "", fileId: fileId, path: path)
        }

        let array = fileId.components(separatedBy: "/")
        let dirId = array.last!
        await subListChildren(dirId: dirId, fileId: fileId, path: path)
    }

    func deflate(longFileName: String) -> String? {
        guard let longFileNameBytes = longFileName.data(using: .utf8) else {
            return nil
        }
        
        let length = Int(CC_SHA1_DIGEST_LENGTH)
        var digest = [UInt8](repeating: 0, count: length)
        let _ = longFileNameBytes.withUnsafeBytes { CC_SHA1($0.baseAddress!, CC_LONG(longFileNameBytes.count), &digest) }
        let encoded = Data(digest).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return encoded + shortened_ext
    }
    
    func resolveDirectory(dirId: String) -> String? {
        guard let inputdata = dirId.data(using: .utf8) else {
            return nil
        }
        let cleartextBytes = [UInt8](inputdata)
        guard let encryptedBytes = try? AesSiv.encrypt(aesKey: encryptionMasterKey, macKey: macMasterKey, plaintext: cleartextBytes) else {
            return nil
        }
        
        let length = Int(CC_SHA1_DIGEST_LENGTH)
        var digest = [UInt8](repeating: 0, count: length)
        let _ = encryptedBytes.withUnsafeBytes { CC_SHA1($0.baseAddress!, CC_LONG(encryptedBytes.count), &digest) }
        return BASE32.base32encode(input: Data(digest))
    }
    
    func encryptFilename(cleartextName: String, dirId: String) -> String? {
        guard let associatedData = dirId.data(using: .utf8) else {
            return nil
        }
        let cleartext = [UInt8](cleartextName.precomposedStringWithCanonicalMapping.utf8)
        guard let ciphertext = try? AesSiv.encrypt(aesKey: encryptionMasterKey, macKey: macMasterKey, plaintext: cleartext, ad: [UInt8](associatedData)) else {
            return nil
        }

        return Data(ciphertext).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }
    
    func decryptFilename(ciphertextName: String, dirId: String) -> String? {
        guard let ciphertextData = Data(base64Encoded: ciphertextName.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")) else {
            return nil
        }
        guard let associatedData = dirId.data(using: .utf8) else {
            return nil
        }
        
        guard let cleartext = try? AesSiv.decrypt(aesKey: encryptionMasterKey, macKey: macMasterKey, ciphertext: [UInt8](ciphertextData), ad: [UInt8](associatedData)) else {
            return nil
        }
        guard let cleartextString = String(bytes: cleartext, encoding: .utf8) else {
            return nil
        }
        return cleartextString
    }
    
    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await CryptomatorRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await CryptomatorRemoteItem(path: path)
    }

    func makeRootFolder() async -> Bool {
        guard let bs = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return false
        }

        guard let dirIdHash = resolveDirectory(dirId: "") else {
            return false
        }

        let target = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        do {
            try Data().write(to: target)
        }
        catch {
            print(error)
            return false
        }
        guard let diridFile = processFile(target: target) else {
            return false
        }

        await bs.list(fileId: baseRootFileId)
        guard let item = await bs.get(fileId: baseRootFileId) else {
            return false
        }
        var parent = item
        for p in [DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))] {
            guard let id = await parent.mkdir(newname: p) else {
                return false
            }
            try? await Task.sleep(for: .seconds(1))
            await bs.list(fileId: parent.id)
            guard let item2 = await bs.get(fileId: id) else {
                return false
            }
            parent = item2
        }
        guard (try? await bs.upload(parentId: parent.id, uploadname: "dirid.c9r", target: diridFile)) != nil else {
            return false
        }
        await bs.list(fileId: parent.id)
        return true
    }
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        os_log("%{public}@", log: log, type: .debug, "makeFolder(\(String(describing: type(of: self))):\(storageName ?? "") \(parentId)(\(parentPath)) \(newname)")

        guard let s = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return nil
        }

        let parentDirId: String
        if parentId == "" {
            parentDirId = ""
        }
        else {
            let array = parentId.components(separatedBy: "/")
            parentDirId = array.last!
        }
        guard let parentIdHash = resolveDirectory(dirId: parentDirId) else {
            return nil
        }

        // generate encrypted name
        guard var encFilename = encryptFilename(cleartextName: newname, dirId: parentDirId) else {
            return nil
        }
        encFilename += normal_ext
        // generate new dirid
        let newDirId = UUID().uuidString.lowercased()
        guard let dirIdHash = resolveDirectory(dirId: newDirId) else {
            return nil
        }
        // make directory for new dirid
        guard let newCreateDirItem = await makeParentStorage(path: [DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))]) else {
            return nil
        }

        let target = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        do {
            try newDirId.write(to: target, atomically: true, encoding: .utf8)
        }
        catch {
            print(error)
            return nil
        }
        guard let diridFile = processFile(target: target) else {
            return nil
        }
        guard (try? await s.upload(parentId: newCreateDirItem.id, uploadname: "dirid.c9r", target: diridFile)) != nil else {
            return nil
        }

        let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
        // if needed filename shorten
        if encFilename.count > shorteningThreshold {
            let target2 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            do {
                try encFilename.write(to: target2, atomically: true, encoding: .utf8)
            }
            catch {
                print(error)
                return nil
            }
            guard let deflatedName = deflate(longFileName: encFilename) else {
                return nil
            }
            guard let dirItem = await makeParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflatedName]) else {
                return nil
            }
            guard (try? await s.upload(parentId: dirItem.id, uploadname: "dir.c9r", target: target)) != nil else {
                return nil
            }
            guard (try? await s.upload(parentId: dirItem.id, uploadname: "name.c9s", target: target2)) != nil else {
                return nil
            }
            storeItem(parentId: parentId, item: newCreateDirItem, name: newname, isFolder: true, dirId: parentDirId, deflatedName: dirItem.name+"/"+newDirId, path: parentPath+"/"+newname, context: backgroundContext)
            await backgroundContext.perform {
                try? backgroundContext.save()
            }
            let newid = "\(parentDirId)/\(dirItem.name)/\(newDirId)"
            let storage = storageName ?? ""
            return await backgroundContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                if let result = try? backgroundContext.fetch(fetchRequest), let items = result as? [RemoteData], let newitem = items.first {
                    return newitem.id
                }
                return nil
            }
        }
        else {
            guard let dirItem = await makeParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), encFilename]) else {
                return nil
            }
            guard (try? await s.upload(parentId: dirItem.id, uploadname: "dir.c9r", target: target)) != nil else {
                return nil
            }
            storeItem(parentId: parentId, item: newCreateDirItem, name: newname, isFolder: true, dirId: parentDirId, deflatedName: dirItem.name+"/"+newDirId, path: parentPath+"/"+newname, context: backgroundContext)
            await backgroundContext.perform {
                try? backgroundContext.save()
            }
            let newid = "\(parentDirId)/\(dirItem.name)/\(newDirId)"
            let storage = storageName ?? ""
            return await backgroundContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                if let result = try? backgroundContext.fetch(fetchRequest), let items = result as? [RemoteData], let newitem = items.first {
                    return newitem.id
                }
                return nil
            }
        }
    }
    
    override func deleteItem(fileId: String) async -> Bool {
        guard fileId != "" else {
            return false
        }

        os_log("%{public}@", log: log, type: .debug, "deleteItem(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId)")

        let array = fileId.components(separatedBy: "/")
        let parentDirId = array[0]
        let deflateId = array[1]

        guard let parentIdHash = resolveDirectory(dirId: parentDirId) else {
            return false
        }

        let items = await findParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30))])
        guard let item = items.first(where: { $0.name == deflateId }) else {
            return false
        }

        guard await item.delete() else {
            return false
        }

        if array.count == 3, let newDirId = array.last {
            guard let newIdHash = resolveDirectory(dirId: newDirId) else {
                return false
            }
            guard let item = await findParentStorage(path: [DATA_DIR_NAME, String(newIdHash.prefix(2)), String(newIdHash.suffix(30))], expand: false).first else {
                return false
            }
            guard await item.delete() else {
                return false
            }
        }

        let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
        let storage = storageName ?? ""
        await backgroundContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? backgroundContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                for item in items {
                    backgroundContext.delete(item)
                }
                try? backgroundContext.save()
            }
        }
        return true
    }
    
    @MainActor
    func getParentPath(parentId: String) async -> String? {
        let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, storageName ?? "")
        if let result = try? viewContext.fetch(fetchRequest) {
            if let items = result as? [RemoteData] {
                return items.first?.path ?? ""
            }
        }
        return nil
    }
    
    override func renameItem(fileId: String, newname: String) async -> String? {
        let newname = newname.precomposedStringWithCanonicalMapping
        guard fileId != "" else {
            return nil
        }
        
        os_log("%{public}@", log: log, type: .debug, "renameItem(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId)->\(newname)")
        
        let array = fileId.components(separatedBy: "/")
        let parentDirId = array[0]
        let deflateId = array[1]
        
        guard let parentIdHash = resolveDirectory(dirId: parentDirId) else {
            return nil
        }
        
        guard let parentBaseitem = await findParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30))], expand: false).first else {
            return nil
        }
        
        guard let c = await CloudFactory.shared.storageList.get(storageName!)?.get(fileId: fileId) else {
            return nil
        }
        let newcdate = c.cDate
        let newmdate = c.mDate
        let newfolder = c.isFolder
        let newsize = c.size
        guard let s = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return nil
        }
        
        var parentPath: String? = nil
        let parentId = c.parent
        if parentId != "" {
            parentPath = await getParentPath(parentId: parentId)
        }
        guard let parentPath = parentPath else {
            return nil
        }
        
        guard var encFilename = encryptFilename(cleartextName: newname, dirId: parentDirId) else {
            return nil
        }
        encFilename += normal_ext
        
        guard let currentBaseItem = await findParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflateId], expand: false).first else {
            return nil
        }
        
        var retId: String
        if encFilename.count > shorteningThreshold {
            guard let deflatedName = deflate(longFileName: encFilename) else {
                return nil
            }
            if deflateId.hasSuffix(normal_ext) {
                // normal -> shorten
                let target2 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
                do {
                    try encFilename.write(to: target2, atomically: true, encoding: .utf8)
                }
                catch {
                    print(error)
                    return nil
                }
                if c.isFolder {
                    // already folder
                    guard (try? await s.upload(parentId: currentBaseItem.id, uploadname: "name.c9s", target: target2)) != nil else {
                        return nil
                    }
                    guard await currentBaseItem.rename(newname: deflatedName) != nil else {
                        return nil
                    }
                    retId = "\(parentDirId)/\(deflatedName)/\(array[2])"
                }
                else {
                    guard let dirItem = await makeParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflatedName]) else {
                        return nil
                    }
                    guard (try? await s.upload(parentId: dirItem.id, uploadname: "name.c9s", target: target2)) != nil else {
                        return nil
                    }
                    guard let renameId = await currentBaseItem.rename(newname: "contents.c9r") else {
                        return nil
                    }
                    await s.list(fileId: parentBaseitem.id)
                    guard let renamedItem = await s.get(fileId: renameId) else {
                        return nil
                    }
                    guard await renamedItem.move(toParentId: dirItem.id) != nil else {
                        return nil
                    }
                    retId = "\(parentDirId)/\(deflatedName)"
                }
            }
            else {
                // shorten -> shorten
                if let nameItem = await findParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflateId, "name.c9s"], expand: false).first {
                    guard await nameItem.delete() else {
                        return nil
                    }
                }
                let target2 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
                do {
                    try encFilename.write(to: target2, atomically: true, encoding: .utf8)
                }
                catch {
                    print(error)
                    return nil
                }
                guard (try? await s.upload(parentId: currentBaseItem.id, uploadname: "name.c9s", target: target2)) != nil else {
                    return nil
                }
                guard await currentBaseItem.rename(newname: deflatedName) != nil else {
                    return nil
                }
                if array.count == 3 {
                    retId = "\(parentDirId)/\(deflatedName)/\(array[2])"
                }
                else {
                    retId = "\(parentDirId)/\(deflatedName)"
                }
            }
        }
        else {
            if deflateId.hasSuffix(normal_ext) {
                // normal -> normal
                guard await currentBaseItem.rename(newname: encFilename) != nil else {
                    return nil
                }
                if array.count == 3 {
                    retId = "\(parentDirId)/\(encFilename)/\(array[2])"
                }
                else {
                    retId = "\(parentDirId)/\(encFilename)"
                }
            }
            else {
                // shorten -> normal
                if c.isFolder {
                    // keep folder
                    if let nameItem = await findParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflateId, "name.c9s"], expand: false).first {
                        guard await nameItem.delete() else {
                            return nil
                        }
                    }
                    guard await currentBaseItem.rename(newname: encFilename) != nil else {
                        return nil
                    }
                    retId = "\(parentDirId)/\(encFilename)/\(array[2])"
                }
                else {
                    // folder -> file
                    if let nameItem = await findParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflateId, "name.c9s"], expand: false).first {
                        guard await nameItem.delete() else {
                            return nil
                        }
                    }
                    guard let contentItem = await findParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflateId, "contents.c9r"], expand: false).first else  {
                        return nil
                    }
                    guard let renameId = await contentItem.rename(newname: encFilename) else {
                        return nil
                    }
                    await s.list(fileId: currentBaseItem.id)
                    guard let renamedItem = await s.get(fileId: renameId) else {
                        return nil
                    }
                    guard await renamedItem.move(toParentId: parentBaseitem.id) != nil else {
                        return nil
                    }
                    retId = "\(parentDirId)/\(encFilename)"
                }
            }
        }
        let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
        let storage = storageName ?? ""
        await backgroundContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? backgroundContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                for item in items {
                    backgroundContext.delete(item)
                }
            }
            
            let newitem = RemoteData(context: backgroundContext)
            newitem.storage = storage
            newitem.id = retId
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
            newitem.path = "\(parentPath)/\(newname)"
            
            try? backgroundContext.save()
        }
        return retId
    }

    
    override func changeTime(fileId: String, newdate: Date) async -> String? {
        guard fileId != "" else {
            return nil
        }
        
        os_log("%{public}@", log: log, type: .debug, "changeTime(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId)->\(newdate)")
        
        let array = fileId.components(separatedBy: "/")
        let parentDirId = array[0]
        let deflateId = array[1]

        let newBaseId: String
        if array.count == 3 {
            let targetDirId = array[2]
            guard let parentIdHash = resolveDirectory(dirId: parentDirId) else {
                return nil
            }
            
            guard let item1 = await findParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflateId], expand: false).first else {
                return nil
            }
            newBaseId = item1.id

            guard let targetDirIdHash = resolveDirectory(dirId: targetDirId) else {
                return nil
            }
            
            guard let item = await findParentStorage(path: [DATA_DIR_NAME, String(targetDirIdHash.prefix(2)), String(targetDirIdHash.suffix(30))], expand: false).first else {
                return nil
            }

            guard await item.changetime(newdate: newdate) != nil else {
                return nil
            }
        }
        else if deflateId.hasSuffix(normal_ext) {
            guard let parentIdHash = resolveDirectory(dirId: parentDirId) else {
                return nil
            }
            
            guard let item = await findParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflateId], expand: false).first else {
                return nil
            }

            guard let id = await item.changetime(newdate: newdate) else {
                return nil
            }
            newBaseId = id
        }
        else {
            guard let parentIdHash = resolveDirectory(dirId: parentDirId) else {
                return nil
            }
            
            guard let item1 = await findParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflateId], expand: false).first else {
                return nil
            }
            newBaseId = item1.id

            guard let item = await findParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflateId, "contents.c9r"], expand: false).first else {
                return nil
            }

            guard await item.changetime(newdate: newdate) != nil else {
                return nil
            }
        }

        let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
        let baseRootStorage = baseRootStorage
        let storage = storageName ?? ""
        await backgroundContext.perform {
            var newcdate: Date? = nil
            var newmdate: Date? = nil
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseRootStorage)
            if let result = try? backgroundContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                if let baseItem = items.first {
                    newcdate = baseItem.cdate
                    newmdate = baseItem.mdate
                }
            }

            let fetchRequest2 = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest2.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? backgroundContext.fetch(fetchRequest2), let items1 = result as? [RemoteData] {
                if let pitem = items1.first {
                    pitem.cdate = newcdate
                    pitem.mdate = newmdate
                    try? backgroundContext.save()
                }
            }
        }
        return fileId
    }

    @MainActor
    func getOrgName(fileId: String) async -> String? {
        var orgname: String? = nil

        let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storageName ?? "")
        if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
            if let item = items.first {
                orgname = item.name
            }
        }
        return orgname
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

        // move target item
        let array = fileId.components(separatedBy: "/")
        let parentDirId = array[0]
        let deflateId = array[1]

        // moveto target item
        let toParentDirId: String
        if toParentId == "" {
            toParentDirId = ""
        }
        else {
            let array2 = toParentId.components(separatedBy: "/")
            guard array2.count == 3 else {
                return nil
            }
            toParentDirId = array2[2]
        }
        
        guard let parentIdHash = resolveDirectory(dirId: parentDirId) else {
            return nil
        }

        guard let toParentIdHash = resolveDirectory(dirId: toParentDirId) else {
            return nil
        }

        guard let toItem = await findParentStorage(path: [DATA_DIR_NAME, String(toParentIdHash.prefix(2)), String(toParentIdHash.suffix(30))], expand: false).first else {
            return nil
        }

        guard let item = await findParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflateId], expand: false).first else {
            return nil
        }

        // move base item to toDir
        guard let newBaseId = await item.move(toParentId: toItem.id) else {
            return nil
        }
        await bs.list(fileId: toItem.id)

        // parent dirid is changed, encrypted name will be changed
        guard var encFilename = encryptFilename(cleartextName: orgname, dirId: toParentDirId) else {
            return nil
        }
        encFilename += normal_ext

        // if needed filename shorten
        let newid: String
        if encFilename.count > shorteningThreshold {
            let target2 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            do {
                try encFilename.write(to: target2, atomically: true, encoding: .utf8)
            }
            catch {
                print(error)
                return nil
            }
            guard let deflatedName = deflate(longFileName: encFilename) else {
                return nil
            }
            guard let newBaseItem = await bs.get(fileId: newBaseId) else {
                return nil
            }
            guard let newRenamedId = await newBaseItem.rename(newname: deflatedName) else {
                return nil
            }
            await bs.list(fileId: toItem.id)
            guard let newRenamedItem = await bs.get(fileId: newRenamedId) else {
                return nil
            }
            guard (try? await bs.upload(parentId: newRenamedItem.id, uploadname: "name.c9s", target: target2)) != nil else {
                return nil
            }
            if array.count == 3 {
                newid = "\(toParentDirId)/\(deflatedName)/\(array[2])"
            }
            else {
                newid = "\(toParentDirId)/\(deflatedName)"
            }
        }
        else {
            guard let newBaseItem = await bs.get(fileId: newBaseId) else {
                return nil
            }
            guard await newBaseItem.rename(newname: encFilename) != nil else {
                return nil
            }
            await bs.list(fileId: toItem.id)
            if array.count == 3 {
                newid = "\(toParentDirId)/\(encFilename)/\(array[2])"
            }
            else {
                newid = "\(toParentDirId)/\(encFilename)"
            }
        }

        // register record
        let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
        let storage = storageName ?? ""
        return await backgroundContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? backgroundContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                if let item = items.first {
                    item.id = newid
                    item.parent = toParentId
                    item.path = "\(toParentPath)/\(item.name ?? "")"
                    try? backgroundContext.save()
                    return newid
                }
            }
            return nil
        }
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

        let parentDirId: String
        if parentId == "" {
            parentDirId = ""
        }
        else {
            let array = parentId.components(separatedBy: "/")
            guard array.count == 3 else {
                return nil
            }
            parentDirId = array[2]
        }

        guard let parentDirIdHash = resolveDirectory(dirId: parentDirId) else {
            return nil
        }

        guard var encFilename = encryptFilename(cleartextName: uploadname, dirId: parentDirId) else {
            return nil
        }
        encFilename += normal_ext

        guard let crypttarget = processFile(target: target) else {
            return nil
        }

        // if needed filename shorten
        if encFilename.count > shorteningThreshold {
            let target2 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            do {
                try encFilename.write(to: target2, atomically: true, encoding: .utf8)
            }
            catch {
                print(error)
                return nil
            }
            guard let deflatedName = deflate(longFileName: encFilename) else {
                return nil
            }

            guard let dirItem = await makeParentStorage(path: [DATA_DIR_NAME, String(parentDirIdHash.prefix(2)), String(parentDirIdHash.suffix(30)), deflatedName]) else {
                return nil
            }
            guard (try? await bs.upload(parentId: dirItem.id, uploadname: "name.c9s", target: target2)) != nil else {
                return nil
            }

            guard let newContentId = try? await bs.upload(parentId: dirItem.id, uploadname: "contents.c9r", target: crypttarget, progress: progress) else {
                return nil
            }

            // register record
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            let storage = storageName ?? ""
            let baseStorage = baseRootStorage
            let convertDecryptSize = {
                self.ConvertDecryptSize(size: $0)
            }
            return await backgroundContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newContentId, baseStorage)
                if let result = try? backgroundContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                    if let item = items.first {
                        let newid = "\(parentDirId)/\(encFilename)"
                        let newname = uploadname
                        let newcdate = item.cdate
                        let newmdate = item.mdate
                        let newsize = convertDecryptSize(item.size)
                        
                        let newitem = RemoteData(context: backgroundContext)
                        newitem.storage = storage
                        newitem.id = newid
                        newitem.name = newname
                        let comp = newname.components(separatedBy: ".")
                        if comp.count >= 1 {
                            newitem.ext = comp.last!.lowercased()
                        }
                        newitem.cdate = newcdate
                        newitem.mdate = newmdate
                        newitem.folder = false
                        newitem.size = newsize
                        newitem.hashstr = ""
                        newitem.parent = parentId
                        if parentId == "" {
                            newitem.path = "\(storage):/\(newname)"
                        }
                        else {
                            newitem.path = "\(parentPath)/\(newname)"
                        }
                        try? backgroundContext.save()
                        return newid
                    }
                }
                return nil
            }
        }
        else {
            guard let item = await findParentStorage(path: [DATA_DIR_NAME, String(parentDirIdHash.prefix(2)), String(parentDirIdHash.suffix(30))], expand: false).first else {
                return nil
            }

            guard let newBaseId = try? await bs.upload(parentId: item.id, uploadname: encFilename, target: crypttarget, progress: progress) else {
                return nil
            }

            // register record
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            let storage = storageName ?? ""
            let baseStorage = baseRootStorage
            let convertDecryptSize = {
                self.ConvertDecryptSize(size: $0)
            }
            return await backgroundContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
                if let result = try? backgroundContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                    if let item = items.first {
                        let newid = "\(parentDirId)/\(encFilename)"
                        let newname = uploadname
                        let newcdate = item.cdate
                        let newmdate = item.mdate
                        let newsize = convertDecryptSize(item.size)
                        
                        let newitem = RemoteData(context: backgroundContext)
                        newitem.storage = storage
                        newitem.id = newid
                        newitem.name = newname
                        let comp = newname.components(separatedBy: ".")
                        if comp.count >= 1 {
                            newitem.ext = comp.last!.lowercased()
                        }
                        newitem.cdate = newcdate
                        newitem.mdate = newmdate
                        newitem.folder = false
                        newitem.size = newsize
                        newitem.hashstr = ""
                        newitem.parent = parentId
                        if parentId == "" {
                            newitem.path = "\(storage):/\(newname)"
                        }
                        else {
                            newitem.path = "\(parentPath)/\(newname)"
                        }
                        try? backgroundContext.save()
                        return newid
                    }
                }
                return nil
            }
        }
    }

    override func processFile(target: URL) -> URL? {
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
        
        let cipher = CryptomatorCryptor(encryptionMasterKey: encryptionMasterKey, macMasterKey: macMasterKey)
        // header
        guard let header = cipher.createHeader() else {
            return nil
        }
        guard header.count == output.write(header, maxLength: header.count) else {
            return nil
        }
        
        var buffer = [UInt8](repeating: 0, count: CryptomatorCryptor.payloadSize)
        var chunkNo: UInt64 = 0
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
            
            guard let crypted = cipher.encryptChunk(chunk: Data(bytes: &buffer, count: len), chunkId: chunkNo) else {
                return nil
            }
            var outbuf = [UInt8](crypted)
            guard outbuf.count == output.write(&outbuf, maxLength: outbuf.count) else {
                return nil
            }
            
            chunkNo += 1
        } while len == CryptomatorCryptor.payloadSize

        return crypttarget
    }
    
    override func readFile(fileId: String, start: Int64?, length: Int64?) async throws -> Data? {
        os_log("%{public}@", log: log, type: .debug, "readFile(cryptomator:\(storageName ?? "")) \(fileId)")
        
        let array = fileId.components(separatedBy: "/")
        let dirId = array[0]
        let deflateId = array[1]

        if deflateId == "" {
            return nil
        }

        guard let dirIdHash = resolveDirectory(dirId: dirId) else {
            return nil
        }

        let items = await findParentStorage(path: [DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))])
        for item in items {
            if item.name == deflateId {
                if item.isFolder {
                    let subItems = await findParentStorage(path: [DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30)), deflateId])
                    if let contentItem = subItems.first(where: { $0.name == "contents.c9r" }) {
                        return try await contentItem.read(start: start, length: length)
                    }
                }
                else {
                    return try await item.read(start: start, length: length)
                }
            }
        }
        return nil
    }
    
    override func ConvertDecryptSize(size: Int64) -> Int64 {
        return Int64(CalcDecryptedSize(crypt_size: Int(size)))
    }
    
    override func ConvertEncryptSize(size: Int64) -> Int64 {
        return Int64(CalcEncryptedSize(org_size: Int(size)))
    }

    func CalcEncryptedSize(org_size: Int) -> Int {
        if org_size < 0 {
            return 0
        }
        let cleartextChunkSize = CryptomatorCryptor.payloadSize
        let ciphertextChunkSize = CryptomatorCryptor.chunkSize
        let overheadPerChunk = ciphertextChunkSize - cleartextChunkSize
        let numFullChunks = org_size / cleartextChunkSize // floor by int-truncation
        let additionalCleartextBytes = org_size % cleartextChunkSize
        let additionalCiphertextBytes = (additionalCleartextBytes == 0) ? 0 : additionalCleartextBytes + overheadPerChunk;
        guard additionalCiphertextBytes >= 0 else {
            return 0
        }
        return ciphertextChunkSize * numFullChunks + additionalCiphertextBytes + CryptomatorCryptor.headerSize
    }
    
    func CalcDecryptedSize(crypt_size: Int) -> Int {
        if crypt_size <= 0 {
            return 0
        }
        let size = crypt_size - CryptomatorCryptor.headerSize
        if size < 0 {
            return 0
        }
        let cleartextChunkSize = CryptomatorCryptor.payloadSize
        let ciphertextChunkSize = CryptomatorCryptor.chunkSize
        let overheadPerChunk = ciphertextChunkSize - cleartextChunkSize
        let numFullChunks = size / ciphertextChunkSize // floor by int-truncation
        let additionalCiphertextBytes = size % ciphertextChunkSize
        if (additionalCiphertextBytes > 0 && additionalCiphertextBytes <= overheadPerChunk) {
            return 0
        }
        let additionalCleartextBytes = (additionalCiphertextBytes == 0) ? 0 : additionalCiphertextBytes - overheadPerChunk
        guard additionalCleartextBytes >= 0 else {
            return 0
        }
        return cleartextChunkSize * numFullChunks + additionalCleartextBytes;
    }
}

public class CryptomatorRemoteItem: RemoteItem {
    let remoteStorage: Cryptomator
    
    override init?(storage: String, id: String) async {
        guard let s = await CloudFactory.shared.storageList.get(storage) as? Cryptomator else {
            return nil
        }
        remoteStorage = s
        await super.init(storage: storage, id: id)
    }
    
    public override func open() async -> RemoteStream {
        return await RemoteCryptomatorStream(remote: self)
    }
}

class CryptomatorCryptor {
    static let nonceLen = 12
    static let payloadSize = 32 * 1024
    static let tagLen = 16
    static let chunkSize = CryptomatorCryptor.nonceLen + CryptomatorCryptor.payloadSize + CryptomatorCryptor.tagLen
    
    static let headerPayloadSize = 40
    static let contentKeyLen = 32
    static let contentKeyOffset = 8
    static let headerSize = CryptomatorCryptor.nonceLen + CryptomatorCryptor.headerPayloadSize + CryptomatorCryptor.tagLen

    let encryptionMasterKey: [UInt8]
    let macMasterKey: [UInt8]

    var headerNonce = [UInt8]()
    var contentKey = [UInt8]()

    init(encryptionMasterKey: [UInt8], macMasterKey: [UInt8]) {
        self.encryptionMasterKey = encryptionMasterKey
        self.macMasterKey = macMasterKey
    }
    
    func createHeader() -> [UInt8]? {
        // generate key
        headerNonce = [UInt8](repeating: 0, count: CryptomatorCryptor.nonceLen)
        guard SecRandomCopyBytes(kSecRandomDefault, headerNonce.count, &headerNonce) == errSecSuccess else {
            return nil
        }
        contentKey = [UInt8](repeating: 0, count: CryptomatorCryptor.contentKeyLen)
        guard SecRandomCopyBytes(kSecRandomDefault, contentKey.count, &contentKey) == errSecSuccess else {
            return nil
        }

        // not use now, set all 1
        let header_filesize_1 = [UInt8](repeating: 0xFF, count: CryptomatorCryptor.contentKeyOffset)
                
        // payload
        var payloadCleartext = [UInt8](repeating: 0, count: CryptomatorCryptor.headerPayloadSize)
        payloadCleartext[0..<header_filesize_1.count] = header_filesize_1[0...]
        payloadCleartext[header_filesize_1.count..<(header_filesize_1.count + contentKey.count)] = contentKey[0...]

        // encrypt payload
        guard let header = try? encryptHeader(payloadCleartext, key: encryptionMasterKey, nonce: headerNonce) else {
            print("header payload encryption error")
            return nil
        }
        return header
    }
    
    func encryptChunk(chunk: Data, chunkId: UInt64) -> [UInt8]? {
        // nonce
        var chunkNonce = [UInt8](repeating: 0, count: CryptomatorCryptor.nonceLen)
        guard SecRandomCopyBytes(kSecRandomDefault, chunkNonce.count, &chunkNonce) == errSecSuccess else {
            return nil
        }
        if let data = try? encryptChunk([UInt8](chunk), chunkNumber: chunkId, chunkNonce: chunkNonce, fileKey: contentKey, headerNonce: headerNonce) {
            return data
        }
        return nil
    }
    
    func decryptHeader(header: Data) -> Bool {
        guard header.count == CryptomatorCryptor.headerSize else {
            print("error on header size check")
            return false
        }
        let nonce = [UInt8](header[0..<CryptomatorCryptor.nonceLen])
        guard let cleartext = try? decryptHeader([UInt8](header), key: encryptionMasterKey) else {
            return false
        }
        headerNonce = nonce
        contentKey = [UInt8](cleartext[CryptomatorCryptor.contentKeyOffset...])
        return true
    }

    func decryptChunk(chunk: Data, chunkId: UInt64) -> Data? {
        if let data = try? decryptChunk([UInt8](chunk), chunkNumber: chunkId, fileKey: contentKey, headerNonce: headerNonce) {
            return Data(data)
        }
        return nil
    }

    func encryptHeader(_ header: [UInt8], key: [UInt8], nonce: [UInt8]) throws -> [UInt8] {
        return try encrypt(header, key: key, nonce: nonce, ad: [])
    }

    func decryptHeader(_ header: [UInt8], key: [UInt8]) throws -> [UInt8] {
        return try decrypt(header, key: key, ad: [])
    }

    func encryptChunk(_ chunk: [UInt8], chunkNumber: UInt64, chunkNonce: [UInt8], fileKey: [UInt8], headerNonce: [UInt8]) throws -> [UInt8] {
        let ad = ad(chunkNumber: chunkNumber, headerNonce: headerNonce)
        return try encrypt(chunk, key: fileKey, nonce: chunkNonce, ad: ad)
    }

    func decryptChunk(_ chunk: [UInt8], chunkNumber: UInt64, fileKey: [UInt8], headerNonce: [UInt8]) throws -> [UInt8] {
        let ad = ad(chunkNumber: chunkNumber, headerNonce: headerNonce)
        return try decrypt(chunk, key: fileKey, ad: ad)
    }

    func ad(chunkNumber: UInt64, headerNonce: [UInt8]) -> [UInt8] {
        return chunkNumber.bigEndian.byteArray() + headerNonce
    }

    func encrypt(_ chunk: [UInt8], key keyBytes: [UInt8], nonce nonceBytes: [UInt8], ad: [UInt8]) throws -> [UInt8] {
        let key = SymmetricKey(data: keyBytes)
        let nonce = try AES.GCM.Nonce(data: nonceBytes)
        let encrypted = try AES.GCM.seal(chunk, using: key, nonce: nonce, authenticating: ad)

        return [UInt8](encrypted.nonce + encrypted.ciphertext + encrypted.tag)
    }

    func decrypt(_ chunk: [UInt8], key keyBytes: [UInt8], ad: [UInt8]) throws -> [UInt8] {
        assert(chunk.count >= CryptomatorCryptor.nonceLen + CryptomatorCryptor.tagLen, "ciphertext chunk must at least contain nonce + tag")

        let key = SymmetricKey(data: keyBytes)
        let encrypted = try AES.GCM.SealedBox(combined: chunk)
        let decrypted = try AES.GCM.open(encrypted, using: key, authenticating: ad)

        return [UInt8](decrypted)
    }
}

public class RemoteCryptomatorStream: SlotStream {
    let remote: CryptomatorRemoteItem
    let OrignalLength: Int64
    let CryptedLength: Int64
    
    let cipher: CryptomatorCryptor
    
    init(remote: CryptomatorRemoteItem) async {
        self.remote = remote
        OrignalLength = remote.size
        CryptedLength = Int64(remote.remoteStorage.CalcEncryptedSize(org_size: Int(OrignalLength)))
        cipher = CryptomatorCryptor(encryptionMasterKey: remote.remoteStorage.encryptionMasterKey, macMasterKey: remote.remoteStorage.macMasterKey)
        await super.init(size: OrignalLength)
    }

    override func fillHeader() async {
        guard let data = try? await remote.read(start: 0, length: Int64(CryptomatorCryptor.headerSize)) else {
            print("error on header null")
            error = true
            await super.fillHeader()
            return
        }
        guard cipher.decryptHeader(header: data) else {
            error = true
            await super.fillHeader()
            return
        }
        await super.fillHeader()
    }
    
    override func subFillBuffer(pos: ClosedRange<Int64>) async {
        guard await initialized.wait(timeout: .seconds(10)) == .success else {
            error = true
            return
        }

        let chunksize = Int64(CryptomatorCryptor.chunkSize)
        let orgBlocksize = Int64(CryptomatorCryptor.payloadSize)
        let headersize = Int64(CryptomatorCryptor.headerSize)
        if await !buffer.dataAvailable(pos: pos) {
            guard pos.lowerBound >= 0 && pos.upperBound < size else {
                return
            }
            let len = min(size-1, pos.upperBound) - pos.lowerBound + 1
            let slot1 = pos.lowerBound / orgBlocksize
            let pos2 = slot1 * chunksize + headersize
            var clen = (len / orgBlocksize + 1) * chunksize
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
            var slot = UInt64(slot1)
            var plainBlock = Data()
            for start in stride(from: 0, to: data.count, by: Int(chunksize)) {
                let end = (start+Int(chunksize) >= data.count) ? data.count : start+Int(chunksize)
                let chunk = data.subdata(in: start..<end)
                guard let plain = cipher.decryptChunk(chunk: chunk, chunkId: slot) else {
                    error = true
                    return
                }
                plainBlock.append(plain)
                slot += 1
                guard !error else {
                    return
                }
            }
            await buffer.store(pos: pos.lowerBound, data: plainBlock)
        }
    }
}

class BASE32 {
    // https://github.com/norio-nomura/Base32/blob/master/Sources/Base32/Base32.swift
    static let alphabetEncodeTable: [Int8] = ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z","2","3","4","5","6","7"].map { (c: UnicodeScalar) -> Int8 in Int8(c.value) }

    public class func base32encode(input: Data) -> String? {
        let table = alphabetEncodeTable
        if input.count == 0 {
            return ""
        }
        let resultBufferSize = Int(ceil(Double(input.count) / 5)) * 8 + 1    // need null termination
        var resultBuffer = [Int8](repeating: 0, count: resultBufferSize)
        var base32Encoded: String?
        input.withUnsafeBytes { data in
            var bytes = data.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var encoded = [Int8](repeating: 0, count: 9)
            
            var length = input.count
            var offset = 0

            // encode regular blocks
            while length >= 5 {
                encoded[0] = table[Int(bytes[0] >> 3)]
                encoded[1] = table[Int((bytes[0] & 0b00000111) << 2 | bytes[1] >> 6)]
                encoded[2] = table[Int((bytes[1] & 0b00111110) >> 1)]
                encoded[3] = table[Int((bytes[1] & 0b00000001) << 4 | bytes[2] >> 4)]
                encoded[4] = table[Int((bytes[2] & 0b00001111) << 1 | bytes[3] >> 7)]
                encoded[5] = table[Int((bytes[3] & 0b01111100) >> 2)]
                encoded[6] = table[Int((bytes[3] & 0b00000011) << 3 | bytes[4] >> 5)]
                encoded[7] = table[Int((bytes[4] & 0b00011111))]
                length -= 5
                bytes = bytes.advanced(by: 5)
                resultBuffer[offset..<(offset+8)] = encoded[0..<8]
                offset += 8
            }

            // encode last block
            var byte0, byte1, byte2, byte3, byte4: UInt8
            (byte0, byte1, byte2, byte3, byte4) = (0,0,0,0,0)
            switch length {
            case 4:
                byte3 = bytes[3]
                encoded[6] = table[Int((byte3 & 0b00000011) << 3 | byte4 >> 5)]
                encoded[5] = table[Int((byte3 & 0b01111100) >> 2)]
                fallthrough
            case 3:
                byte2 = bytes[2]
                encoded[4] = table[Int((byte2 & 0b00001111) << 1 | byte3 >> 7)]
                fallthrough
            case 2:
                byte1 = bytes[1]
                encoded[3] = table[Int((byte1 & 0b00000001) << 4 | byte2 >> 4)]
                encoded[2] = table[Int((byte1 & 0b00111110) >> 1)]
                fallthrough
            case 1:
                byte0 = bytes[0]
                encoded[1] = table[Int((byte0 & 0b00000111) << 2 | byte1 >> 6)]
                encoded[0] = table[Int(byte0 >> 3)]
            default: break
            }
            
            // padding
            let pad = Int8(UnicodeScalar("=").value)
            switch length {
            case 0:
                encoded[0] = 0
                resultBuffer[offset..<(offset+1)] = encoded[0..<1]
            case 1:
                encoded[2] = pad
                encoded[3] = pad
                fallthrough
            case 2:
                encoded[4] = pad
                fallthrough
            case 3:
                encoded[5] = pad
                encoded[6] = pad
                fallthrough
            case 4:
                encoded[7] = pad
                fallthrough
            default:
                encoded[8] = 0
                resultBuffer[offset..<(offset+9)] = encoded[0..<9]
                break
            }
            base32Encoded = String(validatingUTF8: resultBuffer)
        }
        return base32Encoded
    }
    
    static let __: UInt8 = 255
    static let alphabetDecodeTable: [UInt8] = [
        __,__,__,__, __,__,__,__, __,__,__,__, __,__,__,__,  // 0x00 - 0x0F
        __,__,__,__, __,__,__,__, __,__,__,__, __,__,__,__,  // 0x10 - 0x1F
        __,__,__,__, __,__,__,__, __,__,__,__, __,__,__,__,  // 0x20 - 0x2F
        __,__,26,27, 28,29,30,31, __,__,__,__, __,__,__,__,  // 0x30 - 0x3F
        __, 0, 1, 2,  3, 4, 5, 6,  7, 8, 9,10, 11,12,13,14,  // 0x40 - 0x4F
        15,16,17,18, 19,20,21,22, 23,24,25,__, __,__,__,__,  // 0x50 - 0x5F
        __, 0, 1, 2,  3, 4, 5, 6,  7, 8, 9,10, 11,12,13,14,  // 0x60 - 0x6F
        15,16,17,18, 19,20,21,22, 23,24,25,__, __,__,__,__,  // 0x70 - 0x7F
        __,__,__,__, __,__,__,__, __,__,__,__, __,__,__,__,  // 0x80 - 0x8F
        __,__,__,__, __,__,__,__, __,__,__,__, __,__,__,__,  // 0x90 - 0x9F
        __,__,__,__, __,__,__,__, __,__,__,__, __,__,__,__,  // 0xA0 - 0xAF
        __,__,__,__, __,__,__,__, __,__,__,__, __,__,__,__,  // 0xB0 - 0xBF
        __,__,__,__, __,__,__,__, __,__,__,__, __,__,__,__,  // 0xC0 - 0xCF
        __,__,__,__, __,__,__,__, __,__,__,__, __,__,__,__,  // 0xD0 - 0xDF
        __,__,__,__, __,__,__,__, __,__,__,__, __,__,__,__,  // 0xE0 - 0xEF
        __,__,__,__, __,__,__,__, __,__,__,__, __,__,__,__,  // 0xF0 - 0xFF
    ]
    
    public class func base32decode(input: String) -> Data? {
        let table = alphabetDecodeTable
        
        // calc padding length
        func getLeastPaddingLength(_ string: String) -> Int {
            if string.hasSuffix("======") {
                return 6
            } else if string.hasSuffix("====") {
                return 4
            } else if string.hasSuffix("===") {
                return 3
            } else if string.hasSuffix("=") {
                return 1
            } else {
                return 0
            }
        }

        let leastPaddingLength = getLeastPaddingLength(input)
        
        var remainEncodedLength = input.count - leastPaddingLength
        var additionalBytes = 0
        switch remainEncodedLength % 8 {
        // valid
        case 0: break
        case 2: additionalBytes = 1
        case 4: additionalBytes = 2
        case 5: additionalBytes = 3
        case 7: additionalBytes = 4
        default:
            print("string length is invalid.")
            return nil
        }
        
        var result = Data()
        
        let inputdata = input.map { UInt8($0.unicodeScalars.first!.value) }
        return inputdata.withUnsafeBytes { indata in
            var encoded = indata.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var decoded = [UInt8](repeating: 0, count: 5)
            
            // decode regular blocks
            var value = [UInt8](repeating: 0, count: 8)
            while remainEncodedLength >= 8 {
                value[0] = table[Int(encoded[0])]
                value[1] = table[Int(encoded[1])]
                value[2] = table[Int(encoded[2])]
                value[3] = table[Int(encoded[3])]
                value[4] = table[Int(encoded[4])]
                value[5] = table[Int(encoded[5])]
                value[6] = table[Int(encoded[6])]
                value[7] = table[Int(encoded[7])]
                
                guard value.allSatisfy({ $0 < 32 }) else {
                    return nil
                }
                
                decoded[0] = value[0] << 3 | value[1] >> 2
                decoded[1] = value[1] << 6 | value[2] << 1 | value[3] >> 4
                decoded[2] = value[3] << 4 | value[4] >> 1
                decoded[3] = value[4] << 7 | value[5] << 2 | value[6] >> 3
                decoded[4] = value[6] << 5 | value[7]
                
                remainEncodedLength -= 8
                encoded = encoded.advanced(by: 8)
                result.append(contentsOf: decoded)
            }
            
            // decode last block
            var value0, value1, value2, value3, value4, value5, value6: UInt8
            (value0, value1, value2, value3, value4, value5, value6) = (0,0,0,0,0,0,0)
            switch remainEncodedLength {
            case 7:
                value6 = table[Int(encoded[6])]
                value5 = table[Int(encoded[5])]
                guard value6 < 32, value5 < 32 else {
                    return nil
                }
                fallthrough
            case 5:
                value4 = table[Int(encoded[4])]
                guard value4 < 32 else {
                    return nil
                }
                fallthrough
            case 4:
                value3 = table[Int(encoded[3])]
                value2 = table[Int(encoded[2])]
                guard value3 < 32, value2 < 32 else {
                    return nil
                }
                fallthrough
            case 2:
                value1 = table[Int(encoded[1])]
                value0 = table[Int(encoded[0])]
                guard value1 < 32, value0 < 32 else {
                    return nil
                }
            default: break
            }
            switch remainEncodedLength {
            case 7:
                decoded[3] = value4 << 7 | value5 << 2 | value6 >> 3
                fallthrough
            case 5:
                decoded[2] = value3 << 4 | value4 >> 1
                fallthrough
            case 4:
                decoded[1] = value1 << 6 | value2 << 1 | value3 >> 4
                fallthrough
            case 2:
                decoded[0] = value0 << 3 | value1 >> 2
            default: break
            }
            
            if additionalBytes > 0 {
                result.append(contentsOf: decoded[0..<additionalBytes])
            }
            return result
        }
    }
}

public enum CryptoError: Error, Equatable {
    case invalidParameter(_ reason: String)
    case ccCryptorError(_ status: CCCryptorStatus)
    case unauthenticCiphertext
    case csprngError
    case ioError
}

class AesCtr {
    /**
     High-level AES-CTR wrapper around CommonCrypto primitives. Can be used for encryption and decryption (it is the same in CTR mode).

     - Parameter key: 128 or 256 bit encryption key
     - Parameter iv: 128 bit initialization vector (must not be reused!)
     - Parameter data: data to be encrypted/decrypted
     - Returns: encrypted/decrypted data
     */
    static func compute(key: [UInt8], iv: [UInt8], data: [UInt8]) throws -> [UInt8] {
        assert(key.count == kCCKeySizeAES256 || key.count == kCCKeySizeAES128, "key expected to be 128 or 256 bit")
        assert(iv.count == kCCBlockSizeAES128, "iv expected to be 128 bit")

        var cryptor: CCCryptorRef?
        var status = CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding), iv, key, key.count, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
        guard status == kCCSuccess, cryptor != nil else {
            throw CryptoError.invalidParameter("failed to initialize cryptor")
        }
        defer {
            CCCryptorRelease(cryptor)
        }

        let outlen = CCCryptorGetOutputLength(cryptor, data.count, true)
        var ciphertext = [UInt8](repeating: 0x00, count: outlen)

        var numEncryptedBytes = 0
        status = CCCryptorUpdate(cryptor, data, data.count, &ciphertext, ciphertext.count, &numEncryptedBytes)
        guard status == kCCSuccess else {
            throw CryptoError.ccCryptorError(status)
        }

        status = CCCryptorFinal(cryptor, &ciphertext, ciphertext.count, &numEncryptedBytes)
        guard status == kCCSuccess else {
            throw CryptoError.ccCryptorError(status)
        }

        return ciphertext
    }
}

class CryptoSupport {
    /**
     Creates an array of cryptographically secure random bytes.

     - Parameter size: The number of random bytes to return in the array.
     - Returns: An array with cryptographically secure random bytes.
     */
    func createRandomBytes(size: Int) throws -> [UInt8] {
        var randomBytes = [UInt8](repeating: 0x00, count: size)
        guard SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess else {
            throw CryptoError.csprngError
        }
        return randomBytes
    }

    /**
     Compares byte arrays in constant-time.

     The running time of this method is independent of the byte arrays compared, making it safe to use for comparing secret values such as cryptographic MACs.

     The byte arrays are expected to be of same length.

     - Parameter expected: Expected bytes for comparison.
     - Parameter actual: Actual bytes for comparison.
     - Returns: `true` if `expected` and `actual` are equal, otherwise `false`.
     */
    func compareBytes(expected: [UInt8], actual: [UInt8]) -> Bool {
        assert(expected.count == actual.count, "parameters should be of same length")
        return timingsafe_bcmp(expected, actual, expected.count) == 0
    }
}

class AesSiv {
    static let cryptoSupport = CryptoSupport()
    static let zero = [UInt8](repeating: 0x00, count: 16)
    static let dblConst: UInt8 = 0x87

    /**
     Encrypts plaintext using SIV mode.

     - Parameter aesKey: SIV mode requires two separate keys. You can use one long key, which is splitted in half. See [RFC 5297 Section 2.2](https://tools.ietf.org/html/rfc5297#section-2.2).
     - Parameter macKey: SIV mode requires two separate keys. You can use one long key, which is splitted in half. See [RFC 5297 Section 2.2](https://tools.ietf.org/html/rfc5297#section-2.2).
     - Parameter plaintext: Your plaintext, which shall be encrypted. It must not be longer than 2^32 - 16 bytes.
     - Parameter ad: Associated data, which gets authenticated but not encrypted.
     - Returns: IV + Ciphertext as a concatenated byte array.
     */
    static func encrypt(aesKey: [UInt8], macKey: [UInt8], plaintext: [UInt8], ad: [UInt8]...) throws -> [UInt8] {
        guard plaintext.count <= UInt32.max - 16 else {
            throw CryptoError.invalidParameter("plaintext must not be longer than 2^32 - 16 bytes")
        }
        let iv = try s2v(macKey: macKey, plaintext: plaintext, ad: ad)
        let ciphertext = try ctr(aesKey: aesKey, iv: iv, plaintext: plaintext)
        return iv + ciphertext
    }

    /**
     Decrypts ciphertext using SIV mode.

     - Parameter aesKey: SIV mode requires two separate keys. You can use one long key, which is splitted in half. See [RFC 5297 Section 2.2](https://tools.ietf.org/html/rfc5297#section-2.2).
     - Parameter macKey: SIV mode requires two separate keys. You can use one long key, which is splitted in half. See [RFC 5297 Section 2.2](https://tools.ietf.org/html/rfc5297#section-2.2).
     - Parameter ciphertext: Your ciphertext, which shall be decrypted. It must be at least 16 bytes.
     - Parameter ad: Associated data, which needs to be authenticated during decryption.
     - Returns: Plaintext byte array.
     */
    static func decrypt(aesKey: [UInt8], macKey: [UInt8], ciphertext: [UInt8], ad: [UInt8]...) throws -> [UInt8] {
        guard ciphertext.count >= 16 else {
            throw CryptoError.invalidParameter("ciphertext must be at least 16 bytes")
        }
        let iv = Array(ciphertext[..<16])
        let actualCiphertext = Array(ciphertext[16...])
        let plaintext = try ctr(aesKey: aesKey, iv: iv, plaintext: actualCiphertext)
        let control = try s2v(macKey: macKey, plaintext: plaintext, ad: ad)
        guard cryptoSupport.compareBytes(expected: control, actual: iv) else {
            throw CryptoError.unauthenticCiphertext
        }
        return plaintext
    }

    // MARK: - Internal

    static func ctr(aesKey key: [UInt8], iv: [UInt8], plaintext: [UInt8]) throws -> [UInt8] {
        // clear out the 31st and 63rd bit (see https://tools.ietf.org/html/rfc5297#section-2.5)
        var ctr = iv
        ctr[8] &= 0x7F
        ctr[12] &= 0x7F
        return try AesCtr.compute(key: key, iv: ctr, data: plaintext)
    }

    static func s2v(macKey: [UInt8], plaintext: [UInt8], ad: [[UInt8]]) throws -> [UInt8] {
        // Maximum permitted AD length is the block size in bits - 2
        assert(ad.count <= 126, "too many ad")

        // RFC 5297 defines a n == 0 case here. Where n is the length of the input vector:
        // S1 = associatedData1, S2 = associatedData2, ... Sn = plaintext
        // Since this method is invoked only by encrypt/decrypt, we always have a plaintext.
        // Thus n > 0

        var d = try cmac(macKey: macKey, data: zero)
        for s in ad {
            d = try xor(dbl(d), cmac(macKey: macKey, data: s))
        }

        let t: [UInt8]
        if plaintext.count >= 16 {
            t = xorend(plaintext, d)
        } else {
            t = xor(dbl(d), pad(plaintext))
        }

        return try cmac(macKey: macKey, data: t)
    }

    static func cmac(macKey key: [UInt8], data: [UInt8]) throws -> [UInt8] {
        // subkey generation:
        let l = try aes(key: key, plaintext: zero)
        let k1 = l[0] & 0x80 == 0x00 ? shiftLeft(l) : dbl(l)
        let k2 = k1[0] & 0x80 == 0x00 ? shiftLeft(k1) : dbl(k1)

        // determine number of blocks:
        let n = (data.count + 15) / 16
        let lastBlockIdx: Int
        let lastBlockComplete: Bool
        if n == 0 {
            lastBlockIdx = 0
            lastBlockComplete = false
        } else {
            lastBlockIdx = n - 1
            lastBlockComplete = data.count % 16 == 0
        }

        // blocks 0..<n:
        var mac = [UInt8](repeating: 0x00, count: 16)
        for i in 0 ..< lastBlockIdx {
            let block = Array(data[(16 * i) ..< (16 * (i + 1))])
            let y = xor(mac, block)
            mac = try aes(key: key, plaintext: y)
        }

        // block n:
        var lastBlock = Array(data[(16 * lastBlockIdx)...])
        if lastBlockComplete {
            lastBlock = xor(lastBlock, k1)
        } else {
            lastBlock = xor(pad(lastBlock), k2)
        }
        let y = xor(mac, lastBlock)
        mac = try aes(key: key, plaintext: y)

        return mac
    }

    private static func aes(key: [UInt8], plaintext: [UInt8]) throws -> [UInt8] {
        assert(key.count == kCCKeySizeAES128 || key.count == kCCKeySizeAES192 || key.count == kCCKeySizeAES256)
        assert(plaintext.count == kCCBlockSizeAES128, "Attempt to run AES-ECB for plaintext != one single block")

        var ciphertext = [UInt8](repeating: 0x00, count: kCCBlockSizeAES128)
        var ciphertextLen = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode), key, key.count, nil, plaintext, plaintext.count, &ciphertext, kCCBlockSizeAES128, &ciphertextLen)

        guard status == kCCSuccess else {
            throw CryptoError.ccCryptorError(status)
        }

        return ciphertext
    }

    private static func shiftLeft(_ input: [UInt8]) -> [UInt8] {
        var output = [UInt8](repeating: 0x00, count: input.count)
        var bit: UInt8 = 0
        for i in (0 ..< input.count).reversed() {
            let b = input[i] & 0xFF
            output[i] = (b << 1) | bit
            bit = (b >> 7) & 1
        }
        return output
    }

    private static func dbl(_ block: [UInt8]) -> [UInt8] {
        var result = shiftLeft(block)
        if block[0] & 0x80 != 0x00 {
            result[block.count - 1] ^= dblConst
        }
        return result
    }

    private static func xor(_ data1: [UInt8], _ data2: [UInt8]) -> [UInt8] {
        assert(data1.count <= data2.count, "Length of first input must be <= length of second input.")
        var result = [UInt8](repeating: 0x00, count: data1.count)
        for i in 0 ..< data1.count {
            result[i] = data1[i] ^ data2[i]
        }
        return result
    }

    private static func xorend(_ data1: [UInt8], _ data2: [UInt8]) -> [UInt8] {
        assert(data1.count >= data2.count, "Length of first input must be >= length of second input.")
        var result = data1
        let diff = data1.count - data2.count
        for i in 0 ..< data2.count {
            result[i + diff] = data1[i + diff] ^ data2[i]
        }
        return result
    }

    // ISO/IEC 7816-4:2005 Padding: First bit 1, following bits 0
    private static func pad(_ data: [UInt8]) -> [UInt8] {
        var result = data
        if result.count < 16 {
            result.append(0x80)
        }
        while result.count < 16 {
            result.append(0x00)
        }
        return result
    }
}

class AES_CMAC {
    public class func digest(key: [UInt8], message: [UInt8]) -> [UInt8]? {
        guard [128,192,256].contains(key.count * 8) else {
            return nil
        }
        var sum = [UInt8](repeating: 0, count: 16)
        let mlen = message.count
        let mblocks = (mlen + 15) / 16
        if mblocks > 0 {
            for i in 0..<mblocks-1 {
                let w = zip(sum, message[i*16..<(i+1)*16]).map() { $0 ^ $1 }
                guard let c = AES(key: key, data: w) else {
                    return nil
                }
                sum = c
            }
        }
        guard let el = AES(key: key, data: [UInt8](repeating: 0, count: 16)) else {
            return nil
        }
        let key1 = generateSubkey(el: el)
        let key2 = generateSubkey(el: key1)
        
        if mlen > 0 && mlen % 16 == 0 {
            var w = [UInt8](repeating: 0, count: 16)
            for i in 0..<16 {
                w[i] = sum[i] ^ key1[i] ^ message[mlen-16+i]
            }
            guard let c = AES(key: key, data: w) else {
                return nil
            }
            sum = c
        }
        else {
            var m = mblocks > 0 ? Array(message[((mblocks-1)*16)...]) : [UInt8]()
            m.append(0x80)
            for _ in (m.count % 16)..<16 {
                m.append(0)
            }
            var w = [UInt8](repeating: 0, count: 16)
            for i in 0..<16 {
                w[i] = sum[i] ^ key2[i] ^ m[i]
            }
            guard let c = AES(key: key, data: w) else {
                return nil
            }
            sum = c
        }
        return sum
    }
    
    class func generateSubkey(el: [UInt8]) -> [UInt8] {
        let Rb: UInt8 = 0x87
        let lsb: Bool = (el[0] & 0x80) != 0
        var key = [UInt8](repeating: 0, count: 16)
        for i in 0..<15 {
            key[i] = (el[i] << 1) | (el[i + 1] >> 7)
        }
        key[15] = (el[15] << 1) ^ (lsb ? Rb : 0)
        return key
     }
    
    class func AES(key: [UInt8], data: [UInt8], decode: Bool = false) -> [UInt8]? {
        guard [128,192,256].contains(key.count * 8) else {
            return nil
        }
        var outBytes = [UInt8](repeating: 0, count: data.count)
        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
        var outLength = Int(0)
        status = CCCrypt(CCOperation(decode ? kCCDecrypt : kCCEncrypt),
                         CCAlgorithm(kCCAlgorithmAES),
                         CCOptions(kCCOptionECBMode),
                         key,
                         key.count,
                         nil,
                         data,
                         data.count,
                         &outBytes,
                         outBytes.count,
                         &outLength)
        guard status == kCCSuccess else {
            return nil
        }
        return outBytes
    }
}

func HMACSign(_ message: [UInt8], key: [UInt8], alg: String) -> [UInt8] {
    guard ["HS256", "HS384", "HS512"].contains(alg) else {
        return []
    }
    
    var commonCryptoAlgorithm: CCHmacAlgorithm {
        switch alg {
        case "HS256":
            return CCHmacAlgorithm(kCCHmacAlgSHA256)
        case "HS384":
            return CCHmacAlgorithm(kCCHmacAlgSHA384)
        case "HS512":
            return CCHmacAlgorithm(kCCHmacAlgSHA512)
        default:
            fatalError()
        }
    }

    var commonCryptoDigestLength: Int32 {
        switch alg {
        case "HS256":
            return CC_SHA256_DIGEST_LENGTH
        case "HS384":
            return CC_SHA384_DIGEST_LENGTH
        case "HS512":
            return CC_SHA512_DIGEST_LENGTH
        default:
            fatalError()
        }
    }
    
    let context = UnsafeMutablePointer<CCHmacContext>.allocate(capacity: 1)
    defer { context.deallocate() }

    CCHmacInit(context, commonCryptoAlgorithm, key, size_t(key.count))
    CCHmacUpdate(context, message, size_t(message.count))
    var hmac = [UInt8](repeating: 0, count: Int(commonCryptoDigestLength))
    CCHmacFinal(context, &hmac)

    return hmac
}

func wrapKey(_ rawKey: [UInt8], kek: [UInt8]) -> [UInt8] {
    var wrappedKeyLen = CCSymmetricWrappedSize(CCWrappingAlgorithm(kCCWRAPAES), rawKey.count)
    var wrappedKey = [UInt8](repeating: 0x00, count: wrappedKeyLen)
    let status = CCSymmetricKeyWrap(CCWrappingAlgorithm(kCCWRAPAES), CCrfc3394_iv, CCrfc3394_ivLen, kek, kek.count, rawKey, rawKey.count, &wrappedKey, &wrappedKeyLen)
    if status == kCCSuccess {
        return wrappedKey
    } else {
        return []
    }
}

func unwrapKey(_ wrappedKey: [UInt8], kek: [UInt8]) -> [UInt8] {
    var unwrappedKeyLen = CCSymmetricUnwrappedSize(CCWrappingAlgorithm(kCCWRAPAES), wrappedKey.count)
    var unwrappedKey = [UInt8](repeating: 0x00, count: unwrappedKeyLen)
    let status = CCSymmetricKeyUnwrap(CCWrappingAlgorithm(kCCWRAPAES), CCrfc3394_iv, CCrfc3394_ivLen, kek, kek.count, wrappedKey, wrappedKey.count, &unwrappedKey, &unwrappedKeyLen)
    if status == kCCSuccess {
        assert(unwrappedKeyLen == kCCKeySizeAES256)
        return unwrappedKey
    } else {
        return []
    }
}

func checkVaultVersion(versionMac: String, version: Int, macKey: [UInt8]) -> Bool {
    guard let storedVersionMac = Data(base64Encoded: versionMac), storedVersionMac.count == CC_SHA256_DIGEST_LENGTH else {
        return false
    }
    var calculatedVersionMac = [UInt8](repeating: 0x00, count: Int(CC_SHA256_DIGEST_LENGTH))
    let versionBytes = withUnsafeBytes(of: UInt32(version).bigEndian, Array.init)
    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), macKey, macKey.count, versionBytes, versionBytes.count, &calculatedVersionMac)
    var diff: UInt8 = 0x00
    for i in 0 ..< calculatedVersionMac.count {
        diff |= calculatedVersionMac[i] ^ storedVersionMac[i]
    }
    return diff == 0x00
}

public extension FixedWidthInteger {
    func byteArray() -> [UInt8] {
        return withUnsafeBytes(of: self, { [UInt8]($0) })
    }
}

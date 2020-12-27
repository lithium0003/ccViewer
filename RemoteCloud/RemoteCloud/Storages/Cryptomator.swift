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

class ViewControllerPasswordCryptometor: UIViewController, UITextFieldDelegate {
    var textPassword: UITextField!
    var stackView: UIStackView!

    var onCancel: (()->Void)!
    var onFinish: ((String)->Void)!
    var done: Bool = false
    
    let activityIndicatorView = UIActivityIndicatorView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Cryptometor password"
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
        
        let stackView1 = UIStackView()
        stackView1.axis = .horizontal
        stackView1.alignment = .center
        stackView1.spacing = 20
        stackView.insertArrangedSubview(stackView1, at: 0)
        
        let label = UILabel()
        label.text = "Password"
        stackView1.insertArrangedSubview(label, at: 0)
        
        textPassword = UITextField()
        textPassword.borderStyle = .roundedRect
        textPassword.delegate = self
        textPassword.clearButtonMode = .whileEditing
        textPassword.returnKeyType = .done
        textPassword.isSecureTextEntry = true
        textPassword.placeholder = "password"
        stackView1.insertArrangedSubview(textPassword, at: 1)
        let widthConstraint = textPassword.widthAnchor.constraint(equalToConstant: 200)
        widthConstraint.priority = .defaultHigh
        widthConstraint.isActive = true
        
        let stackView4 = UIStackView()
        stackView4.axis = .horizontal
        stackView4.alignment = .center
        stackView4.spacing = 20
        stackView.insertArrangedSubview(stackView4, at: 1)
        
        let button1 = UIButton(type: .system)
        button1.setTitle("Done", for: .normal)
        button1.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView4.insertArrangedSubview(button1, at: 0)
        
        let button2 = UIButton(type: .system)
        button2.setTitle("Cancel", for: .normal)
        button2.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView4.insertArrangedSubview(button2, at: 1)
        
        activityIndicatorView.center = view.center
        if #available(iOS 13.0, *) {
            activityIndicatorView.style = .large
        } else {
            // Fallback on earlier versions
            activityIndicatorView.style = .whiteLarge
        }
        activityIndicatorView.hidesWhenStopped = true
        view.addSubview(activityIndicatorView)
    }
    
    @objc func buttonEvent(_ sender: UIButton) {
        if sender.currentTitle == "Done" {
            textPassword.resignFirstResponder()
            done = true
            activityIndicatorView.startAnimating()
            onFinish(textPassword.text ?? "")
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
        activityIndicatorView.startAnimating()
        onFinish(textPassword.text ?? "")
        return true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if textPassword.isFirstResponder {
            textPassword.resignFirstResponder()
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
    fileprivate var version = 6
    private var KEY_LEN_BYTES = 32
    
    let SHORT_NAMES_MAX_LENGTH = 129
    let DATA_DIR_NAME = "d"
    let METADATA_DIR_NAME = "m"
    let MASTERKEY_BACKUP_SUFFIX = ".bkup"
    let ROOT_DIR_ID = ""
    let LONG_NAME_FILE_EXT = ".lng"
    let masterkey_filename = "masterkey.cryptomator"
    let V7_DIR = "dir.c9r"

    enum ItemType {
        case regular
        case directory
        case symlink
        case broken
    }
    
    public override func getStorageType() -> CloudStorages {
        return .Cryptomator
    }
    
    public override init(name: String) {
        super.init(name: name)
        service = CloudFactory.getServiceName(service: .Cryptomator)
        storageName = name
        
        if let password = getKeyChain(key: "\(storageName ?? "")_password"),
            let datastr = getKeyChain(key: "\(storageName ?? "")_masterKey") {
            guard let data = datastr.data(using: .utf8) else {
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) else {
                return
            }
            guard let jsondata = json as? [String: Any] else {
                return
            }
            restoreMasterKeyFromJson(password: password, json: jsondata) { result in
                if result {
                    os_log("%{public}@", log: self.log, type: .debug, "restore_Key(cryptomator:\(self.storageName ?? "")) restore key success")
                }
                else {
                    os_log("%{public}@", log: self.log, type: .debug, "restore_Key(cryptomator:\(self.storageName ?? "")) restore key failed")
                }
            }
        }
    }
    
    override public func auth(onFinish: ((Bool) -> Void)?) -> Void {
        super.auth() { success in
            if success {
                if self.getKeyChain(key: "\(self.storageName ?? "")_password") != nil {
                    DispatchQueue.global().async {
                        self.generateKey(onFinish: onFinish)
                    }
                    return
                }
                DispatchQueue.main.async {
                    if let controller = UIApplication.topViewController() {
                        let passwordView = ViewControllerPasswordCryptometor()
                        passwordView.onCancel = {
                            onFinish?(false)
                        }
                        passwordView.onFinish = { pass  in
                            let _ = self.setKeyChain(key: "\(self.storageName ?? "")_password", value: pass)
                            
                            DispatchQueue.global().async {
                                self.generateKey(onFinish: onFinish)
                            }
                        }
                        controller.navigationController?.pushViewController(passwordView, animated: true)
                    }
                    else {
                        onFinish?(false)
                    }
                }
            }
            else {
                onFinish?(success)
            }
        }
    }
    
    override public func logout() {
        if let name = storageName {
            let _ = delKeyChain(key: "\(name)_password")
            let _ = delKeyChain(key: "\(name)_masterKey")
        }
        super.logout()
    }
    
    func generateMasterKey(password: String) -> [String: Any]? {
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
        let kek = SCrypt.ComputeDerivedKey(key: [UInt8](password.data(using: .utf8)!), salt: scryptSalt, cost: scryptCostParam, blockSize: scryptBlockSize, derivedKeyLength: KEY_LEN_BYTES)
        let wrappedEncryptionMasterKey = aesKeyWrap(plain: encryptionMasterKey, key: kek)
        let wrappedMacMasterKey = aesKeyWrap(plain: macMasterKey, key: kek)
        
        var verValue = UInt32(version).bigEndian
        let verData = Data(bytes: &verValue, count: MemoryLayout.size(ofValue: verValue))
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), macMasterKey, macMasterKey.count, [UInt8](verData), verData.count, &result)
        
        let jsonData: [String: Any] = ["version": version,
                                       "scryptSalt": Data(scryptSalt).base64EncodedString(),
                                       "scryptCostParam": scryptCostParam,
                                       "scryptBlockSize": scryptBlockSize,
                                       "primaryMasterKey": Data(wrappedEncryptionMasterKey).base64EncodedString(),
                                       "hmacMasterKey": Data(wrappedMacMasterKey).base64EncodedString(),
                                       "versionMac": Data(result).base64EncodedString()]
        
        return jsonData
    }

    func restoreMasterKey(password: String, versionMac: [UInt8], wrappedEncryptionMasterKey: [UInt8], wrappedMacMasterKey: [UInt8]) -> Bool {

        let kek = SCrypt.ComputeDerivedKey(key: [UInt8](password.data(using: .utf8)!), salt: scryptSalt, cost: scryptCostParam, blockSize: scryptBlockSize, derivedKeyLength: KEY_LEN_BYTES)
        encryptionMasterKey = aesKeyUnwrap(cipher: wrappedEncryptionMasterKey, key: kek)
        macMasterKey = aesKeyUnwrap(cipher: wrappedMacMasterKey, key: kek)
        
        var verValue = UInt32(version).bigEndian
        let verData = Data(bytes: &verValue, count: MemoryLayout.size(ofValue: verValue))
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), macMasterKey, macMasterKey.count, [UInt8](verData), verData.count, &result)
        
        return result.elementsEqual(versionMac)
    }

    func aesKeyWrap(plain: [UInt8], key: [UInt8]) -> [UInt8] {
        guard plain.count % 8 == 0 else {
            return []
        }
        guard [128,192,256].contains(key.count * 8) else {
            return []
        }
        var A = UInt64(0xA6A6A6A6A6A6A6A6)
        let n = plain.count / 8
        var R = [UInt64](repeating: 0, count: n+1)
        for i in 1...n {
            R[i] = UInt64(bigEndian: Array(plain[(i-1)*8..<i*8]).withUnsafeBufferPointer {
                ($0.baseAddress!.withMemoryRebound(to: UInt64.self, capacity: 1) { $0 })
                }.pointee)

        }
        
        for j in 0...5 {
            for i in 1...n {
                var r_value = R[i].bigEndian
                var Abig = A.bigEndian
                var W = [UInt8](withUnsafeBytes(of: &Abig) { $0 })
                W.append(contentsOf: [UInt8](withUnsafeBytes(of: &r_value) { $0 }))
                let B = AES(key: key, data: W)
                A = UInt64(bigEndian: Array(B[0..<8]).withUnsafeBufferPointer {
                    ($0.baseAddress!.withMemoryRebound(to: UInt64.self, capacity: 1) { $0 }).pointee
                })
                R[i] = UInt64(bigEndian: Array(B[8...]).withUnsafeBufferPointer {
                    ($0.baseAddress!.withMemoryRebound(to: UInt64.self, capacity: 1) { $0 }).pointee
                })
                let t = UInt64((n*j)+i)
                A ^= t
            }
        }
        
        var C = [UInt8](repeating: 0, count: (n+1)*8)
        var Abig = A.bigEndian
        C[0..<8] = [UInt8](withUnsafeBytes(of: &Abig) { $0 })[0..<8]
        for i in 1...n {
            var value = R[i].bigEndian
            C[i*8..<(i+1)*8] = [UInt8](withUnsafeBytes(of: &value) { $0 })[0..<8]
        }
        return C
    }

    func aesKeyUnwrap(cipher: [UInt8], key: [UInt8]) -> [UInt8] {
        guard cipher.count % 8 == 0 else {
            return []
        }
        guard [128,192,256].contains(key.count * 8) else {
            return []
        }
        let n = cipher.count / 8 - 1
        guard n > 0 else {
            return []
        }
        var A = UInt64(bigEndian: Array(cipher[0..<8]).withUnsafeBufferPointer {
            ($0.baseAddress!.withMemoryRebound(to: UInt64.self, capacity: 1) { $0 }).pointee
        })
        var R = [UInt64](repeating: 0, count: n+1)
        for i in 1...n {
            R[i] = UInt64(bigEndian: Array(cipher[i*8..<(i+1)*8]).withUnsafeBufferPointer {
                ($0.baseAddress!.withMemoryRebound(to: UInt64.self, capacity: 1) { $0 })
                }.pointee)
        }

        for j in (0...5).reversed() {
            for i in (1...n).reversed() {
                let t = UInt64((n*j)+i)
                var w_value = (A ^ t).bigEndian
                var r_value = R[i].bigEndian
                var W = [UInt8](withUnsafeBytes(of: &w_value) { $0 })
                W.append(contentsOf: [UInt8](withUnsafeBytes(of: &r_value) { $0 }))
                let B = AES(key: key, data: W, decode: true)
                A = UInt64(bigEndian: Array(B[0..<8]).withUnsafeBufferPointer {
                    ($0.baseAddress!.withMemoryRebound(to: UInt64.self, capacity: 1) { $0 }).pointee
                })
                R[i] = UInt64(bigEndian: Array(B[8...]).withUnsafeBufferPointer {
                    ($0.baseAddress!.withMemoryRebound(to: UInt64.self, capacity: 1) { $0 }).pointee
                })
            }
        }
        
        guard A == 0xA6A6A6A6A6A6A6A6 else {
            return []
        }
        
        var P = [UInt8](repeating: 0, count: n*8)
        for i in 1...n {
            var value = R[i].bigEndian
            P[(i-1)*8..<i*8] = [UInt8](withUnsafeBytes(of: &value) { $0 })[0..<8]
        }
        return P
    }

    
    func AES(key: [UInt8], data: [UInt8], decode: Bool = false) -> [UInt8] {
        guard [128,192,256].contains(key.count * 8) else {
            return []
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
            return []
        }
        return outBytes
    }
    
    func restoreMasterKeyFromJson(password: String, json: [String: Any], onFinish: @escaping (Bool)->Void) {
        guard let ver = json["version"] as? Int else {
            onFinish(false)
            return
        }
        version = ver
        guard let costParam = json["scryptCostParam"] as? Int else {
            onFinish(false)
            return
        }
        scryptCostParam = costParam
        guard let blockSize = json["scryptBlockSize"] as? Int else {
            onFinish(false)
            return
        }
        scryptBlockSize = blockSize
        guard let saltstr = json["scryptSalt"] as? String else {
            onFinish(false)
            return
        }
        guard let salt = Data(base64Encoded: saltstr) else {
            onFinish(false)
            return
        }
        scryptSalt = [UInt8](salt)
        guard let pmkstr = json["primaryMasterKey"] as? String else {
            onFinish(false)
            return
        }
        guard let pmk = Data(base64Encoded: pmkstr) else {
            onFinish(false)
            return
        }
        let wrappedEncryptionMasterKey = [UInt8](pmk)
        guard let hmkstr = json["hmacMasterKey"] as? String else {
            onFinish(false)
            return
        }
        guard let hmk = Data(base64Encoded: hmkstr) else {
            onFinish(false)
            return
        }
        let wrappedMacMasterKey = [UInt8](hmk)
        guard let verMacstr = json["versionMac"] as? String else {
            onFinish(false)
            return
        }
        guard let verMac = Data(base64Encoded: verMacstr) else {
            onFinish(false)
            return
        }
        let versionMac = [UInt8](verMac)
        
        let ret = restoreMasterKey(password: password, versionMac: versionMac, wrappedEncryptionMasterKey: wrappedEncryptionMasterKey, wrappedMacMasterKey: wrappedMacMasterKey)
        onFinish(ret)
    }
        
    func loadMasterKey(password: String, onFinish: @escaping (Bool, Bool)->Void) {
        readMasterKey() { json in
            guard let json = json else {
                onFinish(false, false)
                return
            }
            self.restoreMasterKeyFromJson(password: password, json: json) { ret in
                onFinish(true, ret)
            }
        }
    }
    
    func generateKey(onFinish: ((Bool) -> Void)?) {
        let password = getKeyChain(key: "\(self.storageName ?? "")_password") ?? ""
        loadMasterKey(password: password) { loading, success in
            if loading {
                onFinish?(success)
                return
            }
            guard let json = self.generateMasterKey(password: password) else {
                onFinish?(false)
                return
            }
            guard let dirIdHash = self.getDirHash(dirId: self.ROOT_DIR_ID) else {
                return
            }

            let group = DispatchGroup()
            var success = true
            // save masterkey file:
            group.enter()
            self.writeMasterKeyFile(json: json) { s in
                success = success && s
                group.leave()
            }

            // make root dir
            group.enter()
            self.makeParentStorage(path: [self.DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))]) { item in
                success = success && (item != nil)
                group.leave()
            }
            
            // make meta dir
            group.enter()
            self.makeParentStorage(path: [self.METADATA_DIR_NAME]) { item in
                success = success && (item != nil)
                group.leave()
            }
            
            group.notify(queue: .global()) {
                onFinish?(success)
            }
        }
    }
    
    var pDirCache = [String:(Date, [RemoteItem])]()

    func removeDirCache(dirId: String) {
        guard let dirIdHash = self.getDirHash(dirId: dirId) else {
            return
        }
        let path_str = [self.DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))].joined(separator: "\n")
        
        self.pDirCache[path_str] = nil
    }
    
    func removeDirCache(fileId: String) {
        resolveDirId(fileId: fileId) { dirId in
            guard let dirId = dirId else {
                return
            }
            guard let dirIdHash = self.getDirHash(dirId: dirId) else {
                return
            }
            let path_str = [self.DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))].joined(separator: "\n")
            
            self.pDirCache[path_str] = nil
            self.pDirIdCache[fileId] = nil
        }
    }
    
    func findParentStorage(path: ArraySlice<String>, expandDir: Bool = true, baseId: String = "", onFinish: @escaping ([RemoteItem])->Void) {
    
        let path_str = path.joined(separator: "\n")
        if expandDir && baseId == "" {
            if let (d, items) = pDirCache[path_str] {
                if Date(timeIntervalSinceNow: -5*60) > d {
                    pDirCache[path_str] = nil
                }
                else {
                    print("hit! \(path.joined(separator: "/"))->\(items)")
                    onFinish(items)
                    return
                }
            }
        }
        
        if path.count == 0 {
            guard let item = CloudFactory.shared[self.baseRootStorage]?.get(fileId: baseId == "" ? baseRootFileId : baseId) else {
                onFinish([])
                return
            }
            if item.isFolder && expandDir {
                findParentStorage(baseId: baseId == "" ? baseRootFileId : baseId) { items in
                    let ret = items.compactMap({ $0.id }).map({ CloudFactory.shared[self.baseRootStorage]?.get(fileId: $0 )}).compactMap({ $0 })
                    DispatchQueue.global().async {
                        onFinish(ret)
                    }
                }
            }
            else {
                onFinish([item])
            }
            return
        }
        self.findParentStorage(baseId: baseId) { result in
            let p = path.prefix(1).map { $0 }
            for item in result {
                guard let name = item.name, let id = item.id else {
                    continue
                }
                if name == p[0] {
                    if expandDir && baseId == "" {
                        DispatchQueue.global().async {
                            self.findParentStorage(path: path.dropFirst(), expandDir: expandDir, baseId: id) { items in
                                self.pDirCache[path_str] = (Date(), items)
                                onFinish(items)
                            }
                        }
                    }
                    else {
                        DispatchQueue.global().async {
                            self.findParentStorage(path: path.dropFirst(), expandDir: expandDir, baseId: id, onFinish: onFinish)
                        }
                    }
                    return
                }
            }
            DispatchQueue.global().async {
                onFinish([])
            }
        }
    }
    
    func findParentStorage(baseId: String = "", onFinish: @escaping ([RemoteData])->Void){
        let fixId = baseId == "" ? baseRootFileId: baseId
        CloudFactory.shared[baseRootStorage]?.list(fileId: fixId) {
            let result = CloudFactory.shared.data.listData(storage: self.baseRootStorage, parentID: fixId)
            DispatchQueue.global().async {
                onFinish(result)
            }
        }
    }

    func makeParentStorage(path: ArraySlice<String>, baseId: String = "", onFinish: ((RemoteItem?)->Void)? = nil) {
        if path.count == 0 {
            guard let item = CloudFactory.shared[self.baseRootStorage]?.get(fileId: baseId == "" ? baseRootFileId : baseId) else {
                onFinish?(nil)
                return
            }
            onFinish?(item)
            return
        }
        self.findParentStorage(baseId: baseId) { result in
            let p = path.prefix(1).map { $0 }
            for item in result {
                guard let name = item.name, let id = item.id else {
                    continue
                }
                if name == p[0] {
                    DispatchQueue.global().async {
                        self.makeParentStorage(path: path.dropFirst(), baseId: id, onFinish: onFinish)
                    }
                    return
                }
            }
            guard let item = CloudFactory.shared[self.baseRootStorage]?.get(fileId: baseId == "" ? self.baseRootFileId : baseId) else {
                onFinish?(nil)
                return
            }
            item.mkdir(newname: p[0]) { newid in
                guard let newid = newid else {
                    onFinish?(nil)
                    return
                }
                self.makeParentStorage(path: path.dropFirst(), baseId: newid, onFinish: onFinish)
            }
        }
    }

    func writeMasterKeyFile(json: [String: Any], onFinish: ((Bool) -> Void)?) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            onFinish?(false)
            return
        }
        guard let jsonStr = String(bytes: jsonData, encoding: .utf8) else {
            onFinish?(false)
            return
        }
        let _ = setKeyChain(key: "\(storageName ?? "")_masterKey", value: jsonStr)
        
        let outdata = Array(jsonStr.utf8)
        
        // generate temp file for upload
        let tempTarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
        
        guard let output = OutputStream(url: tempTarget, append: false) else {
            onFinish?(false)
            return
        }
        do {
            output.open()
            defer {
                output.close()
            }
            output.write(outdata, maxLength: outdata.count)
        }
        
        // upload masterkey file
        CloudFactory.shared[baseRootStorage]?.upload(parentId: baseRootFileId, sessionId: UUID().uuidString, uploadname: masterkey_filename, target: tempTarget) { id in
            onFinish?(id != nil)
        }
    }

    func generateFileIdSuffix(data: [UInt8]) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(data, CC_LONG(data.count), &digest)
        let base16 = digest.map({String(format: "%02X", $0)}).joined()
        return "." + base16.prefix(4)
    }
    
    func readMasterKey(onFinish: @escaping ([String: Any]?)->Void) {
        if let datastr = self.getKeyChain(key: "\(self.storageName ?? "")_masterKey") {
            guard let data = datastr.data(using: .utf8) else {
                onFinish(nil)
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) else {
                onFinish(nil)
                return
            }
            guard let jsondata = json as? [String: Any] else {
                onFinish(nil)
                return
            }
            onFinish(jsondata)
        }
        else {
            readMasterKeyFile(onFinish: onFinish)
        }
    }
    
    func readMasterKeyFile(onFinish: @escaping ([String: Any]?)->Void) {
        findParentStorage(path: [masterkey_filename]) { items in
            guard items.count >= 1 else {
                onFinish(nil)
                return
            }
            let item = items[0]
            item.read() { data in
                guard let data = data else {
                    onFinish(nil)
                    return
                }
                let _ = self.setKeyChain(key: "\(self.storageName ?? "")_masterKey", value: String(bytes: data, encoding: .utf8) ?? "")
                guard let json = try? JSONSerialization.jsonObject(with: data) else {
                    onFinish(nil)
                    return
                }
                guard let jsondata = json as? [String: Any] else {
                    onFinish(nil)
                    return
                }
                onFinish(jsondata)
            }
        }
    }

    func storeItem(parentId: String, item: RemoteItem, name: String, isFolder: Bool, dirId: String, deflatedName: String, path: String, context: NSManagedObjectContext) {
        os_log("%{public}@", log: log, type: .debug, "storeItem(cryptomator:\(storageName ?? "")) \(name)")
        
        context.perform {
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
    
    func subListChildren(dirId: String, fileId: String, path: String, onFinish: (() -> Void)?) {
        guard let dirIdHash = getDirHash(dirId: dirId) else {
            onFinish?()
            return
        }
        let group = DispatchGroup()
        // dirIDHash was used to create folder corresponding to the folder named by dirID
        // So next step is to traverse that folder [DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))]
        group.enter()
        findParentStorage(path: [DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))]) { items in
            defer {
                group.leave()
            }
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            for item in items {
           
                var encodedName: String = String(item.name)
                var t: ItemType = .broken
                var encryptedName: String = String(item.name)
                
                if ( self.version == 6) {
                    if item.name.hasSuffix(self.LONG_NAME_FILE_EXT) {
                        group.enter()
                        self.resolveMetadataFile(shortName: item.name) { orgname in
                            defer {
                                group.leave()
                            }
                            guard let orgname = orgname else {return}
                            encodedName = orgname
                        }
                    }
                } else {    // self.version == 7
                    // This only indicates parent folder is actually a folder
                    // TODO - Add shortened name support
                    // TODO - Add symlink support
                    if (    encodedName == "dir.c9r" ||
                            encodedName.hasSuffix(".c9s") ||
                            encodedName == "symlink.c9r" ) {
                        continue
                    }
                    
                    t = item.isFolder ? .directory : .regular

                } // end self.version check
                
                (t, encryptedName) = self.decodeFilename(encodedName: encodedName, t: t)
                guard t != .broken else { return}
                guard let decryptedName = self.decryptFilename(ciphertextName: encryptedName, dirId: dirId) else { return}
                
                // Skip files started with "."
                if ( decryptedName.hasPrefix(".")) {continue}
                
                if t == .directory {
                    self.storeItem(parentId: fileId, item: item, name: decryptedName, isFolder: true, dirId: dirId, deflatedName: item.name, path: path, context: backgroundContext)
                }
                else if t == .regular {

                    self.storeItem(parentId: fileId,item: item, name: decryptedName, isFolder: false, dirId: dirId, deflatedName: item.name, path: path, context: backgroundContext)
                }
                group.enter()
                backgroundContext.perform {
                    group.leave()
                }
            } // End of findParentStorage closure
        } // End of findParentStorage
        group.notify(queue: .global()) {
            onFinish?()
        }
    }
    
    override func ListChildren(fileId: String, path: String, onFinish: (() -> Void)?) {
        // fileId: dirId/deflatedName
        os_log("%{public}@", log: log, type: .debug, "ListChildren(cryptomator:\(storageName ?? "")) \(fileId)")

        resolveDirId(fileId: fileId) { id in
            guard let id = id else {
                onFinish?()
                return
            }
            self.subListChildren(dirId: id, fileId: fileId, path: path, onFinish: onFinish)
        }
    }
       
    func decodeFilename(encodedName: String, t: ItemType) -> (ItemType, String) {
        if ( self.version == 7) {
             if encodedName.hasSuffix(".c9r") {
                return (t, String(encodedName.dropLast(4)))
            } else {
                return (.broken, encodedName)
            }
        } else {
            return decodeFilename(encryptedName: encodedName)
        }
    }
    
    func decodeFilename(encryptedName: String) -> (ItemType, String) {
        
        if encryptedName.count % 8 == 0 {
            if encryptedName.allSatisfy("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=".contains) {
                return (.regular, encryptedName)
            }
            return (.broken, encryptedName)
        }
        if encryptedName.count % 8 == 1 {
            if encryptedName.hasPrefix("0") {
                let encodedName = encryptedName.dropFirst()
                if encodedName.allSatisfy("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=".contains) {
                    return (.directory, String(encodedName))
                }
            }
            return (.broken, encryptedName)
        }
        if encryptedName.count % 8 == 2 {
            if encryptedName.hasPrefix("1S") {
                let encodedName = encryptedName.dropFirst(2)
                if encodedName.allSatisfy("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=".contains) {
                    return (.symlink, String(encodedName))
                }
            }
            return (.broken, encryptedName)
        }
        return (.broken, encryptedName)
    }
    
    func resolveMetadataFile(shortName: String, onFinish: @escaping (String?)->Void) {
        findParentStorage(path: [METADATA_DIR_NAME, String(shortName.prefix(2)), String(shortName.dropFirst(2).prefix(2))]) { items in
            guard items.count > 0 else {
                onFinish(nil)
                return
            }
            let item = items[0]
            item.read() { data in
                guard let data = data else {
                    onFinish(nil)
                    return
                }
                onFinish(String(bytes: data, encoding: .utf8))
            }
        }
    }

    func uploadMetadataFile(shortName: String, orgName: String, onFinish: ((Bool)->Void)?) {
        guard let s = CloudFactory.shared[baseRootStorage] as? RemoteStorageBase else {
            onFinish?(false)
            return
        }
        makeParentStorage(path: [METADATA_DIR_NAME, String(shortName.prefix(2)), String(shortName.dropFirst(2).prefix(2))]) { item in
            guard let item = item else {
                onFinish?(false)
                return
            }

            DispatchQueue.global().async {
                let target = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
                guard let output = OutputStream(url: target, append: false) else {
                    onFinish?(false)
                    return
                }
                do {
                    output.open()
                    defer {
                        output.close()
                    }
                    let content = Array(orgName.utf8)
                    output.write(content, maxLength: content.count)
                }
                
                s.upload(parentId: item.id, sessionId: UUID().uuidString, uploadname: shortName, target: target) { newBaseId in
                    onFinish?(newBaseId != nil)
                }
            }
        }
    }

    func deflate(longFileName: String) -> String? {
        guard let longFileNameBytes = longFileName.data(using: .utf8) else {
            return nil
        }
        
        let length = Int(CC_SHA1_DIGEST_LENGTH)
        var digest = [UInt8](repeating: 0, count: length)
        let _ = longFileNameBytes.withUnsafeBytes { CC_SHA1($0.baseAddress!, CC_LONG(longFileNameBytes.count), &digest) }
        guard let encoded = BASE32.base32encode(input: Data(digest)) else {
            return nil
        }
        return encoded + LONG_NAME_FILE_EXT
    }
    
    func getDirHash(dirId: String) -> String? { // Encrypt UUID
        guard let inputdata = dirId.data(using: .utf8) else {
            return nil
        }
        let cleartextBytes = [UInt8](inputdata)
        guard let encryptedBytes = AES_SIV.encrypt(ctrKey: encryptionMasterKey, macKey: macMasterKey, plaintext: cleartextBytes) else {
            return nil
        }
        
        let length = Int(CC_SHA1_DIGEST_LENGTH)
        var digest = [UInt8](repeating: 0, count: length)
        let _ = encryptedBytes.withUnsafeBytes { CC_SHA1($0.baseAddress!, CC_LONG(encryptedBytes.count), &digest) }
        if self.version == 6 {
            return BASE32.base32encode(input: Data(digest))
        } else {
            // TODO - Verify in V7, Directory name is still encoded with Base32?
            return BASE32.base32encode(input: Data(digest))
//            return BASE64.base64urlencode(input: Data(digest))
          
        }
    }
    
    func encryptFilename(cleartextName: String, dirId: String) -> String? {
        guard let inputdata = cleartextName.data(using: .utf8) else {
            return nil
        }
        let cleartextBytes = [UInt8](inputdata)
        guard let associatedData = dirId.data(using: .utf8) else {
            return nil
        }
        let associatedBytes = [UInt8](associatedData)

        guard let encryptedBytes = AES_SIV.encrypt(ctrKey: encryptionMasterKey, macKey: macMasterKey, plaintext: cleartextBytes, associatedData: [associatedBytes]) else {
            return nil
        }
        
        return BASE32.base32encode(input: Data(encryptedBytes))
    }
    
    func decryptFilename(ciphertextName: String, dirId: String) -> String? {
        
        guard let associatedData = dirId.data(using: .utf8) else { return nil}
        let associatedBytes = [UInt8](associatedData)
        
        guard let encryptedBytes = self.version == 6 ? BASE32.base32decode(input: ciphertextName) : BASE64.base64urldecode(input: ciphertextName) else { return nil }
        guard let cleartextBytes = AES_SIV.decrypt(ctrKey: encryptionMasterKey, macKey: macMasterKey, ciphertext: [UInt8](encryptedBytes), associatedData: [associatedBytes]) else { return nil}

        return String(bytes: cleartextBytes, encoding: .utf8)
    }
    
    public override func getRaw(fileId: String) -> RemoteItem? {
        return CryptomatorRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) -> RemoteItem? {
        return CryptomatorRemoteItem(path: path)
    }
    
    func resolveDirUUIDFile(dirIdHash: String, deflateDirId: String, onFinish: @escaping (String?)->Void) {
        findParentStorage(path: [self.DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30)), deflateDirId]) { items in
            for item in items {
                if item.name != self.V7_DIR {continue}
                item.read() { data in
                    guard let data = data else {
                        onFinish(nil)
                        return
                    }
                    onFinish(String(bytes: data, encoding: .utf8))
                    return
                }
            }
            onFinish(nil)
        }
    }
    
    func resolveUUIDFromItem( item: RemoteItem, onFinish: @escaping (String?)->Void) {
        var id: String? = nil
        var uuidItem: RemoteItem = item
        let uuidGroup = DispatchGroup()
        let uuidSem = DispatchSemaphore(value: 0)

        if ( self.version == 7) {
            let deflateDirID = item.name
            let array = item.id.components(separatedBy: "/")
            uuidGroup.enter()
            findParentStorage(path: [array[1], array[2], array[3], deflateDirID]) { items in
                defer {
                    uuidGroup.leave()
                    uuidSem.signal()
                }
                for item in items {
                    if item.name != self.V7_DIR {continue}
                    uuidItem = item
                    return
                }
            }
        } else {
            uuidSem.signal()
        }
        
        uuidGroup.enter()
        uuidSem.wait()
        uuidItem.read() { data in
            defer {
                uuidGroup.leave()
                
            }
            guard let data = data else {return}
            guard let tempid = String(bytes: data, encoding: .utf8) else { return}
            id = tempid
        }
        
        uuidGroup.notify(queue: .global()) {
            onFinish(id)
        }
    }
    

    var pDirIdCache = [String: (Date, String)]()
    /*
     Use parent folder's HASH to access/traverse storage, match file name specificied by folder's name in BASE32/64, and then read this folder's UUID in the matching file.
     In V6, the folder UUID is stored in item.id; in V7, the folder UUID is stored in item.id/dir.c9r. https://github.com/cryptomator/cryptofs/issues/64
  
     Example below -
     fileId = "bb26ccca-3726-4c1c-b4eb-d58802d03d66/0ALUAELRDZQI3W3UWPE5JOWMJJQ6PRLEHRAJJDDU56M======"
     Parent folder UUID - bb26ccca-3726-4c1c-b4eb-d58802d03d66
     File containing this folder's UUID - 0ALUAELRDZQI3W3UWPE5JOWMJJQ6PRLEHRAJJDDU56M======
     
     item.id = "/d/S7/3BUXDLCW4X4IOZBQ4X4BNOLJ273A4T/0ALUAELRDZQI3W3UWPE5JOWMJJQ6PRLEHRAJJDDU56M======"
     item.path = "rclone:/d/S7/3BUXDLCW4X4IOZBQ4X4BNOLJ273A4T/0ALUAELRDZQI3W3UWPE5JOWMJJQ6PRLEHRAJJDDU56M======"
     */
    func resolveDirId(fileId: String, onFinish: ((String?)->Void)?) {
        os_log("%{public}@", log: log, type: .debug, "resolveFileId(cryptomator:\(storageName ?? "")) \(fileId)")
        let fixFileId = (fileId == "") ? "/" : fileId
        let array = fixFileId.components(separatedBy: "/")
        let parentDirId = array[0]      // Parent UUID
        let deflateDirId = array[1]     // folder's name in BASE32/64

        if deflateDirId == "" {
            onFinish?("")
            return
        }

        if let (d, id) = pDirIdCache[fileId] {
            if Date(timeIntervalSinceNow: -5*60) > d {
                pDirIdCache[fileId] = nil
            }
            else {
                print("hit! \(fileId)->\(id)")
                onFinish?(id)
                return
            }
        }
        
        guard let dirIdHash = getDirHash(dirId: parentDirId) else {
            onFinish?(nil)
            return
        }

        var id: String? = nil
        var uuidItem: RemoteItem? = nil
        
        let group = DispatchGroup()
        let sem = DispatchSemaphore.init(value: 0)
        group.enter()
        findParentStorage(path: [DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))]) { items in

            /* This for loop runs as a concurrent task in global queue */
            for item in items {
                if item.name != deflateDirId { continue }
                /*
                if (self.version == 6) {
                    uuidItem = item
                    sem.signal()
                } else {
                    let deflateDirID = item.name
                    let array = item.id.components(separatedBy: "/")

                    group.enter()
                    self.findParentStorage(path: [array[1], array[2], array[3], deflateDirID]) { items in
                        for item in items {
                            if item.name != self.V7_DIR {continue}
                            uuidItem = item
                            
                            sem.signal()
                            group.leave()
                            return
                        }
                    }
                }*/

                
                group.enter()
                self.resolveUUIDFromItem(item: item) { dirUUID in
                    id = dirUUID
                    group.leave()
                }
                break
            } // end item in items loop
            
            group.leave()
        } //End of findParentStorage
        
        /*
        group.enter()
        sem.wait()      // Wait till matching item is found.
        uuidItem!.read() { data in
            guard let data = data else { return}
            guard let tempid = String(bytes: data, encoding: .utf8) else { return}
            id = tempid
            group.leave()
        }*/

        group.notify( queue: .global()) {
            defer { onFinish?(id)}
 
            guard let id = id else { return}
            os_log("%{public}@", log: self.log, type: .debug, "resolveFileId(cryptomator:\(self.storageName ?? "")) \(fileId)->\(String(describing: id))")
            self.pDirIdCache[fileId] = (Date(), id)
        }
    }
    

    public override func makeFolder(parentId: String, parentPath: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "makeFolder(\(String(describing: type(of: self))):\(storageName ?? "") \(parentId)(\(parentPath)) \(newname)")

        guard let s = CloudFactory.shared[baseRootStorage] as? RemoteStorageBase else {
            onFinish?(nil)
            return
        }

        resolveDirId(fileId: parentId) { parentDirId in // Get parent folder UUID from parent encrypted filename
            guard let parentDirId = parentDirId else {
                onFinish?(nil)
                return
            }
            guard let parentIdHash = self.getDirHash(dirId: parentDirId) else {
                onFinish?(nil)
                return
            }
            self.findParentStorage(path: [self.DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30))], expandDir: false) { items in
                guard items.count > 0 else {
                    onFinish?(nil)
                    return
                }
                let baseItem = items[0]
                
                // generate encrypted BASE name from clear folder name and its parent folder UUID
                guard let encFilename = self.encryptFilename(cleartextName: newname, dirId: parentDirId) else {
                    onFinish?(nil)
                    return
                }
                let encDirname = "0" + encFilename
                // generate UUID for the folder, encrypt the UUID, and use the UUID to create folder in storage.
                // Later on, as long as you get the UUID from encDirname content, you can locate the folder and then traverse all files in it.
                let newDirId = UUID().uuidString.lowercased()
                guard let dirIdHash = self.getDirHash(dirId: newDirId) else {
                    onFinish?(nil)
                    return
                }
                // make directory for encrypted UUID
                self.makeParentStorage(path: [self.DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))]) { item in
                    guard item != nil else {
                        onFinish?(nil)
                        return
                    }
                }
                
                // if needed filename shorten
                let deflatedName: String?
                let group = DispatchGroup()
                var metadataUploadDone = true
                if encFilename.count <= 129 {
                    deflatedName = nil
                }
                else {
                    metadataUploadDone = false
                    deflatedName = self.deflate(longFileName: encDirname)
                    group.enter()
                    self.uploadMetadataFile(shortName: deflatedName!, orgName: encDirname) { success in
                        metadataUploadDone = success
                        group.leave()
                    }
                }
                
                group.notify(queue: .global()) {
                    guard metadataUploadDone else {
                        onFinish?(nil)
                        return
                    }
                    
                    let target = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
                    guard let output = OutputStream(url: target, append: false) else {
                        onFinish?(nil)
                        return
                    }
                    do {
                        output.open()
                        defer {
                            output.close()
                        }
                        let content = Array(newDirId.utf8)
                        output.write(content, maxLength: content.count)
                    }
                    
                    // Upload new folder UUID as content
                    s.upload(parentId: baseItem.id, sessionId: UUID().uuidString, uploadname: deflatedName ?? encDirname, target: target) { newBaseId in
                        guard let newBaseId = newBaseId else {
                            onFinish?(nil)
                            return
                        }
                        
                        CloudFactory.shared.data.persistentContainer.performBackgroundTask {
                            context in
                            var ret: String?
                            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, self.baseRootStorage)
                            if let result = try? context.fetch(fetchRequest), let items = result as? [RemoteData] {
                                if let item = items.first {
                                    let newid = "\(parentDirId)/\(deflatedName ?? encDirname)"
                                    let newcdate = item.cdate
                                    let newmdate = item.mdate
                                    
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
                                    newitem.folder = true
                                    newitem.size = 0
                                    newitem.hashstr = ""
                                    newitem.parent = parentId
                                    if parentId == "" {
                                        newitem.path = "\(self.storageName ?? ""):/\(newname)"
                                    }
                                    else {
                                        newitem.path = "\(parentPath)/\(newname)"
                                    }
                                    ret = newid
                                    try? context.save()
                                }
                            }
                            
                            DispatchQueue.global().async {
                                onFinish?(ret)
                            }
                        }
                    }
                }
            }
        }
    }
    
    override func deleteItem(fileId: String, callCount: Int = 0, onFinish: ((Bool) -> Void)?) {
        guard fileId != "" else {
            onFinish?(false)
            return
        }

        os_log("%{public}@", log: log, type: .debug, "deleteItem(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId)")

        guard let s = CloudFactory.shared[baseRootStorage] as? RemoteStorageBase else {
            onFinish?(false)
            return
        }
        
        let array = fileId.components(separatedBy: "/")
        let parentDirId = array[0]
        let deflateId = array[1]

        guard let parentIdHash = getDirHash(dirId: parentDirId) else {
            onFinish?(false)
            return
        }

        var itemType: ItemType = .broken
        let group = DispatchGroup()
        
        if deflateId.hasSuffix(LONG_NAME_FILE_EXT) {
            // long name
            group.enter()
            resolveMetadataFile(shortName: deflateId) { orgname in
                defer {
                    group.leave()
                }
                guard let orgname = orgname else {
                    onFinish?(false)
                    return
                }
                let (t, encryptedName) = self.decodeFilename(encryptedName: orgname)
                itemType = t
            }
        }
        else {
            let (t, encryptedName) = decodeFilename(encryptedName: deflateId)
            itemType = t
        }

        group.notify(queue: .global()) {
            guard itemType != .broken else {
                onFinish?(false)
                return
            }
            
            if itemType == .directory {
                // delete folder and its contents
                
                // first, delete folder items
                self.resolveDirId(fileId: fileId) { dirId in
                    guard let dirId = dirId else {
                        onFinish?(false)
                        return
                    }
                    guard let dirIdHash = self.getDirHash(dirId: dirId) else {
                        onFinish?(false)
                        return
                    }
                    var ret = true
                    let group2 = DispatchGroup()
                    // search items
                    group2.enter()
                    self.findParentStorage(path: [self.DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))]) { items in
                        defer {
                            group2.leave()
                        }
                        for item in items {
                            let shortName = item.name
                            if shortName.hasSuffix(self.LONG_NAME_FILE_EXT) {
                                // long name
                                group2.enter()
                                self.resolveMetadataFile(shortName: shortName) { orgname in
                                    defer {
                                        group2.leave()
                                    }
                                    guard let orgname = orgname else {
                                        return
                                    }
                                    let (t, encryptedName) = self.decodeFilename(encryptedName: orgname)
                                    guard t != .broken else {
                                        return
                                    }
                                    if t == .directory {
                                        let id = "\(dirId)/\(shortName)"
                                        group2.enter()
                                        self.deleteItem(fileId: id) { success in
                                            defer {
                                                group2.leave()
                                            }
                                            ret = ret && success
                                        }
                                    }
                                    else {
                                        // remove item and metainfo
                                        let id = "\(dirId)/\(shortName)"
                                        group2.enter()
                                        s.deleteItem(fileId: item.id) { success in
                                            defer {
                                                group2.leave()
                                            }
                                            guard success else {
                                                ret = false
                                                return
                                            }
                                            group2.enter()
                                            self.findParentStorage(path: [self.METADATA_DIR_NAME, String(shortName.prefix(2)), String(shortName.dropFirst(2).prefix(2))]) { metaItems in
                                                defer {
                                                    group2.leave()
                                                }
                                                for metaItem in metaItems {
                                                    if metaItem.name == shortName {
                                                        group2.enter()
                                                        s.deleteItem(fileId: metaItem.id) { success2 in
                                                            defer {
                                                                group2.leave()
                                                            }
                                                            guard success2 else {
                                                                ret = false
                                                                return
                                                            }
                                                            CloudFactory.shared.data.persistentContainer.performBackgroundTask { context in
                                                                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                                                                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName!)
                                                                if let result = try? context.fetch(fetchRequest), let items = result as? [RemoteData] {
                                                                    for item in items {
                                                                        context.delete(item)
                                                                    }
                                                                    try? context.save()
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            else {
                                let (t, encryptedName) = self.decodeFilename(encryptedName: shortName)
                                guard t != .broken else {
                                    return
                                }
                                if t == .directory {
                                    let id = "\(dirId)/\(shortName)"
                                    group2.enter()
                                    self.deleteItem(fileId: id) { success in
                                        defer {
                                            group2.leave()
                                        }
                                        ret = ret && success
                                    }
                                }
                                else {
                                    let id = "\(dirId)/\(shortName)"
                                    group2.enter()
                                    s.deleteItem(fileId: item.id) { success in
                                        defer {
                                            group2.leave()
                                        }
                                        guard success else {
                                            ret = false
                                            return
                                        }
                                        CloudFactory.shared.data.persistentContainer.performBackgroundTask { context in
                                            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                                            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName!)
                                            if let result = try? context.fetch(fetchRequest), let items = result as? [RemoteData] {
                                                for item in items {
                                                    context.delete(item)
                                                }
                                                try? context.save()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    group2.notify(queue: .global()) {
                        guard ret else {
                            onFinish?(ret)
                            return
                        }
                        let group3 = DispatchGroup()
                        group3.enter()
                        self.findParentStorage(path: [self.DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))], expandDir: false) { items in
                            defer {
                                group3.leave()
                            }
                            guard items.count > 0 else {
                                ret = false
                                return
                            }
                            let item = items[0]
                            group3.enter()
                            s.delete(fileId: item.id) { success in
                                defer {
                                    group3.leave()
                                }
                                guard success else {
                                    ret = false
                                    return
                                }
                                group3.enter()
                                self.findParentStorage(path: [self.DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30))]) { items in
                                    defer {
                                        group3.leave()
                                    }
                                    for item in items {
                                        if item.name == deflateId {
                                            group3.enter()
                                            s.deleteItem(fileId: item.id) { success in
                                                defer {
                                                    group3.leave()
                                                }
                                                guard success else {
                                                    ret = false
                                                    return
                                                }
                                                if item.name.hasSuffix(self.LONG_NAME_FILE_EXT) {
                                                    let shortName = item.name
                                                    group3.enter()
                                                    self.findParentStorage(path: [self.METADATA_DIR_NAME, String(shortName.prefix(2)), String(shortName.dropFirst(2).prefix(2))]) { metaItems in
                                                        defer {
                                                            group3.leave()
                                                        }
                                                        for metaItem in metaItems {
                                                            if metaItem.name == shortName {
                                                                group3.enter()
                                                                s.deleteItem(fileId: metaItem.id) { success2 in
                                                                    defer {
                                                                        group3.leave()
                                                                    }
                                                                    guard success2 else {
                                                                        ret = false
                                                                        return
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        group3.notify(queue: .global()) {
                            DispatchQueue.global().async {
                                self.removeDirCache(fileId: fileId)
                            }
                            
                            CloudFactory.shared.data.persistentContainer.performBackgroundTask { context in
                                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName!)
                                if let result = try? context.fetch(fetchRequest), let items = result as? [RemoteData] {
                                    for item in items {
                                        context.delete(item)
                                    }
                                    try? context.save()
                                }
                                DispatchQueue.global().async {
                                    onFinish?(ret)
                                }
                            }
                        }
                    }
                }
            }
            else {
                self.findParentStorage(path: [self.DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30))]) { items in
                    let group2 = DispatchGroup()
                    var going = true
                    for item in items {
                        if item.name == deflateId {
                            group2.enter()
                            s.deleteItem(fileId: item.id) { success in
                                defer {
                                    group2.leave()
                                }
                                guard success else {
                                    going = false
                                    return
                                }
                                if item.name.hasSuffix(self.LONG_NAME_FILE_EXT) {
                                    let shortName = item.name
                                    group2.enter()
                                    self.findParentStorage(path: [self.METADATA_DIR_NAME, String(shortName.prefix(2)), String(shortName.dropFirst(2).prefix(2))]) { metaItems in
                                        defer {
                                            group2.leave()
                                        }
                                        for metaItem in metaItems {
                                            if metaItem.name == shortName {
                                                group2.enter()
                                                s.deleteItem(fileId: metaItem.id) { success2 in
                                                    defer {
                                                        group2.leave()
                                                    }
                                                    guard success2 else {
                                                        going = false
                                                        return
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    group2.notify(queue: .global()) {
                        guard going else {
                            onFinish?(false)
                            return
                        }
                        self.removeDirCache(dirId: parentDirId)
                        
                        CloudFactory.shared.data.persistentContainer.performBackgroundTask { context in
                            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName!)
                            if let result = try? context.fetch(fetchRequest), let items = result as? [RemoteData] {
                                for item in items {
                                    context.delete(item)
                                }
                                try? context.save()
                            }
                            
                            DispatchQueue.global().async {
                                onFinish?(true)
                            }
                        }
                    }
                }
            }
        }
    }
    
    override func renameItem(fileId: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        let newname = newname.precomposedStringWithCanonicalMapping
        guard fileId != "" else {
            onFinish?(nil)
            return
        }
        
        os_log("%{public}@", log: log, type: .debug, "renameItem(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId)->\(newname)")
        
        guard let s = CloudFactory.shared[baseRootStorage] as? RemoteStorageBase else {
            onFinish?(nil)
            return
        }
        
        let array = fileId.components(separatedBy: "/")
        let parentDirId = array[0]
        let deflateId = array[1]
        
        guard let parentIdHash = getDirHash(dirId: parentDirId) else {
            onFinish?(nil)
            return
        }

        guard let c = CloudFactory.shared[storageName!]?.get(fileId: fileId) else {
            onFinish?(nil)
            return
        }
        
        var parentPath1: String?
        let parentId = c.parent
        if parentId != "" {
            if Thread.isMainThread {
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, self.storageName ?? "")
                if let result = try? viewContext.fetch(fetchRequest) {
                    if let items = result as? [RemoteData] {
                        parentPath1 = items.first?.path ?? ""
                    }
                }
            }
            else {
                DispatchQueue.main.sync {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, self.storageName ?? "")
                    if let result = try? viewContext.fetch(fetchRequest) {
                        if let items = result as? [RemoteData] {
                            parentPath1 = items.first?.path ?? ""
                        }
                    }
                }
            }
        }
        guard let parentPath = parentPath1 else {
            DispatchQueue.global().async {
                onFinish?(nil)
            }
            return
        }
        
        var going = true
        let group2 = DispatchGroup()
        guard let ename = self.encryptFilename(cleartextName: newname, dirId: parentDirId) else {
            onFinish?(nil)
            return
        }
        let encFilename = c.isFolder ? "0"+ename : ename
        let deflatedName: String?
        if encFilename.count <= 129 {
            deflatedName = nil
        }
        else {
            deflatedName = self.deflate(longFileName: encFilename)
            group2.enter()
            self.uploadMetadataFile(shortName: deflatedName!, orgName: encFilename) { success in
                going = going && success
                group2.leave()
            }
        }

        group2.notify(queue: .global()) {
            guard going else {
                return
            }
            let group3 = DispatchGroup()
            group3.enter()
            self.findParentStorage(path: [self.DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflateId], expandDir: false) { items in
                defer {
                    group3.leave()
                }
                guard items.count > 0 else {
                    going = false
                    return
                }
                let item = items[0]
                group3.enter()
                s.rename(fileId: item.id, newname: deflatedName ?? encFilename) { newId in
                    defer {
                        group3.leave()
                    }
                    guard newId != nil else {
                        going = false
                        return
                    }
                    
                    // if item had longname, remove old metadata
                    if deflateId.hasSuffix(self.LONG_NAME_FILE_EXT) {
                        // long name
                        group3.enter()
                        self.findParentStorage(path: [self.METADATA_DIR_NAME, String(deflateId.prefix(2)), String(deflateId.dropFirst(2).prefix(2))]) { metaItems in
                            defer {
                                group3.leave()
                            }
                            for metaItem in metaItems {
                                if metaItem.name == deflateId {
                                    group3.enter()
                                    s.deleteItem(fileId: metaItem.id) { success in
                                        defer {
                                            group3.leave()
                                        }
                                        guard success else {
                                            going = false
                                            return
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            group3.notify(queue: .main) {
                guard going else {
                    DispatchQueue.global().async {
                        onFinish?(nil)
                    }
                    return
                }

                self.removeDirCache(dirId: parentDirId)
                
                CloudFactory.shared.data.persistentContainer.performBackgroundTask { context in
                    var ret: String? = nil
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                    if let result = try? context.fetch(fetchRequest), let items = result as? [RemoteData] {
                        if let item = items.first {
                            let newid = "\(parentDirId)/\(deflatedName ?? encFilename)"
                            let newname = newname
                            let newcdate = item.cdate
                            let newmdate = item.mdate
                            let newfolder = item.folder
                            let newsize = item.size
                            
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
                                newitem.path = "\(parentPath)/\(newname)"
                            }
                            ret = newid
                        }
                        if ret != nil {
                            for item in items {
                                context.delete(item)
                            }
                        }
                        try? context.save()
                    }
                    
                    DispatchQueue.global().async {
                        onFinish?(ret)
                    }
                }
            }
        }
    }

    
    override func changeTime(fileId: String, newdate: Date, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        guard fileId != "" else {
            onFinish?(nil)
            return
        }
 
        os_log("%{public}@", log: log, type: .debug, "changeTime(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId)->\(newdate)")
        
        let array = fileId.components(separatedBy: "/")
        let parentDirId = array[0]
        let deflateId = array[1]
        
        guard let parentIdHash = getDirHash(dirId: parentDirId) else {
            onFinish?(nil)
            return
        }

        findParentStorage(path: [DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflateId], expandDir: false) { items in
            guard items.count > 0 else {
                onFinish?(nil)
                return
            }
            let item = items[0]
            item.changetime(newdate: newdate) { id in
                guard let id = id else {
                    onFinish?(nil)
                    return
                }
                
                CloudFactory.shared.data.persistentContainer.performBackgroundTask { context in
                    var newcdate: Date? = nil
                    var newmdate: Date? = nil
                    var newId: String? = nil

                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.baseRootStorage)
                    if let result = try? context.fetch(fetchRequest), let items = result as? [RemoteData] {
                        if let baseItem = items.first {
                            newcdate = baseItem.cdate
                            newmdate = baseItem.mdate
                        }
                    }
                    let fetchRequest1 = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest1.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName!)
                    if let result = try? context.fetch(fetchRequest1), let items1 = result as? [RemoteData] {
                        if let pitem = items1.first {
                            pitem.cdate = newcdate
                            pitem.mdate = newmdate
                            try? context.save()
                            
                            newId = pitem.id
                        }

                        DispatchQueue.global().async {
                            onFinish?(newId)
                        }
                    }
                }
            }
        }
    }

    override func moveItem(fileId: String, fromParentId: String, toParentId: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        
        guard fileId != "" else {
            onFinish?(nil)
            return
        }

        let fixFromParentId = fromParentId == "" ? "/" : fromParentId
        let fixToParentId = toParentId == "" ? "/" : toParentId

        os_log("%{public}@", log: log, type: .debug, "moveItem(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId) \(fixFromParentId)->\(fixToParentId)")
        
        guard fixFromParentId != fixToParentId else {
            onFinish?(nil)
            return
        }
        
        // first, find name for moving item
        var orgname1: String? = nil
        var isFolder = false
        if Thread.isMainThread {
            let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
            if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                if let item = items.first {
                    orgname1 = item.name
                    isFolder = item.folder
                }
            }
        }
        else {
            DispatchQueue.main.sync {
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                    if let item = items.first {
                        orgname1 = item.name
                        isFolder = item.folder
                    }
                }
            }
        }
        
        guard let orgname = orgname1 else {
            onFinish?(nil)
            return
        }
        
        let array = fileId.components(separatedBy: "/")
        let parentDirId = array[0]
        let deflateId = array[1]
        
        guard let parentIdHash = self.getDirHash(dirId: parentDirId) else {
            onFinish?(nil)
            return
        }
        
        self.resolveDirId(fileId: fixToParentId) { toParentDirId in
            guard let toParentDirId = toParentDirId else {
                onFinish?(nil)
                return
            }
            guard let toParentIdHash = self.getDirHash(dirId: toParentDirId) else {
                onFinish?(nil)
                return
            }
            
            // find base item for toDir
            self.findParentStorage(path: [self.DATA_DIR_NAME, String(toParentIdHash.prefix(2)), String(toParentIdHash.suffix(30))], expandDir: false) { toItems in
                guard toItems.count > 0 else {
                    onFinish?(nil)
                    return
                }
                let toItem = toItems[0] //baseItem for toDir
                
                // find base item for moving item
                self.findParentStorage(path: [self.DATA_DIR_NAME, String(parentIdHash.prefix(2)), String(parentIdHash.suffix(30)), deflateId], expandDir: false) { items in
                    guard items.count > 0 else {
                        onFinish?(nil)
                        return
                    }
                    let item = items[0] //baseItem for moving
                    
                    // move base item to toDir
                    item.move(toParentId: toItem.id) { newBaseId in
                        guard let newBaseId = newBaseId else {
                            onFinish?(nil)
                            return
                        }
                        
                        // parent dirid is changed, encrypted name will be changed
                        guard let encFilename = self.encryptFilename(cleartextName: orgname, dirId: toParentDirId) else {
                            onFinish?(nil)
                            return
                        }
                        let uploadname = isFolder ? "0"+encFilename : encFilename
                        let deflatedName: String?
                        var done = false
                        let group2 = DispatchGroup()
                        if encFilename.count <= 129 {
                            deflatedName = nil
                            done = true
                        }
                        else {
                            // long name
                            deflatedName = self.deflate(longFileName: uploadname)
                            group2.enter()
                            self.uploadMetadataFile(shortName: deflatedName!, orgName: uploadname) { success in
                                done = success
                                group2.leave()
                            }
                        }
                        
                        group2.notify(queue: .global()) {
                            guard done else {
                                onFinish?(nil)
                                return
                            }
                            
                            // rename to new encrypted name
                            guard let newBaseItem = CloudFactory.shared[self.baseRootStorage]?.get(fileId: newBaseId == "" ? self.baseRootFileId : newBaseId) else {
                                onFinish?(nil)
                                return
                            }
                            newBaseItem.rename(newname: deflatedName ?? uploadname) { nbItem in
                                guard nbItem != nil else {
                                    onFinish?(nil)
                                    return
                                }
                                
                                // move done successfully
                                self.removeDirCache(fileId: fromParentId)
                                self.removeDirCache(fileId: toParentId)

                                // if old id is longname, remove old matadata
                                if deflateId.hasSuffix(self.LONG_NAME_FILE_EXT) {
                                    guard let s = CloudFactory.shared[self.baseRootStorage] as? RemoteStorageBase else {
                                        return
                                    }

                                    self.findParentStorage(path: [self.METADATA_DIR_NAME, String(deflateId.prefix(2)), String(deflateId.dropFirst(2).prefix(2))]) { metaItems in
                                        for metaItem in metaItems {
                                            if metaItem.name == deflateId {
                                                s.deleteItem(fileId: metaItem.id) { success2 in
                                                }
                                                return
                                            }
                                        }
                                    }
                                }
                                
                                // register record
                                CloudFactory.shared.data.persistentContainer.performBackgroundTask { context in
                                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                                    if let result = try? context.fetch(fetchRequest), let items = result as? [RemoteData] {
                                        if let item = items.first {
                                            item.id = "\(toParentDirId)/\(deflatedName ?? uploadname)"
                                            item.cdate = newBaseItem.cDate
                                            item.mdate = newBaseItem.mDate
                                            item.parent = toParentId
                                            if toParentId == "" {
                                                item.path = "\(self.storageName ?? ""):/\(item.name ?? "")"
                                            }
                                            else {
                                                item.path = "\(toItem.path)/\(item.name ?? "")"
                                            }
                                            try? context.save()
                                            let newId = item.id
                                            
                                            DispatchQueue.global().async {
                                                onFinish?(newId)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    override func uploadFile(parentId: String, sessionId: String, uploadname: String, target: URL, onFinish: ((String?)->Void)?) {
        let uploadname = uploadname.precomposedStringWithCanonicalMapping
        os_log("%{public}@", log: log, type: .debug, "uploadFile(\(String(describing: type(of: self))):\(storageName ?? "") \(uploadname)->\(parentId) \(target)")
        
        guard let s = CloudFactory.shared[baseRootStorage] as? RemoteStorageBase else {
            try? FileManager.default.removeItem(at: target)
            onFinish?(nil)
            return
        }
        guard let b = CloudFactory.shared[storageName!]?.get(fileId: parentId) else {
            try? FileManager.default.removeItem(at: target)
            onFinish?(nil)
            return
        }
        let parentPath = b.path

        resolveDirId(fileId: parentId) { dirId in
            guard let dirId = dirId else {
                try? FileManager.default.removeItem(at: target)
                onFinish?(nil)
                return
            }
            guard let encFilename = self.encryptFilename(cleartextName: uploadname, dirId: dirId) else {
                try? FileManager.default.removeItem(at: target)
                onFinish?(nil)
                return
            }
            let deflatedName: String?
            let group = DispatchGroup()
            var metadataUploadDone = true
            if encFilename.count <= 129 {
                deflatedName = nil
            }
            else {
                metadataUploadDone = false
                deflatedName = self.deflate(longFileName: encFilename)
                group.enter()
                self.uploadMetadataFile(shortName: deflatedName!, orgName: encFilename) { success in
                    metadataUploadDone = success
                    group.leave()
                }
            }
            guard let dirIdHash = self.getDirHash(dirId: dirId) else {
                try? FileManager.default.removeItem(at: target)
                onFinish?(nil)
                return
            }
            self.makeParentStorage(path: [self.DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))]) { baseItem in
                guard let baseItem = baseItem else {
                    try? FileManager.default.removeItem(at: target)
                    onFinish?(nil)
                    return
                }
                
                group.notify(queue: .global()) {
                    guard metadataUploadDone else {
                        try? FileManager.default.removeItem(at: target)
                        onFinish?(nil)
                        return
                    }
                    if let crypttarget = self.processFile(target: target) {
                        s.upload(parentId: baseItem.id, sessionId: sessionId, uploadname: deflatedName ?? encFilename, target: crypttarget) { newBaseId in
                            guard let newBaseId = newBaseId else {
                                try? FileManager.default.removeItem(at: target)
                                onFinish?(nil)
                                return
                            }
                            self.removeDirCache(fileId: parentId)
                            
                            CloudFactory.shared.data.persistentContainer.performBackgroundTask { context in
                                var ret: String? = nil
                                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, self.baseRootStorage)
                                if let result = try? context.fetch(fetchRequest), let items = result as? [RemoteData] {
                                    if let item = items.first {
                                        let newid = "\(dirId)/\(deflatedName ?? encFilename)"
                                        let newname = uploadname
                                        let newcdate = item.cdate
                                        let newmdate = item.mdate
                                        let newfolder = item.folder
                                        let newsize = self.ConvertDecryptSize(size: item.size)

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
                                            newitem.path = "\(parentPath)/\(newname)"
                                        }
                                        try? context.save()
                                        ret = newid
                                    }
                                }

                                DispatchQueue.global().async {
                                    onFinish?(ret)
                                }
                            }
                        }
                    }
                    try? FileManager.default.removeItem(at: target)
                }
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
        
        let cipher = CryptomatorCryptor(encryptionMasterKey: self.encryptionMasterKey, macMasterKey: self.macMasterKey)
        // header
        guard let header = cipher.createHeader() else {
            return nil
        }
        guard header.count == output.write(header, maxLength: header.count) else {
            return nil
        }
        
        var buffer = [UInt8](repeating: 0, count: cipher.PAYLOAD_SIZE)
        var chunkNo:Int64 = 0
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
        } while len == cipher.PAYLOAD_SIZE

        
        return crypttarget
    }
    
    override func readFile(fileId: String, start: Int64?, length: Int64?, callCount: Int = 0, onFinish: ((Data?) -> Void)?) {
        os_log("%{public}@", log: log, type: .debug, "readFile(cryptomator:\(storageName ?? "")) \(fileId)")
        
        let array = fileId.components(separatedBy: "/")
        let dirId = array[0]
        let deflateId = array[1]

        if deflateId == "" {
            onFinish?(nil)
            return
        }
        
        guard let dirIdHash = getDirHash(dirId: dirId) else {
            onFinish?(nil)
            return
        }

        findParentStorage(path: [DATA_DIR_NAME, String(dirIdHash.prefix(2)), String(dirIdHash.suffix(30))]) { items in
            for item in items {
                if item.name == deflateId {
                    item.read(start: start, length: length, onFinish: onFinish)
                    return
                }
            }
            onFinish?(nil)
        }
    }
    
    override func ConvertDecryptSize(size: Int64) -> Int64 {
        return CalcDecryptedSize(crypt_size: size)
    }
    
    override func ConvertEncryptSize(size: Int64) -> Int64 {
        return CalcEncryptedSize(org_size: size)
    }
    
    let NONCE_SIZE: Int64 = 16
    let PAYLOAD_SIZE: Int64 = 32 * 1024
    let MAC_SIZE: Int64 = 32
    lazy var CHUNK_SIZE = NONCE_SIZE + PAYLOAD_SIZE + MAC_SIZE
    let HEADER_SIZE: Int64 = 88
    
    func CalcEncryptedSize(org_size: Int64) -> Int64 {
        if org_size < 0 {
            return 0
        }
        let cleartextChunkSize = PAYLOAD_SIZE
        let ciphertextChunkSize = CHUNK_SIZE
        let overheadPerChunk = ciphertextChunkSize - cleartextChunkSize
        let numFullChunks = org_size / cleartextChunkSize // floor by int-truncation
        let additionalCleartextBytes = org_size % cleartextChunkSize
        let additionalCiphertextBytes = (additionalCleartextBytes == 0) ? 0 : additionalCleartextBytes + overheadPerChunk;
        guard additionalCiphertextBytes >= 0 else {
            return 0
        }
        return ciphertextChunkSize * numFullChunks + additionalCiphertextBytes + HEADER_SIZE
    }
    
    func CalcDecryptedSize(crypt_size: Int64) -> Int64 {
        if crypt_size <= 0 {
            return 0
        }
        let size = crypt_size - HEADER_SIZE
        if size < 0 {
            return 0
        }
        let cleartextChunkSize = PAYLOAD_SIZE
        let ciphertextChunkSize = CHUNK_SIZE
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
    
    override init?(storage: String, id: String) {
        guard let s = CloudFactory.shared[storage] as? Cryptomator else {
            return nil
        }
        remoteStorage = s
        super.init(storage: storage, id: id)
    }
    
    init?(remoteStorage: Cryptomator, id: String) {

        self.remoteStorage = remoteStorage
        super.init(storage: self.remoteStorage.storageName ?? "", id: id)
        
    }
/*
    public override func read(start: Int64? = nil, length: Int64? = nil, onFinish: ((Data?) -> Void)?) {
        if self.remoteStorage.version == 6 {
            return super.read(start: start, length: length, onFinish: onFinish)

        } else {
            
        }
    }
  */
    public override func open() -> RemoteStream {
        return RemoteCryptomatorStream(remote: self)
    }
}

class CryptomatorCryptor {
    let NONCE_SIZE = 16
    let PAYLOAD_SIZE = 32 * 1024
    let MAC_SIZE = 32
    lazy var CHUNK_SIZE = NONCE_SIZE + PAYLOAD_SIZE + MAC_SIZE
    
    let HEADER_NONCE_LEN = 16
    let HEADER_FILESIZE_LEN = 8
    let HEADER_CONTENT_KEY_LEN = 32
    let HEADER_MAC_LEN = 32
    lazy var HEADER_SIZE = HEADER_NONCE_LEN + HEADER_FILESIZE_LEN + HEADER_CONTENT_KEY_LEN + HEADER_MAC_LEN
    lazy var HEADER_PAYLOAD_SIZE = HEADER_FILESIZE_LEN + HEADER_CONTENT_KEY_LEN
    lazy var HEADER_PAYLOAD_OFFSET = HEADER_NONCE_LEN
    lazy var HEADER_MAC_OFFSET = HEADER_NONCE_LEN + HEADER_FILESIZE_LEN + HEADER_CONTENT_KEY_LEN

    let encryptionMasterKey: [UInt8]
    let macMasterKey: [UInt8]

    var headerNonce = [UInt8]()
    var header_filesize: UInt64 = 0
    var contentKey = [UInt8]()

    init(encryptionMasterKey: [UInt8], macMasterKey: [UInt8]) {
        self.encryptionMasterKey = encryptionMasterKey
        self.macMasterKey = macMasterKey
    }
    
    func createHeader() -> [UInt8]? {
        // generate key
        headerNonce = [UInt8](repeating: 0, count: HEADER_NONCE_LEN)
        guard SecRandomCopyBytes(kSecRandomDefault, headerNonce.count, &headerNonce) == errSecSuccess else {
            return nil
        }
        contentKey = [UInt8](repeating: 0, count: HEADER_CONTENT_KEY_LEN)
        guard SecRandomCopyBytes(kSecRandomDefault, contentKey.count, &contentKey) == errSecSuccess else {
            return nil
        }

        // not use now, set all 1
        let header_filesize_1 = [UInt8](repeating: 0xFF, count: HEADER_FILESIZE_LEN)
        
        // make header
        var header = [UInt8](repeating: 0, count: HEADER_SIZE)
        // nonce copy
        header[0..<headerNonce.count] = headerNonce[0...]
        
        // payload
        var payloadCleartext = [UInt8](repeating: 0, count: HEADER_PAYLOAD_SIZE)
        payloadCleartext[0..<header_filesize_1.count] = header_filesize_1[0...]
        payloadCleartext[header_filesize_1.count..<(header_filesize_1.count + contentKey.count)] = contentKey[0...]

        // encrypt payload
        guard let cipher = AES_CTR(key: encryptionMasterKey, nonce: headerNonce) else {
            print("AES_CTR init error")
            return nil
        }
        guard let encrypted = cipher.encrypt(plaintext: payloadCleartext) else {
            print("header payload encryption error")
            return nil
        }
        
        // payload copy
        header[HEADER_PAYLOAD_OFFSET..<(HEADER_PAYLOAD_OFFSET+encrypted.count)] = encrypted[0...]
        
        // calc mac
        var macTarget = [UInt8](repeating: 0, count: HEADER_MAC_OFFSET)
        macTarget[0..<headerNonce.count] = headerNonce[0...]
        macTarget[headerNonce.count...] = encrypted[0...]
        
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), macMasterKey, macMasterKey.count, macTarget, macTarget.count, &result)
        
        // copy mac
        header[HEADER_MAC_OFFSET...] = result[0...]
        
        return header
    }
    
    func encryptChunk(chunk: Data, chunkId: Int64) -> [UInt8]? {
        var result = Data()
        
        // nonce
        var chunkNonce = [UInt8](repeating: 0, count: NONCE_SIZE)
        guard SecRandomCopyBytes(kSecRandomDefault, chunkNonce.count, &chunkNonce) == errSecSuccess else {
            return nil
        }
        result.append(contentsOf: chunkNonce)
        
        // payload
        guard let cipher = AES_CTR(key: contentKey, nonce: chunkNonce) else {
            print("AES_CTR init error")
            return nil
        }
        guard let encrypted = cipher.encrypt(plaintext: [UInt8](chunk)) else {
            print("chunk encryption error")
            return nil
        }
        result.append(contentsOf: encrypted)
        
        // mac
        var mac_target = Data()
        mac_target.append(contentsOf: headerNonce)
        var bigId = chunkId.bigEndian
        mac_target.append(contentsOf: [UInt8](withUnsafeBytes(of: &bigId) { $0 }))
        mac_target.append(contentsOf: chunkNonce)
        mac_target.append(contentsOf: encrypted)
        
        var authenticationCode = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), macMasterKey, macMasterKey.count, [UInt8](mac_target), mac_target.count, &authenticationCode)

        result.append(contentsOf: authenticationCode)
        
        return [UInt8](result)
    }
    
    func decryptHeader(header: Data) -> Bool {
        guard header.count == HEADER_SIZE else {
            print("error on header size check")
            return false
        }
        return header.withUnsafeBytes { data in
            let p = data.baseAddress!.bindMemory(to: UInt8.self, capacity: HEADER_SIZE)
            self.headerNonce = Array(UnsafeBufferPointer(start: p, count: HEADER_NONCE_LEN))
            
            let ciphertextPayload = Array(UnsafeBufferPointer(start: p.advanced(by: HEADER_PAYLOAD_OFFSET), count: HEADER_FILESIZE_LEN + HEADER_CONTENT_KEY_LEN))
            let expectedMac = Array(UnsafeBufferPointer(start: p.advanced(by: HEADER_MAC_OFFSET), count: HEADER_MAC_LEN))
            
            // check mac:
            let nonceAndCiphertextBuf = Array(UnsafeBufferPointer(start: p, count: HEADER_NONCE_LEN + HEADER_FILESIZE_LEN + HEADER_CONTENT_KEY_LEN))
            
            var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), macMasterKey, macMasterKey.count, nonceAndCiphertextBuf, nonceAndCiphertextBuf.count, &result)
            
            guard result.elementsEqual(expectedMac) else {
                print("Header MAC doesn't match.")
                return false
            }
            
            // decrypt payload:
            guard let cipher = AES_CTR(key: encryptionMasterKey, nonce: headerNonce) else {
                print("AES_CTR error")
                return false
            }
            guard let payloadCleartextBuf = cipher.encrypt(plaintext: ciphertextPayload) else {
                print("Error in decrypting header payload")
                return false
            }
            Data(payloadCleartextBuf).withUnsafeBytes {
                header_filesize = $0.load(as: UInt64.self)
                contentKey = Array(UnsafeBufferPointer(start: $0.baseAddress!.bindMemory(to: UInt8.self, capacity: HEADER_FILESIZE_LEN + HEADER_CONTENT_KEY_LEN).advanced(by: HEADER_FILESIZE_LEN), count: HEADER_CONTENT_KEY_LEN))
            }
            return true
        }
    }

    func decryptChunk(chunk: Data, chunkId: Int64) -> Data? {
        return autoreleasepool {
            // check mac
            let nonce_chunk = chunk.subdata(in: 0..<NONCE_SIZE)
            let expectedMacBuf = chunk.subdata(in: (chunk.count-MAC_SIZE)..<chunk.count)
            let payload = chunk.subdata(in: NONCE_SIZE..<(chunk.count-MAC_SIZE))
            
            var mac_target = Data()
            mac_target.append(contentsOf: headerNonce)
            var bigId = chunkId.bigEndian
            mac_target.append(contentsOf: [UInt8](withUnsafeBytes(of: &bigId) { $0 }))
            mac_target.append(nonce_chunk)
            mac_target.append(payload)
            
            var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), macMasterKey, macMasterKey.count, [UInt8](mac_target), mac_target.count, &result)
            
            guard expectedMacBuf.elementsEqual(result) else {
                print("mac not match in chunk.")
                return nil
            }
            
            // decrypt payload:
            guard let cipher = AES_CTR(key: contentKey, nonce: [UInt8](nonce_chunk)) else {
                print("AES_CTR error")
                return nil
            }
            guard let plain = cipher.encrypt(plaintext: [UInt8](payload)) else {
                print("block decrypt error")
                return nil
            }
            return Data(plain)
        }
    }

}

public class RemoteCryptomatorStream: SlotStream {
    let remote: CryptomatorRemoteItem
    let OrignalLength: Int64
    let CryptedLength: Int64
    
    let cipher: CryptomatorCryptor
    
    init(remote: CryptomatorRemoteItem) {
        self.remote = remote
        OrignalLength = remote.size
        CryptedLength = remote.remoteStorage.CalcEncryptedSize(org_size: OrignalLength)
        cipher = CryptomatorCryptor(encryptionMasterKey: remote.remoteStorage.encryptionMasterKey, macMasterKey: remote.remoteStorage.macMasterKey)
        super.init(size: OrignalLength)
    }
    
    override func firstFill() {
        fillHeader()
        super.firstFill()
    }
    
    func fillHeader() {
        init_group.enter()
        remote.read(start: 0, length: Int64(cipher.HEADER_SIZE)) { data in
            defer {
                self.init_group.leave()
            }
            if let data = data {
                guard self.cipher.decryptHeader(header: data) else {
                    self.error = true
                    return
                }
            }
            else {
                print("error on header null")
                self.error = true
            }
        }
    }


    
    override func subFillBuffer(pos1: Int64, onFinish: @escaping ()->Void) {
        guard init_group.wait(timeout: DispatchTime.now()+120) == DispatchTimeoutResult.success else {
            self.error = true
            onFinish()
            return
        }
        
        let chunksize = Int64(cipher.CHUNK_SIZE)
        let orgBlocksize = Int64(cipher.PAYLOAD_SIZE)
        let overhead = chunksize - orgBlocksize
        let headersize = Int64(cipher.HEADER_SIZE)
        let group = DispatchGroup()
        group.enter()
        defer {
            group.leave()
        }
        DispatchQueue.global().async {
            group.notify(queue: .global()) {
                onFinish()
            }
        }
        if !dataAvailable(pos: pos1) {
            guard pos1 >= 0 && pos1 < size else {
                return
            }
            let len = (pos1 + bufSize < size) ? bufSize : size - pos1
            let slot1 = pos1 / orgBlocksize
            let pos2 = slot1 * chunksize + headersize
            var clen = len / orgBlocksize * chunksize
            if len % orgBlocksize != 0 {
                clen += len % orgBlocksize + overhead
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
            group.enter()
            remote.read(start: pos2, length: clen) { data in
                defer {
                    group.leave()
                }
                if let data = data {
                    DispatchQueue.global().async {
                        var slot = slot1
                        var plainBlock = Data()
                        for start in stride(from: 0, to: data.count, by: Int(chunksize)) {
                            autoreleasepool {
                                let end = (start+Int(chunksize) >= data.count) ? data.count : start+Int(chunksize)
                                let chunk = data.subdata(in: start..<end)
                                guard let plain = self.cipher.decryptChunk(chunk: chunk, chunkId: slot) else {
                                    self.error = true
                                    return
                                }
                                plainBlock.append(plain)
                                slot += 1
                            }
                            guard !self.error else {
                                return
                            }
                        }
                        self.queue_buf.async {
                            self.buffer[pos1] = plainBlock
                        }
                    }
                }
                else {
                    print("error on readFile")
                    self.error = true
                }
            }
        }
    }
}

class BASE64 {
    public class func base64urlencode(input: Data) -> String? {
        var base64Encoded: String?
        
        base64Encoded = input.base64EncodedString()
        base64Encoded = base64Encoded?.replacingOccurrences(of: "+", with: "-")
        base64Encoded = base64Encoded?.replacingOccurrences(of: "/", with: "_")
        
        return base64Encoded;
    }
    
    public class func base64urldecode(input: String) -> Data? {

        var base64Encoded = input
        
        base64Encoded = base64Encoded.replacingOccurrences(of: "-", with: "+")
        base64Encoded = base64Encoded.replacingOccurrences(of: "_", with: "/")
        
        return Data(base64Encoded: base64Encoded, options: Data.Base64DecodingOptions(rawValue: 0));
    
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

class AES_CTR {
    let blockSize = 16
    let key: [UInt8]
    var counter: [UInt8]
    
    public init?(key: [UInt8], nonce: [UInt8]) {
        guard [128,192,256].contains(key.count * 8) else {
            return nil
        }
        self.key = key
        self.counter = [UInt8](repeating: 0, count: blockSize)
        if nonce.count <= blockSize {
            self.counter[0..<nonce.count] = nonce[0...]
        }
        else {
            self.counter[0...] = nonce[0..<blockSize]
        }
    }
    
    public func encrypt(plaintext: [UInt8]) -> [UInt8]? {
        let plainLength = plaintext.count
        var crypted = [UInt8](repeating: 0, count: plainLength)
        
        guard plainLength > 0 else {
            return crypted
        }
        
        let plainBlocks = (plainLength + blockSize - 1)/blockSize
        for i in 0..<plainBlocks {
            guard let stream = AES(key: key, data: counter) else {
                return nil
            }
            let len = (i+1)*blockSize < plainLength ? blockSize : plainLength - i*blockSize
            for j in 0..<len {
                crypted[i*blockSize + j] = stream[j] ^ plaintext[i*blockSize + j]
            }
            IncCounter()
        }
        return crypted
    }

    func IncCounter() {
        var carry: UInt8 = 1
        for i in (0..<counter.count).reversed() {
            counter[i] &+= carry
            if counter[i] == 0 {
                carry = 1
            }
            else {
                break
            }
        }
        return
    }
    
    func AES(key: [UInt8], data: [UInt8], decode: Bool = false) -> [UInt8]? {
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

class AES_SIV {
    public class func encrypt(ctrKey: [UInt8], macKey: [UInt8], plaintext: [UInt8], associatedData: [[UInt8]] = []) -> [UInt8]? {
        let numBlocks = (plaintext.count + 15) / 16
        guard let iv = s2v(macKey: macKey, plaintext: plaintext, associatedData: associatedData) else {
            return nil
        }
        guard let keystream = generateKeyStream(ctrKey: ctrKey, iv: iv, numBlocks: numBlocks) else {
            return nil
        }
        guard let ciphertext = xor(in1: plaintext, in2: keystream) else {
            return nil
        }
        var result = iv
        result.append(contentsOf: ciphertext)
        return result
    }
    
    public class func decrypt(ctrKey: [UInt8], macKey: [UInt8], ciphertext: [UInt8], associatedData: [[UInt8]] = []) -> [UInt8]? {
        guard ciphertext.count >= 16 else {
            return nil
        }

        let iv = Array(ciphertext[0..<16])
        let actualCiphertext = Array(ciphertext[16...])
        
        let numBlocks = (actualCiphertext.count + 15) / 16
        guard let keystream = generateKeyStream(ctrKey: ctrKey, iv: iv, numBlocks: numBlocks) else {
            return nil
        }
        guard let plaintext = xor(in1: actualCiphertext, in2: keystream) else {
            return nil
        }
        guard let control = s2v(macKey: macKey, plaintext: plaintext, associatedData: associatedData) else {
            return nil
        }

        guard control.count == iv.count else {
            return nil
        }
        guard zip(control, iv).allSatisfy({ $0 == $1 }) else {
            return nil
        }
        return plaintext
    }
    
    class func generateKeyStream(ctrKey: [UInt8], iv: [UInt8], numBlocks: Int) -> [UInt8]? {
        guard iv.count == 16 else {
            return nil
        }
        var keystream = [UInt8](repeating: 0, count: numBlocks * 16)
        
        // clear out the 31st and 63rd (rightmost) bit:
        var ctr = iv
        ctr[8] &= 0x7F
        ctr[12] &= 0x7F
        let initialCtrVal = Int64(bigEndian: Array(ctr[8...]).withUnsafeBufferPointer {
            ($0.baseAddress!.withMemoryRebound(to: Int64.self, capacity: 1) { $0 })
            }.pointee)
        
        for i in 0..<numBlocks {
            var c = (initialCtrVal + Int64(i)).bigEndian
            ctr[8...] = [UInt8](withUnsafeBytes(of: &c) { $0 })[0...]
            guard let enc = AES(key: ctrKey, data: ctr) else {
                return nil
            }
            keystream[i*16..<(i+1)*16] = enc[0..<16]
        }
        return keystream
    }
    
    class func s2v(macKey: [UInt8], plaintext: [UInt8], associatedData: [[UInt8]] = []) -> [UInt8]? {
        guard associatedData.count <= 126 else {
            return nil
        }
     
        guard var d = AES_CMAC.digest(key: macKey, message: [UInt8](repeating: 0, count: 16)) else {
            return nil
        }
        
        for s in associatedData {
            guard let w = xor(in1: dbl(input: d), in2: AES_CMAC.digest(key: macKey, message: s)) else {
                return nil
            }
            d = w
        }

        if plaintext.count >= 16 {
            guard let t = xorend(in1: plaintext, in2: d) else {
                return nil
            }
            return AES_CMAC.digest(key: macKey, message: t)
        }
        else {
            guard let t = xor(in1: dbl(input: d), in2: pad(input: plaintext)) else {
                return nil
            }
            return AES_CMAC.digest(key: macKey, message: t)
        }
    }
    
    class func pad(input: [UInt8]) -> [UInt8] {
        var output = input
        if output.count < 16 {
            output.append(0x80)
        }
        while output.count < 16 {
            output.append(0)
        }
        return output
    }
    
    class func xorend(in1: [UInt8]?, in2: [UInt8]?) -> [UInt8]? {
        guard let in1 = in1, let in2 = in2 else {
            return nil
        }
        guard in1.count >= in2.count else {
            return nil
        }
        var out = in1
        let diff = in1.count - in2.count
        for i in 0..<in2.count {
            out[i+diff] ^= in2[i]
        }
        return out
    }

    class func xor(in1: [UInt8]?, in2: [UInt8]?) -> [UInt8]? {
        guard let in1 = in1, let in2 = in2 else {
            return nil
        }
        guard in1.count <= in2.count else {
            return nil
        }
        var ret = [UInt8](repeating: 0, count: in1.count)
        for i in 0..<in1.count {
            ret[i] = in1[i] ^ in2[i]
        }
        return ret
    }

    class func dbl(input: [UInt8]) -> [UInt8] {
        let DOUBLING_CONST: UInt8 = 0x87
        var (ret, carry) = shiftLeft(block: input)
        let xor = 0xff & DOUBLING_CONST
        let mask: UInt8 = carry ? UInt8(-1 & 0xff) : 0x00
        ret[input.count - 1] ^= xor & mask
        return ret
    }
    
    class func shiftLeft(block: [UInt8]) -> ([UInt8], Bool) {
        var bit: UInt8 = 0
        var output = [UInt8](repeating: 0, count: block.count)
        for i in (0..<block.count).reversed() {
            let b = block[i]
            output[i] = (b << 1) | bit
            bit = (b >> 7) & 1
        }
        return (output, bit != 0)
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

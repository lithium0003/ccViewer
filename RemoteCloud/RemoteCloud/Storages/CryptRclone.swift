//
//  CryptRclone.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/03/15.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CommonCrypto

class ViewControllerPasswordRclone: UIViewController, UITextFieldDelegate, UIDocumentPickerDelegate  {
    var textPassword: UITextField!
    var textSalt: UITextField!
    var textSuffix: UITextField!
    var stackView: UIStackView!
    var switchObfuscation: UISwitch!
    var switchHidename: UISwitch!
    var filenameEncryption: Bool = false
    var filenameObfuscation: Bool = false

    var onCancel: (()->Void)!
    var onFinish: ((String, String, String, Bool, Bool)->Void)!
    var done: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "CryptRclone password"
        view.backgroundColor = .white
        
        stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        let stackView0 = UIStackView()
        stackView0.axis = .horizontal
        stackView0.alignment = .center
        stackView0.spacing = 20
        stackView.insertArrangedSubview(stackView0, at: 0)
        
        let button0 = UIButton(type: .system)
        button0.setTitle("Load from rclone.conf", for: .normal)
        button0.addTarget(self, action: #selector(buttonLoadEvent), for: .touchUpInside)
        stackView0.insertArrangedSubview(button0, at: 0)

        
        let stackView1 = UIStackView()
        stackView1.axis = .horizontal
        stackView1.alignment = .center
        stackView1.spacing = 20
        stackView.insertArrangedSubview(stackView1, at: 1)
        
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

        let stackView2 = UIStackView()
        stackView2.axis = .horizontal
        stackView2.alignment = .center
        stackView2.spacing = 20
        stackView.insertArrangedSubview(stackView2, at: 2)
        
        let label2 = UILabel()
        label2.text = "Salt"
        stackView2.insertArrangedSubview(label2, at: 0)
        
        textSalt = UITextField()
        textSalt.borderStyle = .roundedRect
        textSalt.delegate = self
        textSalt.clearButtonMode = .whileEditing
        textSalt.returnKeyType = .done
        textSalt.isSecureTextEntry = true
        textSalt.placeholder = "salt"
        stackView2.insertArrangedSubview(textSalt, at: 1)
        let widthConstraint2 = textSalt.widthAnchor.constraint(equalToConstant: 200)
        widthConstraint2.priority = .defaultHigh
        widthConstraint2.isActive = true

        let stackView3 = UIStackView()
        stackView3.axis = .horizontal
        stackView3.alignment = .center
        stackView3.spacing = 20
        stackView.insertArrangedSubview(stackView3, at: 3)
        
        let label3 = UILabel()
        label3.text = "Encrypt filename"
        stackView3.insertArrangedSubview(label3, at: 0)
        
        switchHidename = UISwitch()
        switchHidename.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
        filenameEncryption = switchHidename.isOn
        stackView3.insertArrangedSubview(switchHidename, at: 1)
        
        let stackView6 = UIStackView()
        stackView6.axis = .horizontal
        stackView6.alignment = .center
        stackView6.spacing = 20
        stackView.insertArrangedSubview(stackView6, at: 4)
        
        let label5 = UILabel()
        label5.text = "Obfuscation mode"
        stackView6.insertArrangedSubview(label5, at: 0)
        
        switchObfuscation = UISwitch()
        switchObfuscation.addTarget(self, action: #selector(switchValueChanged2), for: .valueChanged)
        filenameObfuscation = switchObfuscation.isOn
        stackView6.insertArrangedSubview(switchObfuscation, at: 1)
        
        let stackView4 = UIStackView()
        stackView4.axis = .horizontal
        stackView4.alignment = .center
        stackView4.spacing = 20
        stackView.insertArrangedSubview(stackView4, at: 5)
        
        let label4 = UILabel()
        label4.text = "Suffix"
        stackView4.insertArrangedSubview(label4, at: 0)
        
        textSuffix = UITextField()
        textSuffix.borderStyle = .roundedRect
        textSuffix.delegate = self
        textSuffix.clearButtonMode = .whileEditing
        textSuffix.returnKeyType = .done
        textSuffix.placeholder = "bin"
        stackView4.insertArrangedSubview(textSuffix, at: 1)

        (stackView.arrangedSubviews[4]).isHidden = !switchHidename.isOn
        (stackView.arrangedSubviews[5]).isHidden = switchHidename.isOn
        
        let stackView5 = UIStackView()
        stackView5.axis = .horizontal
        stackView5.alignment = .center
        stackView5.spacing = 20
        stackView.insertArrangedSubview(stackView5, at: 6)
        
        let button1 = UIButton(type: .system)
        button1.setTitle("Done", for: .normal)
        button1.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView5.insertArrangedSubview(button1, at: 0)
        
        let button2 = UIButton(type: .system)
        button2.setTitle("Cancel", for: .normal)
        button2.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView5.insertArrangedSubview(button2, at: 1)
    }

    @objc func buttonLoadEvent(_ sender: UIButton) {
        let picker = UIDocumentPickerViewController(documentTypes: ["info.lithium03.mtype.conf"], in: .open)
        picker.delegate = self
        present(picker, animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            var conf = Data()
            do {
                guard CFURLStartAccessingSecurityScopedResource(url as CFURL) else {
                    return
                }
                defer {
                    CFURLStopAccessingSecurityScopedResource(url as CFURL)
                }
                guard let input = InputStream(url: url) else {
                    return
                }
                input.open()
                do {
                    defer {
                        input.close()
                    }
                    var buffer = [UInt8](repeating: 0, count: 1024)
                    while input.hasBytesAvailable {
                        let read = input.read(&buffer, maxLength: buffer.count)
                        if read < 0 {
                            //Stream error occured
                            print(input.streamError!)
                            return
                        } else if read == 0 {
                            //EOF
                            break
                        }
                        conf.append(buffer, count: read)
                    }
                }
            }
            guard let confstr = String(bytes: conf, encoding: .utf8) else {
                return
            }
            let conflines = confstr.components(separatedBy: .newlines)
            if conflines.contains("RCLONE_ENCRYPT_V0:") {
                let base64 = conflines.last!
                guard let box = Data(base64Encoded: base64) else {
                    return
                }
                guard box.count >= 24+Secretbox.Overhead else {
                    return
                }
                
                let alert = UIAlertController(title: "Encrypt config file",
                                              message: "enter password",
                                              preferredStyle: .alert)
                let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
                let defaultAction = UIAlertAction(title: "OK", style: .default) { action in
                    if let password = alert.textFields?[0].text {
                        let data = Array("[\(password)][rclone-config]".utf8)
                        var configKey = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
                        CC_SHA256(data, CC_LONG(data.count), &configKey)

                        let nonce = [UInt8](box.subdata(in: 0..<24))
                        let key = Array(configKey[0..<32])
                        guard let out = Secretbox.open(box: box.subdata(in: 24..<box.count), nonce: nonce, key: key) else {
                            return
                        }
                        guard let plain = String(bytes: out, encoding: .utf8) else {
                            return
                        }
                        self.processConfigFile(conflines: plain.components(separatedBy: .newlines))
                    }
                }
                
                alert.addAction(cancelAction)
                alert.addAction(defaultAction)
                
                alert.addTextField(configurationHandler: {(text:UITextField!) -> Void in
                    text.placeholder = "password"
                    let label = UILabel(frame: CGRect(x: 0, y: 0, width: 50, height: 30))
                    label.text = "Pass"
                    text.leftView = label
                    text.leftViewMode = .always
                    text.enablesReturnKeyAutomatically = true
                    text.isSecureTextEntry = true
                })
                
                present(alert, animated: true, completion: nil)
                return
            }
            processConfigFile(conflines: conflines)
        }
    }
    
    func processConfigFile(conflines: [String]) {
        var config = [String: Any]()
        var aConfigName = ""
        var aConfigs = [String: String]()
        guard let regex1 = try? NSRegularExpression(pattern: #"\[(.+)\]"#, options: []) else {
            return
        }
        guard let regex2 = try? NSRegularExpression(pattern: #"(\S+)\s*=\s*(.*)"#, options: []) else {
            return
        }
        for line in conflines {
            if line.hasPrefix(";") || line.hasPrefix("#") {
                continue
            }
            let targetStringRange = NSRange(location: 0, length: line.count)
            let results1 = regex1.matches(in: line, options: [], range: targetStringRange)
            if results1.count > 0 {
                if aConfigName != "" {
                    // finish prev config
                    config[aConfigName] = aConfigs
                }
                
                let range = results1[0].range(at: 1)
                aConfigName = (line as NSString).substring(with: range)
                aConfigs.removeAll()
                continue
            }
            let results2 = regex2.matches(in: line, options: [], range: targetStringRange)
            if results2.count > 0 {
                let range1 = results2[0].range(at: 1)
                let range2 = results2[0].range(at: 2)
                let name = (line as NSString).substring(with: range1)
                let value = (line as NSString).substring(with: range2)
                aConfigs[name] = value
            }
        }
        if aConfigName != "" {
            // finish prev config
            config[aConfigName] = aConfigs
        }
        
        var crypt_config = [String: [String: String]]()
        for (confKey, confItems) in config {
            guard let confItems = confItems as? [String: String] else {
                continue
            }
            if let type = confItems["type"], type == "crypt" {
                guard let password = confItems["password"] else {
                    continue
                }
                guard let password2 = confItems["password2"] else {
                    continue
                }
                guard let filename_encryption = confItems["filename_encryption"] else {
                    continue
                }
                crypt_config[confKey] = ["password": password, "password2": password2, "filename_encryption": filename_encryption]
            }
        }
        
        let alert = UIAlertController(title: "Load from rclone.conf", message: "select crypt item name", preferredStyle:  .alert)
        
        var alertItems = [UIAlertAction]()
        for (confKey, confItems) in crypt_config {
            let action = UIAlertAction(title: confKey, style: .default) { act in
                self.textPassword.text = self.reveal(ciphertext: confItems["password"])
                self.textSalt.text = self.reveal(ciphertext: confItems["password2"])
                switch confItems["filename_encryption"] {
                case "standard":
                    self.filenameEncryption = true
                    self.filenameObfuscation = false
                case "obfuscate":
                    self.filenameEncryption = true
                    self.filenameObfuscation = true
                case "off":
                    self.filenameEncryption = false
                    self.filenameObfuscation = false
                default:
                    break
                }
                self.switchObfuscation.isOn = self.filenameObfuscation
                self.switchHidename.isOn = self.filenameEncryption
                (self.stackView.arrangedSubviews[4]).isHidden = !self.switchHidename.isOn
                (self.stackView.arrangedSubviews[5]).isHidden = self.switchHidename.isOn
            }
            alert.addAction(action)
            alertItems.append(action)
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        alert.addAction(cancelAction)
        
        present(alert, animated: true, completion: nil)
    }
    
    func reveal(ciphertext: String?) -> String? {
        guard let ciphertext = ciphertext else {
            return nil
        }
        let key: [UInt8] = [ 0x9c, 0x93, 0x5b, 0x48, 0x73, 0x0a, 0x55, 0x4d,
                             0x6b, 0xfd, 0x7c, 0x63, 0xc8, 0x86, 0xa9, 0x2b,
                             0xd3, 0x90, 0x19, 0x8e, 0xb8, 0x12, 0x8a, 0xfb,
                             0xf4, 0xde, 0x16, 0x2b, 0x8b, 0x95, 0xf6, 0x38,]
        var ciphertext_stdbase64 = ciphertext.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        ciphertext_stdbase64.append(contentsOf: String(repeating: "=", count: 4 - ciphertext_stdbase64.count % 4))
        print(ciphertext_stdbase64)
        guard let cipher = Data(base64Encoded: ciphertext_stdbase64) else {
            return nil
        }
        print(cipher)
        guard cipher.count >= 16 else {
            return ciphertext
        }
        let buffer = cipher.subdata(in: 16..<cipher.count)
        let iv = cipher.subdata(in: 0..<16)
        guard let aes = AES_CTR(key: key, nonce: [UInt8](iv)) else {
            return nil
        }
        guard let plain = aes.encrypt(plaintext: [UInt8](buffer)) else {
            return ciphertext
        }
        print(plain)
        return String(bytes: plain, encoding: .utf8)
    }
    
    @objc func buttonEvent(_ sender: UIButton) {
        if sender.currentTitle == "Done" {
            done = true
            onFinish(textPassword.text ?? "", textSalt.text ?? "", textSuffix.text ?? "", filenameEncryption, filenameObfuscation)
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
        onFinish(textPassword.text ?? "", textSalt.text ?? "", textSuffix.text ?? "", filenameEncryption, filenameObfuscation)
        return true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if textPassword.isFirstResponder {
            textPassword.resignFirstResponder()
        }
        if textSalt.isFirstResponder {
            textSalt.resignFirstResponder()
        }
        if textSuffix.isFirstResponder {
            textSuffix.resignFirstResponder()
        }
    }
    
    @objc func switchValueChanged(aSwitch: UISwitch) {
        (stackView.arrangedSubviews[4]).isHidden = !aSwitch.isOn
        (stackView.arrangedSubviews[5]).isHidden = aSwitch.isOn
        filenameEncryption = aSwitch.isOn
    }

    @objc func switchValueChanged2(aSwitch: UISwitch) {
        filenameObfuscation = aSwitch.isOn
    }
}



public class CryptRclone: ChildStorage {
    
    public override func getStorageType() -> CloudStorages {
        return .CryptRclone
    }
    
    let nameCipherBlockSize = 16
    let fileMagic = "RCLONE\0\0".data(using: .ascii)!
    let fileMagicSize: Int64 = 8
    let fileNonceSize: Int64 = 24
    let fileHeaderSize: Int64 = 8 + 24
    let blockHeaderSize: Int64 = 16
    let blockDataSize: Int64 = 64 * 1024
    let chunkSize: Int64 = 16 + 64 * 1024
    let defaultSalt = Data.init([0xA8, 0x0D, 0xF4, 0x3A, 0x8F, 0xBD, 0x03, 0x08, 0xA7, 0xCA, 0xB8, 0x3E, 0x58, 0x1F, 0x86, 0xB1])
    let defaultSuffix = "bin"

    var dataKey = [UInt8](repeating: 0, count: 32)
    var nameKey = [UInt8](repeating: 0, count: 32)
    var nameTweak = [UInt8](repeating: 0, count: 16)
    
    let encodeMap = Array("0123456789ABCDEFGHIJKLMNOPQRSTUV")
    let decodeMap: [Character: Int]
    
    var name_aes: AES_EME?
    var name_crypt: Bool = true
    var name_obfuscation: Bool = false
    var name_suffix: String = ""
    
    override public init(name: String) {
        var m: [Character: Int] = [:]
        encodeMap.enumerated().forEach { i, c in
            m[c] = i
        }
        m["="] = 0
        decodeMap = m

        super.init(name: name)
        service = CloudFactory.getServiceName(service: .CryptRclone)
        storageName = name
        if self.getKeyChain(key: "\(self.storageName ?? "")_password") != nil && self.getKeyChain(key: "\(self.storageName ?? "")_salt") != nil {
            generateKey()
        }
        if let b = getKeyChain(key: "\(self.storageName ?? "")_cryptname"), b == "true" {
            name_crypt = true
        }
        else {
            name_crypt = false
        }
        if let b = getKeyChain(key: "\(self.storageName ?? "")_obfuscation"), b == "true" {
            name_obfuscation = true
        }
        else {
            name_obfuscation = false
        }
        if let s = getKeyChain(key: "\(self.storageName ?? "")_suffix"), s != "" {
            name_suffix = "."+s
        }
        else {
            name_suffix = "."+defaultSuffix
        }
    }
    
    override public func auth(onFinish: ((Bool) -> Void)?) -> Void {
        super.auth() { success in
            if success {
                if self.getKeyChain(key: "\(self.storageName ?? "")_password") != nil && self.getKeyChain(key: "\(self.storageName ?? "")_salt") != nil {
                    DispatchQueue.global().async {
                        self.generateKey()
                        onFinish?(true)
                    }
                    return
                }
                DispatchQueue.main.async {
                    if let controller = UIApplication.topViewController() {
                        let passwordView = ViewControllerPasswordRclone()
                        passwordView.onCancel = {
                            onFinish?(false)
                        }
                        passwordView.onFinish = { pass, salt, suffix, cfname, ofname in
                            let _ = self.setKeyChain(key: "\(self.storageName ?? "")_password", value: pass)
                            let _ = self.setKeyChain(key: "\(self.storageName ?? "")_salt", value: salt)
                            let _ = self.setKeyChain(key: "\(self.storageName ?? "")_suffix", value: suffix)
                            if cfname {
                                let _ = self.setKeyChain(key: "\(self.storageName ?? "")_cryptname", value: "true")
                            }
                            if ofname {
                                let _ = self.setKeyChain(key: "\(self.storageName ?? "")_obfuscation", value: "true")
                            }
                            self.name_crypt = cfname
                            self.name_obfuscation = ofname
                            self.name_suffix = suffix != "" ? suffix : self.defaultSuffix

                            DispatchQueue.global().async {
                                self.generateKey()
                                onFinish?(true)
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
            let _ = delKeyChain(key: "\(name)_salt")
            let _ = delKeyChain(key: "\(name)_suffix")
            let _ = delKeyChain(key: "\(name)_cryptname")
            let _ = delKeyChain(key: "\(name)_obfuscation")
        }
        super.logout()
    }
    
    func generateKey() {
        let password = getKeyChain(key: "\(storageName ?? "")_password") ?? ""
        let salt: Data
        if let saltstr = getKeyChain(key: "\(storageName ?? "")_salt"), saltstr != "" {
            salt = saltstr.data(using: .ascii)!
        }
        else {
            salt = defaultSalt
        }
        
        let keysize = dataKey.count + nameKey.count + nameTweak.count
        DispatchQueue.global().async {
            var key = [UInt8](repeating: 0, count: keysize)
            if password != "" {
                key = SCrypt.ComputeDerivedKey(key: [UInt8](password.data(using: .ascii)!), salt: [UInt8](salt), cost: 16384, blockSize: 8, derivedKeyLength: keysize)
            }
            self.dataKey = Array(key[0..<32])
            self.nameKey = Array(key[32..<64])
            self.nameTweak = Array(key[64..<80])
            
            self.name_aes = AES_EME(key: self.nameKey, IV: self.nameTweak)
        }
    }
    
    override func ConvertDecryptName(name: String) -> String {
        return DecryptName(ciphertext: name) ?? name
    }
    
    override func ConvertDecryptSize(size: Int64) -> Int64 {
        return CalcDecryptedSize(crypt_size: size)
    }

    override func ConvertEncryptName(name: String, folder: Bool) -> String {
        if folder && !name_crypt {
            return name
        }
        return EncryptName(plain: name) ?? name
    }
    
    override func ConvertEncryptSize(size: Int64) -> Int64 {
        return CalcEncryptedSize(org_size: size)
    }
    
    func EncodeFileName(input: [UInt8]) -> String {
        let len = input.count
        if (len == 0) {
            return ""
        }
        
        var out = ""
        var offset = 0
        while len - offset > 0 {
            var b = [UInt8](repeating: 0, count: 8)
            let r = len - offset
            if r > 4 {
                b[7] = input[offset+4] & 0x1f
                b[6] = input[offset+4] >> 5
            }
            if r > 3 {
                b[6] |= (input[offset+3] << 3) & 0x1f
                b[5] = (input[offset+3] >> 2) & 0x1f
                b[4] = input[offset+3] >> 7
            }
            if r > 2 {
                b[4] |= (input[offset+2] << 1) & 0x1f
                b[3] = (input[offset+2] >> 4) & 0x1f
            }
            if r > 1 {
                b[3] |= (input[offset+1] << 4) & 0x1f
                b[2] = (input[offset+1] >> 1) & 0x1f
                b[1] = (input[offset+1] >> 6) & 0x1f
            }
            if r > 0 {
                b[1] |= (input[offset] << 2) & 0x1f
                b[0] = input[offset] >> 3 & 0x1f
            }
            var outchars = b.map { encodeMap[Int($0)] }
            if r < 5 {
                outchars[7] = "="
                if r < 4 {
                    outchars[6] = "="
                    outchars[5] = "="
                    if r < 3 {
                        outchars[4] = "="
                        if r < 2 {
                            outchars[3] = "="
                            outchars[2] = "="
                        }
                    }
                }
                out += String(outchars)
                break
            }
            offset += 5
            out += String(outchars)
        }
        return out.replacingOccurrences(of: "=", with: "").lowercased()
    }
    
    func DecodeFileName(input: String) -> Data? {
        let len = input.count
        let padlen = ((len / 8) + 1) * 8 - len
        if padlen == 7 || padlen == 5 || padlen == 2 {
            return nil
        }
        var inchar = Array(input.uppercased())
        inchar.append(contentsOf: [Character](repeating: "=", count: padlen))
        
        var out = Data()
        for offset in stride(from: 0, to: len, by: 8) {
            var dst = [UInt8](repeating: 0, count: 5)
            let buf = inchar[offset..<offset+8].map { decodeMap[$0] ?? 0 }
            dst[4] = UInt8((buf[6] << 5 | buf[7]) & 0xff)
            dst[3] = UInt8((buf[4] << 7 | buf[5] << 2 | buf[6] >> 3) & 0xff)
            dst[2] = UInt8((buf[3] << 4 | buf[4] >> 1) & 0xff)
            dst[1] = UInt8((buf[1] << 6 | buf[2] << 1 | buf[3] >> 4) & 0xff)
            dst[0] = UInt8((buf[0] << 3 | buf[1] >> 2) & 0xff)
            
            var c = 0;
            if (len - offset >= 8)
            {
                c = 5
            }
            else
            {
                switch (padlen)
                {
                case 1:
                    c = 4
                    break
                case 3:
                    c = 3
                    break
                case 4:
                    c = 2
                    break
                case 6:
                    c = 1
                    break
                default:
                    break;
                }
            }

            out.append(contentsOf: dst[0..<c])
        }
        return out
    }
    
    func EncryptName(plain: String) -> String? {
        if plain == "" {
            return ""
        }
        if name_obfuscation {
            var dir: UInt32 = 0
            for i in plain {
                dir += i.unicodeScalars.first!.value
            }
            dir = dir % 256
            
            var crypted = "\(dir)."
            for i in nameKey {
                dir += UInt32(i)
            }
            
            let obfuscQuoteRune:Character = "!"
            for runeValue in plain {
                switch runeValue {
                case obfuscQuoteRune:
                    crypted += String(obfuscQuoteRune)
                    crypted += String(obfuscQuoteRune)
                case "0"..."9":
                    // Number
                    let thisdir = (dir % 9) + 1
                    let newRune = Unicode.Scalar("0").value + (runeValue.unicodeScalars.first!.value - Unicode.Scalar("0").value + thisdir) % 10
                    crypted += String(Unicode.Scalar(newRune)!)
                case "A"..."Z","a"..."z":
                    // ASCII letter.  Try to avoid trivial A->a mappings
                    let thisdir = dir % 25 + 1
                    // Calculate the offset of this character in A-Za-z
                    var pos = runeValue.unicodeScalars.first!.value - Unicode.Scalar("A").value
                    if pos >= 26 {
                        pos -= 6 // It's lower case
                    }
                    // Rotate the character to the new location
                    pos = (pos + thisdir) % 52
                    if pos >= 26 {
                        pos += 6 // and handle lower case offset again
                    }
                    crypted += String(Unicode.Scalar(Unicode.Scalar("A").value + pos)!)
                case "\u{A0}"..."\u{FF}":
                    // Latin 1 supplement
                    let thisdir = (dir % 95) + 1
                    let newRune = 0xA0 + (runeValue.unicodeScalars.first!.value - 0xA0 - thisdir) % 96
                    crypted += String(Unicode.Scalar(newRune)!)
                case "\u{100}"...:
                    // Some random Unicode range; we have no good rules here
                    let thisdir = (dir % 127) + 1
                    let base = runeValue.unicodeScalars.first!.value - runeValue.unicodeScalars.first!.value % 256
                    let newRune = base + (runeValue.unicodeScalars.first!.value - base + thisdir) % 256
                    // If the new character isn't a valid UTF8 char
                    // then don't rotate it.  Quote it instead
                    if let rune = Unicode.Scalar(newRune) {
                        crypted += String(rune)
                    }
                    else {
                        crypted += String(obfuscQuoteRune)
                        crypted += String(runeValue)
                    }
                default:
                    // Leave character untouched
                    crypted += String(runeValue)
                }
            }
            return crypted
        }
        else if name_crypt {
            guard var input = plain.data(using: .utf8) else {
                return nil
            }
            var padlen = 16 - input.count % 16
            if padlen == 0 {
                padlen = 16
            }
            input.append(Data(repeating: UInt8(padlen), count: padlen))
            guard let output = name_aes?.encode(input: input) else {
                return nil
            }
            return EncodeFileName(input: [UInt8](output))
        }
        else {
            return plain + name_suffix
        }
    }
    
    func DecryptName(ciphertext: String) -> String? {
        if ciphertext == "" {
            return ""
        }
        
        if name_obfuscation {
            guard let range = ciphertext.range(of: ".") else {
                return nil
            }
            let num = ciphertext.components(separatedBy: ".")[0]
            let otext = ciphertext[range.upperBound...]
            if num == "!" {
                return String(otext)
            }
            guard var dir = Int(num) else {
                return nil
            }
            for i in nameKey {
                dir += Int(i)
            }
            var plain = ""
            var inQuote = false
            let obfuscQuoteRune:Character = "!"
            for runeValue in otext {
                if inQuote {
                    plain += String(runeValue)
                    inQuote = false
                }
                else {
                    switch runeValue {
                    case obfuscQuoteRune:
                        inQuote = true
                    case "0"..."9":
                        // Number
                        let thisdir = (dir % 9) + 1
                        var newRune = runeValue.unicodeScalars.first!.value - UInt32(thisdir)
                        if newRune < Unicode.Scalar("0").value {
                            newRune += 10
                        }
                        plain += String(Unicode.Scalar(newRune)!)
                    case "A"..."Z","a"..."z":
                        let thisdir = dir % 25 + 1
                        var pos = Int(runeValue.unicodeScalars.first!.value - Unicode.Scalar("A").value)
                        if pos >= 26 {
                            pos -= 6
                        }
                        pos = pos - thisdir
                        if pos < 0 {
                            pos += 52
                        }
                        if pos >= 26 {
                            pos += 6
                        }
                        plain += String(Unicode.Scalar(Unicode.Scalar("A").value + UInt32(pos))!)
                    case "\u{A0}"..."\u{FF}":
                        let thisdir = (dir % 95) + 1
                        var newRune = runeValue.unicodeScalars.first!.value - UInt32(thisdir)
                        if newRune < 0xA0 {
                            newRune += 96
                        }
                        plain += String(Unicode.Scalar(newRune)!)
                    case "\u{100}"...:
                        let thisdir = (dir % 127) + 1
                        let base = runeValue.unicodeScalars.first!.value - runeValue.unicodeScalars.first!.value % 256
                        var offset = Int(runeValue.unicodeScalars.first!.value - base) - thisdir
                        if offset < 0 {
                            offset += 256
                        }
                        let newRune = base + UInt32(offset)
                        plain += String(Unicode.Scalar(newRune)!)
                    default:
                        plain += String(runeValue)
                    }
                }
            }
            return plain
        }
        else if name_crypt {
            guard let rawcipher = DecodeFileName(input: ciphertext) else {
                return nil
            }
            guard rawcipher.count > 0 && rawcipher.count % (128 / 8) == 0 else {
                return nil
            }
            guard var Plaintext = name_aes?.decode(input: rawcipher) else {
                return nil
            }
            guard let padlen = Plaintext.last, padlen <= (128 / 8) else {
                return nil
            }
            Plaintext = Plaintext.subdata(in: 0..<Plaintext.count-Int(padlen))
            guard let filename = String(bytes: Plaintext, encoding: .utf8) else {
                return nil
            }
            return filename
        }
        else {
            if ciphertext.hasSuffix(name_suffix) {
                return String(ciphertext.prefix(ciphertext.count - name_suffix.count))
            }
            return ciphertext
        }
    }
    
    func CalcEncryptedSize(org_size: Int64) -> Int64 {
        if org_size < 1 {
            return fileHeaderSize
        }
        
        let chunk_num = (org_size - 1) / blockDataSize
        let last_chunk_size = (org_size - 1) % blockDataSize + 1
    
        return fileHeaderSize + chunkSize * chunk_num + (blockHeaderSize + last_chunk_size)
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
        if last_chunk_size < blockHeaderSize {
            return -1
        }
        
        return chunk_num * blockDataSize + last_chunk_size - blockHeaderSize
    }
    
    public override func getRaw(fileId: String) -> RemoteItem? {
        return CryptRcloneRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) -> RemoteItem? {
        return CryptRcloneRemoteItem(path: path)
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
        
        var nonce = [UInt8](repeating: 0, count: Int(fileNonceSize))
        guard errSecSuccess == SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce) else {
            return nil
        }
        
        // header
        var magic = [UInt8](fileMagic)
        guard magic.count == output.write(&magic, maxLength: magic.count) else {
            return nil
        }
        
        guard nonce.count == output.write(&nonce, maxLength: nonce.count) else {
            return nil
        }
        
        var buffer = [UInt8](repeating: 0, count: Int(blockDataSize))
        var chunkNo = 0
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
            
            guard let crypted = Secretbox.seal(message: Data(bytes: &buffer, count: len), nonce: addNonce(pos: chunkNo, nonce: nonce), key: dataKey) else {
                return nil
            }
            var outbuf = [UInt8](crypted)
            guard outbuf.count == output.write(&outbuf, maxLength: outbuf.count) else {
                return nil
            }
            
            chunkNo += 1
        } while len == blockDataSize
        
        return crypttarget
    }

    func addNonce(pos: Int, nonce: [UInt8])->[UInt8] {
        var nonce_count = nonce
        var pos1 = UInt64(pos)
        for i in 0..<nonce_count.count {
            if pos1 == 0 {
                break
            }
            let addcount = UInt16(pos1 & 0xff)
            let newdigit = UInt16(nonce_count[i]) + addcount
            pos1 >>= 8
            if newdigit & 0xff00 != 0 {
                pos1 += 1
            }
            nonce_count[i] = UInt8(newdigit & 0xff)
        }
        return nonce_count
    }
}

public class CryptRcloneRemoteItem: RemoteItem {
    let remoteStorage: CryptRclone
    
    override init?(storage: String, id: String) {
        guard let s = CloudFactory.shared[storage] as? CryptRclone else {
            return nil
        }
        remoteStorage = s
        super.init(storage: storage, id: id)
    }
    
    public override func open() -> RemoteStream {
        return RemoteCryptRcloneStream(remote: self)
    }
}

public class RemoteCryptRcloneStream: SlotStream {
    let remote: CryptRcloneRemoteItem
    let OrignalLength: Int64
    let CryptedLength: Int64
    var nonce = [UInt8](repeating: 0, count: 24)
    let key: [UInt8]

    init(remote: CryptRcloneRemoteItem) {
        self.remote = remote
        OrignalLength = remote.size
        CryptedLength = remote.remoteStorage.CalcEncryptedSize(org_size: OrignalLength)
        key = remote.remoteStorage.dataKey
        super.init(size: OrignalLength)
    }
    
    override func firstFill() {
        fillHeader()
        super.firstFill()
    }
    
    func fillHeader() {
        init_group.enter()
        remote.read(start: 0, length: remote.remoteStorage.fileHeaderSize) { data in
            if let data = data {
                if !self.remote.remoteStorage.fileMagic.elementsEqual(data.subdata(in: 0..<self.remote.remoteStorage.fileMagic.count)) {
                    print("error on header check")
                    self.error = true
                }
                self.nonce.replaceSubrange(0..<self.nonce.count, with: data.subdata(in: self.remote.remoteStorage.fileMagic.count..<data.count))
            }
            else {
                print("error on header null")
                self.error = true
            }
            self.init_group.leave()
        }
    }
    
    func addNonce(pos: Int64)->[UInt8] {
        var nonce_count = nonce
        var pos1 = UInt64(pos)
        for i in 0..<nonce_count.count {
            if pos1 == 0 {
                break
            }
            let addcount = UInt16(pos1 & 0xff)
            let newdigit = UInt16(nonce_count[i]) + addcount
            pos1 >>= 8
            if newdigit & 0xff00 != 0 {
                pos1 += 1
            }
            nonce_count[i] = UInt8(newdigit & 0xff)
        }
        return nonce_count
    }
    
    override func subFillBuffer(pos1: Int64, onFinish: @escaping ()->Void) {
        guard init_group.wait(timeout: DispatchTime.now()+120) == DispatchTimeoutResult.success else {
            self.error = true
            onFinish()
            return
        }
        let chunksize = remote.remoteStorage.chunkSize
        let orgBlocksize = remote.remoteStorage.blockDataSize
        let headersize = Int64(remote.remoteStorage.fileHeaderSize)
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
                clen += len % orgBlocksize + remote.remoteStorage.blockHeaderSize
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
                            let end = (start+Int(chunksize) >= data.count) ? data.count : start+Int(chunksize)
                            let chunk = data.subdata(in: start..<end)
                            guard let plain = Secretbox.open(box: chunk, nonce: self.addNonce(pos: slot), key: self.key) else {
                                self.error = true
                                return
                            }
                            plainBlock.append(plain)
                            slot += 1
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


class AES_EME {
    let key: [UInt8]
    let tweek: [UInt8]
    
    init(key: [UInt8], IV: [UInt8]) {
        self.key = key
        self.tweek = IV
    }
    
    func encode(input: Data) -> Data? {
        return ([UInt8](input)).withUnsafeBufferPointer { inBuf in
            return transform(input: inBuf, decode: false)
        }
    }
    
    func decode(input: Data) -> Data? {
        return ([UInt8](input)).withUnsafeBufferPointer { inBuf in
            return transform(input: inBuf, decode: true)
        }
    }
    
    func transform(input: UnsafeBufferPointer<UInt8>, decode: Bool) -> Data? {
        let op = (decode) ? CCOperation(kCCDecrypt) : CCOperation(kCCEncrypt)
        
        guard tweek.count == 16 else {
            return nil
        }
        guard input.count % 16 == 0 else {
            return nil
        }
        let m = input.count / 16
        guard m > 0 && m <= 16 * 8 else {
            return nil
        }
        
        var C = [UInt8](repeating: 0, count: input.count)
        guard let LTable = TabulateL(m: m) else {
            return nil
        }
        
        let PPj = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: 16)
        C.withUnsafeMutableBufferPointer { (Cbytes: inout UnsafeMutableBufferPointer<UInt8>)->Void in
            tweek.withUnsafeBufferPointer { (T: UnsafeBufferPointer<UInt8>)->Void in
                key.withUnsafeBufferPointer { (keyBytes: UnsafeBufferPointer<UInt8>)->Void in
                    for j in 0..<m {
                        let Pj = UnsafeBufferPointer<UInt8>(rebasing: input[j*16..<(j+1)*16])
                        /* PPj = 2**(j-1)*L xor Pj */
                        XorBlocks(output: PPj, in1: Pj, in2: LTable[j])
                        
                        /* PPPj = AESenc(K; PPj) */
                        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
                        var outLength = Int(0)
                        status = CCCrypt(op,
                                         CCAlgorithm(kCCAlgorithmAES),
                                         CCOptions(kCCOptionECBMode),
                                         keyBytes.baseAddress,
                                         key.count,
                                         nil,
                                         PPj.baseAddress,
                                         PPj.count,
                                         Cbytes.baseAddress! + j*16,
                                         16,
                                         &outLength)
                        
                        guard status == kCCSuccess else {
                            return
                        }
                    }
                    /* MP =(xorSum PPPj) xor T */
                    let MPt = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: 16)
                    XorBlocks(output: MPt, in1: UnsafeBufferPointer<UInt8>(rebasing: Cbytes[0..<16]), in2: T)
                    for j in 1..<m {
                        XorBlocks(inout1: MPt, in2: UnsafeBufferPointer<UInt8>(rebasing: Cbytes[j*16..<(j+1)*16]))
                    }
                    let MP = UnsafeBufferPointer<UInt8>(MPt)
                    
                    /* MC = AESenc(K; MP) */
                    var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
                    var outLength = Int(0)
                    let mcBytes = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: 16)
                    status = CCCrypt(op,
                                     CCAlgorithm(kCCAlgorithmAES),
                                     CCOptions(kCCOptionECBMode),
                                     keyBytes.baseAddress,
                                     key.count,
                                     nil,
                                     MP.baseAddress,
                                     MP.count,
                                     mcBytes.baseAddress,
                                     mcBytes.count,
                                     &outLength)
                    guard status == kCCSuccess else {
                        print(status)
                        return
                    }
                    let MC = UnsafeBufferPointer<UInt8>(mcBytes)
                    
                    /* M = MP xor MC */
                    let M = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: 16)
                    XorBlocks(output: M, in1: MP, in2: MC)
                    for j in 1..<m {
                        MultByTwo(inout1: M)
                        /* CCCj = 2**(j-1)*M xor PPPj */
                        XorBlocks(inout1: UnsafeMutableBufferPointer<UInt8>(rebasing: Cbytes[j*16..<(j+1)*16]), in2: UnsafeBufferPointer<UInt8>(M))
                    }
                    
                    /* CCC1 = (xorSum CCCj) xor T xor MC */
                    let CCC1 = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: 16)
                    XorBlocks(output: CCC1, in1: MC, in2: T)
                    for j in 1..<m {
                        XorBlocks(inout1: CCC1, in2: UnsafeBufferPointer<UInt8>(rebasing: Cbytes[j*16..<(j+1)*16]))
                    }
                    for i in 0..<16 {
                        Cbytes[i] = CCC1[i]
                    }
                    
                    for j in 0..<m {
                        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
                        var outLength = Int(0)
                        var outBytes = [UInt8](repeating: 0, count: 16)
                        status = CCCrypt(op,
                                         CCAlgorithm(kCCAlgorithmAES),
                                         CCOptions(kCCOptionECBMode),
                                         keyBytes.baseAddress,
                                         key.count,
                                         nil,
                                         Cbytes.baseAddress! + j*16,
                                         16,
                                         &outBytes,
                                         outBytes.count,
                                         &outLength)
                        guard status == kCCSuccess else {
                            print(status)
                            return
                        }
                        outBytes.withUnsafeBufferPointer { outBuf in
                            XorBlocks(output: UnsafeMutableBufferPointer<UInt8>(rebasing: Cbytes[j*16..<(j+1)*16]), in1: outBuf, in2: LTable[j])
                        }
                    }
                }
            }
        }
        return Data(C)
    }
    
    func XorBlocks(output: UnsafeMutableBufferPointer<UInt8>, in1: UnsafeBufferPointer<UInt8>, in2: UnsafeBufferPointer<UInt8>) {
        guard in1.count == in2.count else {
            return
        }
        for i in 0..<in1.count {
            output[i] = in1[i] ^ in2[i]
        }
    }

    func XorBlocks(inout1: UnsafeMutableBufferPointer<UInt8>, in2: UnsafeBufferPointer<UInt8>) {
        guard inout1.count == in2.count else {
            return
        }
        for i in 0..<inout1.count {
            inout1[i] ^= in2[i]
        }
    }
    

    func MultByTwo(output: UnsafeMutableBufferPointer<UInt8>, input: UnsafeBufferPointer<UInt8>) {
        guard input.count == 16, output.count == 16 else {
            return
        }
        
        output[0] = 2 &* input[0]
        if (input[15] >= 128)
        {
            output[0] = output[0] ^ 135
        }
        for j in 1..<16 {
            output[j] = 2 &* input[j]
            if (input[j - 1] >= 128)
            {
                output[j] += 1;
            }
        }
    }

    func MultByTwo(inout1: UnsafeMutableBufferPointer<UInt8>) {
        guard inout1.count == 16 else {
            return
        }
        var tmpout = [UInt8](repeating: 0, count: 16)
        tmpout.withUnsafeMutableBufferPointer { output in
            output[0] = 2 &* inout1[0]
            if (inout1[15] >= 128)
            {
                output[0] = output[0] ^ 135
            }
            for j in 1..<16 {
                output[j] = 2 &* inout1[j]
                if (inout1[j - 1] >= 128)
                {
                    output[j] += 1;
                }
            }
            for j in 0..<16 {
                inout1[j] = output[j]
            }
        }
    }

    // tabulateL - calculate L_i for messages up to a length of m cipher blocks
    func TabulateL(m: Int) -> [UnsafeBufferPointer<UInt8>]? {
        
        /* set L0 = 2*AESenc(K; 0) */
        let eZero = [UInt8](repeating: 0, count: 16)
        
        var outLength = Int(0)
        var outBytes = [UInt8](repeating: 0, count: eZero.count)
        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
        key.withUnsafeBytes { keyBytes in
            status = CCCrypt(CCOperation(kCCEncrypt),
                             CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionECBMode),
                             keyBytes.baseAddress,
                             key.count,
                             nil,
                             eZero,
                             eZero.count,
                             &outBytes,
                             outBytes.count,
                             &outLength)
        }
        guard status == kCCSuccess else {
            return nil
        }
        var ret: [UnsafeMutableBufferPointer<UInt8>] = (0..<m).map { _ in UnsafeMutableBufferPointer<UInt8>.allocate(capacity: outLength) }
        var Li = Array(outBytes[0..<outLength])
        Li.withUnsafeMutableBufferPointer { LiBuf in
            for i in 0..<m {
                MultByTwo(output: ret[i], input: UnsafeBufferPointer(LiBuf))
                for j in 0..<16 {
                    LiBuf[j] = ret[i][j]
                }
            }
        }
        return ret.map { UnsafeBufferPointer<UInt8>($0) }
    }
}

class Poly1305 {
    static let TagSize = 16
    
    class func poly1305(tag: UnsafeMutableBufferPointer<UInt8>, msg: UnsafeBufferPointer<UInt8>, key: UnsafeBufferPointer<UInt8>) {
        let len = msg.count
        var h0, h1, h2, h3, h4: UInt32
        var r0, r1, r2, r3, r4: UInt64
        h0 = 0
        h1 = 0
        h2 = 0
        h3 = 0
        h4 = 0
        r0 = 0
        r1 = 0
        r2 = 0
        r3 = 0
        r4 = 0

        let keyPointer = UnsafeRawBufferPointer(key).baseAddress!
        r0 = UInt64((keyPointer).assumingMemoryBound(to: UInt32.self).pointee & 0x3ffffff)
        r1 = UInt64(((keyPointer+3).assumingMemoryBound(to: UInt32.self).pointee >> 2) & 0x3ffff03)
        r2 = UInt64(((keyPointer+6).assumingMemoryBound(to: UInt32.self).pointee >> 4) & 0x3ffc0ff)
        r3 = UInt64(((keyPointer+9).assumingMemoryBound(to: UInt32.self).pointee >> 6) & 0x3f03fff)
        r4 = UInt64(((keyPointer+12).assumingMemoryBound(to: UInt32.self).pointee >> 8) & 0x00fffff)
        
        
        let R1 = r1 * 5
        let R2 = r2 * 5
        let R3 = r3 * 5
        let R4 = r4 * 5
        
        var offset = 0
        while len - offset >= TagSize {
            // h += msg
            h0 += UnsafeRawPointer(msg.baseAddress!+offset).assumingMemoryBound(to: UInt32.self).pointee & 0x3ffffff
            h1 += (UnsafeRawPointer(msg.baseAddress!+offset+3).assumingMemoryBound(to: UInt32.self).pointee >> 2) & 0x3ffffff
            h2 += (UnsafeRawPointer(msg.baseAddress!+offset+6).assumingMemoryBound(to: UInt32.self).pointee >> 4) & 0x3ffffff
            h3 += (UnsafeRawPointer(msg.baseAddress!+offset+9).assumingMemoryBound(to: UInt32.self).pointee >> 6) & 0x3ffffff
            h4 += (UnsafeRawPointer(msg.baseAddress!+offset+12).assumingMemoryBound(to: UInt32.self).pointee >> 8) | (1 << 24)
            
            // h *= r
            let d0 = ((UInt64)(h0) * r0) + ((UInt64)(h1) * R4) + ((UInt64)(h2) * R3) + ((UInt64)(h3) * R2) + ((UInt64)(h4) * R1)
            let d1 = (d0 >> 26) + ((UInt64)(h0) * r1) + ((UInt64)(h1) * r0) + ((UInt64)(h2) * R4) + ((UInt64)(h3) * R3) + ((UInt64)(h4) * R2)
            let d2 = (d1 >> 26) + ((UInt64)(h0) * r2) + ((UInt64)(h1) * r1) + ((UInt64)(h2) * r0) + ((UInt64)(h3) * R4) + ((UInt64)(h4) * R3)
            let d3 = (d2 >> 26) + ((UInt64)(h0) * r3) + ((UInt64)(h1) * r2) + ((UInt64)(h2) * r1) + ((UInt64)(h3) * r0) + ((UInt64)(h4) * R4)
            let d4 = (d3 >> 26) + ((UInt64)(h0) * r4) + ((UInt64)(h1) * r3) + ((UInt64)(h2) * r2) + ((UInt64)(h3) * r1) + ((UInt64)(h4) * r0)
            
            // h %= p
            h0 = (UInt32)(d0 & 0x3ffffff)
            h1 = (UInt32)(d1 & 0x3ffffff)
            h2 = (UInt32)(d2 & 0x3ffffff)
            h3 = (UInt32)(d3 & 0x3ffffff)
            h4 = (UInt32)(d4 & 0x3ffffff)
            
            h0 += (UInt32)(d4 >> 26) * 5
            h1 += h0 >> 26
            h0 = h0 & 0x3ffffff
            
            offset += TagSize
        }
        if msg.count - offset > 0 {
            var block = [UInt8](repeating: 0, count: TagSize)
            block.replaceSubrange(0..<msg.count-offset, with: msg[offset..<msg.count])
            block[msg.count-offset] = 0x01
            
            // h += msg
            block.withUnsafeBytes { u in
                h0 += (u.baseAddress!).assumingMemoryBound(to: UInt32.self).pointee & 0x3ffffff
                h1 += ((u.baseAddress!+3).assumingMemoryBound(to: UInt32.self).pointee >> 2) & 0x3ffffff
                h2 += ((u.baseAddress!+6).assumingMemoryBound(to: UInt32.self).pointee >> 4) & 0x3ffffff
                h3 += ((u.baseAddress!+9).assumingMemoryBound(to: UInt32.self).pointee >> 6) & 0x3ffffff
                h4 += ((u.baseAddress!+12).assumingMemoryBound(to: UInt32.self).pointee >> 8)
            }
            
            // h *= r
            let d0 = ((UInt64)(h0) * r0) + ((UInt64)(h1) * R4) + ((UInt64)(h2) * R3) + ((UInt64)(h3) * R2) + ((UInt64)(h4) * R1)
            let d1 = (d0 >> 26) + ((UInt64)(h0) * r1) + ((UInt64)(h1) * r0) + ((UInt64)(h2) * R4) + ((UInt64)(h3) * R3) + ((UInt64)(h4) * R2)
            let d2 = (d1 >> 26) + ((UInt64)(h0) * r2) + ((UInt64)(h1) * r1) + ((UInt64)(h2) * r0) + ((UInt64)(h3) * R4) + ((UInt64)(h4) * R3)
            let d3 = (d2 >> 26) + ((UInt64)(h0) * r3) + ((UInt64)(h1) * r2) + ((UInt64)(h2) * r1) + ((UInt64)(h3) * r0) + ((UInt64)(h4) * R4)
            let d4 = (d3 >> 26) + ((UInt64)(h0) * r4) + ((UInt64)(h1) * r3) + ((UInt64)(h2) * r2) + ((UInt64)(h3) * r1) + ((UInt64)(h4) * r0)
            
            // h %= p
            h0 = (UInt32)(d0 & 0x3ffffff)
            h1 = (UInt32)(d1 & 0x3ffffff)
            h2 = (UInt32)(d2 & 0x3ffffff)
            h3 = (UInt32)(d3 & 0x3ffffff)
            h4 = (UInt32)(d4 & 0x3ffffff)
            
            h0 += (UInt32)(d4 >> 26) * 5
            h1 += h0 >> 26
            h0 = h0 & 0x3ffffff
        }
        
        // h %= p reduction
        h2 += h1 >> 26
        h1 &= 0x3ffffff
        h3 += h2 >> 26
        h2 &= 0x3ffffff
        h4 += h3 >> 26
        h3 &= 0x3ffffff
        h0 += 5 * (h4 >> 26)
        h4 &= 0x3ffffff
        h1 += h0 >> 26
        h0 &= 0x3ffffff
        
        // h - p
        var t0 = h0 &+ 5
        var t1 = h1 &+ (t0 >> 26)
        var t2 = h2 &+ (t1 >> 26)
        var t3 = h3 &+ (t2 >> 26)
        let t4 = h4 &+ (t3 >> 26) &- (1 << 26)
        t0 &= 0x3ffffff
        t1 &= 0x3ffffff
        t2 &= 0x3ffffff
        t3 &= 0x3ffffff

        // select h if h < p else h - p
        let t_mask = (t4 >> 31) - 1
        let h_mask = ~t_mask
        h0 = (h0 & h_mask) | (t0 & t_mask)
        h1 = (h1 & h_mask) | (t1 & t_mask)
        h2 = (h2 & h_mask) | (t2 & t_mask)
        h3 = (h3 & h_mask) | (t3 & t_mask)
        h4 = (h4 & h_mask) | (t4 & t_mask)

        // h %= 2^128
        h0 |= h1 << 26
        h1 = ((h1 >> 6) | (h2 << 20))
        h2 = ((h2 >> 12) | (h3 << 14))
        h3 = ((h3 >> 18) | (h4 << 8))

        // s: the s part of the key
        // tag = (h + s) % (2^128)
        var t = UInt64(h0)+UInt64((keyPointer+16).assumingMemoryBound(to: UInt32.self).pointee)
        h0 = UInt32(t & 0xffffffff)
        t = UInt64(h1) + UInt64((keyPointer+20).assumingMemoryBound(to: UInt32.self).pointee) + (t >> 32)
        h1 = UInt32(t & 0xffffffff)
        t = UInt64(h2) + UInt64((keyPointer+24).assumingMemoryBound(to: UInt32.self).pointee) + (t >> 32)
        h2 = UInt32(t & 0xffffffff)
        t = UInt64(h3) + UInt64((keyPointer+28).assumingMemoryBound(to: UInt32.self).pointee) + (t >> 32)
        h3 = UInt32(t & 0xffffffff)

        let retUInt32 = UnsafeMutableRawBufferPointer(tag).bindMemory(to: UInt32.self)
        retUInt32[0] = h0
        retUInt32[1] = h1
        retUInt32[2] = h2
        retUInt32[3] = h3
    }
    
    class func Verify(mac: [UInt8], msg: [UInt8], key: [UInt8]) -> Bool {
        guard key.count == 32 else {
            return false
        }
        guard mac.count == TagSize else {
            return false
        }
        var tag = [UInt8](repeating: 0, count: TagSize)
        key.withUnsafeBufferPointer { keyBuf in
            tag.withUnsafeMutableBufferPointer { tagBuf in
                msg.withUnsafeBufferPointer { msgBuf in
                    poly1305(tag: tagBuf, msg: msgBuf, key: keyBuf)
                }
            }
        }
        return tag.elementsEqual(mac)
    }

    class func Verify(mac: UnsafeBufferPointer<UInt8>, msg: UnsafeBufferPointer<UInt8>, key: UnsafeBufferPointer<UInt8>) -> Bool {
        guard key.count == 32 else {
            return false
        }
        guard mac.count == TagSize else {
            return false
        }
        var tag = [UInt8](repeating: 0, count: TagSize)
        tag.withUnsafeMutableBufferPointer { tagBuf in
                poly1305(tag: tagBuf, msg: msg, key: key)
        }
        return tag.elementsEqual(mac)
    }
}

class Secretbox {
    static let Sigma = [UInt8]("expand 32-byte k".data(using: .ascii)!)
    static let Overhead = 16
    
    class func HSala20(input: [UInt8], k: [UInt8], c: [UInt8]) -> [UInt8]? {
        let round = 20
        guard input.count == 16 else {
            return nil
        }
        guard k.count == 32 else {
            return nil
        }
        guard c.count == 16 else {
            return nil
        }

        var x0: UInt32 = 0
        var x1: UInt32 = 0
        var x2: UInt32 = 0
        var x3: UInt32 = 0
        var x4: UInt32 = 0
        var x5: UInt32 = 0
        var x6: UInt32 = 0
        var x7: UInt32 = 0
        var x8: UInt32 = 0
        var x9: UInt32 = 0
        var x10: UInt32 = 0
        var x11: UInt32 = 0
        var x12: UInt32 = 0
        var x13: UInt32 = 0
        var x14: UInt32 = 0
        var x15: UInt32 = 0
        input.withUnsafeBytes { inputBytes in
            k.withUnsafeBytes { kBytes in
                c.withUnsafeBytes { cBytes in
                    let inputUInt32 = inputBytes.bindMemory(to: UInt32.self)
                    let kUInt32 = kBytes.bindMemory(to: UInt32.self)
                    let cUInt32 = cBytes.bindMemory(to: UInt32.self)
                    
                    x0 = cUInt32[0]
                    x1 = kUInt32[0]
                    x2 = kUInt32[1]
                    x3 = kUInt32[2]
                    x4 = kUInt32[3]
                    x5 = cUInt32[1]
                    x6 = inputUInt32[0]
                    x7 = inputUInt32[1]
                    x8 = inputUInt32[2]
                    x9 = inputUInt32[3]
                    x10 = cUInt32[2]
                    x11 = kUInt32[4]
                    x12 = kUInt32[5]
                    x13 = kUInt32[6]
                    x14 = kUInt32[7]
                    x15 = cUInt32[3]
                }
            }
        }

        for _ in stride(from: 0, to: round, by: 2) {
            var u: UInt32
            u = x0 &+ x12
            x4 ^= u << 7 | u >> (32 - 7)
            u = x4 &+ x0
            x8 ^= u << 9 | u >> (32 - 9)
            u = x8 &+ x4
            x12 ^= u << 13 | u >> (32 - 13)
            u = x12 &+ x8
            x0 ^= u << 18 | u >> (32 - 18)
            
            u = x5 &+ x1
            x9 ^= u << 7 | u >> (32 - 7)
            u = x9 &+ x5
            x13 ^= u << 9 | u >> (32 - 9)
            u = x13 &+ x9
            x1 ^= u << 13 | u >> (32 - 13)
            u = x1 &+ x13
            x5 ^= u << 18 | u >> (32 - 18)
            
            u = x10 &+ x6
            x14 ^= u << 7 | u >> (32 - 7)
            u = x14 &+ x10
            x2 ^= u << 9 | u >> (32 - 9)
            u = x2 &+ x14
            x6 ^= u << 13 | u >> (32 - 13)
            u = x6 &+ x2
            x10 ^= u << 18 | u >> (32 - 18)
            
            u = x15 &+ x11
            x3 ^= u << 7 | u >> (32 - 7)
            u = x3 &+ x15
            x7 ^= u << 9 | u >> (32 - 9)
            u = x7 &+ x3
            x11 ^= u << 13 | u >> (32 - 13)
            u = x11 &+ x7
            x15 ^= u << 18 | u >> (32 - 18)
            
            u = x0 &+ x3
            x1 ^= u << 7 | u >> (32 - 7)
            u = x1 &+ x0
            x2 ^= u << 9 | u >> (32 - 9)
            u = x2 &+ x1
            x3 ^= u << 13 | u >> (32 - 13)
            u = x3 &+ x2
            x0 ^= u << 18 | u >> (32 - 18)
            
            u = x5 &+ x4
            x6 ^= u << 7 | u >> (32 - 7)
            u = x6 &+ x5
            x7 ^= u << 9 | u >> (32 - 9)
            u = x7 &+ x6
            x4 ^= u << 13 | u >> (32 - 13)
            u = x4 &+ x7
            x5 ^= u << 18 | u >> (32 - 18)
            
            u = x10 &+ x9
            x11 ^= u << 7 | u >> (32 - 7)
            u = x11 &+ x10
            x8 ^= u << 9 | u >> (32 - 9)
            u = x8 &+ x11
            x9 ^= u << 13 | u >> (32 - 13)
            u = x9 &+ x8
            x10 ^= u << 18 | u >> (32 - 18)
            
            u = x15 &+ x14
            x12 ^= u << 7 | u >> (32 - 7)
            u = x12 &+ x15
            x13 ^= u << 9 | u >> (32 - 9)
            u = x13 &+ x12
            x14 ^= u << 13 | u >> (32 - 13)
            u = x14 &+ x13
            x15 ^= u << 18 | u >> (32 - 18)
        }

        var ret = [UInt8](repeating: 0, count: 32)
        ret.withUnsafeMutableBytes { retBytes in
            let retUInt32 = retBytes.bindMemory(to: UInt32.self)
            retUInt32[0] = x0
            retUInt32[1] = x5
            retUInt32[2] = x10
            retUInt32[3] = x15
            retUInt32[4] = x6
            retUInt32[5] = x7
            retUInt32[6] = x8
            retUInt32[7] = x9
        }
        return ret
    }
    
    class func SalaCore(input: [UInt8], k: [UInt8], c: [UInt8]) -> [UInt8]? {
        let round = 20
        guard input.count == 16 else {
            return nil
        }
        guard k.count == 32 else {
            return nil
        }
        guard c.count == 16 else {
            return nil
        }
        
        var x0: UInt32 = 0
        var x1: UInt32 = 0
        var x2: UInt32 = 0
        var x3: UInt32 = 0
        var x4: UInt32 = 0
        var x5: UInt32 = 0
        var x6: UInt32 = 0
        var x7: UInt32 = 0
        var x8: UInt32 = 0
        var x9: UInt32 = 0
        var x10: UInt32 = 0
        var x11: UInt32 = 0
        var x12: UInt32 = 0
        var x13: UInt32 = 0
        var x14: UInt32 = 0
        var x15: UInt32 = 0
        input.withUnsafeBytes { inputBytes in
            k.withUnsafeBytes { kBytes in
                c.withUnsafeBytes { cBytes in
                    let inputUInt32 = inputBytes.bindMemory(to: UInt32.self)
                    let kUInt32 = kBytes.bindMemory(to: UInt32.self)
                    let cUInt32 = cBytes.bindMemory(to: UInt32.self)
                    
                    x0 = cUInt32[0]
                    x1 = kUInt32[0]
                    x2 = kUInt32[1]
                    x3 = kUInt32[2]
                    x4 = kUInt32[3]
                    x5 = cUInt32[1]
                    x6 = inputUInt32[0]
                    x7 = inputUInt32[1]
                    x8 = inputUInt32[2]
                    x9 = inputUInt32[3]
                    x10 = cUInt32[2]
                    x11 = kUInt32[4]
                    x12 = kUInt32[5]
                    x13 = kUInt32[6]
                    x14 = kUInt32[7]
                    x15 = cUInt32[3]
                }
            }
        }
        let j0 = x0
        let j1 = x1
        let j2 = x2
        let j3 = x3
        let j4 = x4
        let j5 = x5
        let j6 = x6
        let j7 = x7
        let j8 = x8
        let j9 = x9
        let j10 = x10
        let j11 = x11
        let j12 = x12
        let j13 = x13
        let j14 = x14
        let j15 = x15

        for _ in stride(from: 0, to: round, by: 2) {
            var u: UInt32
            u = x0 &+ x12
            x4 ^= u << 7 | u >> (32 - 7)
            u = x4 &+ x0
            x8 ^= u << 9 | u >> (32 - 9)
            u = x8 &+ x4
            x12 ^= u << 13 | u >> (32 - 13)
            u = x12 &+ x8
            x0 ^= u << 18 | u >> (32 - 18)
            
            u = x5 &+ x1
            x9 ^= u << 7 | u >> (32 - 7)
            u = x9 &+ x5
            x13 ^= u << 9 | u >> (32 - 9)
            u = x13 &+ x9
            x1 ^= u << 13 | u >> (32 - 13)
            u = x1 &+ x13
            x5 ^= u << 18 | u >> (32 - 18)
            
            u = x10 &+ x6
            x14 ^= u << 7 | u >> (32 - 7)
            u = x14 &+ x10
            x2 ^= u << 9 | u >> (32 - 9)
            u = x2 &+ x14
            x6 ^= u << 13 | u >> (32 - 13)
            u = x6 &+ x2
            x10 ^= u << 18 | u >> (32 - 18)
            
            u = x15 &+ x11
            x3 ^= u << 7 | u >> (32 - 7)
            u = x3 &+ x15
            x7 ^= u << 9 | u >> (32 - 9)
            u = x7 &+ x3
            x11 ^= u << 13 | u >> (32 - 13)
            u = x11 &+ x7
            x15 ^= u << 18 | u >> (32 - 18)
            
            u = x0 &+ x3
            x1 ^= u << 7 | u >> (32 - 7)
            u = x1 &+ x0
            x2 ^= u << 9 | u >> (32 - 9)
            u = x2 &+ x1
            x3 ^= u << 13 | u >> (32 - 13)
            u = x3 &+ x2
            x0 ^= u << 18 | u >> (32 - 18)
            
            u = x5 &+ x4
            x6 ^= u << 7 | u >> (32 - 7)
            u = x6 &+ x5
            x7 ^= u << 9 | u >> (32 - 9)
            u = x7 &+ x6
            x4 ^= u << 13 | u >> (32 - 13)
            u = x4 &+ x7
            x5 ^= u << 18 | u >> (32 - 18)
            
            u = x10 &+ x9
            x11 ^= u << 7 | u >> (32 - 7)
            u = x11 &+ x10
            x8 ^= u << 9 | u >> (32 - 9)
            u = x8 &+ x11
            x9 ^= u << 13 | u >> (32 - 13)
            u = x9 &+ x8
            x10 ^= u << 18 | u >> (32 - 18)
            
            u = x15 &+ x14
            x12 ^= u << 7 | u >> (32 - 7)
            u = x12 &+ x15
            x13 ^= u << 9 | u >> (32 - 9)
            u = x13 &+ x12
            x14 ^= u << 13 | u >> (32 - 13)
            u = x14 &+ x13
            x15 ^= u << 18 | u >> (32 - 18)
        }
        
        x0 &+= j0
        x1 &+= j1
        x2 &+= j2
        x3 &+= j3
        x4 &+= j4
        x5 &+= j5
        x6 &+= j6
        x7 &+= j7
        x8 &+= j8
        x9 &+= j9
        x10 &+= j10
        x11 &+= j11
        x12 &+= j12
        x13 &+= j13
        x14 &+= j14
        x15 &+= j15

        var ret = [UInt8](repeating: 0, count: 64)
        ret.withUnsafeMutableBytes { retBytes in
            let retUInt32 = retBytes.bindMemory(to: UInt32.self)
            retUInt32[0] = x0
            retUInt32[1] = x1
            retUInt32[2] = x2
            retUInt32[3] = x3
            retUInt32[4] = x4
            retUInt32[5] = x5
            retUInt32[6] = x6
            retUInt32[7] = x7
            retUInt32[8] = x8
            retUInt32[9] = x9
            retUInt32[10] = x10
            retUInt32[11] = x11
            retUInt32[12] = x12
            retUInt32[13] = x13
            retUInt32[14] = x14
            retUInt32[15] = x15
        }
        return ret
    }
    
    class func SalaCore208(intext: UnsafeMutableBufferPointer<UInt32>, outtext: UnsafeMutableBufferPointer<UInt32>) {
        let round = 8
        guard intext.count == 16, outtext.count == 16 else {
            return
        }
        
        var x0 = intext[0]
        var x1 = intext[1]
        var x2 = intext[2]
        var x3 = intext[3]
        var x4 = intext[4]
        var x5 = intext[5]
        var x6 = intext[6]
        var x7 = intext[7]
        var x8 = intext[8]
        var x9 = intext[9]
        var x10 = intext[10]
        var x11 = intext[11]
        var x12 = intext[12]
        var x13 = intext[13]
        var x14 = intext[14]
        var x15 = intext[15]
        let j0 = x0
        let j1 = x1
        let j2 = x2
        let j3 = x3
        let j4 = x4
        let j5 = x5
        let j6 = x6
        let j7 = x7
        let j8 = x8
        let j9 = x9
        let j10 = x10
        let j11 = x11
        let j12 = x12
        let j13 = x13
        let j14 = x14
        let j15 = x15
        
        for _ in stride(from: 0, to: round, by: 2) {
            var u: UInt32
            u = x0 &+ x12
            x4 ^= u << 7 | u >> (32 - 7)
            u = x4 &+ x0
            x8 ^= u << 9 | u >> (32 - 9)
            u = x8 &+ x4
            x12 ^= u << 13 | u >> (32 - 13)
            u = x12 &+ x8
            x0 ^= u << 18 | u >> (32 - 18)
            
            u = x5 &+ x1
            x9 ^= u << 7 | u >> (32 - 7)
            u = x9 &+ x5
            x13 ^= u << 9 | u >> (32 - 9)
            u = x13 &+ x9
            x1 ^= u << 13 | u >> (32 - 13)
            u = x1 &+ x13
            x5 ^= u << 18 | u >> (32 - 18)
            
            u = x10 &+ x6
            x14 ^= u << 7 | u >> (32 - 7)
            u = x14 &+ x10
            x2 ^= u << 9 | u >> (32 - 9)
            u = x2 &+ x14
            x6 ^= u << 13 | u >> (32 - 13)
            u = x6 &+ x2
            x10 ^= u << 18 | u >> (32 - 18)
            
            u = x15 &+ x11
            x3 ^= u << 7 | u >> (32 - 7)
            u = x3 &+ x15
            x7 ^= u << 9 | u >> (32 - 9)
            u = x7 &+ x3
            x11 ^= u << 13 | u >> (32 - 13)
            u = x11 &+ x7
            x15 ^= u << 18 | u >> (32 - 18)
            
            u = x0 &+ x3
            x1 ^= u << 7 | u >> (32 - 7)
            u = x1 &+ x0
            x2 ^= u << 9 | u >> (32 - 9)
            u = x2 &+ x1
            x3 ^= u << 13 | u >> (32 - 13)
            u = x3 &+ x2
            x0 ^= u << 18 | u >> (32 - 18)
            
            u = x5 &+ x4
            x6 ^= u << 7 | u >> (32 - 7)
            u = x6 &+ x5
            x7 ^= u << 9 | u >> (32 - 9)
            u = x7 &+ x6
            x4 ^= u << 13 | u >> (32 - 13)
            u = x4 &+ x7
            x5 ^= u << 18 | u >> (32 - 18)
            
            u = x10 &+ x9
            x11 ^= u << 7 | u >> (32 - 7)
            u = x11 &+ x10
            x8 ^= u << 9 | u >> (32 - 9)
            u = x8 &+ x11
            x9 ^= u << 13 | u >> (32 - 13)
            u = x9 &+ x8
            x10 ^= u << 18 | u >> (32 - 18)
            
            u = x15 &+ x14
            x12 ^= u << 7 | u >> (32 - 7)
            u = x12 &+ x15
            x13 ^= u << 9 | u >> (32 - 9)
            u = x13 &+ x12
            x14 ^= u << 13 | u >> (32 - 13)
            u = x14 &+ x13
            x15 ^= u << 18 | u >> (32 - 18)
        }
        
        x0 &+= j0
        x1 &+= j1
        x2 &+= j2
        x3 &+= j3
        x4 &+= j4
        x5 &+= j5
        x6 &+= j6
        x7 &+= j7
        x8 &+= j8
        x9 &+= j9
        x10 &+= j10
        x11 &+= j11
        x12 &+= j12
        x13 &+= j13
        x14 &+= j14
        x15 &+= j15
        
        outtext[0] = x0
        outtext[1] = x1
        outtext[2] = x2
        outtext[3] = x3
        outtext[4] = x4
        outtext[5] = x5
        outtext[6] = x6
        outtext[7] = x7
        outtext[8] = x8
        outtext[9] = x9
        outtext[10] = x10
        outtext[11] = x11
        outtext[12] = x12
        outtext[13] = x13
        outtext[14] = x14
        outtext[15] = x15
    }
    
    class func XORKeyStream(output: UnsafeMutableBufferPointer<UInt8>, input: UnsafeBufferPointer<UInt8>, counter: [UInt8], key: [UInt8]) {
        guard key.count == 32 else {
            return
        }
        guard counter.count == 16 else {
            return
        }

        var inCounter = counter
        var offset = 0
        while input.count - offset >= 64 {
            guard let block = SalaCore(input: inCounter, k: key, c: Sigma) else {
                return
            }
            for i in 0..<64 {
                output[offset+i] = block[i] ^ input[offset+i]
            }
            
            var u: UInt32 = 1
            for i in 8..<16 {
                u += UInt32(inCounter[i])
                inCounter[i] = UInt8(u & 0xff)
                u >>= 8
            }
            
            offset += 64
        }
        if input.count - offset > 0 {
            guard let block = SalaCore(input: inCounter, k: key, c: Sigma) else {
                return
            }
            for i in 0..<input.count - offset {
                output[offset+i] = block[i] ^ input[offset+i]
            }
        }
    }
    
    class func setup(nonce: [UInt8], key: [UInt8]) -> ([UInt8], [UInt8])? {
        guard nonce.count == 24 else {
            return nil
        }
        guard key.count == 32 else {
            return nil
        }
        
        guard let subkey = HSala20(input: Array(nonce[0..<16]), k: key, c: Sigma) else {
            return nil
        }
        var counter = [UInt8](repeating: 0, count: 16)
        counter.replaceSubrange(0..<8, with: nonce[16..<24])
        return (subkey, counter)
    }

    class func seal(message: Data, nonce: [UInt8], key: [UInt8]) -> Data? {
        let msg = [UInt8](message)
        guard nonce.count == 24 else {
            return nil
        }
        guard key.count == 32 else {
            return nil
        }
        
        guard let (subkey, counter) = setup(nonce: nonce, key: key) else {
            return nil
        }

        let zeroInput = [UInt8](repeating: 0, count: 64)
        var firstBlock = [UInt8](repeating: 0, count: 64)
        var out = [UInt8](repeating: 0, count: Poly1305.TagSize+msg.count)
        out.withUnsafeMutableBufferPointer { outBuf in
            msg.withUnsafeBufferPointer { msgBuf in
                firstBlock.withUnsafeMutableBufferPointer { firstBuf in
                    zeroInput.withUnsafeBufferPointer { zeroBuf in
                        XORKeyStream(output: firstBuf, input: zeroBuf, counter: counter, key: subkey)
                        
                        let poly1305Key = UnsafeBufferPointer(rebasing: firstBuf[0..<32])
                        let firstMessageBlock: UnsafeBufferPointer<UInt8>
                        if msgBuf.count < 32 {
                            firstMessageBlock = msgBuf
                        }
                        else {
                            firstMessageBlock = UnsafeBufferPointer(rebasing: msgBuf[0..<32])
                        }
                        
                        for i in 0..<firstMessageBlock.count {
                            outBuf[i+Poly1305.TagSize] = firstBuf[i+32] ^ firstMessageBlock[i]
                        }

                        if msgBuf.count > 32 {
                            var counter2 = counter
                            counter2[8] = 1
                            XORKeyStream(output: UnsafeMutableBufferPointer(rebasing: outBuf[Poly1305.TagSize+firstMessageBlock.count..<outBuf.count]), input: UnsafeBufferPointer(rebasing: msgBuf[32..<message.count]), counter: counter2, key: subkey)
                        }

                        Poly1305.poly1305(tag: UnsafeMutableBufferPointer(rebasing: outBuf[0..<Poly1305.TagSize]), msg: UnsafeBufferPointer(rebasing: outBuf[Poly1305.TagSize..<outBuf.count]), key: poly1305Key)
                    }
                }
            }
        }
        return Data(out)
    }
    
    class func open(box: Data, nonce: [UInt8], key: [UInt8]) -> Data? {
        let boxmsg = [UInt8](box)
        guard nonce.count == 24 else {
            print("nonce error")
            return nil
        }
        guard key.count == 32 else {
            print("key error")
            return nil
        }
        
        guard let (subkey, counter) = setup(nonce: nonce, key: key) else {
            print("setup error")
            return nil
        }

        let zeroInput = [UInt8](repeating: 0, count: 64)
        var firstBlock = [UInt8](repeating: 0, count: 64)
        var out = [UInt8](repeating: 0, count: boxmsg.count - Poly1305.TagSize)
        guard out.withUnsafeMutableBufferPointer({ outBuf in
            boxmsg.withUnsafeBufferPointer() { msgBuf in
                firstBlock.withUnsafeMutableBufferPointer() { firstBuf in
                    zeroInput.withUnsafeBufferPointer() { zeroBuf in
                        XORKeyStream(output: firstBuf, input: zeroBuf, counter: counter, key: subkey)
                        
                        let poly1305Key = UnsafeBufferPointer(rebasing: firstBuf[0..<32])
                        let tag = UnsafeBufferPointer(rebasing: msgBuf[0..<Poly1305.TagSize])
                        let boxBody = UnsafeBufferPointer(rebasing: msgBuf[Poly1305.TagSize..<msgBuf.count])
              
                        guard Poly1305.Verify(mac: tag, msg: boxBody, key: poly1305Key) else {
                            print("verify error")
                            return false
                        }
                        
                        let firstMessageBlock: UnsafeBufferPointer<UInt8>
                        if msgBuf.count < 32 {
                            firstMessageBlock = boxBody
                        }
                        else {
                            firstMessageBlock = UnsafeBufferPointer(rebasing: boxBody[0..<32])
                        }

                        for i in 0..<firstMessageBlock.count {
                            outBuf[i] = firstBuf[i+32] ^ firstMessageBlock[i]
                        }
                        
                        if boxBody.count > 32 {
                            var counter2 = counter
                            counter2[8] = 1
                            XORKeyStream(output: UnsafeMutableBufferPointer(rebasing: outBuf[firstMessageBlock.count..<outBuf.count]), input: UnsafeBufferPointer(rebasing: boxBody[32..<boxBody.count]), counter: counter2, key: subkey)
                        }
                        return true
                    }
                }
            }
        }) else {
            return nil
        }
        return Data(out)
    }
}

class SCrypt {
    class func ComputeDerivedKey(key: [UInt8], salt: [UInt8], cost: Int, blockSize: Int, derivedKeyLength: Int) -> [UInt8] {
        let B = MFcrypt(P: key, S: salt, cost: cost, blockSize: blockSize)
        return pbkdf2.ComputeDerivedKey(key: key, salt: B, iterations: 1, derivedKeyLength: derivedKeyLength)
    }
    
    class func MFcrypt(P: [UInt8], S: [UInt8], cost: Int, blockSize: Int) -> [UInt8] {
        let MFLen = blockSize * 128
        
        var B = pbkdf2.ComputeDerivedKey(key: P, salt: S, iterations: 1, derivedKeyLength: MFLen)
        B.withUnsafeMutableBytes { bByte in
            let B32 = bByte.bindMemory(to: UInt32.self)
            SMix(B: B32, N: UInt32(cost), r: blockSize)
        }
        return B
    }
    
    class func SMix(B: UnsafeMutableBufferPointer<UInt32>, N: UInt32, r: Int) {
        let Nmask = N - 1
        let Bs = 16 * 2 * r
        
        var v = (0..<Int(N)).map { _ in UnsafeMutableBufferPointer<UInt32>.allocate(capacity: Bs) }
        let x = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: Bs)
        let sc1 = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: 16)
        let scx = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: 16)
        let scy = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: Bs)
        let scz = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: Bs)
        for j in 0..<Bs {
            x[j] = B[j]
        }
        for i in 0..<Int(N) {
            for j in 0..<Bs {
                v[i][j] = x[j]
            }
            BlockMix(B: x, Bp: x, r: r, x: scx, y: scy, sc: sc1)
        }
        for _ in 0..<Int(N) {
            let j = x[Bs - 16] & Nmask
            let vj = v[Int(j)]
            for k in 0..<Bs {
                scz[k] = x[k] ^ vj[k]
            }
            BlockMix(B: scz, Bp: x, r: r, x: scx, y: scy, sc: sc1)
        }
        for j in 0..<Bs {
            B[j] = x[j]
        }
    }
    
    class func BlockMix(B: UnsafeMutableBufferPointer<UInt32>, Bp: UnsafeMutableBufferPointer<UInt32>, r: Int, x: UnsafeMutableBufferPointer<UInt32>, y: UnsafeMutableBufferPointer<UInt32>, sc: UnsafeMutableBufferPointer<UInt32>) {
        for i in 0..<16 {
            x[i] = B[(2 * r - 1) * 16 + i]
        }
        
        let n = 16 * r
        var k = 0
        var m = 0
        for _ in 0..<r {
            for i in 0..<sc.count {
                sc[i] = B[k+i] ^ x[i]
            }
            Secretbox.SalaCore208(intext: sc, outtext: x)
            for i in 0..<16 {
                y[m+i] = x[i]
            }
            k += 16
            
            for i in 0..<sc.count {
                sc[i] = B[k+i] ^ x[i]
            }
            Secretbox.SalaCore208(intext: sc, outtext: x)
            for i in 0..<16 {
                y[m+n+i] = x[i]
            }
            k += 16
            m += 16
        }
        for i in 0..<y.count {
            Bp[i] = y[i]
        }
    }
    
    class pbkdf2 {
        var key: [UInt8]
        var salt: [UInt8]
        var iterations: Int
        
        init(key: [UInt8], salt: [UInt8], iterations: Int) {
            self.key = key
            self.salt = [UInt8](repeating: 0, count: salt.count+4)
            self.salt.replaceSubrange(0..<salt.count, with: salt)
            self.iterations = iterations
        }
        
        func ComputeBlock(pos: UInt32) -> [UInt8] {
            var p = pos.bigEndian
            let d = Data(bytes: &p, count: MemoryLayout.size(ofValue: p))
            salt.replaceSubrange(salt.count-4..<salt.count, with: d)
            var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), &key, key.count, &salt, salt.count, &result)
            var result_T1 = result
            for _ in 1..<iterations {
                var result_T2 = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), &key, key.count, &result_T1, result_T1.count, &result_T2)
                result_T1 = result_T2
                result = zip(result, result_T1).map { $0 ^ $1 }
            }
            return result
        }
        
        func read(len: Int) -> [UInt8] {
            var result = [UInt8](repeating: 0, count: len)
            var offset = 0
            var pos: UInt32 = 0
            while offset < len {
                pos += 1
                var buf = ComputeBlock(pos: pos)
                var l = len - offset
                if l > buf.count {
                    l = buf.count
                }
                result.replaceSubrange(offset..<offset+l, with: buf[0..<l])
                offset += l
            }
            return result
        }
        
        class func ComputeDerivedKey(key: [UInt8], salt: [UInt8], iterations: Int, derivedKeyLength: Int) -> [UInt8] {
            let pdkdf = pbkdf2(key: key, salt: salt, iterations: iterations)
            return pdkdf.read(len: derivedKeyLength)
        }
    }
}

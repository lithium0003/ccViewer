//
//  CryptCarotDAV.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/03/13.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CommonCrypto

class ViewControllerPasswordCarot: UIViewController, UITextFieldDelegate, UIPickerViewDelegate, UIPickerViewDataSource {
    var textPassword: UITextField!
    var stackView: UIStackView!
    let header = ["^_",":D",";)","T-T","orz","ノシ","（´・ω・）"]
    var header_selection = 0
    var filenameEncryption: Bool = false
    
    var onCancel: (()->Void)!
    var onFinish: ((String, String, Bool)->Void)!
    var done: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "CryptCarotDAV password"
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
        
        let stackView2 = UIStackView()
        stackView2.axis = .horizontal
        stackView2.alignment = .center
        stackView2.spacing = 20
        stackView.insertArrangedSubview(stackView2, at: 1)

        let label2 = UILabel()
        label2.text = "Encrypt filename"
        stackView2.insertArrangedSubview(label2, at: 0)
        
        let switchHidename = UISwitch()
        switchHidename.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
        filenameEncryption = switchHidename.isOn
        stackView2.insertArrangedSubview(switchHidename, at: 1)

        let stackView3 = UIStackView()
        stackView3.axis = .horizontal
        stackView3.alignment = .center
        stackView3.spacing = 20
        stackView.insertArrangedSubview(stackView3, at: 2)
        
        let label3 = UILabel()
        label3.text = "Encrypted header"
        stackView3.insertArrangedSubview(label3, at: 0)
        
        let picker = UIPickerView()
        picker.delegate = self
        picker.widthAnchor.constraint(equalToConstant: 150).isActive = true
        picker.heightAnchor.constraint(equalToConstant: 100).isActive = true
        stackView3.insertArrangedSubview(picker, at: 1)
        
        (stackView.arrangedSubviews[2]).isHidden = !switchHidename.isOn
        
        let stackView4 = UIStackView()
        stackView4.axis = .horizontal
        stackView4.alignment = .center
        stackView4.spacing = 20
        stackView.insertArrangedSubview(stackView4, at: 3)
        
        let button1 = UIButton(type: .system)
        button1.setTitle("Done", for: .normal)
        button1.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView4.insertArrangedSubview(button1, at: 0)

        let button2 = UIButton(type: .system)
        button2.setTitle("Cancel", for: .normal)
        button2.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView4.insertArrangedSubview(button2, at: 1)
    }
    
    @objc func buttonEvent(_ sender: UIButton) {
        if sender.currentTitle == "Done" {
            done = true
            onFinish(textPassword.text ?? "", header[header_selection], filenameEncryption)
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
        onFinish(textPassword.text ?? "", header[header_selection], filenameEncryption)
        return true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if textPassword.isFirstResponder {
            textPassword.resignFirstResponder()
        }
    }
    
    @objc func switchValueChanged(aSwitch: UISwitch) {
        (stackView.arrangedSubviews[2]).isHidden = !aSwitch.isOn
        filenameEncryption = aSwitch.isOn
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return header.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return header[row]
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        header_selection = row
    }
}

extension UIApplication {
    class func topViewController(controller: UIViewController? = nil) -> UIViewController? {
        var controller2 = controller
        if controller2 == nil {
            controller2 = UIApplication.shared.windows.first { $0.isKeyWindow }?.rootViewController
        }
        if let navigationController = controller2 as? UINavigationController {
            return topViewController(controller: navigationController.visibleViewController)
        }
        if let tabController = controller2 as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return topViewController(controller: selected)
            }
        }
        if let presented = controller2?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller2
    }
}

public class CryptCarotDAV: ChildStorage {
    fileprivate let salt = "CarotDAV Encryption 1.0 ".data(using: .ascii)!
    fileprivate var key: Data!
    fileprivate var IV: Data!
    private var header_str: String!
    
    public override func getStorageType() -> CloudStorages {
        return .CryptCarotDAV
    }

    public override init(name: String) {
        super.init(name: name)
        service = CloudFactory.getServiceName(service: .CryptCarotDAV)
        storageName = name
        if self.getKeyChain(key: "\(self.storageName ?? "")_password") != nil && self.getKeyChain(key: "\(self.storageName ?? "")_header") != nil {
            generateKey()
        }
    }
    
    override public func auth(onFinish: ((Bool) -> Void)?) -> Void {
        super.auth() { success in
            if success {
                if self.getKeyChain(key: "\(self.storageName ?? "")_password") != nil && self.getKeyChain(key: "\(self.storageName ?? "")_header") != nil {
                    DispatchQueue.global().async {
                        self.generateKey()
                        onFinish?(true)
                    }
                    return
                }
                DispatchQueue.main.async {
                    if let controller = UIApplication.topViewController() {
                        let passwordView = ViewControllerPasswordCarot()
                        passwordView.onCancel = {
                            onFinish?(false)
                        }
                        passwordView.onFinish = { pass, head, cfname in
                            let _ = self.setKeyChain(key: "\(self.storageName ?? "")_password", value: pass)
                            let _ = self.setKeyChain(key: "\(self.storageName ?? "")_header", value: head)
                            if cfname {
                                let _ = self.setKeyChain(key: "\(self.storageName ?? "")_cryptname", value: "true")
                            }
                            
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
            let _ = delKeyChain(key: "\(name)_header")
            let _ = delKeyChain(key: "\(name)_cryptname")
        }
        super.logout()
    }

    override func ConvertDecryptName(name: String) -> String {
        if let orignal = decryptFilename(input: name) {
            return orignal
        }
        return name
    }
    
    override func ConvertEncryptName(name: String, folder: Bool) -> String {
        return encryptFilename(input: name)
    }
    
    override func ConvertDecryptSize(size: Int64) -> Int64 {
        return size - Int64(BlockSizeByte + CryptHeaderByte + CryptFooterByte)
    }
    
    override func ConvertEncryptSize(size: Int64) -> Int64 {
        return size + Int64(BlockSizeByte + CryptFooterByte + CryptFooterByte)
    }
    
    let BlockSize = 128
    let BlockSizeByte = 128/8
    let KeySize = 256
    let CryptHeaderByte = 64
    let CryptFooterByte = 64
    
    func pbkdf2(password: String, salt: Data, iterations: UInt32) -> Data {
        let hashedcount = (BlockSize+KeySize)/8
        var hashed = Data(count: hashedcount)
        let saltBuffer = [UInt8](salt)
        
        let result = hashed.withUnsafeMutableBytes { (body: UnsafeMutableRawBufferPointer) -> Int32 in
            if let baseAddress = body.baseAddress, body.count > 0 {
                let data = baseAddress.assumingMemoryBound(to: UInt8.self)
                return CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                 password, password.count,
                                 saltBuffer, saltBuffer.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                                 iterations,
                                 data, hashedcount)
            }
            return Int32(kCCMemoryFailure)
        }
        
        guard result == kCCSuccess else { fatalError("pbkdf2 error") }
        
        return hashed
    }
    
    func generateKey() {
        let password = getKeyChain(key: "\(self.storageName ?? "")_password") ?? ""
        header_str = getKeyChain(key: "\(self.storageName ?? "")_header") ?? ""
        let key = pbkdf2(password: password, salt: salt, iterations: 0x400)
        self.key = key.subdata(in: 0..<KeySize/8)
        self.IV = key.subdata(in: KeySize/8..<(KeySize+BlockSize)/8)
    }
    
    func encryptFilename(input: String) -> String {
        let plain = input.data(using: .utf8)!
        var padplain = plain
        padplain.append(Data(count: BlockSizeByte - (plain.count % BlockSizeByte)))
        var outLength = Int(0)
        var outBytes = [UInt8](repeating: 0, count: padplain.count + kCCBlockSizeAES128)
        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
        padplain.withUnsafeBytes { (plainBytes: UnsafeRawBufferPointer)->Void in
            IV.withUnsafeBytes { (ivBytes: UnsafeRawBufferPointer)->Void in
                key.withUnsafeBytes { (keyBytes: UnsafeRawBufferPointer)->Void in
                    status = CCCrypt(CCOperation(kCCEncrypt),
                                     CCAlgorithm(kCCAlgorithmAES),
                                     0,
                                     keyBytes.bindMemory(to: UInt8.self).baseAddress,
                                     key.count,
                                     ivBytes.bindMemory(to: UInt8.self).baseAddress,
                                     plainBytes.bindMemory(to: UInt8.self).baseAddress,
                                     padplain.count,
                                     &outBytes,
                                     outBytes.count,
                                     &outLength)
                }
            }
        }
 
        guard status == kCCSuccess else {
            return ""
        }
        var encrypted = Data(bytes: UnsafePointer<UInt8>(outBytes), count: outLength)
        if encrypted.count >= BlockSizeByte * 2 {
            let pos = encrypted.count - BlockSizeByte * 2
            let cryptbuf1 = encrypted.subdata(in: pos..<pos+BlockSizeByte)
            let cryptbuf2 = encrypted.subdata(in: pos+BlockSizeByte..<pos+BlockSizeByte*2)
            let lastlen = plain.count % BlockSizeByte
            let lastblock: Data
            if lastlen == 0 {
                lastblock = cryptbuf1
            }
            else {
                lastblock = cryptbuf1.subdata(in: 0..<lastlen)
            }
            encrypted = encrypted.subdata(in: 0..<pos)
            encrypted.append(cryptbuf2)
            encrypted.append(lastblock)
        }
        var base64 = encrypted.base64EncodedString()
        base64 = base64.replacingOccurrences(of: "+", with: "_")
        base64 = base64.replacingOccurrences(of: "/", with: "-")
        base64 = base64.replacingOccurrences(of: "=", with: "")
        return header_str + base64
    }
    
    func decryptFilename(input: String) -> String? {
        if !input.hasPrefix(header_str) {
            return nil
        }
        var base64 = String(input.suffix(input.count - header_str.count))
        base64 = base64.replacingOccurrences(of: "_", with: "+")
        base64 = base64.replacingOccurrences(of: "-", with: "/")
        switch base64.count % 4 {
        case 0:
            break
        case 1:
            base64 += "==="
        case 2:
            base64 += "=="
        case 3:
            base64 += "="
        default:
            break
        }
        guard var crypt = Data(base64Encoded: base64) else {
            return nil
        }
        
        if crypt.count > BlockSizeByte {
            let lastlen = (crypt.count - 1) % BlockSizeByte + 1
            let pos = crypt.count - BlockSizeByte - lastlen
            let cryptbuf2 = crypt.subdata(in: pos..<pos+BlockSizeByte)
            let lastblock = crypt.subdata(in: pos+BlockSizeByte..<crypt.count)
            
            var outLength = Int(0)
            var outBytes = [UInt8](repeating: 0, count: cryptbuf2.count)
            var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
            cryptbuf2.withUnsafeBytes { (cryptBytes: UnsafeRawBufferPointer)->Void in
                key.withUnsafeBytes { (keyBytes: UnsafeRawBufferPointer)->Void in
                    status = CCCrypt(CCOperation(kCCDecrypt),
                                     CCAlgorithm(kCCAlgorithmAES),
                                     CCOptions(kCCOptionECBMode),
                                     keyBytes.bindMemory(to: UInt8.self).baseAddress,
                                     key.count,
                                     nil,
                                     cryptBytes.bindMemory(to: UInt8.self).baseAddress,
                                     cryptbuf2.count,
                                     &outBytes,
                                     outBytes.count,
                                     &outLength)
                }
            }
            guard status == kCCSuccess else {
                return nil
            }
            var cryptbuf1 = Data(bytes: UnsafePointer<UInt8>(outBytes), count: outLength)
            cryptbuf1.replaceSubrange(0..<lastblock.count, with: lastblock)
            crypt = crypt.subdata(in: 0..<pos)
            crypt.append(cryptbuf1)
            crypt.append(cryptbuf2)
        }
        
        var outLength = Int(0)
        var outBytes = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
        crypt.withUnsafeBytes { (cryptBytes: UnsafeRawBufferPointer)->Void in
            IV.withUnsafeBytes { (ivBytes: UnsafeRawBufferPointer)->Void in
                key.withUnsafeBytes { (keyBytes: UnsafeRawBufferPointer)->Void in
                    status = CCCrypt(CCOperation(kCCDecrypt),
                                     CCAlgorithm(kCCAlgorithmAES),
                                     0,
                                     keyBytes.bindMemory(to: UInt8.self).baseAddress,
                                     key.count,
                                     ivBytes.bindMemory(to: UInt8.self).baseAddress,
                                     cryptBytes.bindMemory(to: UInt8.self).baseAddress,
                                     crypt.count,
                                     &outBytes,
                                     outBytes.count,
                                     &outLength)
                }
            }
        }
        guard status == kCCSuccess else {
            return nil
        }
        let plain = Data(bytes: UnsafePointer<UInt8>(outBytes), count: outLength)
        return String(data: plain, encoding: .utf8)?.replacingOccurrences(of: "\0", with: "")
    }
    
    public override func getRaw(fileId: String) -> RemoteItem? {
        return CryptCarotDAVRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) -> RemoteItem? {
        return CryptCarotDAVRemoteItem(path: path)
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
        
        // header
        var header = [UInt8](repeating: 0, count: CryptHeaderByte)
        header.replaceSubrange(0..<salt.count, with: salt)
        
        guard header.count == output.write(&header, maxLength: header.count) else {
            return nil
        }

        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)
        
        // body
        var buffer = [UInt8](repeating: 0, count: 1*1024*1024)
        var outBytes = [UInt8](repeating: 0, count: buffer.count + kCCBlockSizeAES128)
        var keybuf = [UInt8](key)
        var ivbuf = [UInt8](IV)
        var len = 0
        var bodylen = 0
        repeat {
            len = input.read(&buffer, maxLength: buffer.count)
            if len < 0 {
                print(input.streamError ?? "")
                return nil
            }
            bodylen += len
            
            var cryptlen = len
            if len % BlockSizeByte != 0 {
                let pad = [UInt8](repeating: 0, count: BlockSizeByte - len % BlockSizeByte)
                buffer.replaceSubrange(len..<len+pad.count, with: pad)
                cryptlen += pad.count
            }
            
            CC_SHA256_Update(&context, &buffer, CC_LONG(len))
            var outLength = Int(0)
            let status = CCCrypt(CCOperation(kCCEncrypt),
                                 CCAlgorithm(kCCAlgorithmAES),
                                 0,
                                 &keybuf,
                                 keybuf.count,
                                 &ivbuf,
                                 &buffer,
                                 cryptlen,
                                 &outBytes,
                                 outBytes.count,
                                 &outLength)
            guard status == kCCSuccess else {
                print(status)
                return nil
            }
            ivbuf.replaceSubrange(0..<ivbuf.count, with: outBytes[outLength-ivbuf.count..<outLength])
            
            guard outLength == output.write(&outBytes, maxLength: outLength) else {
                return nil
            }
        } while len == buffer.count
        
        // padding
        var pad = [UInt8](repeating: 0, count: (bodylen - 1) % BlockSizeByte + 1)
        guard pad.count == output.write(&pad, maxLength: pad.count) else {
            return nil
        }

        // footer
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        var footer = [UInt8](digest.map({ String(format: "%02x", $0)}).joined().data(using: .ascii)!)
        guard footer.count == output.write(&footer, maxLength: footer.count) else {
            return nil
        }
        
        return crypttarget
    }
}


public class CryptCarotDAVRemoteItem: RemoteItem {
    let remoteStorage: CryptCarotDAV

    override init?(storage: String, id: String) {
        guard let s = CloudFactory.shared[storage] as? CryptCarotDAV else {
            return nil
        }
        remoteStorage = s
        super.init(storage: storage, id: id)
    }
    
    public override func open() -> RemoteStream {
        return RemoteCryptCarotDAVStream(remote: self)
    }
}

public class RemoteCryptCarotDAVStream: SlotStream {
    let remote: CryptCarotDAVRemoteItem
    let OrignalLength: Int64
    let CryptedLength: Int64
    let CryptBodyLength: Int64
    let salt: Data
    let key: Data
    let IV: Data
    
    init(remote: CryptCarotDAVRemoteItem) {
        self.remote = remote
        OrignalLength = remote.size
        CryptedLength = OrignalLength + Int64(remote.remoteStorage.BlockSizeByte) + Int64(remote.remoteStorage.CryptHeaderByte) + Int64(remote.remoteStorage.CryptFooterByte)
        CryptBodyLength = OrignalLength - ((OrignalLength - 1) % Int64(remote.remoteStorage.BlockSizeByte) + 1) + Int64(remote.remoteStorage.BlockSizeByte)
        salt = "CarotDAV Encryption 1.0 ".data(using: .ascii)!
        key = remote.remoteStorage.key
        IV = remote.remoteStorage.IV
        super.init(size: OrignalLength)
    }
    
    override func firstFill() {
        fillHeader()
        super.firstFill()
    }
    
    func fillHeader() {
        init_group.enter()
        remote.read(start: 0, length: Int64(remote.remoteStorage.CryptHeaderByte)) { data in
            if let data = data {
                if !self.salt.elementsEqual(data.subdata(in: 0..<self.salt.count)) {
                    print("error on header check")
                    self.error = true
                }
            }
            else {
                print("error on header null")
                self.error = true
            }
            self.init_group.leave()
        }
    }
    
    func decode(input: Data, IV: Data) -> Data? {
        var outLength = Int(0)
        var outBytes = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
        input.withUnsafeBytes { (cryptBytes: UnsafeRawBufferPointer)->Void in
            IV.withUnsafeBytes { (ivBytes: UnsafeRawBufferPointer)->Void in
                key.withUnsafeBytes { (keyBytes: UnsafeRawBufferPointer)->Void in
                    status = CCCrypt(CCOperation(kCCDecrypt),
                                     CCAlgorithm(kCCAlgorithmAES),
                                     0,
                                     keyBytes.bindMemory(to: UInt8.self).baseAddress,
                                     key.count,
                                     ivBytes.bindMemory(to: UInt8.self).baseAddress,
                                     cryptBytes.bindMemory(to: UInt8.self).baseAddress,
                                     input.count,
                                     &outBytes,
                                     outBytes.count,
                                     &outLength)
                }
            }
        }
        guard status == kCCSuccess else {
            return nil
        }
        return Data(bytes: UnsafePointer<UInt8>(outBytes), count: outLength)
    }
    
    override func subFillBuffer(pos1: Int64, onFinish: @escaping ()->Void) {
        guard init_group.wait(timeout: DispatchTime.now()+120) == DispatchTimeoutResult.success else {
            self.error = true
            onFinish()
            return
        }
        let blocksize = remote.remoteStorage.BlockSizeByte
        let headersize = Int64(remote.remoteStorage.CryptHeaderByte)
        let pos2 = pos1 + headersize
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
            //print("crypt \(pos1) -> \(pos2)")
            guard pos1 >= 0 && pos1 < size else {
                return
            }
            var len = (pos1 + bufSize < size) ? bufSize : size - pos1
            //print("pos1 \(pos1) size\(size) len \(len)")
            if len % Int64(blocksize) > 0 {
                len += Int64(blocksize)
                len -= len % Int64(blocksize)
            }
            let plen = len + Int64(blocksize)
            let ppos2 = pos2 - Int64(blocksize)
            if pos1 == 0 {
                //print("pos2 \(pos2) len \(len)")
                group.enter()
                self.remote.read(start: pos2, length: len) { data in
                    defer {
                        group.leave()
                    }
                    if let data = data {
                        DispatchQueue.global().async {
                            autoreleasepool {
                                if let plain = self.decode(input: data, IV: self.IV) {
                                    self.queue_buf.async {
                                        self.buffer[pos1] = plain
                                    }
                                }
                                else {
                                    print("error on decode1")
                                    self.error = true
                                }
                            }
                        }
                    }
                    else {
                        print("error on readFile")
                        self.error = true
                    }
                }
            }
            else {
                //print("ppos2 \(ppos2) len\(plen)")
                group.enter()
                self.remote.read(start: ppos2, length: plen) { data in
                    defer {
                        group.leave()
                    }
                    if let data = data, data.count == Int(plen) {
                        DispatchQueue.global().async {
                            if let plain = self.decode(input: data.subdata(in: blocksize..<data.count), IV: data.subdata(in: 0..<blocksize)) {
                                self.queue_buf.async {
                                    self.buffer[pos1] = plain
                                }
                            }
                            else {
                                print("ppos2 \(ppos2) len\(plen)")
                                print("error on decode2")
                                self.error = true
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
}


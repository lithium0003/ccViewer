//
//  CryptCarotDAV.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/03/13.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CommonCrypto
import SwiftUI
import AuthenticationServices

struct PasswordCarotView: View {
    let callback: (String, String, Bool) async -> Void
    let onDismiss: () -> Void
    @State var ok = false

    let header = ["^_",":D",";)","T-T","orz","ノシ","（´・ω・）"]
    @State var showPassword = false
    @State var password = ""
    @State var filenameEncryption = false
    @State var headerSelection = "^_"

    var body: some View {
        ZStack {
            Form {
                Text("CryptCarotDAV configuration")
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
                Section("Encrypt filename") {
                    Toggle("", isOn: $filenameEncryption)
                }
                Section("Prefix for filename") {
                    Picker("", selection: $headerSelection) {
                        ForEach(header, id: \.self) { str in
                            Text(verbatim: str)
                        }
                    }
                }
                .disabled(!filenameEncryption)
                Button("Select root folder") {
                    ok = true
                    Task {
                        await callback(password, headerSelection, filenameEncryption)
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

public class CryptCarotDAV: ChildStorage {
    fileprivate let salt = "CarotDAV Encryption 1.0 ".data(using: .ascii)!
    fileprivate var key: Data!
    fileprivate var IV: Data!
    private var header_str: String!
    
    public override func getStorageType() -> CloudStorages {
        return .CryptCarotDAV
    }

    public override init(name: String) async {
        await super.init(name: name)
        service = CloudFactory.getServiceName(service: .CryptCarotDAV)
        storageName = name
        if await getKeyChain(key: "\(storageName ?? "")_password") != nil, await getKeyChain(key: "\(storageName ?? "")_header") != nil {
            await generateKey()
        }
    }

    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {

        let authRet = await withCheckedContinuation { authContinuation in
            Task {
                let presentRet = await withCheckedContinuation { continuation in
                    callback(PasswordCarotView(callback: { pass, head, cfname in
                        if await super.auth(callback: callback, webAuthenticationSession: webAuthenticationSession, selectItem: selectItem) {
                            let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_password", value: pass)
                            let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_header", value: head)
                            if cfname {
                                let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_cryptname", value: "true")
                            }
                            await self.generateKey()
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
            let _ = await delKeyChain(key: "\(name)_header")
            let _ = await delKeyChain(key: "\(name)_cryptname")
        }
        await super.logout()
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
    
    func generateKey() async {
        let password = await getKeyChain(key: "\(self.storageName ?? "")_password") ?? ""
        header_str = await getKeyChain(key: "\(self.storageName ?? "")_header") ?? ""
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
        var encrypted = Data(bytes: outBytes, count: outLength)
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
            var cryptbuf1 = Data(bytes: outBytes, count: outLength)
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
        let plain = Data(bytes: outBytes, count: outLength)
        return String(data: plain, encoding: .utf8)?.replacingOccurrences(of: "\0", with: "")
    }
    
    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await CryptCarotDAVRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await CryptCarotDAVRemoteItem(path: path)
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

    override init?(storage: String, id: String) async {
        guard let s = await CloudFactory.shared.storageList.get(storage) as? CryptCarotDAV else {
            return nil
        }
        remoteStorage = s
        await super.init(storage: storage, id: id)
    }
    
    public override func open() async -> RemoteStream {
        return await RemoteCryptCarotDAVStream(remote: self)
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
    
    init(remote: CryptCarotDAVRemoteItem) async {
        self.remote = remote
        OrignalLength = remote.size
        CryptedLength = OrignalLength + Int64(remote.remoteStorage.BlockSizeByte) + Int64(remote.remoteStorage.CryptHeaderByte) + Int64(remote.remoteStorage.CryptFooterByte)
        CryptBodyLength = OrignalLength - ((OrignalLength - 1) % Int64(remote.remoteStorage.BlockSizeByte) + 1) + Int64(remote.remoteStorage.BlockSizeByte)
        salt = "CarotDAV Encryption 1.0 ".data(using: .ascii)!
        key = remote.remoteStorage.key
        IV = remote.remoteStorage.IV
        await super.init(size: OrignalLength)
    }

    override func fillHeader() async {
        if let data = try? await remote.read(start: 0, length: Int64(remote.remoteStorage.CryptHeaderByte)) {
            if !salt.elementsEqual(data.subdata(in: 0..<salt.count)) {
                print("error on header check")
                error = true
            }
        }
        else {
            print("error on header null")
            error = true
        }
        await super.fillHeader()
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
        return Data(bytes: outBytes, count: outLength)
    }
    
    override func subFillBuffer(pos: ClosedRange<Int64>) async {
        guard await initialized.wait(timeout: .seconds(10)) == .success else {
            error = true
            return
        }
        let blocksize = remote.remoteStorage.BlockSizeByte
        let headersize = Int64(remote.remoteStorage.CryptHeaderByte)
        let pos2 = pos.lowerBound + headersize
        if await !buffer.dataAvailable(pos: pos) {
            //print("crypt \(pos1) -> \(pos2)")
            guard pos.lowerBound >= 0 && pos.upperBound < size else {
                return
            }
            var len = min(size-1, pos.upperBound) - pos.lowerBound + 1
            //print("pos1 \(pos1) size\(size) len \(len)")
            if len % Int64(blocksize) > 0 {
                len += Int64(blocksize)
                len -= len % Int64(blocksize)
            }
            let plen = len + Int64(blocksize)
            let ppos2 = pos2 - Int64(blocksize)
            if pos.lowerBound == 0 {
                //print("pos2 \(pos2) len \(len)")
                if let data = try? await remote.read(start: pos2, length: len) {
                    if let plain = decode(input: data, IV: self.IV) {
                        await buffer.store(pos: pos.lowerBound, data: plain)
                    }
                    else {
                        print("error on decode1")
                        self.error = true
                    }
                }
                else {
                    print("error on readFile")
                    error = true
                }
            }
            else {
                //print("ppos2 \(ppos2) len\(plen)")
                if let data = try? await remote.read(start: ppos2, length: plen), data.count == Int(plen) {
                    if let plain = decode(input: data.subdata(in: blocksize..<data.count), IV: data.subdata(in: 0..<blocksize)) {
                        await buffer.store(pos: pos.lowerBound, data: plain)
                    }
                    else {
                        print("ppos2 \(ppos2) len\(plen)")
                        print("error on decode2")
                        error = true
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


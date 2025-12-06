//
//  CryptRclone.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/03/15.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CommonCrypto
import SwiftUI
import AuthenticationServices
internal import UniformTypeIdentifiers

struct PasswordRcloneView: View {
    let callback: (String, String, String, String, String) async -> Void
    let onDismiss: () -> Void
    @State var ok = false

    let filenameModes = ["standard", "obfuscation", "off"]
    let encodrdingModes = ["base32", "base64", "base32768"]

    @State var isPresented = false
    @State var isAlertPresented = false
    @State var isAlertPresented2 = false

    @State var confPassword = ""
    @State var box = Data()
    @State var crypt_config = [String: [String: String]]()
    
    @State var showPassword = false
    @State var showSalt = false

    @State var password = ""
    @State var passwordBitsStr = "128"
    @State var passwordBits = 128
    @State var salt = ""
    @State var saltBitsStr = "128"
    @State var saltBits = 128
    @State var filenameEncryption = "standard"
    @State var suffix = ".bin"
    @State var filenameEncodingMode = "base32"

    func processConf(url: URL) {
        var confstr: String?
        do {
            guard url.startAccessingSecurityScopedResource() else {
                return
            }
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            confstr = try? String(contentsOf: url, encoding: .utf8)
        }
        guard let confstr else {
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
            self.box = box
            isAlertPresented.toggle()
            return
        }
        processConfigFile(conflines: conflines)
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
                var password = ""
                var password2 = ""
                if let p = confItems["password"] {
                    password = p
                }
                if let p = confItems["password2"] {
                    password2 = p
                }
                crypt_config[confKey] = ["password": password, "password2": password2]
                if let filename_encoding = confItems["filename_encoding"] {
                    crypt_config[confKey]?["filename_encoding"] = filename_encoding
                }
                if let filename_encryption = confItems["filename_encryption"] {
                    crypt_config[confKey]?["filename_encryption"] = filename_encryption
                }
                if let suffix = confItems["suffix"] {
                    crypt_config[confKey]?["suffix"] = suffix
                }
            }
        }
        self.crypt_config = crypt_config
        isAlertPresented2.toggle()
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
        switch ciphertext_stdbase64.count % 4 {
        case 0:
            break
        case 1:
            return nil
        case 2:
            ciphertext_stdbase64.append(contentsOf: String(repeating: "=", count: 2))
        case 3:
            ciphertext_stdbase64.append(contentsOf: String(repeating: "=", count: 1))
        default:
            break
        }
        //print(ciphertext_stdbase64)
        guard let cipher = Data(base64Encoded: ciphertext_stdbase64) else {
            return nil
        }
        //print(cipher)
        guard cipher.count >= 16 else {
            return ciphertext
        }
        let buffer = cipher.subdata(in: 16..<cipher.count)
        let iv = cipher.subdata(in: 0..<16)
        guard let plain = try? AesCtr.compute(key: key, iv: [UInt8](iv), data: [UInt8](buffer)) else {
            return ciphertext
        }
        return String(bytes: plain, encoding: .utf8)
    }

    var body: some View {
        ZStack {
            Form {
                Text("CryptRclone configuration")
                Button("Load config from file") {
                    isPresented.toggle()
                }
                .buttonStyle(.borderedProminent)
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
                    HStack {
                        Text("Random bits")
                        TextField("", text: $passwordBitsStr)
                            .frame(maxWidth: 100)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                passwordBits = Int(passwordBitsStr) ?? passwordBits
                                if passwordBits < 64 {
                                    passwordBits = 64
                                }
                                if passwordBits > 1024 {
                                    passwordBits = 1024
                                }
                                passwordBitsStr = String(passwordBits)
                            }
                        Spacer()
                        Button("Random generate") {
                            passwordBits = Int(passwordBitsStr) ?? passwordBits
                            if passwordBits < 64 {
                                passwordBits = 64
                            }
                            if passwordBits > 1024 {
                                passwordBits = 1024
                            }
                            passwordBitsStr = String(passwordBits)

                            var count = passwordBits / 8
                            if passwordBits % 8 != 0 {
                                count += 1
                            }
                            var data = Data(count: count)
                            let status = data.withUnsafeMutableBytes { body in
                                SecRandomCopyBytes(kSecRandomDefault, count, body.baseAddress!)
                            }
                            if status == errSecSuccess {
                                password = data.base64EncodedString().replacing("+", with: "-").replacing("/", with: "_").replacing("=", with: "")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Section("Password2") {
                    HStack {
                        if showSalt {
                            TextField("salt", text: $salt)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        }
                        else {
                            SecureField("salt", text: $salt)
                        }
                        Button {
                            showSalt.toggle()
                        } label: {
                            if showSalt {
                                Image(systemName: "eye.slash")
                            }
                            else {
                                Image(systemName: "eye")
                                    .tint(.gray)

                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    HStack {
                        Text("Random bits")
                        TextField("", text: $saltBitsStr)
                            .frame(maxWidth: 100)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                saltBits = Int(saltBitsStr) ?? saltBits
                                if saltBits < 64 {
                                    saltBits = 64
                                }
                                if saltBits > 1024 {
                                    saltBits = 1024
                                }
                                saltBitsStr = String(saltBits)
                            }
                        Spacer()
                        Button("Random generate") {
                            saltBits = Int(saltBitsStr) ?? saltBits
                            if saltBits < 64 {
                                saltBits = 64
                            }
                            if saltBits > 1024 {
                                saltBits = 1024
                            }
                            saltBitsStr = String(saltBits)

                            var count = saltBits / 8
                            if saltBits % 8 != 0 {
                                count += 1
                            }
                            var data = Data(count: count)
                            let status = data.withUnsafeMutableBytes { body in
                                SecRandomCopyBytes(kSecRandomDefault, count, body.baseAddress!)
                            }
                            if status == errSecSuccess {
                                salt = data.base64EncodedString().replacing("+", with: "-").replacing("/", with: "_").replacing("=", with: "")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Section("Encrypt filename") {
                    Picker("Filename encrypt mode", selection: $filenameEncryption) {
                        ForEach(filenameModes, id: \.self) { str in
                            Text(str)
                        }
                    }
                    HStack {
                        Text("Filename suffix")
                        Spacer()
                        TextField("suffix", text: $suffix)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .frame(maxWidth: 100)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                    }
                    .disabled(filenameEncryption != "off")
                    Picker("Filename encoding", selection: $filenameEncodingMode) {
                        ForEach(encodrdingModes, id: \.self) { str in
                            Text(str)
                        }
                    }
                    .disabled(filenameEncryption != "standard")
                }
                Button("Select root folder") {
                    ok = true
                    Task {
                        await callback(password, salt, filenameEncryption, suffix, filenameEncodingMode)
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
        .alert("Encrypt config file", isPresented: $isAlertPresented) {
            SecureField("password", text: $confPassword)

            Button("Cancel", role: .cancel) {
                isAlertPresented = false
            }
            Button("OK", role: .confirm) {
                isAlertPresented = false
                Task {
                    await Task.yield()
                    let data = Array("[\(confPassword)][rclone-config]".utf8)
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
                    processConfigFile(conflines: plain.components(separatedBy: .newlines))
                }
            }
        }
        .alert("Encrypt config file", isPresented: $isAlertPresented2) {
            ForEach(crypt_config.keys.sorted(), id: \.self) { name in
                if let confItems = crypt_config[name] {
                    Button(name, role: .confirm) {
                        isAlertPresented2 = false
                        password = reveal(ciphertext: confItems["password"] ?? "") ?? ""
                        salt = reveal(ciphertext: confItems["password2"] ?? "") ?? ""
                        filenameEncryption = confItems["filename_encryption"] ?? filenameModes[0]
                        suffix = confItems["suffix"] ?? ".bin"
                        filenameEncodingMode = confItems["filename_encoding"] ?? "base32"
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                isAlertPresented2 = false
            }
        }
        .fileImporter(isPresented: $isPresented, allowedContentTypes: [UTType(filenameExtension: "conf")!]) { result in
            switch result {
            case .success(let url):
                processConf(url: url)
            case .failure(let error):
                print(error)
            }
        }
        .onDisappear {
            if ok { return }
            onDismiss()
        }
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
    let defaultSuffix = ".bin"

    var dataKey = [UInt8](repeating: 0, count: 32)
    var nameKey = [UInt8](repeating: 0, count: 32)
    var nameTweak = [UInt8](repeating: 0, count: 16)
    
    let encodeMap = Array("0123456789ABCDEFGHIJKLMNOPQRSTUV")
    let decodeMap: [Character: Int]
    
    enum NameEncryptionMode {
        case standard
        case obfuscated
        case off
    }
    enum NameEncodeMode {
        case base32
        case base64
        case base32768
    }

    var name_aes: AES_EME?
    var name_cryptmode = NameEncryptionMode.standard
    var name_encodemode = NameEncodeMode.base32
    var name_suffix: String = ".bin"
    
    override public init(name: String) async {
        var m: [Character: Int] = [:]
        encodeMap.enumerated().forEach { i, c in
            m[c] = i
        }
        m["="] = 0
        decodeMap = m

        await super.init(name: name)
        service = CloudFactory.getServiceName(service: .CryptRclone)
        storageName = name
        if await getKeyChain(key: "\(storageName ?? "")_password") != nil, await getKeyChain(key: "\(storageName ?? "")_salt") != nil {
            await generateKey()
        }
    }

    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        let authRet = await withCheckedContinuation { authContinuation in
            Task {
                let presentRet = await withCheckedContinuation { continuation in
                    callback(PasswordRcloneView(callback: { password, salt, filenameEncryption, suffix, filenameEncodingMode in
                        if await super.auth(callback: callback, webAuthenticationSession: webAuthenticationSession, selectItem: selectItem) {
                            
                            let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_password", value: password)
                            let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_salt", value: salt)
                            let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_suffix", value: suffix)
                            let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_namecryptmode", value: filenameEncryption)
                            let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_nameencode", value: filenameEncodingMode)
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
            let _ = await delKeyChain(key: "\(name)_salt")
            let _ = await delKeyChain(key: "\(name)_suffix")
            let _ = await delKeyChain(key: "\(name)_cryptname")
            let _ = await delKeyChain(key: "\(name)_obfuscation")
            let _ = await delKeyChain(key: "\(name)_namecryptmode")
            let _ = await delKeyChain(key: "\(name)_nameencode")
        }
        await super.logout()
    }
    
    @concurrent
    func generateKey() async {
        if let b = await getKeyChain(key: "\(storageName ?? "")_cryptname"), b == "true" {
            name_cryptmode = .standard
        }
        else {
            name_cryptmode = .off
        }
        if let b = await getKeyChain(key: "\(storageName ?? "")_obfuscation"), b == "true" {
            name_cryptmode = .obfuscated
        }
        if let s = await getKeyChain(key: "\(storageName ?? "")_suffix"), s != "" {
            name_suffix = "."+s
        }
        else {
            name_suffix = defaultSuffix
        }
        if let s = await getKeyChain(key: "\(storageName ?? "")_namecryptmode"), s != "" {
            if s == "standard" {
                name_cryptmode = .standard
            }
            else if s == "obfuscation" {
                name_cryptmode = .obfuscated
            }
            else if s == "off" {
                name_cryptmode = .off
            }
        }
        if let s = await getKeyChain(key: "\(storageName ?? "")_nameencode"), s != "" {
            if s == "base32" {
                name_encodemode = .base32
            }
            else if s == "base64" {
                name_encodemode = .base64
            }
            else if s == "base32768" {
                name_encodemode = .base32768
            }
        }

        let password = await getKeyChain(key: "\(storageName ?? "")_password") ?? ""
        let salt: Data
        if let saltstr = await getKeyChain(key: "\(storageName ?? "")_salt"), saltstr != "" {
            salt = saltstr.data(using: .utf8)!
        }
        else {
            salt = defaultSalt
        }
        
        let keysize = dataKey.count + nameKey.count + nameTweak.count
        var key = [UInt8](repeating: 0, count: keysize)
        if password != "" {
            key = SCrypt.ComputeDerivedKey(key: [UInt8](password.data(using: .utf8)!), salt: [UInt8](salt), cost: 16384, blockSize: 8, derivedKeyLength: keysize)
        }
        dataKey = Array(key[0..<32])
        nameKey = Array(key[32..<64])
        nameTweak = Array(key[64..<80])
        
        name_aes = AES_EME(key: self.nameKey, IV: self.nameTweak)
    }
    
    override func ConvertDecryptName(name: String) -> String {
        DecryptName(ciphertext: name) ?? name    }
    
    override func ConvertDecryptSize(size: Int64) -> Int64 {
        CalcDecryptedSize(crypt_size: size)
    }

    override func ConvertEncryptName(name: String, folder: Bool) -> String {
        if folder && name_cryptmode == .off {
            return name
        }
        return EncryptName(plain: name) ?? name
    }
    
    override func ConvertEncryptSize(size: Int64) -> Int64 {
        return CalcEncryptedSize(org_size: size)
    }

    struct Base32768 {
        let blockBit = 5
        private let safeAlphabet = "ƀɀɠʀҠԀڀڠݠހ߀ကႠᄀᄠᅀᆀᇠሀሠበዠጠᎠᏀᐠᑀᑠᒀᒠᓀᓠᔀᔠᕀᕠᖀᖠᗀᗠᘀᘠᙀᚠᛀកᠠᡀᣀᦀ᧠ᨠᯀᰀᴀ⇠⋀⍀⍠⎀⎠⏀␀─┠╀╠▀■◀◠☀☠♀♠⚀⚠⛀⛠✀✠❀➀➠⠀⠠⡀⡠⢀⢠⣀⣠⤀⤠⥀⥠⦠⨠⩀⪀⪠⫠⬀⬠⭀ⰀⲀⲠⳀⴀⵀ⺠⻀㇀㐀㐠㑀㑠㒀㒠㓀㓠㔀㔠㕀㕠㖀㖠㗀㗠㘀㘠㙀㙠㚀㚠㛀㛠㜀㜠㝀㝠㞀㞠㟀㟠㠀㠠㡀㡠㢀㢠㣀㣠㤀㤠㥀㥠㦀㦠㧀㧠㨀㨠㩀㩠㪀㪠㫀㫠㬀㬠㭀㭠㮀㮠㯀㯠㰀㰠㱀㱠㲀㲠㳀㳠㴀㴠㵀㵠㶀㶠㷀㷠㸀㸠㹀㹠㺀㺠㻀㻠㼀㼠㽀㽠㾀㾠㿀㿠䀀䀠䁀䁠䂀䂠䃀䃠䄀䄠䅀䅠䆀䆠䇀䇠䈀䈠䉀䉠䊀䊠䋀䋠䌀䌠䍀䍠䎀䎠䏀䏠䐀䐠䑀䑠䒀䒠䓀䓠䔀䔠䕀䕠䖀䖠䗀䗠䘀䘠䙀䙠䚀䚠䛀䛠䜀䜠䝀䝠䞀䞠䟀䟠䠀䠠䡀䡠䢀䢠䣀䣠䤀䤠䥀䥠䦀䦠䧀䧠䨀䨠䩀䩠䪀䪠䫀䫠䬀䬠䭀䭠䮀䮠䯀䯠䰀䰠䱀䱠䲀䲠䳀䳠䴀䴠䵀䵠䶀䷀䷠一丠乀习亀亠什仠伀传佀你侀侠俀俠倀倠偀偠傀傠僀僠儀儠兀兠冀冠净几刀删剀剠劀加勀勠匀匠區占厀厠叀叠吀吠呀呠咀咠哀哠唀唠啀啠喀喠嗀嗠嘀嘠噀噠嚀嚠囀因圀圠址坠垀垠埀埠堀堠塀塠墀墠壀壠夀夠奀奠妀妠姀姠娀娠婀婠媀媠嫀嫠嬀嬠孀孠宀宠寀寠尀尠局屠岀岠峀峠崀崠嵀嵠嶀嶠巀巠帀帠幀幠庀庠廀廠开张彀彠往徠忀忠怀怠恀恠悀悠惀惠愀愠慀慠憀憠懀懠戀戠所扠技抠拀拠挀挠捀捠掀掠揀揠搀搠摀摠撀撠擀擠攀攠敀敠斀斠旀无昀映晀晠暀暠曀曠最朠杀杠枀枠柀柠栀栠桀桠梀梠检棠椀椠楀楠榀榠槀槠樀樠橀橠檀檠櫀櫠欀欠歀歠殀殠毀毠氀氠汀池沀沠泀泠洀洠浀浠涀涠淀淠渀渠湀湠満溠滀滠漀漠潀潠澀澠激濠瀀瀠灀灠炀炠烀烠焀焠煀煠熀熠燀燠爀爠牀牠犀犠狀狠猀猠獀獠玀玠珀珠琀琠瑀瑠璀璠瓀瓠甀甠畀畠疀疠痀痠瘀瘠癀癠皀皠盀盠眀眠着睠瞀瞠矀矠砀砠础硠碀碠磀磠礀礠祀祠禀禠秀秠稀稠穀穠窀窠竀章笀笠筀筠简箠節篠簀簠籀籠粀粠糀糠紀素絀絠綀綠緀締縀縠繀繠纀纠绀绠缀缠罀罠羀羠翀翠耀耠聀聠肀肠胀胠脀脠腀腠膀膠臀臠舀舠艀艠芀芠苀苠茀茠荀荠莀莠菀菠萀萠葀葠蒀蒠蓀蓠蔀蔠蕀蕠薀薠藀藠蘀蘠虀虠蚀蚠蛀蛠蜀蜠蝀蝠螀螠蟀蟠蠀蠠血衠袀袠裀裠褀褠襀襠覀覠觀觠言訠詀詠誀誠諀諠謀謠譀譠讀讠诀诠谀谠豀豠貀負賀賠贀贠赀赠趀趠跀跠踀踠蹀蹠躀躠軀軠輀輠轀轠辀辠迀迠退造遀遠邀邠郀郠鄀鄠酀酠醀醠釀釠鈀鈠鉀鉠銀銠鋀鋠錀錠鍀鍠鎀鎠鏀鏠鐀鐠鑀鑠钀钠铀铠销锠镀镠門閠闀闠阀阠陀陠隀隠雀雠需霠靀靠鞀鞠韀韠頀頠顀顠颀颠飀飠餀餠饀饠馀馠駀駠騀騠驀驠骀骠髀髠鬀鬠魀魠鮀鮠鯀鯠鰀鰠鱀鱠鲀鲠鳀鳠鴀鴠鵀鵠鶀鶠鷀鷠鸀鸠鹀鹠麀麠黀黠鼀鼠齀齠龀龠ꀀꀠꁀꁠꂀꂠꃀꃠꄀꄠꅀꅠꆀꆠꇀꇠꈀꈠꉀꉠꊀꊠꋀꋠꌀꌠꍀꍠꎀꎠꏀꏠꐀꐠꑀꑠ꒠ꔀꔠꕀꕠꖀꖠꗀꗠꙀꚠꛀ꜀꜠ꝀꞀꡀ"

        let encodeA: [UInt16]
        let encodeB: [UInt16]
        let decodeMap: [UInt16]
        let splitter: UInt16
        
        init() {
            let encode = safeAlphabet.unicodeScalars.map { r in
                UInt16(r.value)
            }.sorted()
            splitter = encode[4]
            encodeA = Array(encode[4...])
            encodeB = Array(encode[0..<4])
            var decodeMap = [UInt16](repeating: 0xFFFD, count: 2048)
            for i in 0..<encodeA.count {
                let idx = Int(encodeA[i] >> blockBit)
                if decodeMap[idx] != 0xFFFD {
                    fatalError("encoding alphabet have repeating character")
                }
                decodeMap[idx] = UInt16(i) << blockBit
            }
            for i in 0..<encodeB.count {
                let idx = Int(encodeB[i] >> blockBit)
                if decodeMap[idx] != 0xFFFD {
                    fatalError("encoding alphabet have repeating character")
                }
                decodeMap[idx] = UInt16(i) << blockBit
            }
            self.decodeMap = decodeMap
        }
    }
    let base32768 = Base32768()

    func EncodeBase32768(input: [UInt8]) -> String {
        func encodedLen(_ n: Int) -> Int {
            (8*n + 14) / 15 * 2
        }
        
        func encode15(_ src: UInt16) -> UInt16 {
            let src = src & 0x7FFF
            var dst = base32768.encodeA[Int(src>>base32768.blockBit)]
            dst |= UInt16(src & (1<<base32768.blockBit - 1))
            return dst
        }

        func encode7(_ src: UInt8) -> UInt16 {
            let src = src & 0x7F
            var dst = base32768.encodeB[Int(src>>base32768.blockBit)]
            dst |= UInt16(src & (1<<base32768.blockBit - 1))
            return dst
        }
        
        func encodeUint16(_ src: [UInt8]) -> [UInt16] {
            var dst = [UInt16]()
            var left: UInt8 = 0
            var leftn = 0
            var i = 0
            while i < src.count {
                var chunk: UInt16 = 0 // Chunk contains 15 bits
                chunk = UInt16(left) << (15 - leftn)
                chunk |= UInt16(src[i+0]) << (7 - leftn)
                if leftn < 7 && src.count > i+1 {
                    chunk |= UInt16(src[i+1]) >> (1 + leftn)
                    left = src[i+1] & (1<<(1+leftn) - 1)
                    leftn += 1
                    i += 2 // 2 bytes taken
                } else {
                    chunk |= 1<<(7-leftn) - 1 // Pad with 1s
                    left = 0
                    leftn = 0
                    i += 1 // 1 byte taken
                }
                dst.append(encode15(chunk))
            }
            // Remaining
            if leftn > 0 {
                left = left << (7 - leftn)
                left |= 1<<(7-leftn) - 1 // Pad with 1s
                dst.append(encode7(left))
            }
            return dst
        }

        let buf = encodeUint16(input).map { Character(UnicodeScalar($0)!) }
        return String(buf)
    }
    
    func EncodeBase64(input: [UInt8]) -> String {
        if input.isEmpty {
            return ""
        }
        return Data(input).base64EncodedString().replacing("+", with: "-").replacing("/", with: "_").replacing("=", with: "")
    }

    func EncodeBase32(input: [UInt8]) -> String {
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
                b[0] = (input[offset] >> 3) & 0x1f
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

    func DecodeBase32768(input: String) -> Data? {
        func decode(_ src: UInt16) -> (UInt16, Bool, Bool) {
            let isTrailing = src < base32768.splitter
            var dst = base32768.decodeMap[Int(src>>base32768.blockBit)]
            if dst == 0xFFFD {
                return (dst, isTrailing, false)
            }
            dst |= src & (1<<base32768.blockBit - 1)
            return (dst, isTrailing, true)
        }

        func decodeUint16(_ src: [UInt16]) -> Data? {
            var dst = Data()
            var left: UInt8 = 0
            var leftn: Int = 0
            for chunk in src {
                let (d, trailing, success) = decode(chunk)
                guard success else {
                    return nil
                }
                if trailing {
                    // Left one byte
                    if leftn > 0 {
                        let buf = left<<(8-leftn) | UInt8((d >> (leftn-1)) & 0xff)
                        dst.append(buf)
                    }
                    return dst
                }
                // Read 15 bits
                if leftn > 0 {
                    let buf0 = (left<<(8-leftn)) | UInt8(d>>(7+leftn))
                    let buf1 = UInt8((d >> (leftn - 1)) & 0xff)
                    left = UInt8(d & (1<<(leftn-1) - 1))
                    leftn -= 1
                    dst.append(buf0)
                    dst.append(buf1)
                } else {
                    let buf = UInt8(d >> 7)
                    left = UInt8(d & 0x7F)
                    leftn = 7
                    dst.append(buf)
                }
            }
            return dst
        }
        return decodeUint16(Array(input.utf16))
    }

    func DecodeBase64(input: String) -> Data? {
        let len = input.count
        let padlen = ((len / 4) + 1) * 4 - len
        var inchar = Array(input)
        inchar.append(contentsOf: [Character](repeating: "=", count: padlen))
        return Data(base64Encoded: String(inchar).replacing("-", with: "+").replacing("_", with: "/"))
    }
    
    func DecodeBase32(input: String) -> Data? {
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
                case 3:
                    c = 3
                case 4:
                    c = 2
                case 6:
                    c = 1
                default:
                    break
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
        if name_cryptmode == .obfuscated {
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
        else if name_cryptmode == .standard {
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
            switch name_encodemode {
            case .base32:
                return EncodeBase32(input: [UInt8](output))
            case .base64:
                return EncodeBase64(input: [UInt8](output))
            case .base32768:
                return EncodeBase32768(input: [UInt8](output))
            }
        }
        else {
            return plain + name_suffix
        }
    }
    
    func DecryptName(ciphertext: String) -> String? {
        if ciphertext == "" {
            return ""
        }
        
        if name_cryptmode == .obfuscated {
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
        else if name_cryptmode == .standard {
            let rawcipher: Data?
            switch name_encodemode {
            case .base32:
                rawcipher = DecodeBase32(input: ciphertext)
            case .base64:
                rawcipher = DecodeBase64(input: ciphertext)
            case .base32768:
                rawcipher = DecodeBase32768(input: ciphertext)
            }
            guard let rawcipher else {
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
    
    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await CryptRcloneRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await CryptRcloneRemoteItem(path: path)
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
    
    override init?(storage: String, id: String) async {
        guard let s = await CloudFactory.shared.storageList.get(storage) as? CryptRclone else {
            return nil
        }
        remoteStorage = s
        await super.init(storage: storage, id: id)
    }
    
    public override func open() async -> RemoteStream {
        return await RemoteCryptRcloneStream(remote: self)
    }
}

public class RemoteCryptRcloneStream: SlotStream {
    let remote: CryptRcloneRemoteItem
    let OrignalLength: Int64
    let CryptedLength: Int64
    var nonce = [UInt8](repeating: 0, count: 24)
    let key: [UInt8]

    init(remote: CryptRcloneRemoteItem) async {
        self.remote = remote
        OrignalLength = remote.size
        CryptedLength = remote.remoteStorage.CalcEncryptedSize(org_size: OrignalLength)
        key = remote.remoteStorage.dataKey
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
        if !remote.remoteStorage.fileMagic.elementsEqual(data.subdata(in: 0..<remote.remoteStorage.fileMagic.count)) {
            print("error on header check")
            await super.fillHeader()
            error = true
        }
        nonce.replaceSubrange(0..<nonce.count, with: data.subdata(in: remote.remoteStorage.fileMagic.count..<data.count))
        await super.fillHeader()
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
    
    override func subFillBuffer(pos: ClosedRange<Int64>) async {
        guard await initialized.wait(timeout: .seconds(10)) == .success else {
            error = true
            return
        }

        let chunksize = remote.remoteStorage.chunkSize
        let orgBlocksize = remote.remoteStorage.blockDataSize
        let headersize = Int64(remote.remoteStorage.fileHeaderSize)
        if await !buffer.dataAvailable(pos: pos) {
            guard pos.lowerBound >= 0 && pos.upperBound < size else {
                return
            }
            let len = min(size-1, pos.upperBound) - pos.lowerBound + 1
            let slot1 = pos.lowerBound / orgBlocksize
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
                    guard let plain = Secretbox.open(box: chunk, nonce: addNonce(pos: slot), key: key) else {
                        error = true
                        return
                    }
                    plainBlock.append(plain)
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
        defer {
            PPj.deallocate()
        }
        C.withUnsafeMutableBufferPointer { (Cbytes: inout UnsafeMutableBufferPointer<UInt8>)->Void in
            tweek.withUnsafeBufferPointer { (T: UnsafeBufferPointer<UInt8>)->Void in
                key.withUnsafeBufferPointer { (keyBytes: UnsafeBufferPointer<UInt8>)->Void in
                    for j in 0..<m {
                        let Pj = UnsafeBufferPointer<UInt8>(rebasing: input[j*16..<(j+1)*16])
                        /* PPj = 2**(j-1)*L xor Pj */
                        LTable[j].withUnsafeBufferPointer {
                            XorBlocks(output: PPj, in1: Pj, in2: $0)
                        }
                        
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
                    defer {
                        MPt.deallocate()
                    }
                    XorBlocks(output: MPt, in1: UnsafeBufferPointer<UInt8>(rebasing: Cbytes[0..<16]), in2: T)
                    for j in 1..<m {
                        XorBlocks(inout1: MPt, in2: UnsafeBufferPointer<UInt8>(rebasing: Cbytes[j*16..<(j+1)*16]))
                    }
                    let MP = UnsafeBufferPointer<UInt8>(MPt)
                    
                    /* MC = AESenc(K; MP) */
                    var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
                    var outLength = Int(0)
                    let mcBytes = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: 16)
                    defer {
                        mcBytes.deallocate()
                    }
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
                    defer {
                        M.deallocate()
                    }
                    XorBlocks(output: M, in1: MP, in2: MC)
                    for j in 1..<m {
                        MultByTwo(inout1: M)
                        /* CCCj = 2**(j-1)*M xor PPPj */
                        XorBlocks(inout1: UnsafeMutableBufferPointer<UInt8>(rebasing: Cbytes[j*16..<(j+1)*16]), in2: UnsafeBufferPointer<UInt8>(M))
                    }
                    
                    /* CCC1 = (xorSum CCCj) xor T xor MC */
                    let CCC1 = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: 16)
                    defer {
                        CCC1.deallocate()
                    }
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
                            LTable[j].withUnsafeBufferPointer { Lt in
                                XorBlocks(output: UnsafeMutableBufferPointer<UInt8>(rebasing: Cbytes[j*16..<(j+1)*16]), in1: outBuf, in2: Lt)
                            }
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
    func TabulateL(m: Int) -> [[UInt8]]? {
        
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
        var ret: [[UInt8]] = (0..<m).map { _ in [UInt8](repeating: 0, count: outLength) }
        var Li = Array(outBytes[0..<outLength])
        Li.withUnsafeMutableBufferPointer { LiBuf in
            for i in 0..<m {
                ret[i].withUnsafeMutableBufferPointer {
                    MultByTwo(output: $0, input: UnsafeBufferPointer(LiBuf))
                }
                for j in 0..<16 {
                    LiBuf[j] = ret[i][j]
                }
            }
        }
        return ret
    }
}

class Poly1305 {
    static let TagSize = 16
    
    class func poly1305(tag: inout [UInt8], msg: [UInt8], key: [UInt8]) {
        poly1305(tag: &tag[0..<tag.count], msg: msg[0..<msg.count], key: key)
    }
    
    class func poly1305(tag: inout ArraySlice<UInt8>, msg: ArraySlice<UInt8>, key: [UInt8]) {
        let len = msg.endIndex - msg.startIndex
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

        key.withUnsafeBytes { kp in
            let keyPointer = kp.baseAddress!
            r0 = UInt64((keyPointer).assumingMemoryBound(to: UInt32.self).pointee & 0x3ffffff)
            r1 = UInt64(((keyPointer+3).assumingMemoryBound(to: UInt32.self).pointee >> 2) & 0x3ffff03)
            r2 = UInt64(((keyPointer+6).assumingMemoryBound(to: UInt32.self).pointee >> 4) & 0x3ffc0ff)
            r3 = UInt64(((keyPointer+9).assumingMemoryBound(to: UInt32.self).pointee >> 6) & 0x3f03fff)
            r4 = UInt64(((keyPointer+12).assumingMemoryBound(to: UInt32.self).pointee >> 8) & 0x00fffff)
        }
        
        
        let R1 = r1 * 5
        let R2 = r2 * 5
        let R3 = r3 * 5
        let R4 = r4 * 5
        
        var offset = 0
        while len - offset >= TagSize {
            // h += msg
            msg.withUnsafeBytes { mp in
                let msg_p = mp.baseAddress!
                h0 += (msg_p+offset).assumingMemoryBound(to: UInt32.self).pointee & 0x3ffffff
                h1 += ((msg_p+offset+3).assumingMemoryBound(to: UInt32.self).pointee >> 2) & 0x3ffffff
                h2 += ((msg_p+offset+6).assumingMemoryBound(to: UInt32.self).pointee >> 4) & 0x3ffffff
                h3 += ((msg_p+offset+9).assumingMemoryBound(to: UInt32.self).pointee >> 6) & 0x3ffffff
                h4 += ((msg_p+offset+12).assumingMemoryBound(to: UInt32.self).pointee >> 8) | (1 << 24)
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
            
            offset += TagSize
        }
        if len - offset > 0 {
            var block = [UInt8](repeating: 0, count: TagSize)
            block.replaceSubrange(0..<(len-offset), with: msg[msg.startIndex+offset..<msg.endIndex])
            block[len-offset] = 0x01
            
            // h += msg
            block.withUnsafeBytes { u in
                let up = u.baseAddress!
                h0 += (up).assumingMemoryBound(to: UInt32.self).pointee & 0x3ffffff
                h1 += ((up+3).assumingMemoryBound(to: UInt32.self).pointee >> 2) & 0x3ffffff
                h2 += ((up+6).assumingMemoryBound(to: UInt32.self).pointee >> 4) & 0x3ffffff
                h3 += ((up+9).assumingMemoryBound(to: UInt32.self).pointee >> 6) & 0x3ffffff
                h4 += ((up+12).assumingMemoryBound(to: UInt32.self).pointee >> 8)
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
        key.withUnsafeBytes { kp in
            let keyPointer = kp.baseAddress!
            
            var t = UInt64(h0)+UInt64((keyPointer+16).load(as: UInt32.self))
            h0 = UInt32(t & 0xffffffff)
            t = UInt64(h1) + UInt64((keyPointer+20).load(as: UInt32.self)) + (t >> 32)
            h1 = UInt32(t & 0xffffffff)
            t = UInt64(h2) + UInt64((keyPointer+24).load(as: UInt32.self)) + (t >> 32)
            h2 = UInt32(t & 0xffffffff)
            t = UInt64(h3) + UInt64((keyPointer+28).load(as: UInt32.self)) + (t >> 32)
            h3 = UInt32(t & 0xffffffff)
        }
        
        tag.withUnsafeMutableBytes { tp in
            let tagp = (tp.baseAddress!).bindMemory(to: UInt32.self, capacity: 4)
            tagp[0] = h0
            tagp[1] = h1
            tagp[2] = h2
            tagp[3] = h3
        }
    }
    
    class func Verify(mac: [UInt8], msg: [UInt8], key: [UInt8]) -> Bool {
        guard key.count == 32 else {
            return false
        }
        guard mac.count == TagSize else {
            return false
        }
        var tag = [UInt8](repeating: 0, count: TagSize)
        poly1305(tag: &tag, msg: msg, key: key)
        return tag.elementsEqual(mac)
    }
}

class Secretbox {
    static let Sigma = [UInt8]("expand 32-byte k".data(using: .ascii)!)
    static let Overhead = 16
    
    class func HSalsa20(input: [UInt8], k: [UInt8], c: [UInt8]) -> [UInt8]? {
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
    
    class func SalsaCore(input: [UInt8], k: [UInt8], c: [UInt8]) -> [UInt8]? {
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
    
    class func SalsaCore208(intext: UnsafeMutableBufferPointer<UInt32>, outtext: UnsafeMutableBufferPointer<UInt32>) {
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

    class func XORKeyStream(output: inout [UInt8], input: [UInt8], counter: [UInt8], key: [UInt8]) {
        XORKeyStream(output: &output[0..<output.count], input: input[0..<input.count], counter: counter, key: key)
    }
    
    class func XORKeyStream(output: inout ArraySlice<UInt8>, input: ArraySlice<UInt8>, counter: [UInt8], key: [UInt8]) {
        guard key.count == 32 else {
            return
        }
        guard counter.count == 16 else {
            return
        }

        var inCounter = counter
        var offset = 0
        let inlen = input.endIndex - input.startIndex
        while inlen - offset >= 64 {
            guard let block = SalsaCore(input: inCounter, k: key, c: Sigma) else {
                return
            }
            for i in 0..<64 {
                output[output.startIndex+offset+i] = block[i] ^ input[input.startIndex+offset+i]
            }
            
            var u: UInt32 = 1
            for i in 8..<16 {
                u += UInt32(inCounter[i])
                inCounter[i] = UInt8(u & 0xff)
                u >>= 8
            }
            
            offset += 64
        }
        if inlen - offset > 0 {
            guard let block = SalsaCore(input: inCounter, k: key, c: Sigma) else {
                return
            }
            for i in 0..<inlen - offset {
                output[output.startIndex+offset+i] = block[i] ^ input[input.startIndex+offset+i]
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
        
        guard let subkey = HSalsa20(input: Array(nonce[0..<16]), k: key, c: Sigma) else {
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
        
        XORKeyStream(output: &firstBlock, input: zeroInput, counter: counter, key: subkey)
        
        let poly1305Key = Array(firstBlock[0..<32])
        let firstMessageBlock: [UInt8]
        if msg.count < 32 {
            firstMessageBlock = msg
        }
        else {
            firstMessageBlock = Array(msg[0..<32])
        }
        
        for i in 0..<firstMessageBlock.count {
            out[i+Poly1305.TagSize] = firstBlock[i+32] ^ firstMessageBlock[i]
        }
        
        if msg.count > 32 {
            var counter2 = counter
            counter2[8] = 1
            XORKeyStream(output: &out[Poly1305.TagSize+firstMessageBlock.count..<out.count], input: msg[32..<message.count], counter: counter2, key: subkey)
        }
        
        Poly1305.poly1305(tag: &out[0..<Poly1305.TagSize], msg: out[Poly1305.TagSize..<out.count], key: poly1305Key)

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

        XORKeyStream(output: &firstBlock, input: zeroInput, counter: counter, key: subkey)
        
        let poly1305Key = Array(firstBlock[0..<32])
        let tag = Array(boxmsg[0..<Poly1305.TagSize])
        let boxBody = Array(boxmsg[Poly1305.TagSize..<boxmsg.count])
        
        guard Poly1305.Verify(mac: tag, msg: boxBody, key: poly1305Key) else {
            print("verify error")
            return nil
        }
        
        let firstMessageBlock: [UInt8]
        if boxmsg.count < 32 {
            firstMessageBlock = boxBody
        }
        else {
            firstMessageBlock = Array(boxBody[0..<32])
        }
        
        for i in 0..<firstMessageBlock.count {
            out[i] = firstBlock[i+32] ^ firstMessageBlock[i]
        }
        
        if boxBody.count > 32 {
            var counter2 = counter
            counter2[8] = 1
            XORKeyStream(output: &out[firstMessageBlock.count..<out.count], input: boxBody[32..<boxBody.count], counter: counter2, key: subkey)
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
        
        let v = (0..<Int(N)).map { _ in UnsafeMutableBufferPointer<UInt32>.allocate(capacity: Bs) }
        let x = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: Bs)
        let sc1 = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: 16)
        let scx = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: 16)
        let scy = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: Bs)
        let scz = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: Bs)
        defer {
            let _ = v.map( { $0.deallocate() } )
            x.deallocate()
            sc1.deallocate()
            scx.deallocate()
            scy.deallocate()
            scz.deallocate()
        }
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
            Secretbox.SalsaCore208(intext: sc, outtext: x)
            for i in 0..<16 {
                y[m+i] = x[i]
            }
            k += 16
            
            for i in 0..<sc.count {
                sc[i] = B[k+i] ^ x[i]
            }
            Secretbox.SalsaCore208(intext: sc, outtext: x)
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
                let buf = ComputeBlock(pos: pos)
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

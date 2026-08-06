//
//  SftpStorage.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/04/10.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreData
import os.log
import SwiftUI
import AuthenticationServices
internal import UniformTypeIdentifiers
import libssh

struct KnownHostsManager {
    private static var fileURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDir = paths[0]
        
        if !FileManager.default.fileExists(atPath: appSupportDir.path) {
            try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        }
        
        return appSupportDir.appendingPathComponent("sftp_known_hosts.json")
    }
    
    static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }
    
    static func update(hostname: String, hashString: String) {
        var hosts = load()
        hosts[hostname] = hashString
        
        if let data = try? JSONEncoder().encode(hosts) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
    
    static func clearAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum SSHError: Error, LocalizedError {
    case memoryError
    case connectError(_ log: String)
    case keyError(_ log: String)
    case authError(_ log: String)
    case sftpError(_ code: Int32)
    case readError
    
    var errorDescription: String? {
        switch self {
        case .memoryError:
            return "Failed to allocate memory"
        case .connectError(let log):
            return "Connection Error: \(log)"
        case .keyError(let log):
            return "Host Key Error: \(log)"
        case .authError(let log):
            return "Authentication Error: \(log)"
        case .sftpError(let code):
            return "SFTP Error (code: \(code))"
        case .readError:
            return "Failed to read file"
        }
    }
}

public struct SftpFileStat {
    public let name: String
    public let isDirectory: Bool
    public let size: Int64
    public let modificationDate: Date
}

public final class SftpFileHandle: @unchecked Sendable {
    let raw: sftp_file
    let sessionId: Int
    var isClosed = false
    
    init(raw: sftp_file, sessionId: Int) {
        self.raw = raw
        self.sessionId = sessionId
    }
}

struct SSHConfig {
    var hostname = ""
    var port: Int32 = 22
    var username = ""
    var password = ""
    var privateKeyString = ""
    var passphrase = ""
    var rootPath = ""
}

actor SftpConnection {
    private static let lock = NSLock()
    private static var instanceCount: Int = 0
    private var currentSessionId: Int = 0
    private var max_read_length: UInt64 = 32 * 1024
    private var max_write_length: UInt64 = 32 * 1024
    
    init() {
        Self.lock.withLock {
            Self.instanceCount += 1
            if Self.instanceCount == 1 {
                ssh_init()
            }
        }
    }
    
    deinit {
        Self.lock.withLock {
            Self.instanceCount -= 1
            if Self.instanceCount == 0 {
                ssh_finalize()
            }
        }
    }
    
    var sshSession: ssh_session!
    var sftpSession: sftp_session!
    var connectionInfo = SSHConfig()
    
    var isConnected: Bool {
        return sftpSession != nil && sshSession != nil && ssh_is_connected(sshSession) == 1
    }
    
    private func handleSftpErrorAndThrow(_ sftpErrorCode: Int32) throws -> Never {
        // SSH_FX_NO_CONNECTION = 6, SSH_FX_CONNECTION_LOST = 7
        let isFatalSftpError = (sftpErrorCode == 6 || sftpErrorCode == 7)
        let isSocketDead = sshSession == nil || ssh_is_connected(sshSession) == 0
        
        if isFatalSftpError || isSocketDead {
            print("Fatal network error detected. Disconnecting to force reconnect on next try.")
            disconnect()
        }
        throw SSHError.sftpError(sftpErrorCode)
    }
    
    func setConnectionInfo(_ info: SSHConfig) {
        connectionInfo = info
    }
    
    var onHostKeyVerification: ((_ message: String) async -> Bool)?
    
    func setOnHostKeyVerification(_ callback: @escaping (String) async -> Bool) {
        onHostKeyVerification = callback
    }
    
    static func getServerHashForKnownhost(_ session: ssh_session) throws -> [UInt8] {
        var srv_pubkey: ssh_key!
        var hash: UnsafeMutablePointer<UInt8>!
        var hlen = 0
        if ssh_get_server_publickey(session, &srv_pubkey) < 0 {
            let e = String(cString: ssh_get_error(UnsafeMutableRawPointer(session)))
            throw SSHError.keyError(e)
        }
        defer {
            ssh_key_free(srv_pubkey)
        }
        if ssh_get_publickey_hash(srv_pubkey, SSH_PUBLICKEY_HASH_SHA1, &hash, &hlen) < 0 {
            let e = String(cString: ssh_get_error(UnsafeMutableRawPointer(session)))
            throw SSHError.keyError(e)
        }
        defer {
            ssh_clean_pubkey_hash(&hash)
        }
        
        return Array(UnsafeBufferPointer(start: hash, count: hlen))
    }
    
    func connect() async throws {
        disconnect()
        currentSessionId += 1
        sshSession = ssh_new()
        guard let sshSession else {
            throw SSHError.memoryError
        }
        
        connectionInfo.hostname.withCString { hostPtr in
            _ = ssh_options_set(sshSession, SSH_OPTIONS_HOST, hostPtr)
        }
        ssh_options_set(sshSession, SSH_OPTIONS_PORT, &connectionInfo.port)
        connectionInfo.username.withCString { userPtr in
            _ = ssh_options_set(sshSession, SSH_OPTIONS_USER, userPtr)
        }
        
        var rc: Int32
        repeat {
            rc = ssh_connect(sshSession)
            await Task.yield()
        } while rc == SSH_AGAIN
        if rc != SSH_OK {
            let e = String(cString: ssh_get_error(UnsafeMutableRawPointer(sshSession)))
            disconnect()
            throw SSHError.connectError(e)
        }
        
        let srv_hkey = try SftpConnection.getServerHashForKnownhost(sshSession)
        let hostKeyString = srv_hkey.map({ String(format: "%02x", $0) }).joined(separator: ":")
        print("server key : \(hostKeyString)")
        
        let knownHosts = KnownHostsManager.load()
        
        if let savedKey = knownHosts[connectionInfo.hostname] {
            if savedKey != hostKeyString {
                let shouldContinue = await onHostKeyVerification?("cached key:\n\(savedKey)\n\nnew key:\n\(hostKeyString)") ?? false
                if shouldContinue {
                    KnownHostsManager.update(hostname: connectionInfo.hostname, hashString: hostKeyString)
                    print("User accepted key change. New host key saved.")
                } else {
                    disconnect()
                    throw SSHError.keyError("Server key verification failed.")
                }
            } else {
                print("Known host check passed.")
            }
        } else {
            KnownHostsManager.update(hostname: connectionInfo.hostname, hashString: hostKeyString)
            print("New host key saved.")
        }
        
        if !connectionInfo.privateKeyString.isEmpty {
            var privkey: ssh_key?
            
            let importRc = connectionInfo.privateKeyString.withCString { keyStrPtr in
                let passPtr = connectionInfo.passphrase.isEmpty ? nil : connectionInfo.passphrase
                return passPtr?.withCString { pPtr in
                    ssh_pki_import_privkey_base64(keyStrPtr, pPtr, nil, nil, &privkey)
                } ?? ssh_pki_import_privkey_base64(keyStrPtr, nil, nil, nil, &privkey)
            }
            
            if importRc != SSH_OK {
                let e = String(cString: ssh_get_error(UnsafeMutableRawPointer(sshSession)))
                disconnect()
                throw SSHError.authError("Importing private key failed: \(e)")
            }
            defer { if let k = privkey { ssh_key_free(k) } }
            
            repeat {
                rc = ssh_userauth_publickey(sshSession, nil, privkey)
                await Task.yield()
            } while rc == SSH_AGAIN
            
            if rc != SSH_AUTH_SUCCESS.rawValue {
                let e = String(cString: ssh_get_error(UnsafeMutableRawPointer(sshSession)))
                disconnect()
                throw SSHError.authError("Failed to authenticate with public key: \(e)")
            }
            print("Public Key Authentication Success.")
        }
        else {
            print("Trying Password Authentication...")
            repeat {
                rc = connectionInfo.password.withCString { passPtr in
                    ssh_userauth_password(sshSession, nil, passPtr)
                }
                await Task.yield()
            } while rc == SSH_AGAIN
            if rc != SSH_AUTH_SUCCESS.rawValue {
                let e = String(cString: ssh_get_error(UnsafeMutableRawPointer(sshSession)))
                disconnect()
                throw SSHError.authError("Failed to authenticate with password: \(e)")
            }
            print("Password Authentication Success.")
        }
        
        sftpSession = sftp_new(sshSession)
        guard sftpSession != nil else {
            disconnect()
            throw SSHError.memoryError
        }
        
        repeat {
            rc = sftp_init(sftpSession)
            await Task.yield()
        } while rc == SSH_AGAIN
        if rc != SSH_OK {
            let sftpError = sftp_get_error(sftpSession)
            disconnect()
            throw SSHError.sftpError(sftpError)
        }
    }
    
    func disconnect() {
        if sftpSession != nil {
            sftp_free(sftpSession)
            sftpSession = nil
        }
        if sshSession != nil {
            ssh_disconnect(sshSession)
            ssh_free(sshSession)
            sshSession = nil
        }
    }
    
    func listDirectory(path: String) async throws -> [SftpFileStat] {
        if !isConnected { try await connect() }
        guard let sftp = sftpSession else {
            throw SSHError.memoryError
        }
        
        let targetPath = resolve(path)
        
        guard let dir = targetPath.withCString({ sftp_opendir(sftp, $0) }) else {
            let sftpError = sftp_get_error(sftp)
            disconnect()
            throw SSHError.sftpError(sftpError)
        }
        defer { sftp_closedir(dir) }
        
        var results: [SftpFileStat] = []
        
        while let attr = sftp_readdir(sftp, dir) {
            defer { sftp_attributes_free(attr) }
            
            guard let namePtr = attr.pointee.name else { continue }
            let fileName = String(cString: namePtr)
            
            if fileName == "." || fileName == ".." { continue }
            
            let isDirectory = attr.pointee.type == 2 // (SSH_FILEXFER_TYPE_DIRECTORY)
            
            let size = Int64(attr.pointee.size)
            let mtime = TimeInterval(attr.pointee.mtime)
            let modifiedDate = Date(timeIntervalSince1970: mtime)
            
            let stat = SftpFileStat(
                name: fileName,
                isDirectory: isDirectory,
                size: size,
                modificationDate: modifiedDate
            )
            results.append(stat)
        }
        
        if sftp_dir_eof(dir) == 0 {
            let sftpError = sftp_get_error(sftp)
            disconnect()
            throw SSHError.sftpError(sftpError)
        }
        
        return results
    }
    
    func mkdir(path: String) async throws {
        if !isConnected { try await connect() }
        guard let sftp = sftpSession else { throw SSHError.memoryError }
        
        let rc = resolve(path).withCString { sftp_mkdir(sftp, $0, mode_t(0o755)) }
        if rc != SSH_OK {
            try handleSftpErrorAndThrow(sftp_get_error(sftp))
        }
    }
    
    func delete(path: String) async throws {
        if !isConnected { try await connect() }
        guard let sftp = sftpSession else { throw SSHError.memoryError }
        
        let targetPath = resolve(path)
        
        let unlinkRc = targetPath.withCString { sftp_unlink(sftp, $0) }
        if unlinkRc == SSH_OK {
            return
        }
        
        let sftpError = sftp_get_error(sftp)
        
        if sftpError == 6 || sftpError == 7 {
            try handleSftpErrorAndThrow(sftpError)
        }
        
        do {
            let children = try await listDirectory(path: path)
            
            for child in children {
                let childPath = path.isEmpty ? child.name : path + "/" + child.name
                try await delete(path: childPath)
            }
            
            let rmdirRc = targetPath.withCString { sftp_rmdir(sftp, $0) }
            if rmdirRc != SSH_OK {
                try handleSftpErrorAndThrow(sftp_get_error(sftp))
            }
        } catch {
            throw error
        }
    }
    
    func rename(oldPath: String, newPath: String) async throws {
        if !isConnected { try await connect() }
        guard let sftp = sftpSession else { throw SSHError.memoryError }
        
        let rc = resolve(oldPath).withCString { oldPtr in
            resolve(newPath).withCString { newPtr in
                sftp_rename(sftp, oldPtr, newPtr)
            }
        }
        if rc != SSH_OK {
            try handleSftpErrorAndThrow(sftp_get_error(sftp))
        }
    }
    
    func setModificationTime(path: String, date: Date) async throws {
        if !isConnected { try await connect() }
        guard let sftp = sftpSession else { throw SSHError.memoryError }
        
        var attr = sftp_attributes_struct()
        attr.flags = UInt32(SSH_FILEXFER_ATTR_ACMODTIME)
        let timeInt = UInt32(date.timeIntervalSince1970)
        attr.mtime = timeInt
        attr.atime = timeInt
        
        let rc = resolve(path).withCString { sftp_setstat(sftp, $0, &attr) }
        if rc != SSH_OK {
            try handleSftpErrorAndThrow(sftp_get_error(sftp))
        }
    }
    
    func openFile(path: String) async throws -> SftpFileHandle {
        if !isConnected { try await connect() }
        guard let sftp = sftpSession else { throw SSHError.memoryError }
        
        guard let file = resolve(path).withCString({ sftp_open(sftp, $0, O_RDONLY, 0) }) else {
            try handleSftpErrorAndThrow(sftp_get_error(sftp))
        }
        max_read_length = sftp_limits(sftp).pointee.max_read_length
        return SftpFileHandle(raw: file, sessionId: currentSessionId)
    }
    
    func readFileChunk(file: SftpFileHandle, offset: UInt64, length: Int) throws -> Data {
        if file.isClosed || file.sessionId != currentSessionId {
            throw SSHError.memoryError
        }
        if !isConnected { throw SSHError.memoryError }
        guard length > 0 else {
            return Data()
        }
        
        let rawFile = file.raw
        
        if sftp_seek64(rawFile, offset) < 0 {
            try handleSftpErrorAndThrow(sftp_get_error(sftpSession))
        }
        
        let chunkSize = Int(max_read_length)
        var resultData = Data(count: length)
        
        let totalRead = try resultData.withUnsafeMutableBytes { ptr -> Int in
            guard let baseAddress = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            
            var aioHandles: [sftp_aio?] = []
            var remainingToRequest = length
            
            defer {
                for aio in aioHandles {
                    if let validAio = aio {
                        sftp_aio_free(validAio)
                    }
                }
            }
            
            while remainingToRequest > 0 {
                let reqSize = min(chunkSize, remainingToRequest)
                var aio: sftp_aio? = nil
                
                let reqBytes = sftp_aio_begin_read(rawFile, reqSize, &aio)
                if reqBytes < 0 {
                    try handleSftpErrorAndThrow(sftp_get_error(sftpSession))
                }
                
                aioHandles.append(aio)
                remainingToRequest -= Int(reqBytes)
            }
            
            var currentRead = 0
            for i in 0..<aioHandles.count {
                guard aioHandles[i] != nil else { continue }
                
                let bytesExpected = length - currentRead
                
                let readBytes = sftp_aio_wait_read(&aioHandles[i], baseAddress.advanced(by: currentRead), bytesExpected)
                
                if readBytes < 0 {
                    try handleSftpErrorAndThrow(sftp_get_error(sftpSession))
                }
                if readBytes == 0 {
                    break // EOF
                }
                currentRead += Int(readBytes)
            }
            return currentRead
        }
        
        if totalRead < length {
            return resultData.prefix(totalRead)
        }
        
        return resultData
    }
    
    func closeFile(_ file: SftpFileHandle) {
        guard !file.isClosed else { return }
        file.isClosed = true
        if sftpSession != nil && file.sessionId == currentSessionId {
            sftp_close(file.raw)
        }
    }
    
    func writeFile(path: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws {
        if !isConnected { try await connect() }
        guard let sftp = sftpSession else { throw SSHError.memoryError }
        max_write_length = sftp_limits(sftp).pointee.max_write_length
        
        let targetPath = resolve(path)
        let flags = O_WRONLY | O_CREAT | O_EXCL
        let mode: mode_t = 0o644
        
        guard let file = targetPath.withCString({ sftp_open(sftp, $0, flags, mode) }) else {
            try handleSftpErrorAndThrow(sftp_get_error(sftp))
        }
        defer { sftp_close(file) }
        
        let handle = try FileHandle(forReadingFrom: target)
        defer { try? handle.close() }
        
        let attr = try FileManager.default.attributesOfItem(atPath: target.path(percentEncoded: false))
        let fileSize = attr[.size] as! UInt64
        try await progress?(0, Int64(fileSize))
        
        let batchSize = 32 * 1024 * 1024
        let packetSize = Int(max_write_length)
        var currentOffset: Int64 = 0
        var eof = false
        
        while !eof {
            guard let batchData = try handle.read(upToCount: batchSize) else {
                throw SSHError.readError
            }
            if batchData.count < batchSize {
                eof = true
            }
            if batchData.isEmpty { break }
            
            try batchData.withUnsafeBytes { ptr in
                guard let baseAddress = ptr.baseAddress else { return }
                
                var aioHandles: [sftp_aio?] = []
                defer {
                    for aio in aioHandles {
                        if let validAio = aio { sftp_aio_free(validAio) }
                    }
                }
                
                var batchOffset = 0
                
                while batchOffset < batchData.count {
                    let writeSize = min(packetSize, batchData.count - batchOffset)
                    var aio: sftp_aio? = nil
                    
                    let reqBytes = sftp_aio_begin_write(file, baseAddress.advanced(by: batchOffset), writeSize, &aio)
                    if reqBytes < 0 {
                        try handleSftpErrorAndThrow(sftp_get_error(sftp))
                    }
                    if reqBytes != writeSize {
                        throw SSHError.readError
                    }
                    
                    aioHandles.append(aio)
                    batchOffset += Int(reqBytes)
                }
                
                for i in 0..<aioHandles.count {
                    guard aioHandles[i] != nil else { continue }
                    let status = sftp_aio_wait_write(&aioHandles[i])
                    if status < 0 {
                        try handleSftpErrorAndThrow(sftp_get_error(sftp))
                    }
                }
            }
            
            currentOffset += Int64(batchData.count)
            try await progress?(currentOffset, Int64(fileSize))
        }
    }
}

extension SftpConnection {
    static func generateEd25519KeyPair() throws -> (privateKey: String, publicKeyOpenSSH: String) {
        var key: ssh_key?
        if ssh_pki_generate_key(SSH_KEYTYPE_ED25519, nil, &key) != SSH_OK {
            throw SSHError.keyError("Failed to generate key")
        }
        defer { if let k = key { ssh_key_free(k) } }
        var privKeyChar: UnsafeMutablePointer<CChar>?
        if ssh_pki_export_privkey_base64(key, nil, nil, nil, &privKeyChar) != SSH_OK {
            throw SSHError.keyError("Failed to export private key")
        }
        defer { if let p = privKeyChar { ssh_string_free_char(p) } }
        let privateKeyStr = String(cString: privKeyChar!)
        
        var pubKeyChar: UnsafeMutablePointer<CChar>?
        if ssh_pki_export_pubkey_base64(key, &pubKeyChar) != SSH_OK {
            throw SSHError.keyError("Failed to export public key")
        }
        defer { if let p = pubKeyChar { ssh_string_free_char(p) } }
        let pubBase64Str = String(cString: pubKeyChar!)
        
        let publicKeyOpenSSH = "ssh-ed25519 \(pubBase64Str) generated-by-CryptCloudViewer"
        
        return (privateKeyStr, publicKeyOpenSSH)
    }
    
    private func resolve(_ path: String) -> String {
        let root = connectionInfo.rootPath
        
        if root.isEmpty {
            return path.isEmpty ? "." : path
        }
        
        if path.isEmpty {
            return root
        }
        
        let cleanRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        
        return "\(cleanRoot)/\(cleanPath)"
    }
}

enum AuthMethod: String, CaseIterable {
    case password = "Password"
    case publicKey = "Public Key"
}

struct SftpLoginView: View {
    let authContinuation: CheckedContinuation<Bool, Never>
    let callback: (SSHConfig, @escaping (String) async -> Bool) async -> String?
    let onDismiss: () -> Void
    @State private var ok = false
    @State private var errorMessage = ""
    @State private var isErrorAlertPresent = false
    
    @State private var hostname = ""
    @State private var username = ""
    @State private var port = "22"
    @State private var rootPath = ""
    
    @State private var authMethod: AuthMethod = .password
    @State private var password = ""
    @State private var showPassword = false
    
    @State private var privateKeyString = ""
    @State private var passphrase = ""
    @State private var publicKeyString = ""
    @State private var showFileImporter = false
    @State private var isPublicKeyCopiedAlertPresent = false

    @State private var isHostKeyAlertPresent = false
    @State private var hostKeyMessage = ""
    @State private var hostKeyContinuation: CheckedContinuation<Bool, Never>?
    
    var body: some View {
        ZStack {
            Form {
                Section("Server") {
                    HStack {
                        Text("Host")
                        Spacer()
                        TextField("hostname or IP", text: $hostname)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("port (default 22)", text: $port)
                            .keyboardType(.numberPad)
                    }
                    HStack {
                        Text("Username")
                        Spacer()
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                    HStack {
                        Text("Root Path")
                        Spacer()
                        TextField("/ (default is home)", text: $rootPath)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                }

                Picker("Authentication", selection: $authMethod) {
                    ForEach(AuthMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if authMethod == .password {
                    Section("Password") {
                        HStack {
                            if showPassword {
                                TextField("password", text: $password)
                            } else {
                                SecureField("password", text: $password)
                            }
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .tint(showPassword ? .accentColor : .gray)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } else {
                    Section("Private Key") {
                        if !privateKeyString.isEmpty {
                            HStack {
                                Text("✓ Key Loaded (\(privateKeyString.count) bytes)")
                                    .foregroundColor(.green)
                                Button {
                                    privateKeyString.removeAll()
                                    publicKeyString.removeAll()
                                } label: {
                                    Text("Clear")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            Text("No Key Loaded")
                                .foregroundColor(.gray)
                        }
                        
                        Button("Import Private Key File") {
                            showFileImporter = true
                        }
                        
                        SecureField("Passphrase (Optional)", text: $passphrase)
                    }
                    
                    Section {
                        Button("Generate New Key Pair") {
                            generateAndCopyKey()
                        }
                        if !publicKeyString.isEmpty {
                            Text(verbatim: publicKeyString)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                            
                            Button {
                                UIPasteboard.general.string = publicKeyString
                                isPublicKeyCopiedAlertPresent = true
                            } label: {
                                Label("Copy Public Key again", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    } footer: {
                        Text("Generates an Ed25519 key pair, applies it, and copies the public key to clipboard.")
                    }
                }

                Section {
                    Button("Connect") {
                        connectAction()
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(ok || isHostKeyAlertPresent)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .alert("Error", isPresented: $isErrorAlertPresent) {
                Button(role: .cancel) {
                    ok = false
                }
            } message: {
                Text(errorMessage)
            }
            .alert("Key Copied", isPresented: $isPublicKeyCopiedAlertPresent) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Public key has been copied to your clipboard. Paste it into your server's authorized_keys file.")
            }
            .alert("Host Key Changed", isPresented: $isHostKeyAlertPresent) {
                Button("Cancel", role: .cancel) {
                    hostKeyContinuation?.resume(returning: false)
                    hostKeyContinuation = nil
                    ok = false
                }
                Button("Accept & Continue", role: .destructive) {
                    hostKeyContinuation?.resume(returning: true)
                    hostKeyContinuation = nil
                }
            } message: {
                Text("Warning: Server key has changed.\n\n\(hostKeyMessage)\n\nDo you want to continue connecting?")
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
            hostKeyContinuation?.resume(returning: false)
            hostKeyContinuation = nil
            onDismiss()
        }
    }

    // MARK: - Actions
        
    private func connectAction() {
        if hostname.isEmpty {
            showError("Please fill in hostname.")
            return
        }
        if username.isEmpty {
            showError("Please fill in username.")
            return
        }
        
        if authMethod == .password, password.isEmpty {
            showError("Please fill in password.")
            return
        }
        if authMethod == .publicKey, privateKeyString.isEmpty {
            showError("Please import or generate a private key.")
            return
        }
        
        ok = true
        Task {
            let config = SSHConfig(
                hostname: hostname,
                port: Int32(port) ?? 22,
                username: username,
                password: authMethod == .password ? password : "",
                privateKeyString: authMethod == .publicKey ? privateKeyString : "",
                passphrase: authMethod == .publicKey ? passphrase : "",
                rootPath: rootPath,
            )
            
            if let error = await callback(config, verifyHostKey) {
                showError(error)
                ok = false
            } else {
                authContinuation.resume(returning: true)
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        isErrorAlertPresent = true
    }

    private func generateAndCopyKey() {
        do {
            let keys = try SftpConnection.generateEd25519KeyPair()
            
            self.privateKeyString = keys.privateKey
            self.authMethod = .publicKey
            self.publicKeyString = keys.publicKeyOpenSSH
            
            UIPasteboard.general.string = keys.publicKeyOpenSSH
            
            isPublicKeyCopiedAlertPresent = true
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                showError("Failed to gain access to the file.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                self.privateKeyString = content
                self.publicKeyString = ""
            } catch {
                showError("Could not read key file as text: \(error.localizedDescription)")
            }
        case .failure(let error):
            showError(error.localizedDescription)
        }
    }
    
    func verifyHostKey(message: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.hostKeyMessage = message
                self.hostKeyContinuation = continuation
                self.isHostKeyAlertPresent = true
            }
        }
    }
}

public class SftpStorage: NetworkStorage {
    private let poolSize = 4
    var connections: [SftpConnection] = []

    private var nextConnectionIndex = 0
    private let poolLock = NSLock()
    
    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .sftp)
        storageName = name
        rootName = ""
        
        for _ in 0..<poolSize {
            connections.append(SftpConnection())
        }
    }

    func getConnection() async -> SftpConnection {
        if sshconfig == nil {
            sshconfig = SSHConfig(
                hostname: await getHostname(),
                port: Int32(await getPort()) ?? 22,
                username: await getUsername(),
                password: await getPassword(),
                privateKeyString: await getPrivatekey(),
                passphrase: await getPassphrase(),
                rootPath: await getRootPath(),
            )
        }
        
        let conn = poolLock.withLock {
            let c = connections[nextConnectionIndex]
            nextConnectionIndex = (nextConnectionIndex + 1) % poolSize
            return c
        }
        
        if let config = sshconfig, await !conn.isConnected {
            await conn.setConnectionInfo(config)
        }
        
        return conn
    }
    
    var mainConnection: SftpConnection {
        return connections[0]
    }
    
    public override func getStorageType() -> CloudStorages {
        return .sftp
    }

    var cache_hostname = ""
    var cache_port = ""
    var cache_username = ""
    var cache_password = ""
    var cache_privatekey = ""
    var cache_passphrase = ""
    var cache_rootpath = ""
    var sshconfig: SSHConfig?

    func getHostname() async -> String {
        if !cache_hostname.isEmpty { return cache_hostname }
        if let name = storageName, let val = await getKeyChain(key: "\(name)_hostname") { cache_hostname = val }
        return cache_hostname
    }

    func getPort() async -> String {
        if !cache_port.isEmpty { return cache_port }
        if let name = storageName, let val = await getKeyChain(key: "\(name)_port") { cache_port = val }
        return cache_port
    }

    func getUsername() async -> String {
        if !cache_username.isEmpty { return cache_username }
        if let name = storageName, let val = await getKeyChain(key: "\(name)_username") { cache_username = val }
        return cache_username
    }

    func getPassword() async -> String {
        if !cache_password.isEmpty { return cache_password }
        if let name = storageName, let val = await getKeyChain(key: "\(name)_password") { cache_password = val }
        return cache_password
    }

    func getPrivatekey() async -> String {
        if !cache_privatekey.isEmpty { return cache_privatekey }
        if let name = storageName, let val = await getKeyChain(key: "\(name)_privatekey") { cache_privatekey = val }
        return cache_privatekey
    }

    func getPassphrase() async -> String {
        if !cache_passphrase.isEmpty { return cache_passphrase }
        if let name = storageName, let val = await getKeyChain(key: "\(name)_passphrase") { cache_passphrase = val }
        return cache_passphrase
    }

    func getRootPath() async -> String {
        if !cache_rootpath.isEmpty { return cache_rootpath }
        if let name = storageName, let val = await getKeyChain(key: "\(name)_rootpath") { cache_rootpath = val }
        return cache_rootpath
    }
    
    override func checkToken() async -> Bool {
        if sshconfig == nil {
            sshconfig = SSHConfig(
                hostname: await getHostname(),
                port: Int32(await getPort()) ?? 22,
                username: await getUsername(),
                password: await getPassword(),
                privateKeyString: await getPrivatekey(),
                passphrase: await getPassphrase(),
                rootPath: await getRootPath(),
            )
        }
        guard let sshconfig else {
            return false
        }
        var isAnyConnected = false
        for conn in connections {
            if await !conn.isConnected {
                await conn.setConnectionInfo(sshconfig)
                do {
                    try await conn.connect()
                    isAnyConnected = true
                } catch {
                    print("Connection pool connect error: \(error)")
                }
            } else {
                isAnyConnected = true
            }
        }
        return isAnyConnected
    }

    public override func logout() async {
        if let name = storageName {
            let _ = await delKeyChain(key: "\(name)_hostname")
            let _ = await delKeyChain(key: "\(name)_port")
            let _ = await delKeyChain(key: "\(name)_username")
            let _ = await delKeyChain(key: "\(name)_password")
            let _ = await delKeyChain(key: "\(name)_privatekey")
            let _ = await delKeyChain(key: "\(name)_passphrase")
            let _ = await delKeyChain(key: "\(name)_rootpath")
        }
        cache_hostname = ""
        cache_port = ""
        cache_username = ""
        cache_password = ""
        cache_privatekey = ""
        cache_passphrase = ""
        cache_rootpath = ""
        for conn in connections {
            await conn.disconnect()
        }
        await super.logout()
    }

    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        
        let authRet = await withCheckedContinuation { authContinuation in
            Task {
                let presentRet = await withCheckedContinuation { continuation in
                    callback(SftpLoginView(authContinuation: authContinuation, callback: authCallback, onDismiss: {
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

    func authCallback(config: SSHConfig, handler: @escaping (String) async -> Bool) async -> String? {
        await mainConnection.setConnectionInfo(config)
        await mainConnection.setOnHostKeyVerification { message in
            return await handler(message)
        }
        
        do {
            try await mainConnection.connect()
        }
        catch {
            print(error)
            return error.localizedDescription
        }
        
        sshconfig = config
        let name = storageName ?? ""
        let _ = await setKeyChain(key: "\(name)_hostname", value: config.hostname)
        let _ = await setKeyChain(key: "\(name)_port", value: "\(config.port)")
        let _ = await setKeyChain(key: "\(name)_username", value: config.username)
        let _ = await setKeyChain(key: "\(name)_password", value: config.password)
        let _ = await setKeyChain(key: "\(name)_privatekey", value: config.privateKeyString)
        let _ = await setKeyChain(key: "\(name)_passphrase", value: config.passphrase)
        let _ = await setKeyChain(key: "\(name)_rootpath", value: config.rootPath)
        return nil
    }

    override func listChildren(fileId: String = "", path: String = "") async {
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
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "listFolder(\(String(describing: type(of: self))):\(storageName ?? ""))")
                
                do {
                    let conn = await getConnection()
                    let files = try await conn.listDirectory(path: fileId)
                    
                    for file in files {
                        await storeItem(item: file, parentId: fileId, parentPath: path, context: viewContext)
                    }

                    await viewContext.perform {
                        try? viewContext.save()
                    }
                } catch {
                    print("Failed to list directory: \(error.localizedDescription)")
                }
            })
        }
        catch {
            print(error)
            return
        }
    }
    
    private func storeItem(item: SftpFileStat, parentId: String, parentPath: String, context: NSManagedObjectContext) async {
        let id = parentId.isEmpty ? item.name : parentId + "/" + item.name
        let name = item.name
        let isDirectory = item.isDirectory
        let modificationDate = item.modificationDate
        let size = item.size
        let storage = storageName ?? ""
        await context.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, storage)
            if let result = try? context.fetch(fetchRequest) {
                for object in result {
                    context.delete(object as! NSManagedObject)
                }
            }
            
            let newitem = RemoteData(context: context)
            newitem.storage = storage
            newitem.id = id
            newitem.name = name
            
            let comp = name.components(separatedBy: ".")
            if comp.count > 1 && !isDirectory {
                newitem.ext = comp.last!.lowercased()
            } else {
                newitem.ext = ""
            }
            
            newitem.cdate = modificationDate
            newitem.mdate = modificationDate
            newitem.folder = isDirectory
            newitem.size = Int64(size)
            
            newitem.parent = parentId
            if parentId == "" {
                newitem.path = "\(storage):/\(name)"
            } else {
                newitem.path = "\(parentPath)/\(name)"
            }
        }
    }

    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil) async -> Data? {
        return nil
    }
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "makeFolder(\(String(describing: type(of: self))):\(storageName ?? "") \(parentId) \(newname)")
                do {
                    let targetPath = parentId.isEmpty ? newname : "\(parentId)/\(newname)"

                    let conn = await getConnection()
                    try await conn.mkdir(path: targetPath)

                    return targetPath
                } catch {
                    print("makeFolder error: \(error)")
                    return nil
                }
            })
        }
        catch {
            return nil
        }
    }
    
    override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        if toParentId == fromParentId {
            return nil
        }
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "moveItem(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId) \(fromParentId) \(toParentId)")
                do {
                    let fileName = fileId.components(separatedBy: "/").last ?? fileId
                    let newPath = toParentId.isEmpty ? fileName : "\(toParentId)/\(fileName)"
                    
                    let conn = await getConnection()
                    try await conn.rename(oldPath: fileId, newPath: newPath)

                    await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
                    return newPath
                } catch {
                    print("moveItem error: \(error)")
                    return nil
                }
            })
        }
        catch {
            return nil
        }
    }
    
    override func deleteItem(fileId: String) async -> Bool {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "deleteItem(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId)")
                do {
                    let conn = await getConnection()
                    try await conn.delete(path: fileId)

                    await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
                    return true
                } catch {
                    print("deleteItem error: \(error)")
                    return false
                }
            })
        }
        catch {
            return false
        }
    }
    
    override func renameItem(fileId: String, newname: String) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "renameItem(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId) \(newname)")
                do {
                    let components = fileId.components(separatedBy: "/")
                    let parentDir = components.dropLast().joined(separator: "/")
                    
                    let newPath = parentDir.isEmpty ? newname : "\(parentDir)/\(newname)"
                    
                    let conn = await getConnection()
                    try await conn.rename(oldPath: fileId, newPath: newPath)

                    await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
                    return newPath
                } catch {
                    print("moveItem error: \(error)")
                    return nil
                }
            })
        }
        catch {
            return nil
        }
    }
    
    override func changeTime(fileId: String, newdate: Date) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "changeTime(\(String(describing: type(of: self))):\(storageName ?? "") \(fileId) \(newdate)")
                do {
                    let conn = await getConnection()
                    try await conn.setModificationTime(path: fileId, date: newdate)

                    return fileId
                } catch {
                    print("changeTime error: \(error)")
                    return nil
                }
            })
        }
        catch {
            return nil
        }
    }
    
    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await SftpRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await SftpRemoteItem(path: path)
    }
    
    override func uploadFile(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        defer {
            try? FileManager.default.removeItem(at: target)
        }
        os_log("%{public}@", log: log, type: .debug, "uploadFile(google:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")

        let targetPath = parentId.isEmpty ? uploadname : "\(parentId)/\(uploadname)"

        do {
            let conn = await getConnection()
            try await conn.writeFile(path: targetPath, target: target, progress: progress)

            return targetPath
        } catch {
            print("uploadFile error: \(error)")
            return nil
        }
    }
}

public class SftpRemoteItem: RemoteItem {
    let remoteStorage: SftpStorage

    override init?(storage: String, id: String) async {
        guard let s = await CloudFactory.shared.storageList.get(storage) as? SftpStorage else {
            return nil
        }
        remoteStorage = s
        await super.init(storage: storage, id: id)
    }
    
    public override func open() async -> RemoteStream {
        return await RemoteSftpStream(remote: self)
    }
}

public class RemoteSftpStream: SlotStream {
    let chunkSize: Int64 = 8*1024*1024
    let remote: SftpRemoteItem
    let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "application")

    private let handleLock = NSLock()
    private var openFileTask: Task<SftpFileHandle, Error>?
    
    private let dedicatedConnection: SftpConnection
    
    init(remote: SftpRemoteItem) async {
        self.remote = remote
        self.dedicatedConnection = await remote.remoteStorage.getConnection()
        await super.init(size: remote.size)
    }

    private func getHandle() async throws -> SftpFileHandle {
        let task: Task<SftpFileHandle, Error> = handleLock.withLock {
            if let existingTask = openFileTask {
                return existingTask
            }
            
            let newTask = Task {
                try await dedicatedConnection.openFile(path: remote.id)
            }
            openFileTask = newTask
            return newTask
        }
        
        return try await task.value
    }
    
    override func setLive(_ live: Bool) {
        if !live {
            let taskToCancel = handleLock.withLock {
                let task = openFileTask
                openFileTask = nil
                return task
            }

            if let task = taskToCancel {
                Task { [dedicatedConnection] in
                    if let handle = try? await task.value {
                        await dedicatedConnection.closeFile(handle)
                    }
                }
            }
            let sem = DispatchSemaphore(value: 0)
            Task(priority: .userInitiated) {
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
            guard start <= end else { continue }
            let chunkLen = end - start + 1

            if await !buffer.dataAvailable(pos: start...end) {
                if let cache = await CloudFactory.shared.cache.getCache(storage: remote.storage, id: remote.id, offset: start, size: chunkLen) {
                    if let data = try? Data(contentsOf: cache) {
                        os_log("%{public}@", log: log, type: .debug, "hit cache(SftpStorage:\(remote.storage) \(remote.id) \(start) \(chunkLen) \(start + chunkLen))")
                        await buffer.store(pos: start, data: data)
                        continue
                    }
                }
                do {
                    let handle = try await getHandle()
                    let data = try await dedicatedConnection.readFileChunk(
                        file: handle,
                        offset: UInt64(start),
                        length: Int(chunkLen)
                    )
                    await buffer.store(pos: start, data: data)
                    await CloudFactory.shared.cache.saveCache(storage: remote.storage, id: remote.id, offset: start, data: data)
                } catch {
                    print("Stream read error: \(error)")
                    self.error = true
                    break
                }
            }
        }
    }
}

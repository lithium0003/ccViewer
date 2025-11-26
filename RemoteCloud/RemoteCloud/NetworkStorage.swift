//
//  NetworkStorage.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/03/13.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreData
import os.log
import SwiftUI
import AuthenticationServices

struct WebLoginView: View {
    let webAuthenticationSession: WebAuthenticationSession
    let url: URL
    let callback: ASWebAuthenticationSession.Callback
    let additionalHeaderFields: [String: String]

    let signIn: (URL) async throws -> Bool
    let authContinuation: CheckedContinuation<Bool, Never>

    var body: some View {
        Color.clear
            .task {
                try? await Task.sleep(for: .seconds(1))
                do {
                     // Perform the authentication and await the result.
                    let urlWithToken = try await webAuthenticationSession.authenticate(using: url, callback: callback, additionalHeaderFields: additionalHeaderFields)
                     // Call the method that completes the authentication using the
                     // returned URL.
                    guard try await signIn(urlWithToken) else {
                        authContinuation.resume(returning: false)
                        return
                    }
                    authContinuation.resume(returning: true)
                 } catch {
                     // Respond to any authorization errors.
                     print(error)
                     authContinuation.resume(returning: false)
                 }
            }
    }
}

public class NetworkStorage: RemoteStorageBase {
    actor URLProgressManeger {
        var callbacks: [String: ((Int64, Int64) async throws -> Void)?] = [:]
        var offsets: [String: Int64] = [:]
        var totals: [String: Int64] = [:]

        func progress(url: URL, currnt: Int64) async throws {
            if let callback = callbacks[url.absoluteString] {
                if let offset = offsets[url.absoluteString], let total = totals[url.absoluteString] {
                    try await callback?(currnt+offset, total)
                }
            }
        }
        
        func setCallback(url: URL, total: Int64, callback: ((Int64, Int64) async throws -> Void)?) {
            callbacks[url.absoluteString] = callback
            offsets[url.absoluteString] = 0
            totals[url.absoluteString] = total
        }
        
        func setOffset(url: URL, offset: Int64) {
            offsets[url.absoluteString] = offset
        }
        
        func removeCallback(url: URL) {
            callbacks[url.absoluteString] = nil
            offsets[url.absoluteString] = nil
            totals[url.absoluteString] = nil
        }
    }
    let uploadProgressManeger = URLProgressManeger()
    
    var cacheTokenDate: Date = Date(timeIntervalSince1970: 0)
    var tokenLife: TimeInterval = 0
    let callSemaphore = Semaphore(value: 5)
    let callWait = 0.2
    var cache_accessToken = ""
    var cache_refreshToken = ""

    func accessToken() async -> String {
        if cache_accessToken != "" {
            return cache_accessToken
        }
        if let name = storageName {
            if let token = await getKeyChain(key: "\(name)_accessToken") {
                cache_accessToken = token
            }
            return cache_accessToken
        }
        else {
            return ""
        }
    }
    
    func getRefreshToken() async -> String {
        if cache_refreshToken != "" {
            return cache_refreshToken
        }
        if let name = storageName {
            if let token = await getKeyChain(key: "\(name)_refreshToken") {
                cache_refreshToken = token
            }
            return cache_refreshToken
        }
        else {
            return ""
        }
    }
    
    enum RetryError: Error {
        case Failed
        case Retry
    }

    func callWithRetry<T>(action: @escaping () async throws -> T, callcount: Int = 0, semaphore: Semaphore? = nil, maxCall: Int = 20) async throws -> T {
        let semaphore = semaphore ?? callSemaphore
        if callcount > maxCall {
            throw RetryError.Failed
        }
        if await semaphore.wait(timeout: .seconds(5)) == .timeout {
            if cancelTime.timeIntervalSinceNow > 0 {
                cancelTime = Date(timeIntervalSinceNow: 0.5)
                throw CancellationError()
            }
            try? await Task.sleep(for: .milliseconds(Int(1000 * (callWait + Double.random(in: 0..<callWait)))))
            return try await callWithRetry(action: action, callcount: callcount+1)
        }
        guard await checkToken() else {
            await semaphore.signal()
            throw RetryError.Failed
        }
        do {
            defer {
                Task { await semaphore.signal() }
            }
            return try await action()
        }
        catch RetryError.Retry {
            try? await Task.sleep(for: .milliseconds(Int(1000 * (callWait + Double.random(in: 0..<callWait)))))
            return try await callWithRetry(action: action, callcount: callcount+1)
        }
    }
    
    var authURL: URL {
        URL(string: "https://example.com/oauth/authorize")!
    }
    var authCallback: ASWebAuthenticationSession.Callback {
        ASWebAuthenticationSession.Callback.customScheme("com.example.app")
    }
    var additionalHeaderFields: [String: String] {
        return [:]
    }

    func signIn(_: URL) async throws -> Bool {
        fatalError("signIn not implemented")
    }

    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        if await checkToken() {
            return true
        }
        if await isAuthorized() {
            return true
        }
        let authRet = await withCheckedContinuation { authContinuation in
            Task {
                let presentRet = await withCheckedContinuation { continuation in
                    callback(WebLoginView(webAuthenticationSession: webAuthenticationSession, url: authURL, callback: authCallback, additionalHeaderFields: additionalHeaderFields, signIn: signIn(_:), authContinuation: authContinuation),  continuation)
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
            if let aToken = await getKeyChain(key: "\(name)_accessToken") {
                await revokeToken(token: aToken)
            }
            let _ = await delKeyChain(key: "\(name)_accessToken")
            let _ = await delKeyChain(key: "\(name)_refreshToken")
            cache_accessToken = ""
            cache_refreshToken = ""
            cacheTokenDate = Date(timeIntervalSince1970: 0)
            tokenLife = 0
        }
        await super.logout()
    }

    func checkToken() async -> Bool {
        let d = Date()
        os_log("%{public}@", log: log, type: .debug, "\(d) \(cacheTokenDate),\(tokenLife)")
        if cacheTokenDate < d, d < cacheTokenDate + tokenLife / 2 {
            return true
        }
        else if await getRefreshToken() == "" {
            return false
        }
        else {
            return await refreshToken()
        }
    }
    
    func saveToken(accessToken: String, refreshToken: String) async -> Void {
        if let name = storageName {
            guard accessToken != "" && refreshToken != "" else {
                return
            }
            os_log("%{public}@", log: log, type: .info, "saveToken")
            cacheTokenDate = Date()
            cache_refreshToken = refreshToken
            cache_accessToken = accessToken
            _ = await setKeyChain(key: "\(name)_accessToken", value: accessToken)
            _ = await setKeyChain(key: "\(name)_refreshToken", value: refreshToken)
        }
    }
    
    func isAuthorized() async -> Bool {
        return false
    }
    
    func getToken(oauthToken: String) async -> Bool {
        return false
    }
    
    func refreshToken() async -> Bool {
        return false
    }
    
    @discardableResult
    func revokeToken(token: String) async -> Bool {
        return false
    }
    
}

public class NetworkRemoteItem: RemoteItem {
    let remoteStorage: RemoteStorageBase
    
    override init?(storage: String, id: String) async {
        guard let s = await CloudFactory.shared.storageList.get(storage) as? RemoteStorageBase else {
            return nil
        }
        remoteStorage = s
        await super.init(storage: storage, id: id)
    }
    
    public override func open() async -> RemoteStream {
        return await RemoteNetworkStream(remote: self)
    }
}

public class SlotStream: RemoteStream {
    static let slotcount = 50
    static let slotadvance: Int64 = 2
    static let bufSize:Int64 = 2*1024*1024
    var error = false {
        didSet {
            print(error)
        }
    }

    let waitlist = WaitListManager()
    let initialized = InitialManager()
    let buffer: BufferManager
    
    actor InitialManager {
        private var initialized = false
        private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
        private var idlist: [UUID] = []
        public enum waitResult {
            case timeout
            case success
        }
        
        public func wait() async {
            await wait(id: UUID())
        }
        
        func wait(id: UUID) async {
            if initialized { return }
            await withCheckedContinuation {
                idlist.append(id)
                waiters[id] = $0
            }
        }
        
        @discardableResult
        public func wait(timeout: ContinuousClock.Instant.Duration) async -> waitResult {
            if initialized { return .success }
            let id = UUID()
            return await withTaskGroup(of: waitResult.self) { group in
                group.addTask {
                    await self.wait(id: id)
                    return .success
                }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return .timeout
                }
                let v = await group.next()!
                group.cancelAll()
                if v == .timeout {
                    if let i = idlist.firstIndex(of: id) {
                        idlist.remove(at: i)
                    }
                    waiters[id]?.resume()
                    waiters.removeValue(forKey: id)
                }
                return v
            }
        }
        
        public func signal() {
            initialized = true
            for id in idlist {
                waiters[id]?.resume()
                waiters.removeValue(forKey: id)
            }
            idlist.removeAll()
        }
    }

    actor BufferManager {
        let size: Int64
        var read_start: Int64 = 0
        var read_end: Int64 = 0
        var buffer: [Int64:Data] = [:]
        
        init(size: Int64) {
            self.size = size
        }

        func read(position : Int64, length: Int, read_start: Int64, read_end: Int64) -> Data {
            var ret = Data()
            var len = length
            var p = position
            self.read_start = read_start
            self.read_end = read_end

            for key in Array(buffer.keys).sorted() {
                guard let buf = buffer[key] else {
                    continue
                }
                if key <= p && p < key+Int64(buf.count) {
                    let s = Int(p - key)
                    let l = (len + s > buf.count) ? buf.count : len + s
                    ret += buf.subdata(in: s..<l)
                    len -= l-s
                    p += Int64(l-s)
                }
                if len == 0 {
                    break
                }
            }
            assert(len == 0)
            disposeBuffer()
            return ret
        }
        
        func store(pos: Int64, data: Data) {
            buffer[pos] = data
        }
        
        func dataAvailable(pos: ClosedRange<Int64>) -> Bool {
            return !buffer.allSatisfy({ $0.key > pos.lowerBound || $0.key + Int64($0.value.count) < pos.upperBound })
        }

        func disposeBuffer() {
            if read_start < SlotStream.bufSize * 2 || read_end > size - SlotStream.bufSize*2 {
                return
            }
            if buffer.count > SlotStream.slotcount {
                let del = buffer.keys.sorted().filter({ $0 > SlotStream.bufSize*4 }).filter({ $0 < size - SlotStream.bufSize*5 })
                let target = del.map({ ($0, max(read_start - SlotStream.bufSize - $0, $0 - read_end + SlotStream.bufSize*SlotStream.slotadvance)) }).sorted(by: { $0.1 > $1.1 })
                for (d, dist) in target {
                    if dist < 0 {
                        break
                    }
                    buffer[d] = nil
                    if buffer.count <= SlotStream.slotcount {
                       break
                    }
                }
            }
        }
    }

    actor WaitListManager {
        var waitlist: [Int64] = []
        
        func add(_ pos: Int64) -> Bool {
            if waitlist.contains(pos) {
                return false
            }
            waitlist.append(pos)
            return true
        }
        
        func done(_ pos: Int64) {
            waitlist.removeAll(where: { $0 == pos })
        }
    }
    
    override init(size: Int64) async {
        buffer = BufferManager(size: size)
        await super.init(size: size)
        await fillHeader()
        await firstFill()
    }

    override public func preload(position: Int64, length: Int) async {
        let len1 = (position + Int64(length) < size) ? Int64(length) : size - position
        let read_start = position
        let read_end = position + len1 - 1
        for p in read_start/SlotStream.bufSize...read_end/SlotStream.bufSize+SlotStream.slotadvance {
            Task {
                await fillBuffer(slot: p)
            }
        }
    }
    
    func fillHeader() async {
        await initialized.signal()
    }

    func firstFill() async {
        await withTaskGroup() { group in
            group.addTask { [self] in
                let pos1 = Int64(0)
                let pos2 = Int64(min(size-1, SlotStream.bufSize - 1))
                guard pos1 <= pos2 else {
                    return
                }
                await subFillBuffer(pos: pos1...pos2)
            }
            group.addTask { [self] in
                let slot = size / SlotStream.bufSize
                let pos1 = slot * SlotStream.bufSize
                let pos2 = min(size-1, (slot+1) * SlotStream.bufSize - 1)
                guard pos1 <= pos2 else {
                    return
                }
                await subFillBuffer(pos: pos1...pos2)
            }
        }
    }

    func subFillBuffer(pos: ClosedRange<Int64>) async {
        print("error on implimant")
        error = true
    }
    
    func fillBuffer(slot: Int64) async {
        if slot >= 0 && slot * SlotStream.bufSize < size {
            let slot2 = min(slot+5, size / SlotStream.bufSize)
            for i in slot...slot2 {
                let pos1 = i * SlotStream.bufSize
                let pos2 = min(size-1, (i+1) * SlotStream.bufSize - 1)
                if isLive, pos1 >= 0, pos1 < size, await !buffer.dataAvailable(pos: pos1...pos2) {
                    guard await waitlist.add(pos1) else {
                        continue
                    }
                    await subFillBuffer(pos: pos1...pos2)
                    await waitlist.done(pos1)
                }
            }
        }
    }
    
    func subRead(position : Int64, length: Int) async throws -> Data? {
        if position >= size {
            return nil
        }
        if size <= 0 {
            return nil
        }
        let len1 = (position + Int64(length) < size) ? Int64(length) : size - position
        let read_start = position
        let read_end = position + len1 - 1
        let start = Date()
        while !error && isLive {
            var done = true
            do {
                for p in read_start/SlotStream.bufSize...(read_end/SlotStream.bufSize) {
                    let pos1 = p * SlotStream.bufSize
                    let pos2 = min(size-1, (p+1) * SlotStream.bufSize - 1)
                    let slotdone = await buffer.dataAvailable(pos: pos1...pos2)
                    if !slotdone {
                        Task.detached(priority: .high) {
                            await self.fillBuffer(slot: p)
                        }
                    }
                    done = done && slotdone
                }
                if done {
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
                if start.timeIntervalSinceNow < min(-10, Double(length) * -1e-4) {
                    print("error on timeout")
                    throw CancellationError()
                }
            }
            catch {
                print(error)
                self.error = true
                isLive = false
                return nil
            }
        }
        if error || !isLive {
            return nil
        }
        return await buffer.read(position: position, length: Int(len1), read_start: read_start, read_end: read_end)
    }

    override public func read(position : Int64 = 0, length: Int = -1, onProgress: ((Int) async throws ->Void)? = nil) async throws -> Data? {
        if error {
            return nil
        }
        guard await initialized.wait(timeout: .seconds(30)) == .success else {
            return nil
        }
        var data = Data()
        if position >= size {
            return data
        }
        let length = length < 0 ? size - position : min(size - position, Int64(length))
        for p in stride(from: position, to: position + length, by: 32 * 1024) {
            let len = min(position + length - p, 32*1024)
            if !isLive { return nil }
            guard let d = try await subRead(position: p, length: Int(len)) else {
                return nil
            }
            data.append(d)
            try await onProgress?(Int(p))
        }
        return data
    }
}


public class RemoteNetworkStream: SlotStream {
    let remote: NetworkRemoteItem

    init(remote: NetworkRemoteItem) async {
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

    override func subFillBuffer(pos: ClosedRange<Int64>) async {
        guard pos.lowerBound >= 0 else { return }
        if isLive, await !buffer.dataAvailable(pos: pos) {
            let len = min(size-1, pos.upperBound) - max(0, pos.lowerBound) + 1
            let data = try? await remote.remoteStorage.readFile(fileId: remote.id, start: pos.lowerBound, length: len)
            if let data = data {
                await buffer.store(pos: pos.lowerBound, data: data)
            }
            else {
                print("error on readFile")
                error = true
            }
        }
    }
}

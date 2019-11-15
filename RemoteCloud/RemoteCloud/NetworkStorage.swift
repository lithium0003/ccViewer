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

public class NetworkStorage: RemoteStorageBase {
    var tokenDate: Date = Date(timeIntervalSince1970: 0)
    var cacheTokenDate: Date = Date(timeIntervalSince1970: 0)
    var tokenLife: TimeInterval = 0
    var lastCall = Date()
    let callSemaphore = DispatchSemaphore(value: 5)
    let callWait = 0.2
    var cache_accessToken = ""
    var cache_refreshToken = ""
    var accessToken: String {
        get {
            if let name = storageName {
                if let token = getKeyChain(key: "\(name)_accessToken") {
                    if cacheTokenDate == tokenDate {
                        cache_accessToken = token
                    }
                    else {
                        if setKeyChain(key: "\(name)_accessToken", value: cache_accessToken) {
                            tokenDate = cacheTokenDate
                        }
                    }
                }
                return cache_accessToken
            }
            else {
                return ""
            }
        }
    }
    var refreshToken: String {
        get {
            if let name = storageName {
                if let token = getKeyChain(key: "\(name)_refreshToken") {
                    if cacheTokenDate == tokenDate {
                        cache_refreshToken = token
                    }
                    else {
                        if setKeyChain(key: "\(name)_refreshToken", value: cache_refreshToken) {
                            tokenDate = cacheTokenDate
                        }
                    }
                }
                return cache_refreshToken
            }
            else {
                return ""
            }
        }
    }
    
    enum RetryError: Error {
        case Failed
        case Retry
    }
    
    public override func auth(onFinish: ((Bool) -> Void)?) -> Void {
        checkToken(){ success in
            if success {
                onFinish?(true)
            }
            else {
                self.isAuthorized(){ success in
                    if success {
                        onFinish?(true)
                    }
                    else {
                        DispatchQueue.main.async {
                            self.authorize(onFinish: onFinish)
                        }
                    }
                }
            }
        }
    }
    
    public override func logout() {
        if let name = storageName {
            if let aToken = getKeyChain(key: "\(name)_accessToken") {
                revokeToken(token: aToken, onFinish: nil)
            }
            let _ = delKeyChain(key: "\(name)_accessToken")
            let _ = delKeyChain(key: "\(name)_refreshToken")
            tokenDate = Date(timeIntervalSince1970: 0)
            tokenLife = 0
        }
        super.logout()
    }
    
    func checkToken(onFinish: ((Bool) -> Void)?) -> Void {
        //if Date() < cacheTokenDate + tokenLife - 5*60 {
        os_log("%{public}@", log: log, type: .debug, "\(Date()) \(cacheTokenDate),\(tokenLife)")
        if Date() < cacheTokenDate + tokenLife / 2 {
            onFinish?(true)
        }
        else if refreshToken == "" {
            onFinish?(false)
        }
        else {
            refreshToken(onFinish: onFinish)
        }
    }
    
    func saveToken(accessToken: String, refreshToken: String) -> Void {
        if let name = storageName {
            guard accessToken != "" && refreshToken != "" else {
                return
            }
            os_log("%{public}@", log: log, type: .info, "saveToken")
            cacheTokenDate = Date()
            cache_refreshToken = refreshToken
            cache_accessToken = accessToken
            if setKeyChain(key: "\(name)_accessToken", value: accessToken) && setKeyChain(key: "\(name)_refreshToken", value: refreshToken) {
                tokenDate = cacheTokenDate
            }
        }
    }
    
    func isAuthorized(onFinish: ((Bool) -> Void)?) -> Void {
        onFinish?(false)
    }
    
    func authorize(onFinish: ((Bool) -> Void)?) {
        onFinish?(false)
    }
    
    func getToken(oauthToken: String, onFinish: ((Bool) -> Void)?) {
        onFinish?(false)
    }
    
    func refreshToken(onFinish: ((Bool) -> Void)?) {
        onFinish?(false)
    }
    
    func revokeToken(token: String, onFinish: ((Bool) -> Void)?) {
        onFinish?(false)
    }
    
}

public class NetworkRemoteItem: RemoteItem {
    let remoteStorage: RemoteStorageBase
    
    override init?(storage: String, id: String) {
        guard let s = CloudFactory.shared[storage] as? RemoteStorageBase else {
            return nil
        }
        remoteStorage = s
        super.init(storage: storage, id: id)
    }
    
    public override func open() -> RemoteStream {
        return RemoteNetworkStream(remote: self)
    }
}

public class SlotStream: RemoteStream {
    let queue_buf = DispatchQueue(label: "io_data")
    let queue_wait = DispatchQueue(label: "io_wait")
    var waitlist: [Int64] = []
    var buffer: [Int64:Data] = [:]
    let bufSize:Int64 = 2*1024*1024
    let slotcount = 50
    let slotadvance: Int64 = 5
    var error = false
    
    var read_start: Int64 = 0
    var read_end: Int64 = 0
    let queue = DispatchQueue(label: "slot", attributes: [.concurrent])
    let queue_read = DispatchQueue(label: "read_wait")
    let init_group = DispatchGroup()
    
    override init(size: Int64) {
        super.init(size: size)
        firstFill()
    }

    override public func preload(position: Int64, length: Int) {
        let len1 = (position + Int64(length) < size) ? Int64(length) : size - position
        let read_start = position
        let read_end = position + len1 - 1
        for p in read_start/bufSize...read_end/bufSize+slotadvance {
            //print("fillbuffer \(p*bufSize)")
            fillBuffer(pos: p*bufSize)
        }
    }
    
    func firstFill() {
        self.queue.async {
            self.subFillBuffer(pos1: 0) {
            }
        }
        let slot = (size - bufSize) / bufSize
        self.queue.async {
            self.subFillBuffer(pos1: slot * self.bufSize) {
            }
        }
    }
    
    func dataAvailable(pos: Int64) -> Bool {
        return queue_buf.sync {
            for (key, buf) in buffer {
                if key <= pos && pos < key+Int64(buf.count)-1 {
                    //print("pos \(pos) hit")
                    return true
                }
            }
            //print("pos \(pos) none")
            return false
        }
    }
    
    func disposeBuffer() {
        if read_start < bufSize * 2 || read_end > size - bufSize*2 {
            return
        }
        queue_buf.async {
            if self.buffer.count > self.slotcount*2+10 {
                var del: [Int64] = []
                for (key, _) in self.buffer {
                    if key < self.bufSize*4 {
                        continue
                    }
                    if key > self.size - self.bufSize*5 {
                        continue
                    }
                    if self.read_start - self.bufSize*Int64(self.slotcount) > key || self.read_end + self.bufSize*Int64(self.slotcount) < key {
                        del += [key]
                    }
                }
                for d in del {
                    //print("del \(d)")
                    self.buffer[d] = nil
                }
            }
        }
    }
    
    func subFillBuffer(pos1: Int64, onFinish: @escaping ()->Void) {
        print("error on implimant")
        self.error = true
        onFinish()
    }
    
    func fillBuffer(pos: Int64) {
        if pos >= 0 && pos < size {
            let slot = pos / bufSize
            for i in slot...slot {
                let pos1 = i * bufSize
                if isLive && pos1 >= 0 && pos1 < size && !dataAvailable(pos: pos1) {
                    self.queue_wait.async {
                        if self.waitlist.contains(pos1) {
                            return
                        }
                        self.waitlist += [pos1]
                        self.queue.async {
                            self.subFillBuffer(pos1: pos1) {
                                self.queue_wait.async {
                                    self.waitlist.removeAll(where: { $0 == pos1 })
                                }
                            }
                        }
                    }
                }
            }
        }
        disposeBuffer()
    }
    
    override public func read(position : Int64, length: Int, onProgress: ((Int)->Bool)? = nil) -> Data? {
        guard init_group.wait(timeout: DispatchTime.now()+120) == DispatchTimeoutResult.success else {
            return nil
        }
        //print("read request \(position) + \(length)")
        let len1 = (position + Int64(length) < size) ? Int64(length) : size - position
        let read_start = position
        let read_end = position + len1 - 1
        for p in read_start/bufSize...read_end/bufSize+slotadvance {
            //print("fillbuffer \(p*bufSize)")
            fillBuffer(pos: p*bufSize)
        }
        let semaphore = DispatchSemaphore(value: 0)
        self.queue_read.async {
            let start = Date()
            while !self.error && self.isLive {
                var done = true
                var loadpos:Int64 = 0
                for p in read_start/self.bufSize...read_end/self.bufSize {
                    let slotdone = self.dataAvailable(pos: p*self.bufSize)
                    done = done && slotdone
                    if !slotdone {
                        //print("not filled buffer \(p*self.bufSize)")
                        loadpos = p*self.bufSize
                        break
                    }
                }
                if done {
                    let _ = onProgress?(Int(read_end))
                    break
                }
                if !(onProgress?(Int(loadpos)) ?? true) {
                    self.error = true
                    break
                }
                Thread.sleep(forTimeInterval: 1)
                if start.timeIntervalSinceNow < -120 {
                    print("error on timeout")
                    self.error = true
                }
                for p in read_start/self.bufSize...read_end/self.bufSize+self.slotadvance {
                    self.fillBuffer(pos: p*self.bufSize)
                }
            }
            semaphore.signal()
        }
        semaphore.wait()

        if error || !isLive {
            return nil
        }
        var ret: Data?
        var len = Int(len1)
        var p = position
        queue_buf.sync {
            self.read_start = read_start
            self.read_end = read_end
            
            for key in Array(buffer.keys).sorted() {
                guard let buf = buffer[key] else {
                    continue
                }
                if key <= p && p < key+Int64(buf.count) - 1 {
                    //print("pos \(p) key\(key)")
                    let s = Int(p - key)
                    let l = (len > buf.count - s) ? buf.count : len + s
                    //print("s\(s) l\(l) len\(len) count\(buf.count)")
                    if ret == nil {
                        ret = Data()
                    }
                    ret! += buf.subdata(in: s..<l)
                    len -= l-s
                    p += Int64(l-s)
                }
                if len == 0 {
                    break;
                }
            }
        }
        return ret
    }
}


public class RemoteNetworkStream: SlotStream {
    let remote: NetworkRemoteItem

    init(remote: NetworkRemoteItem) {
        self.remote = remote
        super.init(size: remote.size)
    }
    
    override func subFillBuffer(pos1: Int64, onFinish: @escaping ()->Void) {
        if !dataAvailable(pos: pos1) && isLive {
            let len = (pos1 + bufSize < size) ? bufSize : size - pos1
            remote.remoteStorage.readFile(fileId: remote.id, start: pos1, length: len) { data in
                defer {
                    onFinish()
                }
                if let data = data {
                    self.queue_buf.async {
                        self.buffer[pos1] = data
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

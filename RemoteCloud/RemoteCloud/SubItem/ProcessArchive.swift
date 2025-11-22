//
//  ProcessArchive.swift
//  RemoteCloud
//
//  Created by rei9 on 2025/11/15.
//  Copyright © 2025 lithium03. All rights reserved.
//

import Foundation
internal import UniformTypeIdentifiers

public class ArchiveBridge {
    let item: RemoteItem
    var stream: RemoteStream?
    var offset: Int64 = 0
    var buffer: Data?
    var sendBuffer: UnsafeMutableRawBufferPointer?
    nonisolated var selfref: UnsafeMutableRawPointer! {
        Unmanaged<ArchiveBridge>.passUnretained(self).toOpaque()
    }
    
    init(item: RemoteItem) {
        self.item = item
    }
    
    func setStream(_ stream: RemoteStream) async {
        self.stream = stream
        self.offset = 0
    }
    
    func setBuffer(_ buffer: Data?) {
        self.buffer = buffer
    }
    
    let archive_open_callback: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Int32 = {
        (archive, ref) in
        if let ref_unwrapped = ref {
            let myself = Unmanaged<ArchiveBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached(priority: .userInitiated) {
                defer {
                    semaphore.signal()
                }
                await myself.setStream(myself.item.open())
            }
            if semaphore.wait(timeout: .now()+10) == .timedOut {
                return ARCHIVE_FATAL
            }
            return ARCHIVE_OK
        }
        return ARCHIVE_FATAL
    }
    
    let archive_read_callback: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeRawPointer?>?) -> la_ssize_t = {
        (archive, ref, buffer) in
        if let ref_unwrapped = ref {
            let myself = Unmanaged<ArchiveBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            if let stream = myself.stream {
                let semaphore = DispatchSemaphore(value: 0)
                Task.detached(priority: .userInitiated) {
                    defer {
                        semaphore.signal()
                    }
                    await myself.setBuffer(try? stream.read(position: myself.offset, length: 1*1024*1024))
                }
                if semaphore.wait(timeout: .now() + 10) == .timedOut {
                    return -1
                }
                if let buf = myself.buffer {
                    if myself.sendBuffer != nil {
                        myself.sendBuffer?.deallocate()
                        myself.sendBuffer = nil
                    }
                    myself.offset += Int64(buf.count)
                    myself.sendBuffer = UnsafeMutableRawBufferPointer.allocate(byteCount: buf.count, alignment: 32)
                    buf.withUnsafeBytes { ptr in
                        _ = memcpy(myself.sendBuffer?.baseAddress!, ptr.baseAddress!, buf.count)
                    }
                    buffer?.pointee = UnsafeRawPointer(myself.sendBuffer?.baseAddress)
                    return la_ssize_t(buf.count)
                }
            }
        }
        return -1
    }
    
    let archive_skip_callback: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, la_int64_t) -> la_int64_t = {
        (archive, ref, request) in
        if let ref_unwrapped = ref {
            let myself = Unmanaged<ArchiveBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            let newoffset = min(myself.item.size, myself.offset + request)
            let skipcount = newoffset - myself.offset
            return skipcount
        }
        return 0
    }
    
    let archive_close_callback: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Int32 = {
        (archive, ref) in
        if let ref_unwrapped = ref {
            let myself = Unmanaged<ArchiveBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            myself.stream?.isLive = false
            myself.stream = nil
            myself.buffer = nil
            if myself.sendBuffer != nil {
                myself.sendBuffer?.deallocate()
                myself.sendBuffer = nil
            }
            return ARCHIVE_OK
        }
        return ARCHIVE_FATAL
    }
}

@concurrent
func processArchive(item: RemoteItem) async -> [String: (size: Int64, mdate: Date, cdata: Date)] {
    let a = archive_read_new()
    archive_read_support_format_all(a)
    archive_read_support_filter_all(a)
    let bridge = ArchiveBridge(item: item)
    var filelist: [String: (size: Int64, mdate: Date, cdata: Date)] = [:]
    if archive_read_open2(a, bridge.selfref, bridge.archive_open_callback, bridge.archive_read_callback, bridge.archive_skip_callback, bridge.archive_close_callback) == ARCHIVE_OK {
        defer {
            if let s = archive_error_string(a) {
                print(String(cString: s))
            }
            archive_read_free(a)
        }
        var entry: OpaquePointer?
        while (ARCHIVE_WARN...ARCHIVE_OK ~= archive_read_next_header(a, &entry)) {
            if Task.isCancelled {
                return filelist
            }
            guard let name = archive_entry_pathname(entry) else {
                continue
            }
            var pathname = ""
            if let utf8name = String(cString: name, encoding: .utf8) {
                pathname = utf8name
            }
            else if let sjisname = String(cString: name, encoding: .shiftJIS) {
                pathname = sjisname
            }
            else if let eucname = String(cString: name, encoding: .japaneseEUC) {
                pathname = eucname
            }
            if archive_entry_filetype(entry) & S_IFDIR > 0 {
                let mdate_t = Double(archive_entry_mtime(entry)) + Double(archive_entry_mtime_nsec(entry)) / 1_000_000_000.0
                let cdate_t = Double(archive_entry_birthtime(entry)) + Double(archive_entry_birthtime(entry)) / 1_000_000_000.0
                filelist[pathname] = (0, Date(timeIntervalSince1970: mdate_t), Date(timeIntervalSince1970: cdate_t))
            }
            else if archive_entry_filetype(entry) & S_IFREG > 0 {
                let size = archive_entry_size(entry)
                let mdate_t = Double(archive_entry_mtime(entry)) + Double(archive_entry_mtime_nsec(entry)) / 1_000_000_000.0
                let cdate_t = Double(archive_entry_birthtime(entry)) + Double(archive_entry_birthtime(entry)) / 1_000_000_000.0
                filelist[pathname] = (size, Date(timeIntervalSince1970: mdate_t), Date(timeIntervalSince1970: cdate_t))
            }
        }
    }
    for key in filelist.keys {
        let comp = key.components(separatedBy: "/").filter({ !$0.isEmpty })
        if comp.count > 1 {
            for i in 1..<comp.count {
                let parentDir = comp.dropLast(i).joined(separator: "/") + "/"
                if filelist[parentDir] == nil {
                    filelist[parentDir] = (0, Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 0))
                }
            }
        }
    }
    return filelist
}

@concurrent
func getDataFromArchive(item: RemoteItem, file: String) async -> Data? {
    let a = archive_read_new()
    archive_read_support_format_all(a)
    archive_read_support_filter_all(a)
    let bridge = ArchiveBridge(item: item)
    if archive_read_open2(a, bridge.selfref, bridge.archive_open_callback, bridge.archive_read_callback, bridge.archive_skip_callback, bridge.archive_close_callback) == ARCHIVE_OK {
        defer {
            archive_read_free(a)
        }
        var entry: OpaquePointer?
        while (ARCHIVE_WARN...ARCHIVE_OK ~= archive_read_next_header(a, &entry)) {
            if Task.isCancelled {
                return nil
            }
            guard let name = archive_entry_pathname(entry) else {
                continue
            }
            var pathname = ""
            if let utf8name = String(cString: name, encoding: .utf8) {
                pathname = utf8name
            }
            else if let sjisname = String(cString: name, encoding: .shiftJIS) {
                pathname = sjisname
            }
            else if let eucname = String(cString: name, encoding: .japaneseEUC) {
                pathname = eucname
            }
            if file == pathname {
                var data = Data()
                var buf = [UInt8](repeating: 0, count: 16384)
                while true {
                    let readLength = archive_read_data(a, &buf, buf.count)
                    if readLength < 0 { break }
                    data.append(buf, count: readLength)
                    if readLength < buf.count {
                        break
                    }
                }
                return data
            }
        }
    }
    return nil
}

public class ArchiveRemoteItem: RemoteItem {
    let baseItem: RemoteItem
    let filepath: String

    override init?(storage: String, id: String) async {
        let section = id.components(separatedBy: "\t")
        if section.count < 2 {
            return nil
        }
        filepath = section[1]
        guard let item = await CloudFactory.shared.storageList.get(storage)?.get(fileId: section[0]) else {
            return nil
        }
        baseItem = item
        await super.init(storage: storage, id: id)
    }
    
    public override func open() async -> RemoteStream {
        return await ArchiveStream(remote: self)
    }
    
    override public func mkdir(newname: String) async -> String? {
        return nil
    }
    
    override public func delete() async -> Bool{
        return false
    }
    
    override public func rename(newname: String) async -> String? {
        return nil
    }
    
    override public func changetime(newdate: Date) async -> String?{
        return nil
    }
    
    override public func move(toParentId: String) async -> String? {
        return nil
    }
    
    override public func read(start: Int64?, length: Int64?) async throws -> Data? {
        return nil
    }
}

public class ArchiveStream: SlotStream {
    let remote: ArchiveRemoteItem
    var itemData: Data?
    
    init(remote: ArchiveRemoteItem) async {
        self.remote = remote
        await super.init(size: remote.size)
    }
    
    override func fillHeader() async {
        defer {
            Task { await super.fillHeader() }
        }
        itemData = await getDataFromArchive(item: remote.baseItem, file: remote.filepath)
    }

    override func firstFill() async {
    }
    
    override func subFillBuffer(pos: ClosedRange<Int64>) async {
    }

    override public func read(position : Int64 = 0, length: Int = -1, onProgress: ((Int) async throws ->Void)? = nil) async throws -> Data? {
        if error {
            return nil
        }
        guard await initialized.wait(timeout: .seconds(30)) == .success else {
            return nil
        }
        guard let itemData = itemData else {
            return nil
        }
        if position >= itemData.count {
            return Data()
        }
        let length = length < 0 ? itemData.count - Int(position) : length
        let uppper = min(itemData.count, Int(position) + length)
        return itemData[Data.Index(position)..<uppper]
    }
}

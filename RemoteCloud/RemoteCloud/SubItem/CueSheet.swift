//
//  CueSheet.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/04/09.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreData

public class CueSheetRemoteItem: RemoteSubItem {
    public let baseItem: RemoteItem
    var wavitem: RemoteItem!
    var wavStream: RemoteStream!
    let track: Int
    
    override init?(storage: String, id: String) async {
        let section = id.components(separatedBy: "\t")
        guard section.count > 1, let p = section.last, let t = Int(p) else {
            return nil
        }
        guard let item = await CloudFactory.shared.data.getData(storage: storage, fileId: section.dropLast().joined(separator: "\t"))?.getItem() else {
            return nil
        }
        baseItem = item
        track = t
        
        await super.init(storage: storage, id: id)
        
        guard let wavid = subid?.dropFirst(3) else {
            return nil
        }
        guard let wavitem = await CloudFactory.shared.data.getData(storage: storage, fileId: String(wavid))?.getItem() else {
            return nil
        }
        self.wavitem = wavitem
        self.wavStream = await self.wavitem.open()
    }
    
    class func Create(from item: RemoteItem) async -> RemoteItem? {
        let viewContext = CloudFactory.shared.data.viewContext
        let itemid = item.id
        let storage = item.storage
        guard await CloudFactory.shared.data.listData(storage: storage, parentID: itemid).isEmpty else {
            return item
        }

        let stream = await item.open()
        guard let data = try? await stream.read() else {
            return nil
        }
        guard let cue = CueSheet(data: data) else {
            return nil
        }
        guard let wavname = cue.targetWave else {
            return nil
        }
        let itemparent = item.parent
        let wavId = await viewContext.perform { () -> String? in
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@ && name == %@", itemparent, storage, wavname)
            
            guard let result = try? viewContext.fetch(fetchRequest) as? [RemoteData], let wavdata = result.first else {
                return nil
            }
            return wavdata.id
        }
        guard let wavId, let wavitem = await CloudFactory.shared.data.getData(storage: storage, fileId: wavId)?.getItem() else {
            return nil
        }
        let wavstream = await wavitem.open()
        guard let wavFile = await RemoteWaveFile(stream: wavstream, size: wavitem.size) else {
            wavstream.isLive = false
            await wavitem.cancel()
            return nil
        }
        let bytesPerSec = wavFile.wavFormat.BitsPerSample/8 * wavFile.wavFormat.SampleRate * wavFile.wavFormat.NumChannels
        let bytesPerFrame = bytesPerSec / 75
        let endTime = wavFile.wavSize / bytesPerFrame
        
        var diskTitle: String?
        var diskPerformer: String?
        for (index, track) in cue.tracks.enumerated() {
            if index == 0 {
                diskTitle = track["title"] as? String
                diskPerformer = track["performer"] as? String
                continue
            }
            
            let id = "\(item.id)\t\(index)"
            guard let title = track["title"] as? String ?? diskTitle else {
                continue
            }
            guard let performer = track["performer"] as? String ?? diskPerformer else {
                continue
            }
            let name = String(format: "%02d : %@ - %@", index, performer, title)
            guard let start = track["start"] as? Int64 else {
                continue
            }
            let end = track["end"] as? Int64 ?? Int64(endTime)
            let size = 44 + (end - start) * Int64(bytesPerFrame)
            let timelen = Double(end - start) / 75.0
            var sec = Int(timelen)
            let msec = Int((timelen - Double(sec))*1000)
            let min = Int(sec / 60)
            sec -= min * 60
            let infostr = String(format: "%02d:%02d.%03d", min, sec, msec)
            
            let newitem = RemoteData(context: viewContext)
            newitem.storage = storage
            newitem.id = id
            newitem.name = name
            newitem.ext = "wav"
            newitem.cdate = item.cDate
            newitem.mdate = item.mDate
            newitem.folder = false
            newitem.size = size
            newitem.hashstr = ""
            newitem.parent = item.id
            newitem.path = item.path + "/\(index)"
            newitem.substart = start
            newitem.subend = end
            newitem.subid = "WAV"+wavId
            newitem.subinfo = infostr
        }
        await viewContext.perform {
            try? viewContext.save()
        }
        return item
    }

    public override func open() async -> RemoteStream {
        return await CueSheetStream(remote: self)
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
        return try await wavStream.read(position: start ?? 0, length: Int(length ?? wavitem.size))
    }
}

public class CueSheetStream: SlotStream {
    let remote: CueSheetRemoteItem
    var header: Data?
    var wavOffset: Int = -1
    
    init(remote: CueSheetRemoteItem) async {
        self.remote = remote
        await super.init(size: remote.size)
    }

    override func setLive(_ live: Bool) {
        if !live {
            let sem = DispatchSemaphore(value: 0)
            Task {
                defer {
                    sem.signal()
                }
                await remote.cancel()
            }
            sem.wait()
        }
    }

    override func setError(_ isError: Bool) {
        if isError {
            isLive = false
        }
    }

    override func fillHeader() async {
        let frames = remote.subend - remote.substart
        let stream = await remote.wavitem.open()
        guard let wavfile = await RemoteWaveFile(stream: stream, size: remote.wavitem.size) else {
            error = true
            await super.fillHeader()
            return
        }
        header = wavfile.getHeader(frames: frames)
        guard let header = header else {
            error = true
            await super.fillHeader()
            return
        }
        let bytesPerSec = wavfile.wavFormat.BitsPerSample/8 * wavfile.wavFormat.SampleRate * wavfile.wavFormat.NumChannels
        let bytesPerFrame = bytesPerSec / 75

        size = Int64(bytesPerFrame * Int(frames) + header.count)
        
        wavOffset = wavfile.wavOffset + Int(remote.substart) * bytesPerFrame
        await super.fillHeader()
    }

    override func subFillBuffer(pos: ClosedRange<Int64>) async {
        guard await initialized.wait(timeout: .seconds(10)) == .success else {
            error = true
            return
        }
        if await !buffer.dataAvailable(pos: pos), isLive {
            let len = min(size-1, pos.upperBound) - pos.lowerBound + 1
            guard let header = header else {
                error = true
                return
            }
            if pos.lowerBound < header.count {
                if let data = try? await remote.read(start: Int64(wavOffset), length: len-Int64(header.count)) {
                    var result = Data()
                    result += header
                    result += data
                    result = result[pos]
                    await buffer.store(pos: pos.lowerBound, data: result)
                }
                else {
                    print("error on readFile")
                    error = true
                }
            }
            else {
                let ppos1 = pos.lowerBound - Int64(header.count) + Int64(wavOffset)
                if let data = try? await remote.read(start: ppos1, length: len) {
                    await buffer.store(pos: pos.lowerBound, data: data)
                }
                else {
                    print("error on readFile")
                    error = true
                }
            }
        }
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { self.append(contentsOf: $0) }
    }
}

class RemoteWaveFile {
    let remoteStream: RemoteStream
    let size: Int64
    
    var fileEnd = -1
    var wavSize = -1
    var wavOffset = -1
    var wavFormat: WaveFormatData!
    
    struct WaveFormatData {
        var AudioFormat: Int
        var NumChannels: Int
        var SampleRate: Int
        var ByteRate: Int
        var BlockAlign: Int
        var BitsPerSample: Int
    }
    
    init?(stream: RemoteStream, size: Int64) async {
        self.remoteStream = stream
        self.size = size
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.load()
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(60))
                    throw CancellationError()
                }
                let _ = try await group.next()!
                group.cancelAll()
            }
        }
        catch {
            return nil
        }
        guard wavFormat != nil, wavSize > 0, wavOffset > 0 else {
            return nil
        }
    }

    func getHeader(frames: Int64) -> Data {
        let bytesPerSec = wavFormat.BitsPerSample/8 * wavFormat.SampleRate * wavFormat.NumChannels
        let bytesPerFrame = bytesPerSec / 75
        let wavbytes = Int(frames) * bytesPerFrame
        
        var ret = Data()
        ret += "RIFF".data(using: .ascii)!
        ret.appendLittleEndian(UInt32(wavbytes + 36))
        
        ret += "WAVE".data(using: .ascii)!
        ret += "fmt ".data(using: .ascii)!
        
        ret.appendLittleEndian(UInt32(16)) // SubChunk1Size
        ret.appendLittleEndian(UInt16(1))  // AudioFormat (PCM)
        ret.appendLittleEndian(UInt16(wavFormat.NumChannels))
        ret.appendLittleEndian(UInt32(wavFormat.SampleRate))
        ret.appendLittleEndian(UInt32(wavFormat.ByteRate))
        ret.appendLittleEndian(UInt16(wavFormat.BlockAlign))
        ret.appendLittleEndian(UInt16(wavFormat.BitsPerSample))
        
        ret += "data".data(using: .ascii)!
        ret.appendLittleEndian(UInt32(wavbytes)) // SubChunk2Size
        
        return ret
    }
    
    func load() async {
        var ChunkSize: UInt32 = 0
        guard let data = try? await remoteStream.read(position: 0, length: 12), data.count == 12 else {
            return
        }
        let ChunkID = data.subdata(in: 0..<4)
        guard String(data: ChunkID, encoding: .ascii) == "RIFF" else {
            return
        }
        ChunkSize = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
        let Format = data.subdata(in: 8..<12)
        guard String(data: Format, encoding: .ascii) == "WAVE" else {
            return
        }
        fileEnd = Int(ChunkSize+8)
        await loadSubChunk(pos: 12)
    }
    
    func loadSubChunk(pos: UInt32) async {
        guard let data = try? await remoteStream.read(position: Int64(pos), length: 8), data.count == 8 else {
            return
        }
        let ChunkID = data.subdata(in: 0..<4)
        let ChunkSize = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
        if String(data: ChunkID, encoding: .ascii) == "fmt " {
            await loadFmtSubChunk(pos: pos+8, ChunkSize: ChunkSize)
        }
        else if String(data: ChunkID, encoding: .ascii) == "data" {
            wavSize = Int(ChunkSize)
            wavOffset = Int(pos+8)
        }
        if pos+8+ChunkSize >= fileEnd {
            return
        }
        await loadSubChunk(pos: pos+8+ChunkSize)
    }
    
    func loadFmtSubChunk(pos: UInt32, ChunkSize: UInt32) async {
        guard ChunkSize >= 16 else {
            return
        }
        guard let data = try? await remoteStream.read(position: Int64(pos), length: Int(ChunkSize)), data.count == ChunkSize else {
            return
        }

        data.withUnsafeBytes { ptr in
            let AudioFormat = ptr.loadUnaligned(fromByteOffset: 0, as: UInt16.self)
            guard AudioFormat == 1 else { return } // PCM == 1
            
            let NumChannels = ptr.loadUnaligned(fromByteOffset: 2, as: UInt16.self)
            let SampleRate = ptr.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
            let ByteRate = ptr.loadUnaligned(fromByteOffset: 8, as: UInt32.self)
            let BlockAlign = ptr.loadUnaligned(fromByteOffset: 12, as: UInt16.self)
            let BitsPerSample = ptr.loadUnaligned(fromByteOffset: 14, as: UInt16.self)
            
            wavFormat = WaveFormatData(AudioFormat: Int(AudioFormat), NumChannels: Int(NumChannels), SampleRate: Int(SampleRate), ByteRate: Int(ByteRate), BlockAlign: Int(BlockAlign), BitsPerSample: Int(BitsPerSample))
        }
    }
}

class CueSheet {
    var tracks = [[String: Any]]()
    var targetWave: String?
    
    init?(data: Data) {
        tracks += [[String: Any]()]
        guard loadCue(data: data) else {
            return nil
        }
    }
    
    func loadCue(data: Data) -> Bool {
        if let text = String(data: data, encoding: .utf8) {
            guard parseCue(lines: text) else {
                return false
            }
            return true
        }
        else if let text2 = String(data: data, encoding: .shiftJIS) {
            guard parseCue(lines: text2) else {
                return false
            }
            return true
        }
        else if let text3 = String(data: data, encoding: .unicode) {
            guard parseCue(lines: text3) else {
                return false
            }
            return true
        }
        return false
    }
    
    func parseCue(lines: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #""(.*)""#) else {
            return false
        }
        var pass = true
        var lastTrack = 0
        var lastIndex = -1
        lines.enumerateLines { (line,stop)->Void in
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.uppercased().hasPrefix("PERFORMER") {
                let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.count))
                if matches.count > 0 {
                    let range = matches[0].range(at: 1)
                    let result = (line as NSString).substring(with: range)
                    
                    self.tracks[lastTrack]["performer"] = result
                }
            }
            else if line.uppercased().hasPrefix("TITLE") {
                let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.count))
                if matches.count > 0 {
                    let range = matches[0].range(at: 1)
                    let result = (line as NSString).substring(with: range)
                    
                    self.tracks[lastTrack]["title"] = result
                }
            }
            else if line.uppercased().hasPrefix("FILE") {
                guard line.uppercased().hasSuffix("WAVE") else {
                    pass = false
                    stop = true
                    return
                }
                let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.count))
                if matches.count > 0 {
                    let range = matches[0].range(at: 1)
                    let result = (line as NSString).substring(with: range)
                    
                    self.targetWave = result
                }
            }
            else if line.uppercased().hasPrefix("TRACK") && line.uppercased().hasSuffix("AUDIO") {
                let section = line.components(separatedBy: .whitespaces)
                guard section.count == 3 else {
                    pass = false
                    stop = true
                    return
                }
                guard let track = Int(section[1]), track == lastTrack+1 else {
                    pass = false
                    stop = true
                    return
                }
                lastTrack = track
                lastIndex = -1
                self.tracks += [[String: Any]()]
            }
            else if line.uppercased().hasPrefix("INDEX") {
                let section = line.components(separatedBy: .whitespaces)
                guard section.count == 3 else {
                    pass = false
                    stop = true
                    return
                }
                guard let index = Int(section[1]) else {
                    pass = false
                    stop = true
                    return
                }
                let timestr = section[2].components(separatedBy: ":")
                guard timestr.count == 3 else {
                    pass = false
                    stop = true
                    return
                }
                guard let min = Int(timestr[0]), let sec = Int(timestr[1]), let frame = Int(timestr[2]) else {
                    pass = false
                    stop = true
                    return
                }
                let t = Int64(((min * 60) + sec) * 75 + frame) // 75 frames/sec
                if (lastIndex < 0 && index == 1) || index == 0 {
                    if lastTrack > 1 {
                        self.tracks[lastTrack-1]["end"] = t
                    }
                }
                if index == 1 {
                    self.tracks[lastTrack]["start"] = t
                }
            }
        }
        guard targetWave != nil else {
            return false
        }
        return pass
    }
}

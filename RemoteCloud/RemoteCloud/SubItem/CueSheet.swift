//
//  CueSheet.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/04/09.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation

public class CueSheetRemoteItem: RemoteItem {
    let baseItem: RemoteItem
    var wavitem: RemoteItem!
    var wavStream: RemoteStream!
    let track: Int
    
    override init?(storage: String, id: String) {
        let section = id.components(separatedBy: "\t")
        if section.count < 2 {
            return nil
        }
        guard let item = CloudFactory.shared[storage]?.get(fileId: section[0]) else {
            return nil
        }
        baseItem = item
        guard let t = Int(section[1]) else {
            return nil
        }
        track = t
        
        super.init(storage: storage, id: id)
        
        guard let wavid = subid else {
            return nil
        }
        guard let wavitem = CloudFactory.shared[storage]?.get(fileId: wavid) else {
            return nil
        }
        self.wavitem = wavitem
        self.wavStream = self.wavitem.open()
    }
    
    public override func open() -> RemoteStream {
        return CueSheetStream(remote: self)
    }
    
    override public func mkdir(newname: String, onFinish: ((String?)->Void)?){
        onFinish?(nil)
    }
    
    override public func delete(onFinish: ((Bool)->Void)?){
        onFinish?(false)
    }
    
    override public func rename(newname: String, onFinish: ((String?)->Void)?) {
        onFinish?(nil)
    }
    
    override public func changetime(newdate: Date, onFinish: ((String?)->Void)?) {
        onFinish?(nil)
    }
    
    override public func move(toParentId: String, onFinish: ((String?)->Void)?) {
        onFinish?(nil)
    }
    
    override public func read(start: Int64?, length: Int64?, onFinish: ((Data?)->Void)?){
        if let onFinish = onFinish {
            wavStream.read(position: start ?? 0, length: Int(length ?? wavitem.size), onFinish: onFinish)
        }
    }
}

public class CueSheetStream: SlotStream {
    let remote: CueSheetRemoteItem
    var header: Data?
    var wavOffset: Int = -1
    
    init(remote: CueSheetRemoteItem) {
        self.remote = remote
        super.init(size: remote.size)
    }
    
    override func firstFill() {
        fillHeader()
        super.firstFill()
    }
    
    func fillHeader() {
        init_group.enter()
        DispatchQueue.global().async {
            defer {
                self.init_group.leave()
            }
            let frames = self.remote.subend - self.remote.substart
            let stream = self.remote.wavitem.open()
            guard let wavfile = RemoteWaveFile(stream: stream, size: self.remote.wavitem.size) else {
                self.error = true
                return
            }
            stream.isLive = false
            self.header = wavfile.getHeader(frames: frames)
            guard let header = self.header else {
                self.error = true
                return
            }
            let bytesPerSec = wavfile.wavFormat.BitsPerSample/8 * wavfile.wavFormat.SampleRate * wavfile.wavFormat.NumChannels
            let bytesPerFrame = bytesPerSec / 75

            self.size = Int64(bytesPerFrame * Int(frames) + header.count)
            
            self.wavOffset = wavfile.wavOffset + Int(self.remote.substart) * bytesPerFrame
        }
    }
    
    override func subFillBuffer(pos1: Int64, onFinish: @escaping ()->Void) {
        guard init_group.wait(timeout: DispatchTime.now()+120) == DispatchTimeoutResult.success else {
            self.error = true
            onFinish()
            return
        }
        if !dataAvailable(pos: pos1) && isLive {
            let len = (pos1 + bufSize < size) ? bufSize : size - pos1
            guard let header = self.header else {
                self.error = true
                onFinish()
                return
            }
            if pos1 == 0 {
                
                remote.read(start: Int64(wavOffset), length: len-Int64(header.count)) { data in
                    defer {
                        onFinish()
                    }
                    if let data = data {
                        var result = Data()
                        result += header
                        result += data

                        self.queue_buf.async {
                            self.buffer[pos1] = result
                        }
                    }
                    else {
                        print("error on readFile")
                        self.error = true
                    }
                }
            }
            else {
                let ppos1 = pos1 - Int64(header.count) + Int64(wavOffset)
                remote.read(start: ppos1, length: len) { data in
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

}

class RemoteWaveFile {
    let remoteStream: RemoteStream
    let size: Int64
    
    let group = DispatchGroup()
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
    
    init?(stream: RemoteStream, size: Int64) {
        self.remoteStream = stream
        self.size = size
        group.enter()
        load()
        guard group.wait(timeout: .now()+10) == .success else {
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
        var ChunkSize = UInt32(wavbytes + 36)
        ret += Data(buffer: UnsafeBufferPointer(start: &ChunkSize, count: 1))
        ret += "WAVE".data(using: .ascii)!
        
        ret += "fmt ".data(using: .ascii)!
        var SubChunk1Size = UInt32(16)
        ret += Data(buffer: UnsafeBufferPointer(start: &SubChunk1Size, count: 1))
        var AudioFormat = UInt16(1)
        ret += Data(buffer: UnsafeBufferPointer(start: &AudioFormat, count: 1))
        var NumChannels = UInt16(wavFormat.NumChannels)
        ret += Data(buffer: UnsafeBufferPointer(start: &NumChannels, count: 1))
        var SampleRate = UInt32(wavFormat.SampleRate)
        ret += Data(buffer: UnsafeBufferPointer(start: &SampleRate, count: 1))
        var ByteRate = UInt32(wavFormat.ByteRate)
        ret += Data(buffer: UnsafeBufferPointer(start: &ByteRate, count: 1))
        var BlockAlign = UInt16(wavFormat.BlockAlign)
        ret += Data(buffer: UnsafeBufferPointer(start: &BlockAlign, count: 1))
        var BitsPerSample = UInt16(wavFormat.BitsPerSample)
        ret += Data(buffer: UnsafeBufferPointer(start: &BitsPerSample, count: 1))

        ret += "data".data(using: .ascii)!
        var SubChunk2Size = UInt32(wavbytes)
        ret += Data(buffer: UnsafeBufferPointer(start: &SubChunk2Size, count: 1))
        
        return ret
    }
    
    func load() {
        var ChunkSize: UInt32 = 0
        remoteStream.read(position: 0, length: 12) { data in
            guard let data = data, data.count == 12 else {
                return
            }
            let ChunkID = data.subdata(in: 0..<4)
            guard String(data: ChunkID, encoding: .ascii) == "RIFF" else {
                return
            }
            ChunkSize = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
            let Format = data.subdata(in: 8..<12)
            guard String(data: Format, encoding: .ascii) == "WAVE" else {
                return
            }
            self.fileEnd = Int(ChunkSize+8)
            self.loadSubChunk(pos: 12)
        }
    }
    
    func loadSubChunk(pos: UInt32) {
        remoteStream.read(position: Int64(pos), length: 8) { data in
            guard let data = data, data.count == 8 else {
                return
            }
            let ChunkID = data.subdata(in: 0..<4)
            let ChunkSize = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
            if String(data: ChunkID, encoding: .ascii) == "fmt " {
                self.loadFmtSubChunk(pos: pos+8, ChunkSize: ChunkSize)
            }
            else if String(data: ChunkID, encoding: .ascii) == "data" {
                self.wavSize = Int(ChunkSize)
                self.wavOffset = Int(pos+8)
            }
            if pos+8+ChunkSize >= self.fileEnd {
                self.group.leave()
                return
            }
            self.loadSubChunk(pos: pos+8+ChunkSize)
        }
    }
    
    func loadFmtSubChunk(pos: UInt32, ChunkSize: UInt32) {
        guard ChunkSize >= 16 else {
            return
        }
        self.group.enter()
        remoteStream.read(position: Int64(pos), length: Int(ChunkSize)) { data in
            defer {
                self.group.leave()
            }
            guard let data = data, data.count == ChunkSize else {
                return
            }

            let AudioFormat = data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self) }
            guard AudioFormat == 1 else { // PCM == 1
                return
            }
            let NumChannels = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self) }
            let SampleRate = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
            let ByteRate = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }
            let BlockAlign = data.subdata(in: 12..<14).withUnsafeBytes { $0.load(as: UInt16.self) }
            let BitsPerSample = data.subdata(in: 14..<16).withUnsafeBytes { $0.load(as: UInt16.self) }
            self.wavFormat = WaveFormatData(AudioFormat: Int(AudioFormat), NumChannels: Int(NumChannels), SampleRate: Int(SampleRate), ByteRate: Int(ByteRate), BlockAlign: Int(BlockAlign), BitsPerSample: Int(BitsPerSample))
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

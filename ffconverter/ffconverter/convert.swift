//
//  convert.swift
//  ffconverter
//
//  Created by rei8 on 2019/09/06.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import RemoteCloud

final class FrameworkResource {
    static func getImage(name: String) -> UIImage? {
        return UIImage(named: name, in: Bundle(for: self), compatibleWith: nil)
    }
    static func getLocalized(key: String) -> String {
        return Bundle(for: self).localizedString(forKey: key, value: nil, table: nil)
    }
}

public class ConvertIteminfo {
    public var item: RemoteItem
    public var startpos: Double?
    public var playduration: Double?
    
    public init(item: RemoteItem, startpos: Double? = nil, playduration: Double? = nil) {
        self.item = item
        self.startpos = startpos
        self.playduration = playduration
    }
}

public class PlayItemInfo {
    public var videos: [Int: String] = [:]
    public var subtitle: [Int: String] = [:]
    public var mainVideo = -1
    public var mainSubtitle = -1
}

public class Converter {
    static var converter: convert?
    static let queue = DispatchQueue(label: "touch")
    
    public class func IsCasting() -> Bool {
        return converter != nil
    }
    
    public class func Start() {
        if converter == nil {
            converter = convert()
        }
    }
    
    public class func Stop() {
        if converter != nil {
            converter?.finish()
            converter = nil
        }
    }
    
    public class func Done(targetPath: String) {
        guard let c = converter else {
            return
        }
        c.playdone(targetPath: targetPath)
    }
    
    public class func Play(item: ConvertIteminfo, local: Bool, onSelect: @escaping (PlayItemInfo)->(Int, Int)?, onReady: @escaping (Bool)->Void) -> URL? {
        guard let c = converter else {
            return nil
        }
        return c.play(info: item, local: local, onSelect: onSelect, onReady: onReady)
    }
    
    public class func touch(randID: String, segment: Int) {
        guard let c = converter else {
            return
        }
        guard let r = c.get_running(item: randID) else {
            return
        }
        c.set_lasttouch(item: randID, t: Date())
        DispatchQueue.global().async {
            c.cleanfolder()
        }
        queue.async {
            if segment < 0 {
                for w in r.encoder.writer {
                    w?.set_touch(count: segment)
                }
            }
        }
    }
}

class convert {
    let server: HTTPserver
    let baseURL: URL
    var port: UInt16
    private var running: [String: StreamBridgeConvert] = [:]
    private var holdfiles: [String: URL] = [:]
    private var items: [String: String] = [:]
    private var lasttouch: [String: Date] = [:]
    
    let semaphore_arg = DispatchSemaphore(value: 1)

    func get_running(item: String) -> StreamBridgeConvert? {
        semaphore_arg.wait()
        defer {
            semaphore_arg.signal()
        }
        return running[item]
    }
    
    func get_holdfiles(item: String) -> URL? {
        semaphore_arg.wait()
        defer {
            semaphore_arg.signal()
        }
        return holdfiles[item]
    }
    
    func get_items(item: String) -> String? {
        semaphore_arg.wait()
        defer {
            semaphore_arg.signal()
        }
        return items[item]
    }
    
    func get_lasttouch(item: String) -> Date? {
        semaphore_arg.wait()
        defer {
            semaphore_arg.signal()
        }
        return lasttouch[item]
    }
    
    func set_lasttouch(item: String, t: Date) {
        semaphore_arg.wait()
        defer {
            semaphore_arg.signal()
        }
        lasttouch[item] = t
    }
    
    init?() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        baseURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return nil
        }
        while !FileManager.default.fileExists(atPath: baseURL.path) {
            sleep(1)
        }
        var retry = 100
        while retry > 0 {
            retry -= 1
            port = UInt16.random(in: 49152...65535)
            guard let s = HTTPserver(baseUrl: baseURL, port: port) else {
                continue
            }
            server = s
            return
        }
        return nil
    }
    
    deinit {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        finish()
    }
    
    func finish() {
        semaphore_arg.wait()
        defer {
            semaphore_arg.signal()
        }
        for (_,r) in running {
            r.abort()
        }
        server.Stop()
        do {
            try FileManager.default.removeItem(at: baseURL)
        } catch {
            print("Could not clear temp folder: \(error)")
        }
    }
    
    func cleanfolder() {
        semaphore_arg.wait()
        defer {
            semaphore_arg.signal()
        }
        var liveID = ""
        var liveTime = Date(timeIntervalSince1970: 0)
        for (_, randID) in items {
            if let t = lasttouch[randID] {
                if t > liveTime {
                    liveID = randID
                    liveTime = t
                }
            }
        }
        for (itemid, randID) in items {
            if randID == liveID {
                continue
            }
            if let t = lasttouch[randID] {
                if t < Date(timeIntervalSinceNow: -30) {
                    // finish old convert
                    print("remove folder:", randID)
                    if let r = running[randID] {
                        r.abort()
                    }
                    if let urlout = holdfiles[randID] {
                        do {
                            try FileManager.default.removeItem(at: urlout)
                        } catch {
                            print("Could not clear temp folder: \(error)")
                        }
                        holdfiles[randID] = nil
                    }
                    lasttouch[randID] = nil
                    items[itemid] = nil
                }
            }
        }
    }
    
    func playdone(targetPath: String) {
        semaphore_arg.wait()
        defer {
            semaphore_arg.signal()
        }
        guard let randID = items[targetPath] else {
            return
        }
        
        if let r = running[randID] {
            r.abort()
        }
        if let urlout = holdfiles[randID] {
            do {
                try FileManager.default.removeItem(at: urlout)
            } catch {
                print("Could not clear temp folder: \(error)")
            }
            holdfiles[randID] = nil
        }
        items[targetPath] = nil
    }
    
    func play(info: ConvertIteminfo, local: Bool, onSelect: @escaping (PlayItemInfo)->(Int, Int)?, onReady: @escaping (Bool)->Void) -> URL? {
        guard let host = HTTPserver.getWiFiAddress() else {
            return nil
        }

        let item = info.item
        if let id = get_items(item: item.path) {
            onReady(true)
            return URL(string: "http://\(local ? "localhost" : host):\(port)/\(id)/stream.m3u8")!
        }
        
        let randID = UUID().uuidString
        let urlout = baseURL.appendingPathComponent(randID)
        do {
            try FileManager.default.createDirectory(at: urlout, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return nil
        }
        while !FileManager.default.fileExists(atPath: urlout.path) {
            sleep(1)
        }
        var tencoder: Encoder? = nil
        var count = 3
        while tencoder == nil, count > 0 {
            tencoder = Encoder(dest: urlout)
            count -= 1
        }
        guard let encoder = tencoder else {
            return nil
        }
        do {
            semaphore_arg.wait()
            defer {
                semaphore_arg.signal()
            }
            items[item.path] = randID
        }
        let playURL = URL(string: "http://\(local ? "localhost" : host):\(port)/\(randID)/stream.m3u8")!
        DispatchQueue.global().async {
            let bridge = StreamBridgeConvert(info: info, name: item.name, encoder: encoder)
            bridge.onSelect = onSelect
            bridge.onReady = onReady
            do {
                self.semaphore_arg.wait()
                defer {
                    self.semaphore_arg.signal()
                }
                self.running[randID] = bridge
                self.holdfiles[randID] = urlout
                self.lasttouch[randID] = Date()
            }
            bridge.run() {
                self.semaphore_arg.wait()
                defer {
                    self.semaphore_arg.signal()
                }
                self.running[randID] = nil
                onReady(false)
            }
        }
        return playURL
    }
}

class StreamBridgeConvert {
    let encoder: Encoder
    let remote: RemoteItem
    let stream: RemoteStream
    let name: String
    var selfref: UnsafeMutableRawPointer!
    let semaphore = DispatchSemaphore(value: 1)
    var isCancel = false
    var sdlparam: UnsafeMutableRawPointer!
    var playing = false
    var position: Int64 = 0
    var info: ConvertIteminfo
    var onSelect: ((PlayItemInfo)->(Int, Int)?)?
    var onReady: ((Bool)->Void)?
    
    init(info: ConvertIteminfo, name: String, encoder: Encoder) {
        self.info = info
        let item = info.item
        self.remote = item
        self.stream = item.open()
        self.name = name
        self.encoder = encoder
        self.selfref = Unmanaged<StreamBridgeConvert>.passUnretained(self).toOpaque()
    }

    let encode: @convention(c) (UnsafeMutableRawPointer?, Double, Int32, UnsafeMutablePointer<UInt8>?, Int32, Int32) -> Void = {
        (ref, pts, key, src_data, src_linesize, src_height) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridgeConvert>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.encoder.encode_frame(src_data: src_data, src_linesize: src_linesize, src_height: src_height, pts: pts, key: key == 1)
        }
    }
    
    let encode_sound: @convention(c) (UnsafeMutableRawPointer?, Double, UnsafeMutablePointer<UInt8>?, Int32, Int32) -> Void = {
        (ref, pts, src_data, src_size, ch) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridgeConvert>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            let data = UnsafeBufferPointer(start: src_data, count: Int(src_size))
            stream.encoder.encode_sound(channel: Int(ch), pcm_data: data, pts: pts)
        }
    }

    let encode_text: @convention(c) (UnsafeMutableRawPointer?, Double, Double, UnsafePointer<CChar>?, Int32, Int32) -> Void = {
        (ref, pts_start, pts_end, text, ass, ch) in
        if let ref_unwrapped = ref, let text_unwrapped = text {
            let stream = Unmanaged<StreamBridgeConvert>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            let caption = String(cString: text_unwrapped)
            stream.encoder.encode_text(channel: Int(ch), text: convertText(text: caption, ass: ass == 1), pts_start: pts_start, pts_end: pts_end)
        }
    }

    class func convertText(text: String, ass: Bool) -> String {
        let txtArray = text.components(separatedBy: .newlines)
        if ass {
            var ret = ""
            for assline in txtArray {
                guard let p1 = assline.firstIndex(of: ":") else {
                    continue
                }
                var asstext = assline[p1...].dropFirst()
                var invalid = false
                for _ in 0..<9 {
                    guard let p2 = asstext.firstIndex(of: ",") else {
                        invalid = true
                        break
                    }
                    asstext = asstext[p2...].dropFirst()
                }
                if invalid {
                    continue
                }
                let cmdremoved = asstext.replacingOccurrences(of: "{\\.*}", with: "", options: .regularExpression, range: asstext.range(of: asstext))
                let result = cmdremoved.replacingOccurrences(of: "\\\\[Nn]", with: "\n", options: .regularExpression, range: cmdremoved.range(of: cmdremoved))
                ret += result
            }
            return ret
        }
        else {
            return txtArray.joined(separator: "\n")
        }
    }

    let cancel: @convention(c) (UnsafeMutableRawPointer?) -> Void = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridgeConvert>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.isCancel = true
            stream.stream.isLive = false
            stream.remote.cancel()
            stream.semaphore.signal()
        }
    }

    let finish: @convention(c) (UnsafeMutableRawPointer?) -> Void = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridgeConvert>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.encoder.isLive = false
            for writer in stream.encoder.writer {
                writer?.set_touch(count: -1)
            }
        }
    }

    let stream_count: @convention(c) (UnsafeMutableRawPointer?, Int32, Int32, UnsafePointer<UnsafePointer<CChar>?>?, Int32, Int32, UnsafePointer<UnsafePointer<CChar>?>?) -> Void = {
        (ref, audios, main_audio, audio_lng, subtitles, main_subtitle, subtitle_lng) in
        if let ref_unwrapped = ref, let alang = audio_lng {
            let stream = Unmanaged<StreamBridgeConvert>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            let audio_language = UnsafeBufferPointer(start: alang, count: Int(audios))
            var audio_lang = [String](repeating: "und", count: Int(audios))
            for i in 0..<Int(audios) {
                audio_lang[i] = String(cString: audio_language[i]!)
            }
            var subtitle_lang = [String](repeating: "und", count: Int(subtitles))
            if let slang = subtitle_lng {
                let subtitle_language = UnsafeBufferPointer(start: slang, count: Int(subtitles))
                for i in 0..<Int(subtitles) {
                    subtitle_lang[i] = String(cString: subtitle_language[i]!)
                }
            }
            stream.encoder.set_streamCount(audio_lng: audio_lang, audio_main: Int(main_audio), subtitle_lng: subtitle_lang, subtitle_main: Int(main_subtitle))
        }
    }

    let read_packet: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32 = {
        (ref, buf, buf_size) in
        var count = 0
        if let ref_unwrapped = ref, let buf_unwrapped = buf {
            let buf_array = UnsafeMutableBufferPointer<UInt8>(start: buf_unwrapped, count: Int(buf_size))
            let stream = Unmanaged<StreamBridgeConvert>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            if stream.isCancel {
                return 0
            }
            stream.semaphore.wait()
            stream.stream.read(position: stream.position, length: Int(buf_size)) { data in
                defer {
                    stream.semaphore.signal()
                }
                if stream.isCancel {
                    return
                }
                if let data = data {
                    count = data.copyBytes(to: buf_array)
                }
            }
            var result: DispatchTimeoutResult = .timedOut
            while result == .timedOut && !stream.isCancel {
                result = stream.semaphore.wait(wallTimeout: .now()+1)
            }
            stream.semaphore.signal()
            stream.position += Int64(count)
        }
        return Int32(count)
    }
    
    let seek: @convention(c) (UnsafeMutableRawPointer?, Int64, Int32) -> Int64 = {
        (ref, offset, whence) in
        var count: Int64 = 0
        //print("seek \(offset) \(whence)")
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridgeConvert>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            if stream.isCancel {
                return 0
            }
            stream.semaphore.wait()
            switch whence {
            case 0x10000:
                count = stream.remote.size
            case SEEK_SET:
                if offset >= 0 && offset <= stream.remote.size {
                    stream.position = offset
                    count = offset
                }
                else {
                    count = -1
                }
            case SEEK_CUR:
                let offset2 = offset + stream.position
                if offset2 >= 0 && offset2 <= stream.remote.size {
                    stream.position = offset2
                    count = offset2
                }
                else {
                    count = -1
                }
            case SEEK_END:
                let offset2 = stream.remote.size - offset
                if offset2 >= 0 && offset2 <= stream.remote.size {
                    stream.position = offset2
                    count = offset2
                }
                else {
                    count = -1
                }
            default:
                count = -1
            }
            stream.semaphore.signal()
        }
        return count
    }
    
    let select_stream: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?, Int32, UnsafePointer<Int32>?, UnsafePointer<UnsafePointer<CChar>?>?, Int32, UnsafePointer<Int32>?, UnsafePointer<UnsafePointer<CChar>?>?)->Void = {
        (ref, ret, video_count, video_idx, video_lng, sub_count, sub_idx, sub_lng) in
        if let ref_unwrapped = ref, let ret_unwapped = ret {
            let stream = Unmanaged<StreamBridgeConvert>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            var info = PlayItemInfo()
            if let video_idx_unwapped = video_idx, let video_lng_unwapped = video_lng {
                let video_index = UnsafeBufferPointer(start: video_idx_unwapped, count: Int(video_count))
                let video_language = UnsafeBufferPointer(start: video_lng_unwapped, count: Int(video_count))
                for i in 0..<Int(video_count) {
                    let lng = FrameworkResource.getLocalized(key: String(cString: video_language[i]!))
                    info.videos[Int(video_index[i])] = lng
                }
            }
            if let sub_idx_unwapped = sub_idx, let sub_lng_unwapped = sub_lng {
                let subtitle_index = UnsafeBufferPointer(start: sub_idx_unwapped, count: Int(sub_count))
                let subtitle_language = UnsafeBufferPointer(start: sub_lng_unwapped, count: Int(sub_count))
                for i in 0..<Int(sub_count) {
                    let lng = FrameworkResource.getLocalized(key: String(cString: subtitle_language[i]!))
                    info.subtitle[Int(subtitle_index[i])] = lng
                }
            }
            info.subtitle[-1] = FrameworkResource.getLocalized(key: "none")
            var result = UnsafeMutableBufferPointer(start: ret_unwapped, count: 2)
            info.mainVideo = Int(result[0])
            info.mainSubtitle = Int(result[1])
            if info.mainSubtitle < 0 {
               info.mainSubtitle = -1
            }
            result.assign(repeating: -1)
            if let (v_idx, s_idx) = stream.onSelect?(info) {
                result[0] = Int32(v_idx)
                result[1] = Int32(s_idx)
            }
        }
    }
    
    class params {
        let itemname: UnsafeMutablePointer<Int8>!
        let sdlparam: UnsafeMutableRawPointer!
        init(itemname: UnsafeMutablePointer<Int8>!,
             sdlparam: UnsafeMutableRawPointer!) {
            self.itemname = itemname
            self.sdlparam = sdlparam
        }
    }
    var nameCStr: [CChar]? = nil
    
    func abort() {
        abort_run(sdlparam)
    }
    
    func run(onFinish: @escaping ()->Void) {
        var basename = remote.name
        if let subid = remote.subid, let subbase = CloudFactory.shared[remote.storage]?.get(fileId: subid) {
            basename = subbase.name
        }
        var components = basename.components(separatedBy: ".")
        if components.count > 1 {
            components.removeLast()
            basename = components.joined(separator: ".")
        }
        encoder.onReady = { [weak self] in
            guard let self = self else {
                return
            }
            self.onReady?(true)
        }
        var start = Double.nan
        var duration = Double.nan
        if let s = info.startpos {
            start = s
        }
        if let d = info.playduration {
            duration = d
        }
        nameCStr = self.name.cString(using: .utf8)
        nameCStr?.withUnsafeMutableBufferPointer { itemname in
            sdlparam = makeconvert_arg(itemname.baseAddress, selfref,
                                       start, duration,
                                       read_packet, seek, cancel,
                                       encode, encode_sound, encode_text, finish,
                                       stream_count, select_stream)
            run_play(sdlparam)
            DispatchQueue.global().async {
                run_finish(self.sdlparam)
                self.encoder.finish_encode()
                onFinish()
            }
        }
    }
}

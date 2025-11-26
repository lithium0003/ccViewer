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

    public class func IsCasting() -> Bool {
        return converter != nil
    }

    public class func Start() {
        if converter == nil {
            converter = convert()
        }
    }

    public class func Stop() async {
        if converter != nil {
            await converter?.finish()
            converter = nil
        }
    }

    public class func Done(targetPath: String) async {
        guard let c = converter else {
            return
        }
        await c.args.playdone(targetPath: targetPath)
    }

    public class func Play(item: ConvertIteminfo) async -> URL? {
        guard let c = converter else {
            return nil
        }
        return await c.play(info: item)
    }

    public class func start_encode(randID: String) async -> Bool {
        guard let c = converter else {
            return false
        }
        return await c.args.start_running(randID: randID)
    }

    public class func runState(randID: String) async -> Bool {
        guard let c = converter else {
            return false
        }
        return await c.args.get_runState(randID: randID)
    }

    public class func fileReady(randID: String) async -> Bool {
        guard let c = converter else {
            return false
        }
        return await c.args.fileReady(randID: randID)
    }

    public class func touch(randID: String, segment: Int) async {
        guard let c = converter else {
            return
        }
        guard let r = await c.args.get_running(randID: randID) else {
            return
        }
        await c.args.set_lasttouch(item: randID, t: Date())
        r.encoder.last_touch = Date()
        for w in r.encoder.writer {
            w?.set_touch(count: segment)
        }
    }

    public class func duration(randID: String) async -> Double {
        guard let c = converter else {
            return 0
        }
        guard let r = await c.args.get_running(randID: randID) else {
            return 0
        }
        return r.mediaDuration
    }

    public class func baseItem(randID: String) async -> RemoteItem? {
        guard let c = converter else {
            return nil
        }
        guard let r = await c.args.get_running(randID: randID) else {
            return nil
        }
        return r.remote
    }
}

class convert {
    let bundleId = Bundle.main.bundleIdentifier!

    let server: HTTPserver
    let baseURL: URL
    var port: UInt16
    actor ArgInfo {
        private var running: [String: StreamBridgeConvert] = [:]
        private var tasks: [String: Task<Void, Never>] = [:]
        private var holdfiles: [String: URL] = [:]
        private var items: [String: String] = [:]
        private var lasttouch: [String: Date] = [:]
        private var runState: [String: Bool] = [:]

        func get_running(randID: String) -> StreamBridgeConvert? {
            running[randID]
        }

        func set_running(randID: String, bridge: StreamBridgeConvert, urlout: URL) {
            running[randID] = bridge
            holdfiles[randID] = urlout
            lasttouch[randID] = Date()
        }
        
        func start_running(randID: String) -> Bool {
            if let bridge = running[randID] {
                if tasks[randID] == nil {
                    tasks[randID] = Task {
                        let ret = await bridge.run()
                        runState[randID] = ret
                        running[randID] = nil
                        tasks[randID] = nil
                    }
                    return true
                }
            }
            return false
        }
        
        func get_runState(randID: String) -> Bool {
            if let runstate = runState[randID] {
                return runstate
            }
            return true
        }
        
        func fileReady(randID: String) -> Bool {
            if let urlout = holdfiles[randID] {
                return FileManager.default.fileExists(atPath: urlout.appending(path: "stream.m3u8").path(percentEncoded: false))
            }
            return false
        }
        
        func get_holdfiles(item: String) -> URL? {
            holdfiles[item]
        }

        func get_items(item: String) -> String? {
            items[item]
        }

        func set_item(item: String, randID: String) {
            items[item] = randID
        }
        
        func get_lasttouch(item: String) -> Date? {
            lasttouch[item]
        }

        func set_lasttouch(item: String, t: Date) {
            lasttouch[item] = t
        }
        
        func finish() {
            for (_,r) in running {
                r.abort()
            }
        }

        func playdone(targetPath: String) {
            print("playdone", targetPath)
            guard let randID = items[targetPath] else {
                return
            }
            print("playdone", randID)

            if let r = running[randID] {
                r.encoder.last_touch = Date()
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

        deinit {
            for (_,r) in running {
                r.abort()
            }
        }
    }
    var args = ArgInfo()

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
        while !FileManager.default.fileExists(atPath: baseURL.path(percentEncoded: false)) {
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
        server.Stop()
        do {
            try FileManager.default.removeItem(at: baseURL)
        } catch {
            print("Could not clear temp folder: \(error)")
        }
    }
    
    func finish() async {
        await args.finish()
        server.Stop()
        do {
            try FileManager.default.removeItem(at: baseURL)
        } catch {
            print("Could not clear temp folder: \(error)")
        }
    }
    
    func play(info: ConvertIteminfo) async -> URL? {
        guard let host = HTTPserver.getWiFiAddress() else {
            return nil
        }
        let fixedHost: String
        if host.contains(":") {
            fixedHost = "[\(host)]"
        }
        else {
            fixedHost = host
        }

        let item = info.item
        if let id = await args.get_items(item: item.path) {
            return URL(string: "http://\(fixedHost):\(port)/\(id)/stream.m3u8")!
        }
        
        let randID = UUID().uuidString
        let urlout = baseURL.appendingPathComponent(randID)
        do {
            try FileManager.default.createDirectory(at: urlout, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return nil
        }
        while !FileManager.default.fileExists(atPath: urlout.path(percentEncoded: false)) {
            sleep(1)
        }
        guard let encoder = Encoder(dest: urlout) else {
            return nil
        }
        await args.set_item(item: item.path, randID: randID)
        let playURL = URL(string: "http://\(fixedHost):\(port)/\(randID)/stream.m3u8")!
        let bridge = await StreamBridgeConvert(info: info, name: item.name, encoder: encoder)
        await args.set_running(randID: randID, bridge: bridge, urlout: urlout)
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
    var playing = 0
    var position: Int64 = 0
    var mediaDuration = 0.0
    var info: ConvertIteminfo

    
    init(info: ConvertIteminfo, name: String, encoder: Encoder) async {
        self.info = info
        let item = info.item
        self.remote = item
        self.stream = await item.open()
        self.name = name
        self.encoder = encoder
        self.selfref = Unmanaged<StreamBridgeConvert>.passUnretained(self).toOpaque()
    }

    let encode: @convention(c) (UnsafeMutableRawPointer?, Double, Int32, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int32>?, Int32) -> Void = {
        (ref, pts, key, src_data, src_linesize, src_height) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridgeConvert>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.encoder.encode_frame(src_data: src_data, src_linesizes: src_linesize, src_height: src_height, pts: pts, key: key == 1)
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
                var asstext = assline[assline.startIndex...]
                if let p1 = assline.firstIndex(of: ":") {
                    asstext = assline[p1...].dropFirst()
                }
                var invalid = false
                for _ in 0..<8 {
                    guard let p2 = asstext.firstIndex(of: ",") else {
                        invalid = true
                        break
                    }
                    asstext = asstext[p2...].dropFirst()
                }
                if invalid {
                    continue
                }
                if asstext.first == "," {
                    asstext = asstext.dropFirst()
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
            Task {
                await stream.remote.cancel()
            }
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
            while !stream.isCancel && stream.encoder.needWait {
                print(stream.name, "wait")
                sleep(1)
            }
            if stream.isCancel {
                return averror_exit
            }
            //print("read \(stream.position) \(buf_size)")
            stream.semaphore.wait()
            defer {
                stream.semaphore.signal()
            }
            if stream.position >= stream.remote.size {
                return averror_eof
            }
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached(priority: .high) {
                defer {
                    semaphore.signal()
                }
                let data = try? await stream.stream.read(position: stream.position, length: Int(buf_size))
                if stream.isCancel {
                    return
                }
                assert(data?.count ?? 0 <= Int(buf_size))
                if let data, data.count > 0 {
                    count = data.copyBytes(to: buf_array)
                    stream.position += Int64(count)
                }
            }
            semaphore.wait()
        }
        //print("read count \(count)")
        return Int32(count)
    }
    
    let seek: @convention(c) (UnsafeMutableRawPointer?, Int64, Int32) -> Int64 = {
        (ref, offset, whence) in
        var count: Int64 = 0
        //print("seek \(offset) \(whence)")
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridgeConvert>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            if stream.isCancel {
                return -1
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
            if let sub_idx_unwapped = sub_idx, let sub_lng_unwapped = sub_lng {
                let subtitle_index = UnsafeBufferPointer(start: sub_idx_unwapped, count: Int(sub_count))
                let subtitle_language = UnsafeBufferPointer(start: sub_lng_unwapped, count: Int(sub_count))
                var result = UnsafeMutableBufferPointer(start: ret_unwapped, count: 2)
                if result[1] < 0 {
                    result[1] = -1
                }
                if UserDefaults.standard.integer(forKey: "Cast_text_image_idx") < 0 {
                    result[1] = -1
                }
                else if UserDefaults.standard.integer(forKey: "Cast_text_image_idx") == 0 {
                }
                else {
                    result[1] = subtitle_index[min(UserDefaults.standard.integer(forKey: "Cast_text_image_idx"), Int(sub_count))]
                }
            }
        }
    }

    let set_duration: @convention(c) (UnsafeMutableRawPointer?, Double) -> Void = {
        (ref, duration) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridgeConvert>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.mediaDuration = duration
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
        isCancel = true
        stream.isLive = false
        abort_run(sdlparam)
    }
    
    func run() async -> Bool {
        var basename = remote.name
        if let subid = remote.subid, let subbase = await CloudFactory.shared.storageList.get(remote.storage)?.get(fileId: subid) {
            basename = subbase.name
        }
        var components = basename.components(separatedBy: ".")
        if components.count > 1 {
            components.removeLast()
            basename = components.joined(separator: ".")
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
        let ret = await withCheckedContinuation { continuation in
            nameCStr?.withUnsafeMutableBufferPointer { itemname in
                sdlparam = makeconvert_arg(itemname.baseAddress, selfref,
                                           start, duration,
                                           UserDefaults.standard.bool(forKey: "ARIB_subtitle_convert_to_text_cast") ? 1: 0,
                                           set_duration,
                                           read_packet, seek, cancel,
                                           encode, encode_sound, encode_text, finish,
                                           stream_count, select_stream)
                run_play(sdlparam)
                let ret = run_finish(self.sdlparam) == 0 ? true : false
                self.encoder.finish_encode()
                continuation.resume(returning: ret)
            }
        }
        isCancel = true
        stream.isLive = false
        return ret;
    }
}

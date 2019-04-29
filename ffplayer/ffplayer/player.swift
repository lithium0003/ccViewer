//
//  player.swift
//  ffplayer
//
//  Created by rei6 on 2019/03/21.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import AVFoundation
import RemoteCloud
import MediaPlayer

public class Player {
    static private var queue = DispatchQueue(label: "playerqueue")
    static public private (set) var value: Int = 1
    static public private (set) var initialized: Bool = false
    
    private class func increment() {
        queue.sync {
            value += 1
        }
    }

    private class func initializedDone() -> Bool {
        return queue.sync {
            if initialized {
                return true
            }
            initialized = true
            return false
        }
    }
    
    private class func decrement() -> Bool {
        return queue.sync {
            if value > 0 {
                value -= 1
                return true
            }
            else {
                return false
            }
        }
    }

    public class func SDLdidChangeStatusBarOrientation() {
        if value == 0 {
            didChangeStatusBarOrientation()
        }
    }
    
    public class func SDLapplicationWillTerminate() {
        if value == 0 {
            applicationWillTerminate()
        }
    }
    
    public class func SDLapplicationWillResignActive() {
        if value == 0 {
            applicationWillResignActive()
        }
    }
    
    public class func SDLapplicationDidEnterBackground() {
        if value == 0 {
            applicationDidEnterBackground()
        }
    }
    
    public class func SDLapplicationWillEnterForeground() {
        if value == 0 {
            applicationWillEnterForeground()
        }
    }
    
    public class func SDLapplicationDidBecomeActive() {
        if value == 0 {
            applicationDidBecomeActive()
        }
    }
    
    public class func play(item: RemoteItem, start: Double?, fontsize: Int, onFinish: @escaping (Double?)->Void) {
        guard decrement() else {
            onFinish(nil)
            return
        }
        DispatchQueue.main.async {
            sdlInit()
            let bridge = StreamBridge(item: item, name: item.name, fontsize: fontsize)
            bridge.start = start
            bridge.run() { ret in
                bridge.finishRemoteTransportControls()
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                sdlDone()
                increment()
                onFinish(ret)
            }
        }
    }

    public class func play(items: [RemoteItem], shuffle: Bool, loop: Bool, fontsize: Int, onFinish: @escaping (Bool)->Void) {
        guard decrement() else {
            onFinish(false)
            return
        }
        var playItems = items;
        if shuffle {
            playItems.shuffle()
        }
        if let playItem = playItems.first {
            DispatchQueue.main.async {
                sdlInit()
                let bridge = StreamBridge(item: playItem, name: playItem.name, fontsize: fontsize)
                bridge.run() { ret in
                    bridge.finishRemoteTransportControls()
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                    sdlDone()
                    increment()
                    if ret ?? -1 == 0 {
                        var remain = Array(playItems.dropFirst())
                        if loop {
                           remain += [playItem]
                        }
                        if remain.count > 0 {
                            play(items: remain, shuffle: shuffle, loop: loop, fontsize: fontsize, onFinish: onFinish)
                        }
                        else {
                            onFinish(true)
                        }
                    }
                    else {
                        onFinish(false)
                    }
                }
            }
        }
    }
}

class StreamBridge {
    let remote: RemoteItem
    let stream: RemoteStream
    let name: String
    var start: Double?
    var selfref: UnsafeMutableRawPointer!
    var position: Int64
    var ttfPath: String?
    var image1Path: String?
    var image2Path: String?
    var image3Path: String?
    var image4Path: String?
    let fontsize: Int
    let semaphore = DispatchSemaphore(value: 1)
    var isCancel = false
    var ret: Double?
    var sdlparam: UnsafeMutableRawPointer!
    var image: UIImage?
    var media_pos = 0.0
    var media_len = 0.0
    var playing = false
    
    init(item: RemoteItem, name: String, fontsize: Int) {
        self.remote = item
        self.stream = item.open()
        self.name = name
        self.position = 0
        self.fontsize = fontsize
        self.ret = -1
        self.selfref = Unmanaged<StreamBridge>.passUnretained(self).toOpaque()
        self.ttfPath = Bundle(for: type(of: self)).path(forResource: "ipamp", ofType: "ttf")
        self.image1Path = Bundle(for: type(of: self)).path(forResource: "play", ofType: "bmp")
        self.image2Path = Bundle(for: type(of: self)).path(forResource: "pause", ofType: "bmp")
        self.image3Path = Bundle(for: type(of: self)).path(forResource: "back30", ofType: "bmp")
        self.image4Path = Bundle(for: type(of: self)).path(forResource: "next30", ofType: "bmp")
    }

    let update_info: @convention(c) (UnsafeMutableRawPointer?, Int32, Double, Double) -> Void = {
        (ref, play, pos, len) in
        if let ref_unwrapped = ref, !pos.isNaN, !len.isNaN {
            var stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.media_pos = pos
            stream.media_len = len
            stream.playing = play == 1
            
            var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String : Any]()
            nowPlayingInfo[MPMediaItemPropertyTitle] = stream.remote.name
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = stream.media_pos
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = stream.media_len
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = stream.playing ? NSNumber(1.0) : NSNumber(0.0)
            if nowPlayingInfo[MPMediaItemPropertyArtwork] == nil, let image = stream.image {
                nowPlayingInfo[MPMediaItemPropertyArtwork] =
                    MPMediaItemArtwork(boundsSize: image.size) { size in
                        return image
                }
                if let png = image.pngData() {
                    var buf = [UInt8](png)
                    buf.withUnsafeMutableBufferPointer { p in
                        set_image(stream.sdlparam, p.baseAddress, Int32(p.count))
                    }
                }
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }

    let cancel: @convention(c) (UnsafeMutableRawPointer?) -> Void = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.isCancel = true
            stream.stream.isLive = false
            stream.remote.cancel()
            stream.semaphore.signal()
        }
    }

    let read_packet: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32 = {
        (ref, buf, buf_size) in
        var count = 0
        if let ref_unwrapped = ref, let buf_unwrapped = buf {
            let buf_array = UnsafeMutableBufferPointer<UInt8>(start: buf_unwrapped, count: Int(buf_size))
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
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
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
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
    
    class params {
        let itemname: UnsafeMutablePointer<Int8>!
        let ttf_path: UnsafeMutablePointer<Int8>!
        let image1_path: UnsafeMutablePointer<Int8>!
        let image2_path: UnsafeMutablePointer<Int8>!
        let image3_path: UnsafeMutablePointer<Int8>!
        let image4_path: UnsafeMutablePointer<Int8>!
        let sdlparam: UnsafeMutableRawPointer!
        init(itemname: UnsafeMutablePointer<Int8>!,
             ttf_path: UnsafeMutablePointer<Int8>!,
             image1_path: UnsafeMutablePointer<Int8>!,
             image2_path: UnsafeMutablePointer<Int8>!,
             image3_path: UnsafeMutablePointer<Int8>!,
             image4_path: UnsafeMutablePointer<Int8>!,
             sdlparam: UnsafeMutableRawPointer!) {
            self.itemname = itemname
            self.ttf_path = ttf_path
            self.image1_path = image1_path
            self.image2_path = image2_path
            self.image3_path = image3_path
            self.image4_path = image4_path
            self.sdlparam = sdlparam
        }
    }
    var ttfCStr: [CChar]? = nil
    var image1CStr: [CChar]? = nil
    var nameCStr: [CChar]? = nil
    var image2CStr: [CChar]? = nil
    var image3CStr: [CChar]? = nil
    var image4CStr: [CChar]? = nil
    
    var loop_result: Int32 = 0
    func runloop(sdlparam: UnsafeMutableRawPointer?, group: DispatchGroup) {
        DispatchQueue.main.async {
            guard self.loop_result == 0 else {
                return
            }
            self.loop_result = run_loop(sdlparam);
            if (self.loop_result != 0) {
                group.leave()
            }
            DispatchQueue.global().asyncAfter(deadline: .now()) {
                guard self.loop_result == 0 else {
                    return
                }
                self.runloop(sdlparam: sdlparam, group: group)
            }
        }
    }

    func setObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionRouteChangeObserver), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionInterruptionObserver), name: AVAudioSession.interruptionNotification, object: nil)
    }

    func delObserver() {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func audioSessionRouteChangeObserver(notification: Notification)
    {
        if let userInfo = notification.userInfo {
            if let raw = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt, let audioSessionRouteChangeReason = AVAudioSession.RouteChangeReason.init(rawValue: raw) {
                let audioSessionRouteDescription = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
                let audioSessionPortDescription = audioSessionRouteDescription?.outputs[0];

                switch (audioSessionRouteChangeReason) {
                case .newDeviceAvailable:
                    let latency = AVAudioSession.sharedInstance().outputLatency
                    print(latency)
                    play_latency(sdlparam, latency)
                    break
                case .oldDeviceUnavailable:
                    if audioSessionPortDescription?.portType == .headphones || audioSessionPortDescription?.portType == .bluetoothA2DP {
                        play_pause(sdlparam, 1)
                    }
                    let latency = AVAudioSession.sharedInstance().outputLatency
                    print(latency)
                    play_latency(sdlparam, latency)
                    break
                default:
                    break
                }
            }
        }
    }
    
    @objc func audioSessionInterruptionObserver(notification: Notification)
    {
        if let userInfo = notification.userInfo {
            if let raw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt, let audioSessionInterruptionType = AVAudioSession.InterruptionType.init(rawValue: raw) {
                
                switch (audioSessionInterruptionType) {
                case .began:
                    play_pause(sdlparam, 1)
                case .ended:
                    play_pause(sdlparam, 0)
                default:
                    break
                }
            }
        }
    }
    
    func run(onFinish: @escaping (Double?)->Void) {
        setupRemoteTransportControls()
        
        
        var basename = remote.name
        var parentId = remote.parent
        if let subid = remote.subid, let subbase = CloudFactory.shared[remote.storage]?.get(fileId: subid) {
            basename = subbase.name
            parentId = subbase.parent
        }
        var components = basename.components(separatedBy: ".")
        if components.count > 1 {
            components.removeLast()
            basename = components.joined(separator: ".")
        }
        if let imageitem = CloudFactory.shared.data.getImage(storage: remote.storage, parentId: parentId, baseName: basename) {
            if let imagestream = CloudFactory.shared[remote.storage]?.get(fileId: imageitem.id ?? "")?.open() {
                imagestream.read(position: 0, length: Int(imageitem.size)) { data in
                    if let data = data, let image = UIImage(data: data) {
                        self.image = image
                    }
                }
            }
        }
        if let ttfStr = ttfPath {
            ttfCStr = ttfStr.cString(using: .utf8)
        }
        if let image1Str = image1Path {
            image1CStr = image1Str.cString(using: .utf8)
        }
        if let image2Str = image2Path {
            image2CStr = image2Str.cString(using: .utf8)
        }
        if let image3Str = image3Path {
            image3CStr = image3Str.cString(using: .utf8)
        }
        if let image4Str = image4Path {
            image4CStr = image4Str.cString(using: .utf8)
        }
        nameCStr = self.name.cString(using: .utf8)
        ttfCStr?.withUnsafeMutableBufferPointer { ttf_path in
            image1CStr?.withUnsafeMutableBufferPointer { image1_path in
                image2CStr?.withUnsafeMutableBufferPointer { image2_path in
                    image3CStr?.withUnsafeMutableBufferPointer { image3_path in
                        image4CStr?.withUnsafeMutableBufferPointer { image4_path in
                            nameCStr?.withUnsafeMutableBufferPointer { itemname in
                                let latency = AVAudioSession.sharedInstance().outputLatency
                                print(latency)
                                sdlparam = make_arg(UIDevice.current.userInterfaceIdiom == .phone ? 1 : 0,
                                                    (start == nil) ? Double.nan : start!,
                                                    itemname.baseAddress, ttf_path.baseAddress,
                                                    Int32(fontsize),
                                                    image1_path.baseAddress,
                                                    image2_path.baseAddress,
                                                    image3_path.baseAddress,
                                                    image4_path.baseAddress,
                                                    latency, selfref, read_packet, seek, cancel, update_info)
                                setObserver()
                                let group = DispatchGroup()
                                let group2 = DispatchGroup()
                                group.enter()
                                group2.enter()
                                var failed = false
                                DispatchQueue.main.async {
                                    if run_play(self.sdlparam) != 0 {
                                        failed = true
                                    }
                                    group.leave()
                                }
                                guard !failed else {
                                    self.delObserver()
                                    onFinish(nil)
                                    return
                                }
                                group.notify(queue: .global()) {
                                    self.runloop(sdlparam: self.sdlparam, group: group2)
                                }
                                DispatchQueue.global().async {
                                    group2.notify(queue: .main) {
                                        self.ret = run_finish(self.sdlparam);
                                        self.delObserver()
                                        onFinish(self.ret)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    func setupRemoteTransportControls() {
        // Get the shared MPRemoteCommandCenter
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            play_pause(self.sdlparam, self.playing ? 1 : 0)
            return .success
        }

        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            guard let command = event.command as? MPSkipIntervalCommand else {
                return .noSuchContent
            }
            let interval = command.preferredIntervals[0]
            play_seek(self.sdlparam, self.media_pos+Double(truncating: interval))
            return .success
        }
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            guard let command = event.command as? MPSkipIntervalCommand else {
                return .noSuchContent
            }
            let interval = command.preferredIntervals[0]
            play_seek(self.sdlparam, self.media_pos-Double(truncating: interval))
            return .success
        }
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self](remoteEvent) -> MPRemoteCommandHandlerStatus in
            guard let self = self else {return .commandFailed}
            if let event = remoteEvent as? MPChangePlaybackPositionCommandEvent {
                play_seek(self.sdlparam, event.positionTime)
                return .success
            }
            return .commandFailed
        }
    }
    
    func finishRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
    }

}


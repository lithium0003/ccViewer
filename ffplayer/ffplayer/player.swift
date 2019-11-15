//
//  player.swift
//  ffplayer
//
//  Created by rei6 on 2019/03/21.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import CoreGraphics
import MediaPlayer
import RemoteCloud

public class Player {
    public class func play(parent: UIViewController, item: RemoteItem, start: Double?, onFinish: @escaping (Double?)->Void) {
        DispatchQueue.main.async {
            let bridge = StreamBridge(item: item, name: item.name, count: 1)
            let skip = UserDefaults.standard.integer(forKey: "playStartSkipSec")
            let stop = UserDefaults.standard.integer(forKey: "playStopAfterSec")
            if skip > 0 {
                let skipd = Double(skip)
                if stop > 0 {
                    let stopd = Double(stop)
                    if let s = start {
                        if s < skipd {
                            bridge.start = skipd
                            bridge.durationLimit = stopd
                        }
                        else {
                            if s > stopd {
                                bridge.start = skipd
                                bridge.durationLimit = stopd
                            }
                            else {
                                bridge.start = s
                                bridge.durationLimit = stopd - (s - skipd)
                            }
                        }
                    }
                    else {
                        bridge.start = skipd
                        bridge.durationLimit = stopd
                    }
                }
                else {
                    if let s = start {
                        if s < skipd {
                            bridge.start = skipd
                        }
                        else {
                            bridge.start = s
                        }
                    }
                    else {
                        bridge.start = skipd
                    }
                }
            }
            else {
                if stop > 0 {
                    let stopd = Double(stop)
                    if let s = start {
                        if s < stopd {
                            bridge.start = s
                            bridge.durationLimit = stopd - s
                        }
                        else {
                            bridge.durationLimit = stopd
                        }
                    }
                }
                else {
                    bridge.start = start
                }
            }
            bridge.run(parent: parent) { ret, pos in
                if ret >= 0 {
                    onFinish(pos)
                }
                else {
                    onFinish(nil)
                }
            }
        }
    }

    public class func play(parent: UIViewController, items: [RemoteItem], shuffle: Bool, loop: Bool, onFinish: @escaping (Bool)->Void) {
        var playItems = items;
        if shuffle {
            playItems.shuffle()
        }
        if let playItem = playItems.first {
            DispatchQueue.main.async {
                let group = DispatchGroup()
                var cont = false
                group.enter()
                autoreleasepool {
                    let bridge = StreamBridge(item: playItem, name: playItem.name, count: playItems.count)
                    let skip = UserDefaults.standard.integer(forKey: "playStartSkipSec")
                    if skip > 0 {
                        bridge.start = Double(skip)
                    }
                    let stop = UserDefaults.standard.integer(forKey: "playStopAfterSec")
                    if stop > 0 {
                        bridge.durationLimit = Double(stop)
                    }
                    bridge.run(parent: parent) { ret, pos in
                        defer {
                            group.leave()
                        }
                        if ret >= 0 {
                            var remain = Array(playItems.dropFirst())
                            if loop {
                               remain += [playItem]
                            }
                            playItems = remain
                            if ret == 0 && remain.count > 0 {
                                cont = true
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
                group.notify(queue: .main) {
                    if cont {
                        play(parent: parent, items: playItems, shuffle: shuffle, loop: loop, onFinish: onFinish)
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
    var durationLimit: Double?
    var count: Int
    var position: Int64
    var soundPTS: Double
    var videoPTS: Double
    var mediaDuration: Double

    var selfref: UnsafeMutableRawPointer!
    var player: FFPlayerViewController!
    var sound: AudioQueuePlayer!
    
    var isCancel = false
    let semaphore = DispatchSemaphore(value: 1)
    var param: UnsafeMutableRawPointer!
    
    var nameCStr: [CChar]? = nil

    init(item: RemoteItem, name: String, count: Int) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(error)
        }

        remote = item
        stream = item.open()
        self.name = name
        position = 0
        self.count = count
        soundPTS = Double.nan
        videoPTS = Double.nan
        mediaDuration = 0

        selfref = Unmanaged<StreamBridge>.passUnretained(self).toOpaque()
        player = FFPlayerViewController()
        player.modalPresentationStyle = .fullScreen
        sound = AudioQueuePlayer()
    }

    let getWidth: @convention(c) (UnsafeMutableRawPointer?) -> Int32 = {
        (ref) in
        var width: Int32 = 0
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            width = Int32(stream.player.imageWidth)
        }
        return width
    }

    let getHeight: @convention(c) (UnsafeMutableRawPointer?) -> Int32 = {
        (ref) in
        var height: Int32 = 0
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            height = Int32(stream.player.imageHeight)
        }
        return height
    }

    let setDuration: @convention(c) (UnsafeMutableRawPointer?, Double) -> Void = {
        (ref, duration) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.player.totalTime = duration
            stream.mediaDuration = duration
        }
    }
    
    let setSoundOnly: @convention(c) (UnsafeMutableRawPointer?) -> Void = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.player.soundOnly = true
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

    let draw_pict: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32, Int32, Int32, Double) -> Void = {
        (ref, image_buf, width, height, linesize, t) in
        if let ref_unwrapped = ref, let image = image_buf {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            if stream.isCancel {
                return
            }
            if t.isNaN {
                return
            }
            stream.videoPTS = t
            guard let data = CFDataCreate(nil, image, Int(width * height * 4)) else {
                return
            }
            guard let dataProvider = CGDataProvider(data: data) else {
                return
            }
            
            guard let cgimage = CGImage(width: Int(width), height: Int(height), bitsPerComponent: 8, bitsPerPixel: 8*4, bytesPerRow: Int(width)*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: dataProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
                return
            }
            
            let uiimage = UIImage(cgImage: cgimage)
            DispatchQueue.main.async {
                stream.player.displayImage(image: uiimage, t: t)
                //print(t)
            }
        }
    }

    let sound_play: @convention(c) (UnsafeMutableRawPointer?) -> Int32 = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            if stream.isCancel {
               return stream.sound.isPlay ? 1 : 0
            }
            print("sound_play")
            var ret: Int32 = -1
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.main.async {
                if UIApplication.shared.applicationState == .active {
                    DispatchQueue.global().async {
                        print("sound_play()")
                        stream.sound.play()
                        ret = stream.sound.isPlay ? 1 : 0
                        group.leave()
                    }
                }
                else {
                    DispatchQueue.main.asyncAfter(deadline: .now()+1) {
                        DispatchQueue.global().async {
                            print("sound_play()")
                            stream.sound.play()
                            ret = stream.sound.isPlay ? 1 : 0
                            group.leave()
                        }
                    }
                }
            }
            group.wait()
            return ret
        }
        return -1
    }
    
    let sound_stop: @convention(c) (UnsafeMutableRawPointer?) -> Int32 = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            print("sound_stop")
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                stream.sound.stop()
                group.leave()
            }
            group.wait()
            return stream.sound.isPlay ? 1 : 0
        }
        return -1
    }

    let wait_stop: @convention(c) (UnsafeMutableRawPointer?) -> Void = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.player.waitStop()
        }
    }

    let wait_start: @convention(c) (UnsafeMutableRawPointer?) -> Void = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.player.waitStart()
        }
    }

    let cc_draw: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int32) -> Void = {
        (ref, buf, tp) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            if let buf_unwrapped = buf {
                let cc = String(cString: buf_unwrapped)
                stream.player.displayCCtext(text: cc, ass: tp == 1)
            }
            else {
                stream.player.displayCCtext(text: nil, ass: false)
            }
        }
    }

    let change_lang: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int32, Int32) -> Void = {
        (ref, buf, tp, idx) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            if let buf_unwrapped = buf {
                let lang = String(cString: buf_unwrapped)
                stream.player.changeLanguage(lang: lang, media: Int(tp), idx: Int(idx))
            }
        }
    }

    func run(parent: UIViewController, onFinish: @escaping (Int, Double)->Void) {
        var ret = -1
        var userBreak = false
        nameCStr = name.cString(using: .utf8)
        var start_skip: Double = Double.nan
        if let s = start {
            start_skip = s
        }
        var stop_limit: Double = Double.nan
        if let d = durationLimit {
            stop_limit = d
        }
        player.video_title = name
        player.onClose = { [weak self] interactive in
            guard let self = self else {
                return
            }
            userBreak = interactive
            self.isCancel = true
            self.stream.isLive = false
            run_quit(self.param)
            self.sound.stop()
        }
        player.onSeek = { [weak self] pos in
            guard let self = self else {
                return
            }
            let pos64: Int64 = Int64(pos * 1000000)
            run_seek(self.param, pos64)
        }
        player.onSeekChapter = { [weak self] inc in
            guard let self = self else {
                return
            }
            run_seek_chapter(self.param, Int32(inc))
        }
        player.onPause = { [weak self] state in
            guard let self = self else {
                return
            }
            run_pause(self.param, state ? 1 : 0)
        }
        player.getPause = { [weak self] in
            guard let self = self else {
                return false
            }
            return get_pause(self.param) == 1
        }
        player.onCycleCh = { [weak self] t in
            guard let self = self else {
                return
            }
            run_cycle_ch(self.param, Int32(t))
        }
        sound.onLoadData = { [weak self] buffer, capacity in
            guard let self = self else {
                return Double.nan
            }
            let t = load_sound(self.param, buffer, Int32(capacity/2))
            if !t.isNaN {
                self.soundPTS = t
                self.player.updatePosition(t: t)
            }
            return t
        }
        var timer1: Timer?
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
            self.setObserver()
            self.setupRemoteTransportControls()
        }
        parent.present(player, animated: true) {
            let latency = AVAudioSession.sharedInstance().outputLatency
            print(latency)
            self.nameCStr?.withUnsafeMutableBufferPointer { itemname in
                self.param = make_arg(
                    itemname.baseAddress,
                    latency,
                    start_skip,
                    stop_limit,
                    Int32(self.count),
                    self.selfref,
                    self.read_packet,
                    self.seek,
                    self.cancel,
                    self.getWidth,
                    self.getHeight,
                    self.draw_pict,
                    self.setDuration,
                    self.setSoundOnly,
                    self.sound_play,
                    self.sound_stop,
                    self.wait_stop,
                    self.wait_start,
                    self.cc_draw,
                    self.change_lang)
                DispatchQueue.global().async {
                    run_play(self.param)
                    self.sound.play()
                    DispatchQueue.main.async {
                        timer1 = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                            self.updateMediaInfo()
                        }
                    }
                    ret = Int(run_finish(self.param))
                    if userBreak {
                        ret = 1
                    }
                    timer1?.invalidate()
                    DispatchQueue.main.async {
                        self.player.dismiss(animated: true, completion: nil)
                        UIApplication.shared.isIdleTimerDisabled = false
                        self.delObserver()
                        self.finishRemoteTransportControls()
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                    }
                    if self.player.possition >= self.player.totalTime - 1 {
                        onFinish(ret, 0)
                    }
                    else {
                        onFinish(ret, self.player.possition)
                    }
                }
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
                    set_latency(param, latency)
                    break
                case .oldDeviceUnavailable:
                    if audioSessionPortDescription?.portType == .headphones || audioSessionPortDescription?.portType == .bluetoothA2DP {
                        run_pause(param, 1)
                    }
                    let latency = AVAudioSession.sharedInstance().outputLatency
                    print(latency)
                    set_latency(param, latency)
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
                    guard let wasSuspendedKeyValue = userInfo[AVAudioSessionInterruptionWasSuspendedKey] as? NSNumber else {
                        break
                    }
                    let wasSuspendedKey = wasSuspendedKeyValue.boolValue
                    print(wasSuspendedKey)
                    if !wasSuspendedKey {
                        run_pause(param, 1)
                    }
                case .ended:
                    guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                        break
                    }
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        run_pause(param, 0)
                    }
                default:
                    break
                }
            }
        }
    }

    func setupRemoteTransportControls() {
        // Get the shared MPRemoteCommandCenter
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            DispatchQueue.global().async {
                run_pause(self.param, get_pause(self.param) == 1 ? 0 : 1)
                DispatchQueue.main.async {
                    let t = self.soundPTS.isNaN ? self.videoPTS : self.soundPTS
                    self.player.updatePosition(t: t)
                }
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            if get_pause(self.param) == 1 {
                return .commandFailed
            }
            DispatchQueue.global().async {
                run_pause(self.param, 1)
                DispatchQueue.main.async {
                    let t = self.soundPTS.isNaN ? self.videoPTS : self.soundPTS
                    self.player.updatePosition(t: t)
                }
            }
            return .success
        }

        commandCenter.playCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            if get_pause(self.param) == 0 {
                return .commandFailed
            }
            DispatchQueue.global().async {
                run_pause(self.param, 0)
                DispatchQueue.main.async {
                    let t = self.soundPTS.isNaN ? self.videoPTS : self.soundPTS
                    self.player.updatePosition(t: t)
                }
            }
            return .success
        }

//        commandCenter.skipForwardCommand.addTarget { [weak self] event in
//            guard let self = self else {return .commandFailed}
//            guard let command = event.command as? MPSkipIntervalCommand else {
//                return .noSuchContent
//            }
//            let interval = command.preferredIntervals[0]
//            var pos = self.soundPTS.isNaN ? self.videoPTS : self.soundPTS
//            pos += Double(truncating: interval)
//            let pos64: Int64 = Int64(pos * 1000000)
//            run_seek(self.param, pos64)
//            return .success
//        }
//        commandCenter.skipForwardCommand.preferredIntervals = [15]

        commandCenter.nextTrackCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            run_seek_chapter(self.param, Int32(1))
            return .success
        }

//        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
//            guard let self = self else {return .commandFailed}
//            guard let command = event.command as? MPSkipIntervalCommand else {
//                return .noSuchContent
//            }
//            let interval = command.preferredIntervals[0]
//            var pos = self.soundPTS.isNaN ? self.videoPTS : self.soundPTS
//            pos -= Double(truncating: interval)
//            let pos64: Int64 = Int64(pos * 1000000)
//            run_seek(self.param, pos64)
//            return .success
//        }
//        commandCenter.skipBackwardCommand.preferredIntervals = [15]

        commandCenter.previousTrackCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            run_seek_chapter(self.param, Int32(-1))
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self](remoteEvent) -> MPRemoteCommandHandlerStatus in
            guard let self = self else {return .commandFailed}
            if let event = remoteEvent as? MPChangePlaybackPositionCommandEvent {
                let pos = event.positionTime
                let pos64: Int64 = Int64(pos * 1000000)
                run_seek(self.param, pos64)
                return .success
            }
            return .commandFailed
        }
    }
    
    func finishRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
    }
    
    func updateMediaInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: name,
            MPNowPlayingInfoPropertyPlaybackRate: get_pause(param) == 1 ? 0.0: 1.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: soundPTS.isNaN ? videoPTS : soundPTS,
            MPMediaItemPropertyPlaybackDuration: mediaDuration,
        ]
    }
}

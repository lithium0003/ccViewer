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
import SwiftUI
import Combine
import AVKit
import Accelerate

public class Player {
    public class func prepare(storages: [String], fileids: [String], playlist: Bool) async -> StreamBridge {
        PiPManager.shared.stopCallback?()
        PiPManager.shared.stopCallback = nil
        try? await Task.sleep(for: .milliseconds(500))

        let bridge = await StreamBridge(storages: storages, fileids: fileids, playlist: playlist)
        return bridge
    }
}

public class PiPManager {
    public static let shared = PiPManager()
    private init() {}
    
    public var isActive = false
    public var stopCallback: (() -> Void)?
}

public class StreamBridge: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate {
    let playlist: Bool
    var remotes: [RemoteItem]
    var curIdx = 0
    var idx = 0
    var stream: RemoteStream?
    var position: Int64
    var soundPTS: Double
    var videoPTS: Double
    var name: String
    var mediaDuration: Double
    var soundOnly = false
    var image: MPMediaItemArtwork?
    var playPos = 0.0 {
        didSet {
            positionSender.send(playPos)
            try? displayLayer.controlTimebase?.setTime(CMTime(seconds: playPos, preferredTimescale: 1000000))
        }
    }
    var pause = false

    var loop: Bool {
        UserDefaults.standard.bool(forKey: "loop")
    }
    var shuffle: Bool {
        UserDefaults.standard.bool(forKey: "shuffle")
    }

    public let titleSender = PassthroughSubject<String, Never>()
    public let waiterSender = PassthroughSubject<Bool, Never>()
    public let ccTextSender = PassthroughSubject<String?, Never>()
    var ccLastText = ""
    public let infoTextSender = PassthroughSubject<String, Never>()
    public let artworkImageSender = PassthroughSubject<UIImage?, Never>()
    public let positionSender = PassthroughSubject<Double, Never>()

    public let failedSender = PassthroughSubject<Bool, Never>()
    public let durationSender = PassthroughSubject<Double, Never>()
    public let soundOnlySender = PassthroughSubject<Bool, Never>()
    public let pauseSender = PassthroughSubject<Bool, Never>()

    public let touchUpdate = PassthroughSubject<Date, Never>()
    public let lockrotateSender = PassthroughSubject<Bool, Never>()

    var selfref: UnsafeMutableRawPointer!
    var sound: AudioQueuePlayer!
    
    var pipController: AVPictureInPictureController?
    var displayLayer: AVSampleBufferDisplayLayer!
    
    var pixelBuffer: CVPixelBuffer?
    var bufWidth = 0
    var bufHeight = 0
    
    var isCancel = false
    let semaphore = DispatchSemaphore(value: 1)
    var param: UnsafeMutableRawPointer!
    
    var nameCStr: [CChar]? = nil
    var userBreak = false

    var cancellables: Set<AnyCancellable> = []
    
    init(storages: [String], fileids: [String], playlist: Bool) async {
        await UIApplication.shared.beginReceivingRemoteControlEvents()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(error)
        }

        self.playlist = playlist
        var remotes: [RemoteItem] = []
        for (storage, fileid) in zip(storages, fileids) {
            if let item = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fileid) {
                remotes.append(item)
            }
        }
        self.remotes = remotes
        stream = nil
        name = ""
        position = 0
        soundPTS = Double.nan
        videoPTS = Double.nan
        mediaDuration = 0
        sound = AudioQueuePlayer()
        super.init()
        
        selfref = Unmanaged<StreamBridge>.passUnretained(self).toOpaque()
        
        pauseSender.sink { [weak self] value in
            self?.pause = value
        }
        .store(in: &cancellables)

        await Task { @MainActor in
            displayLayer = AVSampleBufferDisplayLayer()
            displayLayer.videoGravity = .resizeAspect
            displayLayer.controlTimebase = try? CMTimebase(sourceClock: .hostTimeClock)
            try? displayLayer.controlTimebase?.setTime(.zero)
            try? displayLayer.controlTimebase?.setRate(1)
        }.value
    }

    let setDuration: @convention(c) (UnsafeMutableRawPointer?, Double) -> Void = {
        (ref, duration) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.mediaDuration = duration
            stream.durationSender.send(duration)

            Task { @MainActor in
                if AVPictureInPictureController.isPictureInPictureSupported(), stream.pipController == nil {
                    stream.pipController = AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: stream.displayLayer, playbackDelegate: stream))
                    stream.pipController?.delegate = stream
                    stream.pipController?.canStartPictureInPictureAutomaticallyFromInline = true
                }
            }
        }
    }
    
    let setSoundOnly: @convention(c) (UnsafeMutableRawPointer?) -> Void = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.soundOnly = true
            stream.soundOnlySender.send(true)
        }
    }
    
    let cancel: @convention(c) (UnsafeMutableRawPointer?) -> Void = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.isCancel = true
            stream.stream?.isLive = false
            Task {
                for remote in stream.remotes {
                    await remote.cancel()
                }
            }
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
               return -1
            }
            guard let rstream = stream.stream else {
                return -1
            }
            stream.semaphore.wait()
            defer {
                stream.semaphore.signal()
            }
            if stream.position >= stream.remotes[stream.idx].size {
                return -1
            }
            let semaphore = DispatchSemaphore(value: 0)
            let task = Task {
                defer {
                    semaphore.signal()
                }
                let data = try? await rstream.read(position: stream.position, length: Int(buf_size))
                if stream.isCancel {
                    return
                }
                assert(data?.count ?? 0 <= Int(buf_size))
                if let data, data.count > 0 {
                    count = data.copyBytes(to: buf_array)
                    stream.position += Int64(count)
                }
                else {
                    return
                }
            }
            semaphore.wait()
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
                return -1
            }
            stream.semaphore.wait()
            defer {
                stream.semaphore.signal()
            }
            switch whence {
            case 0x10000:
                count = stream.remotes[stream.idx].size
            case SEEK_SET:
                if offset >= 0 && offset <= stream.remotes[stream.idx].size {
                    stream.position = offset
                    count = offset
                }
                else {
                    count = -1
                }
            case SEEK_CUR:
                let offset2 = offset + stream.position
                if offset2 >= 0 && offset2 <= stream.remotes[stream.idx].size {
                    stream.position = offset2
                    count = offset2
                }
                else {
                    count = -1
                }
            case SEEK_END:
                let offset2 = stream.remotes[stream.idx].size - offset
                if offset2 >= 0 && offset2 <= stream.remotes[stream.idx].size {
                    stream.position = offset2
                    count = offset2
                }
                else {
                    count = -1
                }
            default:
                count = -1
            }
        }
        return count
    }

    let draw_pict: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, Int32, Int32, UnsafeMutablePointer<Int32>?, Double) -> Void = {
        (ref, image_buf, width, height, linesizes, t) in
        if let ref_unwrapped = ref, let images = image_buf, let linesizes = linesizes {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            if stream.isCancel {
                return
            }
            if t.isNaN {
                return
            }
            stream.videoPTS = t
            autoreleasepool {
                stream.playPos = t
                guard let displayLayer = stream.displayLayer else {
                    return
                }
                if stream.pixelBuffer == nil || stream.bufWidth != width || stream.bufHeight != height {
                    stream.pixelBuffer = nil
                    stream.bufWidth = Int(width)
                    stream.bufHeight = Int(height)
                    let options = [
                        kCVPixelBufferIOSurfacePropertiesKey: [:],
                    ]
                    CVPixelBufferCreate(kCFAllocatorDefault, Int(width), Int(height), kCVPixelFormatType_420YpCbCr8Planar, options as CFDictionary, &stream.pixelBuffer)
                }
                guard stream.pixelBuffer != nil else {
                    return
                }
                do {
                    CVPixelBufferLockBaseAddress(stream.pixelBuffer!, [])
                    defer {
                        CVPixelBufferUnlockBaseAddress(stream.pixelBuffer!, [])
                    }
                    let yp = CVPixelBufferGetBaseAddressOfPlane(stream.pixelBuffer!, 0)
                    guard let ysrc = images[0] else { return }
                    let sline = Int(linesizes[0])
                    let dline = CVPixelBufferGetBytesPerRowOfPlane(stream.pixelBuffer!, 0)
                    for y in 0..<Int(height) {
                        memcpy(yp! + dline * y, ysrc + sline * y, Int(width))
                    }
                    let up = CVPixelBufferGetBaseAddressOfPlane(stream.pixelBuffer!, 1)
                    guard let usrc = images[1] else { return }
                    let sline2 = Int(linesizes[1])
                    let dline2 = CVPixelBufferGetBytesPerRowOfPlane(stream.pixelBuffer!, 1)
                    for y in 0..<Int(height) / 2 {
                        memcpy(up! + dline2 * y, usrc + sline2 * y, Int(width)/2)
                    }
                    let vp = CVPixelBufferGetBaseAddressOfPlane(stream.pixelBuffer!, 2)
                    guard let vsrc = images[2] else { return }
                    let sline3 = Int(linesizes[2])
                    let dline3 = CVPixelBufferGetBytesPerRowOfPlane(stream.pixelBuffer!, 2)
                    for y in 0..<Int(height) / 2 {
                        memcpy(vp! + dline3 * y, vsrc + sline3 * y, Int(width)/2)
                    }
                }
                var formatDescription: CMFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: stream.pixelBuffer!, formatDescriptionOut: &formatDescription)
                guard let formatDescription else {
                    return
                }
                guard let sampleBuf = try? CMSampleBuffer(imageBuffer: stream.pixelBuffer!, formatDescription: formatDescription, sampleTiming: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: displayLayer.sampleBufferRenderer.timebase.time, decodeTimeStamp: .invalid)) else {
                    return
                }
                sampleBuf.sampleAttachments[0][.displayImmediately] = true
                if displayLayer.sampleBufferRenderer.status == .failed {
                    displayLayer.sampleBufferRenderer.flush()
                }
                displayLayer.sampleBufferRenderer.enqueue(sampleBuf)
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
            stream.sound.play()
            return stream.sound.isPlay ? 1 : 0
        }
        return -1
    }
    
    let sound_stop: @convention(c) (UnsafeMutableRawPointer?) -> Int32 = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            print("sound_stop")
            stream.sound.stop()
            return stream.sound.isPlay ? 1 : 0
        }
        return -1
    }

    let wait_stop: @convention(c) (UnsafeMutableRawPointer?) -> Void = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.waiterSender.send(false)
        }
    }

    let wait_start: @convention(c) (UnsafeMutableRawPointer?) -> Void = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.waiterSender.send(true)
        }
    }

    let send_pause: @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void = {
        (ref, value) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.pauseSender.send(value == 1)
        }
    }

    let skip_media: @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void = {
        (ref, value) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.curIdx += Int(value)
            stream.onStop()
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

    let cc_draw: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int32) -> Void = {
        (ref, buf, tp) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            if let buf_unwrapped = buf {
                let cc = String(cString: buf_unwrapped)
                if stream.ccLastText != cc {
                    stream.ccLastText = cc
                    stream.ccTextSender.send(convertText(text: cc, ass: tp == 1))
                }
            }
            else {
                stream.ccTextSender.send(nil)
            }
        }
    }

    class func convertLanguageText(lang: String, media: Int, idx: Int) -> String {
        let mediaStr: String
        switch media {
        case 0:
            mediaStr = FrameworkResource.getLocalized(key: "Video") + " : "
        case 1:
            mediaStr = FrameworkResource.getLocalized(key: "Audio") + " : "
        case 2:
            mediaStr = FrameworkResource.getLocalized(key: "Subtitles") + " : "
        default:
            mediaStr = ""
        }
        if idx < 0 {
            return mediaStr + "off"
        }
        return mediaStr + FrameworkResource.getLocalized(key: lang) + "(\(idx))"
    }

    let change_lang: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int32, Int32) -> Void = {
        (ref, buf, tp, idx) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            if let buf_unwrapped = buf {
                let lang = String(cString: buf_unwrapped)
                let str = convertLanguageText(lang: lang, media: Int(tp), idx: Int(idx))
                stream.infoTextSender.send(str)
            }
        }
    }

    func setupArtwork(_ i: Int) async {
        let storage = remotes[i].storage
        var basename = remotes[i].name
        var parentId = remotes[i].parent
        if let subid = remotes[i].subid, let subbase = await CloudFactory.shared.storageList.get(storage)?.get(fileId: subid) {
            basename = subbase.name
            parentId = subbase.parent
        }
        var components = basename.components(separatedBy: ".")
        if components.count > 1 {
            components.removeLast()
            basename = components.joined(separator: ".")
        }
        
        if let imageitem = await CloudFactory.shared.data.getImage(storage: storage, parentId: parentId, baseName: basename) {
            if let imagestream = await CloudFactory.shared.storageList.get(storage)?.get(fileId: imageitem.id ?? "")?.open() {
                
                if let data = try? await imagestream.read(position: 0, length: Int(imageitem.size)), let image = UIImage(data: data) {
                    self.image = MPMediaItemArtwork(boundsSize: image.size) { size in
                        return image
                    }
                    artworkImageSender.send(image)
                    return
                }
            }
        }
        artworkImageSender.send(nil)
        image = nil
    }

    public func onStop() {
        isCancel = true
        stream?.isLive = false
        Task {
            run_quit(param)
            sound.stop()
        }
        stream = nil
    }
    
    public func onClose(_ interactive: Bool) {
        userBreak = interactive
        isCancel = true
        stream?.isLive = false
        Task {
            run_quit(param)
            sound.stop()
        }
        stream = nil
        pipController = nil
        pixelBuffer = nil
    }
    
    public func onSeek(_ pos: Double) {
        let pos64: Int64 = Int64(pos * 1000000)
        run_seek(param, pos64)
    }
    
    public func onSeekChapter(_ inc: Int) {
        run_seek_chapter(param, Int32(inc))
    }
    
    public func onPause(_ state: Bool) async {
        run_pause(param, state ? 1 : 0)
    }

    public func onCycleCh(_ tag: Int) {
        run_cycle_ch(param, Int32(tag))
    }
    
    public func run() async -> Bool {
        guard remotes.count > 0 else {
            return true
        }
        
        let aribText = UserDefaults.standard.bool(forKey: "ARIB_subtitle_convert_to_text")
        var ret = -1
        var count = 0

        Task { @MainActor in
            setObserver()
            setupRemoteTransportControls()
        }
        let skip = UserDefaults.standard.integer(forKey: "playStartSkipSec")
        let stop = UserDefaults.standard.integer(forKey: "playStopAfterSec")

        sound.onLoadData = { [weak self] buffer, capacity in
            guard let self else {
                return Double.nan
            }
            let t = load_sound(self.param, buffer, Int32(capacity/2))
            if !t.isNaN {
                self.soundPTS = t
                self.playPos = t
                self.positionSender.send(t)
            }
            return t
        }
        
        while loop || curIdx < remotes.count {
            idx = curIdx
            if idx < 0 {
                idx = 0
            }
            if idx >= remotes.count {
                idx = 0
            }
            if idx == 0, shuffle {
                remotes = remotes.shuffled()
            }
            curIdx = idx
            isCancel = false
            stream = await remotes[idx].open()
            name = remotes[idx].name
            position = 0
            soundPTS = Double.nan
            videoPTS = Double.nan
            mediaDuration = 0
            soundOnlySender.send(false)
            titleSender.send(name)

            nameCStr = name.cString(using: .utf8)
            var start_skip = Double.nan
            if skip > 0 {
                start_skip = Double(skip)
            }
            var stop_limit = Double.nan
            if stop > 0 {
                stop_limit = Double(stop)
            }
            await setupArtwork(idx)

            var partial_start = Double.nan
            if !playlist, let p = await CloudFactory.shared.data.getMark(storage: remotes[idx].storage, targetID: remotes[idx].id) {
                if remotes.count > 1 {
                    if p < 0 || p >= 1 {
                        curIdx += 1
                        continue
                    }
                    partial_start = p
                }
                else if p < 0.99 {
                    partial_start = p
                }
            }
            
            if var nameCStr {
                ret = await withCheckedContinuation { continuation in
                    nameCStr.withUnsafeMutableBufferPointer { itemname in
                        let latency = AVAudioSession.sharedInstance().outputLatency
                        print(latency)
                        self.param = make_arg(
                            itemname.baseAddress,
                            latency,
                            partial_start,
                            start_skip,
                            stop_limit,
                            aribText ? 1: 0,
                            self.selfref,
                            self.read_packet,
                            self.seek,
                            self.cancel,
                            self.draw_pict,
                            self.setDuration,
                            self.setSoundOnly,
                            self.sound_play,
                            self.sound_stop,
                            self.wait_stop,
                            self.wait_start,
                            self.send_pause,
                            self.skip_media,
                            self.cc_draw,
                            self.change_lang)
                        
                        Task {
                            do {
                                try AVAudioSession.sharedInstance().setActive(true)
                            } catch {
                                print(error)
                            }

                            run_play(self.param)
                            self.sound.play()
                            let task = Task {
                                while true {
                                    try await Task.sleep(for: .seconds(1))
                                    updateMediaInfo()
                                }
                            }
                            var ret = Int(run_finish(self.param))
                            if userBreak {
                                ret = 1
                            }
                            task.cancel()
                            if idx == curIdx {
                                curIdx += 1
                                if !playlist {
                                    Task {
                                        await CloudFactory.shared.data.setMark(storage: remotes[idx].storage, targetID: remotes[idx].id, parentID: remotes[idx].parent, position: playPos / mediaDuration)
                                    }
                                }
                            }
                            else {
                                if !playlist {
                                    Task {
                                        await CloudFactory.shared.data.setMark(storage: remotes[idx].storage, targetID: remotes[idx].id, parentID: remotes[idx].parent, position: 1.0)
                                    }
                                }
                            }

                            stream?.isLive = false
                            Task {
                                await remotes[idx].cancel()
                            }
                            stream = nil
                            pixelBuffer = nil
                            continuation.resume(returning: ret)
                        }
                    }
                }
            }
            if ret >= 0 {
                count += 1
            }
            if ret == 1 {
                break
            }
        }

        PiPManager.shared.stopCallback = nil
        PiPManager.shared.isActive = false
        await Task { @MainActor in
            pipController?.stopPictureInPicture()
            pipController = nil

            do {
                try AVAudioSession.sharedInstance().setActive(false)
            } catch {
                print(error)
            }
            UIApplication.shared.endReceivingRemoteControlEvents()

            delObserver()
            finishRemoteTransportControls()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }.value
        return count == 0
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
                    guard let wasSuspendedKeyValue = userInfo[AVAudioSessionInterruptionReasonKey] as? NSNumber else {
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
        let skip_nextsec = UserDefaults.standard.integer(forKey: "playSkipForwardSec")
        let skip_prevsec = UserDefaults.standard.integer(forKey: "playSkipBackwardSec")
        // Get the shared MPRemoteCommandCenter
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            Task {
                run_pause(self.param, self.pause ? 0 : 1)
                let t = self.soundPTS.isNaN ? self.videoPTS : self.soundPTS
                self.playPos = t
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            if self.pause {
                return .commandFailed
            }
            Task {
                run_pause(self.param, 1)
                let t = self.soundPTS.isNaN ? self.videoPTS : self.soundPTS
                self.playPos = t
            }
            return .success
        }

        commandCenter.playCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            if !self.pause {
                return .commandFailed
            }
            Task {
                run_pause(self.param, 0)
                let t = self.soundPTS.isNaN ? self.videoPTS : self.soundPTS
                self.playPos = t
            }
            return .success
        }

        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            guard let command = event.command as? MPSkipIntervalCommand else {
                return .noSuchContent
            }
            let interval = command.preferredIntervals[0]
            var pos = self.soundPTS.isNaN ? self.videoPTS : self.soundPTS
            pos += Double(truncating: interval)
            let pos64: Int64 = Int64(pos * 1000000)
            run_seek(self.param, pos64)
            return .success
        }
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: skip_nextsec)]

        commandCenter.nextTrackCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            run_seek_chapter(self.param, Int32(1))
            return .success
        }

        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            guard let command = event.command as? MPSkipIntervalCommand else {
                return .noSuchContent
            }
            let interval = command.preferredIntervals[0]
            var pos = self.soundPTS.isNaN ? self.videoPTS : self.soundPTS
            pos -= Double(truncating: interval)
            let pos64: Int64 = Int64(pos * 1000000)
            run_seek(self.param, pos64)
            return .success
        }
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: skip_prevsec)]

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
        if let image = image {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyTitle: name,
                MPMediaItemPropertyArtwork: image,
                MPNowPlayingInfoPropertyPlaybackRate: pause ? 0.0: 1.0,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: soundPTS.isNaN ? videoPTS : soundPTS,
                MPMediaItemPropertyPlaybackDuration: mediaDuration,
            ]
        }
        else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyTitle: name,
                MPNowPlayingInfoPropertyPlaybackRate: pause ? 0.0: 1.0,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: soundPTS.isNaN ? videoPTS : soundPTS,
                MPMediaItemPropertyPlaybackDuration: mediaDuration,
            ]
        }
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        if playPos >= mediaDuration { return }
        pause = !playing
        Task { await onPause(pause) }
    }
    
    public func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: CMTime(seconds: mediaDuration, preferredTimescale: 1000000))
    }
    
    public func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        pause
    }

    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
    }

    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime) async {
        Task {
            run_pause(param, 1)
            onSeek(playPos + skipInterval.seconds)
            run_pause(param, 0)
        }
    }
    
    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("pictureInPictureControllerWillStartPictureInPicture")
        PiPManager.shared.isActive = true
        PiPManager.shared.stopCallback = { [weak self] in
            self?.pipController?.stopPictureInPicture()
        }
    }
    
    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("pictureInPictureControllerDidStopPictureInPicture")
        PiPManager.shared.isActive = false
        if userBreak {
            Task { @MainActor in
                onClose(true)
            }
        }
    }
}

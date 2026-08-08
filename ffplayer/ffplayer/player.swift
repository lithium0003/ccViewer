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

public class AudioSessionManager {
    public static let shared = AudioSessionManager()
    private var isObserving = false
    
    private init() {}
    
    public func activateSession() {
        updateCategoryForCurrentRoute()
        
        if !isObserving {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRouteChange(_:)),
                name: AVAudioSession.routeChangeNotification,
                object: nil
            )
            isObserving = true
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            print("audio session on")
        } catch {
            print("failed to set audio session on: \(error)")
        }
    }
    
    public func deactivateSession() {
        if isObserving {
            NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
            isObserving = false
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("audio session off")
        } catch {
            print("failed to set audio session off: \(error)")
        }
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        updateCategoryForCurrentRoute()
    }
    
    private func updateCategoryForCurrentRoute() {
        let session = AVAudioSession.sharedInstance()
        let currentOutputs = session.currentRoute.outputs
        
        let headphonePorts: [AVAudioSession.Port] = [
            .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .usbAudio
        ]
        
        let isHeadphoneConnected = currentOutputs.contains { headphonePorts.contains($0.portType) }
        
        do {
            if isHeadphoneConnected {
                try session.setCategory(.playback, mode: .default)
            } else {
                try session.setCategory(.soloAmbient, mode: .default)
            }
        } catch {
            print("failed to set category: \(error)")
        }
    }
}

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
    var remotes: [(String, String)]
    var curIdx = 0
    var idx = 0
    var remoteItem: RemoteItem?
    var stream: RemoteStream?
    var paletteStr = ""
    var position: Int64
    var soundPTS: Double
    var videoPTS: Double
    var lastVideoPTS = -1.0
    var playbackRate: Double = 1.0
    var name: String
    var mediaDuration: Double
    var soundOnly = 0
    var image: MPMediaItemArtwork?
    var playPos = 0.0 {
        didSet {
            positionSender.send(playPos)
            try? displayLayer.controlTimebase?.setTime(CMTime(seconds: playPos, preferredTimescale: 1000000))
        }
    }
    var pause = false

    var failCount = 0
    let maxFailCount = 20
    
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

    public let initDoneSender = PassthroughSubject<Bool, Never>()

    var selfref: UnsafeMutableRawPointer!
    var sound: AudioQueuePlayer?
    
    var pipController: AVPictureInPictureController?
    var displayLayer: AVSampleBufferDisplayLayer!
    
    var bufWidth = 0
    var bufHeight = 0
    
    var isCancel = false
    let semaphore = DispatchSemaphore(value: 1)
    var param: UnsafeMutableRawPointer?
    
    var userBreak = false

    var cancellables: Set<AnyCancellable> = []
    
    init(storages: [String], fileids: [String], playlist: Bool) async {
        await UIApplication.shared.beginReceivingRemoteControlEvents()
        AudioSessionManager.shared.activateSession()

        self.playlist = playlist
        remotes = zip(storages, fileids).map({ ($0, $1) })
        remoteItem = nil
        stream = nil
        name = ""
        position = 0
        soundPTS = Double.nan
        videoPTS = Double.nan
        mediaDuration = 0
        sound = AudioQueuePlayer.shared
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

    let setDuration: @convention(c) (UnsafeMutableRawPointer?, Double) -> Double = {
        (ref, duration) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            Task { @MainActor in
                if AVPictureInPictureController.isPictureInPictureSupported(), stream.pipController == nil {
                    stream.pipController = AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: stream.displayLayer, playbackDelegate: stream))
                    stream.pipController?.delegate = stream
                    stream.pipController?.canStartPictureInPictureAutomaticallyFromInline = true
                }
            }
            if let dvdItem = stream.remoteItem as? DVDRemoteItem {
                let dvdDuration = dvdItem.chapters.map({ $0.2 }).reduce(0, +)
                stream.mediaDuration = dvdDuration
                stream.durationSender.send(dvdDuration)
                return dvdDuration
            }
            else {
                stream.mediaDuration = duration
                stream.durationSender.send(duration)
                return duration
            }
        }
        return 0
    }
    
    let setSoundOnly: @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void = {
        (ref, value) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.soundOnly = Int(value)
            stream.soundOnlySender.send(value == 1)
        }
    }
    
    let cancel: @convention(c) (UnsafeMutableRawPointer?) -> Void = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.isCancel = true
            stream.stream?.isLive = false
            stream.stream = nil
            stream.remoteItem = nil
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
               return averror_exit
            }
            guard let ritem = stream.remoteItem else {
                return averror_exit
            }
            //print("read \(stream.position) \(buf_size)")
            stream.semaphore.wait()
            defer {
                stream.semaphore.signal()
            }
            if stream.position >= ritem.size {
                return averror_eof
            }
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached(priority: .high) {
                defer {
                    semaphore.signal()
                }
                let start = Date()
                while start.timeIntervalSinceNow > -30 {
                    guard let rstream = stream.stream else {
                        break
                    }
                    let data = try? await rstream.read(position: stream.position, length: Int(buf_size))
                    if stream.isCancel {
                        stream.failCount = 0
                        return
                    }
                    assert(data?.count ?? 0 <= Int(buf_size))
                    if let data, data.count > 0 {
                        count = data.copyBytes(to: buf_array)
                        stream.position += Int64(count)
                        stream.failCount = 0
                        break
                    }

                    if stream.failCount < stream.maxFailCount {
                        stream.failCount += 1
                        // error, reopen stream
                        print("read reopen stream")
                        rstream.isLive = false
                        stream.stream = nil
                        try? await Task.sleep(for: .seconds(2))
                        stream.stream = await stream.remoteItem?.open()
                    }
                    else {
                        return
                    }
                }
            }
            semaphore.wait()
            if stream.failCount < stream.maxFailCount {
                return Int32(count)
            }
        }
        //print("read count \(count)")
        return averror_exit
    }

    let seek: @convention(c) (UnsafeMutableRawPointer?, Int64, Int32) -> Int64 = {
        (ref, offset, whence) in
        var count: Int64 = 0
        print("seek \(offset) \(whence)")
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            if stream.isCancel {
                return -1
            }
            guard let ritem = stream.remoteItem else {
                return -1
            }
            stream.semaphore.wait()
            defer {
                stream.semaphore.signal()
            }
            switch whence {
            case 0x10000:
                count = ritem.size
            case SEEK_SET:
                if offset >= 0 && offset <= ritem.size {
                    stream.position = offset
                    count = offset
                }
                else {
                    count = -1
                }
            case SEEK_CUR:
                let offset2 = offset + stream.position
                if offset2 >= 0 && offset2 <= ritem.size {
                    stream.position = offset2
                    count = offset2
                }
                else {
                    count = -1
                }
            case SEEK_END:
                let offset2 = ritem.size + offset
                if offset2 >= 0 && offset2 <= ritem.size {
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
                if stream.soundOnly == 2 {
                    stream.playPos = t
                }
                guard let displayLayer = stream.displayLayer else {
                    return
                }
                var pixelBuffer: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, Int(width), Int(height), kCVPixelFormatType_420YpCbCr8Planar, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
                guard let validPixelBuffer = pixelBuffer else { return }
                do {
                    CVPixelBufferLockBaseAddress(validPixelBuffer, [])
                    defer { CVPixelBufferUnlockBaseAddress(validPixelBuffer, []) }
                    let yp = CVPixelBufferGetBaseAddressOfPlane(validPixelBuffer, 0)
                    guard let ysrc = images[0] else { return }
                    let sline = Int(linesizes[0])
                    let dline = CVPixelBufferGetBytesPerRowOfPlane(validPixelBuffer, 0)
                    for y in 0..<Int(height) {
                        memcpy(yp! + dline * y, ysrc + sline * y, Int(width))
                    }
                    let up = CVPixelBufferGetBaseAddressOfPlane(validPixelBuffer, 1)
                    guard let usrc = images[1] else { return }
                    let sline2 = Int(linesizes[1])
                    let dline2 = CVPixelBufferGetBytesPerRowOfPlane(validPixelBuffer, 1)
                    for y in 0..<Int(height) / 2 {
                        memcpy(up! + dline2 * y, usrc + sline2 * y, Int(width)/2)
                    }
                    let vp = CVPixelBufferGetBaseAddressOfPlane(validPixelBuffer, 2)
                    guard let vsrc = images[2] else { return }
                    let sline3 = Int(linesizes[2])
                    let dline3 = CVPixelBufferGetBytesPerRowOfPlane(validPixelBuffer, 2)
                    for y in 0..<Int(height) / 2 {
                        memcpy(vp! + dline3 * y, vsrc + sline3 * y, Int(width)/2)
                    }
                }
                var formatDescription: CMFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: validPixelBuffer, formatDescriptionOut: &formatDescription)
                guard let formatDescription else {
                    return
                }
                guard let sampleBuf = try? CMSampleBuffer(imageBuffer: validPixelBuffer, formatDescription: formatDescription, sampleTiming: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: displayLayer.sampleBufferRenderer.timebase.time, decodeTimeStamp: .invalid)) else {
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
            guard let sound = stream.sound else { return -1 }
            if stream.isCancel {
               return sound.isPlay ? 1 : 0
            }
            print("sound_play")
            sound.play()
            return sound.isPlay ? 1 : 0
        }
        return -1
    }
    
    let sound_stop: @convention(c) (UnsafeMutableRawPointer?) -> Int32 = {
        (ref) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            guard let sound = stream.sound else { return -1 }
            print("sound_stop")
            sound.stop()
            return sound.isPlay ? 1 : 0
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

    let initial_seek: @convention(c) (UnsafeMutableRawPointer?, Double) -> Void = {
        (ref, value) in
        if let ref_unwrapped = ref {
            let stream = Unmanaged<StreamBridge>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            stream.onSeek(value)
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
                let cmdremoved = asstext.replacingOccurrences(of: "{\\.*}", with: "", options: .regularExpression)
                let result = cmdremoved.replacingOccurrences(of: "\\\\[Nn]", with: "\n", options: .regularExpression)
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
        let (storage, fileid) = remotes[i]
        guard let item = await CloudFactory.shared.data.getData(storage: storage, fileId: fileid)?.getItem() else {
            artworkImageSender.send(nil)
            image = nil
            return
        }
        let parentId: String
        var basename = ""
        if let subitem = item as? CueSheetRemoteItem {
            basename = subitem.baseItem.name
            parentId = subitem.baseItem.parent
        }
        else {
            basename = item.name
            parentId = item.parent
        }
        var components = basename.components(separatedBy: ".")
        if components.count > 1 {
            components.removeLast()
            basename = components.joined(separator: ".")
        }
        
        if let imageitem = await CloudFactory.shared.data.getImage(storage: storage, parentId: parentId, baseName: basename) {
            if let imagestream = await CloudFactory.shared.data.getData(storage: storage, fileId: imageitem.id ?? "")?.getItem()?.open() {
                defer {
                    imagestream.isLive = false
                }
                if let data = try? await imagestream.read(), let image = UIImage(data: data) {
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
        if let param {
            run_quit(param)
        }
        sound?.stop()
        stream = nil
    }
    
    public func onClose(_ interactive: Bool) {
        userBreak = interactive
        isCancel = true
        stream?.isLive = false
        if let param {
            run_quit(param)
        }
        sound?.stop()
        stream = nil
        pipController = nil
    }
    
    public func onSeek(_ pos: Double) {
        if let dvdItem = remoteItem as? DVDRemoteItem {
            var chaptDuration = 0.0
            var currentCapter = 0
            for (c, (_, _, t, _)) in dvdItem.chapters.enumerated() {
                chaptDuration += t
                if pos < chaptDuration {
                    currentCapter = c
                    break
                }
            }
            let st = dvdItem.chapters[0..<currentCapter].map({ $0.1 }).reduce(0, +)
            let tm = dvdItem.chapters[0..<currentCapter].map({ $0.2 }).reduce(0, +)
            let s = dvdItem.chapters[currentCapter].1
            let t = dvdItem.chapters[currentCapter].2
            let pos64: Int64 = Int64((pos - tm) / t * Double(s)) + st
            let time64: Int64 = Int64(pos * 1000000)
            if let param {
                run_seek(param, time64, pos64)
            }
        }
        else {
            let pos64: Int64 = Int64(pos * 1000000)
            if let param {
                run_seek(param, pos64, -1)
            }
        }
    }

    public func onSeekBytes(_ pos: Double) {
        if (remoteItem as? DVDRemoteItem) != nil {
            let pos64: Int64 = Int64(pos * Double(remoteItem?.size ?? 0))
            let time64: Int64 = Int64(pos * mediaDuration * 1000000)
            if let param {
                run_seek(param, time64, pos64)
            }
        }
        else {
            onSeek(pos * mediaDuration)
        }
    }

    public func onSeekBytes(_ pos: Int64) {
        if let param {
            run_seek(param, 0, pos)
        }
    }

    public func onSeekChapter(_ inc: Int) {
        if let param {
            if let dvdItem = remoteItem as? DVDRemoteItem {
                var chaptDuration = 0.0
                var currentCapter = 0
                for (c, (_, _, t, _)) in dvdItem.chapters.enumerated() {
                    chaptDuration += t
                    if playPos < chaptDuration {
                        currentCapter = c
                        break
                    }
                }
                var inc = inc
                if inc < 0, playPos - 1 > dvdItem.chapters[0..<currentCapter].map({ $0.2 }).reduce(0, +) {
                    inc += 1
                }
                currentCapter += inc
                if currentCapter < 0 {
                    run_seek_chapter(param, -1)
                    return
                }
                if currentCapter >= dvdItem.chapters.count {
                    run_seek_chapter(param, 1)
                    return
                }
                let st = dvdItem.chapters[0..<currentCapter].map({ $0.1 }).reduce(0, +)
                let tm = dvdItem.chapters[0..<currentCapter].map({ $0.2 }).reduce(0, +)
                run_seek(param, Int64(tm * 1000000), st)
                return
            }
            run_seek_chapter(param, Int32(inc))
        }
    }
    
    public func onPause(_ state: Bool) async {
        if let param {
            run_pause(param, state ? 1 : 0)
        }
    }

    public func onCycleCh(_ tag: Int) {
        if let param {
            run_cycle_ch(param, Int32(tag))
        }
    }
    
    public func setPlaybackRate(_ rate: Double) {
        if let param {
            playbackRate = rate
            run_set_playback_rate(param, rate)
        }
    }
    
    public func run() async -> Bool {
        if sound == nil { return true }
        guard remotes.count > 0 else {
            return true
        }
        initDoneSender.send(false)

        var all_done = remotes.count > 1
        if !playlist {
            await withTaskGroup { group in
                for (storage, fileid) in remotes {
                    group.addTask {
                        if let p = await CloudFactory.shared.mark.getMark(storage: storage, targetID: fileid) {
                            p > 0
                        }
                        else {
                            false
                        }
                    }
                }
                for await b in group {
                    all_done = all_done && b
                }
            }
        }
        let aribText = UserDefaults.standard.bool(forKey: "ARIB_subtitle_convert_to_text")
        let loudnorm = UserDefaults.standard.bool(forKey: "ffplay loudnorm")
        var ret = -1
        var count = 0

        Task { @MainActor in
            setObserver()
            setupRemoteTransportControls()
        }
        let skip = UserDefaults.standard.integer(forKey: "playStartSkipSec")
        let stop = UserDefaults.standard.integer(forKey: "playStopAfterSec")

        sound?.onLoadData = { [weak self] buffer, capacity in
            guard let self else {
                return Double.nan
            }
            let t = load_sound(self.param, buffer, Int32(capacity/2))
            if t.isFinite {
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
                all_done = true
            }
            if idx == 0, shuffle {
                remotes = remotes.shuffled()
            }
            curIdx = idx
            isCancel = false
            let (storage, fileid) = remotes[idx]
            guard let item = await CloudFactory.shared.data.getData(storage: storage, fileId: fileid)?.getItem() else {
                curIdx += 1
                continue
            }
            if let uti = UTType(filenameExtension: item.ext), uti.conforms(to: .text) {
                curIdx += 1
                continue
            }
            else if let uti = UTType(filenameExtension: item.ext), uti.conforms(to: .image) {
                curIdx += 1
                continue
            }
            else if let uti = UTType(filenameExtension: item.ext), uti.conforms(to: .pdf) {
                curIdx += 1
                continue
            }
            else if item.ext == "conf" {
                curIdx += 1
                continue
            }
            else if item.ext == "cue" {
                curIdx += 1
                continue
            }
            remoteItem = item
            if let dvdItem = item as? DVDRemoteItem, let chapter = dvdItem.chapters.first {
                paletteStr = chapter.3
            }
            stream = await item.open()
            name = item.name
            position = 0
            soundPTS = Double.nan
            videoPTS = Double.nan
            mediaDuration = 0
            soundOnlySender.send(false)
            titleSender.send(name)

            let cNamePtr = strdup(name)
            let cPalettePtr = strdup(paletteStr)
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
            if !playlist, !all_done, let p = await CloudFactory.shared.mark.getMark(storage: storage, targetID: fileid) {
                if remotes.count > 1 {
                    if p < 0 || p > 0.99 {
                        curIdx += 1
                        continue
                    }
                    partial_start = p
                }
                else if p < 0.99 {
                    partial_start = p
                }
            }
            
            ret = await withCheckedContinuation { continuation in
                let latency = AVAudioSession.sharedInstance().outputLatency
                print(latency)
                param = make_arg(
                    cNamePtr,
                    cPalettePtr,
                    latency,
                    partial_start,
                    start_skip,
                    stop_limit,
                    playbackRate,
                    loudnorm ? 1: 0,
                    aribText ? 1: 0,
                    selfref,
                    read_packet,
                    seek,
                    cancel,
                    draw_pict,
                    setDuration,
                    setSoundOnly,
                    sound_play,
                    sound_stop,
                    wait_stop,
                    wait_start,
                    send_pause,
                    skip_media,
                    initial_seek,
                    cc_draw,
                    change_lang)
                
                Task {
                    defer {
                        free(cNamePtr)
                        free(cPalettePtr)
                    }
                    AudioSessionManager.shared.activateSession()

                    initDoneSender.send(true)
                    run_play(param!)
                    sound?.play()
                    let task = Task {
                        while true {
                            try await Task.sleep(for: .seconds(1))
                            updateMediaInfo()
                        }
                    }
                    var ret = Int(run_finish(param!))
                    param = nil
                    if userBreak {
                        ret = 1
                    }
                    task.cancel()
                    if idx == curIdx {
                        curIdx += 1
                        if ret >= 0 && !playlist {
                            if item.size > 0 && mediaDuration > 0 {
                                await CloudFactory.shared.mark.setMark(storage: item.storage, targetID: item.id, parentID: item.parent, position: max(0, min(1, playPos / mediaDuration)))
                            }
                            else {
                                await CloudFactory.shared.mark.setMark(storage: item.storage, targetID: item.id, parentID: item.parent, position: 1.0)
                            }
                        }
                    }
                    else {
                        if ret >= 0 && !playlist {
                            await CloudFactory.shared.mark.setMark(storage: item.storage, targetID: item.id, parentID: item.parent, position: 1.0)
                        }
                    }

                    stream?.isLive = false
                    remoteItem = nil
                    stream = nil
                    continuation.resume(returning: ret)
                }
            }
            initDoneSender.send(false)
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

            AudioSessionManager.shared.deactivateSession()
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
                    if let param {
                        set_latency(param, latency)
                    }
                    break
                case .oldDeviceUnavailable:
                    if audioSessionPortDescription?.portType == .headphones || audioSessionPortDescription?.portType == .bluetoothA2DP {
                        if let param {
                            run_pause(param, 1)
                        }
                    }
                    let latency = AVAudioSession.sharedInstance().outputLatency
                    print(latency)
                    if let param {
                        set_latency(param, latency)
                    }
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
                        if let param {
                            run_pause(param, 1)
                        }
                    }
                case .ended:
                    guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                        break
                    }
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        if let param {
                            run_pause(param, 0)
                        }
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
                if let param = self.param {
                    run_pause(param, self.pause ? 0 : 1)
                }
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
                if let param = self.param {
                    run_pause(param, 1)
                }
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
                if let param = self.param {
                    run_pause(param, 0)
                }
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
            self.onSeek(self.playPos + Double(truncating: interval))
            return .success
        }
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: skip_nextsec)]

        commandCenter.nextTrackCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            self.onSeekChapter(1)
            return .success
        }

        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            guard let command = event.command as? MPSkipIntervalCommand else {
                return .noSuchContent
            }
            let interval = command.preferredIntervals[0]
            self.onSeek(self.playPos - Double(truncating: interval))
            return .success
        }
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: skip_prevsec)]

        commandCenter.previousTrackCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            self.onSeekChapter(-1)
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self](remoteEvent) -> MPRemoteCommandHandlerStatus in
            guard let self = self else {return .commandFailed}
            if let event = remoteEvent as? MPChangePlaybackPositionCommandEvent {
                let pos = event.positionTime
                self.onSeek(pos)
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
                MPNowPlayingInfoPropertyElapsedPlaybackTime: playPos,
                MPMediaItemPropertyPlaybackDuration: mediaDuration,
            ]
        }
        else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyTitle: name,
                MPNowPlayingInfoPropertyPlaybackRate: pause ? 0.0: 1.0,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: playPos,
                MPMediaItemPropertyPlaybackDuration: mediaDuration,
            ]
        }
    }
    
    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
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
            if let param {
                run_pause(param, 1)
            }
            onSeek(playPos + skipInterval.seconds)
            if let param {
                run_pause(param, 0)
            }
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

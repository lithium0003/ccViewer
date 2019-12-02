//
//  CustomPlayerViewController.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/19.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit
import AVFoundation
import CoreServices
import AVKit
import MediaPlayer

import RemoteCloud

extension Notification.Name {
    static let avPlayerViewDisappear = Notification.Name("avPlayerViewDisappear")
}

extension AVPlayerViewController {
    override open func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.post(name: .avPlayerViewDisappear, object: self)
    }
    override open var shouldAutorotate: Bool {
        if UserDefaults.standard.bool(forKey: "MediaViewerRotation") {
            return false
        }
        return true
    }
    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UserDefaults.standard.bool(forKey: "ForceLandscape") {
            return .landscapeLeft
        }
        return .all
    }
}

class CustomPlayerView: NSObject, AVPlayerViewControllerDelegate {
    static var pipVideo = false

    let itemQueue = DispatchQueue(label: "playItemQueue")
    var playItems = [[String: Any]]()
    var playIndex = [Int]()
    var loop = false
    var shuffle = false
    var playtitle = ""
    var playURL: URL?
    var prevURL: URL?
    var onFinish: ((Double?)->Void)?
    var customDelegate = [URL: [CustomAVARLDelegate]]()
    var infoItems = [URL: [String: Any]]()
    var image: MPMediaItemArtwork?
    var queue = DispatchQueue(label: "load_items")
    var playCounts = [URL: Int]()
    
    func getURL(storage: String, fileId: String) -> URL {
        var allowedCharacterSet = CharacterSet.alphanumerics
        allowedCharacterSet.insert(charactersIn: "-._~")
        
        let s = storage.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet) ?? ""
        let f = fileId.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet) ?? ""
        let url = URL(string: "\(CustomAVARLDelegate.customKeyScheme)://\(s)/\(f)")
        return url!
    }
    
    func getAsset(url: URL) -> AVURLAsset {
        let asset = AVURLAsset(url: url)
        let newDelegate = CustomAVARLDelegate()
        if var prev = self.customDelegate[url] {
            prev += [newDelegate]
            self.customDelegate[url] = prev
        }
        else {
            self.customDelegate[url] = [newDelegate]
        }
        asset.resourceLoader.setDelegate(newDelegate, queue: queue)
        return asset
    }

    func PrepareAVPlayerItem(itemIndex: Int, needplay: Bool = false) {
        let item = playItems[itemIndex]
        let storage = item["storage"] as! String
        let id = item["id"] as! String
        let url = getURL(storage: storage, fileId: id)
        self.infoItems[url] = item
        let asset = getAsset(url: url)
        let playableKey = "playable"
        // Load the "playable" property
        asset.loadValuesAsynchronously(forKeys: [playableKey]) {
            var error: NSError? = nil
            let status = asset.statusOfValue(forKey: playableKey, error: &error)
            switch status {
            case .loaded:
                // Sucessfully loaded. Continue processing.
                let playitem = AVPlayerItem(asset: asset)
                self.itemQueue.async {
                    let pos: CMTime
                    if let lc = item["loadCount"] as? Int, lc > 0 {
                        self.playItems[itemIndex]["loadCount"] = lc + 1
                        let skip = UserDefaults.standard.integer(forKey: "playStartSkipSec")
                        let duration = UserDefaults.standard.integer(forKey: "playStopAfterSec")
                        if duration > 0 {
                            playitem.forwardPlaybackEndTime = CMTimeMakeWithSeconds(Double(skip+duration), preferredTimescale: Int32(NSEC_PER_SEC))
                        }
                        if skip > 0 {
                            pos = CMTimeMakeWithSeconds(Double(skip), preferredTimescale: Int32(NSEC_PER_SEC))
                            playitem.seek(to: pos) { finished in
                            }
                        }
                    }
                    else {
                        self.playItems[itemIndex]["loadCount"] = 1
                        if let stop = item["stop"] as? Double {
                            playitem.forwardPlaybackEndTime = CMTimeMakeWithSeconds(stop, preferredTimescale: Int32(NSEC_PER_SEC))
                        }
                        if let start = item["start"] as? Double {
                            pos = CMTimeMakeWithSeconds(start, preferredTimescale: Int32(NSEC_PER_SEC))
                            playitem.seek(to: pos) { finished in
                            }
                        }
                    }
                }
                let center = NotificationCenter.default
                center.addObserver(self, selector: #selector(self.newErrorLogEntry), name: .AVPlayerItemNewErrorLogEntry, object: playitem)
                center.addObserver(self, selector: #selector(self.failedToPlayToEndTime), name: .AVPlayerItemFailedToPlayToEndTime, object: playitem)
                center.addObserver(self, selector: #selector(self.didPlayToEndTime), name: .AVPlayerItemDidPlayToEndTime, object: playitem)

                DispatchQueue.main.async {
                    self.player.insert(playitem, after: nil)
                    if needplay {
                        self.player.play()
                    }
                }
                
                if self.playIndex.count > 0 {
                    self.enqueuePlayItem()
                }
                
            default:
                // Handle all other cases
                if let lc = item["loadCount"] as? Int, lc > 0 {
                    self.playItems[itemIndex]["loadCount"] = lc + 1
                }
                else {
                    self.playItems[itemIndex]["loadCount"] = 1
                }
            }
        }
    }
    
    lazy var player: AVQueuePlayer = {
        self.playIndex = Array(0..<self.playItems.count)
        if self.shuffle {
            self.playIndex.shuffle()
        }
        for item in self.playItems {
            let storage = item["storage"] as! String
            let id = item["id"] as! String
            let url = getURL(storage: storage, fileId: id)
            self.playCounts[url] = 0
        }
        var player = AVQueuePlayer()
        return player
    }()
    
    func enqueuePlayItem(needplay: Bool = false) {
        itemQueue.async {
            if let next = self.playIndex.first {
                self.PrepareAVPlayerItem(itemIndex: next, needplay: needplay)
                self.playIndex = Array(self.playIndex.dropFirst())
            }
            else if self.loop || UserDefaults.standard.bool(forKey: "keepOpenWhenDone") {
                self.playIndex = Array(0..<self.playItems.count)
                if self.shuffle {
                    self.playIndex.shuffle()
                }
                self.enqueuePlayItem()
            }
        }
    }
    
    lazy var playerViewController: AVPlayerViewController = {
        var viewController = AVPlayerViewController()
        viewController.delegate = self
        viewController.allowsPictureInPicturePlayback = !CustomPlayerView.pipVideo
        return viewController
    }()
    
    var iscancel = false
    var isVideo = false
    
    func setupRemoteTransportControls() {
        // Get the shared MPRemoteCommandCenter
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Add handler for Play Command
        commandCenter.playCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            if self.player.rate == 0.0 {
                self.player.play()
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.player.currentItem?.currentTime().seconds
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = self.player.currentItem?.asset.duration.seconds
                return .success
            }
            return .commandFailed
        }
        
        // Add handler for Pause Command
        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            if self.player.rate == 1.0 {
                self.player.pause()
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.player.currentItem?.currentTime().seconds
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = self.player.currentItem?.asset.duration.seconds
                return .success
            }
            return .commandFailed
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self](remoteEvent) -> MPRemoteCommandHandlerStatus in
            guard let self = self else {return .commandFailed}
            let playerRate = self.player.rate
            if let event = remoteEvent as? MPChangePlaybackPositionCommandEvent {
                self.player.seek(to: CMTime(seconds: event.positionTime, preferredTimescale: CMTimeScale(1000)), completionHandler: { [weak self](success) in
                    guard let self = self else {return}
                    if success {
                        self.player.rate = playerRate
                        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = event.positionTime
                        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = self.player.currentItem?.asset.duration.seconds
                    }
                })
                return .success
            }
            return .commandFailed
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            self.skipNextTrack()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] event in
            guard let self = self else {return .commandFailed}
            let playerRate = self.player.rate
            self.player.seek(to: CMTime.zero, completionHandler: { [weak self](success) in
                guard let self = self else {return}
                if success {
                    self.player.rate = playerRate
                    MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
                }
            })
            return .success
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [String: Any]()
    }
    
    func skipNextTrack() {
        let cururl = (self.player.currentItem?.asset as? AVURLAsset)?.url
        DispatchQueue.global().async {
            print("skipNextTrack ", self.playCounts)
            print(self.player.items())
            let url = self.prevURL
            self.player.pause()
            if self.player.items().count <= 2 {
                self.enqueuePlayItem()
            }
            if self.player.items().count <= 1 && (!self.loop && !UserDefaults.standard.bool(forKey: "keepOpenWhenDone")) {
                DispatchQueue.main.async {
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                    self.iscancel = true
                    self.playerViewController.dismiss(animated: false) {
                        self.finishRemoteTransportControls()
                        for items in self.customDelegate {
                            for delegate in items.value {
                                delegate.item?.cancel()
                                delegate.stream?.isLive = false
                            }
                        }
                        self.customDelegate.removeAll()
                        self.onFinish?(0)
                    }
                }
            }
            else {
                if let url = cururl {
                    self.playCounts[url] = self.playCounts[url]! + 1
                }
                self.player.advanceToNextItem()
                if let url = url, var prev = self.customDelegate[url] {
                    prev = Array(prev.dropFirst())
                    if prev.count > 0 {
                        self.customDelegate[url] = prev
                    }
                    else {
                        self.customDelegate.removeValue(forKey: url)
                    }
                }
                let c = self.playCounts.first?.value ?? 0
                if !self.loop && self.playCounts.values.allSatisfy({ $0 == c }) {
                    // stop
                }
                else {
                    self.player.play()
                }
            }
        }
    }
    
    func finishRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.stopCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
    }
    
    func setupNowPlaying() {
        if let newURL = (player.currentItem?.asset as? AVURLAsset)?.url, playURL != newURL {
            prevURL = playURL
            playURL = newURL
            
            guard let storage = self.infoItems[newURL]?["storage"] as? String else {
                return
            }
            guard let id = self.infoItems[newURL]?["id"] as? String else {
                return
            }
            
            let item = CloudFactory.shared[storage]?.get(fileId: id)
            
            // Define Now Playing Info
            playtitle = item?.name ?? ""
            
            var basename = item?.name ?? ""
            var parentId = item?.parent ?? ""
            if let subid = item?.subid, let subbase = CloudFactory.shared[storage]?.get(fileId: subid) {
                basename = subbase.name
                parentId = subbase.parent
            }
            var components = basename.components(separatedBy: ".")
            if components.count > 1 {
                components.removeLast()
                basename = components.joined(separator: ".")
            }
            
            
            if let imageitem = CloudFactory.shared.data.getImage(storage: storage, parentId: parentId, baseName: basename) {
                DispatchQueue.global().async {
                    if let imagestream = CloudFactory.shared[storage]?.get(fileId: imageitem.id ?? "")?.open() {
                        imagestream.read(position: 0, length: Int(imageitem.size)) { data in
                            if let data = data, let image = UIImage(data: data) {
                                self.image = MPMediaItemArtwork(boundsSize: image.size) { size in
                                    return image
                                }
                            }
                        }
                    }
                }
            }
            self.image = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
        }
    }
    
    func play(parent: UIViewController) {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(error)
        }

        playerViewController.player = player
        playerViewController.updatesNowPlayingInfoCenter = false
        
        player.addObserver(self, forKeyPath: #keyPath(AVPlayer.status), options: [.new, .initial], context: nil)
        player.addObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.status), options:[.new, .initial], context: nil)
        player.addObserver(self, forKeyPath: #keyPath(AVPlayer.timeControlStatus), options:[.new, .old], context: nil)
        player.addPeriodicTimeObserver(forInterval: CMTimeMake(value: 1, timescale: 1) , queue: DispatchQueue.global()) { [weak self] time in
            guard self?.player.timeControlStatus == .playing, time.seconds > 1.0 else {
                return
            }
            DispatchQueue.main.async {
                if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time.seconds
                    info[MPMediaItemPropertyPlaybackDuration] = self?.player.currentItem?.asset.duration.seconds
                    info[MPMediaItemPropertyArtwork] =
                        self?.image
                    info[MPMediaItemPropertyTitle] = self?.playtitle
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
                else {
                    var info = [String: Any]()
                    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time.seconds
                    info[MPMediaItemPropertyPlaybackDuration] = self?.player.currentItem?.asset.duration.seconds
                    info[MPMediaItemPropertyArtwork] =
                        self?.image
                    info[MPMediaItemPropertyTitle] = self?.playtitle
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }
        
        let center = NotificationCenter.default
        center.addObserver(forName: .avPlayerViewDisappear, object: playerViewController, queue: nil) { notification in
            print("PlayerViewDisappear")
            if !CustomPlayerView.pipVideo {
                self.finishDisplay()
            }
        }
        
        setupRemoteTransportControls()

        enqueuePlayItem(needplay: true)
        if loop || UserDefaults.standard.bool(forKey: "keepOpenWhenDone") {
            if self.playItems.count < 2 {
                enqueuePlayItem()
            }
        }
        parent.present(self.playerViewController, animated: true, completion: nil)
    }

    @objc func appMovedToForeground() {
        print("App moved to ForeGround!")
        if !CustomPlayerView.pipVideo && isVideo {
            playerViewController.player = player
        }
    }
    
    @objc func appMovedToBackground() {
        print("App moved to Background!")
        isVideo = player.currentItem?.asset.tracks(withMediaType: .video).count != 0
        if !CustomPlayerView.pipVideo && isVideo {
            playerViewController.player = nil
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        
        if let player = object as? AVPlayer, keyPath == #keyPath(AVPlayer.currentItem.status) {
            let newStatus: AVPlayerItem.Status
            if let newStatusAsNumber = change?[NSKeyValueChangeKey.newKey] as? NSNumber {
                newStatus = AVPlayerItem.Status(rawValue: newStatusAsNumber.intValue)!
            } else {
                newStatus = .unknown
            }
            if newStatus == .failed {
                NSLog("AVPlayer.currntItem Error: \(String(describing: player.currentItem?.error?.localizedDescription)), error: \(String(describing: player.currentItem?.error))")
                if let e = player.currentItem?.error as? AVError {
                    if e.code == .fileFormatNotRecognized {
                        nextTrack()
                    }
                }
            }
        }
        else if object as AnyObject? === player {
            if keyPath == "timeControlStatus", player.timeControlStatus == .playing {
                self.setupNowPlaying()
            }
        }
    }
    
    @objc func newErrorLogEntry(_ notification: Notification) {
        guard let object = notification.object, let playerItem = object as? AVPlayerItem else {
            return
        }
        guard let errorLog = playerItem.errorLog() else {
            return
        }
        
        NSLog("Error: \(errorLog)")
    }
    
    @objc func failedToPlayToEndTime(_ notification: Notification) {
        if let error = notification.userInfo!["AVPlayerItemFailedToPlayToEndTimeErrorKey"] as? Error {
            NSLog("failedToPlayToEndTime Error: \(error.localizedDescription), error: \(error)")
        }
    }

    func nextTrack() {
        let cururl = (self.player.currentItem?.asset as? AVURLAsset)?.url
        DispatchQueue.global().async {
            print("nextTrack ", self.playCounts)
            print(self.player.items())
            let url = self.prevURL
            if self.player.items().count <= 2 {
                self.enqueuePlayItem()
            }
            if self.player.items().count <= 1 && (!self.loop && !UserDefaults.standard.bool(forKey: "keepOpenWhenDone")) {
                DispatchQueue.main.async {
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                    self.iscancel = true
                    self.playerViewController.dismiss(animated: false) {
                        self.finishRemoteTransportControls()
                        for items in self.customDelegate {
                            for delegate in items.value {
                                delegate.item?.cancel()
                                delegate.stream?.isLive = false
                            }
                        }
                        self.customDelegate.removeAll()
                        self.onFinish?(0)
                    }
                }
            }
            else {
                if let url = cururl {
                    self.playCounts[url] = self.playCounts[url]! + 1
                }
                if let url = url, var prev = self.customDelegate[url] {
                    prev = Array(prev.dropFirst())
                    if prev.count > 0 {
                        self.customDelegate[url] = prev
                    }
                    else {
                        self.customDelegate.removeValue(forKey: url)
                    }
                }
                let c = self.playCounts.first?.value ?? 0
                if !self.loop && self.playCounts.values.allSatisfy({ $0 == c }) {
                    self.player.pause()
                }
            }
        }
    }
    
    @objc func didPlayToEndTime(_ notification: Notification) {
        print("didPlayToEndTime")
        nextTrack()
    }

    func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool {
        CustomPlayerView.pipVideo = true
        return true
    }
    
    func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        
        if let currentViewController = UIApplication.topViewController(), !iscancel {
            currentViewController.present(playerViewController, animated: true) {
                completionHandler(true)
            }
        }
        else {
            finishDisplay()
            completionHandler(true)
        }
    }
    
    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        CustomPlayerView.pipVideo = false
    }
        
    func finishDisplay() {
        var ret = 0.0
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            defer {
                group.leave()
            }
            if let len = self.playerViewController.player?.currentItem?.asset.duration.seconds,
                let pos = self.playerViewController.player?.currentTime().seconds,
                pos < len - 2 {
                ret = pos
            }
        }
        playerViewController.player?.pause()
        iscancel = true
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        playerViewController.dismiss(animated: true, completion: nil)
        finishRemoteTransportControls()
        for items in self.customDelegate {
            for delegate in items.value {
                delegate.item?.cancel()
                delegate.stream?.isLive = false
            }
        }
        self.customDelegate.removeAll()
        group.notify(queue: .global()) {
            DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                do {
                    try AVAudioSession.sharedInstance().setActive(false)
                } catch {
                    print(error)
                }
            }
            self.onFinish?(ret)
        }
    }
}

class CustomAVARLDelegate: NSObject, AVAssetResourceLoaderDelegate {
    static let customKeyScheme = "in-memory"
    
    var item: RemoteItem?
    var stream: RemoteStream?
    //var queue = DispatchQueue(label: "io_read", attributes: [.concurrent])
    var queue = DispatchQueue(label: "io_read")
    var retry = 0
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let scheme = loadingRequest.request.url?.scheme else {
            return false
        }
        if scheme == CustomAVARLDelegate.customKeyScheme {
            guard let storageName = loadingRequest.request.url?.host else {
                return false
            }
            guard let fileId = loadingRequest.request.url?.relativePath.dropFirst()  else {
                return false
            }
            if item == nil {
                item = CloudFactory.shared[storageName]?.get(fileId: String(fileId))
            }
            guard let item = self.item else {
                return false
            }
            if stream == nil {
                stream = item.open()
            }
            guard let request = loadingRequest.dataRequest else {
                return false
            }
            if let infoRequest = loadingRequest.contentInformationRequest {
                infoRequest.isByteRangeAccessSupported = true
                infoRequest.contentLength = stream!.size
                print((item.name, item.size))
                let ext = (item.ext == "") ? (item.name as NSString).pathExtension.lowercased() : item.ext
                print(ext)
                if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)?.takeRetainedValue() {
                    print(uti)
                    infoRequest.contentType = uti as String
                }
            }
            var startOffset = request.requestedOffset
            if request.currentOffset != 0 {
                startOffset = request.currentOffset
            }
            guard startOffset < stream!.size else {
                print("eof")
                loadingRequest.finishLoading()
                return true
            }
            let requestLength = request.requestedLength
            print("s\(startOffset) r\(requestLength)")
            guard self.stream!.isLive else {
                loadingRequest.finishLoading(with: URLError(URLError.Code.cannotOpenFile))
                return true
            }
            DispatchQueue.global().asyncAfter(deadline: .now()) {
                self.respondData(position: startOffset, length: requestLength, request: request, loadingRequest: loadingRequest)
            }
            return true
        }
        return false
    }
    
    func respondData(position: Int64, length: Int, request: AVAssetResourceLoadingDataRequest, loadingRequest: AVAssetResourceLoadingRequest) {
        if loadingRequest.isCancelled {
            loadingRequest.finishLoading(with: URLError(.cancelled))
            return
        }
        if position > 20*1024*1024 {
            self.stream?.preload(position: position, length: 60*1024*1024)
        }
        let maxlen = 1*1024*1024
        let len = (length > maxlen) ? maxlen : length
        self.stream?.read(position: position, length: len, onProgress: nil){ data in
            print("read s\(position) r\(len) d\(data?.count ?? -1)")
            self.queue.async {
                if let data = data {
                    request.respond(with: data)
                    if len == length, data.count == len {
                        loadingRequest.finishLoading()
                    }
                    else {
                       DispatchQueue.global().asyncAfter(deadline: .now()) {
                            self.respondData(position: position+Int64(data.count), length: length-data.count, request: request, loadingRequest: loadingRequest)
                        }
                    }
                }
                else {
                    self.retry += 1
                    if self.retry > 3 {
                        loadingRequest.finishLoading(with: URLError(.cannotOpenFile))
                    }
                    else {
                        DispatchQueue.global().asyncAfter(deadline: .now()) {
                            self.respondData(position: position, length: length, request: request, loadingRequest: loadingRequest)
                        }
                    }
                }
            }
        }
    }
}

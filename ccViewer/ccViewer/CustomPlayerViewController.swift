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

class CustomPlayerViewController: UIViewController, AVPlayerViewControllerDelegate {

    var playItems = [[String: Any]]()
    var loop = false
    var shuffle = false
    var playtitle = ""
    var playURL: URL?
    var prevURL: URL?
    var onFinish: ((Double?)->Void)?
    var customDelegate = [URL: [CustomAVARLDelegate]]()
    var infoItems = [URL: [String: Any]]()
    var image: MPMediaItemArtwork?
    
    func getURL(storage: String, fileId: String) -> URL {
        var allowedCharacterSet = CharacterSet.alphanumerics
        allowedCharacterSet.insert(charactersIn: "-._~")
        
        let s = storage.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet) ?? ""
        let f = fileId.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet) ?? ""
        let url = URL(string: "\(CustomAVARLDelegate.customKeyScheme)://\(s)/\(f)")
        return url!
    }
    
    func getPlayItem(url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        let newDelegate = CustomAVARLDelegate()
        if var prev = self.customDelegate[url] {
            prev += [newDelegate]
            self.customDelegate[url] = prev
        }
        else {
            self.customDelegate[url] = [newDelegate]
        }
        asset.resourceLoader.setDelegate(newDelegate, queue: newDelegate.queue)
        let playerItem = AVPlayerItem(asset: asset)
        return playerItem
    }

    lazy var player: AVQueuePlayer = {
        if self.loop && self.playItems.count <= 2 {
            self.playItems += self.playItems
        }
        if self.shuffle {
            self.playItems.shuffle()
        }
        let items = self.playItems.map({ (item: [String: Any])->AVPlayerItem in
            let storage = item["storage"] as! String
            let id = item["id"] as! String
            let url = getURL(storage: storage, fileId: id)
            let playitem = getPlayItem(url: url)
            self.infoItems[url] = item
            let pos: CMTime
            if let start = item["start"] as? Double {
                pos = CMTimeMakeWithSeconds(start, preferredTimescale: Int32(NSEC_PER_SEC))
                playitem.seek(to: pos) { finished in
                }
            }
            return playitem
        })
        var player = AVQueuePlayer(items: items)
        return player
    }()
    
    lazy var playerViewController: AVPlayerViewController = {
        var viewController = AVPlayerViewController()
        viewController.delegate = self
        return viewController
    }()
    
    var finish = false
    var iscancel = false
    var pipVideo = false
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
        let url = (player.currentItem?.asset as? AVURLAsset)?.url
        player.pause()
        if player.items().count <= 2 {
            if loop {
                loopSetup()
            }
        }
        if player.items().count <= 1 {
            DispatchQueue.main.async {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            }
            iscancel = true
            playerViewController.dismiss(animated: false) {
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
        else {
            player.advanceToNextItem()
            if let url = url, var prev = customDelegate[url] {
                prev = Array(prev.dropFirst())
                if prev.count > 0 {
                    customDelegate[url] = prev
                }
                else {
                    customDelegate.removeValue(forKey: url)
                }
            }
            player.play()
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
            self.image = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    
        setNeedsStatusBarAppearanceUpdate()
        playerViewController.player = player
        playerViewController.updatesNowPlayingInfoCenter = false
        
        player.addObserver(self, forKeyPath: #keyPath(AVPlayer.status), options: [.new, .initial], context: nil)
        player.addObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.status), options:[.new, .initial], context: nil)
        player.addObserver(self, forKeyPath: #keyPath(AVPlayer.timeControlStatus), options:[.new, .old], context: nil)
        player.addPeriodicTimeObserver(forInterval: CMTimeMake(value: 1, timescale: 1) , queue: DispatchQueue.main) { [weak self] time in
            guard self?.player.timeControlStatus == .playing, time.seconds > 1.0 else {
                return
            }
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
        
        let center = NotificationCenter.default
        for pitem in player.items() {
            center.addObserver(self, selector: #selector(newErrorLogEntry), name: .AVPlayerItemNewErrorLogEntry, object: pitem)
            center.addObserver(self, selector: #selector(failedToPlayToEndTime), name: .AVPlayerItemFailedToPlayToEndTime, object: pitem)
            center.addObserver(self, selector: #selector(didPlayToEndTime), name: .AVPlayerItemDidPlayToEndTime, object: pitem)
        }
        
        setupRemoteTransportControls()
    }

    @objc func appMovedToForeground() {
        print("App moved to ForeGround!")
        if !pipVideo && isVideo {
            playerViewController.player = player
        }
    }
    
    @objc func appMovedToBackground() {
        print("App moved to Background!")
        isVideo = player.currentItem?.asset.tracks(withMediaType: .video).count != 0
        if !pipVideo && isVideo {
            playerViewController.player = nil
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if finish && !pipVideo {
            finishDisplay()
        }
        else if !finish {
            present(playerViewController, animated: true) {
                self.playerViewController.player?.play()
                self.finish = true
            }
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

    func loopSetup() {
        if self.shuffle {
            self.playItems.shuffle()
        }
        let items = self.playItems.map({ (item: [String: Any])->AVPlayerItem in
            let storage = item["storage"] as! String
            let id = item["id"] as! String
            let url = getURL(storage: storage, fileId: id)
            let playitem = getPlayItem(url: url)
            let pos: CMTime
            if let start = item["start"] as? Double {
                pos = CMTimeMakeWithSeconds(start, preferredTimescale: Int32(NSEC_PER_SEC))
                playitem.seek(to: pos) { finished in
                }
            }
            return playitem
        })

        let center = NotificationCenter.default
        for item in items {
            center.addObserver(self, selector: #selector(newErrorLogEntry), name: .AVPlayerItemNewErrorLogEntry, object: item)
            center.addObserver(self, selector: #selector(failedToPlayToEndTime), name: .AVPlayerItemFailedToPlayToEndTime, object: item)
            center.addObserver(self, selector: #selector(didPlayToEndTime), name: .AVPlayerItemDidPlayToEndTime, object: item)
            player.insert(item, after: nil)
        }
    }
    
    func nextTrack() {
        let url = prevURL
        if player.items().count <= 2 {
            if loop {
                loopSetup()
            }
        }
        if player.items().count <= 1 {
            DispatchQueue.main.async {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            }
            iscancel = true
            playerViewController.dismiss(animated: false) {
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
        else {
            if let url = url, var prev = customDelegate[url] {
                prev = Array(prev.dropFirst())
                if prev.count > 0 {
                    customDelegate[url] = prev
                }
                else {
                    customDelegate.removeValue(forKey: url)
                }
            }
        }
    }
    
    @objc func didPlayToEndTime(_ notification: Notification) {
        print("didPlayToEndTime")
        nextTrack()
    }

    func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool {
        pipVideo = true
        return true
    }
    
    func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        let currentViewController = navigationController?.visibleViewController
        
        if currentViewController != playerViewController {
            if let topViewController = navigationController?.topViewController {
                topViewController.present(playerViewController, animated: true) {
                    self.pipVideo = false
                    completionHandler(true)
                }
            }
        }
    }
    
    func finishDisplay() {
        var ret = 0.0
        if let len = playerViewController.player?.currentItem?.asset.duration.seconds,
            let pos = playerViewController.player?.currentTime().seconds,
            pos < len - 2 {
            ret = pos
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
        self.onFinish?(ret)
    }
}

extension AVPlayerViewController {
    override open var shouldAutorotate: Bool {
        if UserDefaults.standard.bool(forKey: "MediaViewerRotation") {
            return false
        }
        return true
    }
    
    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UserDefaults.standard.bool(forKey: "MediaViewerRotation") {
            return .landscapeRight
        }
        return .all
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
        self.stream?.read(position: position, length: len) { data in
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

//
//  CastPlay.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/11/10.
//

import Foundation
import RemoteCloud
import ffconverter
import GoogleCast
internal import UniformTypeIdentifiers

class CastConverter: NSObject, GCKRemoteMediaClientListener {
    static let shared = CastConverter()
    private override init() {
        super.init()
    }

    actor Items {
        var loop: Bool {
            UserDefaults.standard.bool(forKey: "loop")
        }
        var shuffle: Bool {
            UserDefaults.standard.bool(forKey: "shuffle")
        }

        var items: [RemoteItem] = []
        var itemIDMap: [Int: String] = [:]
        var durations: [String: (Double, String, String, String)] = [:]
        var currentIdx = -1
        var currentItemID: Int = -1 {
            didSet {
                print("currentItemID change", currentItemID, oldValue)
                if currentItemID == oldValue {
                    return
                }
                if oldValue < 0 { return }
                for i in 0...oldValue {
                    if let path = itemIDMap[i] {
                        Task {
                            print("Convert done", i, path)
                            await Converter.Done(targetPath: path)
                        }
                    }
                }
            }
        }

        func setItemID(_ id: Int, path: String) {
            print("setItemID", id, path)
            itemIDMap[id] = path
        }
        
        func setCurrentItemID(_ id: Int) {
            print("setCurrentItemID", id)
            currentItemID = id
        }

        func playDone(url: URL, sec: Double) async {
            let randID = url.deletingLastPathComponent().lastPathComponent
            let duration: Double
            let storage: String
            let id: String
            let parent: String
            if let (duration1, storage1, id1, parent1) = durations[randID] {
                duration = duration1
                storage = storage1
                id = id1
                parent = parent1
            }
            else if let item = await Converter.baseItem(randID: randID) {
                let duration1 = await Converter.duration(randID: randID)
                duration = duration1
                storage = item.storage
                id = item.id
                parent = item.parent
                if duration > 0 {
                    durations[randID] = (duration, storage, id, parent)
                }
            }
            else {
                return
            }
            if duration > 0, await !CastConverter.shared.playlist {
                print("set sec", sec, duration, sec / duration)
                await CloudFactory.shared.mark.setMark(storage: storage, targetID: id, parentID: parent, position: sec / duration)
            }
        }
        
        func finish() async {
            for item in items {
                await Converter.Done(targetPath: item.path)
            }
            items.removeAll()
            itemIDMap.removeAll()
        }
        
        func nextItem() -> (Int, RemoteItem)? {
            if currentIdx + 1 < items.count {
                currentIdx += 1
            }
            else {
                if loop {
                    if shuffle {
                        items.shuffle()
                    }
                    currentIdx = 0
                }
                else {
                    return nil
                }
            }
            return (currentIdx, items[currentIdx])
        }
        
        func setItems(_ items: [RemoteItem]) {
            self.items = items
            currentIdx = -1
        }
    }
    var prop = Items()
    var waiting: Int64 = 0

    var timer: Timer?
    var playlist = false
    
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaMetadata: GCKMediaMetadata?) {
        if let itemID = mediaMetadata?.integer(forKey: kGCKMetadataKeyQueueItemID) {
            print("itemID", itemID)
            Task {
                await prop.setCurrentItemID(itemID)
            }
        }
        if mediaMetadata == nil {
            Task {
                await prop.setCurrentItemID(-1)
            }
            print("queue next item immidiaetly")
            Task {
                await playNext(true)
            }
        }
        else {
            if waiting < 1 {
                OSAtomicIncrement64(&waiting)
                print("queue next item")
                Task {
                    await playNext()
                }
            }
        }
    }
    
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        if mediaStatus?.nextQueueItem == nil {
            myButton.isEnabled = false
        }
        else {
            myButton.isEnabled = true
        }
        if let url = mediaStatus?.mediaInformation?.contentURL, let sec = mediaStatus?.streamPosition, sec > 0 {
            Task {
                await prop.playDone(url: url, sec: sec)
            }
            if waiting < 1, mediaStatus?.nextQueueItem == nil || mediaStatus?.currentQueueItem == nil {
                OSAtomicIncrement64(&waiting)
                print("queue next item")
                Task {
                    await playNext()
                }
            }
        }
    }
    
    @objc
    func didTapMyButton() {
        let castContext = GCKCastContext.sharedInstance()
        if castContext.castState == .connected || castContext.castState == .connecting {
            if let remoteClient = castContext.sessionManager.currentSession?.remoteMediaClient {
                if let next = remoteClient.mediaStatus?.nextQueueItem {
                    remoteClient.queueJumpToItem(withID: next.itemID, playPosition: 0, customData: nil)
                }
                else {
                    myButton.isEnabled = false
                }
            }
        }
    }
    
    lazy var myButton = {
        let myButton = UIButton()
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24.0, weight: .regular, scale: .default)
        myButton.setImage(UIImage(systemName: "forward.end.fill", withConfiguration: symbolConfiguration), for: .normal)
        myButton.addTarget(self, action: #selector(didTapMyButton), for: .touchUpInside)
        return myButton
    }()
    
    @MainActor
    func addNextButton() async {
        let castContext = GCKCastContext.sharedInstance()
        let expandedController = castContext.defaultExpandedMediaControlsViewController
        expandedController.setButtonType(.custom, at: 3)
        expandedController.setCustomButton(myButton, at: 3)
    }
    
    @MainActor
    func showController() async {
        let castContext = GCKCastContext.sharedInstance()
        castContext.presentDefaultExpandedMediaControls()
    }
    
    @concurrent
    func playNext(_ immidiate: Bool = false) async {
        await addNextButton()
        Task { @MainActor in
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                    let castContext = GCKCastContext.sharedInstance()
                    if castContext.castState == .connected || castContext.castState == .connecting {
                        return
                    }
                    Task {
                        await self?.prop.finish()
                    }
                    self?.timer?.invalidate()
                    self?.timer = nil
                }
            }
        }
        guard let (index, item) = await prop.nextItem() else {
            Task { @MainActor in
                OSAtomicDecrement64(&waiting)
            }
            return
        }
        let info = ConvertIteminfo(item: item)
        let skip = UserDefaults.standard.integer(forKey: "playStartSkipSec")
        let stop = UserDefaults.standard.integer(forKey: "playStopAfterSec")
        if skip > 0 {
            info.startpos = Double(skip)
        }
        if stop > 0 {
            info.playduration = Double(stop)
        }
        print(item.path)
        if let url = await Converter.Play(item: info) {
            let randID = url.deletingLastPathComponent().lastPathComponent
            await prop.setItemID(index, path: item.path)
            if await Converter.start_encode(randID: randID) {
                var sleepCount = 0
                while Converter.IsCasting(), await !Converter.fileReady(randID: randID), await Converter.runState(randID: randID) {
                    try? await Task.sleep(for: .milliseconds(100))
                    sleepCount += 1
                    print("sleep \(sleepCount)")
                }
            }
            if await !Converter.runState(randID: randID) {
                print("Convert failed.")
                await playNext()
                return
            }

            let metadata = GCKMediaMetadata()
            metadata.setString(item.name, forKey: kGCKMetadataKeyTitle)
            metadata.setInteger(index, forKey: kGCKMetadataKeyQueueItemID)
            let mediaInfoBuilder = GCKMediaInformationBuilder(contentURL: url)
            mediaInfoBuilder.hlsSegmentFormat = .TS
            mediaInfoBuilder.contentType = "application/vnd.apple.mpegurl"
            mediaInfoBuilder.metadata = metadata
            let itemBuilder = GCKMediaQueueItemBuilder()
            itemBuilder.mediaInformation = mediaInfoBuilder.build()
            itemBuilder.startTime = 0
            itemBuilder.autoplay = true
            let newItem = itemBuilder.build()
            if await prop.currentIdx != 0 {
                let castContext = GCKCastContext.sharedInstance()
                if let client = castContext.sessionManager.currentCastSession?.remoteMediaClient {
                    if immidiate {
                        let request = GCKMediaLoadRequestDataBuilder()
                        let queue = GCKMediaQueueDataBuilder(queueType: .generic)
                        queue.items = [newItem]
                        request.queueData = queue.build()
                        request.startTime = 0
                        client.loadMedia(with: request.build())
                    }
                    else {
                        client.queueInsert(newItem, beforeItemWithID: kGCKMediaQueueInvalidItemID)
                    }
                }
                Task { @MainActor in
                    myButton.isEnabled = true
                }
            }
            else {
                let request = GCKMediaLoadRequestDataBuilder()
                let queue = GCKMediaQueueDataBuilder(queueType: .generic)
                queue.items = [newItem]
                request.queueData = queue.build()
                request.startTime = 0
                let castContext = GCKCastContext.sharedInstance()
                if let client = castContext.sessionManager.currentCastSession?.remoteMediaClient {
                    client.loadMedia(with: request.build())
                }
                Task { @MainActor in
                    myButton.isEnabled = false
                }
            }

            let castContext = GCKCastContext.sharedInstance()
            if Converter.IsCasting(), castContext.castState == .connected || castContext.castState == .connecting {
                await showController()
            }
        }
        Task { @MainActor in
            OSAtomicDecrement64(&waiting)
        }
    }
}

func playConverter(storages: [String], fileids: [String], playlist: Bool = false) async {
    var shuffle: Bool {
        UserDefaults.standard.bool(forKey: "shuffle")
    }
    var items: [RemoteItem] = []
    for (storage, fileid) in zip(storages, fileids) {
        if let remoteItem = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fileid) {
            if let uti = UTType(filenameExtension: remoteItem.ext), uti.conforms(to: .text) {
            }
            else if let uti = UTType(filenameExtension: remoteItem.ext), uti.conforms(to: .image) {
            }
            else if let uti = UTType(filenameExtension: remoteItem.ext), uti.conforms(to: .pdf) {
            }
            else if remoteItem.ext == "cue" {
            }
            else {
                items.append(remoteItem)
            }
        }
    }
    if items.isEmpty { return }
    if shuffle {
        items.shuffle()
    }
    CastConverter.shared.playlist = playlist
    let castContext = GCKCastContext.sharedInstance()
    if castContext.castState == .connected || castContext.castState == .connecting {
        if let remoteClient = castContext.sessionManager.currentSession?.remoteMediaClient, remoteClient.mediaStatus?.queueItemCount ?? 0 == 0 {
            await CastConverter.shared.prop.setItems(items)
            remoteClient.add(CastConverter.shared)
            OSAtomicIncrement64(&CastConverter.shared.waiting)
            await CastConverter.shared.playNext()
        }
    }
}

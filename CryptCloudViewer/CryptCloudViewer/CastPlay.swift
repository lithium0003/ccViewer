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
        var durations: [String: (Double, String, String, String)] = [:]
        var currentIdx = -1

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
            if duration > 0 {
                print("set sec", sec, duration, sec / duration)
                await CloudFactory.shared.data.setMark(storage: storage, targetID: id, parentID: parent, position: sec / duration)
            }
        }
        
        func done() async {
            if currentIdx < 1 { return }
            for i in 0..<currentIdx {
                await Converter.Done(targetPath: items[i].path)
            }
        }
        
        func finish() async {
            for item in items {
                await Converter.Done(targetPath: item.path)
            }
            items.removeAll()
        }
        
        func nextItem() -> RemoteItem? {
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
            return items[currentIdx]
        }
        
        func setItems(_ items: [RemoteItem]) {
            self.items = items
            currentIdx = -1
        }
    }
    var prop = Items()
    var waiting = false

    var timer: Timer?
    
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        if let url = mediaStatus?.mediaInformation?.contentURL, let sec = mediaStatus?.streamPosition, sec > 0 {
            Task {
                await prop.playDone(url: url, sec: sec)
            }
            if !waiting, mediaStatus?.nextQueueItem == nil {
                print("queue has not next item")
                waiting = true
                Task {
                    await playNext(client)
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
                    Task {
                        await prop.done()
                        await removeNextButton()
                    }
                }
            }
        }
    }
    
    @MainActor
    func addNextButton() async {
        let castContext = GCKCastContext.sharedInstance()
        let expandedController = castContext.defaultExpandedMediaControlsViewController
        let myButton = UIButton()
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24.0, weight: .regular, scale: .default)
        myButton.setImage(UIImage(systemName: "forward.end.fill", withConfiguration: symbolConfiguration), for: .normal)
        myButton.addTarget(self, action: #selector(didTapMyButton), for: .touchUpInside)
        expandedController.setButtonType(.custom, at: 3)
        expandedController.setCustomButton(myButton, at: 3)
    }
    
    @MainActor
    func removeNextButton() async {
        let castContext = GCKCastContext.sharedInstance()
        let expandedController = castContext.defaultExpandedMediaControlsViewController
        expandedController.setButtonType(.none, at: 3)
    }
    
    @MainActor
    func showController() async {
        let castContext = GCKCastContext.sharedInstance()
        castContext.presentDefaultExpandedMediaControls()
    }
    
    @concurrent
    func playNext(_ client: GCKRemoteMediaClient) async {
        defer {
            Task { @MainActor in
                waiting = false
            }
        }
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
        guard let item = await prop.nextItem() else {
            return
        }
        let info = ConvertIteminfo(item: item)
        print(item.path)
        if let url = await Converter.Play(item: info) {
            let randID = url.deletingLastPathComponent().lastPathComponent
            if await Converter.start_encode(randID: randID) {
                var sleepCount = 0
                while Converter.IsCasting(), await !Converter.fileReady(randID: randID) {
                    try? await Task.sleep(for: .seconds(1))
                    sleepCount += 1
                    print("sleep \(sleepCount)")
                }
                try? await Task.sleep(for: .seconds(1))
            }

            let metadata = GCKMediaMetadata()
            metadata.setString(item.name, forKey: kGCKMetadataKeyTitle)
            let mediaInfoBuilder = GCKMediaInformationBuilder(contentURL: url)
            mediaInfoBuilder.streamDuration = .infinity
            mediaInfoBuilder.hlsSegmentFormat = .TS
            mediaInfoBuilder.streamType = .live
            mediaInfoBuilder.contentType = "application/vnd.apple.mpegurl"
            mediaInfoBuilder.metadata = metadata
            let itemBuilder = GCKMediaQueueItemBuilder()
            itemBuilder.mediaInformation = mediaInfoBuilder.build()
            itemBuilder.startTime = 0
            itemBuilder.preloadTime = 0
            itemBuilder.autoplay = true
            if await prop.currentIdx != 0 {
                client.queueInsert(itemBuilder.build(), beforeItemWithID: kGCKMediaQueueInvalidItemID)
                await addNextButton()
            }
            else {
                let request = GCKMediaLoadRequestDataBuilder()
                let queue = GCKMediaQueueDataBuilder(queueType: .generic)
                queue.items = [itemBuilder.build()]
                queue.startTime = 0
                request.queueData = queue.build()
                client.loadMedia(with: request.build())
                await removeNextButton()
            }

            try? await Task.sleep(for: .seconds(2))
            if Converter.IsCasting() {
                await showController()
            }
        }
    }
}

func playConverter(storages: [String], fileids: [String]) async {
    var shuffle: Bool {
        UserDefaults.standard.bool(forKey: "shuffle")
    }
    var items: [RemoteItem] = []
    for (storage, fileid) in zip(storages, fileids) {
        if let remoteItem = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fileid) {
            if remoteItem.ext == "txt" {
            }
            else if OpenfileUIView.pict_exts.contains(remoteItem.ext) {
            }
            else if remoteItem.ext == "pdf" {
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
    let castContext = GCKCastContext.sharedInstance()
    if castContext.castState == .connected || castContext.castState == .connecting {
        if let remoteClient = castContext.sessionManager.currentSession?.remoteMediaClient, remoteClient.mediaStatus?.queueItemCount ?? 0 == 0 {
            await CastConverter.shared.prop.setItems(items)
            remoteClient.add(CastConverter.shared)
            CastConverter.shared.waiting = true
            await CastConverter.shared.playNext(remoteClient)
        }
    }
}

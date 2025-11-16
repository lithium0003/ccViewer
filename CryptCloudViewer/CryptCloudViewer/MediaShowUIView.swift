//
//  MediaShowUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/20.
//

import SwiftUI
import RemoteCloud
import AVKit
import Combine
import MediaPlayer
import ffplayer

class CustomAVARLDelegate: NSObject, AVAssetResourceLoaderDelegate {
    static let customKeyScheme = "in-memory"
    
    var item: RemoteItem?
    var stream: RemoteStream?
    
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
            guard let request = loadingRequest.dataRequest else {
                return false
            }
            Task {
                if item == nil {
                    item = await CloudFactory.shared.storageList.get(storageName)?.get(fileId: String(fileId))
                }
                guard let item = self.item else {
                    loadingRequest.finishLoading(with: URLError(URLError.Code.cannotOpenFile))
                    return
                }
                if stream == nil {
                    stream = await item.open()
                }
                if let infoRequest = loadingRequest.contentInformationRequest {
                    infoRequest.isByteRangeAccessSupported = true
                    infoRequest.contentLength = stream!.size
                    print((item.name, item.size))
                    let ext = (item.ext == "") ? (item.name as NSString).pathExtension.lowercased() : item.ext
                    print(ext)
                    if let type = UTType(filenameExtension: ext) {
                        infoRequest.contentType = type.identifier
                    }
                }
                var startOffset = request.requestedOffset
                if request.currentOffset != 0 {
                    startOffset = request.currentOffset
                }
                guard startOffset < stream!.size else {
                    print("eof")
                    loadingRequest.finishLoading()
                    return
                }
                let requestLength = request.requestedLength
                //print("s\(startOffset) r\(requestLength)")
                guard self.stream!.isLive else {
                    loadingRequest.finishLoading(with: URLError(URLError.Code.cannotOpenFile))
                    return
                }
                await respondData(position: startOffset, length: requestLength, request: request, loadingRequest: loadingRequest)
            }
            return true
        }
        return false
    }
    
    func respondData(position: Int64, length: Int, request: AVAssetResourceLoadingDataRequest, loadingRequest: AVAssetResourceLoadingRequest) async {
        if loadingRequest.isCancelled {
            loadingRequest.finishLoading(with: URLError(.cancelled))
            return
        }
        let maxlen = 2*1024*1024
        let len = (length > maxlen) ? maxlen : length
        let data = try? await stream?.read(position: position, length: len, onProgress: nil)
        //print("read s\(position) r\(len) d\(data?.count ?? -1)")
        if let data = data {
            request.respond(with: data)
            if len == length, data.count == len {
                loadingRequest.finishLoading()
            }
            else {
                await respondData(position: position+Int64(data.count), length: length-data.count, request: request, loadingRequest: loadingRequest)
            }
        }
        else {
            loadingRequest.finishLoading(with: URLError(.cannotOpenFile))
        }
    }
}

class CustomPlayer: NSObject {
    lazy var player: AVQueuePlayer = {
        let player = AVQueuePlayer()
        player.automaticallyWaitsToMinimizeStalling = true
        return player
    }()
    let queue = DispatchQueue(label: "load_items")
    var playItems = [[String: Any]]() {
        didSet {
            playIndex = Array(0..<playItems.count)
            if shuffle {
                playIndex.shuffle()
            }
        }
    }
    var playIndex = [Int]()
    var loop: Bool {
        UserDefaults.standard.bool(forKey: "loop")
    }
    var shuffle: Bool {
        UserDefaults.standard.bool(forKey: "shuffle")
    }
    var customDelegate = [URL: [CustomAVARLDelegate]]()
    var infoItems = [URL: [String: Any]]()
    
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
        if var prev = customDelegate[url] {
            prev += [newDelegate]
            customDelegate[url] = prev
        }
        else {
            customDelegate[url] = [newDelegate]
        }
        asset.resourceLoader.setDelegate(newDelegate, queue: queue)
        return asset
    }
    
    func PrepareAVPlayerItem(itemIndex: Int) async {
        let item = playItems[itemIndex]
        let storage = item["storage"] as! String
        let id = item["id"] as! String
        let url = getURL(storage: storage, fileId: id)
        infoItems[url] = item
        let asset = getAsset(url: url)
        // Load the "playable" property
        let remoteItem = await CloudFactory.shared.storageList.get(storage)?.get(fileId: id)
        do {
            if try await asset.load(.isPlayable) {
                let status = asset.status(of: .isPlayable)
                switch status {
                case .loaded:
                    // Sucessfully loaded. Continue processing.
                    let playitem = AVPlayerItem(asset: asset)
                    if let remoteItem {
                        let titleItem =  AVMutableMetadataItem()
                        titleItem.identifier = AVMetadataIdentifier.commonIdentifierTitle
                        titleItem.value = remoteItem.name as any NSCopying & NSObjectProtocol
                        playitem.externalMetadata.append(titleItem)
                        if let image = await getArtimage(item: remoteItem), let data = image.jpegData(compressionQuality: 1.0) {
                            let artItem = AVMutableMetadataItem()
                            artItem.identifier = AVMetadataIdentifier.commonIdentifierArtwork
                            artItem.value = data as NSData
                            artItem.dataType = kCMMetadataBaseDataType_JPEG as String
                            playitem.externalMetadata.append(artItem)
                        }
                    }
                    
                    NotificationCenter.default.addObserver(self, selector: #selector(didPlayToEndTime), name: .AVPlayerItemDidPlayToEndTime, object: playitem)
                    
                    let start = player.currentItem == nil
                    player.insert(playitem, after: nil)
                    if start {
                        player.play()
                    }
                    
                default:
                    // Handle all other cases
                    break
                }
            }
        }
        catch {
            print(error)
        }
    }
    
    @objc func didPlayToEndTime(_ notification: Notification) {
        print("didPlayToEndTime")
        if let asset = player.currentItem?.asset as? AVURLAsset, let delegate = customDelegate[asset.url]?.last, let item = delegate.item {
            Task {
                await CloudFactory.shared.mark.setMark(storage: item.storage, targetID: item.id, parentID: item.parent, position: 1.0)
            }
        }
        if player.items().count == 1, loop {
            playIndex = Array(0..<playItems.count)
            if shuffle {
                playIndex.shuffle()
            }
            Task {
                await enqueuePlayItem()
            }
        }
    }

    func enqueuePlayItem() async {
        while let next = playIndex.first {
            await PrepareAVPlayerItem(itemIndex: next)
            playIndex = Array(playIndex.dropFirst())
        }
    }
    
    func finish() async {
        player.pause()
        for items in customDelegate {
            for delegate in items.value {
                await delegate.item?.cancel()
                delegate.stream?.isLive = false
            }
        }
    }

    func getArtimage(item: RemoteItem) async -> UIImage? {
        var basename = item.name
        var parentId = item.parent
        if let subid = item.subid, let subbase = await CloudFactory.shared.storageList.get(item.storage)?.get(fileId: subid) {
            basename = subbase.name
            parentId = subbase.parent
        }
        var components = basename.components(separatedBy: ".")
        if components.count > 1 {
            components.removeLast()
            basename = components.joined(separator: ".")
        }
        
        if let imageitem = await CloudFactory.shared.data.getImage(storage: item.storage, parentId: parentId, baseName: basename) {
            if let imagestream = await CloudFactory.shared.storageList.get(item.storage)?.get(fileId: imageitem.id ?? "")?.open() {
                let data = try? await imagestream.read()
                if let data = data, let image = UIImage(data: data) {
                    return image
                }
            }
        }
        return nil
    }
}

struct VideoPlayerView: UIViewControllerRepresentable {
    typealias UIViewControllerType = AVPlayerViewController
    let player: AVPlayer

    func makeUIViewController(context: Context) -> UIViewControllerType {
        let view = UIViewControllerType()
        return view
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        uiViewController.player = player
        uiViewController.allowsPictureInPicturePlayback = true
        uiViewController.delegate = PlayerManager.shared
        PlayerManager.shared.playerViewController = uiViewController
    }
}

class TouchTestUIView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        PlayerManager.shared.touchUpdate.send(Date())
        return nil
    }
}

struct TouchTestView: UIViewRepresentable {
    typealias UIViewType = TouchTestUIView

    func makeUIView(context: Context) -> UIViewType {
        UIViewType()
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
    }
}

class PlayerManager: NSObject, AVPlayerViewControllerDelegate {
    public static var shared = PlayerManager()
    private override init() {
        super.init()
    }
    
    var player: CustomPlayer? {
        didSet {
            Task {
                await oldValue?.finish()
            }
            if player != nil {
                UIApplication.shared.beginReceivingRemoteControlEvents()
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback)
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print(error)
                }
            }
            else {
                try? AVAudioSession.sharedInstance().setActive(false)
                UIApplication.shared.endReceivingRemoteControlEvents()
            }
            playerViewController?.allowsPictureInPicturePlayback = false
            playerViewController?.player?.pause()
            playerViewController = nil
            playerUpdate.send(player?.player)
        }
    }

    var playerViewController: AVPlayerViewController?
    var isPip = false
    var isGone = false
    
    func finish() async {
        player = nil
        isPip = false
        isGone = false
    }
    
    let playerUpdate = PassthroughSubject<AVPlayer?, Never>()
    let touchUpdate = PassthroughSubject<Date, Never>()
    
    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        isPip = true
        PiPManager.shared.isActive = true
        PiPManager.shared.stopCallback = { [weak self] in
            self?.playerViewController?.player?.pause()
            Task { await self?.finish() }
        }
    }
    
    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        isPip = false
        PiPManager.shared.isActive = false
        if isGone {
            playerViewController.player?.pause()
            Task { await finish() }
        }
    }
}

struct MediaShowUIView: View {
    let storages: [String]
    let fileids: [String]
    @State var isLoading = false
    @Environment(\.dismiss) private var dismiss
    @State var player: AVPlayer? = nil
    @State var cancellables: Set<AnyCancellable> = []
    @State var isTouched = false
    @State var rotateLock = false
    @State var lastTouched = Date()

    var body: some View {
        ZStack {
            if let player {
                VideoPlayerView(player: player)
                    .ignoresSafeArea()
            }
            TouchTestView()
            
            VStack {
                Color.clear
                    .frame(height: 50)
                    .onTapGesture {
                    }
                HStack {
                    if isTouched {
                        Button {
                            if !PlayerManager.shared.isPip {
                                Task {
                                    await PlayerManager.shared.finish()
                                }
                            }
                            PlayerManager.shared.isGone = true
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.title)
                                .tint(.white)
                        }
                        .buttonStyle(.glass)
                    }
                    Spacer()
                    if isTouched, UIDevice.current.userInterfaceIdiom == .phone {
                        Button {
                            rotateLock.toggle()
                            if rotateLock {
                                OrientationManager.lock()
                            }
                            else {
                                OrientationManager.unlock()
                            }
                        } label: {
                            if rotateLock {
                                Image(systemName: "rectangle.landscape.rotate")
                            }
                            else {
                                Image(systemName: "rectangle.landscape.rotate.slash")
                            }
                        }
                        .buttonStyle(.glass)
                    }
                }
                Spacer()
            }

            if isLoading {
                ProgressView()
                    .padding(30)
                    .background {
                        Color.black
                            .opacity(0.9)
                    }
                    .scaleEffect(3)
                    .cornerRadius(10)
            }
        }
        .toolbarVisibility(.hidden, for: .automatic)
        .task {
            isLoading = true
            defer {
                isLoading = false
            }
            PiPManager.shared.stopCallback?()
            PiPManager.shared.stopCallback = nil
            try? await Task.sleep(for: .milliseconds(500))

            PlayerManager.shared.playerUpdate
                .sink { p in
                    player = p
                }
                .store(in: &cancellables)

            PlayerManager.shared.touchUpdate
                .sink { t in
                    withAnimation {
                        isTouched = true
                    }
                    lastTouched = t
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        if lastTouched.addingTimeInterval(3) < Date() {
                            isTouched = false
                        }
                    }
                }
                .store(in: &cancellables)

            let newplayer = CustomPlayer()
            var items: [[String: Any]] = []
            for (storage, fileid) in zip(storages, fileids) {
                items.append(["storage": storage, "id": fileid])
            }
            newplayer.playItems = items
            PlayerManager.shared.player = newplayer
            await Task.yield()

            await newplayer.enqueuePlayItem()
        }
    }
}

#Preview {
    MediaShowUIView(storages: ["Local"], fileids: [""])
}

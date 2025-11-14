//
//  ImageShowUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/19.
//

import SwiftUI
import RemoteCloud

struct ImageShowUIView: View {
    let storage: String
    let fileid: String
    @State var remoteItem: RemoteItem?
    @State var image: UIImage?
    @State var isLoading = false
    @State var images: [UIImage] = []
    @State var imageIdx = -1
    @State var totalImages = 0
    var titleStr: String {
        if totalImages > 1 {
            if totalImages > images.count {
                return "\(imageIdx + 1) / \(images.count) loading... \(totalImages - images.count)"
            }
            else {
                return "\(imageIdx + 1) / \(images.count)"
            }
        }
        return ""
    }
    
    @State private var currentZoom = 1.0
    @State private var totalZoom = 1.0
    @State private var minZoom = 1.0
    @State private var position = ScrollPosition(id: 0, anchor: .center)
    @State private var offset: CGPoint = .zero
    @State private var transOffset: CGPoint?
    @State private var currentOffset: CGPoint = .zero
    @State private var hideHeader = false
    @State private var loadingTask: Task<Void, Error>?

    struct OffsetPreferenceKey: PreferenceKey {
        static var defaultValue = CGFloat.zero
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value += nextValue()
        }
    }
    
    @ViewBuilder
    var imageView: some View {
        if let image {
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .id(0)
                        .scaleEffect(currentZoom * totalZoom)
                        .frame(width: image.size.width * (currentZoom * totalZoom), height: image.size.height * (currentZoom * totalZoom))
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    if transOffset == nil {
                                        currentOffset = value.startLocation
                                        let offsetAnchor = CGPoint(x: value.startLocation.x - offset.x, y: value.startLocation.y - offset.y)
                                        transOffset = offsetAnchor
                                    }
                                    currentZoom = max(minZoom / totalZoom, value.magnification)
                                    position.scrollTo(x: currentOffset.x * (currentZoom * totalZoom) / totalZoom - transOffset!.x, y: currentOffset.y * (currentZoom * totalZoom) / totalZoom - transOffset!.y)
                                }
                                .onEnded { value in
                                    totalZoom *= currentZoom
                                    currentZoom = 1
                                    transOffset = nil
                                }
                        )
                        .accessibilityZoomAction { action in
                            if action.direction == .zoomIn {
                                totalZoom += 1
                            } else {
                                totalZoom -= 1
                            }
                        }
                        .onTapGesture(count: 2) { location in
                            let offsetAnchor = CGPoint(x: location.x - offset.x, y: location.y - offset.y)
                            let anchor = CGPoint(x: location.x / (currentZoom * totalZoom), y: location.y / (currentZoom * totalZoom))
                            totalZoom *= 1.5
                            let newpos = CGPoint(x: anchor.x * (currentZoom * totalZoom), y: anchor.y * (currentZoom * totalZoom))
                            if totalZoom > 5 {
                                totalZoom = minZoom
                            }
                            position.scrollTo(x: newpos.x - offsetAnchor.x, y: newpos.y - offsetAnchor.y)
                        }
                        .onTapGesture(count: 1) {
                            hideHeader.toggle()
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGPoint.self) { geometry in
                    geometry.contentOffset
                } action: { oldValue, newValue in
                    offset = newValue
                }
                .onTapGesture(count: 3) {
                    totalZoom = minZoom
                    position.scrollTo(id: 0, anchor: .center)
                }
                .onAppear {
                    minZoom = min(geo.size.width / image.size.width, geo.size.height / image.size.height)
                    totalZoom = minZoom
                }
                .onChange(of: image) {
                    minZoom = min(geo.size.width / image.size.width, geo.size.height / image.size.height)
                    totalZoom = minZoom
                    offset = .zero
                }
                .onChange(of: geo.size) {
                    minZoom = min(geo.size.width / image.size.width, geo.size.height / image.size.height)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            if totalZoom == minZoom, abs(value.translation.height) > 10 {
                                if value.translation.height > 0 {
                                    if imageIdx - 1 >= 0, imageIdx - 1 < images.count {
                                        imageIdx -= 1
                                        self.image = images[imageIdx]
                                    }
                                }
                                else {
                                    if imageIdx + 1 < images.count {
                                        imageIdx += 1
                                        self.image = images[imageIdx]
                                    }
                                }
                            }
                        }
                )
            }
        }
        else {
            Color.clear
        }
    }
    
    var body: some View {
        ZStack {
            imageView
                .ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .padding(30)
                    .background {
                        Color(uiColor: .systemBackground)
                            .opacity(0.9)
                    }
                    .scaleEffect(3)
                    .cornerRadius(10)
            }
        }
        .toolbar {
            if images.count > 1 {
                ToolbarItem {
                    Button {
                        if imageIdx - 1 >= 0, imageIdx - 1 < images.count {
                            imageIdx -= 1
                            image = images[imageIdx]
                        }
                    } label: {
                        Image(systemName: "arrowtriangle.backward")
                    }
                }
                ToolbarItem {
                    Button {
                        if imageIdx + 1 < images.count {
                            imageIdx += 1
                            image = images[imageIdx]
                        }
                    } label: {
                        Image(systemName: "arrowtriangle.forward")
                    }
                }
            }
        }
        .navigationTitle(titleStr)
        .toolbarVisibility(hideHeader ? .hidden: .automatic, for: .automatic)
        .statusBarHidden(hideHeader)
        .task {
            isLoading = true
            await Task.yield()
            do {
                defer {
                    isLoading = false
                }
                remoteItem = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fileid)
                guard let remoteItem else { return }
                do {
                    let remoteData = await remoteItem.open()
                    defer {
                        remoteData.isLive = false
                    }
                    let data = try? await remoteData.read(position: 0, length: Int(remoteData.size), onProgress: { pos in
                        print(pos)
                    })
                    if let data, let im = UIImage(data: data) {
                        images.append(im)
                        imageIdx = 0
                        image = im
                    }
                }
            }
            
            await Task.yield()
            guard let remoteItem else { return }
            let files = await CloudFactory.shared.data.listData(storage: remoteItem.storage, parentID: remoteItem.parent).filter{ OpenfileUIView.pict_exts.contains($0.ext ?? "") }.sorted(by: { ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending })
            totalImages = files.count
            guard let curIdx = files.firstIndex(where: { $0.id == remoteItem.id }) else { return }
            guard files.count > 1 else { return }
            
            await Task.yield()
            loadingTask = Task {
                var ret: [Int: UIImage] = [:]
                ret[curIdx] = image
                var tasks: [Task<(Int, UIImage)?, Never>] = []
                for k in 1..<files.count {
                    if Task.isCancelled {
                        break
                    }
                    if curIdx + k < files.count {
                        let itemData = files[curIdx + k]
                        if let id = itemData.id {
                            let task = Task { ()->(Int, UIImage)? in
                                try? await withThrowingTaskGroup { group in
                                    group.addTask { ()->(Int, UIImage)? in
                                        let item = await CloudFactory.shared.storageList.get(remoteItem.storage)?.get(fileId: id)
                                        if let remoteData = await item?.open() {
                                            defer {
                                                remoteData.isLive = false
                                            }
                                            let data = try? await remoteData.read(position: 0, length: Int(remoteData.size))
                                            if let data, let im = UIImage(data: data) {
                                                return (curIdx + k, im)
                                            }
                                        }
                                        return nil
                                    }
                                    group.addTask {
                                        try await Task.sleep(for: .seconds(10))
                                        throw CancellationError()
                                    }
                                    let ret = try await group.next()!
                                    group.cancelAll()
                                    return ret
                                }
                            }
                            tasks.append(task)
                        }
                    }
                    if curIdx - k >= 0 {
                        let itemData = files[curIdx - k]
                        if let id = itemData.id {
                            let task = Task { ()->(Int, UIImage)? in
                                try? await withThrowingTaskGroup { group in
                                    group.addTask { ()->(Int, UIImage)? in
                                        let item = await CloudFactory.shared.storageList.get(remoteItem.storage)?.get(fileId: id)
                                        if let remoteData = await item?.open() {
                                            defer {
                                                remoteData.isLive = false
                                            }
                                            let data = try? await remoteData.read(position: 0, length: Int(remoteData.size))
                                            if let data, let im = UIImage(data: data) {
                                                return (curIdx - k, im)
                                            }
                                        }
                                        return nil
                                    }
                                    group.addTask {
                                        try await Task.sleep(for: .seconds(10))
                                        throw CancellationError()
                                    }
                                    let ret = try await group.next()!
                                    group.cancelAll()
                                    return ret
                                }
                            }
                            tasks.append(task)
                        }
                    }
                    if tasks.count > 5 {
                        if let first = tasks.first {
                            if let (i, im) = await first.value {
                                ret[i] = im
                                images = ret.sorted(by: { $0.key < $1.key }).map(\.value)
                                if let idx = images.firstIndex(of: image!) {
                                    imageIdx = idx
                                }
                            }
                            tasks.removeFirst()
                        }
                    }
                }
                for task in tasks {
                    if Task.isCancelled {
                        task.cancel()
                        _ = await task.value
                        continue
                    }
                    if let (i, im) = await task.value {
                        ret[i] = im
                        images = ret.sorted(by: { $0.key < $1.key }).map(\.value)
                        if let idx = images.firstIndex(of: image!) {
                            imageIdx = idx
                        }
                    }
                }
                totalImages = images.count
            }
        }
        .onDisappear {
            Task {
                await remoteItem?.cancel()
                loadingTask?.cancel()
            }
        }
    }
}

#Preview {
    ImageShowUIView(storage: "Local", fileid: "", remoteItem: nil)
}

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
    @State var progStr = ""
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

    var formatter2: ByteCountFormatter {
        let formatter2 = ByteCountFormatter()
        formatter2.allowedUnits = [.useAll]
        formatter2.countStyle = .file
        return formatter2
    }

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
            Color.black
                .ignoresSafeArea()
            
            imageView
                .ignoresSafeArea()

            if isLoading {
                VStack {
                    ProgressView()
                        .tint(.white)
                        .padding(30)
                        .scaleEffect(3)
                    
                    Text(verbatim: progStr)
                }
                .background {
                    Color(uiColor: .black)
                        .opacity(0.9)
                }
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
        .toolbarColorScheme(.dark, for: .navigationBar)
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
                let total = remoteItem.size
                do {
                    let remoteData = await remoteItem.open()
                    defer {
                        remoteData.isLive = false
                    }
                    let data = try? await remoteData.read(onProgress: { p in
                        if total > 0 {
                            progStr = "\(formatter2.string(fromByteCount: Int64(p))) / \(formatter2.string(fromByteCount: total))"
                        }
                        else {
                            progStr = "\(formatter2.string(fromByteCount: Int64(p)))"
                        }
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
                await withTaskGroup { group0 in
                    var count = 0
                    for k in 1..<files.count {
                        if Task.isCancelled {
                            break
                        }
                        if curIdx + k < files.count {
                            let itemData = files[curIdx + k]
                            if let id = itemData.id {
                                group0.addTask {
                                    try? await withThrowingTaskGroup { group in
                                        group.addTask { ()->(Int, UIImage)? in
                                            let item = await CloudFactory.shared.storageList.get(remoteItem.storage)?.get(fileId: id)
                                            try Task.checkCancellation()
                                            if let remoteData = await item?.open() {
                                                defer {
                                                    remoteData.isLive = false
                                                }
                                                try Task.checkCancellation()
                                                let data = try? await remoteData.read()
                                                try Task.checkCancellation()
                                                if let data, let im = UIImage(data: data) {
                                                    return (curIdx + k, im)
                                                }
                                            }
                                            return nil
                                        }
                                        group.addTask {
                                            try await Task.sleep(for: .seconds(10))
                                            print("timeout")
                                            return nil
                                        }
                                        let ret = try await group.next()!
                                        group.cancelAll()
                                        return ret
                                    }
                                }
                                count += 1
                            }
                        }
                        if curIdx - k >= 0 {
                            let itemData = files[curIdx - k]
                            if let id = itemData.id {
                                group0.addTask {
                                    try? await withThrowingTaskGroup { group in
                                        group.addTask { ()->(Int, UIImage)? in
                                            let item = await CloudFactory.shared.storageList.get(remoteItem.storage)?.get(fileId: id)
                                            try Task.checkCancellation()
                                            if let remoteData = await item?.open() {
                                                defer {
                                                    remoteData.isLive = false
                                                }
                                                try Task.checkCancellation()
                                                let data = try? await remoteData.read()
                                                try Task.checkCancellation()
                                                if let data, let im = UIImage(data: data) {
                                                    return (curIdx - k, im)
                                                }
                                            }
                                            return nil
                                        }
                                        group.addTask {
                                            try await Task.sleep(for: .seconds(10))
                                            print("timeout")
                                            return nil
                                        }
                                        let ret = try await group.next()!
                                        group.cancelAll()
                                        return ret
                                    }
                                }
                                count += 1
                            }
                        }
                        while count > 3 {
                            if let next = await group0.next(), let (i, im) = next {
                                ret[i] = im
                                images = ret.sorted(by: { $0.key < $1.key }).map(\.value)
                                if let idx = images.firstIndex(of: image!) {
                                    imageIdx = idx
                                }
                            }
                            count -= 1
                        }
                    }
                    while count > 0 {
                        if Task.isCancelled {
                            break
                        }
                        if let next = await group0.next(), let (i, im) = next {
                            ret[i] = im
                            images = ret.sorted(by: { $0.key < $1.key }).map(\.value)
                            if let idx = images.firstIndex(of: image!) {
                                imageIdx = idx
                            }
                        }
                        count -= 1
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

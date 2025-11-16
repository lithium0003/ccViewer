//
//  RootUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/19.
//

import SwiftUI
import Combine
internal import UniformTypeIdentifiers

import RemoteCloud
import ffconverter

struct PlayItem: Codable, Identifiable, Transferable {
    var id: String {
        "\(storage)\0\(fileid)\0\(path)"
    }
    var storage: String
    var fileid: String
    var path: String

    init(_ item: RemoteData) {
        self.storage = item.storage ?? ""
        self.fileid = item.id ?? ""
        self.path = item.path ?? ""
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: PlayItem.self, contentType: .data)
    }
}

struct PlaylistUIView: View {
    let playlistName: String
    @Binding var env: UserEnvObject
    @State private var ids: [String] = []
    @State private var items: [String: RemoteData] = [:]
    private var searchedItems: [String] {
        searchText.isEmpty ? ids : ids.filter { items[$0]?.name?.localizedStandardContains(searchText) ?? false }
    }
    @State private var itemMark: [String: Double] = [:]
    @State private var searchText: String = ""
    @State var sortOrder = UserDefaults.standard.integer(forKey: "ItemSortOrder") {
        didSet {
            UserDefaults.standard.set(sortOrder, forKey: "ItemSortOrder")
        }
    }
    @State var isLoading = false
    @State var playlistFolder: [String] = []
    @State var newName = ""
    @State var isNewName = false
    @State var isDelete = false

    @State var downloading = false
    @State var uploading = false
    @State var cancellables = Set<AnyCancellable>()

    @State var isCasting = false
    @State var isLoopPlay = false
    @State var isShufflePlay = false

    let formatString = DateFormatter.dateFormat(fromTemplate: "yyyyMMdd", options: 0, locale: Locale.current)!
    var f: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = formatString + " HH:mm:ss"
        return f
    }
    var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter
    }
    var formatter2: ByteCountFormatter {
        let formatter2 = ByteCountFormatter()
        formatter2.allowedUnits = [.useAll]
        formatter2.countStyle = .file
        return formatter2
    }

    func reload() async {
        let playitems = await CloudFactory.shared.data.getPlaylist(playlistName: playlistName)
        var newItems: [String: RemoteData] = [:]
        var newIds: [String] = []
        for (storage, fileid, path, uuid) in playitems {
            if let item = await CloudFactory.shared.data.getData(storage: storage, fileId: fileid) {
                newItems[uuid] = item
                newIds.append(uuid)
            }
            else {
                await CloudFactory.shared.storageList.get(storage)?.list(path: path)
                if fileid.contains("\t") {
                    let baseFileid = fileid.components(separatedBy: "\t")[0]
                    await (CloudFactory.shared.storageList.get(storage) as? RemoteSubItem)?.listSubitem(fileId: baseFileid)
                }
                if let item = await CloudFactory.shared.data.getData(storage: storage, fileId: fileid) {
                    newItems[uuid] = item
                    newIds.append(uuid)
                }
            }
        }
        items = newItems
        ids = newIds
        playlistFolder = await CloudFactory.shared.data.getPlaylists()
    }
    
    func rowReplace(_ from: IndexSet, _ to: Int) {
        var fixFrom: IndexSet = []
        for f in from {
            fixFrom.insert(ids.firstIndex(of: searchedItems[f])!)
        }
        let fixTo = ids.firstIndex(of: searchedItems[to])!
        ids.move(fromOffsets: fixFrom, toOffset: fixTo)
        var playList: [(String, String, String, String)] = []
        for id in ids {
            playList.append((items[id]?.storage ?? "", items[id]?.id ?? "", items[id]?.path ?? "", id))
        }
        Task {
            await CloudFactory.shared.data.setPlaylist(playlistName: playlistName, items: playList)
        }
    }
    
    func rowRemove(from source: IndexSet) {
        var fixSource: IndexSet = []
        for s in source {
            fixSource.insert(ids.firstIndex(of: searchedItems[s])!)
        }
        ids.remove(atOffsets: fixSource)
        var playList: [(String, String, String, String)] = []
        for id in ids {
            playList.append((items[id]?.storage ?? "", items[id]?.id ?? "", items[id]?.path ?? "", id))
        }
        Task {
            await CloudFactory.shared.data.setPlaylist(playlistName: playlistName, items: playList)
        }
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading) {
                HStack {
                    FlowLayout(alignment: .leading) {
                        ForEach(playlistFolder, id: \.self) { item in
                            if item == playlistName {
                                Button {
                                } label: {
                                    Text(verbatim: item)
                                }
                                .buttonStyle(.glassProminent)
                                .dropDestination(for: PlayItem.self) { (dropItems, dropSession) in
                                    Task {
                                        var newItems = await CloudFactory.shared.data.getPlaylist(playlistName: item)
                                        for drop in dropItems {
                                            newItems.append((drop.storage, drop.fileid, drop.path, UUID().uuidString))
                                        }
                                        await CloudFactory.shared.data.setPlaylist(playlistName: item, items: newItems)
                                        await reload()
                                    }
                                }
                            }
                            else {
                                Button {
                                    env.path.append(.playlist(name: item))
                                } label: {
                                    Text(verbatim: item)
                                }
                                .buttonStyle(.glass)
                                .dropDestination(for: PlayItem.self) { (dropItems, dropSession) in
                                    Task {
                                        var newItems = await CloudFactory.shared.data.getPlaylist(playlistName: item)
                                        for drop in dropItems {
                                            newItems.append((drop.storage, drop.fileid, drop.path, UUID().uuidString))
                                        }
                                        await CloudFactory.shared.data.setPlaylist(playlistName: item, items: newItems)
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        isDelete.toggle()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.glassProminent)
                }
                .padding()
                List {
                    Section {
                        ForEach(searchedItems, id: \.self) { id in
                            VStack(alignment: .leading) {
                                Text(verbatim: items[id]?.name ?? "")
                                    .font(.headline)
                                if let mdate = items[id]?.mdate {
                                    Text(verbatim: "\(f.string(from: mdate))\t\(formatter2.string(fromByteCount: Int64(items[id]!.size))) (\(formatter.string(from: items[id]!.size as NSNumber) ?? "0") bytes) \t\(items[id]?.subinfo ?? "")")
                                        .font(.footnote)
                                }
                                else {
                                    Text(verbatim: "\t\(formatter2.string(fromByteCount: Int64(items[id]!.size))) (\(formatter.string(from: items[id]!.size as NSNumber) ?? "0") bytes) \t\(items[id]?.subinfo ?? "")")
                                        .font(.footnote)
                                }
                            }
                            .draggable(PlayItem(items[id]!)) {
                                Image(systemName: "music.note")
                                    .font(.largeTitle)
                            }
                            .onTapGesture {
                                if Converter.IsCasting() {
                                    isLoading = true
                                    Task {
                                        defer {
                                            isLoading = false
                                        }
                                        await playConverter(storages: [items[id]?.storage ?? ""], fileids: [items[id]?.id ?? ""], playlist: true)
                                    }
                                }
                                else {
                                    env.path.append(HomePath.open(storages: [items[id]?.storage ?? ""], fileids: [items[id]?.id ?? ""], playlist: true))
                                }
                            }
                        }
                        .onMove(perform: rowReplace)
                        .onDelete(perform: rowRemove)
                    }
                }
                .searchable(text: $searchText)
                .refreshable {
                    isLoading = true
                    await reload()
                    isLoading = false
                }
            }

            VStack {
                Spacer()
                HStack {
                    if isLoopPlay {
                        Button {
                            isLoopPlay.toggle()
                            UserDefaults.standard.set(isLoopPlay, forKey: "loop")
                        } label: {
                            Image("loop").renderingMode(.template)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    else {
                        Button {
                            isLoopPlay.toggle()
                            UserDefaults.standard.set(isLoopPlay, forKey: "loop")
                        } label: {
                            Image("loop").renderingMode(.template)
                        }
                        .buttonStyle(.glass)
                    }
                    if isShufflePlay {
                        Button {
                            isShufflePlay.toggle()
                            UserDefaults.standard.set(isShufflePlay, forKey: "shuffle")
                        } label: {
                            Image("shuffle").renderingMode(.template)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    else {
                        Button {
                            isShufflePlay.toggle()
                            UserDefaults.standard.set(isShufflePlay, forKey: "shuffle")
                        } label: {
                            Image("shuffle").renderingMode(.template)
                        }
                        .buttonStyle(.glass)
                    }
                    Spacer()
                    if isCasting {
                        CastButton()
                            .frame(width: 20, height: 20)
                            .buttonStyle(.glass)
                        Spacer()
                            .frame(width: 20)
                        Button {
                            Task {
                                await Converter.Stop()
                                isCasting = Converter.IsCasting()
                            }
                        } label: {
                            Image("cast_on").renderingMode(.template)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    else {
                        Button {
                            Converter.Start()
                            isCasting = Converter.IsCasting()
                        } label: {
                            Image("cast").renderingMode(.template)
                        }
                        .buttonStyle(.glass)
                    }
                    Button {
                        var storages: [String] = []
                        var fileids: [String] = []
                        for id in searchedItems {
                            if !items[id]!.folder {
                                storages.append(items[id]?.storage ?? "")
                                fileids.append(items[id]?.id ?? "")
                            }
                        }
                        if storages.isEmpty { return }
                        if Converter.IsCasting() {
                            if isLoading { return }
                            isLoading = true
                            Task {
                                defer {
                                    isLoading = false
                                }
                                await playConverter(storages: storages, fileids: fileids, playlist: true)
                            }
                        }
                        else {
                            env.path.append(.open(storages: storages, fileids: fileids, playlist: true))
                        }
                    } label: {
                        Image("playall").renderingMode(.template)
                    }
                    .buttonStyle(.glass)
                }
                .padding()
            }
            
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
        .alert("New folder", isPresented: $isNewName) {
            TextField("", text: $newName)
            
            Button(role: .confirm) {
                if newName.isEmpty { return }
                if playlistFolder.contains(newName) { return }
                Task {
                    await CloudFactory.shared.data.setPlaylist(playlistName: newName, items: [])
                    await reload()
                }
            }
            Button(role: .cancel) {
            }
        }
        .alert("Delete playlist", isPresented: $isDelete) {
            Button(role: .destructive) {
                Task {
                    await CloudFactory.shared.data.deletePlaylist(playlistName: playlistName)
                    env.path.removeLast()
                }
            }
            Button(role: .cancel) {
            }
        } message: {
            Text("Remove this playlist?")
        }
        .onAppear {
            isCasting = Converter.IsCasting()
            isLoopPlay = UserDefaults.standard.bool(forKey: "loop")
            isShufflePlay = UserDefaults.standard.bool(forKey: "shuffle")
        }
        .onDisappear {
            isCasting = false
        }
        .task {
            DownloadProgressManeger.shared.subject
                .sink { _ in
                    Task {
                        downloading = await DownloadProgressManeger.shared.progressManeger.isPresent()
                    }
                }
                .store(in: &cancellables)
            UploadProgressManeger.shared.subject
                .sink { _ in
                    Task {
                        uploading = await UploadProgressManeger.shared.progressManeger.isPresent()
                    }
                }
                .store(in: &cancellables)

            isLoading = true
            Task {
                defer {
                    isLoading = false
                }
                try? await Task.sleep(for: .milliseconds(300))
                await reload()
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem() {
                Button {
                    isNewName.toggle()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
            ToolbarItem() {
                NavigationLink(value: HomePath.setting) {
                    Image(systemName: "gear")
                }
            }

            ToolbarItem(placement: .cancellationAction) {
                Button {
                    env.path.removeAll()
                } label: {
                    Image(systemName: "house")
                }
            }

            if downloading {
                ToolbarItem(placement: .status) {
                    DownloadProgressUIView()
                }
            }
            if uploading {
                ToolbarItem(placement: .status) {
                    UploadProgressUIView()
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var env = UserEnvObject()
    PlaylistUIView(playlistName: "", env: $env)
}

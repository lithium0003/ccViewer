//
//  RootUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/19.
//

import SwiftUI
import Combine

import GoogleCast

import RemoteCloud
import ffconverter

struct CastButton: UIViewRepresentable {
    func updateUIView(_ uiView: UIButton, context: Context) {
    }
    
    func makeUIView(context: Context) -> UIButton {
        let button = GCKUICastButton()
        button.configuration = .glass()
        return button
    }
}

struct ItemsUIView: View {
    @Environment(\.scenePhase) var scenePhase

    let storage: String
    let fileid: String
    @Binding var env: UserEnvObject
    @State private var title = ""
    @State private var items: [RemoteData] = []
    private var searchedItems: [RemoteData] {
        searchText.isEmpty ? items : items.filter { $0.name?.localizedStandardContains(searchText) ?? false }
    }
    @State private var itemMark: [String: Double] = [:]
    @State private var searchText: String = ""
    @State var sortOrder = UserDefaults.standard.integer(forKey: "ItemSortOrder") {
        didSet {
            UserDefaults.standard.set(sortOrder, forKey: "ItemSortOrder")
        }
    }
    @State var isLoading = false

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

    func doSort() {
        switch sortOrder {
        case 0:
            items = items.sorted(by: { in1, in2 in (in1.name ?? "").lowercased() < (in2.name  ?? "").lowercased() } )
        case 1:
            items = items.sorted(by: { in1, in2 in (in1.name ?? "").lowercased() > (in2.name  ?? "").lowercased() } )
        case 2:
            items = items.sorted(by: { in1, in2 in in1.size < in2.size } )
        case 3:
            items = items.sorted(by: { in1, in2 in in1.size > in2.size } )
        case 4:
            items = items.sorted(by: { in1, in2 in (in1.mdate ?? Date(timeIntervalSince1970: 0)) < (in2.mdate ?? Date(timeIntervalSince1970: 0)) } )
        case 5:
            items = items.sorted(by: { in1, in2 in (in1.mdate ?? Date(timeIntervalSince1970: 0)) > (in2.mdate ?? Date(timeIntervalSince1970: 0)) } )
        case 6:
            items = items.sorted(by: { in1, in2 in (in1.ext ?? "") < (in2.ext ?? "") } )
        case 7:
            items = items.sorted(by: { in1, in2 in (in1.ext ?? "") > (in2.ext ?? "") } )
        default:
            items = items.sorted(by: { in1, in2 in (in1.name ?? "").lowercased() < (in2.name  ?? "").lowercased() } )
        }
        let folders = items.filter({ $0.folder })
        let files = items.filter({ !$0.folder })
        items = folders + files
    }

    func getMarks() async {
        itemMark.removeAll()
        await Task.yield()
        itemMark = await CloudFactory.shared.mark.getMark(storage: storage, targetIDs: items.map({ $0.id ?? "" }), parentID: fileid)
    }
    
    func reload(_ force: Bool = false) async {
        if fileid.contains("\t") {
            title = fileid.components(separatedBy: "\t").last ?? ""
            items = await CloudFactory.shared.data.listData(storage: storage, parentID: fileid)
            doSort()
            await getMarks()
        }
        else if let item = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fileid) {
            title = item.path
            if item.isFolder {
                if force {
                    await CloudFactory.shared.storageList.get(storage)?.list(fileId: fileid)
                }
                items = await CloudFactory.shared.data.listData(storage: storage, parentID: fileid)
                if items.isEmpty, !force {
                    await CloudFactory.shared.storageList.get(storage)?.list(fileId: fileid)
                    items = await CloudFactory.shared.data.listData(storage: storage, parentID: fileid)
                }
                doSort()
                await getMarks()
            }
            else {
                if force {
                    await (CloudFactory.shared.storageList.get(storage) as? RemoteSubItem)?.removeSubitem(fileId: fileid)
                }
                await (CloudFactory.shared.storageList.get(storage) as? RemoteSubItem)?.listSubitem(fileId: fileid)
                items = await CloudFactory.shared.data.listData(storage: storage, parentID: fileid)
                doSort()
                await getMarks()
            }
        }
    }
    
    func sortButton(key: LocalizedStringKey, idx: Int) -> some View {
        Button {
            sortOrder = idx
            doSort()
        } label: {
            HStack {
                if sortOrder == idx {
                    Image(systemName: "checkmark")
                }
                Text(key)
            }
        }
    }
    
    @ViewBuilder
    func backgroundColor(_ item: RemoteData) -> some View {
        if let id = item.id, let p = itemMark[id], p.isFinite, p >= 0 {
            GeometryReader { geometry in
                Color("DidPlayColor")
                Color.blue.opacity(0.25)
                    .frame(width: (geometry.size.width * p))
            }
        }
    }
    
    var body: some View {
        ZStack {
            List {
                Section {
                    ForEach(searchedItems, id: \.self) { item in
                        if item.folder {
                            NavigationLink(value: HomePath.items(storage: storage, fileid: item.id ?? "")) {
                                VStack(alignment: .leading) {
                                    Text(verbatim: item.name ?? "")
                                        .font(.headline)
                                    if let mdate = item.mdate {
                                        Text(verbatim: "\(f.string(from: mdate))\tfolder")
                                            .font(.footnote)
                                    }
                                    else {
                                        Text(verbatim: "\tfolder")
                                            .font(.footnote)
                                    }
                                }
                            }
                            .listRowBackground(Color("FolderColor"))
                        }
                        else if item.hasSubitems {
                            NavigationLink(value: HomePath.items(storage: storage, fileid: item.id ?? "")) {
                                VStack(alignment: .leading) {
                                    Text(verbatim: item.name ?? "")
                                        .font(.headline)
                                    if let mdate = item.mdate {
                                        Text(verbatim: "\(f.string(from: mdate))\t\(formatter2.string(fromByteCount: Int64(item.size))) (\(formatter.string(from: item.size as NSNumber) ?? "0") bytes) \t\(item.subinfo ?? "")")
                                            .font(.footnote)
                                    }
                                    else {
                                        Text(verbatim: "\t\(formatter2.string(fromByteCount: Int64(item.size))) (\(formatter.string(from: item.size as NSNumber) ?? "0") bytes) \t\(item.subinfo ?? "")")
                                            .font(.footnote)
                                    }
                                }
                            }
                            .listRowBackground(Color("CueColor"))
                        }
                        else {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(verbatim: item.name ?? "")
                                        .font(.headline)
                                    if let mdate = item.mdate {
                                        Text(verbatim: "\(f.string(from: mdate))\t\(formatter2.string(fromByteCount: Int64(item.size))) (\(formatter.string(from: item.size as NSNumber) ?? "0") bytes) \t\(item.subinfo ?? "")")
                                            .font(.footnote)
                                    }
                                    else {
                                        Text(verbatim: "\t\(formatter2.string(fromByteCount: Int64(item.size))) (\(formatter.string(from: item.size as NSNumber) ?? "0") bytes) \t\(item.subinfo ?? "")")
                                            .font(.footnote)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if Converter.IsCasting() {
                                    isLoading = true
                                    Task {
                                        defer {
                                            isLoading = false
                                        }
                                        await playConverter(storages: [storage], fileids: [item.id ?? ""])
                                    }
                                }
                                else {
                                    env.path.append(HomePath.open(storages: [storage], fileids: [item.id ?? ""], playlist: false))
                                }
                            }
                            .listRowBackground(itemMark[item.id ?? ""] != nil ? backgroundColor(item) : nil)
                            .swipeActions {
                                if UserDefaults.standard.bool(forKey: "savePlaypos") {
                                    Button {
                                        Task {
                                            isLoading = true
                                            if itemMark[item.id ?? ""] != nil  {
                                                await CloudFactory.shared.mark.setMark(storage: storage, targetID: item.id ?? "", parentID: fileid, position: nil)
                                            }
                                            else {
                                                await CloudFactory.shared.mark.setMark(storage: storage, targetID: item.id ?? "", parentID: fileid, position: 1.0)
                                            }
                                            await getMarks()
                                            isLoading = false
                                        }
                                    } label: {
                                        if itemMark[item.id ?? ""] != nil {
                                            Label("Unmark", systemImage: "eraser")
                                        }
                                        else {
                                            Label("Mark", systemImage: "checkmark.circle")
                                                .tint(.green)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text(title)
                }
            }
            .searchable(text: $searchText)
            .refreshable {
                isLoading = true
                await reload(true)
                isLoading = false
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
                        for item in searchedItems {
                            if !item.folder {
                                storages.append(item.storage ?? "")
                                fileids.append(item.id ?? "")
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
                                await playConverter(storages: storages, fileids: fileids)
                            }
                        }
                        else {
                            env.path.append(.open(storages: storages, fileids: fileids, playlist: false))
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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            print(newPhase)
            isCasting = Converter.IsCasting()
        }
        .onChange(of: isCasting) {
            if !isCasting {
                Task {
                    await reload()
                }
            }
        }
        .onAppear() {
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
            defer {
                isLoading = false
            }
            try? await Task.sleep(for: .milliseconds(300))
            await reload()
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem() {
                NavigationLink(value: HomePath.edit(storage: storage, fileid: fileid)) {
                    Image(systemName: "square.and.pencil")
                }
            }
            ToolbarItem() {
                Menu {
                    sortButton(key: "Name A → Z", idx: 0)
                    sortButton(key: "Name Z → A", idx: 1)
                    sortButton(key: "Size 0 → 9", idx: 2)
                    sortButton(key: "Size 9 → 0", idx: 3)
                    sortButton(key: "Time old → new", idx: 4)
                    sortButton(key: "Time new → old", idx: 5)
                    sortButton(key: "Extension A → Z", idx: 6)
                    sortButton(key: "Extension Z → A", idx: 7)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
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
    ItemsUIView(storage: "Local", fileid: "", env: $env)
}

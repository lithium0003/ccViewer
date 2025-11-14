//
//  RootUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/19.
//

import SwiftUI
import PhotosUI
import CoreTransferable
internal import UniformTypeIdentifiers

import RemoteCloud
import Combine

func downloadAndUpload(item: RemoteItem, service: RemoteStorage, parentId: String) async {
    if item.isFolder { return }
    let newname = item.name
    let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, conformingTo: .data)
    defer {
        try? FileManager.default.removeItem(at: tmpurl)
    }
    await DownloadProgressManeger.shared.download(outUrl: tmpurl, item: item)
    guard FileManager.default.fileExists(atPath: tmpurl.path(percentEncoded: false)) else { return }
    await UploadProgressManeger.shared.upload(url: tmpurl, service: service, parentId: parentId, uploadname: newname)
}

struct DataFile: Transferable {
    public let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .data) { data in
            SentTransferredFile(data.url)
        } importing: { receivedData in
            let fileName = receivedData.file.lastPathComponent
            let copy: URL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            
            if FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.removeItem(at: copy)
            }
            
            try FileManager.default.copyItem(at: receivedData.file, to: copy)
            return .init(url: copy)
        }
    }
}

@Observable
class DownloadList {
    var continuations: [URL: CheckedContinuation<Bool,Never>] = [:]
}

struct EditItemsUIView: View {
    let storage: String
    let fileid: String
    @Binding var env: UserEnvObject
    @State var title = ""
    @State var items: [RemoteData] = []
    private var searchedItems: [RemoteData] {
        searchText.isEmpty ? items : items.filter { $0.name?.localizedStandardContains(searchText) ?? false }
    }
    @State private var searchText: String = ""
    @State var selection: [String] = []
    @State var sortOrder = UserDefaults.standard.integer(forKey: "ItemSortOrder") {
        didSet {
            UserDefaults.standard.set(sortOrder, forKey: "ItemSortOrder")
        }
    }
    @State private var importerPresented = false
    @State private var importerForExportPresented = false
    @State private var photoPresented = false
    @State var selectedPhotoItems: [PhotosPickerItem] = []
    @State var isLoading = false
    @State var downloading = false
    @State var uploading = false

    @State var cancellables = Set<AnyCancellable>()

    @State private var mkdirPopover = false
    @State private var renamePopover = false
    @State private var chtimePopover = false
    @State private var deleteAlert = false
    @State private var textNewName = ""
    @State private var dateCreate = Date()
    @State private var dateModified = Date()
    @State private var dupName = false
    @State private var downloadList = DownloadList()
    
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

    func hasSubItem(name: String?) -> Bool {
        return name?.lowercased().hasSuffix(".cue") ?? false
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

    func reload() async {
        if let item = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fileid) {
            title = item.path
            if item.isFolder {
                await CloudFactory.shared.storageList.get(storage)?.list(fileId: fileid)
                items = await CloudFactory.shared.data.listData(storage: storage, parentID: fileid)
                doSort()
            }
            else {
                await (CloudFactory.shared.storageList.get(storage) as? RemoteSubItem)?.listsubitem(fileId: fileid)
                items = await CloudFactory.shared.data.listData(storage: storage, parentID: fileid)
                doSort()
            }
        }
    }

    func checkDupName(testNames: [String]) async -> [Bool] {
        await reload()
        
        var ret: [Bool] = []
        for testName in testNames {
            var pass = true
            for item in items {
                if item.name == testName {
                    pass = false
                    break
                }
            }
            ret += [pass]
        }
        return ret
    }

    func addContinuation(url: URL, cont: CheckedContinuation<Bool, Never>) async {
        downloadList.continuations[url] = cont
        dupName = true
    }
    
    func downloadFile(targetFolder: URL, item: RemoteItem) async {
        let outUrl = targetFolder.appending(path: item.name)
        if FileManager.default.fileExists(atPath: outUrl.path(percentEncoded: false)) {
            let ret = await withCheckedContinuation { continuation in
                Task {
                    await addContinuation(url: outUrl, cont: continuation)
                }
            }
            guard ret else { return }
        }
        await DownloadProgressManeger.shared.download(outUrl: outUrl, item: item)
    }

    @concurrent
    func uploadFile(url: URL, service: RemoteStorage, parentId: String, scoped: Bool) async {
        print(url)

        let newname = url.lastPathComponent
        let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)

        do {
            guard !scoped || url.startAccessingSecurityScopedResource() else {
                return
            }
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            do {
                if FileManager.default.fileExists(atPath: tmpurl.path) {
                    try FileManager.default.removeItem(at: tmpurl)
                }
                try FileManager.default.copyItem(at: url, to: tmpurl)
            }
            catch let error {
                print(error)
                return
            }
        }
        await UploadProgressManeger.shared.upload(url: tmpurl, service: service, parentId: parentId, uploadname: newname)
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
    
    var samenameView: some View {
        List {
            Section {
                ForEach(downloadList.continuations.map({ (key: $0.key, value: $0.value) }), id: \.self.key) { (key, value) in
                    Text(key.lastPathComponent)
                    VStack(alignment: .leading) {
                        
                        HStack {
                            Spacer()
                            
                            Button("Override", role: .destructive) {
                                value.resume(returning: true)
                                downloadList.continuations.removeValue(forKey: key)
                                if downloadList.continuations.isEmpty {
                                    dupName = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Cancel", role: .cancel) {
                                value.resume(returning: false)
                                downloadList.continuations.removeValue(forKey: key)
                                if downloadList.continuations.isEmpty {
                                    dupName = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            } header: {
                Text("Same name found")
                    .font(.title)
            }
        }
        .scrollContentBackground(.hidden)
    }
    
    var body: some View {
        ZStack {
            List {
                Section {
                    HStack {
                        Text("All: \(items.count)  Display: \(searchedItems.count) Selected: \(selection.count)")
                        Button {
                            selection = searchedItems.compactMap{ $0.id }
                        } label: {
                            Image(systemName: "checkmark.square")
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        if !selection.isEmpty {
                            Button {
                                selection.removeAll()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .tint(.primary)
                        }
                    }
                    .listRowBackground(Color("NavigationEditColor"))
                    FlowLayout(alignment: .leading) {
                        Menu {
                            Button {
                                importerPresented = true
                            } label: {
                                Label("Documents", systemImage: "document.on.document")
                            }

                            Button {
                                photoPresented = true
                            } label: {
                                Label("Photo library", systemImage: "photo.on.rectangle.angled")
                            }
                        } label: {
                            if storage == "Local" {
                                Text("\(Image("up").renderingMode(.template)) Import")
                            }
                            else {
                                Text("\(Image("up").renderingMode(.template)) Upload")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .disabled(!selection.isEmpty)
                        .photosPicker(isPresented: $photoPresented, selection: $selectedPhotoItems)
                        .fileImporter(isPresented: $importerPresented, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
                            switch result {
                            case .success(let urls):
                                Task {
                                    guard let service = await CloudFactory.shared.storageList.get(storage) else {
                                        return
                                    }
                                    let passUrl = zip(urls, await checkDupName(testNames: urls.map({ $0.lastPathComponent }))).filter{ $0.1 }.map{ $0.0 }

                                    for url in passUrl {
                                        await uploadFile(url: url, service: service, parentId: fileid, scoped: true)
                                    }
                                    try? await Task.sleep(for: .seconds(5))
                                    await reload()
                                }
                            case .failure(let error):
                                print(error.localizedDescription)
                            }
                        }

                        Button {
                            importerForExportPresented.toggle()
                        } label: {
                            if storage == "Local" {
                                Text("\(Image("import").renderingMode(.template)) Export")
                            }
                            else {
                                Text("\(Image("import").renderingMode(.template)) Download")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .disabled(selection.isEmpty)
                        .fileImporter(isPresented: $importerForExportPresented, allowedContentTypes: [.folder]) { result in
                            switch result {
                            case .success(let url):
                                let itemsData = items.filter { selection.contains($0.id ?? "") }
                                guard url.startAccessingSecurityScopedResource() else {
                                    return
                                }
                                Task{
                                    defer {
                                        url.stopAccessingSecurityScopedResource()
                                    }
                                    await withTaskGroup(of: Void.self) { group in
                                        for itd in itemsData {
                                            if itd.folder {
                                                continue
                                            }
                                            group.addTask {
                                                guard let item = await CloudFactory.shared.storageList.get(storage)?.get(fileId: itd.id ?? "") else {
                                                    return
                                                }
                                                await downloadFile(targetFolder: url, item: item)
                                            }
                                        }
                                    }
                                }
                            case .failure(let error):
                                print(error.localizedDescription)
                            }
                        }

                        Button {
                            textNewName = ""
                            mkdirPopover = true
                        } label: {
                            Text("\(Image("newfolder").renderingMode(.template)) Folder")
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .disabled(!selection.isEmpty)
                        .alert("New folder", isPresented: $mkdirPopover) {
                            TextField("new name", text: $textNewName)
                            
                            Button("Cancel", role: .cancel) {
                                mkdirPopover = false
                            }
                            Button("OK", role: .confirm) {
                                mkdirPopover = false
                                let newname = textNewName
                                isLoading = true
                                Task {
                                    defer {
                                        isLoading = false
                                    }
                                    await Task.yield()
                                    guard await checkDupName(testNames: [newname]).first ?? false else {
                                        return
                                    }
                                    guard let service = await CloudFactory.shared.storageList.get(storage) else {
                                        return
                                    }
                                    guard await service.mkdir(parentId: fileid, newname: newname) != nil else {
                                        return
                                    }
                                    try? await Task.sleep(for: .seconds(1))
                                    await reload()
                                }
                            }
                        }

                        Button {
                            guard let fid = selection.first else {
                                return
                            }
                            guard let item = items.first(where: { $0.id == fid}) else {
                                return
                            }
                            textNewName = item.name ?? ""
                            renamePopover = true
                        } label: {
                            Text("\(Image("rename").renderingMode(.template)) Rename")
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .disabled(selection.count != 1)
                        .alert("Rename", isPresented: $renamePopover) {
                            TextField("new name", text: $textNewName)
                            
                            Button("Cancel", role: .cancel) {
                                renamePopover = false
                            }
                            Button("OK", role: .confirm) {
                                renamePopover = false
                                let newname = textNewName
                                guard let fid = selection.first else {
                                    return
                                }
                                isLoading = true
                                Task {
                                    guard let item = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fid) else {
                                        return
                                    }
                                    defer {
                                        isLoading = false
                                    }
                                    await Task.yield()
                                    guard await checkDupName(testNames: [newname]).first ?? false else {
                                        return
                                    }
                                    guard await item.rename(newname: newname) != nil else {
                                        return
                                    }
                                    selection.removeAll()
                                    try? await Task.sleep(for: .seconds(1))
                                    await reload()
                                }
                            }
                        }

                        Button {
                            guard let fid = selection.first else {
                                return
                            }
                            guard let item = items.first(where: { $0.id == fid}) else {
                                return
                            }
                            dateModified = item.mdate ?? Date()
                            chtimePopover = true
                        } label: {
                            Text("\(Image("time").renderingMode(.template)) Time")
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .disabled(selection.count != 1)
                        .popover(isPresented: $chtimePopover) {
                            VStack {
                                DatePicker("modified time", selection: $dateModified, displayedComponents: [.date, .hourAndMinute])
                                    .padding()

                                HStack {
                                    Spacer()
                                    Button("Cancel", role: .cancel) {
                                        chtimePopover = false
                                    }
                                    .buttonStyle(.bordered)
                                    Spacer()
                                    Button("OK", role: .confirm) {
                                        chtimePopover = false
                                        guard let fid = selection.first else {
                                            return
                                        }
                                        isLoading = true
                                        Task {
                                            guard let item = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fid) else {
                                                return
                                            }
                                            defer {
                                                isLoading = false
                                            }
                                            await Task.yield()
                                            guard await item.changetime(newdate: dateModified) != nil else {
                                                return
                                            }
                                            selection.removeAll()
                                            try? await Task.sleep(for: .seconds(1))
                                            await reload()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    Spacer()
                                }
                                .padding()
                            }
                            .padding()
                            .presentationCompactAdaptation(.popover)
                        }
                        
                        Button {
                            Task {
                                let ret = await withCheckedContinuation { continuation in
                                    env.storage = nil
                                    env.fileid = nil
                                    env.continuation = continuation
                                    env.path.append(HomePath.select(storage: "", fileid: ""))
                                }
                                guard ret, let toStorage = env.storage, let toFileId = env.fileid else {
                                    return
                                }
                                isLoading = true
                                defer {
                                    isLoading = false
                                }
                                guard let toRemoteStrage = await CloudFactory.shared.storageList.get(toStorage) else {
                                    return
                                }
                                await Task.yield()
                                await withTaskGroup { group in
                                    for fid in selection {
                                        group.addTask {
                                            guard let item = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fid) else {
                                                return
                                            }
                                            if toStorage == storage, await toRemoteStrage.targetIsMovable(srcFileId: fid, dstFileId: toFileId) {
                                                guard await item.move(toParentId: toFileId) != nil else {
                                                    return
                                                }
                                            }
                                            else {
                                                await downloadAndUpload(item: item, service: toRemoteStrage, parentId: toFileId)
                                            }
                                        }
                                    }
                                }
                                try? await Task.sleep(for: .seconds(1))
                                selection.removeAll()
                                await reload()
                            }
                        } label: {
                            Text("\(Image("move").renderingMode(.template)) Move")
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .disabled(selection.isEmpty)

                        Button {
                            deleteAlert = true
                        } label: {
                            Text("\(Image("delete").renderingMode(.template)) Delete")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(selection.isEmpty)
                        .alert("Delete", isPresented: $deleteAlert) {
                            Button("Delete", role: .destructive) {
                                deleteAlert = false

                                isLoading = true
                                Task {
                                    defer {
                                        isLoading = false
                                    }
                                    await Task.yield()
                                    for fid in selection {
                                        guard let item = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fid) else {
                                            return
                                        }
                                        guard await item.delete() else {
                                            continue
                                        }
                                    }
                                    selection.removeAll()
                                    try? await Task.sleep(for: .seconds(1))
                                    await reload()
                                }
                            }
                            Button("Cancel", role: .cancel) {
                                deleteAlert = false
                            }
                        } message: {
                            Text("\(selection.count) item(s) will be deleted.")
                        }
                    }
                    .
                    listRowBackground(Color("NavigationEditColor"))
                    FlowLayout(alignment: .leading) {
                        Button {
                            isLoading = true
                            Task {
                                defer {
                                    isLoading = false
                                }
                                await Task.yield()
                                await withTaskGroup { group in
                                    for fid in selection {
                                        group.addTask {
                                            guard let item = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fid) else {
                                                return
                                            }
                                            await CloudFactory.shared.data.setMark(storage: item.storage, targetID: item.id, parentID: item.path, position: nil)
                                        }
                                    }
                                }
                                selection.removeAll()
                                try? await Task.sleep(for: .seconds(1))
                                await reload()
                            }
                        } label: {
                            Text("\(Image(systemName: "eraser")) Unmark")
                                .padding(4)
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .disabled(selection.isEmpty || !UserDefaults.standard.bool(forKey: "savePlaypos"))

                        Button {
                            isLoading = true
                            Task {
                                defer {
                                    isLoading = false
                                }
                                await Task.yield()
                                var playList = await CloudFactory.shared.data.getPlaylist(playlistName: "default")
                                for fid in selection {
                                    guard let item = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fid) else {
                                        continue
                                    }
                                    if item.isFolder { continue }
                                    playList.append((item.storage, item.id, item.path, UUID().uuidString))
                                }
                                await CloudFactory.shared.data.setPlaylist(playlistName: "default", items: playList)
                                selection.removeAll()
                                try? await Task.sleep(for: .seconds(1))
                                await reload()
                            }
                        } label: {
                            Text("\(Image("addplay").renderingMode(.template)) Add playlist")
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .disabled(selection.isEmpty)
                    }
                    .listRowBackground(Color("NavigationEditColor"))
                } header: {
                    Text(title)
                }
                ForEach(searchedItems, id: \.self) { item in
                    if item.folder {
                        HStack {
                            if selection.contains(item.id ?? "") {
                                Image(systemName: "checkmark.square.fill")
                            }
                            else {
                                Image(systemName: "square")
                            }
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
                        .onTapGesture {
                            if selection.contains(item.id ?? "") {
                                selection.remove(at: selection.firstIndex(of: item.id ?? "")!)
                            }
                            else {
                                selection.append(item.id ?? "")
                            }
                        }
                        .listRowBackground(Color("FolderColor"))
                    }
                    else {
                        HStack {
                            if selection.contains(item.id ?? "") {
                                Image(systemName: "checkmark.square.fill")
                            }
                            else {
                                Image(systemName: "square")
                            }
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
                        .onTapGesture {
                            if selection.contains(item.id ?? "") {
                                selection.remove(at: selection.firstIndex(of: item.id ?? "")!)
                            }
                            else {
                                selection.append(item.id ?? "")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("NavigationEditColor"))
            .searchable(text: $searchText)
            .refreshable {
                await reload()
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
            await Task.yield()

            await reload()
        }
        .navigationTitle("")
        .toolbar {
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
        .onChange(of: selectedPhotoItems) {
            Task {
                guard let service = await CloudFactory.shared.storageList.get(storage) else {
                    return
                }
                for item in selectedPhotoItems {
                    do {
                        guard let data = try await item.loadTransferable(type: DataFile.self) else {
                            continue
                        }
                        if await checkDupName(testNames: [data.url.lastPathComponent]).first ?? false {
                            await uploadFile(url: data.url, service: service, parentId: fileid, scoped: false)
                        }
                        else {
                            try FileManager.default.removeItem(at: data.url)
                        }
                    }
                    catch {
                        print(error)
                    }
                }
                try? await Task.sleep(for: .seconds(5))
                await reload()
            }
        }
        .sheet(isPresented: $dupName, onDismiss: {
            if !downloadList.continuations.isEmpty {
                dupName = true
            }
        }) {
            samenameView
            .presentationDetents([.medium])
        }
    }
}

#Preview {
    @Previewable @State var env = UserEnvObject()
    EditItemsUIView(storage: "Local", fileid: "", env: $env)
}

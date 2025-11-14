//
//  MainUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/19.
//

import SwiftUI
internal import UniformTypeIdentifiers
import CommonCrypto

import RemoteCloud
import Combine

@Observable class UserEnvObject {
    var storage: String?
    var fileid: String?
    var path = [HomePath]() {
        didSet {
            if let last = path.last {
                if case .select(_, _) = last {
                    // pass
                }
                else if case .auth = last {
                    // pass
                }
                else if storage == nil, fileid == nil, let cont = continuation, case .edit(_, _) = last {
                    cont.resume(returning: false)
                }
            }
        }
    }
    var continuation: CheckedContinuation<Bool, Never>?
    var authView: (any View)?
}

struct AuthProxyView: View {
    @Binding var authView: (any View)?
    @Binding var continuation: CheckedContinuation<Bool, Never>?
    
    var body: some View {
        if let authView {
            AnyView(authView)
                .task {
                    if let continuation {
                        continuation.resume(returning: true)
                        self.continuation = nil
                    }
                }
        }
    }
}

enum HomePath: Hashable {
    case root
    case items(storage: String, fileid: String)
    case open(storages: [String], fileids: [String], playlist: Bool)
    case edit(storage: String, fileid: String)
    case setting
    case select(storage: String, fileid: String)
    case storage
    case auth
    case playlist(name: String)
    case shop

    var toString: LocalizedStringKey {
        switch self {
        case .root:
            "Root"
        case let .items(storage: storage, fileid: fileid):
            "\(storage):\(fileid)"
        case .open:
            ""
        case let .edit(storage: storage, fileid: fileid):
            "\(storage):\(fileid)"
        case .setting:
            "Setting"
        case let .select(storage: storage, fileid: fileid):
            "\(storage):\(fileid)"
        case .storage:
            "Storages"
        case .auth:
            "Auth"
        case let .playlist(name: name):
            "Playlist: \(name)"
        case .shop:
            "Shop"
        }
    }
    
    @ViewBuilder
    func Destination(env: Binding<UserEnvObject>) -> some View{
        switch self {
        case .root:
            EmptyView()
        case let .items(storage: storage, fileid: fileid):
            ItemsUIView(storage: storage, fileid: fileid, env: env)
        case let .open(storages: storages, fileids: fileids, playlist: playlist):
            OpenfileUIView(storages: storages, fileids: fileids, playlist: playlist)
        case let .edit(storage: storage, fileid: fileid):
            EditItemsUIView(storage: storage, fileid: fileid, env: env)
        case .setting:
            SettingUIView(env: env)
        case let .select(storage: storage, fileid: fileid):
            SelectItemsUIView(storage: storage, fileid: fileid, env: env)
        case .storage:
            NewStorageUIView(env: env)
        case .auth:
            AuthProxyView(authView: env.authView, continuation: env.continuation)
        case let .playlist(name: name):
            PlaylistUIView(playlistName: name, env: env)
        case .shop:
            StoreUIView()
        }
    }
}

struct MainUIView: View {
    @State var env = UserEnvObject()
    @State var storagasList: [String] = []
    @State var storageImage: [String: UIImage] = [:]

    @State var downloading = false
    @State var uploading = false
    @State var cancellables = Set<AnyCancellable>()

    @State var importing = false
    @State var isLoading = false

    @State private var toBeDeleted: IndexSet?
    @State private var showingDeleteAlert = false
    @State private var showingRestoreAlert = false

    func rowReplace(_ from: IndexSet, _ to: Int) {
        storagasList.move(fromOffsets: from, toOffset: to)
        CloudFactory.shared.setShowList(storagasList)
    }
    
    func rowRemove(from source: IndexSet) {
        toBeDeleted = source
        showingDeleteAlert = true
    }

    var body: some View {
        NavigationStack(path: $env.path){
            ZStack {
                List {
                    Section {
                        HStack {
                            Image(systemName: "plus")
                                .font(.largeTitle)
                            Text("Add new storage")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onLongPressGesture {
                            if storageImage.count != storagasList.count {
                                showingRestoreAlert.toggle()
                            }
                            else {
                                env.path.append(.storage)
                            }
                        }
                        .onTapGesture {
                            env.path.append(.storage)
                        }
                    }
                    Section {
                        ForEach(storagasList, id: \.self) { name in
                            NavigationLink(value: HomePath.items(storage: name, fileid: "")) {
                                HStack {
                                    if let image = storageImage[name] {
                                        Image(uiImage: image)
                                    }
                                    Text(verbatim: name)
                                        .font(.headline)
                                }
                            }
                        }
                        .onMove(perform: rowReplace)
                        .onDelete(perform: rowRemove)
                    }
                    Section {
                        HStack {
                            Image("playlist").renderingMode(.template)
                            Text("Playlist")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            env.path.append(.playlist(name: "default"))
                        }
                    }
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
            .alert("Restore", isPresented: $showingRestoreAlert) {
                Button(role: .confirm) {
                    CloudFactory.shared.setShowList([])
                } label: {
                    Text("Show all")
                }
                Button(role: .cancel) {
                }
            }
            .alert("Delete", isPresented: $showingDeleteAlert) {
                Button(role: .destructive) {
                    if let delIdx = toBeDeleted {
                        let delTagname = delIdx.map({ storagasList[$0] }).filter({ $0 != "Local" })
                        for tag in delTagname {
                            Task {
                                await CloudFactory.shared.delStorage(tagname: tag)
                            }
                        }
                    }
                } label: {
                    Text("Logout")
                }
                
                Button(role: .confirm) {
                    if let delIdx = toBeDeleted {
                        storagasList.remove(atOffsets: delIdx)
                        CloudFactory.shared.setShowList(storagasList)
                    }
                } label: {
                    Text("Hide")
                }
                
                Button(role: .cancel) {
                    toBeDeleted = nil
                }
            } message: {
                Text("Select the storage just to hide or logout.")
            }
            .navigationTitle(HomePath.root.toString)
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(for: HomePath.self) { appended in
                appended.Destination(env: $env)
                    .navigationTitle(appended.toString)
                    .toolbarTitleDisplayMode(.inline)
            }
            .toolbar {
                ToolbarItem() {
                    NavigationLink(value: HomePath.setting) {
                        Image(systemName: "gear")
                    }
                }
                
                if UserStateObject.shared.isPassworded {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            UserStateObject.shared.locked.toggle()
                        } label: {
                            Image(systemName: "lock")
                        }
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
                CloudFactory.shared.subject
                    .sink { _ in
                        Task {
                            let s = await CloudFactory.shared.storageList.get()
                            storagasList = await CloudFactory.shared.getShowList()
                            storageImage = Dictionary(s.map({ ($0.key, CloudFactory.shared.getIcon(service: $0.value.getStorageType())) }).filter({ ($0.1 != nil) }).map({ ($0.0, $0.1!) }), uniquingKeysWith: { $1 })
                        }
                    }
                    .store(in: &cancellables)

                let s = await CloudFactory.shared.storageList.get()
                storagasList = await CloudFactory.shared.getShowList()
                storageImage = Dictionary(s.map({ ($0.key, CloudFactory.shared.getIcon(service: $0.value.getStorageType())) }).filter({ ($0.1 != nil) }).map({ ($0.0, $0.1!) }), uniquingKeysWith: { $1 })

                if !CloudFactory.shared.initialized {
                    CloudFactory.shared.initiaize
                        .sink { b in
                            isLoading = false
                        }
                        .store(in: &cancellables)
                    isLoading = true
                }
            }
        }
    }
}

#Preview {
    MainUIView()
}

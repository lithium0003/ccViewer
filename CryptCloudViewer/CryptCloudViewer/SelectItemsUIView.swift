//
//  RootUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/19.
//

import SwiftUI

import RemoteCloud
import Combine

struct SelectItemsUIView: View {
    let storage: String
    let fileid: String
    @Binding var env: UserEnvObject
    @State private var title = "Root"
    @State private var items: [RemoteData] = []
    private var searchedItems: [RemoteData] {
        searchText.isEmpty ? items : items.filter { $0.name?.localizedStandardContains(searchText) ?? false }
    }
    @State private var searchText: String = ""
    @State var sortOrder = UserDefaults.standard.integer(forKey: "ItemSortOrder") {
        didSet {
            UserDefaults.standard.set(sortOrder, forKey: "ItemSortOrder")
        }
    }
    @State var isLoading = false

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

    func reload() async {
        if let item = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fileid) {
            title = item.path
            if item.isFolder {
                await CloudFactory.shared.storageList.get(storage)?.list(fileId: fileid)
                items = await CloudFactory.shared.data.listData(storage: storage, parentID: fileid)
                doSort()
            }
            else {
                await (CloudFactory.shared.storageList.get(storage) as? RemoteSubItem)?.listSubitem(fileId: fileid)
                items = await CloudFactory.shared.data.listData(storage: storage, parentID: fileid)
                doSort()
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

    @State var storagasList: [String] = []
    @State var storageImage: [String: UIImage] = [:]
    @State var cancellables = Set<AnyCancellable>()

    var body: some View {
        ZStack {
            if storage == "" {
                List {
                    ForEach(storagasList, id: \.self) { name in
                        NavigationLink(value: HomePath.select(storage: name, fileid: "")) {
                            HStack {
                                if let image = storageImage[name] {
                                    Image(uiImage: image)
                                }
                                Text(verbatim: name)
                                    .font(.headline)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color("RootSelectColor"))
                .task {
                    CloudFactory.shared.subject
                        .sink { _ in
                            Task {
                                let s = await CloudFactory.shared.storageList.get()
                                storagasList = s.keys.sorted()
                                storageImage = Dictionary(s.map({ ($0.key, CloudFactory.shared.getIcon(service: $0.value.getStorageType())) }).filter({ ($0.1 != nil) }).map({ ($0.0, $0.1!) }), uniquingKeysWith: { $1 })
                            }
                        }
                        .store(in: &cancellables)
                    let s = await CloudFactory.shared.storageList.get()
                    storagasList = s.keys.sorted()
                    storageImage = Dictionary(s.map({ ($0.key, CloudFactory.shared.getIcon(service: $0.value.getStorageType())) }).filter({ ($0.1 != nil) }).map({ ($0.0, $0.1!) }), uniquingKeysWith: { $1 })
                }
            }
            else {
                List {
                    ForEach(searchedItems, id: \.self) { item in
                        if item.folder {
                            NavigationLink(value: HomePath.select(storage: storage, fileid: item.id ?? "")) {
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
                        else {
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
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color("RootSelectColor"))
                .searchable(text: $searchText)
                .refreshable {
                    await reload()
                }
                .task {
                    isLoading = true
                    defer {
                        isLoading = false
                    }
                    await Task.yield()
                    await reload()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) {
                            while let last = env.path.last, case .select(_, _) = last {
                                env.path.removeLast()
                            }
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) {
                            env.storage = storage
                            env.fileid = fileid
                            while let last = env.path.last, case .select(_, _) = last {
                                env.path.removeLast()
                            }
                            env.continuation?.resume(returning: true)
                        } label: {
                            Image(systemName: "checkmark")
                        }
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
        .navigationTitle(title)
    }
}

#Preview {
    @Previewable @State var env = UserEnvObject()
    SelectItemsUIView(storage: "Local", fileid: "", env: $env)
}

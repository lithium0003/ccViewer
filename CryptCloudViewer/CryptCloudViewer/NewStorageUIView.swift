//
//  NewStorageUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/22.
//

import SwiftUI
import RemoteCloud

struct NewStorageUIView: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Binding var env: UserEnvObject

    let remotes = CloudStorages.allCases.filter({ $0 != .Local })
    @State var name = ""
    @State var warning = false {
        didSet {
            if warning {
                Task {
                    try await Task.sleep(for: .seconds(1))
                    warning = false
                }
            }
        }
    }
    @State var pass = false
    @State var start = false

    var body: some View {
        VStack {
            Form {
                Section(header: Text("Name")) {
                    TextField("New name", text: $name)
                        .padding(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.orange)
                        )
                }
                .listRowBackground(warning ? Color.red : Color.clear)
                Section(header: Text("Select a storage to add.")) {
                    FlowLayout(alignment: .leading, spacing: 20) {
                        ForEach(remotes, id: \.self) { remote in
                            if let image = CloudFactory.shared.getIcon(service: remote) {
                                VStack {
                                    Image(uiImage: image)
                                    Text(verbatim: CloudFactory.getServiceName(service: remote))
                                }
                                .onTapGesture {
                                    guard !name.isEmpty else {
                                        withAnimation {
                                            warning.toggle()
                                        }
                                        return
                                    }
                                    Task {
                                        guard let newitem = await CloudFactory.shared.newStorage(service: remote, tagname: name) else {
                                            return
                                        }
                                        start = true
                                        env.storage = nil
                                        env.fileid = nil
                                        env.authView = nil
                                        env.continuation = nil
                                        if await newitem.auth(callback: { (authView, continuation) in
                                            env.authView = authView
                                            env.continuation = continuation
                                            env.path.append(HomePath.auth)
                                        }, webAuthenticationSession: webAuthenticationSession, selectItem: {
                                            let ret = await withCheckedContinuation { continuation in
                                                env.storage = nil
                                                env.fileid = nil
                                                env.continuation = continuation
                                                env.path.append(HomePath.select(storage: "", fileid: ""))
                                            }
                                            env.continuation = nil
                                            guard ret, let storage = env.storage, let fileId = env.fileid else {
                                                return nil
                                            }
                                            return (storage, fileId)
                                        }) {
                                            await newitem.list(fileId: "")
                                            pass = true
                                            env.path.removeAll()
                                        }
                                        else {
                                            await CloudFactory.shared.delStorage(tagname: name)
                                            while let last = env.path.last {
                                                if case .storage = last {
                                                    break
                                                }
                                                env.path.removeLast()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Spacer()
        }
        .onDisappear {
            guard start else { return }
            if pass { return }
            for p in env.path {
                if case .storage = p {
                    return
                }
            }
            Task {
                await CloudFactory.shared.delStorage(tagname: name)
            }
        }
    }
}

#Preview {
    @Previewable @State var env = UserEnvObject()
    NewStorageUIView(env: $env)
}

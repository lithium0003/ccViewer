//
//  OpenfileUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/19.
//

import SwiftUI

import RemoteCloud
import ffplayer
import Combine
internal import UniformTypeIdentifiers

struct OpenfileUIView: View {
    let storages: [String]
    let fileids: [String]
    let playlist: Bool
    @Environment(\.dismiss) private var dismiss
    @State var isLoading = false
    @State var bridge: StreamBridge?
    @State var passStorages: [String] = []
    @State var passFileids: [String] = []

    @State var cancellables: Set<AnyCancellable> = []

    let defaultMediaExt: Set<String> = [
        "mp4",
        "mov",
        "m4v",
        "mp3",
        "m4a",
        "aac",
        "wav",
    ]
    
    public static let codeExtensions: Set<String> = [
        "js", "jsx", "mjs", "cjs", "ts", "tsx", "html", "htm", "xml", "svg",
        "css", "scss", "sass", "less", "styl", "json", "json5", "yaml", "yml", "toml",
        "php", "rb", "py", "pyw", "gql", "graphql", "proto",

        "c", "h", "cpp", "hpp", "cc", "cxx", "hh", "hxx", "cs", "java", "kt", "kts",
        "swift", "go", "rs", "d", "nim", "zig", "m", "mm", "v", "sv", "vhd", "vhdl",

        "sh", "bash", "zsh", "fish", "ps1", "psm1", "bat", "cmd", "dockerfile",
        "nginx", "conf", "ini", "properties", "pf", "mk", "makefile", "cmake",

        "hs", "lhs", "ml", "mli", "clj", "cljs", "cljc", "edn", "ex", "exs",
        "erl", "hrl", "fs", "fsi", "fsscript", "lisp", "lsp", "scm", "ss", "rkt",

        "f", "for", "f77", "f90", "f95", "f03", "f08", "m", "mat", "jl", "r",
        "tex", "sty", "cls", "sql", "pls", "plsql", "gcode", "nc",

        "pas", "pp", "inc", "dpr", "as", "ahk", "au3", "basic", "bas", "vb",
        "vbs", "vbe", "lua", "tcl", "tk", "pl", "pm", "elm", "cr", "dart",
        "gd", "gml", "groovy", "gradle", "haml", "hbs", "handlebars", "twig",
        "blade", "sol", "wast", "wasm", "diff", "patch"
    ]
    
    enum DispType {
        case empty
        case txt
        case binary
        case image
        case pdf
        case media
        case ffplay
    }
    @State var dispType = DispType.empty
    @State var loadFailed = false
    @State var shuldDismiss = false

    var body: some View {
        switch dispType {
        case .empty:
            ZStack {
                Color.clear
                
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
                isLoading = true
                defer {
                    isLoading = false
                }
                await Task.yield()
                if storages.count > 1 {
                    passStorages = storages
                    passFileids = fileids
                    if UserDefaults.standard.bool(forKey: "FFplayer") {
                        bridge = await Player.prepare(storages: passStorages, fileids: passFileids, playlist: playlist)
                        dispType = .ffplay
                    }
                    else if UserDefaults.standard.bool(forKey: "MediaViewer") {
                        dispType = .media
                    }
                    return
                }
                if let storage = storages.first, let fileid = fileids.first, let remoteItem = await CloudFactory.shared.data.getData(storage: storage, fileId: fileid)?.getItem() {
                    if remoteItem.ext.isEmpty {
                        dispType = .txt
                    }
                    else if OpenfileUIView.codeExtensions.contains(remoteItem.ext.lowercased()) {
                        dispType = .txt
                    }
                    else if let uti = UTType(filenameExtension: remoteItem.ext), uti.conforms(to: .text) {
                        dispType = .txt
                    }
                    else if let uti = UTType(filenameExtension: remoteItem.ext), uti.conforms(to: .image), UserDefaults.standard.bool(forKey: "ImageViewer") {
                        dispType = .image
                    }
                    else if let uti = UTType(filenameExtension: remoteItem.ext), uti.conforms(to: .pdf), UserDefaults.standard.bool(forKey: "PDFViewer") {
                        dispType = .pdf
                    }
                    else if UserDefaults.standard.bool(forKey: "FFplayer"), UserDefaults.standard.bool(forKey: "firstFFplayer") {
                        passStorages.append(storage)
                        passFileids.append(fileid)
                        bridge = await Player.prepare(storages: passStorages, fileids: passFileids, playlist: playlist)
                        dispType = .ffplay
                    }
                    else if defaultMediaExt.contains(remoteItem.ext.lowercased()), UserDefaults.standard.bool(forKey: "MediaViewer") {
                        passStorages.append(storage)
                        passFileids.append(fileid)
                        dispType = .media
                    }
                    else if UserDefaults.standard.bool(forKey: "FFplayer"), !UserDefaults.standard.bool(forKey: "firstFFplayer") {
                        passStorages.append(storage)
                        passFileids.append(fileid)
                        bridge = await Player.prepare(storages: passStorages, fileids: passFileids, playlist: playlist)
                        dispType = .ffplay
                    }
                    else {
                        dispType = .txt
                    }
                }
            }
            .onDisappear {
                if dispType == .empty {
                    bridge?.onClose(true)
                    bridge = nil
                }
            }
        case .txt:
            if let storage = storages.first, let fileid = fileids.first {
                TextViewUIView(storage: storage, fileid: fileid)
            }
        case .binary:
            if let storage = storages.first, let fileid = fileids.first {
                RawTextUIView(storage: storage, fileid: fileid)
            }
        case .image:
            if let storage = storages.first, let fileid = fileids.first {
                ImageShowUIView(storage: storage, fileid: fileid)
            }
        case .pdf:
            if let storage = storages.first, let fileid = fileids.first {
                PdfShowUIView(storage: storage, fileid: fileid)
            }
        case .media:
            MediaShowUIView(storages: passStorages, fileids: passFileids)
        case .ffplay:
            if !loadFailed {
                if let bridge {
                    FFPlayerUIView(bridge: bridge, shuldDismiss: $shuldDismiss)
                        .task {
                            bridge.failedSender
                                .sink { b in
                                    loadFailed = b
                                }
                                .store(in: &cancellables)
                            bridge.lockrotateSender
                                .sink { b in
                                    if b {
                                        OrientationManager.lock()
                                    }
                                    else {
                                        OrientationManager.unlock()
                                    }
                                }
                                .store(in: &cancellables)
                        }
                        .onChange(of: shuldDismiss) {
                            self.bridge = nil
                            OrientationManager.unlock()
                            Task {
                                try? await Task.sleep(for: .milliseconds(50))
                                dismiss()
                            }
                        }
                }
                else {
                    Color.clear
                }
            }
            else {
                if let storage = storages.first, let fileid = fileids.first {
                    RawTextUIView(storage: storage, fileid: fileid)
                }
            }
        }
    }
}

#Preview {
    OpenfileUIView(storages: ["Local"], fileids: [""], playlist: false)
}

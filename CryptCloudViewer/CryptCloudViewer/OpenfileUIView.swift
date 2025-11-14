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

    enum DispType {
        case empty
        case txt
        case image
        case pdf
        case media
        case ffplay
    }
    @State var dispType = DispType.empty
    @State var loadFailed = false
    @State var shuldDismiss = false

    static let media_exts = [
        "mov",
        "mp4",
        "mp3",
        "wav",
        "aac",
        "3gp",
        "m4a",
    ]

    static let pict_exts = [
        "tif","tiff",
        "heic",
        "jpg","jpeg",
        "gif",
        "png",
        "bmp",
        "ico",
        "cur",
        "xbm",
        "3fr", // (Hasselblad)
        "ari", // (Arri_Alexa)
        "arw","srf","sr2", // (Sony)
        "bay", // (Casio)
        "braw", // (Blackmagic Design)
        "cri", // (Cintel)
        "crw","cr2","cr3", // (Canon)
        "cap","iiq","eip", // (Phase_One)
        "dcs","dcr","drf","k25","kdc", // (Kodak)
        "dng", // (Adobe)
        "erf", // (Epson)
        "fff", // (Imacon/Hasselblad raw)
        "gpr", // (GoPro)
        "mef", // (Mamiya)
        "mdc", // (Minolta, Agfa)
        "mos", // (Leaf)
        "mrw", // (Minolta, Konica Minolta)
        "mos", // (Leaf)
        "mrw", // (Minolta, Konica Minolta)
        "nef","nrw", // (Nikon)
        "orf", // (Olympus)
        "pef","ptx", // (Pentax)
        "pxn", // (Logitech)
        "r3d", // (RED Digital Cinema)
        "raf", // (Fuji)
        "raw","rw2", // (Panasonic)
        "raw","rwl","dng", // (Leica)
        "rwz", // (Rawzor)
        "srw", // (Samsung)
        "x3f", // (Sigma)
    ]

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
                    var ffplay = false
                    if UserDefaults.standard.bool(forKey: "FFplayer"), UserDefaults.standard.bool(forKey: "firstFFplayer") {
                        for (storage, fileid) in zip(storages, fileids) {
                            if let remoteItem = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fileid) {
                                if remoteItem.ext == "txt" {
                                }
                                else if OpenfileUIView.pict_exts.contains(remoteItem.ext) {
                                }
                                else if remoteItem.ext == "pdf" {
                                }
                                else {
                                    ffplay = true
                                    passStorages.append(storage)
                                    passFileids.append(fileid)
                                }
                            }
                        }
                    }
                    else {
                        for (storage, fileid) in zip(storages, fileids) {
                            if let remoteItem = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fileid) {
                                if remoteItem.ext == "txt" {
                                }
                                else if OpenfileUIView.pict_exts.contains(remoteItem.ext) {
                                }
                                else if remoteItem.ext == "pdf" {
                                }
                                else if OpenfileUIView.media_exts.contains(remoteItem.ext), UserDefaults.standard.bool(forKey: "MediaViewer") {
                                    passStorages.append(storage)
                                    passFileids.append(fileid)
                                }
                                else {
                                    ffplay = true
                                    passStorages.append(storage)
                                    passFileids.append(fileid)
                                }
                            }
                        }
                    }
                    if !passStorages.isEmpty {
                        if ffplay {
                            bridge = await Player.prepare(storages: passStorages, fileids: passFileids, playlist: playlist)
                            dispType = .ffplay
                        }
                        else {
                            dispType = .media
                        }
                        return
                    }
                }
                if let storage = storages.first, let fileid = fileids.first, let remoteItem = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fileid) {
                    if remoteItem.ext == "txt" {
                        dispType = .txt
                    }
                    else if OpenfileUIView.pict_exts.contains(remoteItem.ext), UserDefaults.standard.bool(forKey: "ImageViewer") {
                        dispType = .image
                    }
                    else if remoteItem.ext == "pdf", UserDefaults.standard.bool(forKey: "PDFViewer") {
                        dispType = .pdf
                    }
                    else if UserDefaults.standard.bool(forKey: "FFplayer"), UserDefaults.standard.bool(forKey: "firstFFplayer") {
                        passStorages.append(storage)
                        passFileids.append(fileid)
                        bridge = await Player.prepare(storages: passStorages, fileids: passFileids, playlist: playlist)
                        dispType = .ffplay
                    }
                    else if OpenfileUIView.media_exts.contains(remoteItem.ext), UserDefaults.standard.bool(forKey: "MediaViewer") {
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

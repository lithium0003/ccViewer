//
//  SettingUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/20.
//

import SwiftUI
import RemoteCloud

struct SettingUIView: View {
    @Binding var env: UserEnvObject

    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    let appname = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? ""

    let formatter2 = {
        let formatter2 = ByteCountFormatter()
        formatter2.allowedUnits = [.useAll]
        formatter2.countStyle = .file
        return formatter2
    }()

    @State var password = ""
    @State var uploadInBackground = UserDefaults.standard.bool(forKey: "uploadInBackground")
    @State var downloadInBackground = UserDefaults.standard.bool(forKey: "downloadInBackground")
    @State var useImageViewer = UserDefaults.standard.bool(forKey: "ImageViewer")
    @State var usePDFViewer = UserDefaults.standard.bool(forKey: "PDFViewer")
    @State var useMediaViewer = UserDefaults.standard.bool(forKey: "MediaViewer")
    @State var useFFplayer = UserDefaults.standard.bool(forKey: "FFplayer")
    @State var firstFFplayer = UserDefaults.standard.bool(forKey: "firstFFplayer")
    @State var playSkipForwardSec = UserDefaults.standard.integer(forKey: "playSkipForwardSec") {
        didSet {
            if oldValue == playSkipForwardSec {
                return
            }
            playSkipForwardSec = max(1, playSkipForwardSec)
            UserDefaults.standard.set(playSkipForwardSec, forKey: "playSkipForwardSec")
        }
    }
    @State var playSkipBackwardSec = UserDefaults.standard.integer(forKey: "playSkipBackwardSec") {
        didSet {
            if oldValue == playSkipBackwardSec {
                return
            }
            playSkipBackwardSec = max(1, playSkipBackwardSec)
            UserDefaults.standard.set(playSkipBackwardSec, forKey: "playSkipBackwardSec")
        }
    }
    @State var aribText = UserDefaults.standard.bool(forKey: "ARIB_subtitle_convert_to_text")

    @State var aribTextCast = UserDefaults.standard.bool(forKey: "ARIB_subtitle_convert_to_text_cast")
    @State var castTextImageIdx = UserDefaults.standard.integer(forKey: "Cast_text_image_idx") {
        didSet {
            if oldValue == castTextImageIdx {
                return
            }
            castTextImageIdx = max(-1, castTextImageIdx)
            UserDefaults.standard.set(castTextImageIdx, forKey: "Cast_text_image_idx")
        }
    }

    @State var savePlaypos = UserDefaults.standard.bool(forKey: "savePlaypos")
    @State var cloudPlaypos = UserDefaults.standard.bool(forKey: "cloudPlaypos")

    @State var cloudPlaylist = UserDefaults.standard.bool(forKey: "cloudPlaylist")

    @State var startOffsetHour = 0
    @State var startOffsetMin = 0
    @State var startOffsetSec = 0
    @State var startOffset = 0 {
        didSet {
            UserDefaults.standard.set(startOffset, forKey: "playStartSkipSec")
        }
    }
    @State var stopDurationHour = 0
    @State var stopDurationMin = 0
    @State var stopDurationSec = 0
    @State var stopDuration = 0 {
        didSet {
            UserDefaults.standard.set(stopDuration, forKey: "playStopAfterSec")
        }
    }

    @State var deleteConfirmation = false
    
    @State var networkCacheSize = 0
    var networkCacheSizeStr: LocalizedStringKey {
        if networkCacheSize > 0 {
            LocalizedStringKey(formatter2.string(fromByteCount: Int64(networkCacheSize)))
        }
        else {
            LocalizedStringKey("not use")
        }
    }
    @State var networkCacheSizeLimit = CloudFactory.shared.cache.cacheMaxSize
    let sizeKey = [
        0: LocalizedStringKey("Not use"),
        1*1000*1000: "1 MB",
        5*1000*1000: "5 MB",
        10*1000*1000: "10 MB",
        50*1000*1000: "50 MB",
        100*1000*1000: "100 MB",
        200*1000*1000: "200 MB",
        500*1000*1000: "500 MB",
        1000*1000*1000: "1 GB",
        2*1000*1000*1000: "2 GB",
        3*1000*1000*1000: "3 GB",
        5*1000*1000*1000: "5 GB",
        10*1000*1000*1000: "10 GB",
        15*1000*1000*1000: "15 GB",
        20*1000*1000*1000: "20 GB",
        25*1000*1000*1000: "25 GB",
        30*1000*1000*1000: "30 GB",
        40*1000*1000*1000: "40 GB",
        50*1000*1000*1000: "50 GB",
    ]

    func getKeyChain(key: String) -> String? {
        
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key,
                                  kSecReturnData as String: kCFBooleanTrue as Any]
        
        var data: AnyObject?
        let matchingStatus = withUnsafeMutablePointer(to: &data){
            SecItemCopyMatching(dic as CFDictionary, UnsafeMutablePointer($0))
        }
        
        if matchingStatus == errSecSuccess {
            if let getData = data as? Data,
                let getStr = String(data: getData, encoding: .utf8) {
                return getStr
            }
            return nil
        } else {
            return nil
        }
    }

    @discardableResult
    func setKeyChain(key: String, value: String) -> Bool{
        let data = value.data(using: .utf8)
        
        guard let _data = data else {
            return false
        }
        
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key,
                                  kSecValueData as String: _data]
        
        var itemAddStatus: OSStatus?
        let matchingStatus = SecItemCopyMatching(dic as CFDictionary, nil)
        
        if matchingStatus == errSecItemNotFound {
            // 保存
            itemAddStatus = SecItemAdd(dic as CFDictionary, nil)
        } else if matchingStatus == errSecSuccess {
            // 更新
            itemAddStatus = SecItemUpdate(dic as CFDictionary, [kSecValueData as String: _data] as CFDictionary)
        } else {
            print("保存失敗")
        }
        
        if itemAddStatus == errSecSuccess {
            return true
        } else {
            print("保存失敗")
            return false
        }
    }

    static func doDelete() async {
        await CloudFactory.shared.removeAllAuth()
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        await CloudFactory.shared.cache.deleteAllCache()
        await CloudFactory.shared.initializeDatabase()
    }

    var body: some View {
        Form {
            Section {
                SecureField("password", text: $password)
                    .onChange(of: password) {
                        setKeyChain(key: "password", value: password)
                    }
            } header: {
                Text("Protect on Lanch")
            }

            Section {
                Text(verbatim: "\(appname) \(version)(\(build))")
            } header: {
                Text("App infomation")
            }
            
            Section {
                Button {
                    UserDefaults.standard.set(false, forKey: "tutorial")
                    UserStateObject.shared.tutorial = false
                } label: {
                    Text("Show again")
                }
            } header: {
                Text("Tutorial")
            }

            Section {
                Toggle("Upload in background", isOn: $uploadInBackground)
                    .onChange(of: uploadInBackground) {
                        UserDefaults.standard.set(uploadInBackground, forKey: "uploadInBackground")
                    }
                Toggle("Download in background", isOn: $downloadInBackground)
                    .onChange(of: downloadInBackground) {
                        UserDefaults.standard.set(downloadInBackground, forKey: "downloadInBackground")
                    }
            } header: {
                Text("Background task")
            }

            Section {
                Toggle("Use Image viewer", isOn: $useImageViewer)
                    .onChange(of: useImageViewer) {
                        UserDefaults.standard.set(useImageViewer, forKey: "ImageViewer")
                    }
                Toggle("Use PDF viewer", isOn: $usePDFViewer)
                    .onChange(of: usePDFViewer) {
                        UserDefaults.standard.set(usePDFViewer, forKey: "PDFViewer")
                    }
                Toggle("Use Media player", isOn: $useMediaViewer)
                    .onChange(of: useMediaViewer) {
                        UserDefaults.standard.set(useMediaViewer, forKey: "MediaViewer")
                    }
                Toggle("Use FFmpeg player", isOn: $useFFplayer)
                    .onChange(of: useFFplayer) {
                        UserDefaults.standard.set(useFFplayer, forKey: "FFplayer")
                    }
                Toggle("Give priority to FFmpeg player over Media player", isOn: $firstFFplayer)
                    .disabled(!useFFplayer)
                    .onChange(of: firstFFplayer) {
                        UserDefaults.standard.set(firstFFplayer, forKey: "firstFFplayer")
                    }
            } header: {
                Text("Viewer")
            }

            Section {
                HStack {
                    Toggle("ARIB subtitle convert to text", isOn: $aribText)
                        .onChange(of: aribText) {
                            UserDefaults.standard.set(aribText, forKey: "ARIB_subtitle_convert_to_text")
                        }
                    if aribText {
                        Text("Plain text")
                    }
                    else {
                        Text("Image")
                    }
                }
                HStack {
                    Text("Skip foward (sec)")
                    Spacer()
                    Button {
                        playSkipForwardSec -= 1
                    } label: {
                        Image(systemName: "arrowtriangle.down")
                    }
                    .buttonStyle(.glass)
                    Text("\(playSkipForwardSec)")
                    Button {
                        playSkipForwardSec += 1
                    } label: {
                        Image(systemName: "arrowtriangle.up")
                    }
                    .buttonStyle(.glass)
                }
                HStack {
                    Text("Skip backward (sec)")
                    Spacer()
                    Button {
                        playSkipBackwardSec -= 1
                    } label: {
                        Image(systemName: "arrowtriangle.down")
                    }
                    .buttonStyle(.glass)
                    Text("\(playSkipBackwardSec)")
                    Button {
                        playSkipBackwardSec += 1
                    } label: {
                        Image(systemName: "arrowtriangle.up")
                    }
                    .buttonStyle(.glass)
                }
            } header: {
                Text("Player control")
            }

            Section {
                HStack {
                    Toggle("ARIB subtitle convert to text", isOn: $aribTextCast)
                        .onChange(of: aribTextCast) {
                            UserDefaults.standard.set(aribTextCast, forKey: "ARIB_subtitle_convert_to_text_cast")
                        }
                    if aribTextCast {
                        Text("Plain text")
                    }
                    else {
                        Text("Image")
                    }
                }
                HStack {
                    Text("Image subtile selection")
                    Spacer()
                    Button {
                        castTextImageIdx -= 1
                    } label: {
                        Image(systemName: "arrowtriangle.down")
                    }
                    .buttonStyle(.glass)
                    Text("\(castTextImageIdx)")
                    Button {
                        castTextImageIdx += 1
                    } label: {
                        Image(systemName: "arrowtriangle.up")
                    }
                    .buttonStyle(.glass)
                }
            } header: {
                Text("Cast control")
            }

            Section {
                HStack {
                    Spacer()
                    HStack {
                        Picker(selection: $startOffsetHour) {
                            ForEach(0..<26, id: \.self) {
                                Text("\($0)")
                            }
                        } label: {
                            Text("Hour")
                        }
                        Text(":")
                        Picker(selection: $startOffsetMin) {
                            ForEach(0..<60, id: \.self) {
                                Text("\($0)")
                            }
                        } label: {
                            Text("Min")
                        }
                        Text(":")
                        Picker(selection: $startOffsetSec) {
                            ForEach(0..<60, id: \.self) {
                                Text("\($0)")
                            }
                        } label: {
                            Text("Sec")
                        }
                    }
                    .frame(width: 350)
                }
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        startOffsetHour = 0
                        startOffsetMin = 0
                        startOffsetSec = 0
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } header: {
                Text("Start offset")
            }
            .onChange(of: startOffsetHour) {
                startOffset = startOffsetHour * 3600 + startOffsetMin * 60 + startOffsetSec
            }
            .onChange(of: startOffsetMin) {
                startOffset = startOffsetHour * 3600 + startOffsetMin * 60 + startOffsetSec
            }
            .onChange(of: startOffsetSec) {
                startOffset = startOffsetHour * 3600 + startOffsetMin * 60 + startOffsetSec
            }
            Section {
                HStack {
                    Spacer()
                    HStack {
                        Picker(selection: $stopDurationHour) {
                            ForEach(0..<26, id: \.self) {
                                Text("\($0)")
                            }
                        } label: {
                            Text("Hour")
                        }
                        Text(":")
                        Picker(selection: $stopDurationMin) {
                            ForEach(0..<60, id: \.self) {
                                Text("\($0)")
                            }
                        } label: {
                            Text("Min")
                        }
                        Text(":")
                        Picker(selection: $stopDurationSec) {
                            ForEach(0..<60, id: \.self) {
                                Text("\($0)")
                            }
                        } label: {
                            Text("Sec")
                        }
                    }
                    .frame(width: 350)
                }
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        stopDurationHour = 0
                        stopDurationMin = 0
                        stopDurationSec = 0
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } header: {
                Text("Stop duration")
            }
            .onChange(of: stopDurationHour) {
                stopDuration = stopDurationHour * 3600 + stopDurationMin * 60 + stopDurationSec
            }
            .onChange(of: stopDurationMin) {
                stopDuration = stopDurationHour * 3600 + stopDurationMin * 60 + stopDurationSec
            }
            .onChange(of: stopDurationSec) {
                stopDuration = stopDurationHour * 3600 + stopDurationMin * 60 + stopDurationSec
            }

            Section {
                HStack {
                    Text("Current cache size")
                    Spacer()
                    Text(networkCacheSizeStr)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    Task {
                        networkCacheSize = await CloudFactory.shared.cache.getCacheSize()
                    }
                }
                HStack {
                    Text("Cache limit")
                    Spacer()
                    Picker("limit size", selection: $networkCacheSizeLimit) {
                        ForEach(sizeKey.keys.sorted(), id: \.self) { key in
                            Text(sizeKey[key]!)
                        }
                    }
                    .onChange(of: networkCacheSizeLimit) {
                        CloudFactory.shared.cache.cacheMaxSize = networkCacheSizeLimit
                        Task {
                            await CloudFactory.shared.cache.increseFreeSpace()
                            networkCacheSize = await CloudFactory.shared.cache.getCacheSize()
                        }
                    }
                }
                Button(role: .destructive) {
                    Task {
                        await CloudFactory.shared.cache.deleteAllCache()
                        networkCacheSize = await CloudFactory.shared.cache.getCacheSize()
                    }
                } label: {
                    Text("Purge cache")
                }
            } header: {
                Text("Network cache")
            }

            Section {
                Toggle("Save play mark", isOn: $savePlaypos)
                    .onChange(of: savePlaypos) {
                        UserDefaults.standard.set(savePlaypos, forKey: "savePlaypos")
                    }
                Toggle("Sync with iCloud", isOn: $cloudPlaypos)
                    .onChange(of: cloudPlaypos) {
                        UserDefaults.standard.set(cloudPlaypos, forKey: "cloudPlaypos")
                    }
                    .disabled(!savePlaypos)
            } header: {
                Text("Record played item mark")
            }

            Section {
                Toggle("Sync with iCloud", isOn: $cloudPlaylist)
                    .onChange(of: cloudPlaylist) {
                        UserDefaults.standard.set(cloudPlaylist, forKey: "cloudPlaylist")
                    }
            } header: {
                Text("Playlist sync")
            }

            Section {
                Button(role: .destructive) {
                    deleteConfirmation.toggle()
                } label: {
                    Text("Clear all Authorization information and Cache data")
                }
                .alert("Delete all data", isPresented: $deleteConfirmation) {
                    Button(role: .destructive) {
                        Task {
                            await SettingUIView.doDelete()
                            env.path.removeAll()
                        }
                    }
                    Button(role: .cancel) {
                        deleteConfirmation = false
                    }
                } message: {
                    Text("Do you remove all autorization infomarion and cached data in app?")
                }
            } header: {
                Text("Delete")
            }
        }
        .onAppear {
            password = getKeyChain(key: "password") ?? ""
            startOffset = UserDefaults.standard.integer(forKey: "playStartSkipSec")
            startOffsetHour = startOffset / 3600
            startOffsetMin = (startOffset % 3600) / 60
            startOffsetSec = startOffset % 60
            stopDuration = UserDefaults.standard.integer(forKey: "playStopAfterSec")
            stopDurationHour = stopDuration / 3600
            stopDurationMin = (stopDuration % 3600) / 60
            stopDurationSec = stopDuration % 60
        }
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            networkCacheSize = await CloudFactory.shared.cache.getCacheSize()
        }
        .toolbar {
            ToolbarItem() {
                NavigationLink(value: HomePath.shop) {
                    Image(systemName: "cart")
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var env = UserEnvObject()
    SettingUIView(env: $env)
}

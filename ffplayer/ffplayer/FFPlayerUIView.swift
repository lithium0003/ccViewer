//
//  PlayerUIView.swift
//  ffplayer
//
//  Created by rei9 on 2025/10/28.
//  Copyright © 2025 lithium03. All rights reserved.
//

import SwiftUI
import Combine
import RemoteCloud
import AVKit

final class FrameworkResource {
    static func getImage(name: String) -> UIImage? {
        return UIImage(named: name, in: Bundle(for: self), compatibleWith: nil)
    }
    static func getLocalized(key: String) -> String {
        return Bundle(for: self).localizedString(forKey: key, value: nil, table: nil)
    }
}

class AVView: UIView {
    override func layoutSublayers(of layer: CALayer) {
        super.layoutSublayers(of: layer)
        layer.sublayers?.forEach {
            $0.frame = layer.bounds
        }
    }
}

class TouchTestView: UIView {
    var bridge: StreamBridge?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return self
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        bridge?.touchUpdate.send(Date())
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        bridge?.touchUpdate.send(Date())
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        bridge = nil
    }
}

struct AVSampleBufferDisplayLayerRepresentable: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer
    
    func makeUIView(context: Context) -> AVView {
        let uiView = AVView()
        uiView.layer.addSublayer(displayLayer)
        return uiView
    }

    func updateUIView(_ uiView: AVView, context: Context) {}
}

struct TouchTestViewRepresentable: UIViewRepresentable {
    let bridge: StreamBridge

    func makeUIView(context: Context) -> TouchTestView {
        let uiView = TouchTestView()
        uiView.bridge = bridge
        return uiView
    }
    
    func updateUIView(_ uiView: TouchTestView, context: Context) {}
}

public struct FFPlayerUIView: View {
    let bridge: StreamBridge
    @Environment(\.dismiss) private var dismiss
    @Binding var shuldDismiss: Bool

    @State var cancellables: Set<AnyCancellable> = []
    
    @State var mediaName = ""
    @State var mediaDuration = 0.0
    @State var soundOnly = false
    @State var isMediaInfoShow = false
    @State var lastTouched = Date()

    @State var mediaImage: UIImage?
    @State var isLoading = true
    @State var playPos = 0.0
    @State var seekPos = 0.0
    @State var isSeeking = false
    @State var buttonCalls: Int64 = 0
    @State var ccText: String? = nil
    @State var infoText: String? = nil
    @State var infoLastTime = Date()
    @State var pause = false
    @State var rotateLock = false
    @State var displayLayer: AVSampleBufferDisplayLayer?
    @State var observation1: NSKeyValueObservation? = nil
    @State var observation2: NSKeyValueObservation? = nil
    @State var pipAvailable = false
    @State var pipActive = false
    @State var initDone = false

    @State var skip_nextsec = UserDefaults.standard.integer(forKey: "playSkipForwardSec") {
        didSet {
            if skip_nextsec <= 0 {
                skip_nextsec = 15
            }
        }
    }
    @State var skip_prevsec = UserDefaults.standard.integer(forKey: "playSkipBackwardSec") {
        didSet {
            if skip_prevsec <= 0 {
                skip_prevsec = 15
            }
        }
    }

    func getTimeText(t: Double) -> String {
        var t1 = t
        let hour = Int(t1 / 3600)
        t1 -= Double(hour * 3600)
        let min = Int(t1 / 60)
        t1 -= Double(min * 60)
        let sec = Int(t1)
        t1 -= Double(sec)
        let usec = Int(t1 * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hour, min, sec, usec)
    }
    
    var timeText: String {
        if isSeeking {
            "Seeking to \(getTimeText(t: seekPos)) (\(String(format: "%05.2f%%", seekPos / mediaDuration * 100)))"
        }
        else {
            getTimeText(t: playPos) + " / " + getTimeText(t: mediaDuration)
        }
    }

    public init(bridge: StreamBridge, shuldDismiss: Binding<Bool>) {
        self.bridge = bridge
        self._shuldDismiss = shuldDismiss
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let displayLayer {
                AVSampleBufferDisplayLayerRepresentable(displayLayer: displayLayer)
                    .ignoresSafeArea()
            }
            if soundOnly {
                Color.black.ignoresSafeArea()
                if let im = mediaImage {
                    Image(uiImage: im)
                        .resizable()
                        .scaledToFit()
                }
                else {
                    Image(systemName: "waveform")
                        .scaleEffect(5)
                }
            }
            
            TouchTestViewRepresentable(bridge: bridge)

            if pipActive {
                VStack {
                    HStack {
                        if let im = FrameworkResource.getImage(name: "close") {
                            Button {
                                bridge.userBreak = true
                                shuldDismiss = true
                                observation1?.invalidate()
                                observation1 = nil
                                observation2?.invalidate()
                                observation2 = nil
                                cancellables.forEach {
                                    $0.cancel()
                                }
                                cancellables.removeAll()
                            } label: {
                                Image(uiImage: im)
                                    .renderingMode(.template)
                            }
                            .buttonStyle(.glass)
                            .padding()
                        }
                        Spacer()
                    }
                    Spacer()
                }
            }
            
            if (isMediaInfoShow || isSeeking) && !pipActive {
                VStack {
                    HStack {
                        if let im = FrameworkResource.getImage(name: "close") {
                            Button {
                                bridge.onClose(true)
                                if !initDone {
                                    dismiss()
                                }
                            } label: {
                                Image(uiImage: im)
                                    .renderingMode(.template)
                            }
                            .buttonStyle(.glass)
                            .padding()
                        }
                        Spacer()
                        Text(verbatim: mediaName)
                            .foregroundStyle(.white)
                            .background {
                                Color.black
                            }
                            .allowsHitTesting(false)
                        Spacer()
                        if pipAvailable {
                            Button {
                                if let pipController = bridge.pipController {
                                    if !pipController.isPictureInPictureActive {
                                        pipController.startPictureInPicture()
                                    }
                                }
                            } label: {
                                Image(systemName: "pip.enter")
                                    .tint(.white)
                                    .buttonStyle(.glass)
                                    .padding()
                            }
                        }
                    }
                    Spacer()
                    if let im = FrameworkResource.getImage(name: "video") {
                        HStack {
                            Button {
                                bridge.onCycleCh(0)
                            } label: {
                                Image(uiImage: im)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 30, height: 30)
                            }
                            .controlSize(.mini)
                            .buttonStyle(.glass)
                            Spacer()
                        }
                    }
                    if let im = FrameworkResource.getImage(name: "sound") {
                        HStack {
                            Button {
                                bridge.onCycleCh(1)
                            } label: {
                                Image(uiImage: im)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 30, height: 30)
                            }
                            .controlSize(.mini)
                            .buttonStyle(.glass)
                            Spacer()
                            if UIDevice.current.userInterfaceIdiom == .phone {
                                Button {
                                    rotateLock.toggle()
                                    bridge.lockrotateSender.send(rotateLock)
                                } label: {
                                    if rotateLock {
                                        Image(systemName: "rectangle.landscape.rotate")
                                    }
                                    else {
                                        Image(systemName: "rectangle.landscape.rotate.slash")
                                    }
                                }
                                .controlSize(.mini)
                                .buttonStyle(.glass)
                            }
                        }
                    }
                    if let im = FrameworkResource.getImage(name: "subtitle") {
                        HStack {
                            Button {
                                bridge.onCycleCh(2)
                            } label: {
                                Image(uiImage: im)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 30, height: 30)
                            }
                            .controlSize(.mini)
                            .buttonStyle(.glass)
                            Spacer()
                        }
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Spacer()
                        if let im = FrameworkResource.getImage(name: "prevp") {
                            Button {
                                bridge.onSeekChapter(-1)
                            } label: {
                                Image(uiImage: im)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 30, height: 30)
                            }
                            .controlSize(.mini)
                            .buttonStyle(.glass)
                            .tint(.green)
                        }
                        if let im = FrameworkResource.getImage(name: "prev00") {
                            Button {
                                if !isSeeking {
                                    seekPos = playPos
                                    isSeeking = true
                                }
                                OSAtomicIncrement64(&buttonCalls)
                                seekPos = seekPos - Double(skip_prevsec)
                                if seekPos < 0 {
                                    seekPos = 0
                                }
                                Task {
                                    try? await Task.sleep(for: .milliseconds(750))
                                    if OSAtomicDecrement64(&buttonCalls) == 0 {
                                        bridge.onSeek(seekPos)
                                        isSeeking = false
                                    }
                                }
                            } label: {
                                VStack(spacing: -15) {
                                    Image(uiImage: im)
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                    Text(String(skip_prevsec))
                                        .monospaced()
                                        .foregroundStyle(Color.green)
                                }
                            }
                            .controlSize(.mini)
                            .buttonStyle(.glass)
                            .tint(.green)
                        }
                        if let im1 = FrameworkResource.getImage(name: "play"), let im2 = FrameworkResource.getImage(name: "pause") {
                            Button {
                                Task {
                                    await bridge.onPause(!pause)
                                }
                            } label: {
                                if pause {
                                    Image(uiImage: im1)
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                        .tint(.green)
                                }
                                else {
                                    Image(uiImage: im2)
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                }
                            }
                            .controlSize(.mini)
                            .buttonStyle(.glass)
                            .tint(.green)
                        }
                        if let im = FrameworkResource.getImage(name: "next00") {
                            Button {
                                if !isSeeking {
                                    seekPos = playPos
                                    isSeeking = true
                                }
                                OSAtomicIncrement64(&buttonCalls)
                                seekPos = seekPos + Double(skip_nextsec)
                                if seekPos > mediaDuration {
                                    seekPos = mediaDuration
                                }
                                Task {
                                    try? await Task.sleep(for: .milliseconds(750))
                                    if OSAtomicDecrement64(&buttonCalls) == 0 {
                                        bridge.onSeek(seekPos)
                                        isSeeking = false
                                    }
                                }
                            } label: {
                                VStack(spacing: -15) {
                                    Image(uiImage: im)
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                    Text(String(skip_nextsec))
                                        .monospaced()
                                        .foregroundStyle(Color.green)
                                }
                            }
                            .controlSize(.mini)
                            .buttonStyle(.glass)
                            .tint(.green)
                        }
                        if let im = FrameworkResource.getImage(name: "nextp") {
                            Button {
                                bridge.onSeekChapter(1)
                            } label: {
                                Image(uiImage: im)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 30, height: 30)
                            }
                            .controlSize(.mini)
                            .buttonStyle(.glass)
                            .tint(.green)
                        }
                        Spacer()
                    }
                    ZStack {
                        Slider(value: $playPos, in: 0...mediaDuration)
                            .allowsHitTesting(false)
                            .sliderThumbVisibility(.hidden)
                            .opacity(isSeeking ? 0 : 1)
                        Slider(value: $seekPos, in: 0...mediaDuration) { b in
                            if !b {
                                bridge.touchUpdate.send(Date())
                                Task {
                                    isSeeking = false
                                    bridge.onSeek(seekPos)
                                }
                            }
                        }
                        .opacity(isSeeking ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isSeeking {
                            seekPos = playPos
                            isSeeking = true
                        }
                    }
                    Text(verbatim: timeText)
                        .monospaced()
                        .foregroundStyle(.green)
                        .background {
                            Color.black
                        }
                        .allowsHitTesting(false)
                }
            }

            if let ccText {
                VStack {
                    Spacer()
                    Text(verbatim: ccText)
                        .font(.largeTitle)
                        .background {
                            Color.black
                        }
                        .padding()
                }
                .allowsHitTesting(false)
            }

            if let infoText {
                Text(verbatim: infoText)
                    .font(.largeTitle)
                    .background {
                        Color.black
                    }
                    .padding()
                    .allowsHitTesting(false)
                Spacer()
                    .frame(width: 100)
            }

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .padding(30)
                    .background {
                        Color.black
                            .opacity(0.9)
                    }
                    .scaleEffect(3)
                    .cornerRadius(10)
                    .allowsHitTesting(false)
            }
        }
        .toolbarVisibility(.hidden, for: .automatic)
        .statusBarHidden(!isMediaInfoShow)
        .onDisappear {
            if !pipActive {
                bridge.onClose(true)
            }
        }
        .task {
            displayLayer = bridge.displayLayer
            bridge.touchUpdate
                .sink { t in
                    Task {
                        withAnimation {
                            isMediaInfoShow = true
                        }
                        lastTouched = t
                        try? await Task.sleep(for: .seconds(3))
                        if lastTouched.addingTimeInterval(3) < Date() {
                            isMediaInfoShow = false
                        }
                    }
                }
                .store(in: &cancellables)

            bridge.titleSender
                .sink { t in
                    mediaName = t
                }
                .store(in: &cancellables)
            bridge.durationSender
                .sink { t in
                    mediaDuration = max(0, t)
                }
                .store(in: &cancellables)
            bridge.soundOnlySender
                .sink { s in
                    soundOnly = s
                }
                .store(in: &cancellables)

            bridge.waiterSender
                .sink { w in
                    Task {
                        isLoading = w
                    }
                }
                .store(in: &cancellables)
            bridge.ccTextSender
                .sink { s in
                    Task {
                        if var s, let last = s.last, last.isNewline {
                            s.removeLast()
                            ccText = s
                        }
                        else {
                            ccText = s
                        }
                    }
                }
                .store(in: &cancellables)
            bridge.infoTextSender
                .sink { s in
                    Task {
                        infoText = s
                        infoLastTime = Date()
                        try? await Task.sleep(for: .seconds(3))
                        if infoLastTime.timeIntervalSinceNow < -3 {
                            infoText = nil
                        }
                    }
                }
                .store(in: &cancellables)
            bridge.artworkImageSender
                .sink { im in
                    Task {
                        mediaImage = im
                    }
                }
                .store(in: &cancellables)
            bridge.positionSender
                .sink { p in
                    Task {
                        playPos = max(0, p)
                    }
                }
                .store(in: &cancellables)
            bridge.pauseSender
                .sink { p in
                    pause = p
                }
                .store(in: &cancellables)
            
            bridge.initDoneSender
                .sink { v in
                    initDone = v
                }
                .store(in: &cancellables)

            bridge.touchUpdate.send(Date())
            Task {
                while bridge.pipController == nil {
                    try? await Task.sleep(for: .seconds(1))
                }
                if let pipController = bridge.pipController {
                    observation1 = pipController.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { _, change in
                        pipAvailable = change.newValue ?? false
                    }
                    observation2 = pipController.observe(\.isPictureInPictureActive, options: [.initial, .new]) { _, change in
                        pipActive = change.newValue ?? false
                    }
                }
            }
            
            try? await Task.sleep(for: .milliseconds(200))
            let failed = await bridge.run()
            bridge.failedSender.send(failed)

            await bridge.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true)
            observation1?.invalidate()
            observation1 = nil
            observation2?.invalidate()
            observation2 = nil
            Task {
                shuldDismiss = true
            }
        }
    }
}

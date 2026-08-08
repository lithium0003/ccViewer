//
//  RawTextUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/19.
//

import SwiftUI
import RemoteCloud
import Combine

struct HexLine: Identifiable, Hashable {
    var id: Int { offset }
    let offset: Int
    let text: String
}

struct HexChunk: Identifiable, Hashable {
    var id: Int { offset }
    let offset: Int
    let length: Int
    let eof: Bool
    let lines: [HexLine]
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

class ScrollTracker: ObservableObject {
    @Published var percentage: Double = 0.0
    var scrollOffsetY: CGFloat = 0
    var contentHeight: CGFloat = 1
    
    func reset() {
        scrollOffsetY = 0
    }
    
    func update(offset: CGFloat?, height: CGFloat?, remoteItem: RemoteItem?, chunks: [HexChunk]) {
        if let offset = offset { self.scrollOffsetY = max(0, abs(offset)) }
        if let height = height { self.contentHeight = max(1, height) }
        
        guard let size = remoteItem?.size, size > 0, let firstChunk = chunks.first else {
            percentage = 0.0
            return
        }

        let totalLines = chunks.reduce(0) { count, chunk in
            count + chunk.lines.count
        }
        let renderedBytes = Double(totalLines * 16)
        let actualTextHeight = max(1.0, contentHeight - 72.0)
        
        var exactByteOffset = Double(firstChunk.offset)
        if actualTextHeight > 0 {
            let bytesPerPixel = renderedBytes / Double(actualTextHeight)
            let textScrollY = max(0.0, Double(scrollOffsetY) - 16.0)
            exactByteOffset += textScrollY * bytesPerPixel
        }
        
        let calc = (exactByteOffset / Double(size)) * 100.0
        percentage = min(max(calc, 0.0), 100.0)
    }
}

struct PercentageView: View {
    @ObservedObject var tracker: ScrollTracker
    var body: some View {
        Text(String(format: "%.3f%%", tracker.percentage))
            .font(.headline)
            .monospacedDigit()
            .foregroundColor(.secondary)
            .frame(width: 85, alignment: .trailing)
    }
}

struct RawTextUIView: View {
    let storage: String
    let fileid: String
    @State var remoteItem: RemoteItem?
    
    @State var filename = ""
    @State var infotext = ""
    @State var currentOffset = 0
    @State var offsetText = ""
    @State var databuf = ""
    @State var remoteStream: RemoteStream?
    
    @State var chunks: [HexChunk] = []
    let maxChunks = 5
    let chunkSize = 4 * 1024

    @State private var scrollTracker = ScrollTracker()
    
    @State private var scrollPosition: Int?
    @State private var jumpTarget: Int?
    
    @State var isFetchingTop = false
    @State var isFetchingBottom = false
    @State var isLoading = false

    var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter
    }
        
    func convertToHex(data: Data, offset: Int) async -> [HexLine] {
        var lines: [HexLine] = []
        lines.reserveCapacity(data.count / 16 + 1)
        
        let initialColumn = offset % 16
        let dataStart = data.startIndex
        
        var currentLineStr = ""
        var currentLineOffset = offset
        
        for i in 0 ..< data.count {
            let currentAddress = i + offset
            let column = currentAddress % 16
            
            if i == 0 {
                currentLineOffset = currentAddress - column
                currentLineStr += String(format: "0x%08x : ", currentLineOffset)
                currentLineStr += String(repeating: "   ", count: column)
            } else if column == 0 {
                currentLineOffset = currentAddress
                currentLineStr += String(format: "0x%08x : ", currentLineOffset)
            }
            
            currentLineStr += String(format: "%02x ", data[dataStart + i])
            
            if column == 15 || i == data.count - 1 {
                if column < 15 {
                    currentLineStr += String(repeating: "   ", count: 15 - column)
                }
                
                let rowStartIndex = max(0, i - column)
                let actualSubStart = dataStart + rowStartIndex
                let actualSubEnd = dataStart + i
                
                let asciiLineBytes = data[actualSubStart...actualSubEnd].map { c -> UInt8 in
                    switch c {
                    case 0x20..<0x7f: return c
                    default: return 0x2E // "."
                    }
                }
                
                let asciiString = String(decoding: asciiLineBytes, as: UTF8.self)
                let asciiPadding = (rowStartIndex == 0 && initialColumn > 0) ? String(repeating: " ", count: initialColumn) : ""
                
                currentLineStr += " " + asciiPadding + asciiString
                
                // 配列に1行分を格納
                lines.append(HexLine(offset: currentLineOffset, text: currentLineStr))
                currentLineStr = ""
            }
        }
        return lines
    }
    
    @MainActor
    func loadPreviousChunk() async {
        guard !isFetchingTop else { return }
        guard let firstChunk = chunks.first, firstChunk.offset > 0 else { return }
        
        isFetchingTop = true
        defer { isFetchingTop = false }
        
        let prevOffset = max(0, firstChunk.offset - chunkSize)
        let length = firstChunk.offset - prevOffset
        
        if let remoteStream, let data = try? await remoteStream.read(position: Int64(prevOffset), length: length) {
            guard !data.isEmpty else { return }
            
            let eof = data.count < chunkSize || prevOffset + data.count >= (remoteItem?.size ?? 0)
            let hexLines = await convertToHex(data: data, offset: prevOffset)
            let newChunk = HexChunk(offset: prevOffset, length: data.count, eof: eof, lines: hexLines)
            
            guard let currentFirst = chunks.first, currentFirst.id == firstChunk.id else { return }
            
            chunks.insert(newChunk, at: 0)
            if chunks.count > maxChunks {
                chunks.removeLast()
            }
        }
    }

    @MainActor
    func loadNextChunk() async {
        guard !isFetchingBottom else { return }
        guard let lastChunk = chunks.last else { return }
        if lastChunk.eof { return }
        
        let nextOffset = lastChunk.offset + lastChunk.length
        guard let size = remoteItem?.size, nextOffset < size else { return }
        
        isFetchingBottom = true
        defer { isFetchingBottom = false }
        
        if let remoteStream, let data = try? await remoteStream.read(position: Int64(nextOffset), length: chunkSize) {
            guard !data.isEmpty else { return }
            
            let eof = data.count < chunkSize || nextOffset + data.count >= (remoteItem?.size ?? 0)
            let hexLines = await convertToHex(data: data, offset: nextOffset)
            let newChunk = HexChunk(offset: nextOffset, length: data.count, eof: eof, lines: hexLines)
            
            guard let currentLast = chunks.last, currentLast.id == lastChunk.id else { return }
            
            chunks.append(newChunk)
            if chunks.count > maxChunks {
                chunks.removeFirst()
            }
        }
    }
    
    @MainActor
    func jumpToOffset(_ targetOffset: Int) async {
        isLoading = true
        defer { isLoading = false }
        
        isFetchingTop = false
        isFetchingBottom = false
        
        scrollTracker.reset()
        chunks.removeAll()
        
        let normalizedOffset = targetOffset - (targetOffset % 16)
        
        if let remoteStream, let data = try? await remoteStream.read(position: Int64(normalizedOffset), length: chunkSize) {
            guard !data.isEmpty else { return }
            
            let eof = data.count < chunkSize || normalizedOffset + data.count >= (remoteItem?.size ?? 0)
            let hexLines = await convertToHex(data: data, offset: normalizedOffset)
            let chunk = HexChunk(offset: normalizedOffset, length: data.count, eof: eof, lines: hexLines)
            
            chunks.append(chunk)
            await loadPreviousChunk()
            await loadNextChunk()
            await loadPreviousChunk()
            await loadNextChunk()
            await Task.yield()
            jumpTarget = chunk.id
        }
    }

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Text(verbatim: infotext)
                    Spacer()
                    PercentageView(tracker: scrollTracker)
                    Spacer()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "Jump to Offset")
                        HStack {
                            Text(verbatim: "0x")
                            TextField("00000000", text: $offsetText)
                                .frame(maxWidth: 100)
                                .onSubmit {
                                    if let target = Int(offsetText, radix: 16) {
                                        Task.detached { @MainActor in
                                            await jumpToOffset(target)
                                        }
                                    }
                                }
                        }
                    }
                }
                
                GeometryReader { geometry in
                    ScrollViewReader { scrollProxy in
                        ScrollView((chunks.first?.eof ?? true) && scrollTracker.contentHeight < geometry.size.height ? .horizontal : [.vertical, .horizontal]) {
                            VStack(alignment: .leading, spacing: 0) {
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named("ScrollViewSpace")).minY)
                                }
                                .frame(width: 0, height: 0)
                                .onPreferenceChange(ScrollOffsetKey.self) { value in
                                    if abs(value) <= 1.0 {
                                        if let first = chunks.first, first.offset > 0 {
                                            if !isLoading {
                                                Task { @MainActor in await jumpToOffset(0) }
                                            }
                                            return
                                        }
                                    }
                                    scrollTracker.update(offset: value, height: nil, remoteItem: remoteItem, chunks: chunks)
                                }

                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(chunks) { chunk in
                                        ForEach(chunk.lines) { line in
                                            Text(line.text)
                                                .font(.system(size: 16).monospaced())
                                                .onAppear {
                                                    if isLoading { return }
                                                    if chunk.id == chunks.first?.id {
                                                        Task { @MainActor in await loadPreviousChunk() }
                                                    }
                                                    if chunk.id == chunks.last?.id {
                                                        Task { @MainActor in await loadNextChunk() }
                                                    }
                                                }
                                        }
                                    }
                                }
                                .scrollTargetLayout()
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 56)
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear
                                            .preference(key: ContentHeightKey.self, value: proxy.size.height)
                                    }
                                    .onPreferenceChange(ContentHeightKey.self) { value in
                                        scrollTracker.update(offset: nil, height: value, remoteItem: remoteItem, chunks: chunks)
                                    }
                                }
                            }
                            .frame(minWidth: geometry.size.width, alignment: .topLeading)
                            .padding(.bottom, max(0, geometry.size.height - scrollTracker.contentHeight))
                        }
                        .scrollPosition(id: $scrollPosition)
                        .coordinateSpace(name: "ScrollViewSpace")
                        .onChange(of: jumpTarget) { _, target in
                            if let target = target {
                                jumpTarget = nil
                                scrollProxy.scrollTo(target, anchor: .topLeading)
                            }
                        }
                    }
                }
                .onChange(of: chunks) { _, newChunks in
                    scrollTracker.update(offset: nil, height: nil, remoteItem: remoteItem, chunks: newChunks)
                }
            }
            .padding()
            
            if isLoading && chunks.isEmpty {
                ProgressView()
                    .padding(30)
                    .background {
                        Color(uiColor: .systemBackground).opacity(0.9)
                    }
                    .scaleEffect(3)
                    .cornerRadius(10)
            }
        }
        .navigationTitle(filename)
        .task {
            isLoading = true
            defer { isLoading = false }
            
            remoteItem = await CloudFactory.shared.data.getData(storage: storage, fileId: fileid)?.getItem()
            guard let remoteItem else { return }
            await Task.yield()
            filename = remoteItem.name
            let sStr = formatter.string(from: remoteItem.size as NSNumber) ?? "0"
            infotext = "\(sStr)\n\(String(format: "0x%08x", remoteItem.size))"
            remoteStream = await remoteItem.open()
            await jumpToOffset(0)
        }
        .onDisappear {
            Task {
                remoteStream?.isLive = false
                await remoteItem?.cancel()
            }
        }
    }
}

#Preview {
    RawTextUIView(storage: "Local", fileid: "", remoteItem: nil)
}

//
//  RawTextUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/19.
//

import SwiftUI
import RemoteCloud

struct RawTextUIView: View {
    let storage: String
    let fileid: String
    @State var remoteItem: RemoteItem?
    @State var decodeType = 0
    @State var filename = ""
    @State var infotext = ""
    @State var offset = 0 {
        didSet {
            Task { await loadBuffer() }
        }
    }
    @State var offsetText = ""
    @State var databuf = ""
    @State var remoteData: RemoteStream?
    @State var isLoading = false

    let decode = ["ascii", "hex", "utf8", "shift-JIS", "EUC", "unicode"]
    var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter
    }

    @concurrent
    func convertData(type: Int, data: Data, offset: Int) async -> String {
        func convertAscii(c: UInt8) -> String {
            switch c {
            case 0x09, 0x0a, 0x0d, 0x20..<0x7f:
                return String(bytes: [c], encoding: .ascii)!
            default:
                return "."
            }
        }

        switch type {
        case 0:
            return data.map { convertAscii(c: $0) }.joined()
        case 1:
            var str = ""
            data.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
                let bytes = p.bindMemory(to: UInt8.self)
                for i in 0 ..< data.count {
                    if i == 0 {
                        str += String(format: "0x%08x : ", i + offset)
                        str += String(repeating: "   ", count: Int((i + offset) % 16))
                    }
                    else if (i + offset) % 16 == 0 {
                        str += String(format: "0x%08x : ", i + offset)
                    }
                    str += String(format: "%02x ", bytes[i])
                    if (i + offset) % 16 == 15 {
                        str += "\n"
                    }
                }
            }
            return str
        case 2:
            return String(data: data, encoding: .utf8) ?? "failed to convert"
        case 3:
            return String(data: data, encoding: .shiftJIS) ?? "failed to convert"
        case 4:
            return String(data: data, encoding: .japaneseEUC) ?? "failed to convert"
        case 5:
            return String(data: data, encoding: .unicode) ?? "failed to convert"
        default:
            return "invalid"
        }
    }

    func loadBuffer() async {
        isLoading = true
        defer {
            isLoading = false
        }
        if let remoteData, let data = try? await remoteData.read(position: Int64(offset), length: 64 * 1024) {
            databuf = await convertData(type: decodeType, data: data, offset: offset)
        }
    }
    
    var body: some View {
        ZStack {
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Decode")
                        Picker("", selection: $decodeType) {
                            ForEach(0..<decode.count, id: \.self) { i in
                                Text(verbatim: decode[i])
                            }
                        }
                        .onChange(of: decodeType) {
                            Task {
                                await loadBuffer()
                            }
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "Offset")
                        HStack {
                            Text(verbatim: "0x")
                            TextField("00000000", text: $offsetText)
                                .frame(maxWidth: 100)
                                .onSubmit {
                                    offset = Int(offsetText, radix: 16) ?? 0
                                }
                        }
                    }
                    Text(verbatim: infotext)
                }
                .padding()
                TextEditor(text: .constant(databuf))
                    .font(.system(size: 16).monospaced())
                Spacer()
            }
            .padding()
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
        .navigationTitle(filename)
        .task {
            isLoading = true
            defer {
                isLoading = false
            }
            remoteItem = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fileid)
            guard let remoteItem else { return }
            await Task.yield()
            filename = remoteItem.name
            let sStr = formatter.string(from: remoteItem.size as NSNumber) ?? "0"
            infotext = "\(sStr)\n\(String(format: "0x%08x", remoteItem.size))"
            remoteData = await remoteItem.open()
            offset = 0
        }
        .onDisappear {
            Task {
                remoteData?.isLive = false
                await remoteItem?.cancel()
            }
        }
    }
}

#Preview {
    RawTextUIView(storage: "Local", fileid: "", remoteItem: nil)
}

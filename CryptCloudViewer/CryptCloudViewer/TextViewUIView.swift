//
//  TextViewUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2026/08/09.
//

import SwiftUI
import UIKit
import RemoteCloud
internal import UniformTypeIdentifiers
import WebKit

struct ReadOnlyTextView: UIViewRepresentable {
    var text: String
    var attributedText: NSAttributedString?
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.alwaysBounceVertical = true
        
        textView.isFindInteractionEnabled = true
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if let attributedText, uiView.attributedText != attributedText {
            uiView.dataDetectorTypes = .link
            uiView.attributedText = attributedText
            uiView.backgroundColor = .white
        }
        else if uiView.text != text {
            uiView.dataDetectorTypes = []
            let plainAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label
            ]
            uiView.attributedText = NSAttributedString(string: text, attributes: plainAttributes)
            uiView.backgroundColor = .clear
        }
    }
}

struct HTMLWebView: UIViewRepresentable {
    let htmlString: String
    var baseURL: URL? = nil
    var enableJavaScript = false
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    if url.scheme == "http" || url.scheme == "https" {
                        UIApplication.shared.open(url)
                    }
                }
                decisionHandler(.cancel)
                return
            }
            
            decisionHandler(.allow)
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = enableJavaScript
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(htmlString, baseURL: baseURL)
    }
}

struct TextViewUIView: View {
    let storage: String
    let fileid: String
    @State var remoteItem: RemoteItem?
    @State var remoteStream: RemoteStream?
    @State var filename = ""

    @State private var textContent = ""
    @State private var htmlContent = ""
    @State private var internalHtmlContent = ""
    @State private var attributedTextContent: NSAttributedString?
    @State private var isLoading = false
    
    let maxLoadSize = 5 * 1024 * 1024
    @State private var currentEncoding: String.Encoding? = nil
    @State private var isTruncated = false
    @State private var richPresentation = true
    @State private var isRichAbalable = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if isTruncated {
                    Text("File size is >5MB. Truncated.")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.yellow.opacity(0.8))
                        .foregroundColor(.black)
                }
                
                if !htmlContent.isEmpty {
                    HTMLWebView(htmlString: htmlContent)
                }
                else if !internalHtmlContent.isEmpty {
                    HTMLWebView(htmlString: internalHtmlContent, baseURL: Bundle.main.bundleURL, enableJavaScript: true)
                }
                else {
                    ReadOnlyTextView(text: textContent, attributedText: attributedTextContent)
                }
            }
            if isLoading {
                ProgressView("Loading...")
                    .padding()
                    .background(Color(uiColor: .systemBackground).opacity(0.8))
                    .cornerRadius(8)
            }
        }
        .navigationTitle(filename.isEmpty ? "Text Viewer" : filename)
        .toolbar {
            ToolbarItem() {
                Menu("Encode", systemImage: "character") {
                    Button("Auto detect") { reloadText(with: nil) }
                    Divider()
                    Button {
                        reloadText(with: .utf8)
                    } label: {
                        if currentEncoding == .utf8 {
                            Label("UTF-8", systemImage: "checkmark")
                        } else {
                            Text("UTF-8")
                        }
                    }
                    Button {
                        reloadText(with: .shiftJIS)
                    } label: {
                        if currentEncoding == .shiftJIS {
                            Label("Shift-JIS", systemImage: "checkmark")
                        } else {
                            Text("Shift-JIS")
                        }
                    }
                    Button {
                        reloadText(with: .japaneseEUC)
                    } label: {
                        if currentEncoding == .japaneseEUC {
                            Label("EUC-JP", systemImage: "checkmark")
                        } else {
                            Text("EUC-JP")
                        }
                    }
                }
            }
            if isRichAbalable {
                ToolbarItem() {
                    Button {
                        richPresentation.toggle()
                        Task {
                            isLoading = true
                            defer { isLoading = false }
                            await loadTextData()
                        }
                    } label: {
                        if richPresentation {
                            Image(systemName: "richtext.page.fill")
                        }
                        else {
                            Image(systemName: "richtext.page")
                        }
                    }
                }
            }
        }
        .task {
            isLoading = true
            defer { isLoading = false }
            
            await prepareItem()
            await loadTextData()
        }
        .onDisappear {
            Task {
                remoteStream?.isLive = false
                await remoteItem?.cancel()
            }
        }
    }
    
    private func reloadText(with encoding: String.Encoding?) {
        currentEncoding = encoding
        Task {
            isLoading = true
            defer { isLoading = false }
            await loadTextData()
        }
    }
    
    private func decodeDataToString(_ data: Data, forcedEncoding: String.Encoding? = nil) async -> String? {
        func decodeShiftJISLossy(_ data: Data) -> String {
            if let str = String(data: data, encoding: .shiftJIS) {
                return str
            }
            
            var result = ""
            var index = 0
            let count = data.count
            
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                guard let ptr = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
                
                while index < count {
                    let byte1 = ptr[index]
                    
                    let isFirstByteOfSJIS = (byte1 >= 0x81 && byte1 <= 0x9F) || (byte1 >= 0xE0 && byte1 <= 0xFC)
                    
                    if isFirstByteOfSJIS && index + 1 < count {
                        let byte2 = ptr[index + 1]
                        let isSecondByteOfSJIS = (byte2 >= 0x40 && byte2 <= 0x7E) || (byte2 >= 0x80 && byte2 <= 0xFC)
                        
                        if isSecondByteOfSJIS {
                            let subData = Data([byte1, byte2])
                            if let str = String(data: subData, encoding: .shiftJIS) {
                                result.append(str)
                                index += 2
                                continue
                            }
                        }
                    }
                    
                    let subData = Data([byte1])
                    if let str = String(data: subData, encoding: .shiftJIS) {
                        result.append(str)
                    } else {
                        result.append("?")
                    }
                    index += 1
                }
            }
            
            return result
        }

        func decodeEUCJPLossy(_ data: Data) -> String {
            if let str = String(data: data, encoding: .japaneseEUC) {
                return str
            }
            
            var result = ""
            var index = 0
            let count = data.count
            
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                guard let ptr = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
                
                while index < count {
                    let b1 = ptr[index]
                    
                    if b1 == 0x8F && index + 2 < count {
                        let b2 = ptr[index + 1]
                        let b3 = ptr[index + 2]
                        if (b2 >= 0xA1 && b2 <= 0xFE) && (b3 >= 0xA1 && b3 <= 0xFE) {
                            let subData = Data([b1, b2, b3])
                            if let str = String(data: subData, encoding: .japaneseEUC) {
                                result.append(str)
                                index += 3
                                continue
                            }
                        }
                    }
                    
                    if index + 1 < count {
                        let b2 = ptr[index + 1]
                        
                        let isHalfKana = (b1 == 0x8E) && (b2 >= 0xA1 && b2 <= 0xDF)
                        let isKanji = (b1 >= 0xA1 && b1 <= 0xFE) && (b2 >= 0xA1 && b2 <= 0xFE)
                        
                        if isHalfKana || isKanji {
                            let subData = Data([b1, b2])
                            if let str = String(data: subData, encoding: .japaneseEUC) {
                                result.append(str)
                                index += 2
                                continue
                            }
                        }
                    }
                    
                    let subData = Data([b1])
                    if let str = String(data: subData, encoding: .japaneseEUC) {
                        result.append(str)
                    } else {
                        result.append("?")
                    }
                    index += 1
                }
            }
            
            return result
        }
        
        if let encoding = forcedEncoding {
            if let str = String(data: data, encoding: encoding) {
                return str
            }

            switch encoding {
            case .utf8:
                return String(decoding: data, as: UTF8.self)
            case .shiftJIS:
                return decodeShiftJISLossy(data)
            case .japaneseEUC:
                return decodeEUCJPLossy(data)
            default:
                break
            }
        }
        
        if let utf8String = String(data: data, encoding: .utf8) {
            currentEncoding = .utf8
            return utf8String
        }
        
        if let shiftJISString = String(data: data, encoding: .shiftJIS) {
            currentEncoding = .shiftJIS
            return shiftJISString
        }
        
        if let eucString = String(data: data, encoding: .japaneseEUC) {
            currentEncoding = .japaneseEUC
            return eucString
        }
        
        return nil
    }
    
    private func prepareItem() async {
        remoteItem = await CloudFactory.shared.data.getData(storage: storage, fileId: fileid)?.getItem()
        guard let remoteItem else { return }
        filename = remoteItem.name
        if remoteItem.size > maxLoadSize {
            isTruncated = true
        } else {
            isTruncated = false

            let ext = remoteItem.ext.lowercased()
            if ext == "md" || ext == "markdown" {
                isRichAbalable = true
            }
            else if OpenfileUIView.codeExtensions.contains(ext) {
                isRichAbalable = true
            }
            else if let uti = UTType(filenameExtension: ext), uti.conforms(to: .html) {
                isRichAbalable = true
            }
            else if let uti = UTType(filenameExtension: ext), uti.conforms(to: .rtf) {
                isRichAbalable = true
            }
        }
        await Task.yield()
        remoteStream = await remoteItem.open()
    }

    private func getHighlightLanguage(from extension: String) -> String {
        let ext = `extension`.lowercased()
        
        let aliasMap: [String: String] = [
            "f": "fortran", "for": "fortran", "f77": "fortran", "f90": "fortran", "f95": "fortran", "f03": "fortran", "f08": "fortran",
            
            "h": "c", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "hh": "cpp", "hxx": "cpp", "m": "objectivec", "mm": "objectivec",
            
            "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascript",
            "ts": "typescript", "tsx": "typescript",
            "htm": "xml", "html": "xml", "svg": "xml",
            "styl": "stylus", "gql": "graphql",
            
            "py": "python", "pyw": "python",
            "rb": "ruby",
            "sh": "bash", "zsh": "bash", "fish": "shell",
            
            "cs": "csharp",
            "ps1": "powershell", "psm1": "powershell",
            "bat": "dos", "cmd": "dos",
            "vbs": "vbscript", "vbe": "vbscript", "vb": "vbnet",
            
            "kt": "kotlin", "kts": "kotlin",
            "rs": "rust",
            "hs": "haskell",
            "ml": "ocaml", "mli": "ocaml",
            "fs": "fsharp", "fsi": "fsharp", "fsscript": "fsharp",
            "clj": "clojure", "cljs": "clojure", "cljc": "clojure", "edn": "clojure",
            "ex": "elixir", "exs": "elixir",
            "erl": "erlang", "hrl": "erlang",
            "cr": "crystal",
            "lsp": "lisp", "scm": "scheme", "ss": "scheme",
            
            "yml": "yaml",
            "conf": "nginx",
            "mk": "makefile",
            "proto": "protobuf",
            "pls": "pgsql", "plsql": "pgsql",
            
            "tex": "latex", "sty": "latex",
            "jl": "julia",
            "nc": "gcode",
            "pas": "delphi", "pp": "delphi", "dpr": "delphi",
            "as": "actionscript",
            "ahk": "autohotkey",
            "au3": "autoit", "bas": "basic",
            "pl": "perl", "pm": "perl",
            "hbs": "handlebars"
        ]
        
        return aliasMap[ext] ?? ext
    }
    
    private func loadTextData() async {
        attributedTextContent = nil
        htmlContent = ""
        internalHtmlContent = ""
        textContent = ""
        await Task.yield()
        if let remoteStream, let data = try? await remoteStream.read(position: 0, length: maxLoadSize) {
            guard !data.isEmpty else { return }
            await Task.yield()
            if let txt = await decodeDataToString(data, forcedEncoding: currentEncoding) {
                if let remoteItem, isRichAbalable, richPresentation {
                    let ext = remoteItem.ext.lowercased()
                    if let uti = UTType(filenameExtension: ext), uti.conforms(to: .html) {
                        htmlContent = txt
                        return
                    }
                    else if let uti = UTType(filenameExtension: ext), uti.conforms(to: .rtf) {
                        if let data = txt.data(using: .utf8) {
                            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                                .documentType: NSAttributedString.DocumentType.rtf,
                                .characterEncoding: String.Encoding.utf8.rawValue
                            ]
                            
                            if let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                                attributedTextContent = attributedString
                                return
                            }
                        }
                    }
                    else if ext == "md" || ext == "markdown" {
                        let currentLang = Locale.current.language.languageCode?.identifier ?? "en"
                        let base64Text = txt.data(using: .utf8)?.base64EncodedString() ?? ""
                        let htmlTemplate = """
                        <!DOCTYPE html>
                        <html lang="\(currentLang)">
                        <head>
                            <meta charset="UTF-8">
                            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                            <script src="marked.min.js"></script>
                            <style>
                                body { 
                                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; 
                                    padding: 16px; 
                                    line-height: 1.6;
                                    color: #000; 
                                    background-color: #fff; 
                                }
                                a { color: #0a84ff; }
                                pre { background: #f5f5f5; padding: 10px; border-radius: 5px; overflow-x: auto; color: #000; }
                                img { max-width: 100%; height: auto; }
                            </style>
                        </head>
                        <body>
                            <div id="content"></div>
                            <script>
                                try {
                                    const base64Text = "\(base64Text)";
                                    const bytes = Uint8Array.from(atob(base64Text), c => c.charCodeAt(0));
                                    const source = new TextDecoder().decode(bytes);
                                    document.getElementById('content').innerHTML = marked.parse(source);
                                } catch (e) {
                                    document.getElementById('content').innerText = "Render Error: " + e.message;
                                }
                            </script>
                        </body>
                        </html>
                        """
                        internalHtmlContent = htmlTemplate
                        return
                    }
                    else if OpenfileUIView.codeExtensions.contains(ext) {
                        let currentLang = Locale.current.language.languageCode?.identifier ?? "en"
                        let base64Text = txt.data(using: .utf8)?.base64EncodedString() ?? ""
                        let langName = getHighlightLanguage(from: remoteItem.ext)
                        let langClass = "language-\(langName)"
                        let codeHtmlTemplate = """
                        <!DOCTYPE html>
                        <html lang="\(currentLang)">
                        <head>
                            <meta charset="UTF-8">
                            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                            <link rel="stylesheet" href="xcode.min.css">
                            <script src="highlight.min.js"></script>
                            <style>
                                body { 
                                    margin: 0; 
                                    padding: 16px;
                                    background-color: #ffffff;
                                }
                                pre { 
                                    margin: 0; 
                                    background-color: #f6f8fa;
                                    padding: 16px; 
                                    border-radius: 6px; 
                                    overflow-x: auto; 
                                }
                                code { 
                                    font-family: ui-monospace, SFMono-Regular, Consolas, "Liberation Mono", Menlo, monospace; 
                                    font-size: 14px; 
                                    line-height: 1.5;
                                }
                            </style>
                        </head>
                        <body>
                            <pre><code id="code-block" class="\(langClass)"></code></pre>
                            <script>
                                try {
                                    const base64Text = "\(base64Text)";
                                    const bytes = Uint8Array.from(atob(base64Text), c => c.charCodeAt(0));
                                    const source = new TextDecoder().decode(bytes);
                                    
                                    const codeBlock = document.getElementById('code-block');
                                    codeBlock.textContent = source; 
                                    
                                    hljs.highlightElement(codeBlock);
                                } catch (e) {
                                    document.getElementById('code-block').innerText = "Render Error: " + e.message;
                                }
                            </script>
                        </body>
                        </html>
                        """
                        internalHtmlContent = codeHtmlTemplate
                        return
                    }
                }
                textContent = txt
            }
            else {
                textContent = String(localized: "Failed to decode data. Please select encoding manually in menu.")
            }
        }
    }
}

#Preview {
    TextViewUIView(storage: "Local", fileid: "")
}

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
    
    private func decodeDataToString(_ data: Data, forcedEncoding: String.Encoding? = nil) -> String? {
        if let encoding = forcedEncoding {
            return String(data: data, encoding: encoding)
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
    
    private func loadTextData() async {
        attributedTextContent = nil
        htmlContent = ""
        internalHtmlContent = ""
        textContent = ""
        if let remoteStream, let data = try? await remoteStream.read(position: 0, length: maxLoadSize) {
            guard !data.isEmpty else { return }
            if let txt = decodeDataToString(data, forcedEncoding: currentEncoding) {
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
                        let base64Text = txt.data(using: .utf8)?.base64EncodedString() ?? ""
                        let htmlTemplate = """
                        <!DOCTYPE html>
                        <html lang="ja">
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
                        let base64Text = txt.data(using: .utf8)?.base64EncodedString() ?? ""
                        let langClass = "language-\(ext)"
                        let codeHtmlTemplate = """
                        <!DOCTYPE html>
                        <html lang="ja">
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

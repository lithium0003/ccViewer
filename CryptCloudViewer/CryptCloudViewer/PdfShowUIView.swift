//
//  PdfShowUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/20.
//

import SwiftUI
import RemoteCloud
import PDFKit


@Observable class PDFViewModel: NSObject {
    var pdfView: PDFView?
}

struct PDFThumbnailViewRepresentable: UIViewRepresentable {
    let model: PDFViewModel

    func makeUIView(context: Context) -> PDFThumbnailView {
        let uiView = PDFThumbnailView()
        uiView.layoutMode = .horizontal
        uiView.backgroundColor = .clear
        return uiView
    }

    func updateUIView(_ uiView: PDFThumbnailView, context: Context) {
        uiView.pdfView = model.pdfView
    }
}

struct PDFViewRepresentable: UIViewRepresentable {
    let document: PDFDocument
    let model: PDFViewModel
    
    func makeUIView(context: Context) -> PDFView {
        let uiView = PDFView()
        uiView.autoScales = true
        uiView.displayMode = .singlePageContinuous
        return uiView
    }
     
    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
        model.pdfView = uiView
    }
}

struct PdfShowUIView: View {
    let storage: String
    let fileid: String
    @State var title = ""
    @State var progStr = ""
    @State var remoteItem: RemoteItem?
    @State var remoteData: RemoteStream?
    @State var document: PDFDocument?
    @State var isLoading = false
    @State var model = PDFViewModel()
    @State var displayMode: PDFDisplayMode = .singlePageContinuous
    @State var searchText = ""
    @State var isSearching = false
    @State var countOfSelections = 0
    @State var currentSelection = -1 {
        didSet {
            if currentSelection != oldValue, currentSelection >= 0 {
                if let selections = model.pdfView?.highlightedSelections, selections.count > currentSelection {
                    model.pdfView?.go(to: selections[currentSelection])
                    model.pdfView?.setCurrentSelection(selections[currentSelection], animate: true)
                }
            }
        }
    }
    var formatter2: ByteCountFormatter {
        let formatter2 = ByteCountFormatter()
        formatter2.allowedUnits = [.useAll]
        formatter2.countStyle = .file
        return formatter2
    }

    func find(text: String) {
        let selections = model.pdfView?.document?.findString(text, withOptions: .caseInsensitive)
        model.pdfView?.highlightedSelections = selections
        countOfSelections = selections?.count ?? 0
        currentSelection = countOfSelections > 0 ? 0 : -1
    }
    
    @ViewBuilder
    var pdfView: some View {
        if let document {
            PDFViewRepresentable(document: document, model: model)
                .toolbar {
                    if countOfSelections > 0 {
                        ToolbarItem(placement: .automatic) {
                            Button {
                                currentSelection = currentSelection > 0 ? currentSelection - 1 : countOfSelections - 1
                            } label: {
                                Image(systemName: "arrowtriangle.backward.fill")
                            }
                        }
                        ToolbarItem(placement: .automatic) {
                            Button {
                                currentSelection = currentSelection < countOfSelections - 1 ? currentSelection + 1 : 0
                            } label: {
                                Image(systemName: "arrowtriangle.forward.fill")
                            }
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            isSearching.toggle()
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            if let scale = model.pdfView?.scaleFactorForSizeToFit {
                                model.pdfView?.scaleFactor = scale
                            }
                        } label: {
                            Image(systemName: "rectangle.portrait.arrowtriangle.2.inward")
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            switch displayMode {
                            case .singlePage:
                                model.pdfView?.displayMode = .singlePageContinuous
                            case .singlePageContinuous:
                                model.pdfView?.displayMode = .twoUp
                            case .twoUp:
                                model.pdfView?.displayMode = .twoUpContinuous
                            case .twoUpContinuous:
                                model.pdfView?.displayMode = .singlePage
                            @unknown default:
                                break
                            }
                            displayMode = model.pdfView?.displayMode ?? .singlePageContinuous
                            model.pdfView?.scaleFactor = model.pdfView?.scaleFactorForSizeToFit ?? 1.0
                        } label: {
                            switch displayMode {
                            case .singlePage:
                                Image(systemName: "text.page")
                            case .singlePageContinuous:
                                Image(systemName: "scroll")
                            case .twoUp:
                                Image(systemName: "rectangle.split.2x1")
                            case .twoUpContinuous:
                                ZStack {
                                    Image(systemName: "rectangle.split.2x1")
                                        .opacity(0.75)
                                    Image(systemName: "arrow.down")
                                        .scaleEffect(0.5)
                                }
                            @unknown default:
                                fatalError()
                            }
                        }
                    }
                    if displayMode == .singlePage || displayMode == .twoUp {
                        ToolbarItem(placement: .bottomBar) {
                            Button {
                                model.pdfView?.goToPreviousPage(model)
                            } label: {
                                Image(systemName: "arrowtriangle.backward.fill")
                            }
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        PDFThumbnailViewRepresentable(model: model)
                    }
                    if displayMode == .singlePage || displayMode == .twoUp {
                        ToolbarItem(placement: .bottomBar) {
                            Button {
                                model.pdfView?.goToNextPage(model)
                            } label: {
                                Image(systemName: "arrowtriangle.forward.fill")
                            }
                        }
                    }
                }
                .ignoresSafeArea()
                .alert("Search text", isPresented: $isSearching) {
                    TextField("", text: $searchText)
                    
                    Button(role: .confirm) {
                        find(text: searchText)
                    } label: {
                        Text("Search")
                    }
                    
                    Button(role: .cancel) {
                        
                    }
                }
        }
        else {
            Color.clear
        }
    }
    
    var body: some View {
        ZStack {
            pdfView

            if isLoading {
                VStack {
                    ProgressView()
                    .padding(30)
                    .scaleEffect(3)

                    Text(verbatim: progStr)
                }
                .background {
                    Color(uiColor: .systemBackground)
                        .opacity(0.9)
                }
                .cornerRadius(10)
            }
        }
        .navigationTitle(title)
        .task {
            isLoading = true
            defer {
                isLoading = false
            }
            await Task.yield()
            remoteItem = await CloudFactory.shared.storageList.get(storage)?.get(fileId: fileid)
            guard let remoteItem else { return }
            title = remoteItem.name
            let total = remoteItem.size
            remoteData = await remoteItem.open()
            if let remoteData {
                guard let docData = try? await remoteData.read(onProgress: { p in
                    if total > 0 {
                        progStr = "\(formatter2.string(fromByteCount: Int64(p))) / \(formatter2.string(fromByteCount: total))"
                    }
                    else {
                        progStr = "\(formatter2.string(fromByteCount: Int64(p)))"
                    }
                }) else {
                    return
                }
                if docData.count != remoteData.size {
                    return
                }
                Task { @MainActor in
                    if let doc = PDFDocument(data: docData) {
                        document = doc
                    }
                }
            }
            remoteData?.isLive = false
            remoteData = nil
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
    PdfShowUIView(storage: "Local", fileid: "", remoteItem: nil)
}

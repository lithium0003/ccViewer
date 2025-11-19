//
//  DownloadUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/24.
//

import SwiftUI
import RemoteCloud
import Combine
import BackgroundTasks

struct DownloadProgressUIView: View {
    @State var urls: [URL] = []
    @State var names: [URL: String] = [:]
    @State var progress: [URL: Double] = [:]

    @State var cancellables = Set<AnyCancellable>()
    
    @State var isPresented = false
    
    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Text("\(Image("import").renderingMode(.template)) \(urls.count)")
        }
        .sheet(isPresented: $isPresented) {
            ScrollView {
                LazyVStack(pinnedViews: .sectionHeaders) {
                    Section {
                        ForEach(urls, id: \.self) { url in
                            if let name = names[url], let p = progress[url] {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: name)
                                        ProgressView(value: p)
                                    }
                                    Button(role: .cancel) {
                                        Task {
                                            await DownloadProgressManeger.shared.progressManeger.cancel(url: url)
                                        }
                                    } label: {
                                        Image(systemName: "stop.circle")
                                    }
                                }
                                .listRowBackground(Color.clear)
                                .padding()
                            }
                        }
                    } header: {
                        Text("\(urls.count) files are downloading...")
                            .font(.title)
                            .padding()
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .task {
            DownloadProgressManeger.shared.subject
                .sink { _ in
                    Task {
                        (urls, names, progress) = await DownloadProgressManeger.shared.progressManeger.get()
                    }
                }
                .store(in: &cancellables)
        }
    }
}

@Observable
class DownloadProgressManeger {
    private static let _shared = DownloadProgressManeger()
    public static var shared: DownloadProgressManeger { return _shared }

    let bundleId = Bundle.main.bundleIdentifier!

    private init() {
    }
    
    let subject = PassthroughSubject<Int, Never>()

    actor ProgressManeger {
        private var urls: [URL] = []
        private var names: [URL: String] = [:]
        private var progress: [URL: Double] = [:]
        private var cancelList = Set<URL>()

        var count: Int {
            urls.count
        }

        func isPresent() -> Bool {
            count > 0
        }

        func get() -> ([URL], [URL:String], [URL:Double]) {
            return (urls, names, progress)
        }
        
        func isCenceled(url: URL) -> Bool {
            cancelList.contains(url)
        }
        
        func add(url: URL, name: String) {
            cancelList.remove(url)
            urls.append(url)
            names[url] = name
            progress[url] = 0
        }
        
        func delete(url: URL) {
            progress.removeValue(forKey: url)
            names.removeValue(forKey: url)
            urls.remove(at: urls.firstIndex(of: url)!)
            cancelList.remove(url)
        }
        
        func setProgress(url: URL, p: Double) {
            progress[url] = p
        }
        
        func cancel(url: URL) {
            cancelList.insert(url)
        }
    }
    public let progressManeger = ProgressManeger()

    @concurrent
    public func download_mac(outUrl: URL, item: RemoteItem) async {
        await progressManeger.add(url: outUrl, name: item.name)
        await subject.send(progressManeger.count)
        defer {
            Task {
                await progressManeger.delete(url: outUrl)
                await subject.send(progressManeger.count)
            }
        }
        let stream = await item.open()
        do {
            try? FileManager.default.removeItem(at: outUrl)
            guard let outfile = OutputStream(url: outUrl, append: true) else {
                return
            }
            outfile.open()
            defer {
                outfile.close()
            }
            var offset = 0
            while offset < Int(item.size) {
                let len = min(32*1024*1024, Int(item.size) - offset)
                guard let data = try await stream.read(position: Int64(offset), length: len, onProgress: { [self] pos in
                    if await progressManeger.isCenceled(url: outUrl) {
                        throw CancellationError()
                    }
                }) else {
                    try? FileManager.default.removeItem(at: outUrl)
                    return
                }
                data.withUnsafeBytes { ptr in
                    _ = outfile.write(ptr.baseAddress!, maxLength: data.count)
                }
                offset += data.count
                let p = min(1, Double(offset) / Double(item.size))
                await progressManeger.setProgress(url: outUrl, p: p)
                await subject.send(progressManeger.count)
            }
            if await progressManeger.isCenceled(url: outUrl) {
                try? FileManager.default.removeItem(at: outUrl)
                return
            }
            await progressManeger.setProgress(url: outUrl, p: 1)
            await subject.send(progressManeger.count)
        }
        catch {
            print(error)
        }
        stream.isLive = false
    }
    
    @concurrent
    public func download(outUrl: URL, item: RemoteItem) async {
        if ProcessInfo.processInfo.isiOSAppOnMac || !UserDefaults.standard.bool(forKey: "downloadInBackground") {
            await download_mac(outUrl: outUrl, item: item)
            return
        }

        let taskName = UUID().uuidString
        let taskIdentifier = "\(bundleId).export.\(taskName)"

        let request = BGContinuedProcessingTaskRequest(
            identifier: taskIdentifier,
            title: item.name,
            subtitle: "About to start...",
        )
        request.strategy = .fail
        let semaphore = Semaphore(value: 0)

        let success = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { [self] task in
            guard let task = task as? BGContinuedProcessingTask else {
                Task { await semaphore.signal() }
                return
            }
            
            Task {
                defer {
                    Task { await semaphore.signal() }
                }
                var wasExpired = false
                task.expirationHandler = {
                    wasExpired = true
                }

                // Update progress.
                let progress = task.progress
                progress.totalUnitCount = item.size

                await progressManeger.add(url: outUrl, name: item.name)
                await subject.send(progressManeger.count)
                defer {
                    Task {
                        await progressManeger.delete(url: outUrl)
                        await subject.send(progressManeger.count)
                        task.setTaskCompleted(success: !wasExpired)
                    }
                }
                let stream = await item.open()
                do {
                    try? FileManager.default.removeItem(at: outUrl)
                    guard let outfile = OutputStream(url: outUrl, append: true) else {
                        wasExpired = true
                        return
                    }
                    outfile.open()
                    defer {
                        outfile.close()
                    }
                    var offset = 0
                    while !wasExpired, offset < Int(item.size) {
                        let len = min(1*1024*1024, Int(item.size) - offset)
                        guard let data = try await stream.read(position: Int64(offset), length: len, onProgress: { [self] pos in
                            if await progressManeger.isCenceled(url: outUrl) {
                                throw CancellationError()
                            }
                            if wasExpired {
                                throw CancellationError()
                            }
                        }) else {
                            try? FileManager.default.removeItem(at: outUrl)
                            wasExpired = true
                            return
                        }
                        data.withUnsafeBytes { ptr in
                            _ = outfile.write(ptr.baseAddress!, maxLength: data.count)
                        }
                        offset += data.count
                        let p = min(1, Double(offset) / Double(item.size))
                        await progressManeger.setProgress(url: outUrl, p: p)
                        await subject.send(progressManeger.count)
                        progress.completedUnitCount = Int64(offset)
                        let formattedProgress = String(format: "%.2f", progress.fractionCompleted * 100)
                        task.updateTitle(task.title, subtitle: "Downloaded \(formattedProgress)%")
                    }
                    if await progressManeger.isCenceled(url: outUrl) {
                        try? FileManager.default.removeItem(at: outUrl)
                        wasExpired = true
                        return
                    }
                    await progressManeger.setProgress(url: outUrl, p: 1)
                    await subject.send(progressManeger.count)
                    task.updateTitle(task.title, subtitle: "Done")
                }
                catch {
                    print(error)
                    wasExpired = true
                }
                stream.isLive = false
            }
        }

        guard success else {
            try? FileManager.default.removeItem(at: outUrl)
            return
        }

        // Submit the task request.
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to submit request: \(error)")
            try? FileManager.default.removeItem(at: outUrl)
        }
        await semaphore.wait()
    }
}

#Preview {
    DownloadProgressUIView()
}

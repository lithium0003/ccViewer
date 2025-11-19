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

struct UploadProgressUIView: View {
    @State var errors: [URL] = []
    @State var urls: [URL] = []
    @State var names: [URL: String] = [:]
    @State var progress: [URL: Double] = [:]

    @State var cancellables = Set<AnyCancellable>()
    
    @State var isPresented = false
    
    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Text("\(Image("up").renderingMode(.template)) \(urls.count)")
            if !errors.isEmpty {
                Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(errors.count)")
            }
        }
        .sheet(isPresented: $isPresented) {
            ScrollView {
                LazyVStack(pinnedViews: .sectionHeaders) {
                    if !errors.isEmpty {
                        Section {
                            ForEach(errors, id: \.self) { url in
                                if let name = names[url] {
                                    HStack {
                                        Text(verbatim: name)
                                        Spacer()
                                        Button {
                                            Task {
                                                await UploadProgressManeger.shared.remove(url: url)
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                    .listRowBackground(Color.clear)
                                    .padding()
                                }
                            }
                        } header: {
                            Text("Upload failed")
                                .font(.title)
                                .padding()
                        }
                    }
                    if !urls.isEmpty {
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
                                                await UploadProgressManeger.shared.progressManeger.cancel(url: url)
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
                            Text("\(urls.count) files are uploading...")
                                .font(.title)
                                .padding()
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .task {
            UploadProgressManeger.shared.subject
                .sink { _ in
                    Task {
                        (urls, errors, names, progress) = await UploadProgressManeger.shared.progressManeger.get()
                    }
                }
                .store(in: &cancellables)
        }
    }
}

@Observable
class UploadProgressManeger {
    private static let _shared = UploadProgressManeger()
    public static var shared: UploadProgressManeger { return _shared }

    let bundleId = Bundle.main.bundleIdentifier!

    private init() {
    }

    let subject = PassthroughSubject<Int, Never>()

    actor ProgressManeger {
        private var urls: [URL] = []
        private var names: [URL: String] = [:]
        private var progress: [URL: Double] = [:]
        private var cancelList = Set<URL>()
        private var failedUrls: [URL] = []

        var count: Int {
            urls.count
        }

        var errors: Int {
            failedUrls.count
        }

        func get() -> ([URL], [URL], [URL:String], [URL:Double]) {
            return (urls, failedUrls, names, progress)
        }

        func isPresent() -> Bool {
            count + errors > 0
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
            if let index = urls.firstIndex(of: url) {
                urls.remove(at: index)
            }
            cancelList.remove(url)
            if let index = failedUrls.firstIndex(of: url) {
                failedUrls.remove(at: index)
            }
        }
        
        func error(url: URL) {
            progress.removeValue(forKey: url)
            urls.remove(at: urls.firstIndex(of: url)!)
            cancelList.remove(url)
            if !failedUrls.contains(url) {
                failedUrls.append(url)
            }
        }

        func setProgress(url: URL, p: Double) {
            progress[url] = p
        }
        
        func cancel(url: URL) {
            cancelList.insert(url)
        }
    }
    public let progressManeger = ProgressManeger()

    func remove(url: URL) async {
        await progressManeger.delete(url: url)
        await subject.send(progressManeger.count)
    }
    
    @concurrent
    public func upload_mac(url: URL, service: RemoteStorage, parentId: String, uploadname: String) async {
        await progressManeger.add(url: url, name: uploadname)
        await subject.send(progressManeger.count)
        do {
            _ = try await service.upload(parentId: parentId, uploadname: uploadname, target: url) { [self] current, total in
                if await progressManeger.isCenceled(url: url) {
                    throw CancellationError()
                }
                let p = Double(current) / Double(total)
                await progressManeger.setProgress(url: url, p: p)
                await subject.send(progressManeger.count)
            }
            await progressManeger.setProgress(url: url, p: 1)
            await subject.send(progressManeger.count)

            await progressManeger.delete(url: url)
            await subject.send(progressManeger.count)
        }
        catch {
            print(error)

            await progressManeger.error(url: url)
            await subject.send(progressManeger.count)
        }
    }
    
    @concurrent
    public func upload(url: URL, service: RemoteStorage, parentId: String, uploadname: String) async {
        if ProcessInfo.processInfo.isiOSAppOnMac || !UserDefaults.standard.bool(forKey: "uploadInBackground") {
            await upload_mac(url: url, service: service, parentId: parentId, uploadname: uploadname)
            return
        }

        let taskName = UUID().uuidString
        let taskIdentifier = "\(bundleId).upload.\(taskName)"

        let request = BGContinuedProcessingTaskRequest(
            identifier: taskIdentifier,
            title: uploadname,
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

                await progressManeger.add(url: url, name: uploadname)
                await subject.send(progressManeger.count)
                // Update progress.
                let progress = task.progress
                do {
                    _ = try await service.upload(parentId: parentId, uploadname: uploadname, target: url) { [self] current, total in
                        if await progressManeger.isCenceled(url: url) {
                            throw CancellationError()
                        }
                        if wasExpired {
                            throw CancellationError()
                        }
                        progress.totalUnitCount = total
                        progress.completedUnitCount = current
                        let formattedProgress = String(format: "%.2f", progress.fractionCompleted * 100)
                        task.updateTitle(task.title, subtitle: "Uploaded \(formattedProgress)%")
                        let p = Double(current) / Double(total)
                        await progressManeger.setProgress(url: url, p: p)
                        await subject.send(progressManeger.count)
                    }
                    await progressManeger.setProgress(url: url, p: 1)
                    await subject.send(progressManeger.count)
                    task.updateTitle(task.title, subtitle: "Done")

                    await progressManeger.delete(url: url)
                    await subject.send(progressManeger.count)
                    task.setTaskCompleted(success: !wasExpired)
                }
                catch {
                    print(error)

                    await progressManeger.error(url: url)
                    await subject.send(progressManeger.count)
                    task.setTaskCompleted(success: false)
                }
            }
        }

        guard success else {
            return
        }

        // Submit the task request.
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to submit request: \(error)")
        }
        await semaphore.wait()
    }
}

#Preview {
    UploadProgressUIView()
}

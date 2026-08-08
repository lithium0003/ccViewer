//
//  FilesStorage.swift
//  RemoteCloud
//
//  Created by rei8 on 2019/12/02.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreData
import os.log
import UIKit
import CoreServices
internal import UniformTypeIdentifiers
import SwiftUI
import AuthenticationServices

struct FileStorageSelectUIView: View {
    @State private var showFileImporter = false

    let authContinuation: CheckedContinuation<Bool, Never>
    let save: (Data) async -> Void
    @State private var opened = false
    
    var body: some View {
        Color.clear
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.folder]) { result in
                opened = true
                switch result {
                case .success(let url):
                    print(url)
                    Task {
                        do {
                            // Start accessing a security-scoped resource.
                            guard url.startAccessingSecurityScopedResource() else {
                                // Handle the failure here.
                                authContinuation.resume(returning: false)
                                return
                            }
                            
                            // Make sure you release the security-scoped resource when you are done.
                            defer { url.stopAccessingSecurityScopedResource() }
                            
                            let bookmarkData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                            
                            await save(bookmarkData)
                            
                            authContinuation.resume(returning: true)
                        }
                        catch let error {
                            // Handle the error here.
                            print(error)
                            authContinuation.resume(returning: false)
                        }
                    }
                case .failure(let error):
                    print(error)
                    authContinuation.resume(returning: false)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(200))
                showFileImporter = true
            }
            .onChange(of: showFileImporter) { oldValue, newValue in
                if oldValue, !newValue, !opened {
                    authContinuation.resume(returning: false)
                }
            }
    }
}

public class FilesStorage: RemoteStorageBase {
    
    public override func getStorageType() -> CloudStorages {
        return .Files
    }
    
    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .Files)
        storageName = name
    }
    
    var cache_bookmarkData = Data()
    func bookmarkData() async -> Data {
        if let name = storageName {
            if let base64 = await getKeyChain(key: "\(name)_bookmarkData"), let bookmark = Data(base64Encoded: base64) {
                cache_bookmarkData = bookmark
            }
            return cache_bookmarkData
        }
        else {
            return Data()
        }
    }
    
    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        os_log("%{public}@", log: log, type: .debug, "auth(files:\(storageName ?? ""))")
        
        let authRet = await withCheckedContinuation { authContinuation in
            Task {
                let presentRet = await withCheckedContinuation { continuation in
                    callback(FileStorageSelectUIView(authContinuation: authContinuation) { bookmarkData in
                        let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
                    }, continuation)
                }
                guard presentRet else {
                    authContinuation.resume(returning: false)
                    return
                }
            }
        }
        return authRet
    }
    
    public override func logout() async {
        if let name = storageName {
            let _ = await delKeyChain(key: "\(name)_bookmarkData")
        }
        await super.logout()
    }
    
    override func listChildren(fileId: String = "", path: String = "") async {
        do {
            var isStale = false
            let url = try await URL(resolvingBookmarkData: bookmarkData(), bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("url is Stale", url)
                let bookmarkData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            var error: NSError? = nil
            let storage = storageName ?? ""
            
            return await withCheckedContinuation { continuation in
                NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { (baseUrl) in
                    var targetURL = baseUrl
                    if fileId != "" {
                        targetURL.appendPathComponent(fileId, conformingTo: .data)
                    }
                    
                    guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: nil) else {
                        continuation.resume()
                        return
                    }
                    
                    let viewContext = CloudFactory.shared.data.backgroundContext
                    Task {
                        await viewContext.perform {
                            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", fileId, storage)
                            let existingResults = (try? viewContext.fetch(fetchRequest)) ?? []
                            
                            var existingDict = existingResults.reduce(into: [String: RemoteData]()) { dict, item in
                                if let id = item.id { dict[id] = item }
                            }
                            
                            for fileURL in fileURLs {
                                guard let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false)),
                                      let t = attr[.type] as? FileAttributeType, (t == .typeRegular || t == .typeDirectory) else {
                                    continue
                                }
                                
                                guard let id = FilesStorage.getIdFromURL(url: fileURL, baseUrl: baseUrl) else { continue }
                                let name = fileURL.lastPathComponent.precomposedStringWithCanonicalMapping
                                let targetItem: RemoteData
                                
                                if let existing = existingDict.removeValue(forKey: id) {
                                    targetItem = existing
                                    targetItem.baseId = nil
                                    targetItem.baseStorage = nil
                                    targetItem.hashstr = nil
                                    targetItem.subinfo = nil
                                    targetItem.subid = nil
                                    targetItem.substart = 0
                                    targetItem.subend = 0
                                } else {
                                    targetItem = RemoteData(context: viewContext)
                                }
                                
                                targetItem.storage = storage
                                targetItem.id = id
                                targetItem.name = name
                                
                                let comp = name.components(separatedBy: ".")
                                if comp.count > 1 && t != .typeDirectory {
                                    targetItem.ext = comp.last!.lowercased()
                                } else {
                                    targetItem.ext = ""
                                }
                                
                                targetItem.cdate = attr[.creationDate] as? Date
                                targetItem.mdate = attr[.modificationDate] as? Date
                                targetItem.folder = (t == .typeDirectory)
                                targetItem.size = attr[.size] as? NSNumber as? Int64 ?? 0
                                targetItem.parent = fileId
                                
                                if fileId == "" {
                                    targetItem.path = "\(storage):/\(name)"
                                } else {
                                    targetItem.path = "\(path)/\(name)"
                                }
                            }
                            
                            for staleItem in existingDict.values {
                                RemoteStorageBase.cascadeDelete(item: staleItem, in: viewContext)
                            }
                            
                            try? viewContext.save()
                        }
                        continuation.resume()
                    }
                }
            }
        }
        catch let error {
            print(error)
        }
    }
    
    class func getIdFromURL(url: URL, baseUrl: URL) -> String? {
        let base = baseUrl.pathComponents
        let target = url.pathComponents
        guard base.count <= target.count else { return nil }
        for i in 0..<base.count {
            guard base[i] == target[i] else { return nil }
        }
        return target.dropFirst(base.count).joined(separator: "/")
    }
    
    class func storeItem(item: URL, baseUrl: URL, parentFileId: String? = nil, parentPath: String? = nil, storageName: String, context: NSManagedObjectContext) {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: item.path(percentEncoded: false)) else { return }
        guard let t = attr[.type] as? FileAttributeType, (t == .typeRegular || t == .typeDirectory) else { return }
        guard let id = FilesStorage.getIdFromURL(url: item, baseUrl: baseUrl) else { return }
        
        let name = item.lastPathComponent.precomposedStringWithCanonicalMapping
        
        let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, storageName)
        fetchRequest.fetchLimit = 1
        
        let existingItem = try? context.fetch(fetchRequest).first
        let targetItem = existingItem ?? RemoteData(context: context)
        
        let prevParent = targetItem.parent
        let prevPath = targetItem.path
        
        if existingItem != nil {
            targetItem.baseId = nil
            targetItem.baseStorage = nil
            targetItem.hashstr = nil
            targetItem.subinfo = nil
            targetItem.subid = nil
            targetItem.substart = 0
            targetItem.subend = 0
        }
        
        targetItem.storage = storageName
        targetItem.id = id
        targetItem.name = name
        let comp = name.components(separatedBy: ".")
        if comp.count > 1 && t != .typeDirectory {
            targetItem.ext = comp.last!.lowercased()
        } else {
            targetItem.ext = ""
        }
        targetItem.cdate = attr[.creationDate] as? Date
        targetItem.mdate = attr[.modificationDate] as? Date
        targetItem.folder = (t == .typeDirectory)
        targetItem.size = attr[.size] as? NSNumber as? Int64 ?? 0
        
        targetItem.parent = (parentFileId == nil) ? prevParent : parentFileId
        if parentFileId == "" {
            targetItem.path = "\(storageName):/\(name)"
        } else if let path = (parentPath == nil) ? prevPath : parentPath {
            targetItem.path = "\(path)/\(name)"
        }
    }
    
    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil) async -> Data? {
        if let cache = await CloudFactory.shared.cache.getCache(storage: storageName!, id: fileId, offset: start ?? 0, size: length ?? -1) {
            if let data = try? Data(contentsOf: cache) {
                os_log("%{public}@", log: log, type: .debug, "hit cache(File:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                return data
            }
        }
        
        os_log("%{public}@", log: log, type: .debug, "readFile(File:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
        
        do {
            var isStale = false
            let url = try await URL(resolvingBookmarkData: bookmarkData(), bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("url is Stale", url)
                // Handle stale data here.
                let bookmarkData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            // Use the URL here.
            
            // Start accessing a security-scoped resource.
            guard url.startAccessingSecurityScopedResource() else {
                // Handle the failure here.
                return nil
            }
            
            // Make sure you release the security-scoped resource when you are done.
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Use file coordination for reading and writing any of the URL’s content.
            var error: NSError? = nil
            return await withCheckedContinuation { continuation in
                NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { (url) in
                    var targetURL = url
                    if fileId != "" {
                        targetURL.appendPathComponent(fileId, conformingTo: .data)
                    }
                    
                    // Start accessing a security-scoped resource.
                    guard url.startAccessingSecurityScopedResource() else {
                        // Handle the failure here.
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Make sure you release the security-scoped resource when you are done.
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    var ret: Data?
                    let reqOffset = Int(start ?? 0)
                    do {
                        let hFile = try FileHandle(forReadingFrom: targetURL)
                        defer {
                            do {
                                try hFile.close()
                            }
                            catch {
                                print(error)
                            }
                        }
                        try hFile.seek(toOffset: UInt64(reqOffset))
                        if let size = length {
                            ret = hFile.readData(ofLength: Int(size))
                        }
                        else {
                            ret = hFile.readDataToEndOfFile()
                        }
                    }
                    catch {
                        print(error)
                    }
                    if let d = ret {
                        Task {
                            await CloudFactory.shared.cache.saveCache(storage: self.storageName!, id: fileId, offset: start ?? 0, data: d)
                        }
                    }
                    continuation.resume(returning: ret)
                }
            }
        }
        catch let error {
            // Handle the error here.
            print(error)
            return nil
        }
    }
    
    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await NetworkRemoteItem(path: path)
    }
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        os_log("%{public}@", log: log, type: .debug, "makeFolder(File:\(storageName ?? "") \(parentId) \(newname)")
        do {
            var isStale = false
            let url = try await URL(resolvingBookmarkData: bookmarkData(), bookmarkDataIsStale: &isStale)
            
            if isStale {
                let bookmarkData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            guard url.startAccessingSecurityScopedResource() else { return nil }
            defer { url.stopAccessingSecurityScopedResource() }
            
            var error: NSError? = nil
            let storage = storageName ?? ""
            return await withCheckedContinuation { continuation in
                NSFileCoordinator().coordinate(writingItemAt: url, error: &error) { (baseUrl) in
                    var targetURL = baseUrl
                    if parentId != "" {
                        targetURL = targetURL.appendingPathComponent(parentId, isDirectory: true)
                    }
                    targetURL = targetURL.appendingPathComponent(newname, isDirectory: true)
                    
                    do {
                        guard baseUrl.startAccessingSecurityScopedResource() else {
                            continuation.resume(returning: nil)
                            return
                        }
                        defer { baseUrl.stopAccessingSecurityScopedResource() }
                        
                        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: false)
                        let viewContext = CloudFactory.shared.data.backgroundContext
                        Task {
                            await viewContext.perform {
                                FilesStorage.storeItem(item: targetURL, baseUrl: baseUrl, parentFileId: parentId, parentPath: parentPath, storageName: storage, context: viewContext)
                                try? viewContext.save()
                            }
                            let id = FilesStorage.getIdFromURL(url: targetURL, baseUrl: baseUrl)
                            continuation.resume(returning: id)
                        }
                    }
                    catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        catch let error {
            print(error)
            return nil
        }
    }
    
    override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        do {
            if fromParentId == toParentId { return nil }
            var isStale = false
            let url = try await URL(resolvingBookmarkData: bookmarkData(), bookmarkDataIsStale: &isStale)
            
            if isStale {
                let bookmarkData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            var targetURL = url
            var parentPath = ""
            if toParentId != "" {
                targetURL = url.appending(path: toParentId)
                parentPath = await getParentPath(parentId: toParentId) ?? ""
            }
            let fromURL = url.appending(path: fileId)
            let name = fromURL.lastPathComponent
            
            guard url.startAccessingSecurityScopedResource() else { return nil }
            defer { url.stopAccessingSecurityScopedResource() }
            
            var error: NSError? = nil
            let storage = storageName ?? ""
            return await withCheckedContinuation { continuation in
                NSFileCoordinator().coordinate(writingItemAt: url, error: &error) { (baseUrl) in
                    guard baseUrl.startAccessingSecurityScopedResource() else {
                        continuation.resume(returning: nil)
                        return
                    }
                    defer { baseUrl.stopAccessingSecurityScopedResource() }
                    
                    targetURL = targetURL.appendingPathComponent(name)
                    os_log("%{public}@", log: self.log, type: .debug, "moveItem(File:\(storage) \(fromParentId)->\(toParentId)")
                    
                    do {
                        try FileManager.default.moveItem(at: fromURL, to: targetURL)
                        let viewContext = CloudFactory.shared.data.backgroundContext
                        Task {
                            await viewContext.perform {
                                let fetchRequest2 = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                                fetchRequest2.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                                if let results = try? viewContext.fetch(fetchRequest2) {
                                    for object in results {
                                        RemoteStorageBase.cascadeDelete(item: object, in: viewContext)
                                    }
                                }
                                FilesStorage.storeItem(item: targetURL, baseUrl: baseUrl, parentFileId: toParentId, parentPath: parentPath, storageName: storage, context: viewContext)
                                try? viewContext.save()
                            }
                            let id = FilesStorage.getIdFromURL(url: targetURL, baseUrl: baseUrl)
                            await CloudFactory.shared.cache.remove(storage: storage, id: fileId)
                            continuation.resume(returning: id)
                        }
                    }
                    catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        catch let error {
            print(error)
            return nil
        }
    }
    
    override func deleteItem(fileId: String) async -> Bool {
        os_log("%{public}@", log: log, type: .debug, "deleteItem(File:\(storageName ?? "") \(fileId)")
        do {
            var isStale = false
            let url = try await URL(resolvingBookmarkData: bookmarkData(), bookmarkDataIsStale: &isStale)
            
            if isStale {
                let bookmarkData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            guard url.startAccessingSecurityScopedResource() else { return false }
            defer { url.stopAccessingSecurityScopedResource() }
            
            var error: NSError? = nil
            let storage = storageName ?? ""
            return await withCheckedContinuation { continuation in
                NSFileCoordinator().coordinate(writingItemAt: url, error: &error) { (baseUrl) in
                    var targetURL = baseUrl
                    targetURL.appendPathComponent(fileId, conformingTo: .data)
                    
                    guard baseUrl.startAccessingSecurityScopedResource() else {
                        continuation.resume(returning: false)
                        return
                    }
                    defer { baseUrl.stopAccessingSecurityScopedResource() }
                    
                    do {
                        try FileManager.default.removeItem(at: targetURL)
                        let viewContext = CloudFactory.shared.data.backgroundContext
                        Task {
                            await viewContext.perform {
                                let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                                if let results = try? viewContext.fetch(fetchRequest) {
                                    for object in results {
                                        RemoteStorageBase.cascadeDelete(item: object, in: viewContext)
                                    }
                                }
                                try? viewContext.save()
                            }
                            await CloudFactory.shared.cache.remove(storage: storage, id: fileId)
                            continuation.resume(returning: true)
                        }
                    }
                    catch {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
        catch let error {
            print(error)
            return false
        }
    }
    
    override func renameItem(fileId: String, newname: String) async -> String? {
        os_log("%{public}@", log: log, type: .debug, "renameItem(File:\(storageName ?? "") \(fileId)")
        do {
            var isStale = false
            let url = try await URL(resolvingBookmarkData: bookmarkData(), bookmarkDataIsStale: &isStale)
            
            if isStale {
                let bookmarkData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            guard url.startAccessingSecurityScopedResource() else { return nil }
            defer { url.stopAccessingSecurityScopedResource() }
            
            var error: NSError? = nil
            let storage = storageName ?? ""
            return await withCheckedContinuation { continuation in
                NSFileCoordinator().coordinate(writingItemAt: url, error: &error) { (baseUrl) in
                    let fromURL = baseUrl.appendingPathComponent(fileId)
                    let newURL = fromURL.deletingLastPathComponent().appendingPathComponent(newname)
                    
                    guard baseUrl.startAccessingSecurityScopedResource() else {
                        continuation.resume(returning: nil)
                        return
                    }
                    defer { baseUrl.stopAccessingSecurityScopedResource() }
                    
                    do {
                        try FileManager.default.moveItem(at: fromURL, to: newURL)
                        let viewContext = CloudFactory.shared.data.backgroundContext
                        Task {
                            var parentPath: String?
                            var parentId: String?
                            await viewContext.perform {
                                let fetchRequest2 = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                                fetchRequest2.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                                if let results = try? viewContext.fetch(fetchRequest2) {
                                    for object in results {
                                        parentPath = object.path
                                        let component = parentPath?.components(separatedBy: "/")
                                        parentPath = component?.dropLast().joined(separator: "/")
                                        parentId = object.parent
                                        RemoteStorageBase.cascadeDelete(item: object, in: viewContext)
                                    }
                                }
                                FilesStorage.storeItem(item: newURL, baseUrl: baseUrl, parentFileId: parentId, parentPath: parentPath, storageName: storage, context: viewContext)
                                try? viewContext.save()
                            }
                            let id = FilesStorage.getIdFromURL(url: newURL, baseUrl: baseUrl)
                            await CloudFactory.shared.cache.remove(storage: storage, id: fileId)
                            continuation.resume(returning: id)
                        }
                    }
                    catch {
                        print(error)
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        catch let error {
            print(error)
            return nil
        }
    }
    
    override func changeTime(fileId: String, newdate: Date) async -> String? {
        os_log("%{public}@", log: log, type: .debug, "changeTime(File:\(storageName ?? "") \(fileId) \(newdate)")
        do {
            var isStale = false
            let url = try await URL(resolvingBookmarkData: bookmarkData(), bookmarkDataIsStale: &isStale)
            
            if isStale {
                let bookmarkData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            guard url.startAccessingSecurityScopedResource() else { return nil }
            defer { url.stopAccessingSecurityScopedResource() }
            
            var error: NSError? = nil
            let storage = storageName ?? ""
            return await withCheckedContinuation { continuation in
                NSFileCoordinator().coordinate(writingItemAt: url, error: &error) { (baseUrl) in
                    let targetURL = baseUrl.appendingPathComponent(fileId)
                    
                    guard baseUrl.startAccessingSecurityScopedResource() else {
                        continuation.resume(returning: nil)
                        return
                    }
                    defer { baseUrl.stopAccessingSecurityScopedResource() }
                    
                    do {
                        try FileManager.default.setAttributes([FileAttributeKey.modificationDate: newdate], ofItemAtPath: targetURL.path(percentEncoded: false))
                        let viewContext = CloudFactory.shared.data.backgroundContext
                        Task {
                            await viewContext.perform {
                                FilesStorage.storeItem(item: targetURL, baseUrl: baseUrl, storageName: storage, context: viewContext)
                                try? viewContext.save()
                            }
                            let id = FilesStorage.getIdFromURL(url: targetURL, baseUrl: baseUrl)
                            continuation.resume(returning: id)
                        }
                    }
                    catch {
                        print(error)
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        catch let error {
            print(error)
            return nil
        }
    }
    
    override func uploadFile(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        var parentPath = ""
        if parentId != "" {
            parentPath = await getParentPath(parentId: parentId) ?? ""
        }
        
        os_log("%{public}@", log: log, type: .debug, "uploadFile(File:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")
        
        var isStale = false
        let url = try await URL(resolvingBookmarkData: bookmarkData(), bookmarkDataIsStale: &isStale)
        
        if isStale {
            let bookmarkData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
            let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
        }
        
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        
        var error: NSError? = nil
        let storage = storageName ?? ""
        return await withCheckedContinuation { continuation in
            NSFileCoordinator().coordinate(writingItemAt: url, error: &error) { (baseUrl) in
                var newURL = baseUrl
                if parentId != "" {
                    newURL = baseUrl.appendingPathComponent(parentId)
                }
                newURL = newURL.appendingPathComponent(uploadname)
                
                guard baseUrl.startAccessingSecurityScopedResource() else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { baseUrl.stopAccessingSecurityScopedResource() }
                
                do {
                    let attr = try FileManager.default.attributesOfItem(atPath: target.path(percentEncoded: false))
                    let fileSize = attr[.size] as! UInt64
                    Task { try await progress?(0, Int64(fileSize)) }
                    
                    try FileManager.default.moveItem(at: target, to: newURL)
                    
                    let viewContext = CloudFactory.shared.data.backgroundContext
                    Task {
                        await viewContext.perform {
                            FilesStorage.storeItem(item: newURL, baseUrl: baseUrl, parentFileId: parentId, parentPath: parentPath, storageName: storage, context: viewContext)
                            try? viewContext.save()
                        }
                        let id = FilesStorage.getIdFromURL(url: newURL, baseUrl: baseUrl)
                        continuation.resume(returning: id)
                        try await progress?(Int64(fileSize), Int64(fileSize))
                    }
                }
                catch {
                    print(error)
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

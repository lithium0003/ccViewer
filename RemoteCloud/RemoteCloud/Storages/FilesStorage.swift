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

public class FilesStorage: RemoteStorageBase  {

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
                // Handle stale data here.
                let bookmarkData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            // Use the URL here.

            // Start accessing a security-scoped resource.
            guard url.startAccessingSecurityScopedResource() else {
                // Handle the failure here.
                return
            }

            // Make sure you release the security-scoped resource when you are done.
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Use file coordination for reading and writing any of the URL’s content.
            var error: NSError? = nil
            let storage = storageName ?? ""
            return await withCheckedContinuation { continuation in
                NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { (url) in
                    var targetURL = url
                    if fileId != "" {
                        targetURL.appendPathComponent(fileId, conformingTo: .data)
                    }
                    
                    guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: nil) else {
                        continuation.resume()
                        return
                    }
                    
                    let viewContext = CloudFactory.shared.data.viewContext
                    Task {
                        await viewContext.perform {
                            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", fileId, storage)
                            if let result = try? viewContext.fetch(fetchRequest) {
                                for object in result {
                                    viewContext.delete(object as! NSManagedObject)
                                }
                            }
                        }
                        for fileURL in fileURLs {
                            await storeItem(item: fileURL, parentFileId: fileId, parentPath: path, context: viewContext)
                        }
                        await viewContext.perform {
                            try? viewContext.save()
                        }
                        continuation.resume()
                    }
                }
            }
        }
        catch let error {
            // Handle the error here.
            print(error)
        }
    }
    
    func getIdFromURL(url: URL) async -> String? {
        var isStale = false
        guard let baseUrl = try? await URL(resolvingBookmarkData: bookmarkData(), bookmarkDataIsStale: &isStale) else {
            return nil
        }
        guard !isStale else {
            return nil
        }
        
        let base = baseUrl.pathComponents
        let target = url.pathComponents
        guard base.count <= target.count else {
            return nil
        }
        for i in 0..<base.count {
            guard base[i] == target[i] else {
                return nil
            }
        }
        return target.dropFirst(base.count).joined(separator: "/")
    }

    func storeItem(item: URL, parentFileId: String? = nil, parentPath: String? = nil, context: NSManagedObjectContext) async {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: item.path(percentEncoded: false)) else {
            return
        }
        guard let id = await getIdFromURL(url: item) else {
            return
        }
        let name = item.lastPathComponent.precomposedStringWithCanonicalMapping
        let storage = storageName ?? ""
        context.performAndWait {
            var prevParent: String?
            var prevPath: String?
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, storage)
            if let result = try? context.fetch(fetchRequest) {
                for object in result {
                    if let item = object as? RemoteData {
                        prevPath = item.path
                        let component = parentPath?.components(separatedBy: "/")
                        prevPath = component?.dropLast().joined(separator: "/")
                        prevParent = item.parent
                    }
                    context.delete(object as! NSManagedObject)
                }
            }
            
            guard let t = attr[.type] as? FileAttributeType else {
                return
            }
            guard t == .typeRegular || t == .typeDirectory else {
                return
            }
            let newitem = RemoteData(context: context)
            newitem.storage = storage
            newitem.id = id
            newitem.name = name
            let comp = name.components(separatedBy: ".")
            if comp.count >= 1 {
                newitem.ext = comp.last!.lowercased()
            }
            newitem.cdate = attr[.creationDate] as? Date
            newitem.mdate = attr[.modificationDate] as? Date
            newitem.folder = (attr[.type] as? FileAttributeType) == .typeDirectory
            newitem.size = attr[.size] as? NSNumber as? Int64 ?? 0
            newitem.hashstr = ""
            newitem.parent = (parentFileId == nil) ? prevParent : parentFileId
            if parentFileId == "" {
                newitem.path = "\(storage):/\(name)"
            }
            else {
                if let path = (parentPath == nil) ? prevPath : parentPath {
                    newitem.path = "\(path)/\(name)"
                }
            }
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
                NSFileCoordinator().coordinate(writingItemAt: url, error: &error) { (url) in
                    
                    var targetURL = url
                    if parentId != "" {
                        targetURL = targetURL.appendingPathComponent(parentId, isDirectory: true)
                    }
                    targetURL = targetURL.appendingPathComponent(newname, isDirectory: true)
                    
                    do {
                        // Start accessing a security-scoped resource.
                        guard url.startAccessingSecurityScopedResource() else {
                            // Handle the failure here.
                            continuation.resume(returning: nil)
                            return
                        }
                        
                        // Make sure you release the security-scoped resource when you are done.
                        defer { url.stopAccessingSecurityScopedResource() }
                        
                        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: false)
                        let viewContext = CloudFactory.shared.data.viewContext
                        Task {
                            await storeItem(item: targetURL, parentFileId: parentId, parentPath: parentPath, context: viewContext)
                            await viewContext.perform {
                                try? viewContext.save()
                            }
                            let id = await getIdFromURL(url: targetURL)
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
            // Handle the error here.
            print(error)
            return nil
        }
    }

    override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        do {
            if fromParentId == toParentId {
                return nil
            }
            
            var isStale = false
            let url = try await URL(resolvingBookmarkData: bookmarkData(), bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("url is Stale", url)
                // Handle stale data here.
                let bookmarkData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            // Use the URL here.
            var targetURL = url
            var parentPath = ""
            if toParentId != "" {
                targetURL = url.appending(path: toParentId)
                parentPath = await getParentPath(parentId: toParentId) ?? ""
            }
            let fromURL = url.appending(path: fileId)
            let name = fromURL.lastPathComponent

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
                NSFileCoordinator().coordinate(writingItemAt: url, error: &error) { (url) in
                    
                    // Start accessing a security-scoped resource.
                    guard url.startAccessingSecurityScopedResource() else {
                        // Handle the failure here.
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Make sure you release the security-scoped resource when you are done.
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    let viewContext = CloudFactory.shared.data.viewContext
                    viewContext.performAndWait {
                        let fetchRequest2 = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                        fetchRequest2.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                        if let result = try? viewContext.fetch(fetchRequest2) {
                            for object in result {
                                viewContext.delete(object as! NSManagedObject)
                            }
                        }
                    }
                    targetURL = targetURL.appendingPathComponent(name)
                    
                    os_log("%{public}@", log: self.log, type: .debug, "moveItem(File:\(self.storageName ?? "") \(fromParentId)->\(toParentId)")
                    
                    do {
                        try FileManager.default.moveItem(at: fromURL, to: targetURL)
                        Task {
                            await self.storeItem(item: targetURL, parentFileId: toParentId, parentPath: parentPath, context: viewContext)
                            await viewContext.perform {
                                try? viewContext.save()
                            }
                            let id = await self.getIdFromURL(url: targetURL)
                            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
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
            // Handle the error here.
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
                print("url is Stale", url)
                // Handle stale data here.
                let bookmarkData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            // Use the URL here.

            // Start accessing a security-scoped resource.
            guard url.startAccessingSecurityScopedResource() else {
                // Handle the failure here.
                return false
            }

            // Make sure you release the security-scoped resource when you are done.
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Use file coordination for reading and writing any of the URL’s content.
            var error: NSError? = nil
            return await withCheckedContinuation { continuation in
                NSFileCoordinator().coordinate(writingItemAt: url, error: &error) { (url) in
                    
                    var targetURL = url
                    targetURL.appendPathComponent(fileId, conformingTo: .data)
                    
                    guard url.startAccessingSecurityScopedResource() else {
                        // Handle the failure here.
                        continuation.resume(returning: false)
                        return
                    }
                    
                    // Make sure you release the security-scoped resource when you are done.
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    do {
                        try FileManager.default.removeItem(at: targetURL)
                        let viewContext = CloudFactory.shared.data.viewContext
                        viewContext.perform {
                            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                            if let result = try? viewContext.fetch(fetchRequest) {
                                for object in result {
                                    viewContext.delete(object as! NSManagedObject)
                                }
                            }
                        }
                        self.deleteChildRecursive(parent: fileId, context: viewContext)
                        Task {
                            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
                        }
                        viewContext.perform {
                            try? viewContext.save()
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
            // Handle the error here.
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
                NSFileCoordinator().coordinate(writingItemAt: url, error: &error) { (url) in
                    
                    let fromURL = url.appendingPathComponent(fileId)
                    let newURL = fromURL.deletingLastPathComponent().appendingPathComponent(newname)
                    
                    guard url.startAccessingSecurityScopedResource() else {
                        // Handle the failure here.
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Make sure you release the security-scoped resource when you are done.
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    do {
                        try FileManager.default.moveItem(at: fromURL, to: newURL)
                        var parentPath: String?
                        var parentId: String?
                        let viewContext = CloudFactory.shared.data.viewContext
                        viewContext.perform {
                            let fetchRequest2 = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                            fetchRequest2.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                            if let result = try? viewContext.fetch(fetchRequest2) as? [RemoteData] {
                                for object in result {
                                    parentPath = object.path
                                    let component = parentPath?.components(separatedBy: "/")
                                    parentPath = component?.dropLast().joined(separator: "/")
                                    parentId = object.parent
                                    viewContext.delete(object)
                                }
                            }
                        }
                        Task {
                            await self.storeItem(item: newURL, parentFileId: parentId, parentPath: parentPath, context: viewContext)
                            await viewContext.perform {
                                try? viewContext.save()
                            }
                            let id = await self.getIdFromURL(url: newURL)
                            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
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
            // Handle the error here.
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
                NSFileCoordinator().coordinate(writingItemAt: url, error: &error) { (url) in
                    
                    let targetURL = url.appendingPathComponent(fileId)
                    
                    guard url.startAccessingSecurityScopedResource() else {
                        // Handle the failure here.
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Make sure you release the security-scoped resource when you are done.
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    do {
                        try FileManager.default.setAttributes([FileAttributeKey.modificationDate: newdate], ofItemAtPath: targetURL.path(percentEncoded: false))
                        let viewContext = CloudFactory.shared.data.viewContext
                        Task {
                            await self.storeItem(item: targetURL, context: viewContext)
                            await viewContext.perform {
                                try? viewContext.save()
                            }
                            let id = await getIdFromURL(url: targetURL)
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
            // Handle the error here.
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
            NSFileCoordinator().coordinate(writingItemAt: url, error: &error) { (url) in
                
                var newURL = url
                if parentId != "" {
                    newURL = url.appendingPathComponent(parentId)
                }
                newURL = newURL.appendingPathComponent(uploadname)
                
                guard url.startAccessingSecurityScopedResource() else {
                    // Handle the failure here.
                    continuation.resume(returning: nil)
                    return
                }
                
                // Make sure you release the security-scoped resource when you are done.
                defer { url.stopAccessingSecurityScopedResource() }
                
                do {
                    let attr = try FileManager.default.attributesOfItem(atPath: target.path(percentEncoded: false))
                    let fileSize = attr[.size] as! UInt64
                    Task {
                        try await progress?(0, Int64(fileSize))
                    }

                    try FileManager.default.moveItem(at: target, to: newURL)
                    
                    let viewContext = CloudFactory.shared.data.viewContext
                    Task {
                        await self.storeItem(item: newURL, parentFileId: parentId, parentPath: parentPath, context: viewContext)
                        await viewContext.perform {
                            try? viewContext.save()
                        }
                        let id = await self.getIdFromURL(url: newURL)
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

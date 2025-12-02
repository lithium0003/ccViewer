//
//  FileCache.swift
//  RemoteCloud
//
//  Created by rei8 on 2019/11/20.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreData

public class FileCache {
    public var cacheMaxSize: Int {
        get {
            return UserDefaults.standard.integer(forKey: "networkCacheSize")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "networkCacheSize")
        }
    }

    actor DiskAccesser {
        var cacheSize: UInt64 = 0
        var size: UInt64 {
            get {
                if cacheSize > 0 {
                    return cacheSize
                }
                guard let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "NetCache") else {
                    return 0
                }
                cacheSize = sumTotal(url: base)
                return cacheSize
            }
        }
        
        func removeItem(url: URL) {
            var dir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &dir), dir.boolValue {
                cacheSize = 0
            }
            else if let attr = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)) {
                let filesize = attr[.size] as? UInt64 ?? 0
                if cacheSize > filesize {
                    cacheSize -= filesize
                }
                else {
                    cacheSize = 0
                }
            }
            else {
                cacheSize = 0
            }
            try? FileManager.default.removeItem(at: url)
        }
        
        func write(data: Data, url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try data.write(to: url)
            cacheSize += UInt64(data.count)
        }
        
        func sumTotal(url: URL) -> UInt64 {
            let resourceKeys = Set<URLResourceKey>([.fileSizeKey])
            let directoryEnumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(resourceKeys), options: .skipsHiddenFiles)!
             
            var allocSize: UInt64 = 0
            for case let fileURL as URL in directoryEnumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                    let size = resourceValues.fileSize
                    else {
                        continue
                }
                allocSize += UInt64(size)
            }
            return allocSize
        }
    }
    
    actor CacheAccesser {
        let diskAccesser = DiskAccesser()
        lazy var context = {
            persistentContainer.newBackgroundContext()
        }()

        func getPartialFile(orgItem: RemoteData, offset: Int64, size: Int64) async -> Data? {
            let context = context
            let storage = orgItem.storage ?? ""
            let id = orgItem.id ?? ""
            let mdate = orgItem.mdate
            let orgSize = orgItem.size
            do {
                let targetURL = try await context.perform { () -> URL? in
                    let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
                    fetchrequest.predicate = NSPredicate(format: "storage == %@ && id == %@ && chunkOffset == 0", storage, id)
                    let items = try context.fetch(fetchrequest)
                    guard let item = items.first as? FileCacheItem else {
                        return nil
                    }
                    
                    // update check
                    if mdate != item.mdate || (orgSize > 0 && orgSize != item.orgSize) {
                        if let target = item.filename?.uuidString {
                            let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "NetCache")
                            let target_path = base.appending(path: target.prefix(2)).appending(path: target.prefix(4).suffix(2)).appending(path: target)
                            Task {
                                await self.diskAccesser.removeItem(url: target_path)
                            }
                        }
                        context.delete(item)
                        try context.save()
                        return nil
                    }

                    // hit check
                    if let target = item.filename?.uuidString, item.orgSize == item.chunkSize {
                        let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "NetCache")
                        let target_path = base.appending(path: target.prefix(2)).appending(path: target.prefix(4).suffix(2)).appending(path: target)
                        if FileManager.default.fileExists(atPath: target_path.path(percentEncoded: false)) {
                            item.rdate = Date()
                            try context.save()
                            return target_path
                        }
                        else {
                            context.delete(item)
                            try context.save()
                        }
                    }
                    return nil
                }
                if let target = targetURL {
                    do {
                        let hFile = try FileHandle(forReadingFrom: target)
                        defer {
                            do {
                                try hFile.close()
                            }
                            catch {
                                print(error)
                            }
                        }
                        try hFile.seek(toOffset: UInt64(offset))
                        if size < 0 {
                            return try hFile.readToEnd()
                        }
                        return hFile.readData(ofLength: Int(size))
                    }
                    catch {
                        print(error)
                    }
                }
            }
            catch {
                print(error)
            }
            return nil
        }

        func getCache(orgItem: RemoteData, offset: Int64, size: Int64) async -> URL? {
            let context = context
            let storage = orgItem.storage ?? ""
            let id = orgItem.id ?? ""
            let mdate = orgItem.mdate
            let orgSize = orgItem.size
            do {
                return try await context.perform { () -> URL? in
                    let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
                    fetchrequest.predicate = NSPredicate(format: "storage == %@ && id == %@ && chunkOffset == %lld", storage, id, offset)
                    let items = try context.fetch(fetchrequest)
                    guard let item = items.first as? FileCacheItem else {
                        return nil
                    }
                    
                    // update check
                    if mdate != item.mdate || (orgSize > 0 && orgSize != item.orgSize) {
                        if let target = item.filename?.uuidString {
                            let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "NetCache")
                            let target_path = base.appending(path: target.prefix(2)).appending(path: target.prefix(4).suffix(2)).appending(path: target)
                            Task {
                                await self.diskAccesser.removeItem(url: target_path)
                            }
                        }
                        context.delete(item)
                        try context.save()
                        return nil
                    }

                    // hit check
                    if let target = item.filename?.uuidString, (size < 0 || size == item.chunkSize) {
                        let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "NetCache")
                        let target_path = base.appending(path: target.prefix(2)).appending(path: target.prefix(4).suffix(2)).appending(path: target)
                        if FileManager.default.fileExists(atPath: target_path.path(percentEncoded: false)) {
                            item.rdate = Date()
                            try context.save()
                            return target_path
                        }
                        else {
                            context.delete(item)
                            try context.save()
                        }
                    }
                    return nil
                }
            }
            catch {
                print(error)
            }
            return nil
        }
        
        func remove(orgItem: RemoteData) async {
            let context = context
            let storage = orgItem.storage ?? ""
            let id = orgItem.id ?? ""
            do {
                let filePaths = try await context.perform {
                    var removeFiles: [URL] = []
                    let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
                    fetchrequest.predicate = NSPredicate(format: "storage == %@ && id == %@", storage, id)
                    if let items = try context.fetch(fetchrequest) as? [FileCacheItem], !items.isEmpty {
                        for item in items {
                            if let target = item.filename?.uuidString {
                                let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "NetCache")
                                let target_path = base.appending(path: target.prefix(2)).appending(path: target.prefix(4).suffix(2)).appending(path: target)
                                removeFiles.append(target_path)
                            }
                            context.delete(item)
                        }
                    }
                    return removeFiles
                }
                for url in filePaths {
                    await self.diskAccesser.removeItem(url: url)
                }
            }
            catch {
                print(error)
            }
        }
        
        func saveFile(orgItem: RemoteData, data: Data) async {
            let context = context
            let storage = orgItem.storage ?? ""
            let id = orgItem.id ?? ""
            let mdate = orgItem.mdate
            let orgSize = orgItem.size
            do {
                let size = Int64(data.count)
                let pass = try await context.perform {
                    let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
                    fetchrequest.predicate = NSPredicate(format: "storage == %@ && id == %@ && chunkOffset == 0 && chunkSize == %lld", storage, id, size)
                    if let items = try context.fetch(fetchrequest) as? [FileCacheItem], items.count > 0 {
                        return false
                    }
                    return true
                }
                guard pass else { return }
                let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "NetCache")
                let newId = UUID()
                let target = newId.uuidString
                let target_path = base.appending(path: target.prefix(2)).appending(path: target.prefix(4).suffix(2)).appending(path: target)
                try await self.diskAccesser.write(data: data, url: target_path)
                try await context.perform {
                    let newitem = FileCacheItem(context: context)
                    newitem.filename = newId
                    newitem.storage = storage
                    newitem.id = id
                    newitem.chunkSize = size
                    newitem.chunkOffset = 0
                    newitem.rdate = Date()
                    newitem.mdate = mdate
                    newitem.orgSize = orgSize

                    try context.save()
                }
            }
            catch {
                print(error)
            }
        }
        
        func saveCache(orgItem: RemoteData, offset: Int64, data: Data) async {
            let context = context
            let storage = orgItem.storage ?? ""
            let id = orgItem.id ?? ""
            let mdate = orgItem.mdate
            let orgSize = orgItem.size
            do {
                let size = Int64(data.count)
                let pass = try await context.perform {
                    let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
                    fetchrequest.predicate = NSPredicate(format: "storage == %@ && id == %@ && chunkOffset == %lld && chunkSize == %lld", storage, id, offset, size)
                    if let items = try context.fetch(fetchrequest) as? [FileCacheItem], items.count > 0 {
                        return false
                    }
                    return true
                }
                guard pass else { return }
                let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "NetCache")
                let newId = UUID()
                let target = newId.uuidString
                let target_path = base.appending(path: target.prefix(2)).appending(path: target.prefix(4).suffix(2)).appending(path: target)
                try await self.diskAccesser.write(data: data, url: target_path)
                try await context.perform {
                    let newitem = FileCacheItem(context: context)
                    newitem.filename = newId
                    newitem.storage = storage
                    newitem.id = id
                    newitem.chunkSize = size
                    newitem.chunkOffset = offset
                    newitem.rdate = Date()
                    newitem.mdate = mdate
                    newitem.orgSize = orgSize

                    try context.save()
                }
            }
            catch {
                print(error)
            }
        }
        
        func deleteAllCache() async {
            guard let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "NetCache") else { return }
            await diskAccesser.removeItem(url: base)
            let context = context
            await context.perform {
                let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
                fetchrequest.predicate = NSPredicate(value: true)
                do {
                    if let items = try context.fetch(fetchrequest) as? [FileCacheItem], items.count > 0 {
                        for item in items {
                            context.delete(item)
                        }
                        try context.save()
                    }
                }
                catch {
                    print(error)
                }
            }
        }
        
        func increseFreeSpace(_ incSize: Int) async {
            var delSize = 0
            guard let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "NetCache") else { return }
            let context = context
            var delTarget: [URL] = []
            await context.perform {
                let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
                fetchrequest.predicate = NSPredicate(value: true)
                fetchrequest.sortDescriptors = [NSSortDescriptor(key: "rdate", ascending: true)]
                do {
                    if let items = try context.fetch(fetchrequest) as? [FileCacheItem], items.count > 0 {
                        for item in items {
                            if delSize > incSize {
                                break
                            }
                            guard let target = item.filename?.uuidString else {
                                continue
                            }
                            delSize += Int(item.chunkSize)
                            let target_path = base.appending(path: target.prefix(2)).appending(path: target.prefix(4).suffix(2)).appending(path: target)
                            delTarget.append(target_path)
                            context.delete(item)
                        }
                    }
                    if delSize > 0 {
                        try context.save()
                    }
                }
                catch {
                    print(error)
                }
            }
            for url in delTarget {
                await diskAccesser.removeItem(url: url)
            }
        }
        
        // MARK: - Core Data stack
        public lazy var persistentContainer: NSPersistentContainer = {
            /*
             The persistent container for the application. This implementation
             creates and returns a container, having loaded the store for the
             application to it. This property is optional since there are legitimate
             error conditions that could cause the creation of the store to fail.
             */
            let modelURL = Bundle(for: CloudFactory.self).url(forResource: "cache", withExtension: "momd")!
            let mom = NSManagedObjectModel(contentsOf: modelURL)!

            let container = NSPersistentContainer(name: "cache", managedObjectModel: mom)
            let location = container.persistentStoreDescriptions.first!.url!
            let description = NSPersistentStoreDescription(url: location)
            description.shouldInferMappingModelAutomatically = true
            description.shouldMigrateStoreAutomatically = true
            container.persistentStoreDescriptions = [description]
            
            let semaphore = DispatchSemaphore(value: 0)
            container.loadPersistentStores(completionHandler: { (storeDescription, error) in
                defer {
                    semaphore.signal()
                }
                if let error = error as NSError? {
                    // Replace this implementation with code to handle the error appropriately.
                    // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                    
                    /*
                     Typical reasons for an error here include:
                     * The parent directory does not exist, cannot be created, or disallows writing.
                     * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                     * The device is out of space.
                     * The store could not be migrated to the current model version.
                     Check the error message to determine what the actual problem was.
                     */
                    fatalError("Unresolved error \(error), \(error.userInfo)")
                }
            })
            semaphore.wait()
            return container
        }()

        public lazy var viewContext = {
            persistentContainer.newBackgroundContext()
        }()
    }
    let cache = CacheAccesser()
    
    public func getPartialFile(storage: String, id: String, offset: Int64, size: Int64) async -> Data? {
        guard cacheMaxSize > 0 else {
            return nil
        }
        guard let orgItem = await CloudFactory.shared.data.getData(storage: storage, fileId: id) else {
            return nil
        }
        return await cache.getPartialFile(orgItem: orgItem, offset: offset, size: size)
    }

    public func getCache(storage: String, id: String, offset: Int64, size: Int64) async -> URL? {
        guard cacheMaxSize > 0 else {
            return nil
        }
        guard let orgItem = await CloudFactory.shared.data.getData(storage: storage, fileId: id) else {
            return nil
        }
        return await cache.getCache(orgItem: orgItem, offset: offset, size: size)
    }

    public func remove(storage: String, id: String) async {
        guard let orgItem = await CloudFactory.shared.data.getData(storage: storage, fileId: id) else {
            return
        }
        await cache.remove(orgItem: orgItem)
    }

    public func saveFile(storage: String, id: String, data: Data) async {
        guard cacheMaxSize > 0 else {
            return
        }
        if await getCacheSize() > cacheMaxSize {
            await increseFreeSpace()
        }

        guard let orgItem = await CloudFactory.shared.data.getData(storage: storage, fileId: id) else {
            return
        }
        await cache.saveFile(orgItem: orgItem, data: data)
    }

    public func saveCache(storage: String, id: String, offset: Int64, data: Data) async {
        guard cacheMaxSize > 0 else {
            return
        }
        if await getCacheSize() > cacheMaxSize {
            await increseFreeSpace()
        }

        guard let orgItem = await CloudFactory.shared.data.getData(storage: storage, fileId: id) else {
            return
        }
        await cache.saveCache(orgItem: orgItem, offset: offset, data: data)
    }

    public func deleteAllCache() async {
        await cache.deleteAllCache()
    }

    public func increseFreeSpace() async {
        guard cacheMaxSize > 0 else {
            if await getCacheSize() > 0 {
                await deleteAllCache()
            }
            return
        }
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSTemporaryDirectory()) else {
            return
        }
        let freesize = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        var incSize = await getCacheSize() - cacheMaxSize
        if freesize < 512*1024*1024 {
            let incSize2 = 512*1024*1024 - Int(freesize)
            if incSize < 0 {
                incSize = incSize2
            }
            else {
                incSize += incSize2
            }
        }
        guard incSize > 0 else { return }
        await cache.increseFreeSpace(incSize)
    }
    
    public func getCacheSize() async -> Int {
        return Int(await cache.diskAccesser.size)
    }
}

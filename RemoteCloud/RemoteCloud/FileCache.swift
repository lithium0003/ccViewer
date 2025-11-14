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
            if let attr = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)) {
                let filesize = attr[.size] as? UInt64 ?? 0
                if cacheSize > filesize {
                    cacheSize -= filesize
                }
                else {
                    cacheSize = 0
                }
            }
            try? FileManager.default.removeItem(at: url)
        }
        
        func write(data: Data, url: URL) throws {
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
    
    let diskAccesser = DiskAccesser()

    public func getPartialFile(storage: String, id: String, offset: Int64, size: Int64) async -> Data? {
        var ret: Data?
        guard cacheMaxSize > 0 else {
            return nil
        }
        guard let orgItem = await CloudFactory.shared.data.getData(storage: storage, fileId: id) else {
            return nil
        }
        await persistentContainer.performBackgroundTask { context in
            var targetURL: URL?
            let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
            fetchrequest.predicate = NSPredicate(format: "storage == %@ && id == %@ && chunkOffset == 0", storage, id)
            do{
                let items = try context.fetch(fetchrequest)
                guard let item = items.first as? FileCacheItem else {
                    return
                }
                if orgItem.mdate != item.mdate || orgItem.size != item.orgSize {
                    if let target = item.filename?.uuidString {
                        let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true)
                        let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true).appendingPathComponent(target)
                        Task {
                            await self.diskAccesser.removeItem(url: target_path)
                        }
                    }
                    context.delete(item)
                    try context.save()
                    return
                }
                if let target = item.filename?.uuidString, item.orgSize == item.chunkSize {
                    let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true)
                    let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true).appendingPathComponent(target)
                    if FileManager.default.fileExists(atPath: target_path.path) {
                        targetURL = target_path
                        item.rdate = Date()
                        try context.save()
                    }
                    else {
                        context.delete(item)
                        try context.save()
                    }
                }
            }
            catch{
                print(error)
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
                        ret = hFile.readDataToEndOfFile()
                        return
                    }
                    ret = hFile.readData(ofLength: Int(size))
                    return
                }
                catch {
                    print(error)
                }
            }
        }
        return ret
    }

    public func getCache(storage: String, id: String, offset: Int64, size: Int64) async -> URL? {
        var ret: URL? = nil
        guard cacheMaxSize > 0 else {
            return nil
        }
        guard let orgItem = await CloudFactory.shared.data.getData(storage: storage, fileId: id) else {
            return nil
        }
        await persistentContainer.performBackgroundTask { context in
            let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
            fetchrequest.predicate = NSPredicate(format: "storage == %@ && id == %@ && chunkOffset == %lld", storage, id, offset)
            do{
                let items = try context.fetch(fetchrequest)
                guard let item = items.first as? FileCacheItem else {
                    return
                }
                if orgItem.mdate != item.mdate || orgItem.size != item.orgSize {
                    if let target = item.filename?.uuidString {
                        let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true)
                        let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true).appendingPathComponent(target)
                        Task {
                            await self.diskAccesser.removeItem(url: target_path)
                        }
                    }
                    context.delete(item)
                    try context.save()
                    return
                }
                if let target = item.filename?.uuidString, (size == item.chunkSize || size < 0) {
                    let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true)
                    let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true).appendingPathComponent(target)
                    if FileManager.default.fileExists(atPath: target_path.path) {
                        ret = target_path
                        item.rdate = Date()
                        try context.save()
                    }
                    else {
                        context.delete(item)
                        try context.save()
                    }
                }
            }
            catch{
                print(error)
                return
            }
        }
        return ret
    }

    public func remove(storage: String, id: String) async {
        let backgroundContext = persistentContainer.newBackgroundContext()
        var removeFiles: [URL] = []
        await backgroundContext.perform {
            do {
                let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
                fetchrequest.predicate = NSPredicate(format: "storage == %@ && id == %@", storage, id)
                if let items = try backgroundContext.fetch(fetchrequest) as? [FileCacheItem], !items.isEmpty {
                    defer {
                        try? backgroundContext.save()
                    }
                    for item in items {
                        if let target = item.filename?.uuidString {
                            let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true)
                            let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true).appendingPathComponent(target)
                            removeFiles.append(target_path)
                        }
                        backgroundContext.delete(item)
                    }
                }
            }
            catch {
                print(error)
            }
        }
        await withTaskGroup { group in
            for url in removeFiles {
                group.addTask {
                    await self.diskAccesser.removeItem(url: url)
                }
            }
        }
    }

    public func saveFile(storage: String, id: String, data: Data) async {
        guard cacheMaxSize > 0 else {
            return
        }
        if await getCacheSize() > cacheMaxSize {
            await increseFreeSpace()
        }
        
        do {
            let size = Int64(data.count)
            let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true)
            let newId = UUID()
            let target = newId.uuidString
            let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true)
            try FileManager.default.createDirectory(at: target_path, withIntermediateDirectories: true, attributes: nil)
            try await diskAccesser.write(data: data, url: target_path.appendingPathComponent(target))

            return await persistentContainer.performBackgroundTask { context in
                Task {
                    guard let orgItem = await CloudFactory.shared.data.getData(storage: storage, fileId: id) else {
                        await self.diskAccesser.removeItem(url: target_path.appendingPathComponent(target))
                        return
                    }

                    let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
                    fetchrequest.predicate = NSPredicate(format: "storage == %@ && id == %@ && chunkOffset == 0 && chunkSize == %lld", storage, id, size)
                    do {
                        if let items = try context.fetch(fetchrequest) as? [FileCacheItem], items.count > 0 {
                            await self.diskAccesser.removeItem(url: target_path.appendingPathComponent(target))
                            return
                        }
                    }
                    catch {
                        print(error)
                    }

                    let newitem = FileCacheItem(context: context)
                    newitem.filename = newId
                    newitem.storage = storage
                    newitem.id = id
                    newitem.chunkSize = size
                    newitem.chunkOffset = 0
                    newitem.rdate = Date()
                    newitem.mdate = orgItem.mdate
                    newitem.orgSize = orgItem.size

                    try? context.save()
                }
            }
        }
        catch {
            print(error)
        }
    }

    public func saveCache(storage: String, id: String, offset: Int64, data: Data) async {
        guard cacheMaxSize > 0 else {
            return
        }
        do {
            let size = Int64(data.count)
            let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true)
            let newId = UUID()
            let target = newId.uuidString
            let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true)
            try FileManager.default.createDirectory(at: target_path, withIntermediateDirectories: true, attributes: nil)
            try await diskAccesser.write(data: data, url: target_path.appendingPathComponent(target))
            
            if await getCacheSize() > cacheMaxSize {
                await increseFreeSpace()
            }
            
            return await persistentContainer.performBackgroundTask { context in
                Task {
                    let item1 = await CloudFactory.shared.data.getData(storage: storage, fileId: id)

                    guard let orgItem = item1 else {
                        try? FileManager.default.removeItem(at: target_path.appendingPathComponent(target))
                        return
                    }

                    let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
                    fetchrequest.predicate = NSPredicate(format: "storage == %@ && id == %@ && chunkOffset == %lld && chunkSize == %lld", storage, id, offset, size)
                    do {
                        if let items = try context.fetch(fetchrequest) as? [FileCacheItem], items.count > 0 {
                            try FileManager.default.removeItem(at: target_path.appendingPathComponent(target))
                            return
                        }
                    }
                    catch {
                        print(error)
                    }

                    let newitem = FileCacheItem(context: context)
                    newitem.filename = newId
                    newitem.storage = storage
                    newitem.id = id
                    newitem.chunkSize = size
                    newitem.chunkOffset = offset
                    newitem.rdate = Date()
                    newitem.mdate = orgItem.mdate
                    newitem.orgSize = orgItem.size

                    try? context.save()
                }
            }
        }
        catch {
            print(error)
        }
    }

    public func deleteAllCache() async {
        guard let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true) else {
            return
        }
        await diskAccesser.removeItem(url: base)
        await persistentContainer.performBackgroundTask { context in
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
        var delSize = 0
        guard let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true) else {
            return
        }
        await persistentContainer.performBackgroundTask { context in
            let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
            fetchrequest.predicate = NSPredicate(value: true)
            fetchrequest.sortDescriptors = [NSSortDescriptor(key: "rdate", ascending: true)]
            do {
                if let items = try context.fetch(fetchrequest) as? [FileCacheItem], items.count > 0 {
                    var delItems = [FileCacheItem]()
                    for item in items {
                        if delSize > incSize {
                            break
                        }
                        guard let target = item.filename?.uuidString else {
                            continue
                        }
                        delSize += Int(item.chunkSize)
                        delItems += [item]
                        let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true).appendingPathComponent(target)
                        Task {
                            await self.diskAccesser.removeItem(url: target_path)
                        }
                    }
                    for item in delItems {
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
    
    public func getCacheSize() async -> Int {
        return Int(await diskAccesser.size)
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
        description.setOption(FileProtectionType.completeUnlessOpen as NSObject, forKey: NSPersistentStoreFileProtectionKey)
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
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
        return container
    }()

    // MARK: - Core Data Saving support

    public func saveContext () {
        let context = self.persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
}

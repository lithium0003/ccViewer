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
    public var diskQueue = DispatchQueue(label: "FileEnumerate")

    public var cacheMaxSize: Int {
        get {
            return UserDefaults.standard.integer(forKey: "networkCacheSize")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "networkCacheSize")
        }
    }
    
    public func getPartialFile(storage: String, id: String, offset: Int64, size: Int64) -> Data? {
        var ret: Data?
        let group = DispatchGroup()
        group.enter()
        CloudFactory.shared.data.getData(storage: storage, fileId: id) { item1 in
            guard let orgItem = item1 else {
                group.leave()
                return
            }
            self.persistentContainer.performBackgroundTask { context in
                defer {
                    group.leave()
                }
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
                            self.diskQueue.async {
                                try? FileManager.default.removeItem(at: target_path)
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
                                if #available(iOS 13.0, *) {
                                    try hFile.close()
                                } else {
                                    hFile.closeFile()
                                }
                            }
                            catch {
                                print(error)
                            }
                        }
                        if #available(iOS 13.0, *) {
                            try hFile.seek(toOffset: UInt64(offset))
                        } else {
                            hFile.seek(toFileOffset: UInt64(offset))
                        }
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
        }
        let _ = group.wait()
        return ret
    }
    
    public func getCache(storage: String, id: String, offset: Int64, size: Int64) -> URL? {
        var ret: URL? = nil
        guard cacheMaxSize > 0 else {
            return nil
        }
        let group = DispatchGroup()
        group.enter()
        CloudFactory.shared.data.getData(storage: storage, fileId: id) { item1 in
            guard let orgItem = item1 else {
                group.leave()
                return
            }
            self.persistentContainer.performBackgroundTask { context in
                defer {
                    group.leave()
                }
                
                // Fix CoreData merge conflict shows managed object version change not data
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

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
                            self.diskQueue.async {
                                try? FileManager.default.removeItem(at: target_path)
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

        }
        let _ = group.wait()
        return ret
    }

    public func saveFile(storage: String, id: String, data: Data) {
        if getCacheSize() > cacheMaxSize {
            increseFreeSpace()
        }
        
        do {
            let size = Int64(data.count)
            let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true)
            let newId = UUID()
            let target = newId.uuidString
            let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true)
            try FileManager.default.createDirectory(at: target_path, withIntermediateDirectories: true, attributes: nil)
            try diskQueue.sync {
                try data.write(to: target_path.appendingPathComponent(target))
            }

            persistentContainer.performBackgroundTask { context in
                let item1 = CloudFactory.shared.data.getData(storage: storage, fileId: id)
                guard let orgItem = item1 else {
                    try? FileManager.default.removeItem(at: target_path.appendingPathComponent(target))
                    return
                }

                let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
                fetchrequest.predicate = NSPredicate(format: "storage == %@ && id == %@ && chunkOffset == 0 && chunkSize == %lld", storage, id, size)
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
                newitem.chunkOffset = 0
                newitem.rdate = Date()
                newitem.mdate = orgItem.mdate
                newitem.orgSize = orgItem.size

                try? context.save()
            }
        }
        catch {
            print(error)
        }
    }
    
    public func saveCache(storage: String, id: String, offset: Int64, data: Data) {
        guard cacheMaxSize > 0 else {
            if getCacheSize() > 0 {
                deleteAllCache()
            }
            return
        }
        do {
            let size = Int64(data.count)
            let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true)
            let newId = UUID()
            let target = newId.uuidString
            let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true)
            try FileManager.default.createDirectory(at: target_path, withIntermediateDirectories: true, attributes: nil)
            try diskQueue.sync {
                try data.write(to: target_path.appendingPathComponent(target))
            }
            
            if getCacheSize() > cacheMaxSize {
                increseFreeSpace()
            }
            
            persistentContainer.performBackgroundTask { context in
                let item1 = CloudFactory.shared.data.getData(storage: storage, fileId: id)
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
        catch {
            print(error)
        }
    }
    
    public func deleteAllCache() {
        guard let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true) else {
            return
        }
        diskQueue.async {
            do {
                try FileManager.default.removeItem(at: base)
            }
            catch {
                print(error)
            }
        }
        persistentContainer.performBackgroundTask { context in
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
    
    public func increseFreeSpace() {
        guard cacheMaxSize > 0 else {
            if getCacheSize() > 0 {
                deleteAllCache()
            }
            return
        }
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSTemporaryDirectory()) else {
            return
        }
        let freesize = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        var incSize = getCacheSize() - cacheMaxSize
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
        persistentContainer.performBackgroundTask { context in
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
                        self.diskQueue.async {
                            let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true).appendingPathComponent(target)
                            do {
                                try FileManager.default.removeItem(at: target_path)
                            }
                            catch {
                                print(error)
                            }
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
    
    public func getCacheSize() -> Int {
        guard let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true) else {
            return 0
        }
    
        let resourceKeys = Set<URLResourceKey>([.fileAllocatedSizeKey])
        return diskQueue.sync {
            let directoryEnumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: Array(resourceKeys), options: .skipsHiddenFiles)!
             
            var allocSize = 0
            for case let fileURL as URL in directoryEnumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                    let size = resourceValues.fileAllocatedSize
                    else {
                        continue
                }
                allocSize += size
            }
            return allocSize
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

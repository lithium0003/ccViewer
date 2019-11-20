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
    
    public func getCache(storage: String, id: String, offset: Int64, size: Int64) -> URL? {
        var ret: URL? = nil
        guard cacheMaxSize > 0 else {
            return nil
        }
        if Thread.isMainThread {
            guard let orgItem = CloudFactory.shared.data.getData(storage: storage, fileId: id) else {
                return nil
            }
            
            let viewContext = self.persistentContainer.viewContext
            
            let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
            fetchrequest.predicate = NSPredicate(format: "storage == %@ && id == %@ && chunkOffset == %lld", storage, id, offset)
            do{
                guard let item = try viewContext.fetch(fetchrequest).first as? FileCacheItem else {
                    return nil
                }
                if orgItem.mdate != item.mdate || orgItem.size != item.orgSize {
                    if let target = item.filename?.uuidString {
                        let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true)
                        let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true).appendingPathComponent(target)
                        try FileManager.default.removeItem(at: target_path)
                    }
                    viewContext.delete(item)
                    try viewContext.save()
                    return nil
                }
                if let target = item.filename?.uuidString, (size == item.chunkSize || size < 0) {
                    let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true)
                    let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true).appendingPathComponent(target)
                    if FileManager.default.fileExists(atPath: target_path.path) {
                        ret = target_path
                        item.rdate = Date()
                        try? viewContext.save()
                    }
                    else {
                        viewContext.delete(item)
                        try viewContext.save()
                    }
                }
            }
            catch{
                return nil
            }
            return ret
        }
        else {
            DispatchQueue.main.sync {
                ret = getCache(storage: storage, id: id, offset: offset, size: size)
            }
            return ret
        }
    }
    
    public func saveCache(storage: String, id: String, offset: Int64, data: Data) {
        guard cacheMaxSize > 0 else {
            increseFreeSpace()
            return
        }
        do {
            let size = Int64(data.count)
            let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NetCache", isDirectory: true)
            let newId = UUID()
            let target = newId.uuidString
            let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true)
            try FileManager.default.createDirectory(at: target_path, withIntermediateDirectories: true, attributes: nil)
            try data.write(to: target_path.appendingPathComponent(target))
            
            if getCacheSize() > cacheMaxSize {
                increseFreeSpace()
            }
            
            DispatchQueue.main.async {
                guard let orgItem = CloudFactory.shared.data.getData(storage: storage, fileId: id) else {
                    try? FileManager.default.removeItem(at: target_path.appendingPathComponent(target))
                    return
                }

                let viewContext = self.persistentContainer.viewContext
                
                let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
                fetchrequest.predicate = NSPredicate(format: "storage == %@ && id == %@ && chunkOffset == %lld && chunkSize == %lld", storage, id, offset, size)
                do {
                    if let items = try viewContext.fetch(fetchrequest) as? [FileCacheItem], items.count > 0 {
                        try FileManager.default.removeItem(at: target_path.appendingPathComponent(target))
                        return
                    }
                }
                catch {
                    print(error)
                }

                let newitem = FileCacheItem(context: viewContext)
                newitem.filename = newId
                newitem.storage = storage
                newitem.id = id
                newitem.chunkSize = size
                newitem.chunkOffset = offset
                newitem.rdate = Date()
                newitem.mdate = orgItem.mdate
                newitem.orgSize = orgItem.size

                try? viewContext.save()
            }
        }
        catch {
            print(error)
        }
    }
    
    public func increseFreeSpace() {
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
        DispatchQueue.main.async {
            let viewContext = self.persistentContainer.viewContext
            
            let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FileCacheItem")
            fetchrequest.predicate = NSPredicate(value: true)
            fetchrequest.sortDescriptors = [NSSortDescriptor(key: "rdate", ascending: true)]
            do {
                if let items = try viewContext.fetch(fetchrequest) as? [FileCacheItem], items.count > 0 {
                    for item in items {
                        if delSize > incSize {
                            break
                        }
                        guard let target = item.filename?.uuidString else {
                            continue
                        }
                        let target_path = base.appendingPathComponent(String(target.prefix(2)), isDirectory: true).appendingPathComponent(String(target.prefix(4).suffix(2)), isDirectory: true).appendingPathComponent(target)
                        try FileManager.default.removeItem(at: target_path)
                        delSize += Int(item.chunkSize)
                        viewContext.delete(item)
                    }
                    try viewContext.save()
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
        let context = persistentContainer.viewContext
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

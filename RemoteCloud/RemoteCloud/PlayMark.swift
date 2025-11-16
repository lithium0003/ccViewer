//
//  PlayMark.swift
//  RemoteCloud
//
//  Created by rei9 on 2025/11/17.
//  Copyright © 2025 lithium03. All rights reserved.
//

import Foundation
import CoreData
import CloudKit
import CommonCrypto

public class PlayMark {
    public func getMark(storage: String, targetIDs: [String], parentID: String) async -> [String: Double] {
        if !UserDefaults.standard.bool(forKey: "savePlaypos") {
            return [:]
        }
        
        if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
            await getCloudMark(storage: storage, parentID: parentID)
        }
        
        var targets: [String: String] = [:]
        for targetId in targetIDs {
            var result = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
            guard let data = "storage=\(storage),target=\(targetId)".cString(using: .utf8) else {
                continue
            }
            CC_SHA512(data, CC_LONG(data.count-1), &result)
            let target = result.map({ String(format: "%02hhx", $0) }).joined()
            targets[target] = targetId
        }
        
        var result2 = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        guard let data2 = "storage=\(storage),target=\(parentID)".cString(using: .utf8) else {
            return [:]
        }
        CC_SHA512(data2, CC_LONG(data2.count-1), &result2)
        let target2 = result2.map({ String(format: "%02hhx", $0) }).joined()
        
        return await Task { @MainActor in
            let viewContext = viewContext
            
            let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Mark")
            fetchrequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", target2, storage)
            
            var results: [String: Double] = [:]
            do {
                for item in try viewContext.fetch(fetchrequest) as! [Mark] {
                    if let hashedId = item.id, let orgId = targets[hashedId] {
                        results[orgId] = item.position
                    }
                }
            }
            catch {
                print(error)
            }
            
            return results
        }.value
    }
    
    public func getMark(storage: String, targetID: String) async -> Double? {
        if !UserDefaults.standard.bool(forKey: "savePlaypos") {
            return nil
        }
        
        if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
            await getCloudMark(storage: storage, targetID: targetID)
        }
        
        var result = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        guard let data = "storage=\(storage),target=\(targetID)".cString(using: .utf8) else {
            return nil
        }
        CC_SHA512(data, CC_LONG(data.count-1), &result)
        let target = result.map({ String(format: "%02hhx", $0) }).joined()
        
        return await Task { @MainActor in
            let viewContext = viewContext
            
            let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Mark")
            fetchrequest.predicate = NSPredicate(format: "id == %@ && storage == %@", target, storage)
            
            return try? (viewContext.fetch(fetchrequest) as! [Mark]).first?.position
        }.value
    }
    
    func getCloudMark(storage: String, targetID: String) async {
        var result = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        guard let data = "storage=\(storage),target=\(targetID)".cString(using: .utf8) else {
            return
        }
        CC_SHA512(data, CC_LONG(data.count-1), &result)
        let target = result.map({ String(format: "%02hhx", $0) }).joined()
        
        let ckDatabase = CKContainer.default().privateCloudDatabase
        
        let ckQuery = CKQuery(recordType: "PlayTime", predicate: NSPredicate(format: "targetId == %@", argumentArray: [target]))
        do {
            let result = try await ckDatabase.records(matching: ckQuery)
            await persistentContainer.performBackgroundTask { context in
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Mark")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", targetID, storage)
                if let result = try? context.fetch(fetchRequest) {
                    for object in result {
                        context.delete(object as! NSManagedObject)
                    }
                }
                
                for (_, ckRecord) in result.matchResults {
                    switch ckRecord {
                    case .success(let record):
                        let pos = record["lastPosition"] as Double?
                        let id = record["targetId"] as String?
                        let parent = record["parentId"] as String?
                        
                        if let pos = pos {
                            let newitem = Mark(context: context)
                            newitem.id = id
                            newitem.parent = parent
                            newitem.storage = storage
                            newitem.position = pos
                        }
                        
                    case .failure(let error):
                        print(error)
                    }
                }
                
                try? context.save()
            }
        }
        catch {
            print(error)
        }
    }
    
    func getCloudMark(storage: String, parentID: String) async {
        var result2 = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        guard let data2 = "storage=\(storage),target=\(parentID)".cString(using: .utf8) else {
            return
        }
        CC_SHA512(data2, CC_LONG(data2.count-1), &result2)
        let target2 = result2.map({ String(format: "%02hhx", $0) }).joined()
        
        let ckDatabase = CKContainer.default().privateCloudDatabase
        
        let ckQuery = CKQuery(recordType: "PlayTime", predicate: NSPredicate(format: "parentId == %@", argumentArray: [target2]))
        do {
            let result = try await ckDatabase.records(matching: ckQuery)
            await persistentContainer.performBackgroundTask { context in
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Mark")
                fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", parentID, storage)
                if let result = try? context.fetch(fetchRequest) {
                    for object in result {
                        context.delete(object as! NSManagedObject)
                    }
                }
                
                for (_, ckRecord) in result.matchResults {
                    switch ckRecord {
                    case .success(let record):
                        let pos = record["lastPosition"] as Double?
                        let id = record["targetId"] as String?
                        let parent = record["parentId"] as String?
                        
                        if let pos = pos {
                            let newitem = Mark(context: context)
                            newitem.id = id
                            newitem.parent = parent
                            newitem.storage = storage
                            newitem.position = pos
                        }
                        
                    case .failure(let error):
                        print(error)
                    }
                }
                
                try? context.save()
            }
        }
        catch {
            print(error)
        }
    }
    
    public func setMark(storage: String, targetID: String, parentID: String, position: Double?) async {
        if !UserDefaults.standard.bool(forKey: "savePlaypos") {
            return
        }
        
        var result = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        guard let data = "storage=\(storage),target=\(targetID)".cString(using: .utf8) else {
            return
        }
        CC_SHA512(data, CC_LONG(data.count-1), &result)
        let target = result.map({ String(format: "%02hhx", $0) }).joined()
        
        var result2 = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        guard let data2 = "storage=\(storage),target=\(parentID)".cString(using: .utf8) else {
            return
        }
        CC_SHA512(data2, CC_LONG(data2.count-1), &result2)
        let target2 = result2.map({ String(format: "%02hhx", $0) }).joined()
        
        await persistentContainer.performBackgroundTask { context in
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Mark")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", target, storage)
            if let result = try? context.fetch(fetchRequest) {
                for object in result {
                    context.delete(object as! NSManagedObject)
                }
            }
            
            if let position = position {
                let newitem = Mark(context: context)
                newitem.id = target
                newitem.parent = target2
                newitem.storage = storage
                newitem.position = position
                
                try? context.save()
            }
            else {
                try? context.save()
            }
        }
        
        if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
            await setCloudMark(storage: storage, targetID: targetID, parentID: parentID, position: position)
        }
    }
    
    func setCloudMark(storage: String, targetID: String, parentID: String, position: Double?) async {
        var result = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        guard let data = "storage=\(storage),target=\(targetID)".cString(using: .utf8) else {
            return
        }
        CC_SHA512(data, CC_LONG(data.count-1), &result)
        let target = result.map({ String(format: "%02hhx", $0) }).joined()
        
        var result2 = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        guard let data2 = "storage=\(storage),target=\(parentID)".cString(using: .utf8) else {
            return
        }
        CC_SHA512(data2, CC_LONG(data2.count-1), &result2)
        let target2 = result2.map({ String(format: "%02hhx", $0) }).joined()
        
        let ckDatabase = CKContainer.default().privateCloudDatabase
        
        let ckQuery = CKQuery(recordType: "PlayTime", predicate: NSPredicate(format: "targetId == %@", argumentArray: [target]))
        
        do {
            let result = try await ckDatabase.records(matching: ckQuery)
            
            if result.matchResults.isEmpty {
                if let position = position {
                    let ckRecord = CKRecord(recordType: "PlayTime")
                    ckRecord["lastPosition"] = position
                    ckRecord["targetId"] = target
                    ckRecord["parentId"] = target2
                    
                    try await ckDatabase.save(ckRecord)
                }
            }
            for (_, record) in result.matchResults {
                switch record {
                case .success(let ckRecord):
                    if let position = position {
                        ckRecord["lastPosition"] = position
                        ckRecord["targetId"] = target
                        ckRecord["parentId"] = target2
                        
                        try await ckDatabase.save(ckRecord)
                    }
                    else {
                        try await ckDatabase.deleteRecord(withID: ckRecord.recordID)
                    }
                case .failure(let error):
                    print(error)
                }
            }
        }
        catch {
            print(error)
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
        let modelURL = Bundle(for: CloudFactory.self).url(forResource: "playmark", withExtension: "momd")!
        let mom = NSManagedObjectModel(contentsOf: modelURL)!
        
        let container = NSPersistentContainer(name: "playmark", managedObjectModel: mom)
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

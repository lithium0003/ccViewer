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
    
    public lazy var backgroundContext: NSManagedObjectContext = {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }()
    
    // MARK: - Helpers
    private func hashString(_ input: String) -> String {
        guard let data = input.cString(using: .utf8) else { return "" }
        var result = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        CC_SHA512(data, CC_LONG(data.count - 1), &result)
        return result.map { String(format: "%02hhx", $0) }.joined()
    }
    
    // MARK: - Public Methods
    public func getMark(storage: String, targetIDs: [String], parentID: String) async -> [String: Double] {
        guard UserDefaults.standard.bool(forKey: "savePlaypos") else { return [:] }
        
        if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
            await getCloudMark(storage: storage, parentID: parentID)
        }
        
        var targets: [String: String] = [:]
        for targetId in targetIDs {
            let hashedTarget = hashString("storage=\(storage),target=\(targetId)")
            if !hashedTarget.isEmpty {
                targets[hashedTarget] = targetId
            }
        }
        
        let hashedParent = hashString("storage=\(storage),target=\(parentID)")
        guard !hashedParent.isEmpty else { return [:] }
        
        let context = backgroundContext
        return await context.perform {
            let fetchRequest = NSFetchRequest<Mark>(entityName: "Mark")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", hashedParent, storage)
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "mdate", ascending: false)]
            
            var results: [String: Double] = [:]
            if let marks = try? context.fetch(fetchRequest) {
                for item in marks {
                    if let hashedId = item.id, let orgId = targets[hashedId] {
                        if results[orgId] == nil {
                            results[orgId] = item.position
                        }
                    }
                }
            }
            return results
        }
    }
    
    public func getMark(storage: String, targetID: String) async -> Double? {
        guard UserDefaults.standard.bool(forKey: "savePlaypos") else { return nil }
        
        if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
            await getCloudMark(storage: storage, targetID: targetID)
        }
        
        let hashedTarget = hashString("storage=\(storage),target=\(targetID)")
        guard !hashedTarget.isEmpty else { return nil }
        
        let context = backgroundContext
        return await context.perform {
            let fetchRequest = NSFetchRequest<Mark>(entityName: "Mark")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", hashedTarget, storage)
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "mdate", ascending: false)]
            fetchRequest.fetchLimit = 1
            
            return (try? context.fetch(fetchRequest))?.first?.position
        }
    }
    
    public func setMark(storage: String, targetID: String, parentID: String, position: Double?) async {
        guard UserDefaults.standard.bool(forKey: "savePlaypos") else { return }
        
        let hashedTarget = hashString("storage=\(storage),target=\(targetID)")
        let hashedParent = hashString("storage=\(storage),target=\(parentID)")
        guard !hashedTarget.isEmpty, !hashedParent.isEmpty else { return }
        
        let context = backgroundContext
        await context.perform {
            let fetchRequest = NSFetchRequest<Mark>(entityName: "Mark")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", hashedTarget, storage)
            fetchRequest.fetchLimit = 1
            
            let existingMark = (try? context.fetch(fetchRequest))?.first
            
            if let pos = position {
                let markToSave = existingMark ?? Mark(context: context)
                markToSave.id = hashedTarget
                markToSave.parent = hashedParent
                markToSave.storage = storage
                markToSave.position = pos
                markToSave.mdate = Date()
            } else {
                if let existing = existingMark {
                    context.delete(existing)
                }
            }
            try? context.save()
        }
        
        if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
            await setCloudMark(storage: storage, targetID: targetID, parentID: parentID, position: position)
        }
        try? await Task.sleep(for: .milliseconds(500))
    }
    
    // MARK: - CloudKit Sync Methods
    func getCloudMark(storage: String, targetID: String) async {
        let hashedTarget = hashString("storage=\(storage),target=\(targetID)")
        guard !hashedTarget.isEmpty else { return }
        
        let ckDatabase = CKContainer.default().privateCloudDatabase
        let ckQuery = CKQuery(recordType: "PlayTime", predicate: NSPredicate(format: "targetId == %@", argumentArray: [hashedTarget]))
        
        do {
            let result = try await ckDatabase.records(matching: ckQuery)
            let context = backgroundContext
            
            await context.perform {
                for (_, ckRecord) in result.matchResults {
                    switch ckRecord {
                    case .success(let record):
                        guard let pos = record["lastPosition"] as? Double,
                              let id = record["targetId"] as? String,
                              let parent = record["parentId"] as? String else { continue }
                        
                        let fetchRequest = NSFetchRequest<Mark>(entityName: "Mark")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, storage)
                        fetchRequest.fetchLimit = 1
                        
                        let existingMark = (try? context.fetch(fetchRequest))?.first
                        let markToSave = existingMark ?? Mark(context: context)
                        
                        markToSave.id = id
                        markToSave.parent = parent
                        markToSave.storage = storage
                        markToSave.position = pos
                        markToSave.mdate = Date()
                        
                    case .failure(let error):
                        print("CloudKit fetch error: \(error)")
                    }
                }
                try? context.save()
            }
        } catch {
            print("CloudKit query error: \(error)")
        }
    }
    
    func getCloudMark(storage: String, parentID: String) async {
        let hashedParent = hashString("storage=\(storage),target=\(parentID)")
        guard !hashedParent.isEmpty else { return }
        
        let ckDatabase = CKContainer.default().privateCloudDatabase
        let ckQuery = CKQuery(recordType: "PlayTime", predicate: NSPredicate(format: "parentId == %@", argumentArray: [hashedParent]))
        
        do {
            let result = try await ckDatabase.records(matching: ckQuery)
            let context = backgroundContext
            
            await context.perform {
                for (_, ckRecord) in result.matchResults {
                    switch ckRecord {
                    case .success(let record):
                        guard let pos = record["lastPosition"] as? Double,
                              let id = record["targetId"] as? String,
                              let parent = record["parentId"] as? String else { continue }
                        
                        let fetchRequest = NSFetchRequest<Mark>(entityName: "Mark")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, storage)
                        fetchRequest.fetchLimit = 1
                        
                        let existingMark = (try? context.fetch(fetchRequest))?.first
                        let markToSave = existingMark ?? Mark(context: context)
                        
                        markToSave.id = id
                        markToSave.parent = parent
                        markToSave.storage = storage
                        markToSave.position = pos
                        markToSave.mdate = Date()
                        
                    case .failure(let error):
                        print("CloudKit fetch error: \(error)")
                    }
                }
                try? context.save()
            }
        } catch {
            print("CloudKit query error: \(error)")
        }
    }
    
    func setCloudMark(storage: String, targetID: String, parentID: String, position: Double?) async {
        let hashedTarget = hashString("storage=\(storage),target=\(targetID)")
        let hashedParent = hashString("storage=\(storage),target=\(parentID)")
        guard !hashedTarget.isEmpty, !hashedParent.isEmpty else { return }
        
        let ckDatabase = CKContainer.default().privateCloudDatabase
        let ckQuery = CKQuery(recordType: "PlayTime", predicate: NSPredicate(format: "targetId == %@", argumentArray: [hashedTarget]))
        
        do {
            let result = try await ckDatabase.records(matching: ckQuery)
            
            if result.matchResults.isEmpty {
                if let position = position {
                    let ckRecord = CKRecord(recordType: "PlayTime")
                    ckRecord["lastPosition"] = position
                    ckRecord["targetId"] = hashedTarget
                    ckRecord["parentId"] = hashedParent
                    try await ckDatabase.save(ckRecord)
                }
            } else {
                for (_, record) in result.matchResults {
                    switch record {
                    case .success(let ckRecord):
                        if let position = position {
                            ckRecord["lastPosition"] = position
                            ckRecord["targetId"] = hashedTarget
                            ckRecord["parentId"] = hashedParent
                            try await ckDatabase.save(ckRecord)
                        } else {
                            try await ckDatabase.deleteRecord(withID: ckRecord.recordID)
                        }
                    case .failure(let error):
                        print("CloudKit match result error: \(error)")
                    }
                }
            }
        } catch {
            print("CloudKit query error: \(error)")
        }
    }
}

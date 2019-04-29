//
//  RemoteItem.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/03/10.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreData
import CloudKit
import CommonCrypto

public class dataItems {

    public func listData(storage: String, parentID: String) -> [RemoteData]  {
        let viewContext = persistentContainer.viewContext
        
        let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
        fetchrequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", parentID, storage)
        fetchrequest.sortDescriptors = [NSSortDescriptor(key: "folder", ascending: false),
                                        NSSortDescriptor(key: "name", ascending: true)]
        do{
            return try viewContext.fetch(fetchrequest) as! [RemoteData]
        }
        catch{
            return []
        }
    }

    public func getMark(storage: String, targetID: String) -> Double? {
        var result = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        guard let data = "storage=\(storage),target=\(targetID)".cString(using: .utf8) else {
            return nil
        }
        CC_SHA512(data, CC_LONG(data.count-1), &result)
        let target = result.map({ String(format: "%02hhx", $0) }).joined()

        var position: Double?
        if !Thread.isMainThread {
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.main.async {
                let viewContext = self.persistentContainer.viewContext
                
                let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Mark")
                fetchrequest.predicate = NSPredicate(format: "id == %@ && storage == %@", target, storage)
                
                position = try? (viewContext.fetch(fetchrequest) as! [Mark]).first?.position
                group.leave()
            }
            group.wait()
        }
        else {
            let viewContext = self.persistentContainer.viewContext
            
            let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Mark")
            fetchrequest.predicate = NSPredicate(format: "id == %@ && storage == %@", target, storage)
            
            position = try? (viewContext.fetch(fetchrequest) as! [Mark]).first?.position
        }
        return position
    }
    
    public func getCloudMark(storage: String, parentID: String, onFinish: @escaping ()->Void) {
        var result = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        guard let data = "storage=\(storage),target=\(parentID)".cString(using: .utf8) else {
            onFinish()
            return
        }
        CC_SHA512(data, CC_LONG(data.count-1), &result)
        let target = result.map({ String(format: "%02hhx", $0) }).joined()
        
        let ckDatabase = CKContainer.default().privateCloudDatabase

        let ckQuery = CKQuery(recordType: "PlayTime", predicate: NSPredicate(format: "parentId == %@", argumentArray: [target]))
        
        ckDatabase.perform(ckQuery, inZoneWith: nil, completionHandler: { (ckRecords, error) in
            guard error == nil else {
                print("\(String(describing: error?.localizedDescription))")
                onFinish()
                return
            }
            DispatchQueue.main.async {
                let viewContext = self.persistentContainer.viewContext
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Mark")
                fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", parentID, storage)
                if let result = try? viewContext.fetch(fetchRequest) {
                    for object in result {
                        viewContext.delete(object as! NSManagedObject)
                    }
                }

                for ckRecord in ckRecords!{
                    let pos = ckRecord["lastPosition"] as Double?
                    let id = ckRecord["targetId"] as String?
                    
                    if let pos = pos {
                        let newitem = Mark(context: viewContext)
                        newitem.id = id
                        newitem.storage = storage
                        newitem.parent = parentID
                        newitem.position = pos
                    }
                }
                
                try? viewContext.save()
                onFinish()
            }
        })
    }

    func subGetCurrentPlaylist(q: CKQuery? = nil, cursor: CKQueryOperation.Cursor? = nil, onFinish: @escaping ([CKRecord])->Void) {
        
        let operation: CKQueryOperation
        if let query = q {
            operation = CKQueryOperation(query: query)
        }
        else if let cursor = cursor {
            operation = CKQueryOperation(cursor: cursor)
        }
        else {
            onFinish([])
            return
        }
        var ret = [CKRecord]()
        operation.resultsLimit = 100
        operation.recordFetchedBlock = { ckRecord in
            ret += [ckRecord]
        }
        operation.queryCompletionBlock = { cursor, error in
            guard error == nil else {
                print("\(String(describing: error?.localizedDescription))")
                onFinish(ret)
                return
            }
            if let cursor = cursor {
                print("next query")
                self.subGetCurrentPlaylist(cursor: cursor) { subret in
                    ret += subret
                    onFinish(ret)
                }
                return
            }
            onFinish(ret)
        }
        
        let ckDatabase = CKContainer.default().privateCloudDatabase
        ckDatabase.add(operation)
    }
    
    func subUploadCloudPlaylist(delete: [CKRecord.ID]? = nil, save: [CKRecord]? = nil, onFinish: @escaping ()->Void) {
        let currentDelete: [CKRecord.ID]?
        let remainDelete: [CKRecord.ID]?
        if let delete = delete {
            if delete.count > 400 {
                currentDelete = Array(delete[0..<400])
                remainDelete = Array(delete[400...])
            }
            else {
                currentDelete = delete
                remainDelete = nil
            }
        }
        else {
            currentDelete = nil
            remainDelete = nil
        }
        let currentSave: [CKRecord]?
        let remainSave: [CKRecord]?
        if currentDelete != nil {
            currentSave = nil
            remainSave = save
        }
        else if let save = save {
            if save.count > 400 {
                currentSave = Array(save[0..<400])
                remainSave = Array(save[400...])
            }
            else {
                currentSave = save
                remainSave = nil
            }
        }
        else {
            currentSave = nil
            remainSave = nil
        }
        
        let opetation = CKModifyRecordsOperation()
        opetation.recordIDsToDelete = currentDelete
        opetation.recordsToSave = currentSave
        opetation.modifyRecordsCompletionBlock = { saved, deleted, error in
            guard error == nil else {
                print("\(String(describing: error?.localizedDescription))")
                onFinish()
                return
            }
            print(saved?.count ?? -1)
            print(deleted?.count ?? -1)
            if remainSave != nil || remainDelete != nil {
                self.subUploadCloudPlaylist(delete: remainDelete, save: remainSave, onFinish: onFinish)
            }
            else {
                onFinish()
            }
        }
        opetation.perRecordCompletionBlock = { record, error in
            guard error == nil else {
                print("\(String(describing: error?.localizedDescription))")
                return
            }
        }
        let ckDatabase = CKContainer.default().privateCloudDatabase
        ckDatabase.add(opetation)
    }
    
    public func uploadCloudPlaylist(onFinish: @escaping ()->Void) {
        var serialStart = Int64(0)
        var serialEnd = Int64(0)
        let group = DispatchGroup()
        var saveItems = [CKRecord]()
        group.enter()
        DispatchQueue.main.async {
            let viewContext = self.persistentContainer.viewContext
            let fetchRequest1 = NSFetchRequest<NSFetchRequestResult>(entityName: "PlayList")
            fetchRequest1.predicate = NSPredicate(format: "id == %@ && storage == %@ && folder == %@", "", "", "")
            if let result = try? viewContext.fetch(fetchRequest1) as? [PlayList] {
                if let forid = result.first {
                    serialStart = forid.index
                    serialEnd = forid.serial
                }
            }

            let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "PlayList")
            fetchrequest.predicate = NSPredicate(format: "serial BETWEEN {%lld, %lld}", serialStart, serialEnd)
            if let data = try? viewContext.fetch(fetchrequest) as? [PlayList] {
                for item in data {
                    let ckRecord = CKRecord(recordType: "PlayList")
                    ckRecord["id"] = item.id
                    ckRecord["storage"] = item.storage
                    ckRecord["folder"] = item.folder
                    ckRecord["index"] = item.index
                    ckRecord["serial"] = item.serial
                    saveItems += [ckRecord]
                }
            }

            let ckRecord = CKRecord(recordType: "PlayList")
            ckRecord["id"] = ""
            ckRecord["storage"] = ""
            ckRecord["folder"] = ""
            ckRecord["index"] = serialStart
            ckRecord["serial"] = serialEnd
            saveItems += [ckRecord]

            group.leave()
        }
        
        group.notify(queue: .global()) {
            let ckQuery = CKQuery(recordType: "PlayList", predicate: NSPredicate(value: true))
            
            self.subGetCurrentPlaylist(q: ckQuery) { ckRecords in
                self.subUploadCloudPlaylist(delete: ckRecords.map({ $0.recordID}), save: saveItems, onFinish: onFinish)
            }
        }
    }

    func subGetCloudPlaylist(q: CKQuery? = nil, cursor: CKQueryOperation.Cursor? = nil, onFinish: @escaping ()->Void) {
        let operation: CKQueryOperation
        if let query = q {
            operation = CKQueryOperation(query: query)
        }
        else if let cursor = cursor {
            operation = CKQueryOperation(cursor: cursor)
        }
        else {
            onFinish()
            return
        }
        operation.resultsLimit = 100
        operation.recordFetchedBlock = { ckRecord in
            DispatchQueue.main.async {
                let viewContext = self.persistentContainer.viewContext
                
                let id = ckRecord["id"] as String?
                let storage = ckRecord["storage"] as String?
                let folder = ckRecord["folder"] as String?
                let index = ckRecord["index"] as Int64?
                let serial = ckRecord["serial"] as Int64?
                
                let newitem = PlayList(context: viewContext)
                newitem.id = id
                newitem.storage = storage
                newitem.folder = folder
                newitem.index = index ?? -1
                newitem.serial = serial ?? 0
            }
        }
        operation.queryCompletionBlock = { cursor, error in
            guard error == nil else {
                print("\(String(describing: error?.localizedDescription))")
                DispatchQueue.main.async {
                    let viewContext = self.persistentContainer.viewContext
                    try? viewContext.save()
                }
                onFinish()
                return
            }
            if let cursor = cursor {
                print("next query")
                self.subGetCloudPlaylist(cursor: cursor, onFinish: onFinish)
                return
            }
            DispatchQueue.main.async {
                let viewContext = self.persistentContainer.viewContext
                try? viewContext.save()
            }
            onFinish()
        }
        
        let ckDatabase = CKContainer.default().privateCloudDatabase
        ckDatabase.add(operation)
    }
    
    public func getCloudPlaylist(onFinish: @escaping ()->Void) {
        let ckDatabase = CKContainer.default().privateCloudDatabase
        DispatchQueue.global().async {
            let ckQuery = CKQuery(recordType: "PlayList", predicate: NSPredicate(format: "id == %@ && storage == %@ && folder == %@", "", "", ""))
            ckDatabase.perform(ckQuery, inZoneWith: nil, completionHandler: { (ckRecords, error) in
                guard error == nil else {
                    print("\(String(describing: error?.localizedDescription))")
                    onFinish()
                    return
                }
                var serverSerial = Int64(0)
                var serverSerialEnd = Int64(0)
                for ckRecord in ckRecords!{
                    serverSerial = ckRecord["index"] as Int64? ?? 0
                    serverSerialEnd = ckRecord["serial"] as Int64? ?? 0
                }
                
                print(serverSerial, serverSerialEnd)
                
                DispatchQueue.main.async {
                    let viewContext = self.persistentContainer.viewContext

                    let fetchRequest1 = NSFetchRequest<NSFetchRequestResult>(entityName: "PlayList")
                    fetchRequest1.predicate = NSPredicate(format: "id == %@ && storage == %@ && folder == %@", "", "", "")
                    if let result = try? viewContext.fetch(fetchRequest1) as? [PlayList] {
                        if let forid = result.first {
                            forid.index = serverSerial
                            forid.serial = serverSerialEnd
                        }
                        else {
                            let forid = PlayList(context: viewContext)
                            forid.folder = ""
                            forid.id = ""
                            forid.storage = ""
                            forid.index = serverSerial
                            forid.serial = serverSerialEnd
                        }
                    }
                    try? viewContext.save()
                }
                
                let ckQuery = CKQuery(recordType: "PlayList", predicate: NSPredicate(format: "serial BETWEEN {%lld, %lld}", serverSerial, serverSerialEnd))
              
                self.subGetCloudPlaylist(q: ckQuery, onFinish: onFinish)
            })
        }
    }

    public func touchPlaylist(items: [[String: Any]]) {
        if !Thread.isMainThread {
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.main.async {
                self.touchPlaylist(items: items)
                group.leave()
            }
            group.wait()
        }
        else {
            let serial = Int64(Date().timeIntervalSince1970 * 1000)
            let viewContext = self.persistentContainer.viewContext
            
            let fetchRequest1 = NSFetchRequest<NSFetchRequestResult>(entityName: "PlayList")
            fetchRequest1.predicate = NSPredicate(format: "id == %@ && storage == %@ && folder == %@", "", "", "")
            if let result = try? viewContext.fetch(fetchRequest1) as? [PlayList] {
                if let forid = result.first {
                    forid.serial = serial
                }
                else {
                    let forid = PlayList(context: viewContext)
                    forid.folder = ""
                    forid.id = ""
                    forid.storage = ""
                    forid.index = serial
                    forid.serial = serial
                }
            }

            for item in items.filter({ !($0["isFolder"] as? Bool ?? true) }) {
                if let id = item["id"] as? String, let storage = item["storage"] as? String, let folder = item["folder"] as? String, let index = item["index"] as? Int64 {
                    let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "PlayList")
                    fetchrequest.predicate = NSPredicate(format: "id == %@ && storage == %@ && folder == %@ && index == %lld", id, storage, folder, index)
                    if let data = try? viewContext.fetch(fetchrequest) as? [PlayList] {
                        if let target = data.first {
                            target.serial = serial
                        }
                    }
                }
            }
            try? viewContext.save()
        }
    }
    
    public func getPlaylist() -> [[String: Any]] {
        var result = [[String: Any]]()
        if !Thread.isMainThread {
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.main.async {
                result = self.getPlaylist()
                group.leave()
            }
            group.wait()
        }
        else {
            let viewContext = self.persistentContainer.viewContext

            var startSerial = Int64(0)
            var endSerial = Int64(0)
            let fetchRequest1 = NSFetchRequest<NSFetchRequestResult>(entityName: "PlayList")
            fetchRequest1.predicate = NSPredicate(format: "id == %@ && storage == %@ && folder == %@", "", "", "")
            if let result = try? viewContext.fetch(fetchRequest1) as? [PlayList] {
                if let forid = result.first {
                    endSerial = forid.serial
                    startSerial = forid.index
                }
            }

            let fetchRequest2 = NSFetchRequest<NSFetchRequestResult>(entityName: "PlayList")
            fetchRequest2.predicate = NSPredicate(format: "NOT serial BETWEEN {%lld, %lld}", startSerial, endSerial)
            if let result = try? viewContext.fetch(fetchRequest2) as? [PlayList] {
                for item in result {
                    viewContext.delete(item)
                }
            }
            try? viewContext.save()

            let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "PlayList")
            fetchrequest.predicate = NSPredicate(format: "id != %@ && storage != %@ && serial BETWEEN {%lld, %lld}", "", "", startSerial, endSerial)
            if let data = try? viewContext.fetch(fetchrequest) as? [PlayList] {
                result = data.map { item in
                    var ret = [String: Any]()
                    ret["id"] = item.id
                    ret["storage"] = item.storage
                    ret["folder"] = item.folder
                    ret["index"] = item.index
                    return ret
                }
            }
        }
        return result
    }

    public func updatePlaylist(prevItem: [String: Any], newItem: [String: Any]) {
        let viewContext = persistentContainer.viewContext
        let serial = Int64(Date().timeIntervalSince1970 * 1000)

        let fetchRequest1 = NSFetchRequest<NSFetchRequestResult>(entityName: "PlayList")
        fetchRequest1.predicate = NSPredicate(format: "id == %@ && storage == %@ && folder == %@", "", "", "")
        if let result = try? viewContext.fetch(fetchRequest1) as? [PlayList] {
            if let forid = result.first {
                forid.serial = serial
            }
            else {
                let forid = PlayList(context: viewContext)
                forid.folder = ""
                forid.id = ""
                forid.storage = ""
                forid.index = serial
                forid.serial = serial
            }
        }
        else {
            let forid = PlayList(context: viewContext)
            forid.folder = ""
            forid.id = ""
            forid.storage = ""
            forid.index = serial
            forid.serial = serial
        }
        try? viewContext.save()

        var newData: PlayList
        if let id = prevItem["id"] as? String, let storage = prevItem["storage"] as? String, let folder = prevItem["folder"] as? String {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "PlayList")
            if let index = prevItem["index"] as? Int64 {
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@ && folder == %@ && index == %lld", id, storage, folder, index)
            }
            else {
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@ && folder == %@", id, storage, folder)
            }
            if let result = try? viewContext.fetch(fetchRequest) as? [PlayList] {
                newData = result.first ?? PlayList(context: viewContext)
                for object in result.dropFirst() {
                    viewContext.delete(object)
                }
            }
            else {
                newData = PlayList(context: viewContext)
            }
        }
        else {
            newData = PlayList(context: viewContext)
        }
        if let newid = newItem["id"] as? String, let newstorage = newItem["storage"] as? String, let newfolder = newItem["folder"] as? String {
            newData.id = newid
            newData.storage = newstorage
            newData.folder = newfolder
            if let index = newItem["index"] as? Int64 {
                newData.index = index
            }
            else {
                newData.index = Int64(Date().timeIntervalSince1970 * 1000)
            }
            newData.serial = serial
        }
        else {
            viewContext.delete(newData)
        }
        try? viewContext.save()
    }
    
    public func setMark(storage: String, targetID: String, parentID: String, position: Double?) {
        var result = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        guard let data = "storage=\(storage),target=\(targetID)".cString(using: .utf8) else {
            return
        }
        CC_SHA512(data, CC_LONG(data.count-1), &result)
        let target = result.map({ String(format: "%02hhx", $0) }).joined()

        let viewContext = persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Mark")
        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", target, storage)
        if let result = try? viewContext.fetch(fetchRequest) {
            for object in result {
                viewContext.delete(object as! NSManagedObject)
            }
        }
        
        if let position = position {
            let newitem = Mark(context: viewContext)
            newitem.id = target
            newitem.storage = storage
            newitem.parent = parentID
            newitem.position = position
            
            try? viewContext.save()
        }
        else {
            try? viewContext.save()
        }
    }

    public func setCloudMark(storage: String, targetID: String, parentID: String, position: Double?, group: DispatchGroup) {
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
        let parent = result2.map({ String(format: "%02hhx", $0) }).joined()

        let ckDatabase = CKContainer.default().privateCloudDatabase
        
        let ckQuery = CKQuery(recordType: "PlayTime", predicate: NSPredicate(format: "targetId == %@", argumentArray: [target]))

        group.enter()
        ckDatabase.perform(ckQuery, inZoneWith: nil, completionHandler: { (ckRecords, error) in
            defer {
                group.leave()
            }
            guard error == nil else {
                print("\(String(describing: error?.localizedDescription))")
                return
            }
            if ckRecords?.count ?? 0 > 0 {
                if let position = position {
                    for ckRecord in ckRecords!{
                        ckRecord["lastPosition"] = position
                        ckRecord["targetId"] = target
                        ckRecord["parentId"] = parent

                        group.enter()
                        ckDatabase.save(ckRecord, completionHandler: { (ckRecord, error) in
                            defer {
                                group.leave()
                            }
                            guard error == nil else {
                                print("\(String(describing: error?.localizedDescription))")
                                return
                            }
                        })
                    }
                }
                else {
                    for ckRecord in ckRecords!{
                        group.enter()
                        ckDatabase.delete(withRecordID: ckRecord.recordID, completionHandler: { (recordId, error) in
                            defer {
                                group.leave()
                            }
                            guard error == nil else {
                                print("\(String(describing: error?.localizedDescription))")
                                return
                            }
                        })
                    }
                }
            }
            else {
                if let position = position {
                    let ckRecord = CKRecord(recordType: "PlayTime")
                    ckRecord["lastPosition"] = position
                    ckRecord["targetId"] = target
                    ckRecord["parentId"] = parent

                    group.enter()
                    ckDatabase.save(ckRecord, completionHandler: { (ckRecords, error) in
                        defer {
                            group.leave()
                        }
                        guard error == nil else {
                            print("\(String(describing: error?.localizedDescription))")
                            return
                        }
                    })
                }
            }
        })
    }
    
    public func getImage(storage: String, parentId: String, baseName: String) -> RemoteData? {
        let viewContext = persistentContainer.viewContext
        
        let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
        fetchrequest.predicate = NSPredicate(format: "parent == %@ && storage == %@ && name BEGINSWITH %@", parentId, storage, baseName)
        guard let results = try? viewContext.fetch(fetchrequest) as? [RemoteData] else {
            return nil
        }
        if let img = results.filter({ ($0.name ?? "").hasSuffix(".jpg")}).first {
            return img
        }
        if let img = results.filter({ ($0.name ?? "").hasSuffix(".jpeg")}).first {
            return img
        }
        if let img = results.filter({ ($0.name ?? "").hasSuffix(".png")}).first {
            return img
        }
        if let img = results.filter({ ($0.name ?? "").hasSuffix(".tif")}).first {
            return img
        }
        if let img = results.filter({ ($0.name ?? "").hasSuffix(".tiff")}).first {
            return img
        }
        if let img = results.filter({ ($0.name ?? "").hasSuffix(".bmp")}).first {
            return img
        }
        return nil
    }
    
    public func getData(storage: String, fileId: String) -> RemoteData?  {
        let viewContext = persistentContainer.viewContext
        
        let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
        fetchrequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
        return ((try? viewContext.fetch(fetchrequest)) as? [RemoteData])?.first
    }
    
    public func getData(path: String) -> RemoteData?  {
        let viewContext = persistentContainer.viewContext
        
        let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
        fetchrequest.predicate = NSPredicate(format: "path == %@", path)
        return ((try? viewContext.fetch(fetchrequest)) as? [RemoteData])?.first
    }

    // MARK: - Core Data stack
    public lazy var persistentContainer: NSPersistentContainer = {
        /*
         The persistent container for the application. This implementation
         creates and returns a container, having loaded the store for the
         application to it. This property is optional since there are legitimate
         error conditions that could cause the creation of the store to fail.
         */
        let modelURL = Bundle(for: CloudFactory.self).url(forResource: "cloud", withExtension: "momd")!
        let mom = NSManagedObjectModel(contentsOf: modelURL)!

        let container = NSPersistentContainer(name: "cloud", managedObjectModel: mom)
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

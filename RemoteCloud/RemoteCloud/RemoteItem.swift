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

class PlaylistDocument: UIDocument {
    var userData: [(String, String, String, String)] = []
    
    convenience init(fileURL url: URL, userData: [(String, String, String, String)] = []) {
        self.init(fileURL: url)
        self.userData = userData
    }

    override func contents(forType typeName: String) throws -> Any {
        return userData.map({ "\($0.0)\0\($0.1)\0\($0.2)\0\($0.3)" }).joined(separator: "\0").data(using: .utf8)!
    }
    
    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        userData.removeAll()
        if let userContent = contents as? Data {
            let items = String(bytes: userContent, encoding: .utf8)?.components(separatedBy: "\0") ?? []
            for i in 0..<items.count/4 {
                userData.append((items[i*4], items[i*4+1], items[i*4+2], items[i*4+3]))
            }
        }
    }
}

public class dataItems {
    public func listData(storage: String, parentID: String) async -> [RemoteData]  {
        let viewContext = persistentContainer.viewContext
        
        let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
        fetchrequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", parentID, storage)
        fetchrequest.sortDescriptors = [NSSortDescriptor(key: "folder", ascending: false),
                                        NSSortDescriptor(key: "name", ascending: true)]
        do{
            return try viewContext.fetch(fetchrequest) as! [RemoteData]
        }
        catch{
            print(error)
            return []
        }
    }

    public func getPlaylists() async -> [String] {
        let url: URL
        if UserDefaults.standard.bool(forKey: "cloudPlaylist"), FileManager.default.ubiquityIdentityToken != nil {
            if let playlist = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appending(component: "Playlist") {
                try? FileManager.default.createDirectory(at: playlist, withIntermediateDirectories: true)
                url = playlist
            }
            else {
                return []
            }
        }
        else {
            if let playlist = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appending(path: "Playlist") {
                try? FileManager.default.createDirectory(at: playlist, withIntermediateDirectories: true)
                url = playlist
            }
            else {
                return []
            }
        }
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)) else {
            return []
        }
        return dirs.sorted(using: .localizedStandard)
    }
    
    public func getPlaylist(playlistName: String) async -> [(String, String, String, String)] {
        let url: URL
        if UserDefaults.standard.bool(forKey: "cloudPlaylist"), FileManager.default.ubiquityIdentityToken != nil {
            if let playlist = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appending(component: "Playlist") {
                try? FileManager.default.createDirectory(at: playlist, withIntermediateDirectories: true)
                url = playlist.appending(component: playlistName)
            }
            else {
                return []
            }
        }
        else {
            if let playlist = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appending(path: "Playlist") {
                try? FileManager.default.createDirectory(at: playlist, withIntermediateDirectories: true)
                url = playlist.appending(component: playlistName)
            }
            else {
                return []
            }
        }
        let playlistFile = PlaylistDocument(fileURL: url)
        guard await playlistFile.open() else {
            return []
        }
        let data = playlistFile.userData
        if playlistFile.documentState == .inConflict {
            let currentVersion = NSFileVersion.currentVersionOfItem(at: url)
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
            currentVersion?.isResolved = true
        }
        await playlistFile.close()
        return data
    }

    public func setPlaylist(playlistName: String, items: [(String, String, String, String)]) async {
        let url: URL
        if UserDefaults.standard.bool(forKey: "cloudPlaylist"), FileManager.default.ubiquityIdentityToken != nil {
            if let playlist = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appending(component: "Playlist") {
                try? FileManager.default.createDirectory(at: playlist, withIntermediateDirectories: true)
                url = playlist.appending(component: playlistName)
            }
            else {
                return
            }
        }
        else {
            if let playlist = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appending(path: "Playlist") {
                try? FileManager.default.createDirectory(at: playlist, withIntermediateDirectories: true)
                url = playlist.appending(component: playlistName)
            }
            else {
                return
            }
        }
        let playlistFile = PlaylistDocument(fileURL: url, userData: items)
        await playlistFile.save(to: url, for: .forOverwriting)
        if playlistFile.documentState == .inConflict {
            let currentVersion = NSFileVersion.currentVersionOfItem(at: url)
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
            currentVersion?.isResolved = true
        }
        await playlistFile.close()
    }

    public func deletePlaylist(playlistName: String) async {
        let url: URL
        if UserDefaults.standard.bool(forKey: "cloudPlaylist"), FileManager.default.ubiquityIdentityToken != nil {
            if let playlist = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appending(component: "Playlist") {
                try? FileManager.default.createDirectory(at: playlist, withIntermediateDirectories: true)
                url = playlist.appending(component: playlistName)
            }
            else {
                return
            }
        }
        else {
            if let playlist = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appending(path: "Playlist") {
                try? FileManager.default.createDirectory(at: playlist, withIntermediateDirectories: true)
                url = playlist.appending(component: playlistName)
            }
            else {
                return
            }
        }
        try? FileManager.default.removeItem(at: url)
    }

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
            let viewContext = persistentContainer.viewContext
            
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
            let viewContext = persistentContainer.viewContext
            
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
    
    public func getImage(storage: String, parentId: String, baseName: String) async -> RemoteData? {
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

    public func getData(storage: String, fileId: String) async -> RemoteData? {
        let viewContext = self.persistentContainer.viewContext
        return await viewContext.perform {
            let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchrequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            return ((try? viewContext.fetch(fetchrequest)) as? [RemoteData])?.first
        }
    }

    public func getData(path: String) async -> RemoteData? {
        let viewContext = self.persistentContainer.viewContext
        return await viewContext.perform {
            let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchrequest.predicate = NSPredicate(format: "path == %@", path)
            return ((try? viewContext.fetch(fetchrequest)) as? [RemoteData])?.first
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
        let modelURL = Bundle(for: CloudFactory.self).url(forResource: "cloud", withExtension: "momd")!
        let mom = NSManagedObjectModel(contentsOf: modelURL)!

        let container = NSPersistentContainer(name: "cloud", managedObjectModel: mom)
        let location = container.persistentStoreDescriptions.first!.url!
        let description = NSPersistentStoreDescription(url: location)
        description.shouldInferMappingModelAutomatically = true
        description.shouldMigrateStoreAutomatically = true
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
}

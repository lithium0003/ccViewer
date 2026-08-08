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
import UIKit

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

public struct RemoteDataDTO: Sendable, Identifiable, Hashable {
    public let cdate: Date?
    public let ext: String?
    public let folder: Bool
    public let hashstr: String?
    public let id: String?
    public let mdate: Date?
    public let name: String?
    public let parent: String?
    public let parentDate: Date?
    public let path: String?
    public let size: Int64
    public let storage: String?
    public let subend: Int64
    public let subid: String?
    public let subinfo: String?
    public let substart: Int64
    public let baseStorage: String?
    public let baseId: String?
}

public class dataItems {
    public func list(storage: String, targetID: String, force: Bool = false) async -> [RemoteDataDTO] {
        guard let service = await CloudFactory.shared.storageList.get(storage) else {
            return []
        }
        if targetID == "" {
            if force {
                await service.list(fileId: "")
            }
            let items = await CloudFactory.shared.data.listData(storage: storage, parentID: "")
            if items.isEmpty, !force {
                await service.list(fileId: "")
                return await CloudFactory.shared.data.listData(storage: storage, parentID: "")
            }
            return items
        }
        if let itemdata = await getData(storage: storage, fileId: targetID) {
            if force {
                await RemoteItem.removeSubitem(storage: storage, id: targetID)
            }
            if let item = await itemdata.getItem() {
                return await item.list(force: force)
            }
            return []
        }
        else {
            let comp = targetID.components(separatedBy: "\t")
            if force {
                await service.list(fileId: comp[0])
            }
            var results = await CloudFactory.shared.data.listData(storage: storage, parentID: comp[0])
            if results.isEmpty, !force {
                await service.list(fileId: comp[0])
                results = await CloudFactory.shared.data.listData(storage: storage, parentID: comp[0])
            }
            for i in 1..<comp.count {
                results = await list(storage: storage, targetID: comp[0..<i].joined(separator: "\t"), force: force)
            }
            return results
        }
    }
    
    public func listData(storage: String, parentID: String) async -> [RemoteDataDTO] {
        let viewContext = self.backgroundContext
        return await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", parentID, storage)
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: "folder", ascending: false),
                NSSortDescriptor(key: "name", ascending: true)
            ]
            
            do {
                let results = try viewContext.fetch(fetchRequest)
                
                return results.map { result in
                    RemoteDataDTO(
                        cdate: result.cdate,
                        ext: result.ext,
                        folder: result.folder,
                        hashstr: result.hashstr,
                        id: result.id,
                        mdate: result.mdate,
                        name: result.name,
                        parent: result.parent,
                        parentDate: result.parentDate,
                        path: result.path,
                        size: result.size,
                        storage: result.storage,
                        subend: result.subend,
                        subid: result.subid,
                        subinfo: result.subinfo,
                        substart: result.substart,
                        baseStorage: result.baseStorage,
                        baseId: result.baseId,
                    )
                }
            } catch {
                print("Failed to fetch listData: \(error)")
                return []
            }
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
    
    public func getImage(storage: String, parentId: String, baseName: String) async -> RemoteDataDTO? {
        let viewContext = self.backgroundContext
        return await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@ && name BEGINSWITH %@", parentId, storage, baseName)
            
            guard let results = try? viewContext.fetch(fetchRequest) else {
                return nil
            }
            
            let targetExtensions = [".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp"]
            var targetImage: RemoteData? = nil
            for ext in targetExtensions {
                if let img = results.first(where: { ($0.name ?? "").lowercased().hasSuffix(ext) }) {
                    targetImage = img
                    break
                }
            }
            
            guard let result = targetImage else {
                return nil
            }
            
            return RemoteDataDTO(
                cdate: result.cdate,
                ext: result.ext,
                folder: result.folder,
                hashstr: result.hashstr,
                id: result.id,
                mdate: result.mdate,
                name: result.name,
                parent: result.parent,
                parentDate: result.parentDate,
                path: result.path,
                size: result.size,
                storage: result.storage,
                subend: result.subend,
                subid: result.subid,
                subinfo: result.subinfo,
                substart: result.substart,
                baseStorage: result.baseStorage,
                baseId: result.baseId,
            )
        }
    }
    
    public func getData(storage: String, fileId: String) async -> RemoteDataDTO? {
        let context = self.backgroundContext
        return await context.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            if let result = (try? context.fetch(fetchRequest))?.first {
                return RemoteDataDTO(
                    cdate: result.cdate,
                    ext: result.ext,
                    folder: result.folder,
                    hashstr: result.hashstr,
                    id: result.id,
                    mdate: result.mdate,
                    name: result.name,
                    parent: result.parent,
                    parentDate: result.parentDate,
                    path: result.path,
                    size: result.size,
                    storage: result.storage,
                    subend: result.subend,
                    subid: result.subid,
                    subinfo: result.subinfo,
                    substart: result.substart,
                    baseStorage: result.baseStorage,
                    baseId: result.baseId
                )
            }
            return nil
        }
    }
    
    public func getData(path: String) async -> RemoteDataDTO? {
        let context = self.backgroundContext
        return await context.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "path == %@", path)
            fetchRequest.fetchLimit = 1
            if let result = (try? context.fetch(fetchRequest))?.first {
                return RemoteDataDTO(
                    cdate: result.cdate,
                    ext: result.ext,
                    folder: result.folder,
                    hashstr: result.hashstr,
                    id: result.id,
                    mdate: result.mdate,
                    name: result.name,
                    parent: result.parent,
                    parentDate: result.parentDate,
                    path: result.path,
                    size: result.size,
                    storage: result.storage,
                    subend: result.subend,
                    subid: result.subid,
                    subinfo: result.subinfo,
                    substart: result.substart,
                    baseStorage: result.baseStorage,
                    baseId: result.baseId
                )
            }
            return nil
        }
    }
    
    public func clearAllData() async throws {
        let context = self.backgroundContext
        try await context.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDeleteRequest.resultType = .resultTypeObjectIDs
            
            let result = try context.execute(batchDeleteRequest) as? NSBatchDeleteResult
            let objectIDArray = result?.result as? [NSManagedObjectID] ?? []
            
            let changes = [NSDeletedObjectsKey: objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
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
        let modelURL = Bundle(for: CloudFactory.self).url(forResource: "remote", withExtension: "momd")!
        let mom = NSManagedObjectModel(contentsOf: modelURL)!

        let container = NSPersistentContainer(name: "remote", managedObjectModel: mom)
        let location = container.persistentStoreDescriptions.first!.url!
        let description = NSPersistentStoreDescription(url: location)
        description.shouldAddStoreAsynchronously = true
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

    public lazy var backgroundContext = {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }()
}

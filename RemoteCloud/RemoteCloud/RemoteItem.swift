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
        let viewContext = viewContext
        return await viewContext.perform {
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
    
    public func getImage(storage: String, parentId: String, baseName: String) async -> RemoteData? {
        let viewContext = viewContext
        return await viewContext.perform {
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
    }

    public func getData(storage: String, fileId: String) async -> RemoteData? {
        let viewContext = self.viewContext
        return await viewContext.perform {
            let fetchrequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchrequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            return ((try? viewContext.fetch(fetchrequest)) as? [RemoteData])?.first
        }
    }

    public func getData(path: String) async -> RemoteData? {
        let viewContext = self.viewContext
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

    public lazy var viewContext = {
        persistentContainer.newBackgroundContext()
    }()
}

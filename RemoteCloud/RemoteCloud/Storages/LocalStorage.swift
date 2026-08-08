//
//  LocalStorage.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/04/10.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreData
import os.log

public class LocalStorage: RemoteStorageBase {

    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .Local)
        storageName = name
        rootName = ""
    }

    public override func getStorageType() -> CloudStorages {
        return .Local
    }
    
    override func listChildren(fileId: String = "", path: String = "") async {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var targetURL = documentsURL
        
        if fileId != "" {
            targetURL = targetURL.appendingPathComponent(fileId, conformingTo: .data)
        }
        
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: nil) else {
            return
        }
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = self.storageName ?? ""
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", fileId, storage)
            let existingResults = (try? viewContext.fetch(fetchRequest)) ?? []
            
            var existingDict = existingResults.reduce(into: [String: RemoteData]()) { dict, item in
                if let id = item.id { dict[id] = item }
            }
            
            for fileURL in fileURLs {
                guard let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false)),
                      let t = attr[.type] as? FileAttributeType, (t == .typeRegular || t == .typeDirectory) else {
                    continue
                }
                
                let id = LocalStorage.getIdFromURL(url: fileURL)
                let name = fileURL.lastPathComponent.precomposedStringWithCanonicalMapping
                let targetItem: RemoteData
                
                if let existing = existingDict.removeValue(forKey: id) {
                    targetItem = existing
                    targetItem.baseId = nil
                    targetItem.baseStorage = nil
                    targetItem.hashstr = nil
                    targetItem.subinfo = nil
                    targetItem.subid = nil
                    targetItem.substart = 0
                    targetItem.subend = 0
                } else {
                    targetItem = RemoteData(context: viewContext)
                }
                
                targetItem.storage = storage
                targetItem.id = id
                targetItem.name = name
                let comp = name.components(separatedBy: ".")
                if comp.count > 1 && t != .typeDirectory {
                    targetItem.ext = comp.last!.lowercased()
                } else {
                    targetItem.ext = ""
                }
                targetItem.cdate = attr[.creationDate] as? Date
                targetItem.mdate = attr[.modificationDate] as? Date
                targetItem.folder = (t == .typeDirectory)
                targetItem.size = attr[.size] as? NSNumber as? Int64 ?? 0
                targetItem.parent = fileId
                
                if fileId == "" {
                    targetItem.path = "\(storage):/\(name)"
                } else {
                    targetItem.path = "\(path)/\(name)"
                }
            }
            
            for staleItem in existingDict.values {
                LocalStorage.cascadeDelete(item: staleItem, in: viewContext)
            }
            
            // 6. 最後に1回だけセーブ
            try? viewContext.save()
        }
    }
    
    private class func storeItem(item: URL, parentFileId: String? = nil, parentPath: String? = nil, storageName: String, context: NSManagedObjectContext) {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: item.path(percentEncoded: false)) else {
            return
        }
        guard let t = attr[.type] as? FileAttributeType, (t == .typeRegular || t == .typeDirectory) else {
            return
        }
        
        // getIdFromURL もすでに class func なので LocalStorage. で呼ぶ
        let id = LocalStorage.getIdFromURL(url: item)
        let name = item.lastPathComponent.precomposedStringWithCanonicalMapping
        
        let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, storageName)
        fetchRequest.fetchLimit = 1
        
        let existingItem = try? context.fetch(fetchRequest).first
        let targetItem = existingItem ?? RemoteData(context: context)
        
        let prevParent = targetItem.parent
        let prevPath = targetItem.path
        
        if existingItem != nil {
            targetItem.baseId = nil
            targetItem.baseStorage = nil
            targetItem.hashstr = nil
            targetItem.subinfo = nil
            targetItem.subid = nil
            targetItem.substart = 0
            targetItem.subend = 0
        }
        
        targetItem.storage = storageName
        targetItem.id = id
        targetItem.name = name
        
        let comp = name.components(separatedBy: ".")
        if comp.count > 1 && t != .typeDirectory {
            targetItem.ext = comp.last!.lowercased()
        } else {
            targetItem.ext = ""
        }
        
        targetItem.cdate = attr[.creationDate] as? Date
        targetItem.mdate = attr[.modificationDate] as? Date
        targetItem.folder = (t == .typeDirectory)
        targetItem.size = attr[.size] as? NSNumber as? Int64 ?? 0
        
        targetItem.parent = (parentFileId == nil) ? prevParent : parentFileId
        if parentFileId == "" {
            targetItem.path = "\(storageName):/\(name)"
        } else if let path = (parentPath == nil) ? prevPath : parentPath {
            targetItem.path = "\(path)/\(name)"
        }
    }
    
    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil) async -> Data? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let targetURL = documentsURL.appendingPathComponent(fileId, conformingTo: .data)
        print(targetURL)

        var ret: Data?
        let reqOffset = Int(start ?? 0)
        do {
            let hFile = try FileHandle(forReadingFrom: targetURL)
            defer {
                do {
                    try hFile.close()
                }
                catch {
                    print(error)
                }
            }
            try hFile.seek(toOffset: UInt64(reqOffset))
            if let size = length {
                ret = hFile.readData(ofLength: Int(size))
            }
            else {
                ret = hFile.readDataToEndOfFile()
            }
        }
        catch {
            print(error)
        }
        return ret
    }
    
    class func getIdFromURL(url: URL) -> String {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let docComponent = documentsURL.pathComponents
        guard docComponent.last == "Documents" else {
            return ""
        }
        guard let appdir = docComponent.dropLast().last else {
            return ""
        }
        let targetComponent = url.pathComponents
        guard let idx = targetComponent.firstIndex(of: appdir) else {
            return ""
        }
        return targetComponent.dropFirst(idx+2).joined(separator: "/")
    }
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var targetURL = documentsURL
        
        if parentId != "" {
            targetURL = documentsURL.appendingPathComponent(parentId, conformingTo: .folder)
        }
        targetURL = targetURL.appendingPathComponent(newname, conformingTo: .folder)
        let storage = storageName ?? ""
        
        do {
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: false)
            let viewContext = CloudFactory.shared.data.backgroundContext
            await viewContext.perform {
                LocalStorage.storeItem(item: targetURL, parentFileId: parentId, parentPath: parentPath, storageName: storage, context: viewContext)
                try? viewContext.save()
            }
            let id = LocalStorage.getIdFromURL(url: targetURL)
            return id
        }
        catch {
            return nil
        }
    }
    
    override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if fromParentId == toParentId { return nil }
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        let fromURL = documentsURL.appendingPathComponent(fileId, conformingTo: .data)
        let name = fromURL.lastPathComponent
        
        var targetURL = documentsURL
        if toParentId != "" {
            targetURL = documentsURL.appendingPathComponent(toParentId, conformingTo: .folder)
        }
        targetURL = targetURL.appendingPathComponent(name, conformingTo: .data)
        
        do {
            try FileManager.default.moveItem(at: fromURL, to: targetURL)
            
            await viewContext.perform {
                var parentPath = ""
                
                if toParentId != "" {
                    let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", toParentId, storage)
                    fetchRequest.fetchLimit = 1
                    if let item = try? viewContext.fetch(fetchRequest).first {
                        parentPath = item.path ?? ""
                    }
                }
                
                let fetchRequest2 = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                fetchRequest2.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                if let results = try? viewContext.fetch(fetchRequest2) {
                    for object in results {
                        LocalStorage.cascadeDelete(item: object, in: viewContext)
                    }
                }
                
                LocalStorage.storeItem(
                    item: targetURL,
                    parentFileId: toParentId,
                    parentPath: parentPath,
                    storageName: storage,
                    context: viewContext
                )
                
                try? viewContext.save()
            }
            
            let id = LocalStorage.getIdFromURL(url: targetURL)
            await CloudFactory.shared.cache.remove(storage: storage, id: fileId)
            return id
        }
        catch {
            return nil
        }
    }
    
    override func deleteItem(fileId: String) async -> Bool {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let targetURL = documentsURL.appendingPathComponent(fileId, conformingTo: .data)
        
        do {
            try FileManager.default.removeItem(at: targetURL)
            let viewContext = CloudFactory.shared.data.backgroundContext
            let storage = self.storageName ?? ""
            
            await viewContext.perform {
                let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                if let results = try? viewContext.fetch(fetchRequest) {
                    for object in results {
                        LocalStorage.cascadeDelete(item: object, in: viewContext)
                    }
                }
                try? viewContext.save()
            }
            await CloudFactory.shared.cache.remove(storage: storage, id: fileId)
            return true
        }
        catch {
            return false
        }
    }
    
    override func renameItem(fileId: String, newname: String) async -> String? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fromURL = documentsURL.appendingPathComponent(fileId, conformingTo: .data)
        let newURL = fromURL.deletingLastPathComponent().appendingPathComponent(newname, conformingTo: .data)
        
        do {
            try FileManager.default.moveItem(at: fromURL, to: newURL)
            let viewContext = CloudFactory.shared.data.backgroundContext
            let storage = self.storageName ?? ""
            
            await viewContext.perform {
                var parentPath: String?
                var parentId: String?
                
                let fetchRequest2 = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                fetchRequest2.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                if let results = try? viewContext.fetch(fetchRequest2) {
                    for object in results {
                        parentPath = object.path
                        let component = parentPath?.components(separatedBy: "/")
                        parentPath = component?.dropLast().joined(separator: "/")
                        parentId = object.parent
                        LocalStorage.cascadeDelete(item: object, in: viewContext)
                    }
                }
                
                LocalStorage.storeItem(item: newURL, parentFileId: parentId, parentPath: parentPath, storageName: storage, context: viewContext)
                
                try? viewContext.save()
            }
            
            let newid = LocalStorage.getIdFromURL(url: newURL)
            await CloudFactory.shared.cache.remove(storage: storage, id: fileId)
            return newid
        }
        catch {
            return nil
        }
    }
    
    override func changeTime(fileId: String, newdate: Date) async -> String? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let targetURL = documentsURL.appendingPathComponent(fileId, conformingTo: .data)
        
        let storage = storageName ?? ""
        do {
            try FileManager.default.setAttributes([FileAttributeKey.modificationDate: newdate], ofItemAtPath: targetURL.path(percentEncoded: false))
            let viewContext = CloudFactory.shared.data.backgroundContext
            await viewContext.perform {
                LocalStorage.storeItem(item: targetURL, storageName: storage, context: viewContext)
                try? viewContext.save()
            }
            let id = LocalStorage.getIdFromURL(url: targetURL)
            return id
        }
        catch {
            return nil
        }
    }
    
    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await NetworkRemoteItem(path: path)
    }
    
    override func uploadFile(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var newURL = documentsURL
        if parentId != "" {
            newURL = documentsURL.appendingPathComponent(parentId, conformingTo: .data)
        }
        newURL = newURL.appendingPathComponent(uploadname, conformingTo: .data)
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        var parentPath = ""
        if parentId != "" {
            await viewContext.perform {
                let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, storage)
                fetchRequest.fetchLimit = 1
                if let results = try? viewContext.fetch(fetchRequest) {
                    if let item = results.first {
                        parentPath = item.path ?? ""
                    }
                }
            }
        }

        let attr = try FileManager.default.attributesOfItem(atPath: target.path(percentEncoded: false))
        let fileSize = attr[.size] as! UInt64
        try await progress?(0, Int64(fileSize))
        
        try FileManager.default.moveItem(at: target, to: newURL)
        try await progress?(Int64(fileSize), Int64(fileSize))

        await viewContext.perform {
            LocalStorage.storeItem(item: newURL, parentFileId: parentId, parentPath: parentPath, storageName: storage, context: viewContext)
            try? viewContext.save()
        }
        let id = LocalStorage.getIdFromURL(url: newURL)
        return id
    }
}

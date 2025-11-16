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
        print(documentsURL)

        if fileId != "" {
            targetURL = targetURL.appendingPathComponent(fileId, conformingTo: .data)
        }
        
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: nil) else {
            return
        }

        let viewContext = CloudFactory.shared.data.viewContext
        let storage = self.storageName ?? ""
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest) {
                for object in result {
                    viewContext.delete(object as! NSManagedObject)
                }
            }
        }
        
        for fileURL in fileURLs {
            storeItem(item: fileURL, parentFileId: fileId, parentPath: path, context: viewContext)
        }
        await viewContext.perform {
            try? viewContext.save()
        }
    }
    
    func storeItem(item: URL, parentFileId: String? = nil, parentPath: String? = nil, context: NSManagedObjectContext) {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: item.path(percentEncoded: false)) else {
            return
        }
        let id = getIdFromURL(url: item)
        let name = item.lastPathComponent.precomposedStringWithCanonicalMapping
        context.performAndWait {
            var prevParent: String?
            var prevPath: String?
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", id, self.storageName ?? "")
            if let result = try? context.fetch(fetchRequest) {
                for object in result {
                    if let item = object as? RemoteData {
                        prevPath = item.path
                        let component = parentPath?.components(separatedBy: "/")
                        prevPath = component?.dropLast().joined(separator: "/")
                        prevParent = item.parent
                    }
                    context.delete(object as! NSManagedObject)
                }
            }
            
            guard let t = attr[.type] as? FileAttributeType else {
                return
            }
            guard t == .typeRegular || t == .typeDirectory else {
                return
            }
            let newitem = RemoteData(context: context)
            newitem.storage = self.storageName
            newitem.id = id
            newitem.name = name
            let comp = name.components(separatedBy: ".")
            if comp.count >= 1 {
                newitem.ext = comp.last!.lowercased()
            }
            newitem.cdate = attr[.creationDate] as? Date
            newitem.mdate = attr[.modificationDate] as? Date
            newitem.folder = (attr[.type] as? FileAttributeType) == .typeDirectory
            newitem.size = attr[.size] as? NSNumber as? Int64 ?? 0
            newitem.hashstr = ""
            newitem.parent = (parentFileId == nil) ? prevParent : parentFileId
            if parentFileId == "" {
                newitem.path = "\(self.storageName ?? ""):/\(name)"
            }
            else {
                if let path = (parentPath == nil) ? prevPath : parentPath {
                    newitem.path = "\(path)/\(name)"
                }
            }
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
    
    func getIdFromURL(url: URL) -> String {
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
        
        do {
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: false)
            let viewContext = CloudFactory.shared.data.viewContext
            storeItem(item: targetURL, parentFileId: parentId, parentPath: parentPath, context: viewContext)
            let id = getIdFromURL(url: targetURL)
            await viewContext.perform {
                try? viewContext.save()
            }
            return id
        }
        catch {
            return nil
        }
    }
    
    @MainActor
    override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        if fromParentId == toParentId {
            return nil
        }

        let fromURL = documentsURL.appendingPathComponent(fileId, conformingTo: .data)
        let name = fromURL.lastPathComponent
        var targetURL = documentsURL
        var parentPath = ""
        if toParentId != "" {
            targetURL = documentsURL.appendingPathComponent(toParentId, conformingTo: .folder)
            let viewContext = CloudFactory.shared.data.viewContext
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", toParentId, self.storageName ?? "")
            if let result = try? viewContext.fetch(fetchRequest) {
                if let items = result as? [RemoteData] {
                    parentPath = items.first?.path ?? ""
                }
            }
        }
        let viewContext = CloudFactory.shared.data.viewContext
        let storage = self.storageName ?? ""
        await viewContext.perform {
            let fetchRequest2 = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest2.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest2) {
                for object in result {
                    viewContext.delete(object as! NSManagedObject)
                }
            }
        }
        targetURL = targetURL.appendingPathComponent(name, conformingTo: .data)
        do {
            try FileManager.default.moveItem(at: fromURL, to: targetURL)
            self.storeItem(item: targetURL, parentFileId: toParentId, parentPath: parentPath, context: viewContext)
            let id = self.getIdFromURL(url: targetURL)
            await viewContext.perform {
                try? viewContext.save()
            }
            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
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
            let viewContext = CloudFactory.shared.data.viewContext
            let storage = self.storageName ?? ""
            await viewContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                if let result = try? viewContext.fetch(fetchRequest) {
                    for object in result {
                        viewContext.delete(object as! NSManagedObject)
                    }
                }
            }
            deleteChildRecursive(parent: fileId, context: viewContext)
            await viewContext.perform {
                try? viewContext.save()
            }
            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
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
            var parentPath: String?
            var parentId: String?
            let viewContext = CloudFactory.shared.data.viewContext
            let storage = self.storageName ?? ""
            await viewContext.perform {
                let fetchRequest2 = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest2.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                if let result = try? viewContext.fetch(fetchRequest2) as? [RemoteData] {
                    for object in result {
                        parentPath = object.path
                        let component = parentPath?.components(separatedBy: "/")
                        parentPath = component?.dropLast().joined(separator: "/")
                        parentId = object.parent
                        viewContext.delete(object)
                    }
                }
            }
            self.storeItem(item: newURL, parentFileId: parentId, parentPath: parentPath, context: viewContext)
            await viewContext.perform {
                try? viewContext.save()
            }
            let newid = getIdFromURL(url: newURL)
            await CloudFactory.shared.cache.remove(storage: storageName!, id: fileId)
            return newid
        }
        catch {
            return nil
        }
    }
    
    override func changeTime(fileId: String, newdate: Date) async -> String? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let targetURL = documentsURL.appendingPathComponent(fileId, conformingTo: .data)
        
        do {
            try FileManager.default.setAttributes([FileAttributeKey.modificationDate: newdate], ofItemAtPath: targetURL.path(percentEncoded: false))
            let viewContext = CloudFactory.shared.data.viewContext
            self.storeItem(item: targetURL, context: viewContext)
            let id = getIdFromURL(url: targetURL)
            await viewContext.perform {
                try? viewContext.save()
            }
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
    
    @MainActor
    override func uploadFile(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var newURL = documentsURL
        if parentId != "" {
            newURL = documentsURL.appendingPathComponent(parentId, conformingTo: .data)
        }
        newURL = newURL.appendingPathComponent(uploadname, conformingTo: .data)
        
        var parentPath = ""
        if parentId != "" {
            let viewContext = CloudFactory.shared.data.viewContext
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, self.storageName ?? "")
            if let result = try? viewContext.fetch(fetchRequest) {
                if let items = result as? [RemoteData] {
                    parentPath = items.first?.path ?? ""
                }
            }
        }

        let attr = try FileManager.default.attributesOfItem(atPath: target.path(percentEncoded: false))
        let fileSize = attr[.size] as! UInt64
        try await progress?(0, Int64(fileSize))
        
        try FileManager.default.moveItem(at: target, to: newURL)
        
        let viewContext = CloudFactory.shared.data.viewContext
        self.storeItem(item: newURL, parentFileId: parentId, parentPath: parentPath, context: viewContext)
        let id = self.getIdFromURL(url: newURL)
        await viewContext.perform {
            try? viewContext.save()
        }
        try await progress?(Int64(fileSize), Int64(fileSize))
        return id
    }
}

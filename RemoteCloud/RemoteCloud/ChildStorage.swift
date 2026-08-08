//
//  ChildStorage.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/03/13.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreData
import os.log
import SwiftUI
import AuthenticationServices

public class ChildStorage: RemoteStorageBase {
    var baseRootStorage: String = ""
    var baseRootFileId: String = ""
    var baseRootFileChain: String = ""
    
    public init(name: String) async {
        super.init()
        storageName = name
        baseRootStorage = await getKeyChain(key: "\(name)_rootStorage") ?? ""
        baseRootFileId = await getKeyChain(key: "\(name)_rootFileId") ?? ""
        baseRootFileChain = await getKeyChain(key: "\(name)_rootFileChain") ?? ""
    }
    
    override public func cancel() async {
        await super.cancel()
        guard let s = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return
        }
        await s.cancel()
    }
    
    private func traceRoot() async -> String {
        guard var b = await CloudFactory.shared.data.getData(storage: baseRootStorage, fileId: baseRootFileId) else {
            return ""
        }
        var rootChain: [String] = []
        while b.id != "" {
            if b.id == nil { break }
            rootChain.append(b.id!)
            if let b2 = await CloudFactory.shared.data.getData(storage: baseRootStorage, fileId: b.parent ?? "") {
                b = b2
            }
            else {
                break
            }
        }
        rootChain.append("")
        return rootChain.reversed().joined(separator: "\n")
    }
    
    func recoverBaseRootIfNeeded() async {
        if await CloudFactory.shared.data.getData(storage: baseRootStorage, fileId: baseRootFileId) != nil {
            if baseRootFileChain.isEmpty {
                baseRootFileChain = await traceRoot()
                let _ = await setKeyChain(key: "\(storageName!)_rootFileChain", value: baseRootFileChain)
            }
            return
        }
        let pathIds = baseRootFileChain.split(separator: "\n").map { String($0) }
        
        guard let baseService = await CloudFactory.shared.storageList.get(baseRootStorage) else { return }
        var currentId = ""

        for id in pathIds {
            await baseService.list(fileId: currentId)
            let children = await CloudFactory.shared.data.listData(storage: baseRootStorage, parentID: currentId)
            guard let nextFolder = children.first(where: { $0.id == id }), let nextId = nextFolder.id else {
                print("Recovery failed: \(id) not found.")
                break
            }
            
            currentId = nextId
        }
        
        if currentId == baseRootFileId {
            print("Successfully recovered baseRoot path!")
        }
    }

    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        if baseRootFileId != "" && baseRootFileId != "" {
            return true
        }
        guard let (rootstrage, rootid) = await selectItem() else {
            return false
        }
        guard let s = await CloudFactory.shared.storageList.get(rootstrage) as? RemoteStorageBase else {
            return false
        }
        await s.list(fileId: rootid)

        baseRootStorage = rootstrage
        baseRootFileId = rootid
        baseRootFileChain = await traceRoot()
        
        os_log("%{public}@", log: self.log, type: .info, "saveInfo")
        let _ = await setKeyChain(key: "\(storageName!)_rootStorage", value: baseRootStorage)
        let _ = await setKeyChain(key: "\(storageName!)_rootFileId", value: baseRootFileId)
        let _ = await setKeyChain(key: "\(baseRootStorage)_depended_\(storageName!)", value: storageName!)
        let _ = await setKeyChain(key: "\(storageName!)_rootFileChain", value: baseRootFileChain)

        return true
    }
    
    override public func logout() async {
        if let name = storageName {
            let _ = await delKeyChain(key: "\(name)_rootStorage")
            let _ = await delKeyChain(key: "\(name)_rootFileId")
            let _ = await delKeyChain(key: "\(baseRootStorage)_depended_\(name)")
            let _ = await delKeyChain(key: "\(name)_rootFileChain")
        }
        await super.logout()
    }
    
    func ConvertDecryptName(name: String) -> String {
        return name
    }
    
    func ConvertDecryptSize(size: Int64) -> Int64 {
        return size
    }

    func ConvertEncryptName(name: String, folder: Bool) -> String {
        return name
    }
    
    func ConvertEncryptSize(size: Int64) -> Int64 {
        return size
    }
    
    func getBaseList(baseStorage: String, baseFileId: String) async -> [RemoteDataDTO] {
        let viewContext = CloudFactory.shared.data.backgroundContext
        
        return await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", baseFileId, baseStorage)
            if let results = try? viewContext.fetch(fetchRequest) {
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
            }
            return []
        }
    }
    
    override func listChildren(fileId: String, path: String) async {
        await recoverBaseRootIfNeeded()
        let fixFileId = (fileId == "") ? "\(baseRootStorage)\n\(baseRootFileId)" : fileId
        let array = fixFileId.components(separatedBy: .newlines)
        let baseStorage = array[0]
        let baseFileId = array[1]
        
        guard let s = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return
        }
        await s.list(fileId: baseFileId)
        
        let items = await getBaseList(baseStorage: baseStorage, baseFileId: baseFileId)
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storageName = self.storageName ?? ""
        let decryptName = { name in
            self.ConvertDecryptName(name: name)
        }
        let decryptSize = { size in
            self.ConvertDecryptSize(size: size)
        }

        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", fileId, storageName)
            let existingItems = (try? viewContext.fetch(fetchRequest)) ?? []
            
            var existingDict = [String: RemoteData]()
            for item in existingItems {
                if let id = item.id { existingDict[id] = item }
            }
            
            for item in items {
                guard let storage = item.storage, let id = item.id, let name = item.name else {
                    continue
                }
                let newid = "\(storage)\n\(id)"
                let newname = decryptName(name)
                
                let existing = existingDict.removeValue(forKey: newid)
                let targetItem = existing ?? RemoteData(context: viewContext)
                
                targetItem.storage = storageName
                targetItem.id = newid
                targetItem.name = newname
                
                let comp = newname.components(separatedBy: ".")
                if comp.count >= 1 {
                    targetItem.ext = comp.last!.lowercased()
                } else {
                    targetItem.ext = ""
                }
                
                targetItem.cdate = item.cdate
                targetItem.mdate = item.mdate
                targetItem.folder = item.folder
                targetItem.size = decryptSize(item.size)
                targetItem.hashstr = nil
                targetItem.parent = fileId
                
                if fileId == "" {
                    targetItem.path = "\(storageName):/\(newname)"
                } else {
                    targetItem.path = "\(path)/\(newname)"
                }

                targetItem.baseStorage = storage
                targetItem.baseId = id
            }
            
            for (_, orphan) in existingDict {
                ChildStorage.cascadeDelete(item: orphan, in: viewContext)
            }
            
            try? viewContext.save()
        }
    }
    
    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await NetworkRemoteItem(path: path)
    }

    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        let array = (parentId == "") ? [baseRootStorage, baseRootFileId] : parentId.components(separatedBy: .newlines)
        let baseStorage = array[0]
        let baseFileId = array[1]
        if baseStorage == "" {
            return nil
        }
        guard let s = await CloudFactory.shared.storageList.get(baseStorage) as? RemoteStorageBase else {
            return nil
        }
        
        var newBaseId = ""
        let id = await s.mkdir(parentId: baseFileId, newname: ConvertEncryptName(name: newname, folder: true))
        if let id = id {
            newBaseId = id
        }
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        let decryptName = { name in
            self.ConvertDecryptName(name: name)
        }
        let decryptSize = { size in
            self.ConvertDecryptSize(size: size)
        }

        return await viewContext.perform {
            var ret: String?
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
            fetchRequest.fetchLimit = 1
            if let results = try? viewContext.fetch(fetchRequest), let item = results.first {
                let newid = "\(item.storage ?? "")\n\(item.id ?? "")"
                let newname = decryptName(item.name ?? "")
                let newcdate = item.cdate
                let newmdate = item.mdate
                let newfolder = item.folder
                let newsize = decryptSize(item.size)
                
                let existingFetch = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                existingFetch.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                existingFetch.fetchLimit = 1
                let existing = (try? viewContext.fetch(existingFetch))?.first
                
                let targetItem = existing ?? RemoteData(context: viewContext)
                targetItem.storage = storage
                targetItem.id = newid
                targetItem.name = newname
                
                let comp = newname.components(separatedBy: ".")
                if comp.count >= 1 {
                    targetItem.ext = comp.last!.lowercased()
                } else {
                    targetItem.ext = ""
                }
                
                targetItem.cdate = newcdate
                targetItem.mdate = newmdate
                targetItem.folder = newfolder
                targetItem.size = newsize
                targetItem.hashstr = nil
                targetItem.parent = parentId
                
                if parentId == "" {
                    targetItem.path = "\(storage):/\(newname)"
                } else {
                    targetItem.path = "\(parentPath)/\(newname)"
                }

                targetItem.baseStorage = storage
                targetItem.baseId = id

                ret = newid
                try? viewContext.save()
            }
            return ret
        }
    }
    
    override func deleteItem(fileId: String) async -> Bool {
        guard fileId != "" else {
            return false
        }
        
        let array = fileId.components(separatedBy: .newlines)
        let baseStorage = array[0]
        let baseFileId = array[1]
        if baseFileId == "" || baseStorage == "" {
            return false
        }
        guard let s = await CloudFactory.shared.storageList.get(baseStorage) as? RemoteStorageBase else {
            return false
        }
        
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        var targetObjectID: NSManagedObjectID? = nil
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            targetObjectID = (try? viewContext.fetch(fetchRequest))?.first?.objectID
        }
        
        guard await s.delete(fileId: baseFileId) else {
            return false
        }
        
        await viewContext.perform {
            if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                ChildStorage.cascadeDelete(item: existing, in: viewContext)
            }
            try? viewContext.save()
        }
        return true
    }
    
    override func renameItem(fileId: String, newname: String) async -> String? {
        guard fileId != "" else {
            return nil
        }
        
        let array = fileId.components(separatedBy: .newlines)
        let baseStorage = array[0]
        let baseFileId = array[1]
        if baseFileId == "" || baseStorage == "" {
            return nil
        }
        guard let b = await CloudFactory.shared.storageList.get(baseStorage)?.get(fileId: baseFileId) else {
            return nil
        }
        guard let c = await CloudFactory.shared.storageList.get(storageName!)?.get(fileId: fileId) else {
            return nil
        }
        
        var parentPath = ""
        let parentId = c.parent
        if parentId != "" {
            parentPath = await getParentPath(parentId: parentId) ?? parentPath
        }
        var newBaseId = ""
        let id = await b.rename(newname: self.ConvertEncryptName(name: newname, folder: b.isFolder))
        if let id = id {
            newBaseId = id
        }
        let decryptName = { name in
            self.ConvertDecryptName(name: name)
        }
        let decryptSize = { size in
            self.ConvertDecryptSize(size: size)
        }

        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        var targetObjectID: NSManagedObjectID? = nil
        
        await viewContext.perform {
            let fetchRequest1 = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest1.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest1.fetchLimit = 1
            targetObjectID = (try? viewContext.fetch(fetchRequest1))?.first?.objectID
        }
        
        return await viewContext.perform {
            var ret: String?
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
            fetchRequest.fetchLimit = 1
            if let results = try? viewContext.fetch(fetchRequest), let item = results.first {
                let newid = "\(item.storage ?? "")\n\(item.id ?? "")"
                let decryptedName = decryptName(item.name ?? "")
                
                if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                    ChildStorage.cascadeDelete(item: existing, in: viewContext)
                }
                
                let targetItem = RemoteData(context: viewContext)
                targetItem.storage = storage
                targetItem.id = newid
                targetItem.name = decryptedName
                
                let comp = decryptedName.components(separatedBy: ".")
                if comp.count >= 1 {
                    targetItem.ext = comp.last!.lowercased()
                } else {
                    targetItem.ext = ""
                }
                
                targetItem.cdate = item.cdate
                targetItem.mdate = item.mdate
                targetItem.folder = item.folder
                targetItem.size = decryptSize(item.size)
                targetItem.parent = parentId
                
                if parentId == "" {
                    targetItem.path = "\(storage):/\(decryptedName)"
                } else {
                    targetItem.path = "\(parentPath)/\(decryptedName)"
                }
                
                targetItem.baseStorage = storage
                targetItem.baseId = id

                ret = newid
            }
            try? viewContext.save()
            return ret
        }
    }
    
    override func changeTime(fileId: String, newdate: Date) async -> String? {
        guard fileId != "" else {
            return nil
        }
        
        let array = fileId.components(separatedBy: .newlines)
        let baseStorage = array[0]
        let baseFileId = array[1]
        if baseFileId == "" || baseStorage == "" {
            return nil
        }
        guard let b = await CloudFactory.shared.storageList.get(baseStorage)?.get(fileId: baseFileId) else {
            return nil
        }
        guard let c = await CloudFactory.shared.storageList.get(storageName!)?.get(fileId: fileId) else {
            return nil
        }
        
        var parentPath = ""
        let parentId = c.parent
        if parentId != "" {
            parentPath = await getParentPath(parentId: parentId) ?? parentPath
        }
        var newBaseId = ""
        let id = await b.changetime(newdate: newdate)
        if let id = id {
            newBaseId = id
        }
        let decryptName = { name in
            self.ConvertDecryptName(name: name)
        }
        let decryptSize = { size in
            self.ConvertDecryptSize(size: size)
        }

        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        var targetObjectID: NSManagedObjectID? = nil
        
        await viewContext.perform {
            let fetchRequest1 = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest1.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest1.fetchLimit = 1
            targetObjectID = (try? viewContext.fetch(fetchRequest1))?.first?.objectID
        }
        
        return await viewContext.perform {
            var ret: String?
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
            fetchRequest.fetchLimit = 1
            if let results = try? viewContext.fetch(fetchRequest), let item = results.first {
                let newid = "\(item.storage ?? "")\n\(item.id ?? "")"
                let decryptedName = decryptName(item.name ?? "")
                
                if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                    ChildStorage.cascadeDelete(item: existing, in: viewContext)
                }
                
                let targetItem = RemoteData(context: viewContext)
                targetItem.storage = storage
                targetItem.id = newid
                targetItem.name = decryptedName
                
                let comp = decryptedName.components(separatedBy: ".")
                if comp.count >= 1 {
                    targetItem.ext = comp.last!.lowercased()
                } else {
                    targetItem.ext = ""
                }
                
                targetItem.cdate = item.cdate
                targetItem.mdate = item.mdate
                targetItem.folder = item.folder
                targetItem.size = decryptSize(item.size)
                targetItem.parent = parentId
                
                if parentId == "" {
                    targetItem.path = "\(storage):/\(decryptedName)"
                } else {
                    targetItem.path = "\(parentPath)/\(decryptedName)"
                }
                
                targetItem.baseStorage = storage
                targetItem.baseId = id

                ret = newid
            }
            try? viewContext.save()
            return ret
        }
    }
    
    override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        guard fileId != "" else {
            return nil
        }
        
        let array = fileId.components(separatedBy: .newlines)
        let baseStorage = array[0]
        let baseFileId = array[1]
        if baseFileId == "" || baseStorage == "" {
            return nil
        }
        
        let array3 = (toParentId == "") ? [baseRootStorage, baseRootFileId] : toParentId.components(separatedBy: .newlines)
        let tobaseStorage = array3[0]
        let tobaseFileId = array3[1]
        if tobaseStorage == "" {
            return nil
        }
        
        if baseStorage != tobaseStorage {
            return nil
        }
        
        guard let b = await CloudFactory.shared.storageList.get(baseStorage)?.get(fileId: baseFileId) else {
            return nil
        }
        
        var toParentPath = "\(tobaseStorage):/"
        if toParentId != "" {
            toParentPath = await getParentPath(parentId: toParentId) ?? toParentPath
        }
        
        var newBaseId = ""
        let id = await b.move(toParentId: tobaseFileId)
        if let id = id {
            newBaseId = id
        }
        let decryptName = { name in
            self.ConvertDecryptName(name: name)
        }
        let decryptSize = { size in
            self.ConvertDecryptSize(size: size)
        }

        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        var targetObjectID: NSManagedObjectID? = nil
        
        await viewContext.perform {
            let fetchRequest1 = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest1.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest1.fetchLimit = 1
            targetObjectID = (try? viewContext.fetch(fetchRequest1))?.first?.objectID
        }
        
        return await viewContext.perform {
            var ret: String?
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
            fetchRequest.fetchLimit = 1
            if let results = try? viewContext.fetch(fetchRequest), let item = results.first {
                let newid = "\(item.storage ?? "")\n\(item.id ?? "")"
                let decryptedName = decryptName(item.name ?? "")
                
                if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                    ChildStorage.cascadeDelete(item: existing, in: viewContext)
                }
                
                let targetItem = RemoteData(context: viewContext)
                targetItem.storage = storage
                targetItem.id = newid
                targetItem.name = decryptedName
                
                let comp = decryptedName.components(separatedBy: ".")
                if comp.count >= 1 {
                    targetItem.ext = comp.last!.lowercased()
                } else {
                    targetItem.ext = ""
                }
                
                targetItem.cdate = item.cdate
                targetItem.mdate = item.mdate
                targetItem.folder = item.folder
                targetItem.size = decryptSize(item.size)
                targetItem.parent = toParentId
                
                if toParentId == "" {
                    targetItem.path = "\(storage):/\(decryptedName)"
                } else {
                    targetItem.path = "\(toParentPath)/\(decryptedName)"
                }
                
                targetItem.baseStorage = storage
                targetItem.baseId = id

                ret = newid
            }
            try? viewContext.save()
            return ret
        }
    }
    
    override func uploadFile(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        os_log("%{public}@", log: log, type: .debug, "uploadFile(\(String(describing: type(of: self))):\(storageName ?? "") \(uploadname)->\(parentId) \(target)")
        defer {
            try? FileManager.default.removeItem(at: target)
        }
        
        let array = (parentId == "") ? [baseRootStorage, baseRootFileId] : parentId.components(separatedBy: .newlines)
        let baseStorage = array[0]
        let baseFileId = array[1]
        if baseStorage == "" {
            return nil
        }
        
        guard let s = await CloudFactory.shared.storageList.get(baseStorage) as? RemoteStorageBase else {
            return nil
        }
        guard let b = await CloudFactory.shared.storageList.get(baseStorage)?.get(fileId: baseFileId) else {
            return nil
        }
        let parentPath = b.path
        let storage = storageName ?? ""
        let decryptName = { name in
            self.ConvertDecryptName(name: name)
        }
        let decryptSize = { size in
            self.ConvertDecryptSize(size: size)
        }

        if let crypttarget = processFile(target: target) {
            let newBaseId = try await s.upload(parentId: baseFileId, uploadname: ConvertEncryptName(name: uploadname, folder: false), target: crypttarget, progress: progress)
            guard let newBaseId = newBaseId else {
                return nil
            }
            let viewContext = CloudFactory.shared.data.backgroundContext
            return await viewContext.perform {
                var ret: String? = nil
                let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
                fetchRequest.fetchLimit = 1
                if let results = try? viewContext.fetch(fetchRequest), let item = results.first {
                    let newid = "\(item.storage ?? "")\n\(item.id ?? "")"
                    let decryptedName = decryptName(item.name ?? "")
                    
                    let existingFetch = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                    existingFetch.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                    existingFetch.fetchLimit = 1
                    let existing = (try? viewContext.fetch(existingFetch))?.first
                    
                    let targetItem = existing ?? RemoteData(context: viewContext)
                    targetItem.storage = storage
                    targetItem.id = newid
                    targetItem.name = decryptedName
                    
                    let comp = decryptedName.components(separatedBy: ".")
                    if comp.count >= 1 {
                        targetItem.ext = comp.last!.lowercased()
                    } else {
                        targetItem.ext = ""
                    }
                    
                    targetItem.cdate = item.cdate
                    targetItem.mdate = item.mdate
                    targetItem.folder = item.folder
                    targetItem.size = decryptSize(item.size)
                    targetItem.parent = parentId
                    
                    if parentId == "" {
                        targetItem.path = "\(storage):/\(decryptedName)"
                    } else {
                        targetItem.path = "\(parentPath)/\(decryptedName)"
                    }

                    targetItem.baseStorage = item.storage
                    targetItem.baseId = item.id
                    
                    ret = newid
                }
                try? viewContext.save()
                return ret
            }
        }
        return nil
    }
    
    func processFile(target: URL) -> URL? {
        return target
    }
    
    override func readFile(fileId: String, start: Int64?, length: Int64?) async throws -> Data? {
        let array = fileId.components(separatedBy: .newlines)
        let baseStorage = array[0]
        let baseFileId = array[1]
        if baseFileId == "" || baseStorage == "" {
            return nil
        }
        guard let s = await CloudFactory.shared.storageList.get(baseStorage) else {
            return nil
        }
        return try await s.read(fileId: baseFileId, start: start, length: length)
    }
    
    override public func targetIsMovable(srcFileId: String, dstFileId: String) async -> Bool {
        let sarray = srcFileId.components(separatedBy: .newlines)
        let sBaseStorage = sarray[0]
        let sBaseFileId = sarray[1]
        
        let darray = dstFileId.components(separatedBy: .newlines)
        let dBaseStorage = darray[0]
        let dBaseFileId = darray[1]

        if sBaseStorage == dBaseStorage {
            return await CloudFactory.shared.storageList.get(sBaseStorage)?.targetIsMovable(srcFileId: sBaseFileId, dstFileId: dBaseFileId) ?? false
        }
        return false
    }
}

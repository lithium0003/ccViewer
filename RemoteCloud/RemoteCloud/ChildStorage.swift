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

    public init(name: String) async {
        super.init()
        storageName = name
        baseRootStorage = await getKeyChain(key: "\(name)_rootStorage") ?? ""
        baseRootFileId = await getKeyChain(key: "\(name)_rootFileId") ?? ""
    }
    
    override public func cancel() async {
        await super.cancel()
        guard let s = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return
        }
        await s.cancel()
    }

    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        if baseRootFileId != "" && baseRootFileId != "" {
            return true
        }
        guard let (rootstrage, rootid) = await selectItem() else {
            return false
        }
        baseRootStorage = rootstrage
        baseRootFileId = rootid
        
        os_log("%{public}@", log: self.log, type: .info, "saveInfo")
        let _ = await setKeyChain(key: "\(storageName!)_rootStorage", value: baseRootStorage)
        let _ = await setKeyChain(key: "\(storageName!)_rootFileId", value: baseRootFileId)
        let _ = await setKeyChain(key: "\(baseRootStorage)_depended_\(storageName!)", value: storageName!)

        guard let s = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return false
        }
        await s.list(fileId: baseRootFileId)
        return true
    }
    
    override public func logout() async {
        if let name = storageName {
            let _ = await delKeyChain(key: "\(name)_rootStorage")
            let _ = await delKeyChain(key: "\(name)_rootFileId")
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
    
    func getBaseList(baseStorage: String, baseFileId: String) async -> [RemoteData] {
        let viewContext = CloudFactory.shared.data.viewContext

        return await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", baseFileId, baseStorage)
            if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                return items
            }
            return []
        }
    }
    
    override func listChildren(fileId: String, path: String) async {
        let viewContext = CloudFactory.shared.data.viewContext
        let storage = storageName ?? ""
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest) {
                for object in result {
                    viewContext.delete(object as! NSManagedObject)
                }
            }
        }
        await viewContext.perform {
            try? viewContext.save()
        }

        let fixFileId = (fileId == "") ? "\(baseRootStorage)\n\(baseRootFileId)" : fileId
        let array = fixFileId.components(separatedBy: .newlines)
        let baseStorage = array[0]
        let baseFileId = array[1]
        guard let s = await CloudFactory.shared.storageList.get(baseRootStorage) as? RemoteStorageBase else {
            return
        }
        await s.list(fileId: baseFileId)

        let items = await getBaseList(baseStorage: baseStorage, baseFileId: baseFileId)
        for item in items {
            guard let storage = item.storage, let id = item.id, let name = item.name else {
                continue
            }
            let newid = "\(storage)\n\(id)"
            let newname = self.ConvertDecryptName(name: name)
            let newcdate = item.cdate
            let newmdate = item.mdate
            let newfolder = item.folder
            let newsize = self.ConvertDecryptSize(size: item.size)

            let storageName = storageName ?? ""
            await viewContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storageName)
                if let result = try? viewContext.fetch(fetchRequest) {
                    for object in result {
                        viewContext.delete(object as! NSManagedObject)
                    }
                }

                let newitem = RemoteData(context: viewContext)
                newitem.storage = storageName
                newitem.id = newid
                newitem.name = newname
                let comp = newname.components(separatedBy: ".")
                if comp.count >= 1 {
                    newitem.ext = comp.last!.lowercased()
                }
                newitem.cdate = newcdate
                newitem.mdate = newmdate
                newitem.folder = newfolder
                newitem.size = newsize
                newitem.hashstr = ""
                newitem.parent = fileId
                if fileId == "" {
                    newitem.path = "\(storageName):/\(newname)"
                }
                else {
                    newitem.path = "\(path)/\(newname)"
                }
            }
        }
        await viewContext.perform {
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
        
        let viewContext = CloudFactory.shared.data.viewContext
        let storage = storageName ?? ""
        let decryptName = { name in
            self.ConvertDecryptName(name: name)
        }
        let decryptSize = { size in
            self.ConvertDecryptSize(size: size)
        }
        return await viewContext.perform {
            var ret: String?
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
            if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                if let item = items.first {
                    let newid = "\(item.storage!)\n\(item.id!)"
                    let newname = decryptName(item.name!)
                    let newcdate = item.cdate
                    let newmdate = item.mdate
                    let newfolder = item.folder
                    let newsize = decryptSize(item.size)
                    
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                    if let result = try? viewContext.fetch(fetchRequest) {
                        for object in result {
                            viewContext.delete(object as! NSManagedObject)
                        }
                    }
                    
                    let newitem = RemoteData(context: viewContext)
                    newitem.storage = storage
                    newitem.id = newid
                    newitem.name = newname
                    let comp = newname.components(separatedBy: ".")
                    if comp.count >= 1 {
                        newitem.ext = comp.last!.lowercased()
                    }
                    newitem.cdate = newcdate
                    newitem.mdate = newmdate
                    newitem.folder = newfolder
                    newitem.size = newsize
                    newitem.hashstr = ""
                    newitem.parent = parentId
                    if parentId == "" {
                        newitem.path = "\(storage):/\(newname)"
                    }
                    else {
                        newitem.path = "\(parentPath)/\(newname)"
                    }
                    ret = newid
                    try? viewContext.save()
                }
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
        
        guard await s.delete(fileId: baseFileId) else {
            return false
        }

        let viewContext = CloudFactory.shared.data.viewContext        
        let storage = storageName ?? ""
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                for item in items {
                    viewContext.delete(item)
                }
                try? viewContext.save()
            }
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
        let viewContext = CloudFactory.shared.data.viewContext        
        let storage = storageName ?? ""
        let decryptName = { name in
            self.ConvertDecryptName(name: name)
        }
        let decryptSize = { size in
            self.ConvertDecryptSize(size: size)
        }
        await viewContext.perform {
            let fetchRequest1 = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest1.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest1), let items1 = result as? [RemoteData] {
                for item in items1 {
                    viewContext.delete(item)
                }
            }
        }
        return await viewContext.perform {
            var ret: String?
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
            if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                if let item = items.first {
                    let newid = "\(item.storage!)\n\(item.id!)"
                    let newname = decryptName(item.name!)
                    let newcdate = item.cdate
                    let newmdate = item.mdate
                    let newfolder = item.folder
                    let newsize = decryptSize(item.size)
                    
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                    if let result = try? viewContext.fetch(fetchRequest) {
                        for object in result {
                            viewContext.delete(object as! NSManagedObject)
                        }
                    }
                    
                    let newitem = RemoteData(context: viewContext)
                    newitem.storage = storage
                    newitem.id = newid
                    newitem.name = newname
                    let comp = newname.components(separatedBy: ".")
                    if comp.count >= 1 {
                        newitem.ext = comp.last!.lowercased()
                    }
                    newitem.cdate = newcdate
                    newitem.mdate = newmdate
                    newitem.folder = newfolder
                    newitem.size = newsize
                    newitem.hashstr = ""
                    newitem.parent = parentId
                    if parentId == "" {
                        newitem.path = "\(storage):/\(newname)"
                    }
                    else {
                        newitem.path = "\(parentPath)/\(newname)"
                    }
                    ret = newid
                }
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
        let viewContext = CloudFactory.shared.data.viewContext        
        let storage = storageName ?? ""
        let decryptName = { name in
            self.ConvertDecryptName(name: name)
        }
        let decryptSize = { size in
            self.ConvertDecryptSize(size: size)
        }
        await viewContext.perform {
            let fetchRequest1 = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest1.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest1), let items1 = result as? [RemoteData] {
                for item in items1 {
                    viewContext.delete(item)
                }
            }
        }
        return await viewContext.perform {
            var ret: String?
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
            if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                if let item = items.first {
                    let newid = "\(item.storage!)\n\(item.id!)"
                    let newname = decryptName(item.name!)
                    let newcdate = item.cdate
                    let newmdate = item.mdate
                    let newfolder = item.folder
                    let newsize = decryptSize(item.size)
                    
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                    if let result = try? viewContext.fetch(fetchRequest) {
                        for object in result {
                            viewContext.delete(object as! NSManagedObject)
                        }
                    }
                    
                    let newitem = RemoteData(context: viewContext)
                    newitem.storage = storage
                    newitem.id = newid
                    newitem.name = newname
                    let comp = newname.components(separatedBy: ".")
                    if comp.count >= 1 {
                        newitem.ext = comp.last!.lowercased()
                    }
                    newitem.cdate = newcdate
                    newitem.mdate = newmdate
                    newitem.folder = newfolder
                    newitem.size = newsize
                    newitem.hashstr = ""
                    newitem.parent = parentId
                    if parentId == "" {
                        newitem.path = "\(storage):/\(newname)"
                    }
                    else {
                        newitem.path = "\(parentPath)/\(newname)"
                    }
                    ret = newid
                }
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
        let viewContext = CloudFactory.shared.data.viewContext        
        let storage = storageName ?? ""
        let decryptName = { name in
            self.ConvertDecryptName(name: name)
        }
        let decryptSize = { size in
            self.ConvertDecryptSize(size: size)
        }
        await viewContext.perform {
            let fetchRequest1 = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest1.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            if let result = try? viewContext.fetch(fetchRequest1), let items1 = result as? [RemoteData] {
                for item in items1 {
                    viewContext.delete(item)
                }
            }
        }
        return await viewContext.perform {
            var ret: String?
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
            if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                if let item = items.first {
                    let newid = "\(item.storage!)\n\(item.id!)"
                    let newname = decryptName(item.name!)
                    let newcdate = item.cdate
                    let newmdate = item.mdate
                    let newfolder = item.folder
                    let newsize = decryptSize(item.size)
                    
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                    if let result = try? viewContext.fetch(fetchRequest) {
                        for object in result {
                            viewContext.delete(object as! NSManagedObject)
                        }
                    }
                    
                    let newitem = RemoteData(context: viewContext)
                    newitem.storage = storage
                    newitem.id = newid
                    newitem.name = newname
                    let comp = newname.components(separatedBy: ".")
                    if comp.count >= 1 {
                        newitem.ext = comp.last!.lowercased()
                    }
                    newitem.cdate = newcdate
                    newitem.mdate = newmdate
                    newitem.folder = newfolder
                    newitem.size = newsize
                    newitem.hashstr = ""
                    newitem.parent = toParentId
                    if toParentId == "" {
                        newitem.path = "\(storage):/\(newname)"
                    }
                    else {
                        newitem.path = "\(toParentPath)/\(newname)"
                    }
                    ret = newid
                }
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
            let viewContext = CloudFactory.shared.data.viewContext
            return await viewContext.perform {
                var ret: String? = nil
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newBaseId, baseStorage)
                if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                    if let item = items.first {
                        let newid = "\(item.storage!)\n\(item.id!)"
                        let newname = decryptName(item.name!)
                        let newcdate = item.cdate
                        let newmdate = item.mdate
                        let newfolder = item.folder
                        let newsize = decryptSize(item.size)
                        
                        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                        fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                        if let result = try? viewContext.fetch(fetchRequest) {
                            for object in result {
                                viewContext.delete(object as! NSManagedObject)
                            }
                        }
                        
                        let newitem = RemoteData(context: viewContext)
                        newitem.storage = storage
                        newitem.id = newid
                        newitem.name = newname
                        let comp = newname.components(separatedBy: ".")
                        if comp.count >= 1 {
                            newitem.ext = comp.last!.lowercased()
                        }
                        newitem.cdate = newcdate
                        newitem.mdate = newmdate
                        newitem.folder = newfolder
                        newitem.size = newsize
                        newitem.hashstr = ""
                        newitem.parent = parentId
                        if parentId == "" {
                            newitem.path = "\(storage):/\(newname)"
                        }
                        else {
                            newitem.path = "\(parentPath)/\(newname)"
                        }
                        ret = newid
                    }
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

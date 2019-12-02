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

    public override func auth(onFinish: ((Bool) -> Void)?) -> Void {
        onFinish?(true)
    }
    
    public override func getStorageType() -> CloudStorages {
        return .Local
    }

    override func ListChildren(fileId: String = "", path: String = "", onFinish: (() -> Void)?) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var targetURL = documentsURL
        
        if fileId != "" {
            targetURL = targetURL.appendingPathComponent(fileId)
        }
        
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: nil) else {
            onFinish?()
            return
        }
        
        let backgroudContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
        backgroudContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", fileId, self.storageName ?? "")
            if let result = try? backgroudContext.fetch(fetchRequest) {
                for object in result {
                    backgroudContext.delete(object as! NSManagedObject)
                }
            }
        }
        
        for fileURL in fileURLs {
            storeItem(item: fileURL, parentFileId: fileId, parentPath: path, context: backgroudContext)
        }
        backgroudContext.perform {
            try? backgroudContext.save()
            DispatchQueue.global().async {
                onFinish?()
            }
        }
    }
    
    func storeItem(item: URL, parentFileId: String? = nil, parentPath: String? = nil, context: NSManagedObjectContext) {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: item.path) else {
            return
        }
        let id = getIdFromURL(url: item)
        let name = item.lastPathComponent.precomposedStringWithCanonicalMapping
        context.perform {
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
    
    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil, callCount: Int = 0, onFinish: ((Data?) -> Void)?) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let targetURL = documentsURL.appendingPathComponent(fileId)
        print(targetURL)

        guard let attr = try? FileManager.default.attributesOfItem(atPath: targetURL.path) else {
            return
        }
        let maxlen = Int(truncating: attr[.size] as? NSNumber ?? 0)
        
        guard let stream = InputStream(url: targetURL) else {
            onFinish?(nil)
            return
        }
        stream.open()
        defer {
            stream.close()
        }
        
        let reqOffset = Int(start ?? 0)
        var offset = 0
        while offset < reqOffset {
            var buflen = reqOffset - offset
            if buflen > 1024*1024 {
                buflen = 1024*1024
            }
            var buf:[UInt8] = [UInt8](repeating: 0, count: buflen)
            let len = stream.read(&buf, maxLength: buf.count)
            if len <= 0 {
                print(stream.streamError!)
                onFinish?(nil)
                return
            }
            offset += len
        }
        
        let len = Int(length ?? Int64(maxlen - reqOffset))
        
        var buf:[UInt8] = [UInt8](repeating: 0, count: len)
        let rlen = stream.read(&buf, maxLength: buf.count)
        if rlen <= 0 {
            print(stream.streamError!)
            onFinish?(nil)
            return
        }
        onFinish?(Data(buf))
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
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var targetURL = documentsURL
        
        if parentId != "" {
            targetURL = documentsURL.appendingPathComponent(parentId, isDirectory: true)
        }
        targetURL = targetURL.appendingPathComponent(newname, isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: false)
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            storeItem(item: targetURL, parentFileId: parentId, parentPath: parentPath, context: backgroundContext)
            let id = getIdFromURL(url: targetURL)
            backgroundContext.perform {
                try? backgroundContext.save()
                DispatchQueue.global().async {
                    onFinish?(id)
                }
            }
        }
        catch {
            onFinish?(nil)
        }
    }
    
    override func moveItem(fileId: String, fromParentId: String, toParentId: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        if fromParentId == toParentId {
            onFinish?(nil)
            return
        }

        let fromURL = documentsURL.appendingPathComponent(fileId)
        let name = fromURL.lastPathComponent
        var targetURL = documentsURL
        var parentPath = ""
        if toParentId != "" {
            targetURL = documentsURL.appendingPathComponent(toParentId, isDirectory: true)
            if Thread.isMainThread {
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", toParentId, self.storageName ?? "")
                if let result = try? viewContext.fetch(fetchRequest) {
                    if let items = result as? [RemoteData] {
                        parentPath = items.first?.path ?? ""
                    }
                }
            }
            else {
                DispatchQueue.main.sync {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", toParentId, self.storageName ?? "")
                    if let result = try? viewContext.fetch(fetchRequest) {
                        if let items = result as? [RemoteData] {
                            parentPath = items.first?.path ?? ""
                        }
                    }
                }
            }
        }
        let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
        backgroundContext.perform {
            let fetchRequest2 = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest2.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
            if let result = try? backgroundContext.fetch(fetchRequest2) {
                for object in result {
                    backgroundContext.delete(object as! NSManagedObject)
                }
            }
        }
        targetURL = targetURL.appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: fromURL, to: targetURL)
            DispatchQueue.main.async {
                self.storeItem(item: targetURL, parentFileId: toParentId, parentPath: parentPath, context: backgroundContext)
            }
            let id = self.getIdFromURL(url: targetURL)
            backgroundContext.perform {
                try? backgroundContext.save()
                DispatchQueue.global().async {
                    onFinish?(id)
                }
            }
        }
        catch {
            onFinish?(nil)
        }
    }
    
    override func deleteItem(fileId: String, callCount: Int = 0, onFinish: ((Bool) -> Void)?) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let targetURL = documentsURL.appendingPathComponent(fileId)

        do {
            try FileManager.default.removeItem(at: targetURL)
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            backgroundContext.performAndWait {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                if let result = try? backgroundContext.fetch(fetchRequest) {
                    for object in result {
                        backgroundContext.delete(object as! NSManagedObject)
                    }
                }
                
                self.deleteChildRecursive(parent: fileId, context: backgroundContext)
            }
            backgroundContext.perform {
                try? backgroundContext.save()
                DispatchQueue.global().async {
                    onFinish?(true)
                }
            }
        }
        catch {
            onFinish?(false)
        }
    }
    
    override func renameItem(fileId: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fromURL = documentsURL.appendingPathComponent(fileId)
        let newURL = fromURL.deletingLastPathComponent().appendingPathComponent(newname)
        
        do {
            try FileManager.default.moveItem(at: fromURL, to: newURL)
            var parentPath: String?
            var parentId: String?
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            backgroundContext.perform {
                let fetchRequest2 = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest2.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                if let result = try? backgroundContext.fetch(fetchRequest2) as? [RemoteData] {
                    for object in result {
                        parentPath = object.path
                        let component = parentPath?.components(separatedBy: "/")
                        parentPath = component?.dropLast().joined(separator: "/")
                        parentId = object.parent
                        backgroundContext.delete(object)
                    }
                }
            }
            self.storeItem(item: newURL, parentFileId: parentId, parentPath: parentPath, context: backgroundContext)
            backgroundContext.perform {
                try? backgroundContext.save()
                let id = self.getIdFromURL(url: newURL)
                DispatchQueue.global().async {
                    onFinish?(id)
                }
            }
        }
        catch {
            onFinish?(nil)
        }
    }
    
    override func changeTime(fileId: String, newdate: Date, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let targetURL = documentsURL.appendingPathComponent(fileId)
        
        do {
            try FileManager.default.setAttributes([FileAttributeKey.modificationDate: newdate], ofItemAtPath: targetURL.path)
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            self.storeItem(item: targetURL, context: backgroundContext)
            let id = getIdFromURL(url: targetURL)
            backgroundContext.perform {
                try? backgroundContext.save()
                DispatchQueue.global().async {
                    onFinish?(id)
                }
            }
        }
        catch {
            onFinish?(nil)
        }
    }
    
    public override func getRaw(fileId: String) -> RemoteItem? {
        return NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) -> RemoteItem? {
        return NetworkRemoteItem(path: path)
    }
    
    override func uploadFile(parentId: String, sessionId: String, uploadname: String, target: URL, onFinish: ((String?)->Void)?) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var newURL = documentsURL
        if parentId != "" {
            newURL = documentsURL.appendingPathComponent(parentId)
        }
        newURL = newURL.appendingPathComponent(uploadname)
        
        var parentPath = ""
        if parentId != "" {
            if Thread.isMainThread {
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, self.storageName ?? "")
                if let result = try? viewContext.fetch(fetchRequest) {
                    if let items = result as? [RemoteData] {
                        parentPath = items.first?.path ?? ""
                    }
                }
            }
            else {
                DispatchQueue.main.sync {
                    let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                    
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, self.storageName ?? "")
                    if let result = try? viewContext.fetch(fetchRequest) {
                        if let items = result as? [RemoteData] {
                            parentPath = items.first?.path ?? ""
                        }
                    }
                }
            }
        }

        do {
            let attr = try FileManager.default.attributesOfItem(atPath: target.path)
            let fileSize = attr[.size] as! UInt64

            UploadManeger.shared.UploadFixSize(identifier: sessionId, size: Int(fileSize))
            
            try FileManager.default.moveItem(at: target, to: newURL)
            
            UploadManeger.shared.UploadProgress(identifier: sessionId, possition: Int(fileSize))
            
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            self.storeItem(item: newURL, parentFileId: parentId, parentPath: parentPath, context: backgroundContext)
            let id = self.getIdFromURL(url: newURL)
            backgroundContext.perform {
                try? backgroundContext.save()
                DispatchQueue.global().async {
                    onFinish?(id)
                }
            }
        }
        catch {
            onFinish?(nil)
        }
    }
    
}

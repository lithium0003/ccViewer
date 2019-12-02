//
//  FilesStorage.swift
//  RemoteCloud
//
//  Created by rei8 on 2019/12/02.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreData
import os.log
import UIKit
import CoreServices

public class FilesStorage: RemoteStorageBase, UIDocumentPickerDelegate {

    public override func getStorageType() -> CloudStorages {
        return .Files
    }

    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .Files)
        storageName = name
    }

    var cache_bookmarkData = Data()
    var bookmarkData: Data {
        if let name = storageName {
            if let base64 = getKeyChain(key: "\(name)_bookmarkData"), let bookmark = Data(base64Encoded: base64) {
                cache_bookmarkData = bookmark
            }
            return cache_bookmarkData
        }
        else {
            return Data()
        }
    }

    var authCallback: ((Bool)->Void)?
    
    public override func auth(onFinish: ((Bool) -> Void)?) -> Void {
        os_log("%{public}@", log: log, type: .debug, "auth(files:\(storageName ?? ""))")

        if authCallback != nil {
            onFinish?(false)
        }
        
        DispatchQueue.main.async {
            if #available(iOS 13.0, *) {
                if let controller = UIApplication.topViewController() {
                    let documentPicker =
                        UIDocumentPickerViewController(documentTypes: [kUTTypeFolder as String],
                                                       in: .open)
                    
                    documentPicker.delegate = self
                    self.authCallback = onFinish
                    controller.present(documentPicker, animated: true, completion: nil)
                }
                else {
                    onFinish?(false)
                }
            }
            else {
                if let controller = UIApplication.topViewController() {
                    let alart = UIAlertController(title: "iOS13 required", message: "folder selection feature needs >= iOS13", preferredStyle: .alert)
                    let cancel = UIAlertAction(title: "OK", style: .cancel) { action in
                        onFinish?(false)
                    }
                    alart.addAction(cancel)
                    
                    controller.present(alart, animated: true, completion: nil)
                }
                else {
                    onFinish?(false)
                }
            }
        }
    }
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let onFinish = authCallback else {
            return
        }
        guard let url = urls.first else {
            onFinish(false)
            return
        }
        print(url)
        do {
            // Start accessing a security-scoped resource.
            guard url.startAccessingSecurityScopedResource() else {
                // Handle the failure here.
                onFinish(false)
                return
            }

            // Make sure you release the security-scoped resource when you are done.
            defer { url.stopAccessingSecurityScopedResource() }

            let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            
            let _ = self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            
            DispatchQueue.global().async {
                onFinish(true)
            }
        }
        catch let error {
            // Handle the error here.
            print(error)
            onFinish(false)
        }
    }
    
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if let onFinish = authCallback {
            onFinish(false)
        }
    }
    
    public override func logout() {
        if let name = storageName {
            let _ = delKeyChain(key: "\(name)_bookmarkData")
        }
        super.logout()
    }

    override func ListChildren(fileId: String = "", path: String = "", onFinish: (() -> Void)?) {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("url is Stale", url)
                // Handle stale data here.
                let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let _ = self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            // Use the URL here.

            // Start accessing a security-scoped resource.
            guard url.startAccessingSecurityScopedResource() else {
                // Handle the failure here.
                onFinish?()
                return
            }

            // Make sure you release the security-scoped resource when you are done.
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Use file coordination for reading and writing any of the URL’s content.
            var error: NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { (url) in
                
                var targetURL = url
                if fileId != "" {
                    targetURL.appendPathComponent(fileId)
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
                    // Start accessing a security-scoped resource.
                    guard url.startAccessingSecurityScopedResource() else {
                        // Handle the failure here.
                        onFinish?()
                        return
                    }

                    // Make sure you release the security-scoped resource when you are done.
                    defer { url.stopAccessingSecurityScopedResource() }

                    storeItem(item: fileURL, parentFileId: fileId, parentPath: path, context: backgroudContext)
                }
                backgroudContext.perform {
                    try? backgroudContext.save()
                    DispatchQueue.global().async {
                        onFinish?()
                    }
                }
            }
        }
        catch let error {
            // Handle the error here.
            print(error)
            onFinish?()
        }
    }
    
    func getIdFromURL(url: URL) -> String? {
        var isStale = false
        guard let baseUrl = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        guard !isStale else {
            return nil
        }
        
        let base = baseUrl.pathComponents
        let target = url.pathComponents
        guard base.count <= target.count else {
            return nil
        }
        for i in 0..<base.count {
            guard base[i] == target[i] else {
                return nil
            }
        }
        return target.dropFirst(base.count).joined(separator: "/")
    }

    func storeItem(item: URL, parentFileId: String? = nil, parentPath: String? = nil, context: NSManagedObjectContext) {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: item.path) else {
            return
        }
        guard let id = getIdFromURL(url: item) else {
            return
        }
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
        
        if let cache = CloudFactory.shared.cache.getCache(storage: storageName!, id: fileId, offset: start ?? 0, size: length ?? -1) {
            if let data = try? Data(contentsOf: cache) {
                os_log("%{public}@", log: log, type: .debug, "hit cache(File:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                onFinish?(data)
                return
            }
        }

        os_log("%{public}@", log: log, type: .debug, "readFile(File:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("url is Stale", url)
                // Handle stale data here.
                let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let _ = self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            // Use the URL here.

            // Start accessing a security-scoped resource.
            guard url.startAccessingSecurityScopedResource() else {
                // Handle the failure here.
                onFinish?(nil)
                return
            }

            // Make sure you release the security-scoped resource when you are done.
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Use file coordination for reading and writing any of the URL’s content.
            var error: NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { (url) in
                
                var targetURL = url
                if fileId != "" {
                    targetURL.appendPathComponent(fileId)
                }
                
                // Start accessing a security-scoped resource.
                guard url.startAccessingSecurityScopedResource() else {
                    // Handle the failure here.
                    onFinish?(nil)
                    return
                }

                // Make sure you release the security-scoped resource when you are done.
                defer { url.stopAccessingSecurityScopedResource() }

                var ret: Data?
                let reqOffset = Int(start ?? 0)
                do {
                    let hFile = try FileHandle(forReadingFrom: targetURL)
                    defer {
                        do {
                            if #available(iOS 13.0, *) {
                                try hFile.close()
                            } else {
                                hFile.closeFile()
                            }
                        }
                        catch {
                            print(error)
                        }
                    }
                    if #available(iOS 13.0, *) {
                        try hFile.seek(toOffset: UInt64(reqOffset))
                    } else {
                        hFile.seek(toFileOffset: UInt64(reqOffset))
                    }
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
                if let d = ret {
                    CloudFactory.shared.cache.saveCache(storage: self.storageName!, id: fileId, offset: start ?? 0, data: d)
                }
                DispatchQueue.global().async {
                    onFinish?(ret)
                }
            }
        }
        catch let error {
            // Handle the error here.
            print(error)
            onFinish?(nil)
        }
    }

    public override func getRaw(fileId: String) -> RemoteItem? {
        return NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) -> RemoteItem? {
        return NetworkRemoteItem(path: path)
    }
    
    public override func makeFolder(parentId: String, parentPath: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {

        os_log("%{public}@", log: log, type: .debug, "makeFolder(File:\(storageName ?? "") \(parentId) \(newname)")

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("url is Stale", url)
                // Handle stale data here.
                let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let _ = self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            // Use the URL here.

            // Start accessing a security-scoped resource.
            guard url.startAccessingSecurityScopedResource() else {
                // Handle the failure here.
                onFinish?(nil)
                return
            }

            // Make sure you release the security-scoped resource when you are done.
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Use file coordination for reading and writing any of the URL’s content.
            var error: NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { (url) in
                
                var targetURL = url
                if parentId != "" {
                    targetURL = targetURL.appendingPathComponent(parentId, isDirectory: true)
                }
                targetURL = targetURL.appendingPathComponent(newname, isDirectory: true)

                do {
                    // Start accessing a security-scoped resource.
                    guard url.startAccessingSecurityScopedResource() else {
                        // Handle the failure here.
                        onFinish?(nil)
                        return
                    }

                    // Make sure you release the security-scoped resource when you are done.
                    defer { url.stopAccessingSecurityScopedResource() }

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
        }
        catch let error {
            // Handle the error here.
            print(error)
            onFinish?(nil)
        }
    }

    
    override func moveItem(fileId: String, fromParentId: String, toParentId: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {

        do {
            if fromParentId == toParentId {
                onFinish?(nil)
                return
            }

            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("url is Stale", url)
                // Handle stale data here.
                let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let _ = self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }

            // Use the URL here.

            // Start accessing a security-scoped resource.
            guard url.startAccessingSecurityScopedResource() else {
                // Handle the failure here.
                onFinish?(nil)
                return
            }

            // Make sure you release the security-scoped resource when you are done.
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Use file coordination for reading and writing any of the URL’s content.
            var error: NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { (url) in

                let fromURL = url.appendingPathComponent(fileId)
                let name = fromURL.lastPathComponent
                var targetURL = url
                var parentPath = ""
                if toParentId != "" {
                    targetURL = url.appendingPathComponent(toParentId, isDirectory: true)
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

                os_log("%{public}@", log: self.log, type: .debug, "moveItem(File:\(self.storageName ?? "") \(fromParentId)->\(toParentId)")

                do {
                    try FileManager.default.moveItem(at: fromURL, to: targetURL)
                    self.storeItem(item: targetURL, parentFileId: toParentId, parentPath: parentPath, context: backgroundContext)
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
        }
        catch let error {
            // Handle the error here.
            print(error)
            onFinish?(nil)
        }
    }
    
    override func deleteItem(fileId: String, callCount: Int = 0, onFinish: ((Bool) -> Void)?) {
        
        os_log("%{public}@", log: log, type: .debug, "deleteItem(File:\(storageName ?? "") \(fileId)")

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("url is Stale", url)
                // Handle stale data here.
                let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let _ = self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            // Use the URL here.

            // Start accessing a security-scoped resource.
            guard url.startAccessingSecurityScopedResource() else {
                // Handle the failure here.
                onFinish?(false)
                return
            }

            // Make sure you release the security-scoped resource when you are done.
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Use file coordination for reading and writing any of the URL’s content.
            var error: NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { (url) in
                
                var targetURL = url
                targetURL.appendPathComponent(fileId)

                guard url.startAccessingSecurityScopedResource() else {
                    // Handle the failure here.
                    onFinish?(false)
                    return
                }

                // Make sure you release the security-scoped resource when you are done.
                defer { url.stopAccessingSecurityScopedResource() }

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
        }
        catch let error {
            // Handle the error here.
            print(error)
            onFinish?(false)
        }
    }

    override func renameItem(fileId: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        
        os_log("%{public}@", log: log, type: .debug, "renameItem(File:\(storageName ?? "") \(fileId)")

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("url is Stale", url)
                // Handle stale data here.
                let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let _ = self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            // Use the URL here.

            // Start accessing a security-scoped resource.
            guard url.startAccessingSecurityScopedResource() else {
                // Handle the failure here.
                onFinish?(nil)
                return
            }

            // Make sure you release the security-scoped resource when you are done.
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Use file coordination for reading and writing any of the URL’s content.
            var error: NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { (url) in
                
                let fromURL = url.appendingPathComponent(fileId)
                let newURL = fromURL.deletingLastPathComponent().appendingPathComponent(newname)

                guard url.startAccessingSecurityScopedResource() else {
                    // Handle the failure here.
                    onFinish?(nil)
                    return
                }

                // Make sure you release the security-scoped resource when you are done.
                defer { url.stopAccessingSecurityScopedResource() }

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
        }
        catch let error {
            // Handle the error here.
            print(error)
            onFinish?(nil)
        }
    }

    override func changeTime(fileId: String, newdate: Date, callCount: Int = 0, onFinish: ((String?) -> Void)?) {

        os_log("%{public}@", log: log, type: .debug, "changeTime(File:\(storageName ?? "") \(fileId) \(newdate)")

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("url is Stale", url)
                // Handle stale data here.
                let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let _ = self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            // Use the URL here.

            // Start accessing a security-scoped resource.
            guard url.startAccessingSecurityScopedResource() else {
                // Handle the failure here.
                onFinish?(nil)
                return
            }

            // Make sure you release the security-scoped resource when you are done.
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Use file coordination for reading and writing any of the URL’s content.
            var error: NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { (url) in
                
                let targetURL = url.appendingPathComponent(fileId)

                guard url.startAccessingSecurityScopedResource() else {
                    // Handle the failure here.
                    onFinish?(nil)
                    return
                }

                // Make sure you release the security-scoped resource when you are done.
                defer { url.stopAccessingSecurityScopedResource() }

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
                    print(error)
                    onFinish?(nil)
                }
            }
        }
        catch let error {
            // Handle the error here.
            print(error)
            onFinish?(nil)
        }
    }

    override func uploadFile(parentId: String, sessionId: String, uploadname: String, target: URL, onFinish: ((String?)->Void)?) {
        
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

        os_log("%{public}@", log: log, type: .debug, "uploadFile(File:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("url is Stale", url)
                // Handle stale data here.
                let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                let _ = self.setKeyChain(key: "\(self.storageName ?? "")_bookmarkData", value: bookmarkData.base64EncodedString())
            }
            
            // Use the URL here.

            // Start accessing a security-scoped resource.
            guard url.startAccessingSecurityScopedResource() else {
                // Handle the failure here.
                onFinish?(nil)
                return
            }

            // Make sure you release the security-scoped resource when you are done.
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Use file coordination for reading and writing any of the URL’s content.
            var error: NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { (url) in
                
                var newURL = url
                if parentId != "" {
                    newURL = url.appendingPathComponent(parentId)
                }
                newURL = newURL.appendingPathComponent(uploadname)
                
                guard url.startAccessingSecurityScopedResource() else {
                    // Handle the failure here.
                    onFinish?(nil)
                    return
                }

                // Make sure you release the security-scoped resource when you are done.
                defer { url.stopAccessingSecurityScopedResource() }

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
        catch let error {
            // Handle the error here.
            print(error)
            onFinish?(nil)
        }
    }

}

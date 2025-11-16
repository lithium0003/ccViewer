//
//  RemoteStorage.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/09.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import os.log
import CoreData
import SwiftUI
import AuthenticationServices
import Combine

func DummyView() -> some View {
    Color.clear
}

public enum CloudStorages: Hashable, Identifiable, CaseIterable {
    public var id: Self {
        return self
    }

    case Local
    case Files
    case DropBox
    case GoogleDrive
    case OneDrive
    case pCloud
    case WebDAV
    case Samba
    case CryptCarotDAV
    case CryptRclone
    case Cryptomator
}

public protocol RemoteStorage {
    func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void, webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool
    func logout() async
    
    func list(fileId: String) async
    func list(path: String) async
    
    func read(fileId: String, start: Int64?, length: Int64?) async throws -> Data?
    
    func mkdir(parentId: String, newname: String) async -> String?
    func delete(fileId: String) async -> Bool
    func rename(fileId: String, newname: String) async -> String?
    func chagetime(fileId: String, newdate: Date) async -> String?
    func move(fileId: String, fromParent: String, toParent: String) async -> String?

    func upload(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)?) async throws -> String?
    
    func get(fileId: String) async -> RemoteItem?
    func get(path: String) async -> RemoteItem?

    func config() -> String
    func getStorageType() -> CloudStorages
    
    func cancel() async
    
    func targetIsMovable(srcFileId: String, dstFileId: String) async -> Bool

    var rootName: String { get }
}

public class RemoteItem {
    public let storage: String
    public let id: String
    public let name: String
    public let ext: String
    public let size: Int64
    public let path: String
    public let parent: String
    public let parentDate: Date?
    public let isFolder: Bool
    public let mDate: Date?
    public let cDate: Date?
    public let substart: Int64
    public let subend: Int64
    public let subid: String?
    let service: RemoteStorage

    init?(storage: String, id: String) async {
        self.storage = storage
        self.id = id
        guard let service = await CloudFactory.shared.storageList.get(storage) else {
            return nil
        }
        self.service = service
        if id == "" {
            self.name = ""
            self.ext = ""
            self.size = 0
            self.path = "\(storage):/"
            self.parent = ""
            self.parentDate = nil
            self.isFolder = true
            self.mDate = nil
            self.cDate = nil
            self.substart = -1
            self.subend = -1
            self.subid = nil
        }
        else {
            let item1 = await CloudFactory.shared.data.getData(storage: storage, fileId: id)
            guard let origin = item1 else {
                return nil
            }
            guard let name = origin.name else {
                return nil
            }
            self.name = name
            self.ext = origin.ext?.lowercased() ?? ""
            self.size = origin.size
            guard let path = origin.path else {
                return nil
            }
            self.path = path
            guard let parent = origin.parent else {
                return nil
            }
            self.isFolder = origin.folder
            self.parent = parent
            self.parentDate = origin.parentDate
            self.mDate = origin.mdate
            self.cDate = origin.cdate
            self.substart = origin.substart
            self.subend = origin.subend
            self.subid = origin.subid
        }
    }
    
    convenience init?(path: String) async {
        guard let origin = await CloudFactory.shared.data.getData(path: path) else {
            return nil
        }
        guard let storage = origin.storage else {
            return nil
        }
        guard let id = origin.id else {
            return nil
        }
        await self.init(storage: storage, id: id)
    }
    
    public func open() async -> RemoteStream {
        return await RemoteStream(size: 0)
    }
    
    public func cancel() async {
        await service.cancel()
    }
    
    public func mkdir(newname: String) async -> String? {
        if isFolder {
            return await service.mkdir(parentId: id, newname: newname)
        }
        else {
            return nil
        }
    }
    
    public func delete() async -> Bool {
        await service.delete(fileId: id)
    }
    
    public func rename(newname: String) async -> String? {
        await service.rename(fileId: id, newname: newname)
    }
    
    public func changetime(newdate: Date) async -> String? {
        await service.chagetime(fileId: id, newdate: newdate)
    }
    
    public func move(toParentId: String) async -> String? {
        await service.move(fileId: id, fromParent: parent, toParent: toParentId)
    }
    
    public func read(start: Int64? = nil, length: Int64? = nil) async throws -> Data? {
        try await service.read(fileId: id, start: start, length: length)
    }
}

public class RemoteStream {
    public internal(set) var size:Int64
    public var isLive = true
    
    init(size: Int64) async {
        self.size = size
    }
    
    public func read(position: Int64 = 0, length: Int = -1, onProgress: ((Int) async throws ->Void)? = nil) async throws -> Data? {
        return nil
    }
    
    public func preload(position: Int64, length: Int) async {        
    }
}

public class CloudFactory {
    private static let _shared = CloudFactory()
    public static var shared: CloudFactory { return _shared }
    let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "application")

    public let subject = PassthroughSubject<Int, Never>()
    public let initiaize = PassthroughSubject<Bool, Never>()
    public private(set) var initialized = false
    
    public actor StorageList {
        var list: [String: RemoteStorage] = [:]
        public var count: Int { list.count }
        public var keys: [String] { Array(list.keys) }
        
        public func clear() {
            list.removeAll()
        }
        
        public func assign(_ dict: [String: RemoteStorage]) {
            list = dict
        }
        
        public func add(_ key: String, _ value: RemoteStorage?) {
            list[key] = value
        }

        public func get() -> [String: RemoteStorage] {
            list
        }

        public func get(_ key: String) -> RemoteStorage? {
            list[key]
        }
        
        public func delete(_ key: String, callback: (RemoteStorage?) async -> Void) async {
            await callback(list[key])
            list.removeValue(forKey: key)
        }
    }
    public var storageList = StorageList()
    
    private init() {
        Task {
            await initializeDatabase()
            initiaize.send(true)
            initialized = true
        }
    }

    public func initializeDatabase() async {
        os_log("%{public}@", log: log, type: .info, "CloudFactory(init)")
        await storageList.clear()

        if let sList = getKeyChain(key: "remoteStorageList") {
            let classmap = Dictionary(uniqueKeysWithValues: CloudStorages.allCases.map() { (CloudFactory.getServiceName(service: $0), $0) })
            do {
                if let d = try NSKeyedUnarchiver.unarchivedDictionary(ofKeyClass: NSString.self, objectClass: NSString.self, from: sList) as? [String: String] {
                    print(d)
                    let tList = await withTaskGroup { group in
                        for (key, value) in d {
                            guard let jsondata = value.data(using: .utf8) else {
                                continue
                            }
                            guard let json = try? JSONSerialization.jsonObject(with: jsondata, options: []) else {
                                continue
                            }
                            guard let conf = json as? [String: String?], conf["name"] == key else {
                                continue
                            }
                            guard let valueService = conf["service"], let newService = valueService else {
                                continue
                            }
                            if let newClass = classmap[newService] {
                                os_log("%{public}@", log: log, type: .info, "Restore \(key) \(newService)")
                                group.addTask {
                                    await (key, self.newStorage(service: newClass, tagname: key))
                                }
                            }
                        }
                        var ret = [String: RemoteStorage?]()
                        for await (key, item) in group {
                            ret[key] = item
                        }
                        return ret
                    }
                    await storageList.assign(Dictionary(uniqueKeysWithValues: tList.filter() { $1 != nil }.map() { ($0, $1!)} ))
                    await saveConfig()
                }
            }
            catch {
                let _ = delKeyChain(key: "remoteStorageList")
                await saveConfig()
            }
        }
        await storageList.add("Local", await newStorage(service: .Local, tagname: "Local"))
    }
    
    public let data = dataItems()
    public let cache = FileCache()
    
    public func getShowList() async -> [String] {
        if let data = getKeyChain(key: "showList"), let a = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClasses: [NSString.self], from: data) as? [String] {
            return a
        }
        return await storages()
    }
    
    public func setShowList(_ list: [String]) {
        if list.isEmpty {
            let _ = delKeyChain(key: "showList")
        }
        else {
            var newList: [String] = []
            for listItem in list {
                if !newList.contains(listItem) {
                    newList.append(listItem)
                }
            }
            if let rData = try? NSKeyedArchiver.archivedData(withRootObject: newList, requiringSecureCoding: true) {
                let _ = setKeyChain(key: "showList", data: rData)
            }
        }
        subject.send(0)
    }
    
    public func getIcon(service: CloudStorages) -> UIImage? {
        switch service {
        case .GoogleDrive:
            return UIImage(named: "google", in: Bundle(for: type(of: self)), compatibleWith: nil)
        case .DropBox:
            return UIImage(named: "dropbox", in: Bundle(for: type(of: self)), compatibleWith: nil)
        case .OneDrive:
            return UIImage(named: "onedrive", in: Bundle(for: type(of: self)), compatibleWith: nil)
        case .pCloud:
            return UIImage(named: "pcloud", in: Bundle(for: type(of: self)), compatibleWith: nil)
        case .WebDAV:
            return UIImage(named: "webdav", in: Bundle(for: type(of: self)), compatibleWith: nil)
        case .Samba:
            return UIImage(named: "samba", in: Bundle(for: type(of: self)), compatibleWith: nil)
        case .CryptCarotDAV:
            return UIImage(named: "carot", in: Bundle(for: type(of: self)), compatibleWith: nil)
        case .CryptRclone:
            return UIImage(named: "rclone", in: Bundle(for: type(of: self)), compatibleWith: nil)
        case .Cryptomator:
            return UIImage(named: "cryptomator", in: Bundle(for: type(of: self)), compatibleWith: nil)
        case .Local:
            return UIImage(named: "local", in: Bundle(for: type(of: self)), compatibleWith: nil)
        case .Files:
            return UIImage(named: "files", in: Bundle(for: type(of: self)), compatibleWith: nil)
        }
    }

    public class func getServiceName(service: CloudStorages) -> String {
        switch service {
        case .GoogleDrive:
            return "GoogleDrive"
        case .DropBox:
            return "DropBox"
        case .OneDrive:
            return "OneDrive"
        case .pCloud:
            return "pCloud"
        case .WebDAV:
            return "WebDAV"
        case .Samba:
            return "Samba"
        case .CryptCarotDAV:
            return "CryptCarotDAV"
        case .CryptRclone:
            return "CryptRclone"
        case .Cryptomator:
            return "Cryptomator"
        case .Local:
            return "Local"
        case .Files:
            return "Files"
        }
    }
    
    class func createInstance(service: CloudStorages, tagname: String) async -> RemoteStorage {
        switch service {
        case .GoogleDrive:
            return GoogleDriveStorage(name: tagname)
        case .DropBox:
            return DropBoxStorage(name: tagname)
        case .OneDrive:
            return OneDriveStorage(name: tagname)
        case .pCloud:
            return pCloudStorage(name: tagname)
        case .WebDAV:
            return WebDAVStorage(name: tagname)
        case .Samba:
            return SambaStorage(name: tagname)
        case .CryptCarotDAV:
            return await CryptCarotDAV(name: tagname)
        case .CryptRclone:
            return await CryptRclone(name: tagname)
        case .Cryptomator:
            return await Cryptomator(name: tagname)
        case .Local:
            return LocalStorage(name: tagname)
        case .Files:
            return FilesStorage(name: tagname)
        }
    }

    func saveConfig() async {
        do {
            let seq = await storageList.get().filter({ $0.key != "Local" }).map(){ key, value in (key, value.config()) }
            let d = Dictionary(uniqueKeysWithValues: seq)
            let rData = try NSKeyedArchiver.archivedData(withRootObject: d, requiringSecureCoding: true)
            let _ = setKeyChain(key: "remoteStorageList", data: rData)
            os_log("%{public}@", log: log, type: .info, "saveConfig success")
        }
        catch {
            let _ = delKeyChain(key: "remoteStorageList")
        }
        await subject.send(storageList.count)
    }
    
    public func newStorage(service: CloudStorages, tagname: String) async -> RemoteStorage? {
        if let p = await storageList.get()[tagname] {
            return p
        }
        await storageList.add(tagname, CloudFactory.createInstance(service: service, tagname: tagname))
        await saveConfig()
        if initialized {
            await setShowList(getShowList() + [tagname])
        }
        return await storageList.get()[tagname]
    }

    public func storages() async -> [String] {
        return await [String](storageList.get().keys).sorted()
    }
    
    public func delStorage(tagname: String) async {
        await storageList.delete(tagname) { p in
            if let p {
                await p.logout()
                let depended = getKeyChain(cond: "^\(tagname)_depended")
                for (key, dep) in depended {
                    if let s = String(data: dep, encoding: .utf8) {
                        await delStorage(tagname: s)
                        let _ = delKeyChain(key: key)
                    }
                }
            }
        }
        await saveConfig()
        await setShowList(getShowList().filter({ $0 != tagname }))
    }

    public func delAllStorage() async {
        for storage in await storageList.keys {
            await delStorage(tagname: storage)
        }
    }
    
    public func removeAllAuth() async {
        if delAllKeyChain() {
            await storageList.clear()
            await storageList.add("Local", await newStorage(service: .Local, tagname: "Local"))
        }
    }

    func getKeyChain(key: String) -> Data? {
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key,
                                  kSecReturnData as String: kCFBooleanTrue as Any]
        
        var data: AnyObject?
        let matchingStatus = withUnsafeMutablePointer(to: &data){
            SecItemCopyMatching(dic as CFDictionary, UnsafeMutablePointer($0))
        }
        
        if matchingStatus == errSecSuccess {
            if let getData = data as? Data {
                return getData
            }
            return nil
        } else {
            return nil
        }
    }
    
    func getKeyChain(cond: String) -> [String: Data] {
        guard let regex = try? NSRegularExpression(pattern: cond, options: []) else {
            return [:]
        }

        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecReturnAttributes as String: kCFBooleanTrue as Any,
                                  kSecReturnData as String: kCFBooleanTrue as Any,
                                  kSecMatchLimit as String: kSecMatchLimitAll]
        
        var data: AnyObject?
        let matchingStatus = withUnsafeMutablePointer(to: &data){
            SecItemCopyMatching(dic as CFDictionary, UnsafeMutablePointer($0))
        }
        
        if matchingStatus == errSecSuccess {
            var ret: [String: Data] = [:]
            if let result = data as? [[String: Any]] {
                for item in result {
                    if let account = item[kSecAttrAccount as String] as? String {
                        if regex.numberOfMatches(in: account, options: [], range: NSRange(location: 0, length: account.count)) != 0 {
                            if let d = item[kSecValueData as String] as? Data {
                                ret[account] = d
                            }
                            else {
                                print("取得失敗: Dataが不正")
                            }
                        }
                    }
                }
            }
            return ret
        } else {
            print("取得失敗")
            return [:]
        }
    }
    
    func delAllKeyChain() -> Bool {
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrSynchronizable as String: kCFBooleanTrue as Any]
        let dic2: [String: Any] = [kSecClass as String: kSecClassGenericPassword]
        let dic3: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
                                  kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]

        if SecItemDelete(dic as CFDictionary) == errSecSuccess {
            print("削除成功")
        } else {
            print("削除失敗")
        }
        if SecItemDelete(dic2 as CFDictionary) == errSecSuccess {
            print("削除成功")
        } else {
            print("削除失敗")
        }
        if SecItemDelete(dic3 as CFDictionary) == errSecSuccess {
            print("削除成功")
        } else {
            print("削除失敗")
        }
        return true
    }

    func delKeyChain(key: String) -> Bool {
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key]
        
        if SecItemDelete(dic as CFDictionary) == errSecSuccess {
            print("削除成功")
            return true
        } else {
            print("削除失敗")
            return false
        }
    }
    
    func setKeyChain(key: String, data: Data) -> Bool{
         let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key,
                                  kSecValueData as String: data]
        
        var itemAddStatus: OSStatus?
        let matchingStatus = SecItemCopyMatching(dic as CFDictionary, nil)
        
        if matchingStatus == errSecItemNotFound {
            // 保存
            itemAddStatus = SecItemAdd(dic as CFDictionary, nil)
        } else if matchingStatus == errSecSuccess {
            // 更新
            itemAddStatus = SecItemUpdate(dic as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            print("保存失敗")
        }
        
        if itemAddStatus == errSecSuccess {
            return true
        } else {
            print("保存失敗")
            return false
        }
    }
}

public class RemoteStorageBase: NSObject, RemoteStorage {
    static let semaphore_key = Semaphore(value: 1)
    
    public var rootName: String = ""
    
    public func read(fileId: String, start: Int64? = nil, length: Int64? = nil) async throws -> Data? {
        try await readFile(fileId: fileId, start: start, length: length)
    }
    
    public func upload(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        try await uploadFile(parentId: parentId, uploadname: uploadname, target: target, progress: progress)
    }
    
    public func move(fileId: String, fromParent: String, toParent: String) async -> String? {
        await moveItem(fileId: fileId, fromParentId: fromParent, toParentId: toParent)
    }
    
    public func chagetime(fileId: String, newdate: Date) async -> String? {
        await changeTime(fileId: fileId, newdate: newdate)
    }
    
    public func rename(fileId: String, newname: String) async -> String? {
        await renameItem(fileId: fileId, newname: newname)
    }
    
    public func delete(fileId: String) async -> Bool {
        await deleteItem(fileId: fileId)
    }
    
    func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        return nil
    }

    public func get(fileId: String) async -> RemoteItem? {
        await fileId.contains("\t") ? getSubitem(fileId: fileId) : getRaw(fileId: fileId)
    }
    
    public func get(path: String) async -> RemoteItem? {
        await getRaw(path: path)
    }

    public func getRaw(fileId: String) async -> RemoteItem? {
        await RemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public func getRaw(path: String) async -> RemoteItem? {
        await RemoteItem(path: path)
    }
    
    public func getStorageType() -> CloudStorages {
        return .GoogleDrive
    }
    
    let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "application")
    var storageName: String?
    var service: String?
    var cancelTime = Date(timeIntervalSince1970: 0)

    public func cancel() async {
        cancelTime = Date(timeIntervalSinceNow: 0.5)
    }
    
    public func config() -> String {
        let conf = ["name": storageName,
                    "service": service
        ]
        do {
            let json = try JSONSerialization.data(withJSONObject: conf, options: [])
            return String(bytes: json, encoding: .utf8) ?? ""
        }
        catch {
            return ""
        }
    }

    public func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        return await withCheckedContinuation { continuation in
            callback(DummyView(), continuation)
        }
    }
    
    @discardableResult
    func deleteItems(name: String) async -> Bool {
        await CloudFactory.shared.data.persistentContainer.performBackgroundTask { context in
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "storage == %@", name)
            if let result = try? context.fetch(fetchRequest) {
                for object in result {
                    context.delete(object as! NSManagedObject)
                }
            }
            
            try? context.save()
            return true
        }
    }
    
    public func logout() async {
        if let name = storageName {
            os_log("%{public}@", log: log, type: .info, "logout(\(name))")
            
            await deleteItems(name: name)
        }
    }

    func listChildren(fileId: String = "", path: String = "") async {
    }
 
    func deleteChild(parent: String, context: NSManagedObjectContext) async {
        let storage = storageName ?? ""
        await context.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", parent, storage)
            if let result = try? context.fetch(fetchRequest), let items = result as? [RemoteData] {
                for item in items {
                    context.delete(item)
                }
            }
        }
    }

    func deleteChildRecursive(parent: String, context: NSManagedObjectContext) {
        context.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", parent, self.storageName ?? "")
            if let result = try? context.fetch(fetchRequest), let items = result as? [RemoteData] {
                for item in items {
                    if let p = item.id {
                        self.deleteChildRecursive(parent: p, context: context)
                    }
                    context.delete(item)
                }
            }
        }
    }
    

    public func list(fileId: String) async {
        if fileId == "" {
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            await deleteChild(parent: fileId, context: backgroundContext)
            await backgroundContext.perform {
                try? backgroundContext.save()
            }
            await listChildren()
        }
        else {
            var path = ""
            var isFoler = false
            let storage = storageName ?? ""
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            await backgroundContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
                if let result = try? backgroundContext.fetch(fetchRequest) {
                    if let items = result as? [RemoteData] {
                        path = items.first?.path ?? ""
                        isFoler = items.first?.folder ?? false
                    }
                }
            }
            if !isFoler {
                return
            }
            if path != "" {
                await deleteChild(parent: fileId, context: backgroundContext)
            }
            await backgroundContext.perform {
                if path != "" {
                    try? backgroundContext.save()
                }
            }
            await listChildren(fileId: fileId, path: path)
        }
    }
    
    public func list(path: String) async {
        if path == "" || path == "\(storageName ?? ""):/" || path == "\(storageName ?? ""):" {
            await listChildren()
        }
        else {
            let parentPath = path.components(separatedBy: "/").dropLast().joined(separator: "/")
            await list(path: parentPath)
            
            var ids: [String] = []
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            await backgroundContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "path == %@", path)
                if let result = try? backgroundContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                    ids = items.filter { $0.id != nil && $0.folder }.map { $0.id! }
                }
            }
            for id in ids {
                await deleteChild(parent: id, context: backgroundContext)
            }
            await backgroundContext.perform {
                try? backgroundContext.save()
            }

            for id in ids {
                await listChildren(fileId: id, path: path)
            }
        }
    }

    @MainActor
    public func mkdir(parentId: String, newname: String) async -> String? {
        if parentId == "" {
            return await makeFolder(parentId: parentId, parentPath: "", newname: newname)
        }
        else{
            var path = ""
            let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, self.storageName ?? "")
            if let result = try? viewContext.fetch(fetchRequest) {
                if let items = result as? [RemoteData] {
                    path = items.first?.path ?? ""
                }
            }
            if path != "" {
                return await makeFolder(parentId: parentId, parentPath: path, newname: newname)
            }
            else {
                return nil
            }
        }
    }
    
    @discardableResult
    func deleteItem(fileId: String) async -> Bool {
        return false
    }
    
    func renameItem(fileId: String, newname: String) async -> String? {
        return nil
    }
    
    func changeTime(fileId: String, newdate: Date) async -> String? {
        return nil
    }
    
    func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        return nil
    }
    
    func readFile(fileId: String, start: Int64?, length: Int64?) async throws -> Data? {
        return nil
    }
    
    func uploadFile(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        return nil
    }
    
    func getKeyChain(key: String) async -> String? {
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key,
                                  kSecReturnData as String: kCFBooleanTrue as Any]
        
        await RemoteStorageBase.semaphore_key.wait()
        defer {
            Task { await RemoteStorageBase.semaphore_key.signal() }
        }
        var data: AnyObject?
        let matchingStatus = withUnsafeMutablePointer(to: &data){
            SecItemCopyMatching(dic as CFDictionary, UnsafeMutablePointer($0))
        }
        
        if matchingStatus == errSecSuccess {
            if let getData = data as? Data,
                let getStr = String(data: getData, encoding: .utf8) {
                return getStr
            }
            return nil
        } else {
            return nil
        }
    }

    func delKeyChain(key: String) async -> Bool {
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key]
        
        await RemoteStorageBase.semaphore_key.wait()
        defer {
            Task { await RemoteStorageBase.semaphore_key.signal() }
        }
        if SecItemDelete(dic as CFDictionary) == errSecSuccess {
            return true
        } else {
            return false
        }
    }

    func setKeyChain(key: String, value: String) async -> Bool{
        let data = value.data(using: .utf8)
        
        guard let _data = data else {
            return false
        }
        
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key,
                                  kSecValueData as String: _data]
        
        await RemoteStorageBase.semaphore_key.wait()
        defer {
            Task { await RemoteStorageBase.semaphore_key.signal() }
        }
        var itemAddStatus: OSStatus?
        let matchingStatus = SecItemCopyMatching(dic as CFDictionary, nil)
        
        if matchingStatus == errSecItemNotFound {
            // 保存
            itemAddStatus = SecItemAdd(dic as CFDictionary, nil)
        } else if matchingStatus == errSecSuccess {
            // 更新
            itemAddStatus = SecItemUpdate(dic as CFDictionary, [kSecValueData as String: _data] as CFDictionary)
        } else {
            print("保存失敗")
        }
        
        if itemAddStatus == errSecSuccess {
            return true
        } else {
            print("保存失敗")
            return false
        }
    }
    
    public func targetIsMovable(srcFileId: String, dstFileId: String) async -> Bool {
        true
    }
}

public actor Semaphore {
    private var value: Int
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var idlist: [UUID] = []
    public enum waitResult {
        case timeout
        case success
    }
    
    public init(value: Int = 0) {
        self.value = value
    }
    
    public func wait() async {
        await wait(id: UUID())
    }
    
    private func wait(id: UUID) async {
        value -= 1
        if value >= 0 { return }
        await withCheckedContinuation {
            idlist.append(id)
            waiters[id] = $0
        }
    }
    
    @discardableResult
    public func wait(timeout: Duration) async -> waitResult {
        let id = UUID()
        return await withTaskGroup(of: waitResult.self) { group in
            group.addTask {
                await self.wait(id: id)
                return .success
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timeout
            }
            let v = await group.next()!
            group.cancelAll()
            if v == .timeout {
                value += 1
                if let i = idlist.firstIndex(of: id) {
                    idlist.remove(at: i)
                }
                waiters[id]?.resume()
                waiters.removeValue(forKey: id)
            }
            return v
        }
    }
    
    public func signal() {
        value += 1
        guard let id = idlist.first else { return }
        idlist.removeFirst()
        waiters[id]?.resume()
        waiters.removeValue(forKey: id)
    }
}

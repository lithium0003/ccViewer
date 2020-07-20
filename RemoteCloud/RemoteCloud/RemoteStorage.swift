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

public enum CloudStorages: CaseIterable {
    case Local
    case Files
    case DropBox
    case GoogleDrive
    case OneDrive
    case pCloud
    case WebDAV
    case CryptCarotDAV
    case CryptRclone
    case Cryptomator
}

public protocol RemoteStorage {
    func auth(onFinish: ((Bool) -> Void)?) -> Void
    func logout()
    
    func list(fileId: String, onFinish: (() -> Void)?)
    func list(path: String, onFinish: (() -> Void)?)
    
    func read(fileId: String, start: Int64?, length: Int64?, onFinish: ((Data?) -> Void)?)
    
    func mkdir(parentId: String, newname: String, onFinish: ((String?)->Void)?)
    func delete(fileId: String, onFinish: ((Bool)->Void)?)
    func rename(fileId: String, newname: String, onFinish: ((String?)->Void)?)
    func chagetime(fileId: String, newdate: Date, onFinish: ((String?)->Void)?)
    func move(fileId: String, fromParent: String, toParent: String, onFinish: ((String?)->Void)?)

    func upload(parentId: String, sessionId: String, uploadname: String, target: URL, onFinish: ((String?)->Void)?)
    
    func get(fileId: String) -> RemoteItem?
    func get(path: String) -> RemoteItem?

    func config() -> String
    func getStorageType() -> CloudStorages
    
    func cancel()
    
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
    public let isFolder: Bool
    public let mDate: Date?
    public let cDate: Date?
    public let substart: Int64
    public let subend: Int64
    public let subid: String?
    let service: RemoteStorage

    init?(storage: String, id: String) {
        self.storage = storage
        self.id = id
        guard let service = CloudFactory.shared[storage] else {
            return nil
        }
        self.service = service
        if id == "" {
            self.name = ""
            self.ext = ""
            self.size = 0
            self.path = "\(storage):/"
            self.parent = ""
            self.isFolder = true
            self.mDate = nil
            self.cDate = nil
            self.substart = -1
            self.subend = -1
            self.subid = nil
        }
        else {
            let item1 = CloudFactory.shared.data.getData(storage: storage, fileId: id)
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
            self.mDate = origin.mdate
            self.cDate = origin.cdate
            self.substart = origin.substart
            self.subend = origin.subend
            self.subid = origin.subid
        }
    }
    
    convenience init?(path: String) {
        guard let origin = CloudFactory.shared.data.getData(path: path) else {
            return nil
        }
        guard let storage = origin.storage else {
            return nil
        }
        guard let id = origin.id else {
            return nil
        }
        self.init(storage: storage, id: id)
    }
    
    public func open() -> RemoteStream {
        return RemoteStream(size: 0)
    }
    
    public func cancel() {
        service.cancel()
    }
    
    public func mkdir(newname: String, onFinish: ((String?)->Void)?){
        if isFolder {
            service.mkdir(parentId: id, newname: newname, onFinish: onFinish)
        }
        else {
            onFinish?(nil)
        }
    }
    
    public func delete(onFinish: ((Bool)->Void)?){
        service.delete(fileId: id, onFinish: onFinish)
    }
    
    public func rename(newname: String, onFinish: ((String?)->Void)?) {
        service.rename(fileId: id, newname: newname, onFinish: onFinish)
    }
    
    public func changetime(newdate: Date, onFinish: ((String?)->Void)?) {
        service.chagetime(fileId: id, newdate: newdate, onFinish: onFinish)
    }
    
    public func move(toParentId: String, onFinish: ((String?)->Void)?) {
        service.move(fileId: id, fromParent: parent, toParent: toParentId, onFinish: onFinish)
    }
    
    public func read(start: Int64? = nil, length: Int64? = nil, onFinish: ((Data?)->Void)?){
        service.read(fileId: id, start: start, length: length, onFinish: onFinish)
    }
}

public class RemoteStream {
    public internal(set) var size:Int64
    public var isLive = true
    private let read_queue = DispatchQueue(label: "read")
    
    init(size: Int64) {
        self.size = size
    }
    
    public func read(position: Int64, length: Int, onProgress: ((Int)->Bool)? = nil) -> Data? {
        return nil
    }
    public func read(position: Int64, length: Int, onProgress: ((Int)->Bool)? = nil, onFinish: @escaping (Data?) -> Void) {
        read_queue.async {
            let fixlen = (Int64(length) + position >= self.size) ? Int(self.size - position) : length
            let data = self.read(position: position, length: fixlen, onProgress: onProgress)
            DispatchQueue.global().async {
                onFinish(data)
            }
        }
    }
    
    public func preload(position: Int64, length: Int) {
        
    }
}

public class CloudFactory {
    private static let _shared = CloudFactory()
    public static var shared: CloudFactory { return _shared }
    let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "application")
    
    public var urlSessionDidFinishCallback: ((URLSession)->Void)?

    private init() {
        storageList = [:]
        initializeDatabase()
    }

    public func initializeDatabase() {
        os_log("%{public}@", log: log, type: .info, "CloudFactory(init)")
        storageList = [:]

        if let sList = getKeyChain(key: "remoteStorageList") {
            let classmap = Dictionary(uniqueKeysWithValues: CloudStorages.allCases.map() { (CloudFactory.getServiceName(service: $0), $0) })
            do {
                if let d = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(sList) as? [String: String] {
                    print(d)
                    let tList = d.map() { key, value -> (String, RemoteStorage?) in
                        guard let jsondata = value.data(using: .utf8) else {
                            return (key, nil)
                        }
                        guard let json = try? JSONSerialization.jsonObject(with: jsondata, options: []) else {
                            return (key, nil)
                        }
                        guard let conf = json as? [String: String?], conf["name"] == key else {
                            return (key, nil)
                        }
                        guard let valueService = conf["service"], let newService = valueService else {
                            return (key, nil)
                        }
                        if let newClass = classmap[newService] {
                            os_log("%{public}@", log: log, type: .info, "Restore \(key) \(newService)")
                            let newItem = newStorage(service: newClass, tagname: key)
                            return (key, newItem)
                        }
                        return (key, nil)
                    }
                    storageList = Dictionary(uniqueKeysWithValues: tList.filter() { $1 != nil }.map() { ($0, $1!)} )
                    saveConfig()
                }
            }
            catch {
                let _ = delKeyChain(key: "remoteStorageList")
            }
        }
        storageList["Local"] = newStorage(service: .Local, tagname: "Local")
    }
    
    public let data = dataItems()
    public let cache = FileCache()
    
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

    var storageList: [String: RemoteStorage]
    
    class func createInstance(service: CloudStorages, tagname: String) -> RemoteStorage {
        switch service {
        case .GoogleDrive:
            return GoogleDriveStorageCustom(name: tagname)
        case .DropBox:
            return DropBoxStorage(name: tagname)
        case .OneDrive:
            return OneDriveStorage(name: tagname)
        case .pCloud:
            return pCloudStorage(name: tagname)
        case .WebDAV:
            return WebDAVStorage(name: tagname)
        case .CryptCarotDAV:
            return CryptCarotDAV(name: tagname)
        case .CryptRclone:
            return CryptRclone(name: tagname)
        case .Cryptomator:
            return Cryptomator(name: tagname)
        case .Local:
            return LocalStorage(name: tagname)
        case .Files:
            return FilesStorage(name: tagname)
        }
    }

    func saveConfig() {
        do {
            let seq = storageList.filter({ $0.key != "Local" }).map(){ key, value in (key, value.config()) }
            let d = Dictionary(uniqueKeysWithValues: seq)
            let rData = try NSKeyedArchiver.archivedData(withRootObject: d, requiringSecureCoding: true)
            let _ = setKeyChain(key: "remoteStorageList", data: rData)
            os_log("%{public}@", log: log, type: .info, "saveConfig success")
        }
        catch {
            let _ = delKeyChain(key: "remoteStorageList")
        }
    }
    
    public func newStorage(service: CloudStorages, tagname: String) -> RemoteStorage {
        if let p = self[tagname] {
            return p
        }
        let newInstance = CloudFactory.createInstance(service: service, tagname: tagname)
        storageList[tagname] = newInstance
        saveConfig()
        return newInstance
    }

    func loadChild(item: RemoteData, onFinish: @escaping ([RemoteData])->Void) {
        self[item.storage ?? ""]?.list(fileId: item.id ?? "") {
            var loadData = [RemoteData]()
            let children = self.data.listData(storage: item.storage ?? "", parentID: item.id ?? "")
            loadData += children.filter({ $0.folder })
            DispatchQueue.global().async {
                onFinish(loadData)
            }
        }
    }
    
    func findChild(storage: String, id: String, onFinish: @escaping ([RemoteData])->Void) {
        let children = self.data.listData(storage: storage, parentID: id)
        DispatchQueue.global().async {
            var loadData = [RemoteData]()
            if children.count > 0 {
                for item in children.filter({ $0.folder }) {
                    let group = DispatchGroup()
                    group.enter()
                    self.findChild(storage: item.storage ?? "", id: item.id ?? "") { newload in
                        loadData += newload
                        group.leave()
                    }
                    group.wait()
                }
                onFinish(loadData)
            }
            else {
                if let item = self.data.getData(storage: storage, fileId: id) {
                    loadData += [item]
                }
                DispatchQueue.global().async {
                    onFinish(loadData)
                }
            }
        }
    }
    
    public func deepLoad(storage: String) {
        DispatchQueue.global().async {
            self.findChild(storage: storage, id: "") { newload in
                let group = DispatchGroup()
                var remain = newload
                while remain.count > 0 {
                    if let target = remain.first {
                        remain = Array(remain.dropFirst())
                        group.enter()
                        self.loadChild(item: target) { addItems in
                            remain += addItems
                            group.leave()
                        }
                        group.wait()
                    }
                    else {
                        break
                    }
                }
            }
        }
    }
    
    public subscript(name: String) -> RemoteStorage? {
        return storageList[name]
    }
    public var storages: [String] {
        return [String](storageList.keys).sorted()
    }
    
    public func delStorage(tagname: String) {
        if let p = self[tagname] {
            p.logout()
            let depended = getKeyChain(cond: "^\(tagname)_depended")
            for (key, dep) in depended {
                if let s = String(data: dep, encoding: .utf8) {
                    delStorage(tagname: s)
                    let _ = delKeyChain(key: key)
                }
            }
            storageList.removeValue(forKey: tagname)
            saveConfig()
        }
    }

    public func delAllStorage() {
        let _ = storageList.map() { delStorage(tagname: $0.key) }
    }
    
    public func removeAllAuth() {
        if delAllKeyChain() {
            storageList = [:]
            storageList["Local"] = CloudFactory.createInstance(service: .Local, tagname: "Local")
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
    static let semaphore_key = DispatchSemaphore(value: 1)
    
    public var rootName: String = ""
    
    public func read(fileId: String, start: Int64?, length: Int64?, onFinish: ((Data?) -> Void)?) {
        readFile(fileId: fileId, start: start, length: length, onFinish: onFinish)
    }
    
    public func upload(parentId: String, sessionId: String, uploadname: String, target: URL, onFinish: ((String?)->Void)?) {
        uploadFile(parentId: parentId, sessionId: sessionId, uploadname: uploadname, target: target, onFinish: onFinish)
    }
    
    public func move(fileId: String, fromParent: String, toParent: String, onFinish: ((String?) -> Void)?) {
        moveItem(fileId: fileId, fromParentId: fromParent, toParentId: toParent, onFinish: onFinish)
    }
    
    public func chagetime(fileId: String, newdate: Date, onFinish: ((String?) -> Void)?) {
        changeTime(fileId: fileId, newdate: newdate, onFinish: onFinish)
    }
    
    public func rename(fileId: String, newname: String, onFinish: ((String?) -> Void)?) {
        renameItem(fileId: fileId, newname: newname, onFinish: onFinish)
    }
    
    public func delete(fileId: String, onFinish: ((Bool) -> Void)?) {
        deleteItem(fileId: fileId, onFinish: onFinish)
    }
    
    func makeFolder(parentId: String, parentPath: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        onFinish?(nil)
    }

    public func get(fileId: String) -> RemoteItem? {
        return fileId.contains("\t") ? getsubitem(fileId: fileId) : getRaw(fileId: fileId)
    }
    
    public func get(path: String) -> RemoteItem? {
        return getRaw(path: path)
    }

    public func getRaw(fileId: String) -> RemoteItem? {
        return RemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public func getRaw(path: String) -> RemoteItem? {
        return RemoteItem(path: path)
    }
    
    public func getStorageType() -> CloudStorages {
        return .GoogleDrive
    }
    
    let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "application")
    var storageName: String?
    var service: String?
    var cancelTime = Date(timeIntervalSince1970: 0)

    public func cancel() {
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
    
    public func auth(onFinish: ((Bool) -> Void)?) -> Void {
        onFinish?(true)
    }
    
    func deleteItems(name: String) {
        CloudFactory.shared.data.persistentContainer.performBackgroundTask { context in
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "storage == %@", name)
            if let result = try? context.fetch(fetchRequest) {
                for object in result {
                    context.delete(object as! NSManagedObject)
                }
            }
            
            try? context.save()
        }
    }
    
    public func logout() {
        if let name = storageName {
            os_log("%{public}@", log: log, type: .info, "logout(\(name))")
            
            deleteItems(name: name)
        }
    }

    func ListChildren(fileId: String = "", path: String = "", onFinish: (() -> Void)?) {
        onFinish?()
    }
 
    func deleteChild(parent: String, context: NSManagedObjectContext) {
        context.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", parent, self.storageName ?? "")
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
    

    public func list(fileId: String, onFinish: (() -> Void)?) {
        if fileId == "" {
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            self.deleteChild(parent: fileId, context: backgroundContext)
            backgroundContext.perform {
                try? backgroundContext.save()
                self.ListChildren(onFinish: onFinish)
            }
        }
        else {
            var path = ""
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            backgroundContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, self.storageName ?? "")
                if let result = try? backgroundContext.fetch(fetchRequest) {
                    if let items = result as? [RemoteData] {
                        path = items.first?.path ?? ""
                    }
                }
                
                if path != "" {
                    self.deleteChild(parent: fileId, context: backgroundContext)
                }
            }
            backgroundContext.perform {
                if path != "" {
                    try? backgroundContext.save()
                    self.ListChildren(fileId: fileId, path: path, onFinish: onFinish)
                }
                else {
                    onFinish?()
                }
            }
        }
    }
    
    public func list(path: String, onFinish: (() -> Void)?) {
        if path == "" || path == "\(storageName ?? ""):/" {
            ListChildren(onFinish: onFinish)
        }
        else {
            var ids: [String] = []
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            backgroundContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "path == %@", path)
                if let result = try? backgroundContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                    ids = items.filter { $0.id != nil }.map { $0.id! }
                }
                
                for id in ids {
                    self.deleteChild(parent: id, context: backgroundContext)
                }
            }
            backgroundContext.perform {
                try? backgroundContext.save()

                if ids.isEmpty {
                    onFinish?()
                    return
                }
                for id in ids {
                    self.ListChildren(fileId: id, path: path, onFinish: onFinish)
                }
            }
        }
    }

    public func mkdir(parentId: String, newname: String, onFinish: ((String?) -> Void)?) {
        if parentId == "" {
            makeFolder(parentId: parentId, parentPath: "", newname: newname, onFinish: onFinish)
        }
        else{
            var path = ""
            if Thread.isMainThread {
                let viewContext = CloudFactory.shared.data.persistentContainer.viewContext
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", parentId, self.storageName ?? "")
                if let result = try? viewContext.fetch(fetchRequest) {
                    if let items = result as? [RemoteData] {
                        path = items.first?.path ?? ""
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
                            path = items.first?.path ?? ""
                        }
                    }
                }
            }
            if path != "" {
                self.makeFolder(parentId: parentId, parentPath: path, newname: newname, onFinish: onFinish)
            }
            else {
                onFinish?(nil)
            }
        }
    }
    
    func deleteItem(fileId: String, callCount: Int = 0, onFinish: ((Bool) -> Void)?) {
        onFinish?(false)
    }
    
    func renameItem(fileId: String, newname: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        onFinish?(nil)
    }
    
    func changeTime(fileId: String, newdate: Date, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        onFinish?(nil)
    }
    
    func moveItem(fileId: String, fromParentId: String, toParentId: String, callCount: Int = 0, onFinish: ((String?) -> Void)?) {
        onFinish?(nil)
    }
    
    func readFile(fileId: String, start: Int64?, length: Int64?, callCount: Int = 0, onFinish: ((Data?) -> Void)?) {
        onFinish?(nil)
    }
    
    func uploadFile(parentId: String, sessionId: String, uploadname: String, target: URL, onFinish: ((String?)->Void)?) {
        onFinish?(nil)
    }
    
    func getKeyChain(key: String) -> String? {
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key,
                                  kSecReturnData as String: kCFBooleanTrue as Any]
        
        RemoteStorageBase.semaphore_key.wait()
        defer {
            RemoteStorageBase.semaphore_key.signal()
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

    func delKeyChain(key: String) -> Bool {
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key]
        
        RemoteStorageBase.semaphore_key.wait()
        defer {
            RemoteStorageBase.semaphore_key.signal()
        }
        if SecItemDelete(dic as CFDictionary) == errSecSuccess {
            return true
        } else {
            return false
        }
    }
    
    func setKeyChain(key: String, value: String) -> Bool{
        let data = value.data(using: .utf8)
        
        guard let _data = data else {
            return false
        }
        
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key,
                                  kSecValueData as String: _data]
        
        RemoteStorageBase.semaphore_key.wait()
        defer {
            RemoteStorageBase.semaphore_key.signal()
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
}

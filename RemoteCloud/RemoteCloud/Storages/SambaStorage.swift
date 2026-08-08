//
//  SambaStorage.swift
//  RemoteCloud
//
//  Created by rei8 on 2019/11/22.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import os.log
import CoreData
import SwiftUI
import AuthenticationServices

import SMBClient

struct SambaLoginView: View {
    let authContinuation: CheckedContinuation<Bool, Never>
    let callback: (String, String, String) async -> Bool
    let onDismiss: () -> Void
    @State var ok = false

    @State var textHost = ""
    @State var textUser = ""
    @State var textPass = ""

    var body: some View {
        ZStack {
            Form {
                Section("Host") {
                    TextField("localhost", text: $textHost)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section("Username") {
                    TextField("(Optional)", text: $textUser)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section("Password") {
                    SecureField("(Optional)", text: $textPass)
                }
                Button("Connect") {
                    if textHost.isEmpty {
                        return
                    }
                    ok = true
                    Task {
                        if await callback(textHost, textUser, textPass) {
                            authContinuation.resume(returning: true)
                        }
                        else {
                            authContinuation.resume(returning: false)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(ok)

            if ok {
                ProgressView()
                    .padding(30)
                    .background {
                        Color(uiColor: .systemBackground)
                            .opacity(0.9)
                    }
                    .scaleEffect(3)
                    .cornerRadius(10)
            }
        }
        .onDisappear {
            if ok { return }
            onDismiss()
        }
    }
}

extension Data {
    init<T>(from value: T) {
        var value = value
        self = Swift.withUnsafeBytes(of: &value) { Data($0) }
    }
    
    func to<T>(type: T.Type) -> T {
        return self.withUnsafeBytes { $0.load(as: T.self) }
    }
}

public class SambaStorage: NetworkStorage {
    let calendar = Calendar(identifier: .gregorian)
    lazy var time1601: Date = {
        var comps = DateComponents()
        comps.year = 1601
        comps.month = 1
        comps.day = 1
        return calendar.date(from: comps)!
    }()

    struct FileObject {
        let fileId: Data
        let size: UInt64
    }

    actor SessionList {
        var sessions: [UUID: Session] = [:]
        var availableIdx: Set<UUID> = []
        var fileSemaphore: [String: Semaphore] = [:]

        var count: Int {
            sessions.count
        }
        
        func addSession(_ session: Session) {
            let id = UUID()
            sessions[id] = session
            availableIdx.insert(id)
        }
        
        func popSession() -> (UUID, Session)? {
            guard let id = availableIdx.popFirst(), let session = sessions[id] else {
                return nil
            }
            return (id, session)
        }
        
        func returnSession(_ id: UUID) {
            availableIdx.insert(id)
        }
        
        func removeSession(_ id: UUID) {
            sessions.removeValue(forKey: id)
        }
        
        func getFileSemaphore(forPath path: String) -> Semaphore {
            if let sema = fileSemaphore[path] {
                return sema
            } else {
                let sema = Semaphore(value: 1)
                fileSemaphore[path] = sema
                return sema
            }
        }
    }
    
    class SessionManager {
        let host: String
        let username: String
        let password: String
        let sessionList = SessionList()
        let calendar = Calendar(identifier: .gregorian)
        lazy var time1601: Date = {
            var comps = DateComponents()
            comps.year = 1601
            comps.month = 1
            comps.day = 1
            return calendar.date(from: comps)!
        }()
        
        init(host: String, username: String, password: String) {
            self.host = host
            self.username = username
            self.password = password
        }
        
        func connect() async throws {
            if await sessionList.count >= 5 {
                return
            }
            while await sessionList.count < 5 {
                let session = Session(host: host)
                try await session.connect()
                try await session.negotiate()
                
                try await session.sessionSetup(username: username, password: password)
                await sessionList.addSession(session)
            }
        }
        
        func disconnect() async {
            while let (idx, session) = await sessionList.popSession() {
                session.disconnect()
                await sessionList.removeSession(idx)
            }
        }

        func runSession<T>(_ callback: (Session) async throws -> T) async throws -> T {
            for _ in 0..<5 {
                try await connect()
                if let (idx, session) = await sessionList.popSession() {
                    do {
                        try await session.echo()
                    }
                    catch {
                        print(error)
                        session.disconnect()
                        await sessionList.removeSession(idx)
                        continue
                    }
                    defer {
                        Task {
                            await sessionList.returnSession(idx)
                        }
                    }
                    return try await callback(session)
                }
            }
            throw NSError(domain: "SambaStorage", code: -1, userInfo: nil)
        }

        func enumShareAll() async throws -> [Share] {
            try await runSession { session in
                try await session.enumShareAll()
            }
        }
        
        func queryDirectory(share: String, path: String) async throws -> [FileDirectoryInformation] {
            try await runSession { session in
                if let prevTree = session.connectedTree, prevTree != share {
                    try await session.treeDisconnect()
                    try await session.treeConnect(path: share)
                }
                else if session.connectedTree == nil {
                    try await session.treeConnect(path: share)
                }
                return try await session.queryDirectory(path: path, pattern: "*")
            }
        }

        func read(share: String, path: String, start: Int64? = nil, length: Int64? = nil) async throws -> Data? {
            return try await runSession { session in
                let sem = await sessionList.getFileSemaphore(forPath: "\(share)/\(path)")
                await sem.wait()
                defer {
                    Task {
                        await sem.signal()
                    }
                }
                if let prevTree = session.connectedTree, prevTree != share {
                    try await session.treeDisconnect()
                    try await session.treeConnect(path: share)
                }
                else if session.connectedTree == nil {
                    try await session.treeConnect(path: share)
                }

                let response = try await session.create(
                    desiredAccess: [.genericRead],
                    fileAttributes: [],
                    shareAccess: [],
                    createDisposition: .open,
                    createOptions: [],
                    name: path
                )
                let obj = FileObject(fileId: response.fileId, size: response.endOfFile)
                defer {
                    Task {
                        try await session.close(fileId: obj.fileId)
                    }
                }
                
                let s = UInt64(start ?? 0)
                let len = UInt64(length ?? Int64(obj.size - s))
                var offset = s
                var buffer = Data()
                
                var response2: Read.Response
                repeat {
                    response2 = try await session.read(
                        fileId: obj.fileId,
                        offset: offset,
                        length: UInt32(len & 0xffffffff),
                    )
                    
                    buffer.append(response2.buffer)
                    offset = s + UInt64(buffer.count)
                } while NTStatus(response2.header.status) != .endOfFile && buffer.count < len
                return buffer[0..<len]
            }
        }

        func createDirectory(share: String, path: String, newname: String) async throws -> String? {
            try await runSession { session in
                if let prevTree = session.connectedTree, prevTree != share {
                    try await session.treeDisconnect()
                    try await session.treeConnect(path: share)
                }
                else if session.connectedTree == nil {
                    try await session.treeConnect(path: share)
                }
                try await session.createDirectory(path: "\(path)/\(newname)")
                return "\(share)/\(path)/\(newname)"
            }
        }

        func delete(share: String, path: String, directory: Bool = false) async throws -> Bool {
            try await runSession { session in
                if let prevTree = session.connectedTree, prevTree != share {
                    try await session.treeDisconnect()
                    try await session.treeConnect(path: share)
                }
                else if session.connectedTree == nil {
                    try await session.treeConnect(path: share)
                }
                if directory {
                    try await session.deleteDirectory(path: "\(path)")
                }
                else {
                    try await session.deleteFile(path: "\(path)")
                }
                return true
            }
        }
        
        func move(share: String, fromPath: String, toPath: String) async throws -> String {
            try await runSession { session in
                if let prevTree = session.connectedTree, prevTree != share {
                    try await session.treeDisconnect()
                    try await session.treeConnect(path: share)
                }
                else if session.connectedTree == nil {
                    try await session.treeConnect(path: share)
                }
                try await session.move(from: fromPath, to: toPath)
                return "\(share)/\(toPath)"
            }
        }

        func changetime(share: String, path: String, time: Date) async throws -> String? {
            try await runSession { session in
                if let prevTree = session.connectedTree, prevTree != share {
                    try await session.treeDisconnect()
                    try await session.treeConnect(path: share)
                }
                else if session.connectedTree == nil {
                    try await session.treeConnect(path: share)
                }
                let res = try await session.queryInfo(path: path, fileInfoClass: .fileBasicInformation)
                let info = FileBasicInformation(data: res.buffer)
                var data = Data()
                data += Data(from: info.creationTime)
                data += Data(from: info.lastAccessTime)
                data += Data(from: info.lastWriteTime)
                data += Data(from: UInt64(time.timeIntervalSince(time1601) * 10000000))
                data += Data(from: info.fileAttributes.rawValue)
                data += Data(from: info.reserved)
                let newInfo = FileBasicInformation(data: data)
                try await session.setInfo(path: path, newInfo)
                return "\(share)/\(path)"
            }
        }

        func write(share: String, path: String, url: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> Bool {
            try await runSession { session in
                if let prevTree = session.connectedTree, prevTree != share {
                    try await session.treeDisconnect()
                    try await session.treeConnect(path: share)
                }
                else if session.connectedTree == nil {
                    try await session.treeConnect(path: share)
                }

                let response = try await session.create(
                    desiredAccess: [
                      .readData,
                      .writeData,
                      .appendData,
                      .readAttributes,
                      .readControl,
                      .writeDac
                    ],
                    fileAttributes: [.archive, .normal],
                    shareAccess: [.read, .write, .delete],
                    createDisposition: .create,
                    createOptions: [],
                    name: path
                )
                let obj = FileObject(fileId: response.fileId, size: response.endOfFile)

                let handle = try FileHandle(forReadingFrom: url)
                defer {
                    try? handle.close()
                }
                
                let attr = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attr[.size] as! UInt64
                try await progress?(0, Int64(fileSize))

                var offset: UInt64 = 0
                while offset < fileSize {
                    guard let srcData = try handle.read(upToCount: Int(session.maxWriteSize)) else {
                        return false
                    }
                    
                    _ = try await session.write(
                        data: srcData,
                        fileId: obj.fileId,
                        offset: offset
                    )
                    
                    offset += UInt64(srcData.count)
                    try await progress?(Int64(offset), Int64(fileSize))
                }

                try await session.close(fileId: obj.fileId)
                return true
            }
        }
    }
    var sessionManager: SessionManager!
        
    let uploadSemaphore = Semaphore(value: 5)

    public override func getStorageType() -> CloudStorages {
        return .Samba
    }

    var cache_accessUsername = ""
    func accessUsername() async -> String {
        if !cache_accessUsername.isEmpty {
            return cache_accessUsername
        }
        if let name = storageName {
            if let user = await getKeyChain(key: "\(name)_accessUsername") {
                cache_accessUsername = user
            }
            return cache_accessUsername
        }
        else {
            return ""
        }
    }

    var cache_accessPassword = ""
    func accessPassword() async -> String {
        if !cache_accessPassword.isEmpty {
            return cache_accessPassword
        }
        if let name = storageName {
            if let pass = await getKeyChain(key: "\(name)_accessPassword") {
                cache_accessPassword = pass
            }
            return cache_accessPassword
        }
        else {
            return ""
        }
    }

    var cache_aaccessHost = ""
    func accessHost() async -> String {
        if !cache_aaccessHost.isEmpty {
            return cache_aaccessHost
        }
        if let name = storageName {
            if let host = await getKeyChain(key: "\(name)_accessHost") {
                cache_aaccessHost = host
            }
            return cache_aaccessHost
        }
        else {
            return ""
        }
    }

    public convenience init(name: String) {
        self.init()
        service = CloudFactory.getServiceName(service: .Samba)
        storageName = name
    }

    public override func auth(callback: @escaping (any View, CheckedContinuation<Bool, Never>) -> Void,  webAuthenticationSession: WebAuthenticationSession, selectItem: @escaping () async -> (String, String)?) async -> Bool {
        let authRet = await withCheckedContinuation { authContinuation in
            Task {
                let presentRet = await withCheckedContinuation { continuation in
                    callback(SambaLoginView(authContinuation: authContinuation) { (host, user, pass) in
                        let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_accessHost", value: host)
                        let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_accessUsername", value: user)
                        let _ = await self.setKeyChain(key: "\(self.storageName ?? "")_accessPassword", value: pass)
                            return true
                    } onDismiss: {
                        authContinuation.resume(returning: false)
                    }, continuation)
                }
                guard presentRet else {
                    authContinuation.resume(returning: false)
                    return
                }
            }
        }
        return authRet
    }
    
    public override func logout() async {
        Task {
            await disconnect()
        }
        if let name = storageName {
            let _ = await delKeyChain(key: "\(name)_accessHost")
            let _ = await delKeyChain(key: "\(name)_accessUsername")
            let _ = await delKeyChain(key: "\(name)_accessPassword")
        }
        await super.logout()
    }

    override func checkToken() async -> Bool {
        if sessionManager == nil {
            sessionManager = await SessionManager(host: accessHost(), username: accessUsername(), password: accessPassword())
        }
        return true
    }
    
    func connect() async throws {
        sessionManager = await SessionManager(host: accessHost(), username: accessUsername(), password: accessPassword())
        try await sessionManager.connect()
    }
    
    func disconnect() async {
        await sessionManager?.disconnect()
    }
        
    override func listChildren(fileId: String, path: String) async {
        do {
            return try await callWithRetry(action: { [self] in
                let viewContext = CloudFactory.shared.data.backgroundContext
                let storage = self.storageName ?? ""
                let t1601 = self.time1601
                
                if fileId == "" {
                    do {
                        let shares = try await sessionManager.enumShareAll()
                        let shareNames = shares.filter({ $0.name != "IPC$" }).map({ $0.name })
                        
                        await viewContext.perform {
                            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", "", storage)
                            let existingItems = (try? viewContext.fetch(fetchRequest)) ?? []
                            
                            var existingDict = [String: RemoteData]()
                            for item in existingItems {
                                if let id = item.id { existingDict[id] = item }
                            }
                            
                            for id in shareNames {
                                let existing = existingDict.removeValue(forKey: id)
                                let targetItem = existing ?? RemoteData(context: viewContext)
                                
                                targetItem.storage = storage
                                targetItem.id = id
                                targetItem.name = id
                                targetItem.ext = ""
                                targetItem.cdate = nil
                                targetItem.mdate = nil
                                targetItem.folder = true
                                targetItem.size = 0
                                targetItem.hashstr = nil
                                targetItem.parent = ""
                                targetItem.path = "\(storage):/\(id)"
                            }
                            
                            for (_, orphan) in existingDict {
                                SambaStorage.cascadeDelete(item: orphan, in: viewContext)
                            }
                            try? viewContext.save()
                        }
                    }
                    catch {
                        print(error)
                        throw RetryError.Retry
                    }
                }
                else if let share = fileId.components(separatedBy: "/").first {
                    let dirPath = fileId.components(separatedBy: "/").dropFirst().joined(separator: "/")
                    do {
                        let files = try await sessionManager.queryDirectory(share: share, path: dirPath)
                        
                        let validFiles = files
                            .filter { $0.fileName != "." && $0.fileName != ".." && !$0.fileName.hasPrefix("._") }
                            .map { (
                                name: $0.fileName,
                                ctime: Double($0.creationTime),
                                mtime: Double($0.changeTime),
                                isFolder: $0.fileAttributes.contains(.directory),
                                size: Int64($0.endOfFile)
                            )}
                        
                        await viewContext.perform {
                            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", fileId, storage)
                            let existingItems = (try? viewContext.fetch(fetchRequest)) ?? []
                            
                            var existingDict = [String: RemoteData]()
                            for item in existingItems {
                                if let id = item.id { existingDict[id] = item }
                            }
                            
                            for item in validFiles {
                                let id = "\(fileId)/\(item.name)"
                                let existing = existingDict.removeValue(forKey: id)
                                let targetItem = existing ?? RemoteData(context: viewContext)
                                
                                targetItem.hashstr = nil
                                targetItem.subinfo = nil
                                targetItem.subid = nil
                                targetItem.substart = 0
                                targetItem.subend = 0
                                targetItem.baseId = nil
                                targetItem.baseStorage = nil
                                
                                targetItem.storage = storage
                                targetItem.id = id
                                targetItem.name = item.name
                                
                                let comp = item.name.components(separatedBy: ".")
                                targetItem.ext = comp.count > 1 ? comp.last!.lowercased() : ""
                                
                                targetItem.cdate = Date(timeInterval: item.ctime / 10000000, since: t1601)
                                targetItem.mdate = Date(timeInterval: item.mtime / 10000000, since: t1601)
                                targetItem.folder = item.isFolder
                                targetItem.size = item.size
                                targetItem.parent = fileId
                                targetItem.path = "\(storage):/\(id)"
                            }
                            
                            for (_, orphan) in existingDict {
                                SambaStorage.cascadeDelete(item: orphan, in: viewContext)
                            }
                            try? viewContext.save()
                        }
                    }
                    catch {
                        print(error)
                        throw RetryError.Retry
                    }
                }
            })
        }
        catch {
            print(error)
            await disconnect()
        }
    }
    
    override func readFile(fileId: String, start: Int64? = nil, length: Int64? = nil) async throws -> Data? {
        if let cache = await CloudFactory.shared.cache.getCache(storage: storageName!, id: fileId, offset: start ?? 0, size: length ?? -1) {
            if let data = try? Data(contentsOf: cache) {
                os_log("%{public}@", log: log, type: .debug, "hit cache(Samba:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")
                return data
            }
        }
        do {
            return try await callWithRetry(action: { [self] in
                if let share = fileId.components(separatedBy: "/").first {
                    let path = fileId.components(separatedBy: "/").dropFirst().joined(separator: "/")
                    os_log("%{public}@", log: log, type: .debug, "readFile(Samba:\(storageName ?? "") \(fileId) \(start ?? -1) \(length ?? -1) \((start ?? 0) + (length ?? 0))")

                    do {
                        guard let data = try await sessionManager.read(share: share, path: path, start: start, length: length) else {
                            return nil
                        }
                        await CloudFactory.shared.cache.saveCache(storage: self.storageName!, id: fileId, offset: start ?? 0, data: data)
                        return data
                    }
                    catch {
                        print(error)
                        throw RetryError.Retry
                    }
                }
                return nil
            })
        }
        catch {
            print(error)
            await disconnect()
            return nil
        }
    }

    public override func getRaw(fileId: String) async -> RemoteItem? {
        return await NetworkRemoteItem(storage: storageName ?? "", id: fileId)
    }
    
    public override func getRaw(path: String) async -> RemoteItem? {
        return await NetworkRemoteItem(path: path)
    }

    public override func makeFolder(parentId: String, parentPath: String, newname: String) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "makeFolder(Samba:\(storageName ?? "") \(parentId) \(newname)")
                if let share = parentId.components(separatedBy: "/").first {
                    let path = parentId.components(separatedBy: "/").dropFirst().joined(separator: "/")
                    do {
                        if let newid = try await sessionManager.createDirectory(share: share, path: path, newname: newname) {
                            let viewContext = CloudFactory.shared.data.backgroundContext
                            let storage = storageName ?? ""
                            
                            await viewContext.perform {
                                let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                                fetchRequest.fetchLimit = 1
                                let existing = (try? viewContext.fetch(fetchRequest))?.first
                                
                                let targetItem = existing ?? RemoteData(context: viewContext)
                                targetItem.storage = storage
                                targetItem.id = newid
                                targetItem.name = newname
                                targetItem.ext = ""
                                targetItem.cdate = Date()
                                targetItem.mdate = Date()
                                targetItem.folder = true
                                targetItem.size = 0
                                targetItem.hashstr = nil
                                targetItem.parent = parentId
                                targetItem.path = "\(storage):/\(newid)"
                                
                                try? viewContext.save()
                            }
                            return newid
                        }
                    }
                    catch {
                        print(error)
                        throw RetryError.Retry
                    }
                }
                return nil
            })
        }
        catch {
            print(error)
            await disconnect()
            return nil
        }
    }
    
    override func deleteItem(fileId: String) async -> Bool {
        var isFolder = false
        var targetObjectID: NSManagedObjectID? = nil
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            if let item = (try? viewContext.fetch(fetchRequest))?.first {
                isFolder = item.folder
                targetObjectID = item.objectID
            }
        }
        
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "deleteItem(Samba:\(storageName ?? "") \(fileId)")
                if let share = fileId.components(separatedBy: "/").first {
                    let path = fileId.components(separatedBy: "/").dropFirst().joined(separator: "/")
                    do {
                        let ret = try await sessionManager.delete(share: share, path: path, directory: isFolder)
                        if ret {
                            await viewContext.perform {
                                if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                                    SambaStorage.cascadeDelete(item: existing, in: viewContext)
                                }
                                try? viewContext.save()
                            }
                        }
                        return ret
                    }
                    catch {
                        print(error)
                        throw RetryError.Retry
                    }
                }
                return false
            })
        }
        catch {
            print(error)
            await disconnect()
            return false
        }
    }
    
    override func renameItem(fileId: String, newname: String) async -> String? {
        var targetObjectID: NSManagedObjectID? = nil
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            targetObjectID = (try? viewContext.fetch(fetchRequest))?.first?.objectID
        }
        
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "renameItem(Samba:\(storageName ?? "") \(fileId) \(newname)")
                
                if let share = fileId.components(separatedBy: "/").first {
                    var pathComponents = fileId.components(separatedBy: "/")
                    let path = pathComponents.dropFirst().joined(separator: "/")
                    pathComponents.removeLast()
                    pathComponents.append(newname)
                    let newPath = pathComponents.dropFirst().joined(separator: "/")
                    do {
                        let newid = try await sessionManager.move(share: share, fromPath: path, toPath: newPath)
                        
                        await viewContext.perform {
                            if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                                SambaStorage.cascadeDelete(item: existing, in: viewContext)
                            }
                            try? viewContext.save()
                        }
                        return newid
                    }
                    catch {
                        print(error)
                        throw RetryError.Retry
                    }
                }
                return nil
            })
        }
        catch {
            print(error)
            await disconnect()
            return nil
        }
    }
    
    override func moveItem(fileId: String, fromParentId: String, toParentId: String) async -> String? {
        guard let share = fileId.components(separatedBy: "/").first, let share2 = fromParentId.components(separatedBy: "/").first, let share3 = toParentId.components(separatedBy: "/").first, share == share2, share == share3 else {
            return nil
        }
        
        var targetObjectID: NSManagedObjectID? = nil
        let viewContext = CloudFactory.shared.data.backgroundContext
        let storage = storageName ?? ""
        
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", fileId, storage)
            fetchRequest.fetchLimit = 1
            targetObjectID = (try? viewContext.fetch(fetchRequest))?.first?.objectID
        }
        
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "moveItem(Samba:\(storageName ?? "") \(fileId) \(fromParentId)->\(toParentId)")
                
                if let name = fileId.components(separatedBy: "/").dropFirst().last {
                    do {
                        let fromPath = fileId.components(separatedBy: "/").dropFirst().joined(separator: "/")
                        let toPath = toParentId.components(separatedBy: "/").dropFirst().joined(separator: "/") + "/\(name)"
                        let newid = try await sessionManager.move(share: share, fromPath: fromPath, toPath: toPath)
                        
                        await viewContext.perform {
                            if let objID = targetObjectID, let existing = try? viewContext.existingObject(with: objID) as? RemoteData {
                                SambaStorage.cascadeDelete(item: existing, in: viewContext)
                            }
                            try? viewContext.save()
                        }
                        return newid
                    }
                    catch {
                        print(error)
                        throw RetryError.Retry
                    }
                }
                return nil
            })
        }
        catch {
            print(error)
            await disconnect()
            return nil
        }
    }
    
    override func changeTime(fileId: String, newdate: Date) async -> String? {
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: self.log, type: .debug, "changeTime(Samba:\(storageName ?? "") \(fileId) \(newdate)")
                if let share = fileId.components(separatedBy: "/").first {
                    let path = fileId.components(separatedBy: "/").dropFirst().joined(separator: "/")
                    do {
                        return try await sessionManager.changetime(share: share, path: path, time: newdate)
                    }
                    catch {
                        print(error)
                        throw RetryError.Retry
                    }
                }
                return nil
            })
        }
        catch {
            print(error)
            await disconnect()
            return nil
        }
    }
    
    override func uploadFile(parentId: String, uploadname: String, target: URL, progress: ((Int64, Int64) async throws -> Void)? = nil) async throws -> String? {
        defer {
            try? FileManager.default.removeItem(at: target)
        }
        
        do {
            return try await callWithRetry(action: { [self] in
                os_log("%{public}@", log: log, type: .debug, "uploadFile(Samba:\(storageName ?? "") \(uploadname)->\(parentId) \(target)")
                
                if let share = parentId.components(separatedBy: "/").first {
                    let path = parentId.components(separatedBy: "/").dropFirst().joined(separator: "/")
                    do {
                        if try await sessionManager.write(share: share, path: "\(path)/\(uploadname)", url: target, progress: progress) {
                            let newid = "\(parentId)/\(uploadname)"
                            
                            let viewContext = CloudFactory.shared.data.backgroundContext
                            let storage = storageName ?? ""
                            let attr = try? FileManager.default.attributesOfItem(atPath: target.path)
                            let fileSize = attr?[.size] as? Int64 ?? 0
                            
                            await viewContext.perform {
                                let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                                fetchRequest.predicate = NSPredicate(format: "id == %@ && storage == %@", newid, storage)
                                fetchRequest.fetchLimit = 1
                                let existing = (try? viewContext.fetch(fetchRequest))?.first
                                
                                let targetItem = existing ?? RemoteData(context: viewContext)
                                targetItem.storage = storage
                                targetItem.id = newid
                                targetItem.name = uploadname
                                
                                let comp = uploadname.components(separatedBy: ".")
                                if comp.count > 1 {
                                    targetItem.ext = comp.last!.lowercased()
                                } else {
                                    targetItem.ext = ""
                                }
                                
                                targetItem.cdate = Date()
                                targetItem.mdate = Date()
                                targetItem.folder = false
                                targetItem.size = fileSize
                                targetItem.hashstr = nil
                                targetItem.parent = parentId
                                targetItem.path = "\(storage):/\(newid)"
                                
                                try? viewContext.save()
                            }
                            return newid
                        }
                    }
                    catch {
                        print(error)
                        throw RetryError.Retry
                    }
                }
                return nil
            }, semaphore: uploadSemaphore, maxCall: 3)
        }
        catch {
            print(error)
            await disconnect()
            return nil
        }
    }
    
    public override func targetIsMovable(srcFileId: String, dstFileId: String) async -> Bool {
        if let sshare = srcFileId.components(separatedBy: "/").first, let dshare = dstFileId.components(separatedBy: "/").first {
            return sshare == dshare
        }
        return false
    }
}

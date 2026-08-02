//
//  ISOItem.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/04/09.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreData

struct ISOFile {
    let path: String
    let offset: Int64
    let length: Int
}

public class ISORemoteItem: RemoteSubItem {
    let baseItem: RemoteItem
    var baseStream: RemoteStream!
    let filepath: String
    
    override init?(storage: String, id: String) async {
        let section = id.components(separatedBy: "\t")
        guard section.count > 1, let path = section.last else {
            return nil
        }
        filepath = path
        guard let item = await CloudFactory.shared.data.getData(storage: storage, fileId: section.dropLast().joined(separator: "\t"))?.getItem() else {
            return nil
        }
        baseItem = item
        await super.init(storage: storage, id: id)
        baseStream = await self.baseItem.open()
    }
    
    class func Create(from item: RemoteItem) async -> RemoteItem? {
        let itemid = item.id
        let storage = item.storage
        let viewContext = CloudFactory.shared.data.viewContext
        guard await CloudFactory.shared.data.listData(storage: storage, parentID: itemid).isEmpty else {
            return item
        }

        let stream = await item.open()
        guard let PVD = try? await stream.read(position: 0x8000, length: 2048),
              PVD.count == 2048 else {
            return nil
        }
        
        guard PVD[0] == 0x01 else {
            print("Error: Not a Primary Volume Descriptor")
            return nil
        }
        
        let signatureData = PVD[1...5]
        guard let signature = String(data: signatureData, encoding: .ascii),
              signature == "CD001" else {
            print("Error: Invalid ISO 9660 signature")
            return nil
        }
        
        let rootLBN = PVD[158..<162].withUnsafeBytes { $0.load(as: UInt32.self) }
        let rootSize = PVD[166..<170].withUnsafeBytes { $0.load(as: UInt32.self) }
        
        let allFiles = await walkDirectory(stream: stream, lbn: rootLBN, size: rootSize, currentPath: "/")
        
        // 結果の確認
        for file in allFiles {
            print("Path: \(file.path)")
            print("  -> Offset: \(file.offset), Length: \(file.length) bytes\n")
            let path = file.path.dropFirst() + (file.offset < 0 ? "/" : "")
            let id = "\(item.id)\t\(path)"
            let comp = path.components(separatedBy: "/").filter({ !$0.isEmpty })
            let name = comp.last ?? ""
            let parent: String
            if comp.count > 1 {
                parent = "\(item.id)\t\(comp.dropLast().joined(separator: "/"))/"
            }
            else {
                parent = item.id
            }

            let newitem = RemoteData(context: viewContext)
            newitem.storage = storage
            newitem.id = id
            newitem.name = name
            newitem.ext = name.components(separatedBy: ".").last ?? ""
            newitem.cdate = item.cDate
            newitem.mdate = item.mDate
            newitem.folder = file.offset < 0
            newitem.size = Int64(file.length)
            newitem.hashstr = ""
            newitem.parent = parent
            newitem.parentDate = item.mDate
            newitem.path = item.path + "/\(path)"
            newitem.subid = "ISO"+item.id
            newitem.substart = file.offset
        }
        await viewContext.perform {
            try? viewContext.save()
        }

        return item
    }

    private class func walkDirectory(stream: RemoteStream, lbn: UInt32, size: UInt32, currentPath: String) async -> [ISOFile] {
        var foundFiles: [ISOFile] = []
        
        guard let dirData = try? await stream.read(position: Int64(lbn) * 2048, length: Int(size)) else {
            return foundFiles
        }
        
        var cursor = 0
        
        while cursor < dirData.count {
            let recordLength = Int(dirData[cursor])
            
            if recordLength == 0 {
                let nextSector = ((cursor / 2048) + 1) * 2048
                cursor = nextSector
                continue
            }
            
            guard cursor + recordLength <= dirData.count else { break }
            
            let fileLBN = dirData[(cursor + 2)..<(cursor + 6)].withUnsafeBytes { $0.load(as: UInt32.self) }
            let fileSize = dirData[(cursor + 10)..<(cursor + 14)].withUnsafeBytes { $0.load(as: UInt32.self) }
            
            let flags = dirData[cursor + 25]
            let isDirectory = (flags & 0x02) != 0
            
            let nameLength = Int(dirData[cursor + 32])
            let nameData = dirData[(cursor + 33)..<(cursor + 33 + nameLength)]
            var fileName = ""
            
            if nameLength == 1 && nameData.first == 0x00 {
                fileName = "."
            } else if nameLength == 1 && nameData.first == 0x01 {
                fileName = ".."
            } else {
                fileName = String(data: nameData, encoding: .ascii) ?? "Unknown"
                if let cleanName = fileName.split(separator: ";").first {
                    fileName = String(cleanName)
                }
            }
            
            if fileName != "." && fileName != ".." {
                let fullPath = currentPath + fileName
                
                if isDirectory {
                    let newDir = ISOFile(path: fullPath, offset: -1, length: 0)
                    foundFiles.append(newDir)
                    let subFiles = await walkDirectory(stream: stream, lbn: fileLBN, size: fileSize, currentPath: fullPath + "/")
                    foundFiles.append(contentsOf: subFiles)
                } else {
                    let fileOffset = Int64(fileLBN) * 2048
                    let newFile = ISOFile(path: fullPath, offset: fileOffset, length: Int(fileSize))
                    foundFiles.append(newFile)
                }
            }
            
            cursor += recordLength
        }
        
        return foundFiles
    }

    public override func open() async -> RemoteStream {
        return await ISOItemStream(remote: self)
    }
    
    override public func mkdir(newname: String) async -> String? {
        return nil
    }
    
    override public func delete() async -> Bool{
        return false
    }
    
    override public func rename(newname: String) async -> String? {
        return nil
    }
    
    override public func changetime(newdate: Date) async -> String?{
        return nil
    }
    
    override public func move(toParentId: String) async -> String? {
        return nil
    }
    
    override public func read(start: Int64?, length: Int64?) async throws -> Data? {
        if substart < 0 {
            return nil
        }
        return try await baseStream.read(position: (start ?? 0) + substart, length: Int(length ?? size))
    }
}

public class ISOItemStream: SlotStream {
    let remote: ISORemoteItem
    
    init(remote: ISORemoteItem) async {
        self.remote = remote
        await super.init(size: remote.size)
    }

    override func setLive(_ live: Bool) {
        if !live {
            let sem = DispatchSemaphore(value: 0)
            Task {
                defer {
                    sem.signal()
                }
                await remote.cancel()
            }
            sem.wait()
        }
    }

    override func setError(_ isError: Bool) {
        if isError {
            isLive = false
        }
    }

    override func subFillBuffer(pos: ClosedRange<Int64>) async {
        guard await initialized.wait(timeout: .seconds(10)) == .success else {
            error = true
            return
        }
        if await !buffer.dataAvailable(pos: pos), isLive {
            let len = min(size-1, pos.upperBound) - pos.lowerBound + 1
            if let data = try? await remote.read(start: pos.lowerBound, length: len) {
                await buffer.store(pos: pos.lowerBound, data: data)
            }
            else {
                print("error on readFile")
                error = true
            }
        }
    }
}

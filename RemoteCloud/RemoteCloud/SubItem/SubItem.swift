//
//  SubItem.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/04/09.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreData
internal import UniformTypeIdentifiers

public protocol RemoteSubItem {
    func removeSubitem(fileId: String) async
    func listSubitem(fileId: String) async
    func getSubitem(fileId: String) async -> RemoteItem?
}

extension RemoteItem {
    public var hasSubitems: Bool {
        if let uti = UTType(filenameExtension: ext), uti.conforms(to: .archive) {
            return true
        }
        if ext.lowercased() == "cue" {
            return true
        }
        return false
    }
}

extension RemoteData {
    public var hasSubitems: Bool {
        if let ext {
            if let uti = UTType(filenameExtension: ext), uti.conforms(to: .archive) {
                return true
            }
            if ext.lowercased() == "cue" {
                return true
            }
        }
        return false
    }
}

extension RemoteStorageBase: RemoteSubItem {
    public func removeSubitem(fileId: String) async {
        guard let item = await getRaw(fileId: fileId) else {
            return
        }
        let itemid = item.id
        let storage = storageName ?? ""
        let viewContext = CloudFactory.shared.data.viewContext
        await viewContext.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
            fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", itemid, storage)
            if let result = try? viewContext.fetch(fetchRequest) {
                for object in result {
                    viewContext.delete(object as! NSManagedObject)
                }
            }
            fetchRequest.predicate = NSPredicate(format: "subid == %@ && storage == %@", itemid, storage)
            if let result = try? viewContext.fetch(fetchRequest) {
                for object in result {
                    viewContext.delete(object as! NSManagedObject)
                }
            }
        }
        await viewContext.perform {
            try? viewContext.save()
        }
    }
    
    public func listSubitem(fileId: String) async {
        guard let item = await getRaw(fileId: fileId) else {
            return
        }
        if let uti = UTType(filenameExtension: item.ext), uti.conforms(to: .archive) {
            let itemid = item.id
            let mDate = item.mDate
            let storage = storageName ?? ""
            let viewContext = CloudFactory.shared.data.viewContext
            var pass = false
            await viewContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", itemid, storage)
                if let result = try? viewContext.fetch(fetchRequest), let items = result as? [RemoteData] {
                    for subItem in items {
                        pass = mDate == subItem.parentDate
                    }
                }
            }
            if pass { return }
            await viewContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", itemid, storage)
                if let result = try? viewContext.fetch(fetchRequest) {
                    for object in result {
                        viewContext.delete(object as! NSManagedObject)
                    }
                }
            }
            let content = await processArchive(item: item)
            for (subItem, subInfo) in content {
                let id = "\(item.id)\t\(subItem)"
                let comp = subItem.components(separatedBy: "/").filter({ !$0.isEmpty })
                let name = comp.last ?? ""
                let parent: String
                if comp.count > 1 {
                    parent = "\(item.id)\t\(comp.dropLast().joined(separator: "/"))/"
                }
                else {
                    parent = item.id
                }
                
                let newitem = RemoteData(context: viewContext)
                newitem.storage = self.storageName
                newitem.id = id
                newitem.name = name
                newitem.ext = name.components(separatedBy: ".").last ?? ""
                newitem.cdate = subInfo.cdata
                newitem.mdate = subInfo.mdate
                newitem.folder = subItem.hasSuffix("/")
                newitem.size = subInfo.size
                newitem.hashstr = ""
                newitem.parent = parent
                newitem.parentDate = item.mDate
                newitem.path = item.path + "/\(subItem)"
                newitem.subid = item.id
            }
            await viewContext.perform {
                try? viewContext.save()
            }
        }
        else if item.ext.lowercased() == "cue" {
            let viewContext = CloudFactory.shared.data.viewContext
            let itemid = item.id
            let storage = storageName ?? ""
            await viewContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", itemid, storage)
                if let result = try? viewContext.fetch(fetchRequest) {
                    for object in result {
                        viewContext.delete(object as! NSManagedObject)
                    }
                }
            }
            let stream = await item.open()
            guard let data = try? await stream.read() else {
                return
            }
            guard let cue = CueSheet(data: data) else {
                return
            }
            guard let wavname = cue.targetWave else {
                return
            }
            let itemparent = item.parent
            let wavId = await viewContext.perform { () -> String? in
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@ && name == %@", itemparent, storage, wavname)
                
                guard let result = try? viewContext.fetch(fetchRequest) as? [RemoteData], let wavdata = result.first else {
                    return nil
                }
                return wavdata.id
            }
            guard let wavitem = await get(fileId: wavId ?? "") else {
                return
            }
            let wavstream = await wavitem.open()
            guard let wavFile = await RemoteWaveFile(stream: wavstream, size: wavitem.size) else {
                wavstream.isLive = false
                await wavitem.cancel()
                return
            }
            wavstream.isLive = false
            let bytesPerSec = wavFile.wavFormat.BitsPerSample/8 * wavFile.wavFormat.SampleRate * wavFile.wavFormat.NumChannels
            let bytesPerFrame = bytesPerSec / 75
            let endTime = wavFile.wavSize / bytesPerFrame
            
            var diskTitle: String?
            var diskPerformer: String?
            for (index, track) in cue.tracks.enumerated() {
                if index == 0 {
                    diskTitle = track["title"] as? String
                    diskPerformer = track["performer"] as? String
                    continue
                }
                
                let id = "\(item.id)\t\(index)"
                guard let title = track["title"] as? String ?? diskTitle else {
                    continue
                }
                guard let performer = track["performer"] as? String ?? diskPerformer else {
                    continue
                }
                let name = String(format: "%02d : %@ - %@", index, performer, title)
                guard let start = track["start"] as? Int64 else {
                    continue
                }
                let end = track["end"] as? Int64 ?? Int64(endTime)
                let size = 44 + (end - start) * Int64(bytesPerFrame)
                let timelen = Double(end - start) / 75.0
                var sec = Int(timelen)
                let msec = Int((timelen - Double(sec))*1000)
                let min = Int(sec / 60)
                sec -= min * 60
                let infostr = String(format: "%02d:%02d.%03d", min, sec, msec)
                
                let newitem = RemoteData(context: viewContext)
                newitem.storage = self.storageName
                newitem.id = id
                newitem.name = name
                newitem.ext = "wav"
                newitem.cdate = item.cDate
                newitem.mdate = item.mDate
                newitem.folder = false
                newitem.size = size
                newitem.hashstr = ""
                newitem.parent = item.id
                newitem.path = item.path + "/\(index)"
                newitem.substart = start
                newitem.subend = end
                newitem.subid = wavId
                newitem.subinfo = infostr
            }
            await viewContext.perform {
                try? viewContext.save()
            }
        }
    }
    
    public func getSubitem(fileId: String) async -> RemoteItem? {
        let section = fileId.components(separatedBy: "\t")
        if section.count < 2 {
            return nil
        }
        guard let item = await getRaw(fileId: section[0]) else {
            return nil
        }
        if let uti = UTType(filenameExtension: item.ext), uti.conforms(to: .archive) {
            return await ArchiveRemoteItem(storage: item.storage, id: fileId)
        }
        else if item.ext.lowercased() == "cue" {
            return await CueSheetRemoteItem(storage: item.storage, id: fileId)
        }
        return nil
    }
}

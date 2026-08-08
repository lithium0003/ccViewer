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

extension RemoteItem {
    public var hasSubitems: Bool {
        if name == "VIDEO_TS.IFO" {
            return true
        }
        if ext.lowercased() == "iso" {
            return true
        }
        if let uti = UTType(filenameExtension: ext), uti.conforms(to: .archive) {
            return true
        }
        if ext.lowercased() == "cue" {
            return true
        }
        return false
    }
    
    class public func removeSubitem(storage: String, id: String) async {
        let context = CloudFactory.shared.data.backgroundContext
        
        let deletedIds = await context.perform {
            var ids: [String] = []
            
            func deleteRecursively(parentId: String) {
                let fetchRequest = NSFetchRequest<RemoteData>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", parentId, storage)
                if let results = try? context.fetch(fetchRequest) {
                    for item in results {
                        if let childId = item.id {
                            ids.append(childId)
                            deleteRecursively(parentId: childId)
                        }
                        context.delete(item)
                    }
                }
            }
            
            deleteRecursively(parentId: id)
            try? context.save()
            return ids
        }
        
        for childId in deletedIds {
            await CloudFactory.shared.cache.remove(storage: storage, id: childId)
        }
    }
}

extension RemoteDataDTO {
    public var hasSubitems: Bool {
        if let name {
            if name == "VIDEO_TS.IFO" {
                return true
            }
        }
        if let ext {
            if ext.lowercased() == "iso" {
                return true
            }
            if let uti = UTType(filenameExtension: ext), uti.conforms(to: .archive) {
                return true
            }
            if ext.lowercased() == "cue" {
                return true
            }
        }
        return false
    }
    
    public func getItem() async -> RemoteItem? {
        if hasSubitems {
            return await getSubitem()
        }
        if subid != nil {
            return await getSubitem()
        }
        guard let storage, let id, let service = await CloudFactory.shared.storageList.get(storage) else {
            return nil
        }
        return await service.get(fileId: id)
    }
    
    private func getSubitem() async -> RemoteItem? {
        func getSubItem2(storage: String, id: String, subid: String) async -> RemoteItem? {
            if subid.starts(with: "DVD") {
                return await DVDRemoteItem(storage: storage, id: id)
            }
            else if subid.starts(with: "ISO") {
                return await ISORemoteItem(storage: storage, id: id)
            }
            else if subid.starts(with: "WAV") {
                return await CueSheetRemoteItem(storage: storage, id: id)
            }
            else if subid.starts(with: "CAB") {
                return await ArchiveRemoteItem(storage: storage, id: id)
            }
            return nil
        }
        
        guard let section = id?.components(separatedBy: "\t") else {
            return nil
        }
        guard let storage, let service = await CloudFactory.shared.storageList.get(storage) else {
            return nil
        }
        guard let baseId = section.first else {
            return nil
        }
        guard let item = await service.get(fileId: baseId) else {
            return nil
        }
        if section.count == 1 {
            if item.name == "VIDEO_TS.IFO" {
                return await DVDRemoteItem.Create(from: item)
            }
            else if item.ext.lowercased() == "iso" {
                return await ISORemoteItem.Create(from: item)
            }
            else if let uti = UTType(filenameExtension: item.ext), uti.conforms(to: .archive) {
                return await ArchiveRemoteItem.Create(from: item)
            }
            else if item.ext.lowercased() == "cue" {
                return await CueSheetRemoteItem.Create(from: item)
            }
            return item
        }
        else {
            if let item = await getSubItem2(storage: storage, id: id!, subid: subid ?? "") {
                if item.name == "VIDEO_TS.IFO" {
                    return await DVDRemoteItem.Create(from: item)
                }
                if item.ext.lowercased() == "iso" {
                    return await ISORemoteItem.Create(from: item)
                }
                if item.ext.lowercased() == "cue" {
                    return await CueSheetRemoteItem.Create(from: item)
                }
                if let uti = UTType(filenameExtension: item.ext), uti.conforms(to: .archive) {
                    return await ArchiveRemoteItem.Create(from: item)
                }
                return item
            }
            else if let parent, let item = await CloudFactory.shared.data.getData(storage: storage, fileId: parent)?.getItem() {
                if item.name == "VIDEO_TS.IFO" {
                    return await DVDRemoteItem.Create(from: item)
                }
                if item.ext.lowercased() == "iso" {
                    return await ISORemoteItem.Create(from: item)
                }
                if item.ext.lowercased() == "cue" {
                    return await CueSheetRemoteItem.Create(from: item)
                }
                if let uti = UTType(filenameExtension: item.ext), uti.conforms(to: .archive) {
                    return await ArchiveRemoteItem.Create(from: item)
                }
                return item
            }
            return item
        }
    }
}

public class RemoteSubItem: RemoteItem {
    override public func list(force: Bool = false) async -> [RemoteDataDTO] {
        return await CloudFactory.shared.data.listData(storage: storage, parentID: id)
    }
}

//
//  SubItem.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/04/09.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreData

public protocol RemoteSubItem {
    func listsubitem(fileId: String) async
    func getsubitem(fileId: String) async -> RemoteItem?
}

extension RemoteStorageBase: RemoteSubItem {
    
    public func listsubitem(fileId: String) async {
        guard let item = await getRaw(fileId: fileId) else {
            return
        }
        if item.name.lowercased().hasSuffix(".cue") {
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            let itemid = item.id
            let storage = storageName ?? ""
            await backgroundContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", itemid, storage)
                if let result = try? backgroundContext.fetch(fetchRequest) {
                    for object in result {
                        backgroundContext.delete(object as! NSManagedObject)
                    }
                }
            }
            let stream = await item.open()
            guard let data = try? await stream.read(position: 0, length: Int(item.size)) else {
                return
            }
            guard let cue = CueSheet(data: data) else {
                return
            }
            guard let wavname = cue.targetWave else {
                return
            }
            let itemparent = item.parent
            let wavId = await backgroundContext.perform { () -> String? in
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@ && name == %@", itemparent, storage, wavname)
                
                guard let result = try? backgroundContext.fetch(fetchRequest) as? [RemoteData], let wavdata = result.first else {
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
                
                let newitem = RemoteData(context: backgroundContext)
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
            await backgroundContext.perform {
                try? backgroundContext.save()
            }
        }
    }
    
    public func getsubitem(fileId: String) async -> RemoteItem? {
        let section = fileId.components(separatedBy: "\t")
        if section.count < 2 {
            return nil
        }
        guard let item = await getRaw(fileId: section[0]) else {
            return nil
        }
        if item.name.lowercased().hasSuffix(".cue") {
            return await CueSheetRemoteItem(storage: item.storage, id: fileId)
        }
        return nil
    }
}

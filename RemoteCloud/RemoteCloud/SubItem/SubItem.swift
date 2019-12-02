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
    func listsubitem(fileId: String, onFinish: (() -> Void)?)
    func getsubitem(fileId: String) -> RemoteItem?
}

extension RemoteStorageBase: RemoteSubItem {
    
    public func listsubitem(fileId: String, onFinish: (() -> Void)?) {
        guard let item = getRaw(fileId: fileId) else {
            onFinish?()
            return
        }
        if item.name.lowercased().hasSuffix(".cue") {
            let backgroundContext = CloudFactory.shared.data.persistentContainer.newBackgroundContext()
            backgroundContext.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@", item.id, self.storageName ?? "")
                if let result = try? backgroundContext.fetch(fetchRequest) {
                    for object in result {
                        backgroundContext.delete(object as! NSManagedObject)
                    }
                }
            }
            let stream = item.open()
            stream.read(position: 0, length: Int(item.size)) { data in
                guard let data = data else {
                    onFinish?()
                    return
                }
                guard let cue = CueSheet(data: data) else {
                    onFinish?()
                    return
                }
                guard let wav = cue.targetWave else {
                    onFinish?()
                    return
                }
                var wavFile: RemoteWaveFile?
                var wavId = ""
                backgroundContext.perform {
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                    fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@ && name == %@", item.parent, self.storageName ?? "", wav)
                    
                    guard let result = try? backgroundContext.fetch(fetchRequest) as? [RemoteData], let wavdata = result.first else {
                        DispatchQueue.global().async {
                            onFinish?()
                        }
                        return
                    }
                    DispatchQueue.global().async {
                        guard let wavitem = self.get(fileId: wavdata.id ?? "") else {
                            DispatchQueue.global().async {
                                onFinish?()
                            }
                            return
                        }
                        wavId = wavdata.id ?? ""
                        
                        let wavstream = wavitem.open()
                        var wav: RemoteWaveFile?
                        for _ in 0..<5 {
                            wav = RemoteWaveFile(stream: wavstream, size: wavitem.size)
                            if wav != nil {
                                break
                            }
                        }
                        guard wav != nil else {
                            wavstream.isLive = false
                            wavitem.cancel()
                            return
                        }
                        wavFile = wav
                        wavstream.isLive = false

                        guard let wavFile = wavFile else {
                            DispatchQueue.global().async {
                                onFinish?()
                            }
                            return
                        }
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
                            newitem.path = item.path
                            newitem.substart = start
                            newitem.subend = end
                            newitem.subid = wavId
                            newitem.subinfo = infostr
                        }
                        try? backgroundContext.save()
                        DispatchQueue.global().async {
                            onFinish?()
                        }
                    }
                }
            }
        }
    }
    
    public func getsubitem(fileId: String) -> RemoteItem? {
        let section = fileId.components(separatedBy: "\t")
        if section.count < 2 {
            return nil
        }
        guard let item = getRaw(fileId: section[0]) else {
            return nil
        }
        if item.name.lowercased().hasSuffix(".cue") {
            return CueSheetRemoteItem(storage: item.storage, id: fileId)
        }
        return nil
    }
}

//
//  DVDItem.swift
//  RemoteCloud
//
//  Created by rei6 on 2019/04/09.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreData

public class DVDRemoteItem: RemoteSubItem {
    var vobitem: [RemoteItem] = []
    var vobStream: [RemoteStream] = []
    public var chapters: [([(Int64,Int64)], Int64, Double, String)] = []
    let title_idx: Int
    
    override init?(storage: String, id: String) async {
        let section = id.components(separatedBy: "\t")
        guard section.count > 1, let p = section.last, let t = Int(p) else {
            return nil
        }
        title_idx = t
        await super.init(storage: storage, id: id)
        
        guard let comp1 = subid?.dropFirst(3).components(separatedBy: "\n"), comp1.count > 1 else {
            return nil
        }
        guard let title_set_num = Int(comp1[0]) else { return }
        let chapt = comp1[1...].filter { !$0.isEmpty }
        for c in chapt {
            let citems = c.components(separatedBy: "\t")
            guard citems.count == 4 else {
                continue
            }
            guard let csize = Int64(citems[1]) else { continue }
            guard let cduration = Double(citems[2]) else { continue }
            var offset: [(Int64, Int64)] = []
            for p in citems[0].components(separatedBy: ";").filter({ !$0.isEmpty }) {
                let comp2 = p.components(separatedBy: ",")
                guard comp2.count == 2 else { continue }
                guard let start = Int64(comp2[0]), let end = Int64(comp2[1]) else { continue }
                offset.append((start * 2048, (end + 1) * 2048))
            }
            chapters.append((offset, csize * 2048, cduration, citems[3]))
        }
        
        let maxoffset = chapters.map{ $0.0.map(\.1).max() ?? 0 }.max() ?? 0
        
        let viewContext = CloudFactory.shared.data.viewContext
        guard let baseItem = await CloudFactory.shared.data.getData(storage: storage, fileId: parent)?.getItem() else {
            return nil
        }
        let parent = baseItem.parent
        var i = 1
        var curOffset: Int64 = 0
        while curOffset < maxoffset {
            let vob_file = "VTS_\(String(format: "%02d", title_set_num))_\(i).VOB"
            let vobdata = await viewContext.perform { () -> RemoteData? in
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@ && name == %@", parent, storage, vob_file)
                
                guard let result = try? viewContext.fetch(fetchRequest) as? [RemoteData], let ifodata = result.first else {
                    return nil
                }
                return ifodata
            }
            guard let vobdata, let item = await vobdata.getItem() else {
                break
            }
            vobitem.append(item)
            vobStream.append(await item.open())
            curOffset += item.size
            i += 1
        }
    }
    
    class func Create(from item: RemoteItem) async -> RemoteItem? {
        let viewContext = CloudFactory.shared.data.viewContext
        let itemid = item.id
        let storage = item.storage
        guard await CloudFactory.shared.data.listData(storage: storage, parentID: itemid).isEmpty else {
            return item
        }

        let stream = await item.open()
        guard let data = try? await stream.read() else {
            return nil
        }
        let magic = data.prefix(12)
        guard String(data: magic, encoding: .ascii) == "DVDVIDEO-VMG" else {
            return nil
        }
        guard data.count >= 0x00C4 + 4 else {
            print("Error: IFO file is too short or corrupted.")
            return nil
        }
        let tt_srpt_sec = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 0x00C4, as: UInt32.self).bigEndian
        }
        let tt_srpt_offset = Int(tt_srpt_sec) * 2048
        guard data.count >= tt_srpt_offset + 2 else {
            print("Error: IFO file is too short or corrupted.")
            return nil
        }
        let title_count = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: tt_srpt_offset, as: UInt16.self).bigEndian
        }
        let first_title_offset = tt_srpt_offset + 8
        var titles: [(String, Int, Int)] = []
        for i in 0..<Int(title_count) {
            let entry_offset = first_title_offset + (i * 12)
            
            guard data.count >= entry_offset + 12 else { break }
            
            data.withUnsafeBytes { buffer in
                let title_set_num = buffer.load(fromByteOffset: entry_offset + 6, as: UInt8.self)
                let vts_title_num = buffer.load(fromByteOffset: entry_offset + 7, as: UInt8.self)
                
                print("VTS_\(String(format: "%02d", title_set_num))_0.IFO title: \(vts_title_num)")
                titles.append(("VTS_\(String(format: "%02d", title_set_num))_0.IFO", Int(vts_title_num), Int(title_set_num)))
            }
        }
        for (index, (vts_ifo, title_num, title_set_num)) in titles.enumerated() {
            print("VTS: \(vts_ifo)")
            let itemparent = item.parent
            let ifodata = await viewContext.perform { () -> RemoteData? in
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "RemoteData")
                fetchRequest.predicate = NSPredicate(format: "parent == %@ && storage == %@ && name == %@", itemparent, storage, vts_ifo)
                
                guard let result = try? viewContext.fetch(fetchRequest) as? [RemoteData], let ifodata = result.first else {
                    return nil
                }
                return ifodata
            }
            if let ifodata, let data2 = try? await ifodata.getItem()?.open().read() {
                let magic = data2.prefix(12)
                guard String(data: magic, encoding: .ascii) == "DVDVIDEO-VTS" else {
                    continue
                }
                
                guard data2.count >= 0x00CC + 4 else {
                    print("Error: IFO file is too short or corrupted.")
                    continue
                }
                let vts_srpt_sec = data2.withUnsafeBytes { buffer in
                    buffer.load(fromByteOffset: 0x00C8, as: UInt32.self).bigEndian
                }
                let vts_ptt_srpt_offset = Int(vts_srpt_sec) * 2048
                guard data2.count >= vts_ptt_srpt_offset + 8 else {
                    print("Error: IFO file size (\(data2.count) bytes) is too small for offset \(vts_ptt_srpt_offset).")
                    continue
                }
                
                let vts_title_count = data2.withUnsafeBytes { buffer in
                    buffer.load(fromByteOffset: vts_ptt_srpt_offset, as: UInt16.self).bigEndian
                }
                print("Titles in this VTS: \(vts_title_count)")
                
                let vts_ptt_srpt_end = data2.withUnsafeBytes { buffer in
                    buffer.load(fromByteOffset: vts_ptt_srpt_offset + 4, as: UInt32.self).bigEndian
                }
                let table_end_absolute = vts_ptt_srpt_offset + Int(vts_ptt_srpt_end) + 1
                
                let title_pointers_start = vts_ptt_srpt_offset + 8
                guard title_num <= Int(vts_title_count) else {
                    continue
                }
                let t = title_num - 1
                var chapters: [(Int, Int)] = []
                let pointer_offset = title_pointers_start + (t * 4)
                
                let ptt_array_rel = data2.withUnsafeBytes { buffer in
                    buffer.load(fromByteOffset: pointer_offset, as: UInt32.self).bigEndian
                }
                let ptt_array_absolute = vts_ptt_srpt_offset + Int(ptt_array_rel)
                
                let next_array_absolute: Int
                if t < Int(vts_title_count) - 1 {
                    let next_rel = data2.withUnsafeBytes { buffer in
                        buffer.load(fromByteOffset: pointer_offset + 4, as: UInt32.self).bigEndian
                    }
                    next_array_absolute = vts_ptt_srpt_offset + Int(next_rel)
                } else {
                    next_array_absolute = table_end_absolute
                }
                
                let chapter_count = (next_array_absolute - ptt_array_absolute) / 4
                print("  Title \(t + 1) has \(chapter_count) Chapters (starts at: \(ptt_array_absolute))")
                
                for c in 0..<chapter_count {
                    let chapter_offset = ptt_array_absolute + (c * 4)
                    
                    data2.withUnsafeBytes { buffer in
                        let pgc_num = buffer.load(fromByteOffset: chapter_offset, as: UInt16.self).bigEndian
                        let pg_num = buffer.load(fromByteOffset: chapter_offset + 2, as: UInt16.self).bigEndian
                        print("    Chapter \(c + 1) -> PGC: \(pgc_num), Program: \(pg_num)")
                        
                        chapters.append((Int(pgc_num), Int(pg_num)))
                    }
                }
                
                let vts_pgciti_sec = data2.withUnsafeBytes { buffer in
                    buffer.load(fromByteOffset: 0x00CC, as: UInt32.self).bigEndian
                }
                
                let vts_pgciti_offset = Int(vts_pgciti_sec) * 2048
                guard data2.count >= vts_pgciti_offset + 8 else {
                    print("Error: IFO file size (\(data2.count) bytes) is too small for offset \(vts_ptt_srpt_offset).")
                    continue
                }
                
                let pgc_count = data2.withUnsafeBytes { buffer in
                    buffer.load(fromByteOffset: vts_pgciti_offset, as: UInt16.self).bigEndian
                }
                print("PGC Count: \(pgc_count)")
                
                let pgc_pointer_start = vts_pgciti_offset + 8
                var pgc: [([Int], [(Int, Int, Double)], String)] = []
                for i in 0..<Int(pgc_count) {
                    print("PGC: \(i+1)")
                    let pointer_offset = pgc_pointer_start + (i * 8)
                    
                    let pgc_relative_offset = data2.withUnsafeBytes { buffer in
                        buffer.load(fromByteOffset: pointer_offset + 4, as: UInt32.self).bigEndian
                    }
                    
                    let pgc_absolute_offset = vts_pgciti_offset + Int(pgc_relative_offset)

                    var paletteStr = "palette: "
                    if data2.count >= pgc_absolute_offset + 0x00A4 + 64 {
                        data2.withUnsafeBytes { buffer in
                            for c in 0..<16 {
                                let colorOffset = pgc_absolute_offset + 0x00A4 + (c * 4)
                                let y = Double(buffer.load(fromByteOffset: colorOffset + 1, as: UInt8.self))
                                let cr = Double(buffer.load(fromByteOffset: colorOffset + 2, as: UInt8.self))
                                let cb = Double(buffer.load(fromByteOffset: colorOffset + 3, as: UInt8.self))
                                
                                let r = y + 1.402 * (cr - 128.0)
                                let g = y - 0.344136 * (cb - 128.0) - 0.714136 * (cr - 128.0)
                                let b = y + 1.772 * (cb - 128.0)
                                
                                let r8 = UInt8(clamping: Int(round(r)))
                                let g8 = UInt8(clamping: Int(round(g)))
                                let b8 = UInt8(clamping: Int(round(b)))
                                
                                paletteStr += String(format: "%02x%02x%02x", r8, g8, b8)
                                if c < 15 { paletteStr += ", " }
                            }
                        }
                    } else {
                        paletteStr = "palette: 000000, ffffff, 000000, 7f7f7f, 000000, ffffff, 000000, 7f7f7f, 000000, ffffff, 000000, 7f7f7f, 000000, ffffff, 000000, 7f7f7f"
                    }
                    data2.withUnsafeBytes { buffer in
                        let pg_count = buffer.load(fromByteOffset: pgc_absolute_offset + 2, as: UInt8.self)
                        let cell_count = buffer.load(fromByteOffset: pgc_absolute_offset + 3, as: UInt8.self)
                        let pg_map_rel = buffer.load(fromByteOffset: pgc_absolute_offset + 0x00E6, as: UInt16.self).bigEndian
                        let pg_map_absolute = pgc_absolute_offset + Int(pg_map_rel)
                        let c_pbit_rel = buffer.load(fromByteOffset: pgc_absolute_offset + 0x00E8, as: UInt16.self).bigEndian
                        let c_pbit_absolute = pgc_absolute_offset + Int(c_pbit_rel)
                        print("  Programs: \(pg_count), Cells: \(cell_count)")
                        var program_map: [Int] = []
                        for p in 0..<Int(pg_count) {
                            let entry_cell = buffer.load(fromByteOffset: pg_map_absolute + p, as: UInt8.self)
                            
                            print("    Program \(p + 1) starts at -> Cell \(entry_cell)")
                            program_map.append(Int(entry_cell))
                        }
                        
                        print("  Cell Count: \(cell_count), C_PBIT starts at: \(c_pbit_absolute)")
                        var cell_offsets: [(Int, Int, Double)] = []
                        for c in 0..<Int(cell_count) {
                            let cell_offset = c_pbit_absolute + (c * 24)
                            guard data2.count >= cell_offset + 24 else { return }

                            let time_sec = data2.withUnsafeBytes { buffer -> Double in
                                let b0 = buffer.load(fromByteOffset: cell_offset + 4, as: UInt8.self)
                                let b1 = buffer.load(fromByteOffset: cell_offset + 5, as: UInt8.self)
                                let b2 = buffer.load(fromByteOffset: cell_offset + 6, as: UInt8.self)
                                let b3 = buffer.load(fromByteOffset: cell_offset + 7, as: UInt8.self)
                                
                                let hours   = Double((b0 >> 4) * 10 + (b0 & 0x0F))
                                let minutes = Double((b1 >> 4) * 10 + (b1 & 0x0F))
                                let seconds = Double((b2 >> 4) * 10 + (b2 & 0x0F))
                                
                                let fpsFlag = (b3 >> 6) & 0x03
                                let frameVal = b3 & 0x3F
                                let frames  = Double((frameVal >> 4) * 10 + (frameVal & 0x0F))
                                let fps     = (fpsFlag == 1) ? 25.0 : 29.97 // 1=PAL, 3=NTSC
                                
                                return (hours * 3600.0) + (minutes * 60.0) + seconds + (frames / fps)
                            }
                            let start_sector = buffer.load(fromByteOffset: cell_offset + 8, as: UInt32.self).bigEndian
                            let end_sector = buffer.load(fromByteOffset: cell_offset + 20, as: UInt32.self).bigEndian
                            
                            print("    Cell \(c + 1): Start = \(start_sector), End = \(end_sector), Time = \(time_sec)s")
                            cell_offsets.append((Int(start_sector), Int(end_sector), time_sec))
                        }
                        pgc.append((program_map,cell_offsets,paletteStr))
                    }
                }
                let id = "\(itemid)\t\(index)"
                var subid = "\(title_set_num)\n"
                var size = 0
                for (pgc_num, pg_num) in chapters {
                    let (program_map, cells, paletteStr) = pgc[pgc_num-1]
                    
                    let pg_index = pg_num - 1
                    let start_cell_idx = program_map[pg_index] - 1
                    
                    let end_cell_idx: Int
                    if pg_index + 1 < program_map.count {
                        end_cell_idx = program_map[pg_index + 1] - 2
                    } else {
                        end_cell_idx = cells.count - 1
                    }
                    
                    let chapter_cells = cells[start_cell_idx...end_cell_idx]
                    
                    var current = -1
                    var tmp_size = 0
                    var chapter_time_sec = 0.0
                    
                    for (start, end, time_sec) in chapter_cells {
                        tmp_size += end - start + 1
                        chapter_time_sec += time_sec
                        if current < 0 {
                            subid += "\(start),"
                        }
                        else if current + 1 != start {
                            subid += "\(current);\(start),"
                        }
                        current = end
                    }
                    subid += "\(current)\t\(tmp_size)\t\(chapter_time_sec)\t\(paletteStr)\n"
                    size += tmp_size
                }
                
                let size2 = size
                let subid2 = subid
                let cDate = item.cDate
                let mDate = item.mDate
                let path = item.path
                await viewContext.perform {
                    let newitem = RemoteData(context: viewContext)
                    newitem.storage = storage
                    newitem.id = id
                    newitem.name = "Title\(String(format: "%02d", index+1))"
                    newitem.ext = "mpg"
                    newitem.cdate = cDate
                    newitem.mdate = mDate
                    newitem.folder = false
                    newitem.size = Int64(size2) * 2048
                    newitem.hashstr = ""
                    newitem.parent = itemid
                    newitem.path = path + "/\(index)"
                    newitem.subid = "DVD"+subid2
                    newitem.subinfo = "\(chapter_count) Chapters"

                    try? viewContext.save()
                }
            }
        }
        return item
    }
    
    public override func open() async -> RemoteStream {
        return await DVDItemStream(remote: self)
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
        guard !chapters.isEmpty else { return nil }
        
        var remainingStart = start ?? 0
        var remainingLength = length ?? size
        var data = Data()
        
        for chapter in chapters {
            for (st, ed) in chapter.0 {
                if remainingLength <= 0 {
                    return data
                }
                
                let chapterLen = ed - st
                
                if remainingStart >= chapterLen {
                    remainingStart -= chapterLen
                    continue
                }
                
                var currentOffset = st + remainingStart
                var lengthToReadInChapter = min(remainingLength, chapterLen - remainingStart)
                
                while lengthToReadInChapter > 0 {
                    var volIndex = 0
                    var localOffset = currentOffset
                    for item in vobitem {
                        let vobSize = item.size
                        if localOffset < vobSize {
                            break
                        }
                        localOffset -= vobSize
                        volIndex += 1
                    }
                    guard volIndex < vobStream.count, volIndex < vobitem.count else { break }

                    let maxReadableInVol = vobitem[volIndex].size - localOffset
                    let bytesToRead = min(lengthToReadInChapter, maxReadableInVol)
                                    
                    guard let chunk = try await vobStream[volIndex].read(position: localOffset, length: Int(bytesToRead)) else {
                        return data.isEmpty ? nil : data
                    }
                    
                    data.append(chunk)
                    
                    currentOffset += bytesToRead
                    lengthToReadInChapter -= bytesToRead
                    remainingLength -= bytesToRead
                }
                remainingStart = 0
            }
        }
        
        return data.isEmpty ? nil : data
    }
}

public class DVDItemStream: SlotStream {
    let remote: DVDRemoteItem
    
    init(remote: DVDRemoteItem) async {
        self.remote = remote
        await super.init(size: remote.size)
    }

    override func setLive(_ live: Bool) {
        if !live {
            let sem = DispatchSemaphore(value: 0)
            Task(priority: .userInitiated) {
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
            let len = min(size - 1, pos.upperBound) - pos.lowerBound + 1
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

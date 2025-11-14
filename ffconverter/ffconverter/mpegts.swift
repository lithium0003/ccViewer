//
//  mpegts.swift
//  ffconverter
//
//  Created by rei8 on 2019/09/07.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import CoreMedia

class TS_writer {
    let PAT_interval = 1.0
    let PCR_interval = 0.1
    
    let dest_url: URL
    var data_count = 0
    var byterate = 0.0
    var calc_position = 0
    
    var last_write_m3u8 = -1
    
    let split_time: Double
    let time_hint: Double
    var split_count = 0
    var split_points: [CMTime] = [CMTime(seconds: 0, preferredTimescale: 90000)]
    var outfile: OutputStream?
    
    var last_PCR_time = 0.0
    var last_PCR_offset = -1
    
    var last_PAT_time = -1.0
    var last_time: CMTime?
    
    var touch_count = -1
    var audio_count = 0
    var video_count = 0
    
    var isFinished = false
    
    let writeQueue = DispatchQueue(label: "write")
    
    init(dest: URL, split_time: Double, time_hint: Double) {
        dest_url = dest
        self.split_time = split_time
        self.time_hint = time_hint
    }

    func set_channel(video: Int, audio: Int) {
        audio_count = audio
        video_count = video
    }
    
    func set_touch(count: Int) {
        touch_count = max(touch_count, count)
        if count < 0 {
            isFinished = true
        }
    }
    
    func write_m3u8() {
        let m3u8file = OutputStream(url: dest_url.appendingPathComponent("stream.m3u8"), append: last_write_m3u8 < 0 ? false : true)
        m3u8file?.open()
        defer {
            m3u8file?.close()
        }
        if last_write_m3u8 < 0 {
            let header = [
                "#EXTM3U",
                "#EXT-X-VERSION:3",
                "#EXT-X-TARGETDURATION:\(Int(time_hint))",
                "#EXT-X-MEDIA-SEQUENCE:0",
                "#EXT-X-PLAYLIST-TYPE:EVENT",
                ].joined(separator: "\r\n")+"\r\n"
            let data = Array(header.utf8)
            m3u8file?.write(data, maxLength: data.count)
            last_write_m3u8 = 0
        }
        guard split_points.count > last_write_m3u8+1 else {
            return
        }
        let t1 = split_points[last_write_m3u8]
        let t2 = split_points[last_write_m3u8+1]
        let value = max(1, (t2 - t1).seconds)
        let entry = [
            "#EXTINF:\(String(format: "%.8f", value)),",
            String(format: "stream%08d.ts", last_write_m3u8),
            ].joined(separator: "\r\n")+"\r\n"
        let data = Array(entry.utf8)
        m3u8file?.write(data, maxLength: data.count)
        last_write_m3u8 += 1
    }
    
    func write_callback(data: Data) {
        data_count += data.count
        if outfile == nil {
            outfile = OutputStream(url: dest_url.appendingPathComponent(String(format: "stream%08d.ts", split_count)), append: false)
            outfile?.open()
        }
        if let outfile = outfile {
            data.withUnsafeBytes {
                let _ = outfile.write($0.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: data.count)
            }
        }
    }
    
    func do_split(t: CMTime) {
        if let outfile = outfile {
            outfile.close()
            self.outfile = nil
            split_count += 1
            split_points += [t]
        }
        //print(split_points)
        print(split_count)
        outfile = OutputStream(url: dest_url.appendingPathComponent(String(format: "stream%08d.ts", split_count)), append: false)
        outfile?.open()
        last_PCR_time = 0.0
        last_PCR_offset = -1
        last_PAT_time = -1.0
        write_m3u8()
    }
    
    func finalize() {
        if let outfile = outfile {
            outfile.close()
            self.outfile = nil
            split_count += 1
            split_points += [last_time == nil ? CMTime(seconds: 0, preferredTimescale: 90000) : last_time!]
        }
        write_m3u8()
        
        let m3u8file = OutputStream(url: dest_url.appendingPathComponent("stream.m3u8"), append: last_write_m3u8 < 0 ? false : true)
        m3u8file?.open()
        defer {
            m3u8file?.close()
        }
        let entry = [
            "#EXT-X-ENDLIST",
            ].joined(separator: "\r\n")+"\r\n"
        let data = Array(entry.utf8)
        m3u8file?.write(data, maxLength: data.count)
    }
    
    func can_split(t: CMTime) -> Bool {
        let last_t = split_points.last!
        if (t - last_t).seconds > split_time {
            do_split(t: t)
            initial_write()
            return true
        }
        return false
    }
    
    let service_id = UInt16(0x0001)
    let PMT_PID = UInt16(0x1000)
    let PCR_PID = UInt16(0x0100)
    var cont_counter = [UInt16: Int]()
    
    func initial_write() {
        let pat = PA_section()
        pat.transport_stream_id = 0x0001
        let prog = PA_section.Program_Info()
        prog.program_number = 0x0001
        prog.PID = self.PMT_PID
        pat.programs += [prog]
        
        for d in self.section_packet(PID: 0x0000, section: pat) {
            self.write_callback(data: d)
        }
        
        let pmt = PM_section()
        pmt.program_number = 0x0001
        pmt.PCR_PID = self.PCR_PID
        let audio_PIDbase: UInt16
        if video_count > 0 {
            let stream1 = PM_section.stream_info_class()
            stream1.stream_type = 0x1b
            stream1.elementary_PID = 0x0100
            pmt.stream_info += [stream1]
            audio_PIDbase = 0x0101
        }
        else {
            audio_PIDbase = 0x0100
        }
        for i in 0..<audio_count {
            let stream2 = PM_section.stream_info_class()
            stream2.stream_type = 0x0f
            stream2.elementary_PID = audio_PIDbase + UInt16(i)
            pmt.stream_info += [stream2]
        }
        
        for d in self.section_packet(PID: 0x1000, section: pmt) {
            self.write_callback(data: d)
        }
        
        self.last_PAT_time = self.get_PCR()
    }
    
    func write_video(PS_stream: Data, PTS: CMTime?, DTS: CMTime?, keyframe: Bool) {
        writeQueue.async {
            var PAT_write = false
            if self.last_PAT_time < 0 {
                PAT_write = true
            }
            let t = self.get_PCR()
            if t - self.last_PAT_time > self.PAT_interval {
                PAT_write = true
            }
            if PAT_write {
                self.initial_write()
            }
            
            if let PTS = PTS, keyframe {
                if self.can_split(t: PTS) {
                    print("**************************************************")
                    print("Split ", PTS.seconds, DTS?.seconds ?? "?", self.get_PCR())
                }
            }

            if self.video_count > 0 {
                autoreleasepool {
                    let pes = TS_PESpacket()
                    pes.stream_id = 0xE0
                    pes.PES_payload = PS_stream
                    if let PTS = PTS {
                        pes.PTS = PTS
                    }
                    if let DTS = DTS {
                        pes.DTS = DTS
                    }
                    
                    for d in self.PES_packet(PID: 0x0100, PES_data: pes) {
                        self.write_callback(data: d)
                    }
                }
            }
            if let DTS = DTS {
                self.last_time = DTS
                if DTS.seconds > 0 {
                    self.byterate = Double(self.data_count) / DTS.seconds
                    self.calc_position = self.data_count
                }
            }
            else if let PTS = PTS {
                self.last_time = PTS
                if PTS.seconds > 0 {
                    self.byterate = Double(self.data_count) / PTS.seconds
                    self.calc_position = self.data_count
                }
            }
            //print("video,", PTS?.seconds, DTS?.seconds)
        }
    }

    func write_audio(PS_stream: Data, PTS: CMTime?, index: Int) {
        guard PS_stream.count >= 0 else {
            return
        }
        if self.last_time == nil {
            while !isFinished, self.last_time == nil {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        while !isFinished, let PTS = PTS, let last_time = self.last_time, PTS > last_time {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if isFinished {
            return
        }
        writeQueue.async {
            var PAT_write = false
            if self.last_PAT_time < 0 {
                PAT_write = true
            }
            let t = self.get_PCR()
            if t - self.last_PAT_time > self.PAT_interval {
                PAT_write = true
            }
            if PAT_write {
                self.initial_write()
            }
            
            autoreleasepool {
                let pes = TS_PESpacket()
                pes.stream_id = 0xc0 + UInt8(index)
                pes.PES_payload = PS_stream
                if let PTS = PTS {
                    pes.PTS = PTS
                }
                
                let PIDbase: UInt16
                if self.video_count > 0 {
                    PIDbase = 0x0101
                }
                else {
                    PIDbase = 0x0100
                }
                
                for d in self.PES_packet(PID: PIDbase + UInt16(index), PES_data: pes) {
                    self.write_callback(data: d)
                }
            }
            //print("audio,", PTS?.seconds)
        }
    }

    func get_PCR() -> Double {
        if let last_time = last_time, last_time.seconds > 0 {
            return last_time.seconds
        }
        return 0
    }
    
    func PES_packet(PID: UInt16, PES_data: TS_PESpacket) -> [Data] {
        var PCR_write = false
        let t = get_PCR()
        if t - last_PCR_time > PCR_interval {
            PCR_write = true
        }
        if last_PCR_offset < 0 {
            PCR_write = true
        }
        if PID != PCR_PID {
            PCR_write = false
        }
        
        var ret = [Data]()
        let pes_data = PES_data.GetData()
        var offset = 0
        while offset < pes_data.count {
            var packet = Data()
            let sync = UInt8(0x47)
            packet.append(sync)
            var tmp: UInt8 = offset == 0 ? 0b0100_0000 : 0b0000_0000
            tmp = tmp | UInt8((PID & 0x1FFF) >> 8)
            packet.append(tmp)
            tmp = UInt8(PID & 0xFF)
            packet.append(tmp)
            if let c = cont_counter[PID] {
                tmp = UInt8(c & 0x0F)
                tmp += 1
                tmp &= 0x0F
            }
            else {
                tmp = 0
            }
            cont_counter[PID] = Int(tmp)
            var len = 188 - packet.count - 1
            
            if PCR_write {
                len -= 7
            }
            if pes_data.count - offset < len {
                // need padding
                tmp = tmp | 0b0011_0000
                packet.append(tmp)
                
                if PCR_write {
                    len = pes_data.count - offset
                    let alen = 188 - packet.count - (pes_data.count - offset) - 1
                    tmp = UInt8(alen)
                    packet.append(tmp)
                    
                    tmp = 0b0001_0000
                    packet.append(tmp)
                    
                    let pcr_base = Int(t * (27_000_000 / 300)) % 0x1_FFFF_FFFF
                    let pcr_ext = Int(t * 27_000_000) % 300
                    
                    tmp = UInt8((pcr_base >> 25) & 0xFF)
                    packet.append(tmp)
                    tmp = UInt8((pcr_base >> 17) & 0xFF)
                    packet.append(tmp)
                    tmp = UInt8((pcr_base >> 9) & 0xFF)
                    packet.append(tmp)
                    tmp = UInt8((pcr_base >> 1) & 0xFF)
                    packet.append(tmp)
                    tmp = UInt8((pcr_base & 0b0000_0001) << 7) | UInt8((pcr_ext >> 8) & 0b0000_0001) | 0b0111_1110
                    packet.append(tmp)
                    tmp = UInt8(pcr_ext & 0xFF)
                    packet.append(tmp)
                    
                    let padlen = 188 - packet.count - (pes_data.count - offset)
                    packet.append(contentsOf: [UInt8](repeating: 0xFF, count: padlen))
                }
                else {
                    var padlen = 188 - packet.count - (pes_data.count - offset) - 1
                    len = pes_data.count - offset
                    tmp = UInt8(padlen)
                    packet.append(tmp)
                    if padlen > 0 {
                        tmp = 0
                        padlen -= 1
                        packet.append(tmp)
                        packet.append(contentsOf: [UInt8](repeating: 0xFF, count: padlen))
                    }
                }
            }
            else if PCR_write {
                tmp = tmp | 0b0011_0000
                packet.append(tmp)
                
                let alen = UInt8(7)
                packet.append(alen)
                tmp = 0b0001_0000
                packet.append(tmp)
                
                //print(t)
                let pcr_base = Int(t * (27_000_000 / 300)) % 0x1_FFFF_FFFF
                let pcr_ext = Int(t * 27_000_000) % 300
                
                tmp = UInt8((pcr_base >> 25) & 0xFF)
                packet.append(tmp)
                tmp = UInt8((pcr_base >> 17) & 0xFF)
                packet.append(tmp)
                tmp = UInt8((pcr_base >> 9) & 0xFF)
                packet.append(tmp)
                tmp = UInt8((pcr_base >> 1) & 0xFF)
                packet.append(tmp)
                tmp = UInt8((pcr_base & 0b0000_0001) << 7) | UInt8((pcr_ext >> 8) & 0b0000_0001) | 0b0111_1110
                packet.append(tmp)
                tmp = UInt8(pcr_ext & 0xFF)
                packet.append(tmp)
                
                len = 188 - packet.count
            }
            else {
                tmp = tmp | 0b0001_0000
                packet.append(tmp)
            }
            packet.append(pes_data.subdata(in: offset..<(offset+len)))
            offset += len
            ret += [packet]
            
            if PCR_write {
                PCR_write = false
                last_PCR_offset = data_count
                last_PCR_time = t
            }
        }
        return ret
    }
    
    func section_packet(PID: UInt16, section: TS_section) -> [Data] {
        var ret = [Data]()
        let section_data = section.GetData()
        var offset = 0
        while offset < section_data.count {
            var packet = Data()
            let sync = UInt8(0x47)
            packet.append(sync)
            var tmp: UInt8 = offset == 0 ? 0b0100_0000 : 0b0000_0000
            tmp = tmp | UInt8((PID & 0x1FFF) >> 8)
            packet.append(tmp)
            tmp = UInt8(PID & 0xFF)
            packet.append(tmp)
            if let c = cont_counter[PID] {
                tmp = UInt8(c & 0x0F)
                tmp += 1
                tmp &= 0x0F
            }
            else {
                tmp = 0
            }
            cont_counter[PID] = Int(tmp)
            tmp = tmp | 0b0001_0000
            packet.append(tmp)
            var len = 188 - packet.count
            if section_data.count - offset <= len - 1 {
                len = section_data.count - offset
                if offset == 0 {
                    tmp = 0
                    packet.append(tmp)
                }
                packet.append(section_data.subdata(in: offset..<(offset+len)))
                offset += len
                let pad = [UInt8](repeating: 0xFF, count: 188-packet.count)
                packet.append(contentsOf: pad)
            }
            else {
                if offset == 0 {
                    tmp = 0
                    packet.append(tmp)
                    len -= 1
                }
                packet.append(section_data.subdata(in: offset..<(offset+len)))
                offset += len
            }
            ret += [packet]
        }
        return ret
    }
}

class TS_section {
    var table_id: UInt8 = 0
    var reserved: UInt8 = 0b1111_0000
    var section_length: Int = 0
    var section_extended: UInt16 = 0
    var version_number: UInt8 = 0
    var current_next_indicator = true
    var section_number: UInt8 = 0
    var last_section_number: UInt8 = 0
    var section_data = Data()
    
    func GetData() -> Data {
        var ret = Data()
        section_length = section_data.count + 5 + 4
        
        ret.append(table_id)
        var tmp: UInt8 = reserved | UInt8(section_length >> 8)
        ret.append(tmp)
        tmp = UInt8(section_length & 0xFF)
        ret.append(tmp)
        tmp = UInt8(section_extended >> 8)
        ret.append(tmp)
        tmp = UInt8(section_extended & 0xFF)
        ret.append(tmp)
        tmp = 0b1100_0000 | (version_number & 0b0001_1111) << 1 | (current_next_indicator ? 1 : 0)
        ret.append(tmp)
        ret.append(section_number)
        ret.append(last_section_number)
        ret.append(section_data)
        
        let crc32 = self.crc32(data: [UInt8](ret))
        tmp = UInt8((crc32 >> 24) & 0xff)
        ret.append(tmp)
        tmp = UInt8((crc32 >> 16) & 0xff)
        ret.append(tmp)
        tmp = UInt8((crc32 >> 8) & 0xff)
        ret.append(tmp)
        tmp = UInt8(crc32 & 0xff)
        ret.append(tmp)
        
        return ret
    }
    
    var crcTable: [UInt32] = []
    func crc32(data: [UInt8]) -> UInt32 {
        if crcTable.count == 0 {
            makeTable()
        }
        var crc = UInt32(0xffffffff)
        for d in data {
            crc = (crc << 8) ^ crcTable[Int(((crc >> 24) ^ UInt32(d)) & 0xff)]
        }
        return crc
    }
    
    func makeTable() {
        let MPEG2TS_POLYNOMIAL = UInt32(0x04c11db7)
        crcTable = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt32(i << 24)
            for _ in 0..<8 {
                crc = (crc << 1) ^ ( (crc & 0x80000000) != 0 ? MPEG2TS_POLYNOMIAL : 0)
            }
            crcTable[i] = crc
        }
    }
}

class PA_section: TS_section {
    var transport_stream_id: UInt16 = 0
    var programs = [Program_Info]()
    
    class Program_Info {
        var program_number = UInt16(0)
        var PID = UInt16(0)
    }
    
    override func GetData() -> Data {
        table_id = 0
        reserved = 0b1011_0000
        current_next_indicator = true
        section_number = 0
        last_section_number = 0
        section_extended = transport_stream_id
        var secdata = Data()
        for prog in programs {
            var tmp: UInt8
            tmp = UInt8(prog.program_number >> 8)
            secdata.append(tmp)
            tmp = UInt8(prog.program_number & 0xFF)
            secdata.append(tmp)
            let pid = prog.PID & 0x1FFF
            tmp = UInt8(pid >> 8) | 0b1110_0000
            secdata.append(tmp)
            tmp = UInt8(pid & 0xFF)
            secdata.append(tmp)
        }
        section_data = secdata
        return super.GetData()
    }
}

class PM_section: TS_section {
    var program_number: UInt16 = 0
    var PCR_PID: UInt16 = 0
    var program_info: [descriptor] = []
    var stream_info: [stream_info_class] = []
    
    class stream_info_class {
        var stream_type = UInt8(0)
        var elementary_PID = UInt16(0)
        var ES_info: [descriptor] = []
    }
    
    override func GetData() -> Data {
        table_id = 0x02
        reserved = 0b1011_0000
        current_next_indicator = true
        section_number = 0
        last_section_number = 0
        section_extended = program_number
        PCR_PID = PCR_PID & 0x1FFF
        
        var secdata = Data()
        var tmp: UInt8
        tmp = UInt8(PCR_PID >> 8) | 0b1110_0000
        secdata.append(tmp)
        tmp = UInt8(PCR_PID & 0xFF)
        secdata.append(tmp)
        
        var descriptor = Data()
        for desc in program_info {
            descriptor.append(desc.save())
        }
        let program_info_length = descriptor.count
        secdata.append(UInt8(program_info_length >> 8) | 0b1111_0000)
        secdata.append(UInt8(program_info_length & 0xFF))
        secdata.append(descriptor)
        
        for stream in stream_info {
            secdata.append(stream.stream_type)
            let pid = stream.elementary_PID & 0x1FFF
            tmp = UInt8(pid >> 8) | 0b1110_0000
            secdata.append(tmp)
            tmp = UInt8(pid & 0xFF)
            secdata.append(tmp)
            descriptor = Data()
            for desc in stream.ES_info {
                descriptor.append(desc.save())
            }
            let ES_info_length = descriptor.count
            secdata.append(UInt8(ES_info_length >> 8) | 0b1111_0000)
            secdata.append(UInt8(ES_info_length & 0xFF))
            secdata.append(descriptor)
        }
        
        section_data = secdata
        return super.GetData()
    }
}

class TS_PESpacket {
    var stream_id: UInt8 = 0
    var PES_packet_length: UInt16 = 0
    var PTS: CMTime?
    var DTS: CMTime?
    var PES_payload = Data()
    
    func GetData() -> Data {
        var ret = Data()
        var tmp = UInt8(0x00)
        ret.append(tmp)
        ret.append(tmp)
        tmp = 0x01
        ret.append(tmp)
        ret.append(stream_id)
        
        let body = GetBody()
        switch stream_id {
        case 0xE0...0xEF:
            PES_packet_length = 0
        default:
            PES_packet_length = UInt16(body.count)
        }
        tmp = UInt8(PES_packet_length >> 8)
        ret.append(tmp)
        tmp = UInt8(PES_packet_length & 0xFF)
        ret.append(tmp)
        ret.append(body)
        
        return ret
    }
    
    func GetBody() -> Data {
        var ret = Data()
        var tmp = UInt8(0b1000_0000)
        ret.append(tmp)
        
        var header = Data()
        if let PTS = PTS {
            if let DTS = DTS {
                tmp = 0b1100_0000
                ret.append(tmp)
                
                let PTS1 = CMTimeConvertScale(PTS, timescale: 27_000_000 / 300, method: .roundHalfAwayFromZero)
                let DTS1 = CMTimeConvertScale(DTS, timescale: 27_000_000 / 300, method: .roundHalfAwayFromZero)
                
                let PTSk = PTS1.value % 0x1_FFFF_FFFF
                let DTSk = DTS1.value % 0x1_FFFF_FFFF
            
                tmp = 0b0011_0001
                tmp |= UInt8(((PTSk >> 30) & 0b111) << 1)
                header.append(tmp)
                tmp = UInt8((PTSk >> 22) & 0xFF)
                header.append(tmp)
                tmp = 0b0000_0001
                tmp |= UInt8(((PTSk >> 15) & 0b0111_1111) << 1)
                header.append(tmp)
                tmp = UInt8((PTSk >> 7) & 0xFF)
                header.append(tmp)
                tmp = 0b0000_0001
                tmp |= UInt8((PTSk & 0b0111_1111) << 1)
                header.append(tmp)
                
                tmp = 0b0001_0001
                tmp |= UInt8(((DTSk >> 30) & 0b111) << 1)
                header.append(tmp)
                tmp = UInt8((DTSk >> 22) & 0xFF)
                header.append(tmp)
                tmp = 0b0000_0001
                tmp |= UInt8(((DTSk >> 15) & 0b0111_1111) << 1)
                header.append(tmp)
                tmp = UInt8((DTSk >> 7) & 0xFF)
                header.append(tmp)
                tmp = 0b0000_0001
                tmp |= UInt8((DTSk & 0b0111_1111) << 1)
                header.append(tmp)
            }
            else {
                tmp = 0b1000_0000
                ret.append(tmp)
                
                let PTS1 = CMTimeConvertScale(PTS, timescale: 27_000_000 / 300, method: .roundHalfAwayFromZero)
                let PTSk = PTS1.value % 0x1_FFFF_FFFF
                
                tmp = 0b0010_0001
                tmp |= UInt8(((PTSk >> 30) & 0b111) << 1)
                header.append(tmp)
                tmp = UInt8((PTSk >> 22) & 0xFF)
                header.append(tmp)
                tmp = 0b0000_0001
                tmp |= UInt8(((PTSk >> 15) & 0b0111_1111) << 1)
                header.append(tmp)
                tmp = UInt8((PTSk >> 7) & 0xFF)
                header.append(tmp)
                tmp = 0b0000_0001
                tmp |= UInt8((PTSk & 0b0111_1111) << 1)
                header.append(tmp)
            }
        }
        else {
            tmp = 0b0000_0000
            ret.append(tmp)
        }
        tmp = UInt8(header.count)
        ret.append(tmp)
        ret.append(header)
        
        ret.append(PES_payload)
        return ret
    }
}

class descriptor {
    var tag: UInt8 = 0
    var length = 0
    var body: [UInt8] = []
    
    func load(data: [UInt8]) -> Int? {
        guard data.count >= 2 else {
            return nil
        }
        tag = data[0]
        length = Int(data[1])
        guard data.count >= length+2 else {
            return nil
        }
        body = Array(data[2..<(2+length)])
        return 2+length
    }
    
    func save() -> Data {
        var ret = Data()
        length = body.count
        ret.append(tag)
        ret.append(UInt8(length))
        ret.append(contentsOf: body)
        return ret
    }
    
    func dump() -> String {
        var str = [
            "tag: \(tag) \(String(format: "0x%02x", tag))",
        ]
        str += [body.map({ String(format: "%02x", $0) }).joined(separator: " ")]
        return str.joined(separator: "\r\n")
    }
}

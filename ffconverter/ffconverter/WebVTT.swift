//
//  WebVTT.swift
//  ffconverter
//
//  Created by rei8 on 2019/11/13.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation

class WebVTTwriter {
    let dest_url: URL
    let split_time: Double
    let time_hint: Double
    var split_count = 0
    var split_points: [Double] = [0]
    var last_time: Double?
    var outfile: OutputStream?
    var last_write_m3u8 = -1
    var counter = 0
    
    let writeQueue = DispatchQueue(label: "write")

    init(dest: URL, split_time: Double, time_hint: Double) {
        dest_url = dest
        self.split_time = split_time
        self.time_hint = time_hint
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
        let entry = [
            "#EXTINF:\(String(format: "%.8f", max(1, t2-t1))),",
            String(format: "stream%08d.vtt", last_write_m3u8),
            ].joined(separator: "\r\n")+"\r\n"
        let data = Array(entry.utf8)
        m3u8file?.write(data, maxLength: data.count)
        last_write_m3u8 += 1
    }

    func write_callback(data: Data) {
        if outfile == nil {
            outfile = OutputStream(url: dest_url.appendingPathComponent(String(format: "stream%08d.vtt", split_count)), append: false)
            outfile?.open()
            initial_write()
        }
        if let outfile = outfile {
            data.withUnsafeBytes {
                let _ = outfile.write($0.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: data.count)
            }
        }
    }

    func do_split(t: Double) {
        if let outfile = outfile {
            outfile.close()
            self.outfile = nil
            split_count += 1
            split_points += [t]
            last_time = t
        }
        print(split_count)
        outfile = OutputStream(url: dest_url.appendingPathComponent(String(format: "stream%08d.vtt", split_count)), append: false)
        outfile?.open()
        write_m3u8()
        initial_write()
    }

    func finalize() {
        if let outfile = outfile {
            outfile.close()
            self.outfile = nil
            split_count += 1
            split_points += [last_time ?? 0]
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

    func can_split(st: Double, et: Double) {
        if et - split_points.last! <= split_time {
            return
        }
        if st - split_points.last! > split_time {
            while st - split_points.last! > split_time {
                do_split(t: split_points.last!+split_time)
            }
        }
        if et - split_points.last! > split_time {
            do_split(t: st)
        }
    }

    func initial_write() {
        let header = "WEBVTT\r\n\r\n\r\n"
        write_callback(data: header.data(using: .utf8)!)
    }
    
    func convert_timestamp(t: Double) -> String {
        let hour = Int(t / 3600)
        let min = Int((t - Double(hour) * 3600) / 60)
        let sec = Int(t - Double(hour * 3600 + min * 60))
        let msec = Int((t - Double(hour * 3600 + min * 60 + sec)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hour, min, sec, msec)
    }
    
    func sanitize_str(str: String) -> String {
        var str2 = str.replacingOccurrences(of: "&", with: "＆")
        str2 = str2.replacingOccurrences(of: "<", with: "＜")
        str2 = str2.replacingOccurrences(of: ">", with: "＞")
        return str2
    }
    
    func split_check(pts: Double) {
        writeQueue.async {
            if pts - self.split_points.last! > self.split_time {
                self.do_split(t: pts)
            }
        }
    }
    
    func write_text(caption: String, pts_start: Double, pts_end: Double) {
        if caption.filter({ !$0.isWhitespace }).isEmpty { return }
        writeQueue.async {
            self.can_split(st: pts_start, et: pts_end)
            
            let content = "\(self.convert_timestamp(t: pts_start)) --> \(self.convert_timestamp(t: pts_end))\r\n" +
            self.sanitize_str(str: caption) + "\r\n\r\n"
            self.write_callback(data: content.data(using: .utf8)!)
        }
    }
}

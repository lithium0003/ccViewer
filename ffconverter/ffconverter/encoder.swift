//
//  encoder.swift
//  ffconverter
//
//  Created by rei8 on 2019/09/07.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMedia
import VideoToolbox
import CoreAudio

class Encoder {
    let width = 1920
    let height = 1080
    //let width = 1280
    //let height = 720

    var compressionSession: VTCompressionSession?
    var pxbuffer: CVPixelBuffer?

    var audio_count: Int = -1
    var subtitle_count: Int = -1
    var audios: [sound_processer] = []
    var writer: [TS_writer?] = []
    var subwriter: [WebVTTwriter?] = []
    let dest: URL
    var isLive = true
    var needWait: Bool {
        var wait = true
        for w in writer {
            if let w {
                if w.last_write_m3u8 < 0 {
                    wait = false
                    break
                }
                if w.touch_count >= 0 {
                    wait = false
                    break
                }
            }
        }
        return wait
    }
    
    class sound_processer {
        let sound_fq = 48000.0
        let ch: Int

        let bufferQueue: DispatchQueue
        var lpcmToAACConverter: AVAudioConverter? = nil
        var sound_buffer = Data()
        var sound_RDBs: [Data] = []
        var sound_pts: Double? = nil

        init(channel: Int) {
            ch = channel
            bufferQueue = DispatchQueue(label: "bufferQueue \(channel)")
        }
        
        func process_sound(writer: TS_writer?, final: Bool = false) {
            autoreleasepool {
                let outFormat: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: sound_fq,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRatePerChannelKey: 320000,
                    AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Variable,
                ]
                guard let outputFormat = AVAudioFormat(settings: outFormat) else {
                    return
                }
                
                guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sound_fq, channels: 2, interleaved: true) else {
                    return
                }
                
                //init converter once
                if lpcmToAACConverter == nil {
                    lpcmToAACConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
                }
                let outBuffer = AVAudioCompressedBuffer(format: outputFormat, packetCapacity: 1, maximumPacketSize: 1024 * 2)
                
                let inputBlock : AVAudioConverterInputBlock = { [weak self] (inNumPackets, outStatus) -> AVAudioBuffer? in
                    outStatus.pointee = .noDataNow
                    guard let self = self else {
                        return nil
                    }
                    return self.bufferQueue.sync {
                        let sample_size = MemoryLayout<Float>.size * 2
                        if self.sound_buffer.count <= (final ? 0 : sample_size * 1024) {
                            return nil
                        }
                        var samples = self.sound_buffer.count / sample_size
                        if samples > 1024 {
                            samples = 1024
                        }
                        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples)) else {
                            return nil
                        }
                        guard let target = inputBuffer.floatChannelData else {
                            return nil
                        }
                        let _ = self.sound_buffer.withUnsafeBytes { wav_data in
                            memcpy(target.pointee, wav_data.baseAddress, samples*sample_size)
                        }
                        self.sound_buffer = self.sound_buffer.subdata(in: (samples*sample_size)..<self.sound_buffer.count)
                        inputBuffer.frameLength = inputBuffer.frameCapacity
                        outStatus.pointee = AVAudioConverterInputStatus.haveData
                        let audioBuffer : AVAudioBuffer = inputBuffer
                        return audioBuffer
                    }
                }
                var status: AVAudioConverterOutputStatus?
                var error : NSError?
                
                repeat {
                    status = lpcmToAACConverter?.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
                    
                    if outBuffer.byteLength > 0 {
                        var data = [UInt8](repeating: 0, count: Int(outBuffer.byteLength))
                        data.withUnsafeMutableBufferPointer { p in
                            let _ = memcpy(p.baseAddress, outBuffer.data, Int(outBuffer.byteLength))
                        }
                        
                        sound_RDBs += [Data(data)]
                    }
                } while status == .haveData
                
                var spts: CMTime? = nil
                if let pts = self.sound_pts {
                    spts = CMTime(seconds: pts, preferredTimescale: CMTimeScale(self.sound_fq))
                }
                for RDBblock in sound_RDBs {
                    var PESdata = Data()
                    let len = RDBblock.count
                    PESdata.append(0xFF)
                    PESdata.append(0xF1)
                    let profile = 2  //AAC LC
                    let freqIdx = self.sound_fq == 48000 ? 3 : 4 //3:48kHz, 4:44.1kHz
                    let chanCfg = 2  //L R
                    let adtsLength = 7
                    let fullLength = adtsLength + len
                    PESdata.append(UInt8(((profile-1)<<6)|(freqIdx<<2)|(chanCfg>>2)))
                    PESdata.append(UInt8(((chanCfg&3)<<6)|((fullLength&0x1800)>>11)))
                    PESdata.append(UInt8(((fullLength&0x7FF) >> 3)))
                    PESdata.append(UInt8((((fullLength&7)<<5)|0x1F)))
                    PESdata.append(0xFC)
                    PESdata.append(RDBblock)

                    writer?.write_audio(PS_stream: PESdata, PTS: spts, index: 0)
                    if spts != nil {
                        spts = spts! + CMTime(seconds: 1024/self.sound_fq, preferredTimescale: CMTimeScale(self.sound_fq))
                    }
                }
                sound_RDBs = []
            }
        }
    }
    
    init?(dest: URL) {
        self.dest = dest

        var formatHint: CMFormatDescription? = nil
        var status = CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_H264, width: Int32(width), height: Int32(height), extensions: nil, formatDescriptionOut: &formatHint)
        guard status == noErr else {
            return nil
        }

        let sourceImageBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_420YpCbCr8Planar),
            kCVPixelBufferWidthKey: Int(width),
            kCVPixelBufferHeightKey: Int(height),
            ] as CFDictionary
        status = VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height), codecType: CMVideoCodecType(kCMVideoCodecType_H264), encoderSpecification: nil, imageBufferAttributes: sourceImageBufferAttributes, compressedDataAllocator: kCFAllocatorDefault, outputCallback: self.vt_compression_callback, refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &self.compressionSession)
        guard status == noErr else {
            return nil
        }
        
        let properties = [
            //kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_AverageBitRate: 5*1024*1024,
            kVTCompressionPropertyKey_AllowOpenGOP: false,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_4_1,
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: 5.0,
            ] as CFDictionary
        status = VTSessionSetProperties(self.compressionSession!, propertyDictionary: properties)
        guard status == noErr else {
            return nil
        }
        
        VTCompressionSessionPrepareToEncodeFrames(self.compressionSession!)

        status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8Planar, nil, &pxbuffer)
        guard status == noErr else {
            return nil
        }
    }
    
    func set_streamCount(audio_lng: [String], audio_main: Int, subtitle_lng: [String], subtitle_main: Int) {
        audio_count = audio_lng.count
        subtitle_count = subtitle_lng.count
        audios.removeAll()
        writer.removeAll()
        for i in 0...audio_count {
            if i > 0 {
                audios += [sound_processer(channel: i)]
            }
            let p = dest.appendingPathComponent("\(i)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return
            }
            let w = TS_writer(dest: p, split_time: 5.0, time_hint: 10.0)
            if i == 0 {
                w.set_channel(video: 1, audio: 0)
            }
            else {
                w.set_channel(video: 0, audio: 1)
            }
            writer += [w]
        }
        if subtitle_count > 0 {
            for i in (audio_count+1)...(audio_count+subtitle_count) {
                let p = dest.appendingPathComponent("\(i)", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    return
                }
                let wt = WebVTTwriter(dest: p, split_time: 10.0, time_hint: 20.0)
                subwriter += [wt]
            }
        }
        
        var content = [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-INDEPENDENT-SEGMENTS",
        ]
        let astr = FrameworkResource.getLocalized(key: "Audio")
        for i in 1...audio_count {
            let langstr = FrameworkResource.getLocalized(key: audio_lng[i-1])
            if i == audio_main+1 {
                content += ["#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"aac\",LANGUAGE=\"\(audio_lng[i-1])\",NAME=\"\(astr)\(i): \(langstr)\",AUTOSELECT=YES,DEFAULT=YES,URI=\"\(i)/stream.m3u8\""]
            }
            else {
                content += ["#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"aac\",LANGUAGE=\"\(audio_lng[i-1])\",NAME=\"\(astr)\(i): \(langstr)\",AUTOSELECT=YES,DEFAULT=NO,URI=\"\(i)/stream.m3u8\""]
            }
        }
        var sub_str = ""
        if subtitle_count > 0 {
            let sstr = FrameworkResource.getLocalized(key: "Subtitle")
            for i in 0..<subtitle_count {
                let langstr = FrameworkResource.getLocalized(key: subtitle_lng[i])
                let sid = audio_count+1+i
                if i == subtitle_main {
                    content += ["#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",LANGUAGE=\"\(subtitle_lng[i])\",NAME=\"\(sstr)\(i+1): \(langstr)\",AUTOSELECT=YES,DEFAULT=YES,URI=\"\(sid)/stream.m3u8\""]
                }
                else {
                    content += ["#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",LANGUAGE=\"\(subtitle_lng[i])\",NAME=\"\(sstr)\(i+1): \(langstr)\",AUTOSELECT=YES,DEFAULT=NO,URI=\"\(sid)/stream.m3u8\""]
                }
            }
            sub_str = ",SUBTITLES=\"subs\""
        }
        content += [
            "#EXT-X-STREAM-INF:BANDWIDTH=50000000,CODECS=\"avc1.640029, mp4a.40.5\",RESOLUTION=\(width)x\(height),AUDIO=\"aac\"\(sub_str)",
            "0/stream.m3u8"
            ]
        
        Task.detached {
            while self.isLive {
                var done = true
                for i in 0...(self.audio_count+self.subtitle_count) {
                    let p = self.dest.appendingPathComponent("\(i)", isDirectory: true)
                    if !FileManager.default.fileExists(atPath: p.appendingPathComponent("stream.m3u8").path(percentEncoded: false)) {
                        done = false
                        break
                    }
                }
                
                if !done {
                    sleep(1)
                    continue
                }
                break
            }
            
            let m3u8file = OutputStream(url: self.dest.appendingPathComponent("stream.m3u8"), append: false)
            m3u8file?.open()
            defer {
                m3u8file?.close()
            }
            let str = content.joined(separator: "\r\n") + "\r\n"
            let data = Array(str.utf8)
            m3u8file?.write(data, maxLength: data.count)
        }
    }
    
    func encode_frame(src_data: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, src_linesizes: UnsafeMutablePointer<Int32>?, src_height: Int32, pts: Double, key: Bool) {
        guard let pxbuffer = pxbuffer else {
            return
        }
        guard let src_data else {
            return
        }
        guard let src_linesizes else {
            return
        }
        guard let compressionSession = compressionSession else {
            return
        }
        var status = CVPixelBufferLockBaseAddress(pxbuffer, .init(rawValue: 0))
        guard status == noErr else {
            return
        }
        do {
            defer {
                CVPixelBufferUnlockBaseAddress(pxbuffer, .init(rawValue: 0))
            }
            let yp = CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 0)
            guard let ysrc = src_data[0] else { return }
            let sline = Int(src_linesizes[0])
            let dline = CVPixelBufferGetBytesPerRowOfPlane(pxbuffer, 0)
            for y in 0..<Int(height) {
                memcpy(yp! + dline * y, ysrc + sline * y, Int(width))
            }
            let up = CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 1)
            guard let usrc = src_data[1] else { return }
            let sline2 = Int(src_linesizes[1])
            let dline2 = CVPixelBufferGetBytesPerRowOfPlane(pxbuffer, 1)
            for y in 0..<Int(height) / 2 {
                memcpy(up! + dline2 * y, usrc + sline2 * y, Int(width)/2)
            }
            let vp = CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 2)
            guard let vsrc = src_data[2] else { return }
            let sline3 = Int(src_linesizes[2])
            let dline3 = CVPixelBufferGetBytesPerRowOfPlane(pxbuffer, 2)
            for y in 0..<Int(height) / 2 {
                memcpy(vp! + dline3 * y, vsrc + sline3 * y, Int(width)/2)
            }
        }
        //print(pts, key)
        let properties = [
            kVTEncodeFrameOptionKey_ForceKeyFrame: key,
            ] as CFDictionary
        status = VTCompressionSessionEncodeFrame(
            compressionSession,
            imageBuffer: pxbuffer,
            presentationTimeStamp: CMTime(seconds: pts, preferredTimescale: 90000),
            duration: .invalid,
            frameProperties: properties,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil)
        
        for sub in subwriter {
            sub?.split_check(pts: pts)
        }
    }
    
    func encode_sound(channel: Int, pcm_data: UnsafeBufferPointer<UInt8>, pts: Double) {
        let group = DispatchGroup()
        group.enter()
        audios[channel].bufferQueue.async {
            defer {
                group.leave()
            }
            self.audios[channel].sound_buffer.append(pcm_data)
            let sample_size = Double(MemoryLayout<Float>.size)
            self.audios[channel].sound_pts = pts - Double(self.audios[channel].sound_buffer.count)/(sample_size*2)/self.audios[channel].sound_fq
            if self.audios[channel].sound_buffer.count < Int(0.1*sample_size*2*self.audios[channel].sound_fq) {
                return
            }
        }
        group.wait()
        audios[channel].process_sound(writer: writer[channel+1])
    }
    
    func encode_text(channel: Int, text: String, pts_start: Double, pts_end: Double) {
        subwriter[channel]?.write_text(caption: text, pts_start: pts_start, pts_end: pts_end)
    }
    
    func finish_encode() {
        print("finish_encode()")
        Task {
            guard let compressionSession = self.compressionSession else {
                return
            }
            VTCompressionSessionCompleteFrames(compressionSession, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(compressionSession)
            self.compressionSession = nil
            
            if self.audio_count >= 0 {
                for channel in 0...self.audio_count {
                    if let writer = self.writer[channel] {
                        if channel > 0 {
                            self.audios[channel-1].process_sound(writer: writer, final: true)
                        }
                        writer.finalize()
                    }
                }
            }
            if self.subtitle_count > 0 {
                for i in 0..<self.subtitle_count {
                    if let writer = self.subwriter[i] {
                        writer.finalize()
                    }
                }
            }
        }
    }
    
    var vt_compression_callback:VTCompressionOutputCallback = {(outputCallbackRefCon: UnsafeMutableRawPointer?, sourceFrameRefCon: UnsafeMutableRawPointer?, status: OSStatus, infoFlags: VTEncodeInfoFlags, sampleBuffer: CMSampleBuffer?) in
        guard let frame = sampleBuffer else {
            print("nil buffer")
            return
        }
        guard let ref_unwrapped = outputCallbackRefCon else { return }
        guard status == noErr else {
            print(status)
            return
        }
        guard CMSampleBufferDataIsReady(frame) else {
            print("CMSampleBuffer is not ready to use")
            return
        }
        guard infoFlags != VTEncodeInfoFlags.frameDropped else {
            print("frame dropped")
            return
        }
        autoreleasepool {
            let encoder = Unmanaged<Encoder>.fromOpaque(ref_unwrapped).takeUnretainedValue()
            var elementaryStream = Data()
            // Find out if the sample buffer contains an I-Frame.
            // If so we will write the SPS and PPS NAL units to the elementary stream.
            var isIFrame = false
            if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(frame, createIfNecessary: false), CFArrayGetCount(attachmentsArray) > 0 {
                let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachmentsArray, 0), to: CFDictionary.self)
                if let dict = dict as? [String: AnyObject] {
                    if let notSync = dict[kCMSampleAttachmentKey_NotSync as String] as? Bool {
                        isIFrame = !notSync
                    }
                    else {
                        isIFrame = true
                    }
                }
            }
            
            // This is the start code that we will write to
            // the elementary stream before every NAL unit
            let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]
            let startCodeLength = startCode.count
            
            elementaryStream.append(contentsOf: startCode)
            elementaryStream.append(0x09)
            elementaryStream.append(0xf0)

            // Write the SPS and PPS NAL units to the elementary stream before every I-Frame
            if isIFrame, let description = CMSampleBufferGetFormatDescription(frame) {
                var numberOfParameterSets = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &numberOfParameterSets, nalUnitHeaderLengthOut: nil)
                
                // Write each parameter set to the elementary stream
                for i in 0..<numberOfParameterSets {
                    var parameterSetPointer: UnsafePointer<UInt8>?
                    var parameterSetLength = 0
                    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: i, parameterSetPointerOut: &parameterSetPointer, parameterSetSizeOut: &parameterSetLength, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                    
                    // Write the parameter set to the elementary stream
                    if let parameterSetPointer = parameterSetPointer {
                        elementaryStream.append(contentsOf: startCode)
                        elementaryStream.append(parameterSetPointer, count: parameterSetLength)
                    }
                }
            }
            
            // Get a pointer to the raw AVCC NAL unit data in the sample buffer
            var blockBufferLength = 0
            var bufferDataPointer: UnsafeMutablePointer<Int8>?
            if let block = CMSampleBufferGetDataBuffer(frame) {
                CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &blockBufferLength, dataPointerOut: &bufferDataPointer)
            }
            bufferDataPointer?.withMemoryRebound(to: UInt8.self, capacity: blockBufferLength) { bufferDataPointer in
                // Loop through all the NAL units in the block buffer
                // and write them to the elementary stream with
                // start codes instead of AVCC length headers
                var bufferOffset = 0
                let AVCCHeaderLength = 4
                while bufferOffset < blockBufferLength - AVCCHeaderLength {
                    // Read the NAL unit length
                    var NALUnitLength = UInt32(0)
                    memcpy(&NALUnitLength, bufferDataPointer + bufferOffset, AVCCHeaderLength);
                    // Convert the length value from Big-endian to Little-endian
                    NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
                    // Write start code to the elementary stream
                    elementaryStream.append(contentsOf: startCode)
                    // Write the NAL unit without the AVCC length header to the elementary stream
                    autoreleasepool {
                        var NALunit = [UInt8](repeating: 0, count: Int(NALUnitLength))
                        NALunit.withUnsafeMutableBufferPointer { p in
                            let _ = memcpy(p.baseAddress, bufferDataPointer + bufferOffset + AVCCHeaderLength, Int(NALUnitLength))
                        }
                        elementaryStream.append(contentsOf: NALunit)
                    }
                    // Move to the next NAL unit in the block buffer
                    bufferOffset += AVCCHeaderLength + Int(NALUnitLength);
                }
            }
            
            let pts_frame = CMSampleBufferGetPresentationTimeStamp(frame)
            let dts_frame = CMSampleBufferGetDecodeTimeStamp(frame)
            
            let pts: CMTime?
            if CMTIME_IS_VALID(pts_frame) {
                pts = pts_frame
            }
            else {
                pts = nil
            }
            let dts: CMTime?
            if CMTIME_IS_VALID(dts_frame) {
                dts = dts_frame
            }
            else {
                dts = nil
            }
            
            for writer in encoder.writer {
                writer?.write_video(PS_stream: elementaryStream, PTS: pts, DTS: dts, keyframe: isIFrame)
            }
        }
    }
}

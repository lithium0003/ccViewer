//
//  sound.swift
//  fftest
//
//  Created by rei8 on 2019/10/16.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import AudioToolbox
import AVFoundation
import MediaPlayer
import CoreAudio

class AudioQueuePlayer {
    let sampleRate = 48000.0
    
    var isPlay = false
    
    var onLoadData: ((UnsafeMutablePointer<Float>?, Int) -> Double)?
    var pts: Double = 0.0
    
    var audioUnit: AudioUnit?
    lazy var callbackStruct: AURenderCallbackStruct = {
        var callbackStruct = AURenderCallbackStruct()
        callbackStruct.inputProc = renderCallback
        callbackStruct.inputProcRefCon = Unmanaged.passUnretained(self).toOpaque()
        return callbackStruct
    }()

    init?() {
        var acd = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_RemoteIO, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        let audioComponent: AudioComponent = AudioComponentFindNext(nil, &acd)!
        guard AudioComponentInstanceNew(audioComponent, &audioUnit) == noErr else {
            return nil
        }
        guard AudioUnitInitialize(audioUnit!) == noErr else {
            return nil
        }
        
        guard AudioUnitSetProperty(audioUnit!, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callbackStruct, UInt32(MemoryLayout.size(ofValue: callbackStruct))) == noErr else {
            return nil
        }
        
        var asbd = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagsNativeFloatPacked, mBytesPerPacket: UInt32(MemoryLayout<Float32>.size)*2, mFramesPerPacket: 1, mBytesPerFrame: UInt32(MemoryLayout<Float32>.size)*2, mChannelsPerFrame: 2, mBitsPerChannel: UInt32(8 * MemoryLayout<UInt32>.size), mReserved: 0)
        
        guard AudioUnitSetProperty(audioUnit!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &asbd, UInt32(MemoryLayout.size(ofValue: asbd))) == noErr else {
            return nil
        }
    }

    deinit {
        AudioUnitUninitialize(audioUnit!)
        AudioComponentInstanceDispose(audioUnit!)
    }
    
    let renderCallback: AURenderCallback = {(
        inRefCon: UnsafeMutableRawPointer,
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inBusNumber: UInt32,
        inNumberFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus in
        let obj = Unmanaged<AudioQueuePlayer>.fromOpaque(inRefCon).takeUnretainedValue()
        
        guard let buf = UnsafeMutableAudioBufferListPointer(ioData) else {
            return noErr
        }
        let capacity = Int(buf[0].mDataByteSize) / MemoryLayout<Float>.size
        let buffer: UnsafeMutablePointer<Float>? = buf[0].mData?.bindMemory(to: Float.self, capacity: capacity)
        
        obj.pts = obj.onLoadData?(buffer, capacity) ?? 0

        return noErr
    }

    func play() {
        guard !isPlay else {
            return
        }
        guard AudioOutputUnitStart(audioUnit!) == noErr else {
            return
        }
        isPlay = true
    }
    
    func stop() {
        guard isPlay else {
            return
        }
        guard AudioOutputUnitStop(audioUnit!) == noErr else {
            return
        }
        isPlay = false
    }
}

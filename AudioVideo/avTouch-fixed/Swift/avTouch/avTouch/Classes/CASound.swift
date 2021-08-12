//
// Created by Bq Lin on 2021/8/12.
// Copyright © 2021 Bq. All rights reserved.
//

import Foundation
import AudioToolbox

// TODO: 补充注释

/*
 static void CASoundAQOutputCallback(
 void *                  inUserData,
 AudioQueueRef           inAQ,
 AudioQueueBufferRef     inBuffer);
 
 static void CASoundAQPropertyListenerProc(
 void *                  inUserData,
 AudioQueueRef           inAQ,
 AudioQueuePropertyID    inID);
 
 static OSStatus CASoundAFReadProc(
 void *        inClientData,
 SInt64        inPosition,
 UInt32    requestCount,
 void *        buffer,
 UInt32 *    actualCount);
 
 static SInt64 CASoundAFGetSizeProc(void *         inClientData);
 */

protocol CASoundDelegate: AnyObject {
    func soundDidFinishPlaying(_ sound: CASound)
}

class CASound {
    enum SoundFormat: String {
        case lpcm8BitInt, lpcm16BitInt, lpcm24BitInt, lpcm32BitFloat
    }
    
    struct SoundLevel {
        var avagePower: Float
        var peakPower: Float
    }
    
    class Impl {
        weak var delegate: CASoundDelegate?
        var data: Data?
        var url: URL?
        
        var asbd: AudioStreamBasicDescription = .init()
        var afid: AudioFileID?
        var queue: AudioQueueRef?
        var readPos: UInt32 = 0
        var readStrartPos: UInt32 = 0
        var volume: Float = 1
        
        var numLoops: Int = -1
        var loopCount: Int = 0
        
        var wasCued: Bool = false
        var wasStarted: Bool = false
        var isPlaying: Bool = false
        var isSkipping: Bool = false
        var isStopping: Bool = true
        var outOfData: Bool = false
        var queueSampleTime: Double = 0
        var mediaSampleTime: Double = 0
        var queueStartSampleTime: Double = 0
        var mediaStartSampleTime: Double = 0
        var mediaEndSampleTime: Double = 1e100
        
        var enableMetering: Bool = false
        var meters: [SoundLevel] = []
        
        // skip mode
        var playSeconds: Double = 0
        // negative for rewind
        var periodLengthSeconds: Double = 0
        
        var aqbuf: [AudioQueueBufferRef?] = []
        var lastBufferEnqueued: AudioQueueBufferRef?
    }
    
    let numberOfAudioQueueBuffers = 4
    
    // TODO: 补充销毁操作
    
    var impl = Impl()
    
    var isPlaying: Bool { impl.isPlaying }
    var sampleRate: Double { impl.asbd.mSampleRate }
    var channelCount: Int { Int(impl.asbd.mChannelsPerFrame) }
    var bitratePerChannel: Double {
        let numChannels = impl.asbd.mSampleRate
        var bitrate: UInt32 = 0
        var propSize: UInt32 = UInt32(MemoryLayout.size(ofValue: bitrate))
        if let afid = impl.afid {
            AudioFileGetProperty(afid, kAudioFilePropertyBitRate, &propSize, &bitrate)
        }
        return Double(bitrate) / numChannels
    }
    var duration: TimeInterval?
    weak var delegate: CASoundDelegate? {
        set { impl.delegate = newValue }
        get { impl.delegate }
    }
    var volume: Float {
        set {
            impl.volume = newValue
            AudioQueueSetParameter(impl.queue!, kAudioQueueParam_Volume, impl.volume)
        }
        get { impl.volume }
    }
    var currentTIme: TimeInterval {
        get {
            var time: TimeInterval
            if impl.wasStarted {
                let queueTime = getQueueTime()
                time = (queueTime + impl.mediaStartSampleTime) / impl.asbd.mSampleRate
            } else {
                time = impl.mediaSampleTime / impl.asbd.mSampleRate
            }
            return time
        }
        
        set {
            let packetPerSeconds: Double = impl.asbd.mSampleRate / Double(impl.asbd.mFramesPerPacket)
            impl.readStrartPos = UInt32((newValue * packetPerSeconds).rounded())
            impl.readPos = impl.readStrartPos
            impl.mediaStartSampleTime = Double(impl.readPos) * Double(impl.asbd.mFramesPerPacket)
            if impl.wasStarted || impl.wasCued {
                if impl.isPlaying {
                    stopQueue()
                } else {
                    AudioQueueReset(impl.queue!)
                }
                impl.wasStarted = false
            }
            play()
        }
    }
    var numberOfLoops: Int {
        get { impl.numLoops }
        set { impl.numLoops = newValue }
    }
    var data: Data? { impl.data }
    var enableMetering: Bool {
        get { impl.enableMetering }
        set {
            impl.enableMetering = newValue
            var iflag: UInt32 = newValue ? 1 : 0
            AudioQueueSetProperty(impl.queue!, kAudioQueueProperty_EnableLevelMetering, &iflag, UInt32(MemoryLayout<UInt32>.size))
        }
    }
    var meters: [SoundLevel] {
        let numChannels = impl.asbd.mChannelsPerFrame
        if impl.queue != nil && impl.enableMetering {
            var proSize: UInt32 = UInt32(MemoryLayout<SoundLevel>.size) * numChannels
            AudioQueueGetProperty(impl.queue!, kAudioQueueProperty_CurrentLevelMeterDB, &impl.meters, &proSize)
        }
        
        return impl.meters
    }
    var formatId: String {
        let fid = impl.asbd.mFormatID
        if fid == kAudioFormatLinearPCM {
            let isFloat = (impl.asbd.mFormatFlags & kAudioFormatFlagIsFloat) == 1
            let bitDepth = impl.asbd.mBitsPerChannel
            if isFloat && bitDepth == 32 {
                return SoundFormat.lpcm32BitFloat.rawValue
            } else {
                switch bitDepth {
                    case 8:
                        return SoundFormat.lpcm8BitInt.rawValue
                    case 16:
                        return SoundFormat.lpcm16BitInt.rawValue
                    case 24:
                        return SoundFormat.lpcm24BitInt.rawValue
                    default:
                        break
                }
            }
            
        }
        let sfid = [
            (fid >> 24) & 255,
            (fid >> 16) & 255,
            (fid >>  8) & 255,
            (fid >>  0) & 255,
            0,
        ]
        
        return String(utf8String: sfid.map { CChar($0) })!
    }
    
    init(url: URL) {
        let err = AudioFileOpenURL(url as CFURL, .readPermission, 0, &impl.afid)
        assert(err == 0)
        impl.url = url
        
        var propSize: UInt32 = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        AudioFileGetProperty(impl.afid!, kAudioFilePropertyDataFormat, &propSize, &impl.asbd)
    }
    
    init(data: Data) {
        impl.data = data
        var inData = self
        let err = AudioFileOpenWithCallbacks(&inData, AFReadProc, nil, AFGetSizeProc, nil, 0, &impl.afid)
        guard err != 0 else { fatalError() }
    }
    
//    typealias DataCallback = (_ sound: CASound, _ userData: Any, _ byteOffset: Int, _ bytesRequested: UInt, _ bytesSupplied: [UInt], _ dataPtr: Any) -> Void
//    init(dataCallBack: DataCallback, userData: Any? = nil) {}
}

// 公共
extension CASound {
    @discardableResult
    func prepareForPlay() -> Bool {
        allocAudioQueue()
        if impl.wasCued { return true }
        if impl.wasCued { return false }
        impl.outOfData = false
        impl.lastBufferEnqueued = nil
        var _self = self
        for i in 0 ..< numberOfAudioQueueBuffers {
            AQOutput(inUserData: &_self, inAQ: impl.queue!, inBuffer: impl.aqbuf[i]!)
        }
        impl.wasCued = true
        
        return false
    }
    
    
    func play() {
        guard !impl.isPlaying else { return }
        
        prepareForPlay()
        if impl.wasStarted {
            let prevQueueStartTime = impl.queueStartSampleTime
            let queueTime = getQueueTime()
            impl.queueStartSampleTime = queueTime
            impl.mediaSampleTime += queueTime - prevQueueStartTime
        } else {
            impl.mediaSampleTime = impl.mediaStartSampleTime
        }
        
        impl.wasStarted = true
        impl.isPlaying = true
        impl.isSkipping = true
        impl.isSkipping = false
        impl.wasCued = false
        impl.loopCount = 0
        AudioQueueSetParameter(impl.queue!, kAudioQueueParam_Volume, impl.volume)
    }
    
    func skipForward(playSeconds: TimeInterval, periodSeconds: TimeInterval) {
        impl.isSkipping = true
        impl.playSeconds = playSeconds
        impl.periodLengthSeconds = -periodSeconds
    }
    
    func pause() {
        guard impl.isPlaying else { return }
        AudioQueuePause(impl.queue!)
        impl.isPlaying = false
        impl.isSkipping = false
    }
    
    func stop() {
        guard impl.wasStarted else { return }
        disposeQueue()
    }
    
    
    
    
}

// 私有
extension CASound {
    @discardableResult
    func allocAudioQueue() -> OSStatus {
        guard impl.queue == nil else { return noErr }
        
        var _self = self
        var err = AudioQueueNewOutput(&impl.asbd, AQOutput, &_self, nil, nil, 0, &impl.queue)
        guard err == 0 else { return err }
        
        if impl.enableMetering {
            var iflag: UInt32 = 1
            AudioQueueSetProperty(impl.queue!, kAudioQueueProperty_EnableLevelMetering, &iflag, UInt32(MemoryLayout<UInt32>.size))
        }
        
        AudioQueueAddPropertyListener(impl.queue!, kAudioQueueProperty_IsRunning, AQPropertyListenerProc, &_self)
        
        for i in 0 ..< numberOfAudioQueueBuffers {
            err = AudioQueueAllocateBuffer(impl.queue!, 65536, &impl.aqbuf[i])
            guard err == 0 else { return err }
        }
        
        return err
    }
    
    @discardableResult
    func stopQueue() -> OSStatus {
        impl.isStopping = true
        OSMemoryBarrier()
        let err = AudioQueueStop(impl.queue!, true)
        impl.wasStarted = false
        impl.isPlaying = false
        impl.isSkipping = false
        impl.isStopping = false
        impl.queueSampleTime = 0
        impl.queueStartSampleTime = 0
        impl.mediaSampleTime = 0
        impl.readPos = impl.readStrartPos
        OSMemoryBarrier()
        return err
    }
    
    @discardableResult
    func disposeQueue() -> OSStatus {
        var _self = self
        AudioQueueRemovePropertyListener(impl.queue!, kAudioQueueProperty_IsRunning, AQPropertyListenerProc, &_self)
        
        impl.isStopping = true
        OSMemoryBarrier()
        let err = AudioQueueDispose(impl.queue!, true)
        impl.queue = nil
        impl.wasStarted = false
        impl.isPlaying = false
        impl.isSkipping = false
        impl.isStopping = false
        impl.queueSampleTime = 0
        impl.queueStartSampleTime = 0
        impl.mediaSampleTime = 0
        impl.readPos = impl.readStrartPos
        OSMemoryBarrier()
        return err
    }
    
    func getQueueTime() -> Double {
        var timestamp = AudioTimeStamp()
        let err = AudioQueueGetCurrentTime(impl.queue!, nil, &timestamp, nil)
        guard err == 0 else { return impl.queueSampleTime }
        impl.queueSampleTime = timestamp.mSampleTime
        return impl.queueStartSampleTime
    }
    
    func queue(_ queue: AudioQueueRef, propertyId: AudioQueuePropertyID) {}
    
    func queue(_ queue: AudioQueueRef, buffer: AudioQueueBufferRef) {
        guard !impl.isStopping else { return }
        
        if impl.outOfData, impl.lastBufferEnqueued == buffer {
            impl.outOfData = false
            impl.lastBufferEnqueued = nil
            if impl.numLoops < 0 {
                impl.readPos = impl.readStrartPos
            } else {
                stopQueue()
                impl.delegate?.soundDidFinishPlaying(self)
                return
            }
        }
        
        var inBuffer = buffer.pointee
        if impl.asbd.mBytesPerPacket != 0 {
            var bytesToFill = inBuffer.mAudioDataBytesCapacity
            var packetsToFill = inBuffer.mAudioDataBytesCapacity / impl.asbd.mBytesPerPacket
            var fillPtr = inBuffer.mAudioData
            var bytesFilled: UInt32 = 0
            while true {
                var ioNumBytes = bytesToFill
                var ioNumPackets = packetsToFill
                let err = AudioFileReadPacketData(impl.afid!, false, &ioNumBytes, nil, Int64(impl.readPos), &ioNumPackets, fillPtr)
                if err != 0 { return }
                
                fillPtr += UnsafeMutableRawPointer.Stride(ioNumBytes)
                bytesFilled += ioNumBytes
                bytesToFill -= ioNumBytes
                packetsToFill -= ioNumPackets
                impl.readPos += ioNumPackets
                
                if packetsToFill != 0 {
                    if impl.numLoops < 0 || impl.loopCount + 1 < impl.numLoops {
                        impl.loopCount += 1
                        if impl.readPos == impl.readStrartPos { break }
                        impl.readPos = impl.readStrartPos
                    } else {
                        impl.outOfData = true
                        impl.mediaEndSampleTime = Double(impl.readPos * impl.asbd.mFramesPerPacket)
                        break
                    }
                } else {
                    break
                }
            }
            
            if bytesFilled != 0 {
                inBuffer.mAudioDataByteSize = bytesFilled
                buffer.pointee = inBuffer
                impl.lastBufferEnqueued = buffer
                AudioQueueEnqueueBuffer(impl.queue!, buffer, 0, nil)
            }
        } else {
            let numPacketDescs: UInt32 = 512
            var descs: [AudioStreamPacketDescription] = []
            var ioNumBytes = inBuffer.mAudioDataBytesCapacity
            var ioNumPackets = numPacketDescs
            var err = AudioFileReadPacketData(impl.afid!, false, &ioNumBytes, &descs, Int64(impl.readPos), &ioNumPackets, inBuffer.mAudioData)
            if err != 0 { return }
            
            impl.readPos += ioNumPackets
            inBuffer.mAudioDataByteSize = ioNumBytes
            buffer.pointee = inBuffer
            
            if ioNumPackets != 0 {
                impl.lastBufferEnqueued = buffer
                err = AudioQueueEnqueueBuffer(impl.queue!, buffer, ioNumPackets, &descs)
            } else {
                impl.outOfData = true
                impl.mediaEndSampleTime = Double(impl.readPos * impl.asbd.mFramesPerPacket)
            }
        }
    }
}

private func AQPropertyListenerProc(inUserData: UnsafeMutableRawPointer?, inAQ: AudioQueueRef, inId: AudioQueuePropertyID) {
    let _self = inUserData!.load(as: CASound.self)
    _self.queue(inAQ, propertyId: inId)
}

private func AQOutput(inUserData: UnsafeMutableRawPointer?, inAQ: AudioQueueRef, inBuffer: AudioQueueBufferRef) {
    let _self = inUserData!.load(as: CASound.self)
    _self.queue(inAQ, buffer: inBuffer)
}


private func AFGetSizeProc(inClientData: UnsafeMutableRawPointer) -> Int64 {
    let _self = inClientData.load(as: CASound.self)
    return Int64(_self.impl.data?.count ?? 0)
}

private func AFReadProc(inClientData: UnsafeMutableRawPointer, inPosition: Int64, requestCount: UInt32, buffer: UnsafeMutableRawPointer, actualCount: UnsafeMutablePointer<UInt32>) -> OSStatus {
    let _self = inClientData.load(as: CASound.self)
    
    guard let data = _self.impl.data else {
        actualCount.pointee = 0
        return kAudio_ParamError
    }
    
    let _requestCount = min(requestCount, UInt32(data.count))
    let _buffer = buffer.bindMemory(to: UInt8.self, capacity: 0)
    data.copyBytes(to: _buffer, from: Int(inPosition) ..< Int(_requestCount))
    
    actualCount.pointee = _requestCount
    
    return noErr
}

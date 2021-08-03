/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 It's a Metronome!
*/

import Foundation
import AVFoundation

struct GlobalConstants {
    static let kBipDurationSeconds: Float32 = 0.020
    static let kTempoChangeResponsivenessSeconds: Float32 = 0.250
}

@objc protocol MetronomeDelegate: class {
    @objc optional func metronomeTicking(_ metronome: Metronome, bar: Int32, beat: Int32)
}

class Metronome : NSObject {
    var engine: AVAudioEngine = AVAudioEngine()
    var player: AVAudioPlayerNode = AVAudioPlayerNode()    // owned by engine
    
    var soundBuffer = [AVAudioPCMBuffer?]()
    
    var bufferNumber: Int = 0
    var bufferSampleRate: Float64 = 0.0
    
    var syncQueue: DispatchQueue? = nil
    
    var tempoBPM: Float32 = 0.0
    var beatNumber: Int32 = 0
    var nextBeatSampleTime: Float64 = 0.0
    var beatsToScheduleAhead: Int32 = 0     // controls responsiveness to tempo changes
    var beatsScheduled: Int32 = 0
    
    var isPlaying: Bool = false
    var playerStarted: Bool = false
    
    weak var delegate: MetronomeDelegate?
    
    override init() {
        super.init()
        // Use two triangle waves which are generate for the metronome bips.
        
        // Create a standard audio format deinterleaved float.
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 2)
        
        // How many audio frames?
        let bipFrames: UInt32 = UInt32(GlobalConstants.kBipDurationSeconds * Float(format.sampleRate))
        
        // Create the PCM buffers.
        soundBuffer.append(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bipFrames))
        soundBuffer.append(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bipFrames))
        
        // Fill in the number of valid sample frames in the buffers (required).
        soundBuffer[0]?.frameLength = bipFrames
        soundBuffer[1]?.frameLength = bipFrames
        
        // Generate the metronme bips, first buffer will be A440 and the second buffer Middle C.
        let wg1 = TriangleWaveGenerator(sampleRate: Float(format.sampleRate))                     // A 440
        let wg2 = TriangleWaveGenerator(sampleRate: Float(format.sampleRate), frequency: 261.6)   // Middle C
        wg1.render(soundBuffer[0]!)
        wg2.render(soundBuffer[1]!)
        
        // Connect player -> output, with the format of the buffers we're playing.
        let output: AVAudioOutputNode = engine.outputNode
        
        engine.attach(player)
        engine.connect(player, to: output, fromBus: 0, toBus: 0, format: format)
        
        bufferSampleRate = format.sampleRate
        
        // Create a serial dispatch queue for synchronizing callbacks.
        syncQueue = DispatchQueue(label: "Metronome")
        
        self.setTempo(120)
    }
    
    deinit {
        self.stop()
        
        engine.detach(player)
        soundBuffer[0] = nil
        soundBuffer[1] = nil
    }
    
    func scheduleBeats() {
        if (!isPlaying) { return }
        
        while (beatsScheduled < beatsToScheduleAhead) {
            // Schedule the beat.
            
            let secondsPerBeat = 60.0 / tempoBPM
            let samplesPerBeat = Float(secondsPerBeat * Float(bufferSampleRate))
            let beatSampleTime: AVAudioFramePosition = AVAudioFramePosition(nextBeatSampleTime)
            let playerBeatTime: AVAudioTime = AVAudioTime(sampleTime: AVAudioFramePosition(beatSampleTime), atRate: bufferSampleRate)
            // This time is relative to the player's start time.
            
            player.scheduleBuffer(soundBuffer[bufferNumber]!, at: playerBeatTime, options: AVAudioPlayerNodeBufferOptions(rawValue: 0), completionHandler: {
                self.syncQueue!.sync() {
                    self.beatsScheduled -= 1
                    self.bufferNumber ^= 1
                    self.scheduleBeats()
                }
            })
            
            beatsScheduled += 1
            
            if (!playerStarted) {
                // We defer the starting of the player so that the first beat will play precisely
                // at player time 0. Having scheduled the first beat, we need the player to be running
                // in order for nodeTimeForPlayerTime to return a non-nil value.
                player.play()
                playerStarted = true
            }
            
            // Schedule the delegate callback (metronomeTicking:bar:beat:) if necessary.
            let callbackBeat = beatNumber
            beatNumber += 1
            if delegate?.metronomeTicking != nil {
                let nodeBeatTime: AVAudioTime = player.nodeTime(forPlayerTime: playerBeatTime)!
                let output: AVAudioIONode = engine.outputNode
                
                //print(" \(playerBeatTime), \(nodeBeatTime), \(output.presentationLatency)")
                let latencyHostTicks: UInt64 = AVAudioTime.hostTime(forSeconds: output.presentationLatency)
                let dispatchTime = DispatchTime(uptimeNanoseconds: nodeBeatTime.hostTime + latencyHostTicks)
                
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: dispatchTime) {
                    if (self.isPlaying) {
                        self.delegate!.metronomeTicking!(self, bar: (callbackBeat / 4) + 1, beat: (callbackBeat % 4) + 1)
                    }
                }
            }
            
            nextBeatSampleTime += Float64(samplesPerBeat)
        }
    }
    
    @discardableResult func start() -> Bool {
        // Start the engine without playing anything yet.
        do {
            try engine.start()
            
            isPlaying = true
            nextBeatSampleTime = 0
            beatNumber = 0
            bufferNumber = 0
            
            self.syncQueue!.sync() {
                self.scheduleBeats()
            }
            
            return true
        } catch {
            print("\(error)")
            return false
        }
    }
    
    func stop() {
        isPlaying = false;
        
        /* Note that pausing or stopping all AVAudioPlayerNode's connected to an engine does
         NOT pause or stop the engine or the underlying hardware.
         
         The engine must be explicitly paused or stopped for the hardware to stop.
        */
        player.stop()
        player.reset()
        
        /* Stop the audio hardware and the engine and release the resources allocated by the prepare method.
         
         Note that pause will also stop the audio hardware and the flow of audio through the engine, but
         will not deallocate the resources allocated by the prepare method.
         
         It is recommended that the engine be paused or stopped (as applicable) when not in use,
         to minimize power consumption.
        */
        engine.stop()
        
        playerStarted = false
    }
    
    func setTempo(_ tempo: Float32) {
        tempoBPM = tempo
        
        let secondsPerBeat: Float32 = 60.0 / tempoBPM
        beatsToScheduleAhead = Int32(GlobalConstants.kTempoChangeResponsivenessSeconds / secondsPerBeat)
        if (beatsToScheduleAhead < 1) { beatsToScheduleAhead = 1 }
    }
    
}

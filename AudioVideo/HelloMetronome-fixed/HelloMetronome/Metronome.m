/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 It's a Metronome!
*/

#import "Metronome.h"
#import "HelloMetronome-Swift.h"

static const float kBipDurationSeconds = 0.020f;
static const float kTempoChangeResponsivenessSeconds = 0.250f;

@interface Metronome () {
    AVAudioEngine     * _engine;
    AVAudioPlayerNode * _player; // owned by engine
    
    AVAudioPCMBuffer * _soundBuf1;
    AVAudioPCMBuffer * _soundBuf2;
    AVAudioPCMBuffer * _soundBuffer[2];
    
    SInt32  _bufferNumber;
    Float64 _bufferSampleRate;
    
    dispatch_queue_t _syncQueue;
    
    Float32 _tempoBPM;
    SInt32  _beatNumber;
    Float64 _nextBeatSampleTime;
    SInt32  _beatsToScheduleAhead; // controls responsiveness to tempo changes
    SInt32  _beatsScheduled;
    
    BOOL    _playing;
    BOOL    _playerStarted;
    
    id<MetronomeDelegate> __weak _delegate;
}
@end

@implementation Metronome

- (instancetype)init {
    return [self init:nil];
}

- (instancetype)init:(NSURL *)fileURL {
    
	if ((self = [super init]) != nil) {
        // Read the sound into memory.
        
        // If there is a file URL, read in the file data and use that for
        // the metronome bip sound buffers being scheduled on the player.
		AVAudioFormat *format;
		
		if (fileURL != nil) {
			AVAudioFile *file = [[AVAudioFile alloc] initForReading: fileURL error: NULL];
			
            format = file.processingFormat;
			
			_soundBuf1 = [[AVAudioPCMBuffer alloc] initWithPCMFormat: format
                                                       frameCapacity: (AVAudioFrameCount)file.length];

			[file readIntoBuffer: _soundBuf1 error:nil];
            
            // Use the same audio buffer for both bips.
            _soundBuffer[0] = _soundBuf1;
            _soundBuffer[1] = _soundBuf1;
		} else {
            // Use two triangle waves which are generate for the metronome bips.
            
            // Create a standard audio format.
			format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:1];
            
            // How many audio frames?
			UInt32 bipFrames = (UInt32)(kBipDurationSeconds * format.sampleRate);
			
            // Create the buffers and get the data pointer for the wave generator.
            _soundBuf1 = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:bipFrames];
            _soundBuf2 = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:bipFrames];
            _soundBuf1.frameLength = bipFrames;
            _soundBuf2.frameLength = bipFrames;
			
            // Generate the metronme bips, first buffer will be A440 and the second buffer Middle C.
            TriangleWaveGenerator *twg1 = [[TriangleWaveGenerator alloc] init];
            TriangleWaveGenerator *twg2 = [[TriangleWaveGenerator alloc] initWithSampleRate:format.sampleRate
                                                                                  frequency:261.6f];
            [twg1 render:_soundBuf1];
            [twg2 render:_soundBuf2];
			
            // Fill in the number of valid sample frames in the buffers (required) and set the playback buffer array.
            _soundBuffer[0] = _soundBuf1;
            _soundBuffer[1] = _soundBuf2;
		}

		// Create the engine, connect player -> output, with the same format as the file we're playing.
		_engine = [[AVAudioEngine alloc] init];
		AVAudioOutputNode *output = _engine.outputNode;
		
		_player = [[AVAudioPlayerNode alloc] init];
		[_engine attachNode: _player];
		[_engine connect: _player to: output fromBus: 0 toBus: 0 format: format];
		
		_bufferSampleRate = format.sampleRate;
		
		// Create a dispatch queue for synchronizing callbacks.
		_syncQueue = dispatch_queue_create("Metronome", DISPATCH_QUEUE_SERIAL);
		
		[self setTempo: 120];
	}
    
	return self;
}

- (void)dealloc {
    [self stop];
    
    [_engine detachNode:_player];
    
    _player = nil;
    _engine = nil;
    _soundBuf1 = nil;
    _soundBuf2 = nil;
}

// The caller is responsible for calling this method on _syncQueue.
- (void)scheduleBeats {
	if (!_playing) return;
	
	while (_beatsScheduled < _beatsToScheduleAhead) {
		// Schedule the beat.
        
		float secondsPerBeat = 60.0f / _tempoBPM;
		float samplesPerBeat = (float)(secondsPerBeat * _bufferSampleRate);
		AVAudioFramePosition beatSampleTime = (AVAudioFramePosition)_nextBeatSampleTime;
		AVAudioTime *playerBeatTime = [AVAudioTime timeWithSampleTime: beatSampleTime atRate: _bufferSampleRate];
			// This time is relative to the player's start time.

        [_player scheduleBuffer:_soundBuffer[_bufferNumber] atTime:playerBeatTime options:0 completionHandler:^{
            dispatch_sync(_syncQueue, ^{
				_beatsScheduled -= 1;
                _bufferNumber ^= 1;
				[self scheduleBeats];
			});
		}];
		
        _beatsScheduled += 1;
		
        if (!_playerStarted) {
			// We defer the starting of the player so that the first beat will play precisely
			// at player time 0. Having scheduled the first beat, we need the player to be running
			// in order for nodeTimeForPlayerTime to return a non-nil value.
			[_player play];
			_playerStarted = YES;
		}
		
		// Schedule the delegate callback (metronomeTicking:bar:beat:) if necessary.
		int callbackBeat = _beatNumber++;
		if (_delegate && [_delegate respondsToSelector: @selector(metronomeTicking:bar:beat:)]) {
			AVAudioTime *nodeBeatTime = [_player nodeTimeForPlayerTime: playerBeatTime];
			
            AVAudioIONode *output = _engine.outputNode;
			
			//NSLog(@"%@ %@ %.6f", playerBeatTime, nodeBeatTime, output.presentationLatency);
			uint64_t latencyHostTicks = [AVAudioTime hostTimeForSeconds: output.presentationLatency];
			dispatch_after(dispatch_time(nodeBeatTime.hostTime + latencyHostTicks, 0), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
				// hardcoded to 4/4 meter
				if (_playing)
					[_delegate metronomeTicking: self bar: (callbackBeat / 4) + 1 beat: (callbackBeat % 4) + 1];
			});
		}
        
		_nextBeatSampleTime += samplesPerBeat;
	}
}

- (BOOL)start {
	// Start the engine without playing anything yet.
	if (![_engine startAndReturnError:nil]) return NO;

	_playing = YES;
	_nextBeatSampleTime = 0;
	_beatNumber = 0;
	
	dispatch_sync(_syncQueue, ^{
		[self scheduleBeats];
	});
	
	return YES;
}

- (void)stop {
	_playing = NO;
    
    /* Note that pausing or stopping all AVAudioPlayerNode's connected to an engine does
       NOT pause or stop the engine or the underlying hardware.
     
       The engine must be explicitly paused or stopped for the hardware to stop.
    */
	[_player stop];
	[_player reset];
    
    /* Stop the audio hardware and the engine and release the resources allocated by the prepare method.
     
       Note that pause will also stop the audio hardware and the flow of audio through the engine, but
       will not deallocate the resources allocated by the prepare method.
       
       It is recommended that the engine be paused or stopped (as applicable) when not in use,
       to minimize power consumption.
    */
	[_engine stop];

	_playerStarted = NO;
}

- (void)setTempo: (float)tempo {
	_tempoBPM = tempo;

	float secondsPerBeat = 60.0f / _tempoBPM;
	_beatsToScheduleAhead = (SInt32)(kTempoChangeResponsivenessSeconds / secondsPerBeat);
	if (_beatsToScheduleAhead < 1) _beatsToScheduleAhead = 1;
}

@end
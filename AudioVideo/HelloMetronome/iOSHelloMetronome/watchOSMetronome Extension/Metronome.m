/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 It's a Metronome!
*/

#import "Metronome.h"
#import "watchOSMetronome_Extension-Swift.h"

static const float      kTempoDefault   = 120;
static const float      kTempoMin       = 40;
static const float      kTempoMax       = 208;

static const NSInteger  kMeterDefault   = 4;
static const NSInteger  kMeterMin       = 2;
static const NSInteger  kMeterMax       = 8;

static const NSInteger  kNumDivisions   = 4;
static const NSInteger  kDivisions[4]   = { 2, 4, 8, 16 };

static const float      kBipDurationSeconds = 0.020f;
static const float      kTempoChangeResponsivenessSeconds = 0.250f;

@interface Metronome() {
    AVAudioEngine*      _audioEngine;
    AVAudioPlayerNode*  _audioPlayerNode;
    AVAudioFormat*      _audioFormat;
    AVAudioPCMBuffer*   _downbeatBuffer;
    AVAudioPCMBuffer*   _upbeatBuffer;
    
    Float32             _timeInterval_s;
    NSInteger           _divisionIndex;
    
    dispatch_queue_t    _syncQueue;
    
    SInt32               _beatsToScheduleAhead; // controls responsiveness to tempo changes
    SInt32              _beatsScheduled;
    Float64             _nextBeatSampleTime;

    BOOL                _playerStarted;
}
@end

@implementation Metronome

- (id)init {
    
    self = [super init];
    
    if (self) {
        
        [self initializeDefaults];
        
        // Start Audio Session and Get Sample Rate
        float sampleRate = [[AVAudioSession sharedInstance] sampleRate];
        
        // Create a standard audio format.
        _audioFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels: 1];
        
        // Initialize AVAudioPCM Buffers
        unsigned bipFrames = (unsigned)(kBipDurationSeconds * _audioFormat.sampleRate);
        _downbeatBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_audioFormat frameCapacity:bipFrames];
        _upbeatBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_audioFormat frameCapacity:bipFrames];
        
        // Fill Number of Valid Sample Frames (required).
        _downbeatBuffer.frameLength = bipFrames;
        _upbeatBuffer.frameLength = bipFrames;
        
        // Generate Metronome Bips
        TriangleWaveGenerator *twg1 = [[TriangleWaveGenerator alloc] initWithSampleRate:_audioFormat.sampleRate frequency:660.0];
        TriangleWaveGenerator *twg2 = [[TriangleWaveGenerator alloc] initWithSampleRate:_audioFormat.sampleRate];
        [twg1 render:_downbeatBuffer];
        [twg2 render:_upbeatBuffer];
        
        // Create AVAudioEngine, Connect Player -> Output
        _audioEngine = [[AVAudioEngine alloc] init];
        _audioPlayerNode = [[AVAudioPlayerNode alloc] init];
        AVAudioOutputNode* outputNode = _audioEngine.outputNode;
        
        [_audioEngine attachNode:_audioPlayerNode];
        [_audioEngine connect:_audioPlayerNode to:outputNode fromBus:0 toBus:0 format:_audioFormat];
        
        // Create Dispatch Queue for Synchronizing Tasks
        _syncQueue = dispatch_queue_create("com.apple.audio.metronome", DISPATCH_QUEUE_SERIAL);
    }
    
    return self;
}

#pragma mark - Singleton

+ (instancetype)sharedInstance {
    
    static Metronome* sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[Metronome alloc] init];
    });
    
    return sharedInstance;
}

#pragma mark - Public Methods

- (BOOL)startClock {
    
    if (![_audioEngine startAndReturnError:nil]) {
        return NO;
    }
    
    _isRunning = YES;
    
    _nextBeatSampleTime = 0;
    _currentTick = 0;
    
    dispatch_async(_syncQueue, ^{
        [self scheduleBeat];
    });
    
    return YES;
}

- (void)stopClock {
    
    _isRunning = NO;
    
    /* Note that pausing or stopping all AVAudioPlayerNode's connected to an engine does
     NOT pause or stop the engine or the underlying hardware.
     
     The engine must be explicitly paused or stopped for the hardware to stop.
    */
    [_audioPlayerNode stop];
    [_audioPlayerNode reset];
    
    /* Stop the audio hardware and the engine and release the resources allocated by the prepare method.
     
     Note that pause will also stop the audio hardware and the flow of audio through the engine, but
     will not deallocate the resources allocated by the prepare method.
     
     It is recommended that the engine be paused or stopped (as applicable) when not in use,
     to minimize power consumption.
    */
    [_audioEngine stop];
    [_audioEngine reset];
    
    _playerStarted = NO;
}

// called if we recieved a AVAudioSessionMediaServicesWereResetNotification
- (void)reset {
    
    // dispose of the player and engine
    _audioEngine = nil;
    _audioPlayerNode = nil;
    
    // reset defaults
    [self initializeDefaults];
    
    // create AVAudioEngine, connect Player -> Output
    _audioEngine = [[AVAudioEngine alloc] init];
    _audioPlayerNode = [[AVAudioPlayerNode alloc] init];
    AVAudioOutputNode* outputNode = [_audioEngine outputNode];
    
    [_audioEngine attachNode:_audioPlayerNode];
    [_audioEngine connect:_audioPlayerNode to:outputNode fromBus:0 toBus:0 format:_audioFormat];
}

- (void)incrementTempo:(NSInteger)increment {
    
    _tempo += increment;
    
    if (_tempo > kTempoMax) {
        _tempo = kTempoMax;
    } else if (_tempo < kTempoMin) {
        _tempo = kTempoMin;
    }
    
    [self updateTimeInterval];
}

- (void)incrementMeter:(NSInteger)increment {
    
    _meter += increment;
    
    if (_meter < kMeterMin) {
        _meter = kMeterMin;
    } else if (_meter > kMeterMax) {
        _meter = kMeterMax;
    }
    
    _currentTick = 0;
}

- (void)incrementDivisionIndex:(NSInteger)increment {
    
    BOOL wasRunning = _isRunning;
    
    if (wasRunning) {
        [self stopClock];
    }
    
    _divisionIndex += increment;
    
    if (_divisionIndex < 0) {
        _divisionIndex = 0;
    } else if (_divisionIndex > kNumDivisions-1) {
        _divisionIndex = kNumDivisions-1;
    }
    
    _division = kDivisions[_divisionIndex];
    [self updateTimeInterval];
    
    if (wasRunning) {
        [self startClock];
    }
}

#pragma mark - Private Methods

- (void)initializeDefaults {
    
    _tempo = kTempoDefault;
    _meter = kMeterDefault;
    _timeInterval_s = 0;
    _divisionIndex = 1;
    _division = kDivisions[_divisionIndex];
    _currentTick = 0;
    _beatsScheduled = 0;
    
    [self updateTimeInterval];
    
    _isRunning = NO;
    _playerStarted  = NO;
}

- (void)scheduleBeat {
    
    if (!_isRunning) return;

    while (_beatsScheduled < _beatsToScheduleAhead) {
        
        float samplesPerBeat = (float)(_timeInterval_s * _audioFormat.sampleRate);
        AVAudioFramePosition beatSampleTime = (AVAudioFramePosition)_nextBeatSampleTime;
        AVAudioTime* playerBeatTime = [AVAudioTime timeWithSampleTime:beatSampleTime atRate:_audioFormat.sampleRate];
        
        AVAudioPCMBuffer* bufferToPlay;
        if (_currentTick == 0) {
            bufferToPlay = _downbeatBuffer;
        } else {
            bufferToPlay = _upbeatBuffer;
        }
        
        [_audioPlayerNode scheduleBuffer:bufferToPlay atTime:playerBeatTime options:0 completionHandler:^{
            dispatch_sync(_syncQueue, ^{
                _beatsScheduled -= 1;
                [self scheduleBeat];
            });
        }];
        
        _beatsScheduled += 1;
        
        if (!_playerStarted) {
            // We defer the starting of the player so that the first beat will play precisely
            // at player time 0. Having scheduled the first beat, we need the player to be running
            // in order for nodeTimeForPlayerTime to return a non-nil value.
            [_audioPlayerNode play];
            _playerStarted = YES;
        }
        
        NSInteger callbackBeat = _currentTick;
        NSInteger callbackMeter = _meter;
        
        if ([self.delegate respondsToSelector:@selector(metronomeTick:)]) {
            AVAudioTime* nodeBeatTime = [_audioPlayerNode nodeTimeForPlayerTime: playerBeatTime];
            AVAudioIONode *output = _audioEngine.outputNode;
            
            uint64_t latencyHostTicks = [AVAudioTime hostTimeForSeconds: output.presentationLatency];
            dispatch_after(dispatch_time(nodeBeatTime.hostTime + latencyHostTicks, 0), dispatch_get_main_queue(), ^{
                // if meter has changed since dispatch, callbackBeat will be invalid so just return.
                if (_meter != callbackMeter) return;
                
                // if engine is running update the UI.
                if (_isRunning) {
                    [_delegate metronomeTick:callbackBeat];
                }
            });
        }
        
        _currentTick = (_currentTick + 1) % _meter;
        _nextBeatSampleTime += samplesPerBeat;
    }
}

- (void)updateTimeInterval {
    
    _timeInterval_s = (60.0f / _tempo) * (4.0f / kDivisions[_divisionIndex]);
    
    _beatsToScheduleAhead = (int)(kTempoChangeResponsivenessSeconds / _timeInterval_s);
    if (_beatsToScheduleAhead < 1) _beatsToScheduleAhead = 1;
}

@end

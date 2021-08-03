/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    AudioEngine is the main controller class that manages the following:
                    AVAudioEngine           *_engine;
                    AVAudioEnvironmentNode  *_environment;
                    AVAudioPCMBuffer        *_collisionSoundBuffer;
                    NSMutableArray          *_collisionPlayerArray;
                    AVAudioPlayerNode       *_launchSoundPlayer;
                    AVAudioPCMBuffer        *_launchSoundBuffer;
                    bool                    _multichannelOutputEnabled;
    
                 It creates and connects all the nodes, loads the buffers as well as controls the AVAudioEngine object itself.
*/

#import "AudioEngine.h"

@interface AudioEngine () {
    AVAudioEngine                       *_engine;
    AVAudioEnvironmentNode              *_environment;
    AVAudioPCMBuffer                    *_collisionSoundBuffer;
    NSMutableArray <AVAudioPlayerNode*> *_collisionPlayerArray;
    AVAudioPlayerNode                   *_launchSoundPlayer;
    AVAudioPCMBuffer                    *_launchSoundBuffer;
    bool                                _multichannelOutputEnabled;
    
    // mananging session and configuration changes
    BOOL                    _isSessionInterrupted;
    BOOL                    _isConfigChangePending;
}
@end

@implementation AudioEngine

- (AVAudioPCMBuffer *)loadSoundIntoBuffer:(NSString *)filename
{
    NSError *error;
    BOOL success = NO;
    
    // load the collision sound into a buffer
    NSURL *soundFileURL = [NSURL URLWithString:[[NSBundle mainBundle] pathForResource:filename ofType:@"caf"]];
    NSAssert(soundFileURL, @"Error creating URL to sound file");
    
    AVAudioFile *soundFile = [[AVAudioFile alloc] initForReading:soundFileURL commonFormat:AVAudioPCMFormatFloat32 interleaved:NO error:&error];
    NSAssert(soundFile != nil, @"Error creating soundFile, %@", error.localizedDescription);
    
    AVAudioPCMBuffer *outputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:soundFile.processingFormat frameCapacity:(AVAudioFrameCount)soundFile.length];
    success = [soundFile readIntoBuffer:outputBuffer error:&error];
    NSAssert(success, @"Error reading file into buffer, %@", error.localizedDescription);
    
    return outputBuffer;
}

- (BOOL)isRunning
{
    return _engine.isRunning;
}

- (instancetype)init
{
    if (self = [super init]) {
        
#if TARGET_OS_IOS || TARGET_OS_SIMULATOR
        [self initAVAudioSession];
#endif
        _isSessionInterrupted = NO;
        _isConfigChangePending = NO;
        
        _engine = [[AVAudioEngine alloc] init];
        _environment = [[AVAudioEnvironmentNode alloc] init];
        [_engine attachNode:_environment];
        
        // array that keeps track of all the collision players
        _collisionPlayerArray = [[NSMutableArray alloc] init];
        
        // load the collision sound into a buffer
        _collisionSoundBuffer = [self loadSoundIntoBuffer:@"bounce"];
        
        // load the launch sound into a buffer
        _launchSoundBuffer = [self loadSoundIntoBuffer:@"launchSound"];
        
        // setup the launch sound player
        _launchSoundPlayer = [[AVAudioPlayerNode alloc] init];
        [_engine attachNode:_launchSoundPlayer];
        _launchSoundPlayer.volume = 0.35;
        
        // wire everything up
        [self makeEngineConnections];
        
        // sign up for notifications about changes in output configuration
        [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioEngineConfigurationChangeNotification object:_engine queue:nil usingBlock: ^(NSNotification *note) {
            
            // if we've received this notification, something has changed and the engine has been stopped
            // re-wire all the connections and start the engine
            
            _isConfigChangePending = YES;
            
            if (!_isSessionInterrupted) {
                NSLog(@"Received a %@ notification!", AVAudioEngineConfigurationChangeNotification);
                NSLog(@"Re-wiring connections and starting once again");
                [self makeEngineConnections];
                [self startEngine];
            }
            else {
                NSLog(@"Session is interrupted, deferring changes");
            }
            
            // post notification
            if ([self.delegate respondsToSelector:@selector(engineConfigurationHasChanged)]) {
                [self.delegate engineConfigurationHasChanged];
            }
        }];
        
        // turn on the environment reverb
        _environment.reverbParameters.enable = YES;
        _environment.reverbParameters.level = -20.0;
        [_environment.reverbParameters loadFactoryReverbPreset:AVAudioUnitReverbPresetLargeHall];
 
        // we're ready to start rendering so start the engine
        [self startEngine];
    }
    return self;
}

- (void)makeEngineConnections
{
    [_engine connect:_launchSoundPlayer to:_environment format:_launchSoundBuffer.format];
    [_engine connect:_environment to:_engine.outputNode format:[self constructOutputConnectionFormatForEnvironment]];
    
    // if we're connecting with a multichannel format, we need to pick a multichannel rendering algorithm
    AVAudio3DMixingRenderingAlgorithm renderingAlgo = _multichannelOutputEnabled ? AVAudio3DMixingRenderingAlgorithmSoundField : AVAudio3DMixingRenderingAlgorithmEqualPowerPanning;
    
    // if we already have a pool of collision players, connect all of them to the environment
    for (int i = 0; i < _collisionPlayerArray.count; i++) {
        [_engine connect:_collisionPlayerArray[i] to:_environment format:_collisionSoundBuffer.format];
        _collisionPlayerArray[i].renderingAlgorithm = renderingAlgo;
    }
}

- (void)startEngine
{
    NSError *error;
    BOOL success = NO;
    success = [_engine startAndReturnError:&error];
    NSAssert(success, @"Error starting engine, %@", error.localizedDescription);
}

- (AVAudioFormat *)constructOutputConnectionFormatForEnvironment
{
    AVAudioFormat *environmentOutputConnectionFormat = nil;
    AVAudioChannelCount numHardwareOutputChannels = [_engine.outputNode outputFormatForBus:0].channelCount;
    const double hardwareSampleRate = [_engine.outputNode outputFormatForBus:0].sampleRate;
    
    // if we're connected to multichannel hardware, create a compatible multichannel format for the environment node
    if (numHardwareOutputChannels > 2 && numHardwareOutputChannels != 3) {
        if (numHardwareOutputChannels > 8) numHardwareOutputChannels = 8;
        
        // find an AudioChannelLayoutTag that the environment node knows how to render to
        // this is documented in AVAudioEnvironmentNode.h
        AudioChannelLayoutTag environmentOutputLayoutTag;
        switch (numHardwareOutputChannels) {
            case 4:
                environmentOutputLayoutTag = kAudioChannelLayoutTag_AudioUnit_4;
                break;
                
            case 5:
                environmentOutputLayoutTag = kAudioChannelLayoutTag_AudioUnit_5_0;
                break;
                
            case 6:
                environmentOutputLayoutTag = kAudioChannelLayoutTag_AudioUnit_6_0;
                break;
                
            case 7:
                environmentOutputLayoutTag = kAudioChannelLayoutTag_AudioUnit_7_0;
                break;
                
            case 8:
                environmentOutputLayoutTag = kAudioChannelLayoutTag_AudioUnit_8;
                break;
                
            default:
                // based on our logic, we shouldn't hit this case
                environmentOutputLayoutTag = kAudioChannelLayoutTag_Stereo;
                break;
        }
        
        // using that layout tag, now construct a format
        AVAudioChannelLayout *environmentOutputChannelLayout = [[AVAudioChannelLayout alloc] initWithLayoutTag:environmentOutputLayoutTag];
        environmentOutputConnectionFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:hardwareSampleRate channelLayout:environmentOutputChannelLayout];
        _multichannelOutputEnabled = true;
    }
    else {
        // stereo rendering format, this is the common case
        environmentOutputConnectionFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:hardwareSampleRate channels:2];
        _multichannelOutputEnabled = false;
    }
    
    return environmentOutputConnectionFormat;
}

- (void)createPlayerForSCNNode:(SCNNode *)node
{
    // create a new player and connect it to the environment node
    AVAudioPlayerNode *newPlayer = [[AVAudioPlayerNode alloc] init];
    [_engine attachNode:newPlayer];
    [_engine connect:newPlayer to:_environment format:_collisionSoundBuffer.format];
    [_collisionPlayerArray insertObject:newPlayer atIndex:[node.name integerValue]];
    
    // pick a rendering algorithm based on the rendering format
    AVAudio3DMixingRenderingAlgorithm renderingAlgo = _multichannelOutputEnabled ? AVAudio3DMixingRenderingAlgorithmSoundField : AVAudio3DMixingRenderingAlgorithmEqualPowerPanning;
    newPlayer.renderingAlgorithm = renderingAlgo;
    
    // turn up the reverb blend for this player
    newPlayer.reverbBlend = 0.3;
}

- (void)destroyPlayerForSCNNode:(SCNNode *)node
{
    NSInteger playerIndex = [node.name integerValue];
    AVAudioPlayerNode *player = _collisionPlayerArray[playerIndex];
    [player stop];
    [_engine disconnectNodeOutput:player];
}

- (void)playCollisionSoundForSCNNode:(SCNNode *)node position:(AVAudio3DPoint)position impulse:(float)impulse
{
    if (_engine.isRunning) {
        NSInteger playerIndex = [node.name integerValue];
        AVAudioPlayerNode *player = _collisionPlayerArray[playerIndex];
        [player scheduleBuffer:_collisionSoundBuffer atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:nil];
        player.position = position;
        player.volume = [self calculateVolumeForImpulse:impulse];
        player.rate = [self calculatePlaybackRateForImpulse:impulse];
        [player play];
    }
}

- (void)playLaunchSoundAtPosition:(AVAudio3DPoint)position completionHandler:(AVAudioNodeCompletionHandler)completionHandler
{
    if (_engine.isRunning) {
        _launchSoundPlayer.position = position;
        [_launchSoundPlayer scheduleBuffer:_launchSoundBuffer completionHandler:completionHandler];
        [_launchSoundPlayer play];
    }
}

- (float)calculateVolumeForImpulse:(float)impulse
{
    // Simple mapping of impulse to volume
    
    const float volMinDB = -20.;
    const float impulseMax = 12.;
    
    if (impulse > impulseMax) impulse = impulseMax;
    float volDB = (impulse / impulseMax * -volMinDB) + volMinDB;
    return powf(10, (volDB / 20));
}

- (float)calculatePlaybackRateForImpulse:(float)impulse
{
    // Simple mapping of impulse to playback rate (pitch)
    // This gives the effect of the pitch dropping as the impulse reduces
    
    const float rateMax = 1.2;
    const float rateMin = 0.95;
    const float rateRange = rateMax - rateMin;
    const float impulseMax = 12.;
    const float impulseMin = 0.6;
    const float impulseRange = impulseMax - impulseMin;
    
    if (impulse > impulseMax)   impulse = impulseMax;
    if (impulse < impulseMin)   impulse = impulseMin;
    
    return (((impulse - impulseMin) / impulseRange) * rateRange) + rateMin;
}

- (void)updateListenerPosition:(AVAudio3DPoint)position
{
    _environment.listenerPosition = position;
}

- (AVAudio3DPoint)listenerPosition
{
    return _environment.listenerPosition;
}

- (void)updateListenerOrientation:(AVAudio3DAngularOrientation)orientation
{
    _environment.listenerAngularOrientation = orientation;
}

- (AVAudio3DAngularOrientation)listenerAngularOrientation
{
    return _environment.listenerAngularOrientation;
}

#pragma mark AVAudioSession

#if TARGET_OS_IOS || TARGET_OS_SIMULATOR
- (void)initAVAudioSession
{
    NSError *error;
    
    // Configure the audio session
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];

    // set the session category
    bool success = [sessionInstance setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (!success) NSLog(@"Error setting AVAudioSession category! %@\n", [error localizedDescription]);
     
    const NSInteger desiredNumChannels = 8; // for 7.1 rendering
    const NSInteger maxChannels = sessionInstance.maximumOutputNumberOfChannels;
    if (maxChannels >= desiredNumChannels) {
        success = [sessionInstance setPreferredOutputNumberOfChannels:desiredNumChannels error:&error];
        if (!success) NSLog(@"Error setting PreferredOuputNumberOfChannels! %@", [error localizedDescription]);
    }
    
    
    // add interruption handler
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:sessionInstance];
    
    // we don't do anything special in the route change notification
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleRouteChange:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:sessionInstance];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMediaServicesReset:)
                                                 name:AVAudioSessionMediaServicesWereResetNotification
                                               object:sessionInstance];
    
    // activate the audio session
    success = [sessionInstance setActive:YES error:&error];
    if (!success) NSLog(@"Error setting session active! %@\n", [error localizedDescription]);
}

- (void)handleInterruption:(NSNotification *)notification
{
    UInt8 theInterruptionType = [[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] intValue];
    
    NSLog(@"Session interrupted > --- %s ---\n", theInterruptionType == AVAudioSessionInterruptionTypeBegan ? "Begin Interruption" : "End Interruption");
    
    if (theInterruptionType == AVAudioSessionInterruptionTypeBegan) {
        _isSessionInterrupted = YES;
        
        //stop the playback of the nodes
        for (int i = 0; i < _collisionPlayerArray.count; i++)
             [[_collisionPlayerArray objectAtIndex:i] stop];
        
        if ([self.delegate respondsToSelector:@selector(engineWasInterrupted)]) {
            [self.delegate engineWasInterrupted];
        }
        
    }
    if (theInterruptionType == AVAudioSessionInterruptionTypeEnded) {
        // make sure to activate the session
        NSError *error;
        bool success = [[AVAudioSession sharedInstance] setActive:YES error:&error];
        if (!success)
            NSLog(@"AVAudioSession set active failed with error: %@", [error localizedDescription]);
        else {
            _isSessionInterrupted = NO;
            if (_isConfigChangePending) {
                //there is a pending config changed notification
                NSLog(@"Responding to earlier engine config changed notification. Re-wiring connections and starting once again");
                [self makeEngineConnections];
                [self startEngine];
                
                _isConfigChangePending = NO;
            }
            else {
                // start the engine once again
                [self startEngine];
            }
        }
    }
}

- (void)handleRouteChange:(NSNotification *)notification
{
    UInt8 reasonValue = [[notification.userInfo valueForKey:AVAudioSessionRouteChangeReasonKey] intValue];
    AVAudioSessionRouteDescription *routeDescription = [notification.userInfo valueForKey:AVAudioSessionRouteChangePreviousRouteKey];
    
    NSLog(@"Route change:");
    switch (reasonValue) {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            NSLog(@"     NewDeviceAvailable");
            break;
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            NSLog(@"     OldDeviceUnavailable");
            break;
        case AVAudioSessionRouteChangeReasonCategoryChange:
            NSLog(@"     CategoryChange");
            NSLog(@"     New Category: %@", [[AVAudioSession sharedInstance] category]);
            break;
        case AVAudioSessionRouteChangeReasonOverride:
            NSLog(@"     Override");
            break;
        case AVAudioSessionRouteChangeReasonWakeFromSleep:
            NSLog(@"     WakeFromSleep");
            break;
        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
            NSLog(@"     NoSuitableRouteForCategory");
            break;
        default:
            NSLog(@"     ReasonUnknown");
    }
    
    NSLog(@"Previous route:\n");
    NSLog(@"%@", routeDescription);
}

- (void)handleMediaServicesReset:(NSNotification *)notification
{
    // if we've received this notification, the media server has been reset
    // re-wire all the connections and start the engine
    NSLog(@"Media services have been reset!");
    NSLog(@"Re-wiring connections and starting once again");
    
    [self initAVAudioSession];
    [self createEngineAndAttachNodes];
    [self makeEngineConnections];
    [self startEngine];
    
    //notify the delegate
    if ([self.delegate respondsToSelector:@selector(engineConfigurationHasChanged)]) {
        [self.delegate engineConfigurationHasChanged];
    }
}

- (void)createEngineAndAttachNodes
{
    _engine = [[AVAudioEngine alloc] init];
    
    [_engine attachNode:_environment];
    [_engine attachNode:_launchSoundPlayer];
    
    for (int i = 0; i < _collisionPlayerArray.count; i++)
        [_engine attachNode:[_collisionPlayerArray objectAtIndex:i]];
    
}

#endif


@end

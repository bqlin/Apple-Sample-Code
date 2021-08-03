/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    GameView
*/

@import SceneKit;

@class AudioEngine;

@interface GameView : SCNView

@property (strong) AudioEngine *gameAudioEngine;

@end

/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Metronome class header file
*/

#import <AVFoundation/AVFoundation.h>

@protocol MetronomeDelegate;

@interface Metronome : NSObject {
}

- (nullable instancetype)init:(NSURL * _Nullable)fileURL NS_DESIGNATED_INITIALIZER;
- (BOOL)start;
- (void)stop;
- (void)setTempo:(Float32)tempo;

@property(weak, nullable) id<MetronomeDelegate> delegate;

@end

@protocol MetronomeDelegate <NSObject>
@optional 
- (void)metronomeTicking:(Metronome * _Nonnull)metronome bar:(SInt32)bar beat:(SInt32)beat;
@end

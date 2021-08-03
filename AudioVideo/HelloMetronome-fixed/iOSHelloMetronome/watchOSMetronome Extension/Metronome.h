/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Metronome class header file
*/

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@protocol MetronomeDelegate <NSObject>
@optional
- (void)metronomeTick:(NSInteger)currentTick;
@end

@interface Metronome : NSObject

+ (nullable instancetype)sharedInstance;

- (BOOL)startClock;
- (void)stopClock;
- (void)reset;

- (void)incrementTempo:(NSInteger)increment;
- (void)incrementMeter:(NSInteger)increment;
- (void)incrementDivisionIndex:(NSInteger)increment;

@property (nonatomic, readonly) NSInteger   tempo;
@property (nonatomic, readonly) NSUInteger  meter;
@property (nonatomic, readonly) NSInteger   division;
@property (nonatomic, readonly) NSInteger   currentTick;
@property (nonatomic, readonly) BOOL        isRunning;
@property (nonatomic, weak, nullable) id<MetronomeDelegate> delegate;

@end

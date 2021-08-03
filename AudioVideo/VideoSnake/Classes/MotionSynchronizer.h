/*
 <codex>
 <abstract>Synchronizes motion samples with media samples</abstract>
 </codex>
 */

#import <Foundation/Foundation.h>
#import <CoreMedia/CMSampleBuffer.h>
#import <CoreMedia/CMSync.h>

@class CMDeviceMotion;

@protocol MotionSynchronizationDelegate;

@interface MotionSynchronizer : NSObject

@property(nonatomic) int motionRate;
@property(nonatomic, retain) __attribute__((NSObject)) CMClockRef sampleBufferClock; // safe to update if you aren't concurrently calling appendSampleBufferForSynchronization:

- (void)start;
- (void)stop;

- (void)appendSampleBufferForSynchronization:(CMSampleBufferRef)sampleBuffer;
- (void)setSynchronizedSampleBufferDelegate:(id<MotionSynchronizationDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue;

@end

@protocol MotionSynchronizationDelegate <NSObject>

@required
- (void)motionSynchronizer:(MotionSynchronizer *)synchronizer didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer withMotion:(CMDeviceMotion*)motion;

@end

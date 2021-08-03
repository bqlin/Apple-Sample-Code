/*
 <codex>
 <abstract>The class that creates and manages the AVCaptureSession</abstract>
 </codex>
 */

#import <AVFoundation/AVFoundation.h>
#import <CoreMotion/CoreMotion.h>

@protocol VideoSnakeSessionManagerDelegate;

@interface VideoSnakeSessionManager : NSObject 

- (void)setDelegate:(id<VideoSnakeSessionManagerDelegate>)delegate callbackQueue:(dispatch_queue_t)delegateCallbackQueue; // delegate is weak referenced

// Consider renaming this class VideoSnakeCapturePipeline
// These methods are synchronous
- (void)startRunning;
- (void)stopRunning;

// Must be running before starting recording
// These methods are asynchronous, see the recording delegate callbacks
- (void)startRecording;
- (void)stopRecording;

@property (readwrite) BOOL renderingEnabled; // When set to false the GPU will not be used after the setRenderingEnabled: call returns.

@property (readwrite) AVCaptureVideoOrientation recordingOrientation; // client can set the orientation for the recorded movie

- (CGAffineTransform)transformFromVideoBufferOrientationToOrientation:(AVCaptureVideoOrientation)orientation withAutoMirroring:(BOOL)mirroring; // only valid after startRunning has been called

// Stats
@property (readonly) float videoFrameRate;
@property (readonly) CMVideoDimensions videoDimensions;

@end

@protocol VideoSnakeSessionManagerDelegate <NSObject>
@required

- (void)sessionManager:(VideoSnakeSessionManager *)sessionManager didStopRunningWithError:(NSError *)error;

// Preview
- (void)sessionManager:(VideoSnakeSessionManager *)sessionManager previewPixelBufferReadyForDisplay:(CVPixelBufferRef)previewPixelBuffer;
- (void)sessionManagerDidRunOutOfPreviewBuffers:(VideoSnakeSessionManager *)sessionManager;

// Recording
- (void)sessionManagerRecordingDidStart:(VideoSnakeSessionManager *)manager;
- (void)sessionManager:(VideoSnakeSessionManager *)manager recordingDidFailWithError:(NSError *)error; // Can happen at any point after a startRecording call, for example: startRecording->didFail (without a didStart), willStop->didFail (without a didStop)
- (void)sessionManagerRecordingWillStop:(VideoSnakeSessionManager *)manager;
- (void)sessionManagerRecordingDidStop:(VideoSnakeSessionManager *)manager;

@end

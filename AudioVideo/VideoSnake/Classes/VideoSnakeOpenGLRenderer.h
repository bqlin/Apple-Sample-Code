/*
 <codex>
 <abstract>The VideoSnake OpenGL effect renderer.</abstract>
 </codex>
 */
#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMotion/CoreMotion.h>

@interface VideoSnakeOpenGLRenderer : NSObject

- (void)prepareWithOutputDimensions:(CMVideoDimensions)outputDimensions retainedBufferCountHint:(size_t)retainedBufferCountHint;
- (void)reset;

- (CVPixelBufferRef)copyRenderedPixelBuffer:(CVPixelBufferRef)pixelBuffer motion:(CMDeviceMotion *)motion;

@property(nonatomic, assign) BOOL shouldMirrorMotion;
@property(nonatomic, readonly) CMFormatDescriptionRef __attribute__((NSObject)) outputFormatDescription; // non-NULL once the renderer has been prepared

@end

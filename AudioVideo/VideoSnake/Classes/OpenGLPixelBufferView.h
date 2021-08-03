/*
 <codex>
 <abstract>The OpenGL ES view.</abstract>
 </codex>
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>

@interface OpenGLPixelBufferView : UIView

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer;
- (void)flushPixelBufferCache;
- (void)reset;

@end

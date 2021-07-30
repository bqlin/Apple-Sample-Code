//
//  RosyCIRenderer.h
//  AVCamPhotoFilter
//
//  Created by bqlin on 2018/9/3.
//  Copyright © 2018年 Bq. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FilterRendererProtocol.h"

@interface RosyCIRenderer : NSObject <FilterRendererProtocol>

#pragma mark FilterRenderer

@property (nonatomic, assign) BOOL isPrepared;

// Prepare resources.
// The outputRetainedBufferCountHint tells out of place renderers how many of
// their output buffers will be held onto by the downstream pipeline at one time.
// This can be used by the renderer to size and preallocate their pools.
- (void)prepareWithInputFormatDescription:(CMFormatDescriptionRef)inputFormatDescription outputRetainedBufferCountHint:(NSInteger)outputRetainedBufferCountHint;

// Release resources.
- (void)reset;

// The format description of the output pixel buffers.
@property (nonatomic, assign, readonly) CMFormatDescriptionRef outputFormatDescription;

// The format description of the input pixel buffers.
@property (nonatomic, assign, readonly) CMFormatDescriptionRef inputFormatDescription;

// Render pixel buffer.
- (CVPixelBufferRef)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

//
//  RosyCIRenderer.m
//  AVCamPhotoFilter
//
//  Created by bqlin on 2018/9/3.
//  Copyright © 2018年 Bq. All rights reserved.
//

#import "RosyCIRenderer.h"
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import "FilterRendererUtil.h"

@interface RosyCIRenderer()

@property (nonatomic, strong) CIContext *ciContext;
@property (nonatomic, strong) CIFilter *rosyFilter;
@property (nonatomic, assign) CGColorSpaceRef outputColorSpace;
@property (nonatomic, assign) CVPixelBufferPoolRef outputPixelBufferPool;

// The format description of the output pixel buffers.
@property (nonatomic, assign) CMFormatDescriptionRef outputFormatDescription;

// The format description of the input pixel buffers.
@property (nonatomic, assign) CMFormatDescriptionRef inputFormatDescription;

@end

@implementation RosyCIRenderer

- (instancetype)init {
    if (self = [super init]) {
        _isPrepared = NO;
    }
    return self;
}

- (NSString *)description {
    NSMutableString *description = [super.description stringByAppendingString:@":\n"].mutableCopy;
    [description appendFormat:@"Rosy (Core Image)"];
    return description;
}

#pragma mark - FilterRenderer

- (void)prepareWithInputFormatDescription:(CMFormatDescriptionRef)inputFormatDescription outputRetainedBufferCountHint:(NSInteger)outputRetainedBufferCountHint {
    ArrayTuple tuple = [FilterRendererUtil allocateOutputBufferPoolWithInputFormatDescription:inputFormatDescription outputRetainedBufferCountHint:outputRetainedBufferCountHint];
    _outputPixelBufferPool = (__bridge CVPixelBufferPoolRef)tuple[0];
    _outputColorSpace = (__bridge CGColorSpaceRef)tuple[1];
    _outputFormatDescription = (__bridge CMFormatDescriptionRef)tuple[2];
    
    if (!_outputPixelBufferPool) {
        return;
    }
    _inputFormatDescription = inputFormatDescription;
    
    _ciContext = [[CIContext alloc] init];
    _rosyFilter = [CIFilter filterWithName:@"CIColorMatrix"];
    [_rosyFilter setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:0] forKeyPath:@"inputGVector"];
    
    _isPrepared = YES;
}

- (void)reset {
    _ciContext = nil;
    _rosyFilter = nil;
    _outputColorSpace = nil;
    _outputPixelBufferPool = nil;
    _outputFormatDescription = nil;
    _inputFormatDescription = nil;
    _isPrepared = NO;
}

- (CVPixelBufferRef)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    NSAssert(_rosyFilter && _ciContext && _isPrepared, @"Invalid state: Not prepared");
    
    CIImage *sourceImage = [CIImage imageWithCVImageBuffer:pixelBuffer];
    [_rosyFilter setValue:sourceImage forKeyPath:kCIInputImageKey];
    
    CIImage *filteredImage = [_rosyFilter valueForKey:kCIOutputImageKey];
    NSAssert(filteredImage, @"CIFilter failed to render image");
    
    CVPixelBufferRef pbuf = nil;
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _outputPixelBufferPool, &pbuf);
    NSAssert(pbuf, @"Allocation failure");
    CVPixelBufferRef outputPixelBuffer = pbuf;
    
    // Render the filtered image out to a pixel buffer (no locking needed, as CIContext's render method will do that)
    [_ciContext render:filteredImage toCVPixelBuffer:outputPixelBuffer bounds:filteredImage.extent colorSpace:_outputColorSpace];
    return outputPixelBuffer;
}

@end

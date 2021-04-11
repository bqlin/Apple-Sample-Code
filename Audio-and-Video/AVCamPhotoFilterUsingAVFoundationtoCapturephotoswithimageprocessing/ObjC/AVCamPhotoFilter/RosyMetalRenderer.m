//
//  RosyMetalRenderer.m
//  AVCamPhotoFilter
//
//  Created by bqlin on 2018/9/5.
//  Copyright © 2018年 Bq. All rights reserved.
//

#import "RosyMetalRenderer.h"
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import "FilterRendererUtil.h"

@interface RosyMetalRenderer ()

@property (nonatomic, assign) CMFormatDescriptionRef inputFormatDescription;
@property (nonatomic, assign) CMFormatDescriptionRef outputFormatDescription;
@property (nonatomic, assign) CVPixelBufferPoolRef outputPixelBufferPool;
@property (nonatomic, strong) id<MTLDevice> metalDevice;
@property (nonatomic, strong) id<MTLComputePipelineState> computePipelineState;
@property (nonatomic, assign) CVMetalTextureCacheRef textureCache;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;


@end

@implementation RosyMetalRenderer

- (instancetype)init {
    if (self = [super init]) {
        _isPrepared = NO;
        _metalDevice = MTLCreateSystemDefaultDevice();
        _commandQueue = _metalDevice.newCommandQueue;
        id<MTLLibrary> defaultLibrary = _metalDevice.newDefaultLibrary;
        id<MTLFunction> kernelFunction = [defaultLibrary newFunctionWithName:@"rosyEffect"];
        NSError *error = nil;
        _computePipelineState = [_metalDevice newComputePipelineStateWithFunction:kernelFunction error:&error];
        if (error) {
            NSLog(@"Could not create pipeline state: %@", error);
        }
    }
    return self;
}

- (NSString *)description {
    NSMutableString *description = [super.description stringByAppendingString:@":\n"].mutableCopy;
    [description appendFormat:@"Rosy (Metal)"];
    return description;
}

#pragma mark -

- (void)prepareWithInputFormatDescription:(CMFormatDescriptionRef)inputFormatDescription outputRetainedBufferCountHint:(NSInteger)outputRetainedBufferCountHint {
    ArrayTuple tupe = [FilterRendererUtil allocateOutputBufferPoolWithInputFormatDescription:inputFormatDescription outputRetainedBufferCountHint:outputRetainedBufferCountHint];
    _outputPixelBufferPool = (__bridge CVPixelBufferPoolRef)tupe[0];
    _outputFormatDescription = (__bridge CMFormatDescriptionRef)tupe[2];
    
    if (!_outputPixelBufferPool) {
        return;
    }
    _inputFormatDescription = inputFormatDescription;
    
    CVMetalTextureCacheRef metalTextureCache = NULL;
    if (CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, _metalDevice, nil, &metalTextureCache) != kCVReturnSuccess) {
        NSLog(@"Unable to allocate texture cache");
    } else {
        _textureCache = metalTextureCache;
    }
    
    _isPrepared = YES;
}

- (void)reset {
    _outputPixelBufferPool = nil;
    _outputFormatDescription = nil;
    _inputFormatDescription = nil;
    _textureCache = nil;
    _isPrepared = NO;
}

- (CVPixelBufferRef)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!_isPrepared) {
        NSLog(@"Invalid state: Not prepared");
        return nil;
    }
    
    CVPixelBufferRef newPixelBuffer = NULL;
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _outputPixelBufferPool, &newPixelBuffer);
    NSAssert(newPixelBuffer, @"Allocation failure: Could not get pixel buffer from pool (%@)", self);
    
    id<MTLTexture> inputTexture = [self makeTextureFromCVPixelBuffer:pixelBuffer textureFormat:MTLPixelFormatBGRA8Unorm];
    id<MTLTexture> outputTexture = [self makeTextureFromCVPixelBuffer:newPixelBuffer textureFormat:MTLPixelFormatBGRA8Unorm];
    NSAssert(inputTexture & outputTexture, @"inputTexture & outputTexture");
    
    // Set up command queue, buffer, and encoder
    id<MTLCommandBuffer> commandBuffer = _commandQueue.commandBuffer;
    id<MTLComputeCommandEncoder> commandEncoder = commandBuffer.computeCommandEncoder;
    if (_commandQueue && commandBuffer && commandEncoder) {} else {
        NSLog(@"Failed to create Metal command queue");
        CVMetalTextureCacheFlush(_textureCache, 0);
        return nil;
    }
    
    commandEncoder.label = @"Rosy Metal";
    [commandEncoder setComputePipelineState:_computePipelineState];
    [commandEncoder setTexture:inputTexture atIndex:0];
    [commandEncoder setTexture:outputTexture atIndex:1];
    
    // Set up thread groups as described in https://developer.apple.com/reference/metal/mtlcomputecommandencoder
    NSUInteger w = _computePipelineState.threadExecutionWidth;
    NSUInteger h = _computePipelineState.maxTotalThreadsPerThreadgroup / w;
    MTLSize threadsPerThreadgroup = MTLSizeMake(w, h, 1);
    MTLSize threadgroupsPerGrid = MTLSizeMake((inputTexture.width + w - 1) / w, (inputTexture.height + h -1) / h, 1);
    [commandEncoder dispatchThreadgroups:threadgroupsPerGrid threadsPerThreadgroup:threadsPerThreadgroup];
    
    [commandEncoder endEncoding];
    [commandBuffer commit];
    
    return newPixelBuffer;
}

- (id<MTLTexture>)makeTextureFromCVPixelBuffer:(CVPixelBufferRef)pixelBuffer textureFormat:(MTLPixelFormat)textureFormat {
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    // Create a Metal texture from the image buffer
    CVMetalTextureRef cvTextureOut = NULL;
    CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pixelBuffer, nil, textureFormat, width, height, 0, &cvTextureOut);
    
    id<MTLTexture> texture = CVMetalTextureGetTexture(cvTextureOut);
    if (cvTextureOut && texture) {} else {
        CVMetalTextureCacheFlush(_textureCache, 0);
        return nil;
    }
    return texture;
}

@end

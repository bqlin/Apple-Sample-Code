//
//  FilterRendererUtil.m
//  AVCamPhotoFilter
//
//  Created by bqlin on 2018/9/3.
//  Copyright © 2018年 Bq. All rights reserved.
//

#import "FilterRendererUtil.h"

@implementation FilterRendererUtil

+ (ArrayTuple)allocateOutputBufferPoolWithInputFormatDescription:(CMFormatDescriptionRef)inputFormatDescription outputRetainedBufferCountHint:(NSInteger)outputRetainedBufferCountHint {
    FourCharCode inputMediaSubType = CMFormatDescriptionGetMediaSubType(inputFormatDescription);
    if (inputMediaSubType != kCVPixelFormatType_32BGRA) {
        NSLog(@"Invalid input pixel buffer type %s", FourCC2Str(inputMediaSubType));
        return nil;
    }
    
    CMVideoDimensions inputDimensions = CMVideoFormatDescriptionGetDimensions(inputFormatDescription);
    NSMutableDictionary *pixelBufferAttributes =
    @{
      (id)kCVPixelBufferPixelFormatTypeKey: @(inputMediaSubType),
      (id)kCVPixelBufferWidthKey: @(inputDimensions.width),
      (id)kCVPixelBufferHeightKey: @(inputDimensions.height),
      (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
      }.mutableCopy;
    
    // Get pixel buffer attributes and color space from the input format description
    CGColorSpaceRef cgColorSpace = CGColorSpaceCreateDeviceRGB();
    NSDictionary *inputFormatDescriptionExtension = (NSDictionary *)CMFormatDescriptionGetExtensions(inputFormatDescription);
    if (inputFormatDescriptionExtension) {
        id colorPrimaries = inputFormatDescriptionExtension[(id)kCVImageBufferColorPrimariesKey];
        if (colorPrimaries) {
            NSMutableDictionary *colorSpaceProperties = @{(id)kCVImageBufferColorPrimariesKey: colorPrimaries}.mutableCopy;
            id yCbCrMatrix = inputFormatDescriptionExtension[(id)kCVImageBufferYCbCrMatrixKey];
            if (yCbCrMatrix) {
                colorSpaceProperties[(id)kCVImageBufferYCbCrMatrixKey] = yCbCrMatrix;
            }
            
            id transferFunction = inputFormatDescriptionExtension[(id)kCVImageBufferTransferFunctionKey];
            if (transferFunction) {
                colorSpaceProperties[(id)kCVImageBufferTransferFunctionKey] = transferFunction;
            }
            
            pixelBufferAttributes[(id)kCVBufferPropagatedAttachmentsKey] = colorSpaceProperties;
        }
        
        id cvColorspace = inputFormatDescriptionExtension[(id)kCVImageBufferCGColorSpaceKey];
        if (cvColorspace) {
            cgColorSpace = (__bridge CGColorSpaceRef)cvColorspace;
        } else if ([colorPrimaries isKindOfClass:[NSString class]] && [(NSString *)colorPrimaries isEqualToString:(NSString *)kCVImageBufferColorPrimaries_P3_D65]) {
            cgColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
        }
    }
    
    // Create a pixel buffer pool with the same pixel attributes as the input format description
    NSDictionary *poolAttributes = @{(id)kCVPixelBufferPoolMinimumBufferCountKey: @(outputRetainedBufferCountHint)};
    CVPixelBufferPoolRef cvPixelBufferPool = nil;
    CVPixelBufferPoolCreate(kCFAllocatorDefault, (__bridge CFDictionaryRef)poolAttributes, (__bridge CFDictionaryRef)pixelBufferAttributes, &cvPixelBufferPool);
    if (cvPixelBufferPool) {
        NSLog(@"Allocation failure: Could not allocate pixel buffer pool");
        return nil;
    }
    
    [self preallocateBuffersWithPool:cvPixelBufferPool allocationThreshold:outputRetainedBufferCountHint];
    
    // Get output format description
    CVPixelBufferRef pixelBuffer = nil;
    CMFormatDescriptionRef outputFormatDescription = nil;
    NSDictionary *auxAttributes = @{(id)kCVPixelBufferPoolAllocationThresholdKey: @(outputRetainedBufferCountHint)};
    CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, cvPixelBufferPool, (__bridge CFDictionaryRef)auxAttributes, &pixelBuffer);
    if (pixelBuffer) {
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &outputFormatDescription);
    }
    pixelBuffer = nil;
    
    return @[(__bridge id)cvPixelBufferPool, (__bridge id)cgColorSpace, (__bridge id)outputFormatDescription];
}

+ (void)preallocateBuffersWithPool:(CVPixelBufferPoolRef)pool allocationThreshold:(NSInteger)allocationThreshold {
    NSMutableArray *pixelBuffers = [NSMutableArray array];
    CVReturn error = kCVReturnSuccess;
    NSDictionary *auxAttributes = @{(id)kCVPixelBufferPoolAllocationThresholdKey: @(allocationThreshold)};
    CVPixelBufferRef pixelBuffer = nil;
    while (error == kCVReturnSuccess) {
        error = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, (__bridge CFDictionaryRef)auxAttributes, &pixelBuffer);
        if (pixelBuffer) {
            [pixelBuffers addObject:(__bridge id)pixelBuffer];
        }
        pixelBuffer = nil;
    }
    [pixelBuffers removeAllObjects];
}

@end

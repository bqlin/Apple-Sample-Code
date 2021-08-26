/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Declaration of utility functions that are shared across renderers.
*/

#pragma once

#import "TargetConditionals.h"
#import <vector>
#import <Metal/Metal.h>

inline id <MTLComputePipelineState> CreateKernelPipeline (id<MTLDevice>  device,
                                                          id<MTLLibrary> library,
                                                          NSString*      inFunctionName,
                                                          bool           threadGroupSizeIsHwMultiple = true)
{
    static MTLComputePipelineDescriptor* pipelineStateDescriptor =
    [[MTLComputePipelineDescriptor alloc] init];
    
    pipelineStateDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = threadGroupSizeIsHwMultiple;
    
    pipelineStateDescriptor.computeFunction = [library newFunctionWithName:inFunctionName];
    assert (pipelineStateDescriptor.computeFunction != nil);
    NSError *error;
    id <MTLComputePipelineState> res =
        [device newComputePipelineStateWithDescriptor:pipelineStateDescriptor
                                              options:0
                                           reflection:nil
                                                error:&error];
    if (!res) { NSLog(@"Failed to create pipeline state, error %@", error); }
    return res;
};

id<MTLTexture> CreateTextureWithDevice (id<MTLDevice>        device,
                                        NSString*            filePath,
                                        bool                 sRGB,
                                        bool                 generateMips,
                                        MTLResourceOptions   storageMode = MTLStorageModePrivate);

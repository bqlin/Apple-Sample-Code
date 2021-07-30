//
//  PreviewMetalView.h
//  AVCamPhotoFilter
//
//  Created by bqlin on 2018/9/3.
//  Copyright © 2018年 Bq. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

typedef NS_ENUM(NSInteger, PreviewMetalViewRotation) {
    PreviewMetalViewRotation0Degrees,
    PreviewMetalViewRotation90Degrees,
    PreviewMetalViewRotation180Degrees,
    PreviewMetalViewRotation270Degrees,
};

@interface PreviewMetalView : MTKView

@property (nonatomic, assign) BOOL mirroring;

@property (nonatomic, assign) PreviewMetalViewRotation rotation;

@property (nonatomic, assign) CVPixelBufferRef pixelBuffer;

- (void)flushTextureCache;

- (void)configureMetal;

- (void)createTextureCache;

@end

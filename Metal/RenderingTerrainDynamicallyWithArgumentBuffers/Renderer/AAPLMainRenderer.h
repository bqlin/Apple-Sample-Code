/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Declaration of the AAPLMainRenderer which is responsible for the highest level rendering operations.
*/

#pragma once

#import "TargetConditionals.h"
#import <Metal/Metal.h>
#import <simd/simd.h>
#import "AAPLCamera.h"

@interface AAPLMainRenderer : NSObject

@property (nonnull) AAPLCamera* camera;

// Cursor position in pixel coordinates
@property simd::float2          cursorPosition;

// Bitmask for mouse button state: the first bit is for left click, second bit is right
@property NSUInteger            mouseButtonMask;
@property float                 brushSize;

-(nullable instancetype) initWithDevice:(nonnull id<MTLDevice>) device size:(CGSize) size;

-(void) DrawableSizeWillChange:(CGSize) size;

-(void) UpdateWithDrawable:(id<MTLDrawable> _Nonnull) drawable
      renderPassDescriptor:(MTLRenderPassDescriptor* _Nonnull) renderPassDescriptor
         waitForCompletion:(bool) waitForCompletion;
@end

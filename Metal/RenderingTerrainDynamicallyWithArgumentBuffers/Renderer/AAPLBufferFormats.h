/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Declaration of BufferFormats ; namespace containing global constants defining the pixel
 formats for any framebuffer used.
*/

#pragma once

#import <Metal/Metal.h>

namespace BufferFormats
{
    static const MTLPixelFormat gBuffer0Format =        MTLPixelFormatBGRA8Unorm_sRGB;
    static const MTLPixelFormat gBuffer1Format =        MTLPixelFormatRGBA8Unorm;
#if TARGET_OS_IOS
    static const MTLPixelFormat gBufferDepthFormat =    MTLPixelFormatR32Float;
#endif
    static const MTLPixelFormat depthFormat =           MTLPixelFormatDepth32Float;
    static const MTLPixelFormat shadowDepthFormat =     MTLPixelFormatDepth32Float;
    static const NSUInteger     sampleCount =           1;
    static const MTLPixelFormat backBufferformat =      MTLPixelFormatBGRA8Unorm_sRGB;
}

/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for renderer class which performs Metal setup and per frame rendering
*/

@import MetalKit;

// Platform independent renderer class
@interface AAPLMetalRenderer : NSObject

- (nonnull instancetype)initWithDevice:(nonnull id<MTLDevice>)device
                      colorPixelFormat:(MTLPixelFormat)colorPixelFormat;

- (void) drawToMTKView:(nonnull MTKView *)view;

- (void)drawToInteropTexture:(nonnull id<MTLTexture>)interopTexture;

- (void) resize:(CGSize)size;

- (void)useInteropTextureAsBaseMap:(nonnull id<MTLTexture>)texture;

- (void)useTextureFromFileAsBaseMap;


@end

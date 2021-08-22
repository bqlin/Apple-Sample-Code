/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for the renderer class that performs Metal setup and per-frame rendering.
*/

@import MetalKit;

/// The platform-independent renderer class.
@interface AAPLRenderer : NSObject<MTKViewDelegate>

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView;

// Clip-space depth value of each of the triangle's three vertices.
@property float topVertexDepth;
@property float leftVertexDepth;
@property float rightVertexDepth;

@end

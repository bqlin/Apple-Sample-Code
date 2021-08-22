/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation for a renderer class that performs Metal setup and
 per-frame rendering.
*/

@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLShaderTypes.h"

// The main class performing the rendering.
@implementation AAPLRenderer
{
    // Texture to render to and then sample from.
    id<MTLTexture> _renderTargetTexture;

    // Render pass descriptor to draw to the texture
    MTLRenderPassDescriptor* _renderToTextureRenderPassDescriptor;

    // A pipeline object to render to the offscreen texture.
    id<MTLRenderPipelineState> _renderToTextureRenderPipeline;

    // A pipeline object to render to the screen.
    id<MTLRenderPipelineState> _drawableRenderPipeline;

    // Ratio of width to height to scale positions in the vertex shader.
    float _aspectRatio;

    id<MTLDevice> _device;

    id<MTLCommandQueue> _commandQueue;
}

/// Initializes the renderer with the MetalKit view from which you obtain the Metal device.
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        NSError *error;

        _device = mtkView.device;

        mtkView.clearColor = MTLClearColorMake(1.0, 0.0, 0.0, 1.0);

        _commandQueue = [_device newCommandQueue];

        // Set up a texture for rendering to and sampling from
        MTLTextureDescriptor *texDescriptor = [MTLTextureDescriptor new];
        texDescriptor.textureType = MTLTextureType2D;
        texDescriptor.width = 512;
        texDescriptor.height = 512;
        texDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
        texDescriptor.usage = MTLTextureUsageRenderTarget |
                              MTLTextureUsageShaderRead;

        _renderTargetTexture = [_device newTextureWithDescriptor:texDescriptor];

        // Set up a render pass descriptor for the render pass to render into
        // _renderTargetTexture.

        _renderToTextureRenderPassDescriptor = [MTLRenderPassDescriptor new];

        _renderToTextureRenderPassDescriptor.colorAttachments[0].texture = _renderTargetTexture;

        _renderToTextureRenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        _renderToTextureRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 1, 1);

        _renderToTextureRenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;

        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Drawable Render Pipeline";
        pipelineStateDescriptor.sampleCount = mtkView.sampleCount;
        pipelineStateDescriptor.vertexFunction =  [defaultLibrary newFunctionWithName:@"textureVertexShader"];
        pipelineStateDescriptor.fragmentFunction =  [defaultLibrary newFunctionWithName:@"textureFragmentShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
        pipelineStateDescriptor.vertexBuffers[AAPLVertexInputIndexVertices].mutability = MTLMutabilityImmutable;

        _drawableRenderPipeline = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];

        NSAssert(_drawableRenderPipeline, @"Failed to create pipeline state to render to screen: %@", error);

        // Set up pipeline for rendering to the offscreen texture. Reuse the
        // descriptor and change properties that differ.
        pipelineStateDescriptor.label = @"Offscreen Render Pipeline";
        pipelineStateDescriptor.sampleCount = 1;
        pipelineStateDescriptor.vertexFunction =  [defaultLibrary newFunctionWithName:@"simpleVertexShader"];
        pipelineStateDescriptor.fragmentFunction =  [defaultLibrary newFunctionWithName:@"simpleFragmentShader"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = _renderTargetTexture.pixelFormat;
        _renderToTextureRenderPipeline = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        NSAssert(_renderToTextureRenderPipeline, @"Failed to create pipeline state to render to texture: %@", error);
    }
    return self;
}

#pragma mark - MetalKit View Delegate

// Handles view orientation and size changes.
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    _aspectRatio =  (float)size.height / (float)size.width;
}

// Handles view rendering for a new frame.
- (void)drawInMTKView:(nonnull MTKView *)view
{

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Command Buffer";

    {
        static const AAPLSimpleVertex triVertices[] =
        {
            // Positions     ,  Colors
            { {  0.5,  -0.5 },  { 1.0, 0.0, 0.0, 1.0 } },
            { { -0.5,  -0.5 },  { 0.0, 1.0, 0.0, 1.0 } },
            { {  0.0,   0.5 },  { 0.0, 0.0, 1.0, 0.0 } },
        };

        id<MTLRenderCommandEncoder> renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:_renderToTextureRenderPassDescriptor];
        renderEncoder.label = @"Offscreen Render Pass";
        [renderEncoder setRenderPipelineState:_renderToTextureRenderPipeline];

        [renderEncoder setVertexBytes:&triVertices
                               length:sizeof(triVertices)
                              atIndex:AAPLVertexInputIndexVertices];

        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:3];

        // End encoding commands for this render pass.
        [renderEncoder endEncoding];
    }

    MTLRenderPassDescriptor *drawableRenderPassDescriptor = view.currentRenderPassDescriptor;
    if(drawableRenderPassDescriptor != nil)
    {
        static const AAPLTextureVertex quadVertices[] =
        {
            // Positions     , Texture coordinates
            { {  0.5,  -0.5 },  { 1.0, 1.0 } },
            { { -0.5,  -0.5 },  { 0.0, 1.0 } },
            { { -0.5,   0.5 },  { 0.0, 0.0 } },

            { {  0.5,  -0.5 },  { 1.0, 1.0 } },
            { { -0.5,   0.5 },  { 0.0, 0.0 } },
            { {  0.5,   0.5 },  { 1.0, 0.0 } },
        };
        id<MTLRenderCommandEncoder> renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:drawableRenderPassDescriptor];
        renderEncoder.label = @"Drawable Render Pass";

        [renderEncoder setRenderPipelineState:_drawableRenderPipeline];

        [renderEncoder setVertexBytes:&quadVertices
                               length:sizeof(quadVertices)
                              atIndex:AAPLVertexInputIndexVertices];

        [renderEncoder setVertexBytes:&_aspectRatio
                               length:sizeof(_aspectRatio)
                              atIndex:AAPLVertexInputIndexAspectRatio];

        // Set the offscreen texture as the source texture.
        [renderEncoder setFragmentTexture:_renderTargetTexture atIndex:AAPLTextureInputIndexColor];

        // Draw quad with rendered texture.
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:6];

        [renderEncoder endEncoding];

        [commandBuffer presentDrawable:view.currentDrawable];
    }

    [commandBuffer commit];
}

@end

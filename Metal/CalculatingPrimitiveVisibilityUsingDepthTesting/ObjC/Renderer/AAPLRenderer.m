/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the renderer class that performs Metal setup and per-frame rendering.
*/

@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLShaderTypes.h"

@implementation AAPLRenderer
{    
    id<MTLDevice>              _device;
    id<MTLCommandQueue>        _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    
    // Combined depth and stencil state object.
    id<MTLDepthStencilState> _depthState;
    
    vector_uint2             _viewportSize;
}

/// Initializes the renderer with the MetalKit view from which you obtain the Metal device.
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        _device = mtkView.device;
        
        // Set a black clear color.
        mtkView.clearColor = MTLClearColorMake(0, 0, 0, 1);
        
        // Indicate that each pixel in the depth buffer is a 32-bit floating point value.
        mtkView.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
        
        // Indicate that Metal should clear all values in the depth buffer to `1.0` when you create
        // a render command encoder with the MetalKit view's `currentRenderPassDescriptor` property.
        mtkView.clearDepth = 1.0;

        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];
        
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Render Pipeline";
        pipelineStateDescriptor.sampleCount = mtkView.sampleCount;
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
        pipelineStateDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat;
        pipelineStateDescriptor.vertexBuffers[AAPLVertexInputIndexVertices].mutability = MTLMutabilityImmutable;
        
        NSError *error;
        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];

        NSAssert(_pipelineState, @"Failed to create pipeline state: %@", error);
        
        MTLDepthStencilDescriptor *depthDescriptor = [MTLDepthStencilDescriptor new];
        depthDescriptor.depthCompareFunction = MTLCompareFunctionLessEqual;
        depthDescriptor.depthWriteEnabled = YES;
        _depthState = [_device newDepthStencilStateWithDescriptor:depthDescriptor];
        
        // Create the command queue.
        _commandQueue = [_device newCommandQueue];
    }
    return self;
}

#pragma mark - MTKView Delegate Methods

/// Handles view orientation or size changes.
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Save the size of the drawable so you pass these
    // values to the vertex shader when you render the view.
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
}

/// Handles view rendering for a new frame.
- (void)drawInMTKView:(nonnull MTKView *)view
{
    // Create a new command buffer for each rendering pass to the current drawable.
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Command Buffer";
    
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if(renderPassDescriptor != nil)
    {
        // Create a render command encoder to encode the rendering pass.
        id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"Render Encoder";
        
        // Encode the render pipeline state object.
        [renderEncoder setRenderPipelineState:_pipelineState];
        
        [renderEncoder setDepthStencilState:_depthState];
        
        // Encode the viewport size so it can be accessed by the vertex shader.
        [renderEncoder setVertexBytes:&_viewportSize
                               length:sizeof(_viewportSize)
                              atIndex:AAPLVertexInputIndexViewport];
        
        // Initialize and encode the vertex data for the gray quad.
        // Set the vertex depth values to `0.5` (z component).
        const AAPLVertex quadVertices[] =
        {
            // Pixel positions (x, y) and clip depth (z),        RGBA colors.
            { {                 100,                 100, 0.5 }, { 0.5, 0.5, 0.5, 1 } },
            { {                 100, _viewportSize.y-100, 0.5 }, { 0.5, 0.5, 0.5, 1 } },
            { { _viewportSize.x-100, _viewportSize.y-100, 0.5 }, { 0.5, 0.5, 0.5, 1 } },
            
            { {                 100,                 100, 0.5 }, { 0.5, 0.5, 0.5, 1 } },
            { { _viewportSize.x-100, _viewportSize.y-100, 0.5 }, { 0.5, 0.5, 0.5, 1 } },
            { { _viewportSize.x-100,                 100, 0.5 }, { 0.5, 0.5, 0.5, 1 } },
        };
        
        [renderEncoder setVertexBytes:quadVertices
                               length:sizeof(quadVertices)
                              atIndex:AAPLVertexInputIndexVertices];
        
        // Encode the draw command for the gray quad.
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:6];
        
        // Initialize and encode the vertex data for the white triangle.
        // Set the UI control values to the vertex depth values (z component).
        const AAPLVertex triangleVertices[] =
        {
            // Pixel positions (x, y) and clip depth (z),                           RGBA colors.
            { {                    200, _viewportSize.y - 200, _leftVertexDepth  }, { 1, 1, 1, 1 } },
            { {  _viewportSize.x / 2.0,                   200, _topVertexDepth   }, { 1, 1, 1, 1 } },
            { {  _viewportSize.x - 200, _viewportSize.y - 200, _rightVertexDepth }, { 1, 1, 1, 1 } }
        };
        
        [renderEncoder setVertexBytes:triangleVertices
                               length:sizeof(triangleVertices)
                              atIndex:AAPLVertexInputIndexVertices];
        
        // Encode the draw command for the white triangle.
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:3];
        
        // Finalize encoding.
        [renderEncoder endEncoding];
        
        // Schedule a drawable's presentation after the rendering pass is complete.
        [commandBuffer presentDrawable:view.currentDrawable];
    }

    // Finalize CPU work and submit the command buffer to the GPU.
    [commandBuffer commit];
}

@end

/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per frame rendering
*/

@import simd;
@import MetalKit;

#import "AAPLRenderer.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as input to the shaders
#import "AAPLShaderTypes.h"

// Main class performing the rendering
@implementation AAPLRenderer
{
    id <MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;

    // The Metal buffers in which we store our vertex data
    id<MTLBuffer> _vertexBuffer;

    // The number of vertices in the vertex buffer
    NSUInteger _numVertices;

    // Render pipeline used to draw the quad
    id<MTLRenderPipelineState> _pipelineState;

    // Metal texture object to be referenced via an argument buffer
    id<MTLTexture> _texture;

    // Metal sampler object to be referenced via an argument buffer
    id<MTLSamplerState> _sampler;

    // Metal buffer object to be reference via an argument buffer
    id<MTLBuffer> _indirectBuffer;

    // Buffer containing encoded arguments for our fragment shader
    id<MTLBuffer> _fragmentShaderArgumentBuffer;

    // Viewport to maintain 1:1 aspect ratio
    MTLViewport _viewport;
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        _device = mtkView.device;

        mtkView.clearColor = MTLClearColorMake(0.0, 0.5, 0.5, 1.0f);

        // Create a vertex buffer, and initialize it with our generics array
        {
            static const AAPLVertex vertexData[] =
            {
                //      Vertex      |  Texture    |         Vertex
                //     Positions    | Coordinates |         Colors
                { {  .75f,  -.75f }, { 1.f, 0.f }, { 0.f, 1.f, 0.f, 1.f } },
                { { -.75f,  -.75f }, { 0.f, 0.f }, { 1.f, 1.f, 1.f, 1.f } },
                { { -.75f,   .75f }, { 0.f, 1.f }, { 0.f, 0.f, 1.f, 1.f } },
                { {  .75f,  -.75f }, { 1.f, 0.f }, { 0.f, 1.f, 0.f, 1.f } },
                { { -.75f,   .75f }, { 0.f, 1.f }, { 0.f, 0.f, 1.f, 1.f } },
                { {  .75f,   .75f }, { 1.f, 1.f }, { 1.f, 1.f, 1.f, 1.f } },
            };

            _vertexBuffer = [_device newBufferWithBytes:vertexData
                                                 length:sizeof(vertexData)
                                                options:MTLResourceStorageModeShared];

            _vertexBuffer.label = @"Vertices";
        }

        // Create texture to apply to the quad
        {
            NSError *error;

            MTKTextureLoader *textureLoader = [[MTKTextureLoader alloc] initWithDevice:_device];

            _texture = [textureLoader newTextureWithName:@"Text"
                                             scaleFactor:1.0
                                                  bundle:nil
                                                 options:nil
                                                   error:&error];

            NSAssert(_texture, @"Could not load foregroundTexture: %@", error);

            _texture.label = @"Text";
        }

        // Create sampler to use for texturing
        {
            MTLSamplerDescriptor *samplerDesc = [MTLSamplerDescriptor new];
            samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
            samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
            samplerDesc.mipFilter = MTLSamplerMipFilterNotMipmapped;
            samplerDesc.normalizedCoordinates = YES;
            samplerDesc.supportArgumentBuffers = YES;

            _sampler = [_device newSamplerStateWithDescriptor:samplerDesc];
        }

        uint16_t bufferElements = 256;

        // Create buffers used to make a pattern on our quad
        {
            _indirectBuffer = [_device newBufferWithLength:sizeof(float) * bufferElements
                                                   options:MTLResourceStorageModeShared];

            float * const patternArray = _indirectBuffer.contents;

            for(uint16_t i = 0; i < bufferElements; i++) {
                patternArray[i] = ((i % 24) < 3) * 1.0;
            }

            _indirectBuffer.label = @"Indirect Buffer";
        }

        // Create our render pipeline and argument buffers
        {
            NSError *error;

            id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

            id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];

            id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

            id <MTLArgumentEncoder> argumentEncoder =
                [fragmentFunction newArgumentEncoderWithBufferIndex:AAPLFragmentBufferIndexArguments];

            NSUInteger argumentBufferLength = argumentEncoder.encodedLength;

            _fragmentShaderArgumentBuffer = [_device newBufferWithLength:argumentBufferLength options:0];

            _fragmentShaderArgumentBuffer.label = @"Argument Buffer";

            [argumentEncoder setArgumentBuffer:_fragmentShaderArgumentBuffer offset:0];

            [argumentEncoder setTexture:_texture atIndex:AAPLArgumentBufferIDExampleTexture];
            [argumentEncoder setSamplerState:_sampler atIndex:AAPLArgumentBufferIDExampleSampler];
            [argumentEncoder setBuffer:_indirectBuffer offset:0 atIndex:AAPLArgumentBufferIDExampleBuffer];

            uint32_t *numElementsAddress = [argumentEncoder constantDataAtIndex:AAPLArgumentBufferIDExampleConstant];

            *numElementsAddress = bufferElements;

            // Set up a descriptor for creating a pipeline state object
            MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
            pipelineStateDescriptor.label = @"Argument Buffer Example";
            pipelineStateDescriptor.vertexFunction = vertexFunction;
            pipelineStateDescriptor.fragmentFunction = fragmentFunction;
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
            _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                     error:&error];

            NSAssert(_pipelineState, @"Failed to create pipeline state: %@", error.localizedDescription);

        }

        // Create the command queue
        _commandQueue = [_device newCommandQueue];
    }

    return self;
}

/// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view
{
    // Create a new command buffer for each render pass to the current drawable
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";

    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    if(renderPassDescriptor != nil)
    {
        // Create a render command encoder so we can render into something
        id <MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"MyRenderEncoder";

        [renderEncoder setViewport:_viewport];

        // Indicate to Metal that these resources will be accessed by the GPU and therefore
        //   must be mapped to the GPU's address space
        [renderEncoder useResource:_texture usage:MTLResourceUsageSample];
        [renderEncoder useResource:_indirectBuffer usage:MTLResourceUsageRead];

        [renderEncoder setRenderPipelineState:_pipelineState];

        [renderEncoder setVertexBuffer:_vertexBuffer
                                offset:0
                               atIndex:AAPLVertexBufferIndexVertices];

        [renderEncoder setFragmentBuffer:_fragmentShaderArgumentBuffer
                                  offset:0
                                 atIndex:AAPLFragmentBufferIndexArguments];

        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:6];

        [renderEncoder endEncoding];

        // Schedule a present once the framebuffer is complete using the current drawable
        [commandBuffer presentDrawable:view.currentDrawable];
    }

    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Calculate a viewport so that it's always square and and in the middle of the drawable

    if(size.width < size.height) {
        _viewport.originX = 0;
        _viewport.originY = (size.height - size.width) / 2.0;;
        _viewport.width = _viewport.height = size.width;
        _viewport.zfar = 1.0;
        _viewport.znear = -1.0;
    } else {
        _viewport.originX = (size.width - size.height) / 2.0;
        _viewport.originY = 0;
        _viewport.width = _viewport.height = size.height;
        _viewport.zfar = 1.0;
        _viewport.znear = -1.0;
    }
}

@end


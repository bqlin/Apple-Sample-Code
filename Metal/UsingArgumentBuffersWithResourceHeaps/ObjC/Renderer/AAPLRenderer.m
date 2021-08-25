/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per frame rendering
*/
@import simd;
@import MetalKit;

#import <stdlib.h>      // for random()
#import "AAPLRenderer.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as input to the shaders
#import "AAPLShaderTypes.h"

// This sample can be run both with and without using a resource heap to demonstrate the difference
//    between the two methods of resource management when used in conjunction with argument buffers
#define ENABLE_RESOURCE_HEAP 1

// Main class performing the rendering
@implementation AAPLRenderer
{
    id <MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;

    // The Metal buffer storing vertex data
    id<MTLBuffer> _vertexBuffer;

    // Render pipeline used to draw all quads
    id<MTLRenderPipelineState> _pipelineState;

    // The number of vertices in the vertex buffer
    NSUInteger _numVertices;

    // Metal texture object to be referenced via an argument buffer
    id<MTLTexture> _texture[AAPLNumTextureArguments];

    // Metal buffer object containing data and referenced by the shader via an argument buffer
    id<MTLBuffer> _dataBuffer[AAPLNumBufferArguments];

    // Buffer containing encoded arguments for our fragment shader
    id<MTLBuffer> _fragmentShaderArgumentBuffer;

    // Resource Heap to contain all resources encoded in our argument buffer
    id<MTLHeap> _heap;

    // Viewport to maintain 1:1 aspect ratio
    MTLViewport _viewport;
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        NSError *error;

        _device = mtkView.device;

        // Create the command queue
        _commandQueue = [_device newCommandQueue];

        mtkView.clearColor = MTLClearColorMake(0.0, 0.5, 0.5, 1.0f);

        // Set up a MTLBuffer with the textures coordinates and per-vertex colors
        static const AAPLVertex vertexData[] =
        {
            //      Vertex      |  Texture    |
            //     Positions    | Coordinates |
            { {  .75f,  -.75f }, { 1.f, 0.f } },
            { { -.75f,  -.75f }, { 0.f, 0.f } },
            { { -.75f,   .75f }, { 0.f, 1.f } },
            { {  .75f,  -.75f }, { 1.f, 0.f } },
            { { -.75f,   .75f }, { 0.f, 1.f } },
            { {  .75f,   .75f }, { 1.f, 1.f } }            
        };

        // Create a vertex buffer, and initialize it with our generics array
        _vertexBuffer = [_device newBufferWithBytes:vertexData
                                             length:sizeof(vertexData)
                                            options:MTLResourceStorageModeShared];

        _vertexBuffer.label = @"Vertices";

        // Load data for resources
        [self loadResources];

#if ENABLE_RESOURCE_HEAP

        // Create a heap large enough to contain all resources
        [self createHeap];

        /// Move resources loaded into heap
        [self moveResourcesToHeap];

#endif

        /// Create our render pipeline

        // Load the shader function from the library
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
        id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
        id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

        // Create a pipeline state object

        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Argument Buffer Example";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                 error:&error];

        NSAssert(_pipelineState, @"Failed to create pipeline state, error %@", error);

        id <MTLArgumentEncoder> argumentEncoder =
            [fragmentFunction newArgumentEncoderWithBufferIndex:AAPLFragmentBufferIndexArguments];

        NSUInteger argumentBufferLength = argumentEncoder.encodedLength;

        _fragmentShaderArgumentBuffer = [_device newBufferWithLength:argumentBufferLength options:0];

        _fragmentShaderArgumentBuffer.label = @"Argument Buffer Fragment Shader";

        [argumentEncoder setArgumentBuffer:_fragmentShaderArgumentBuffer offset:0];

        for(uint32_t i = 0; i < AAPLNumTextureArguments; i++)
        {
            [argumentEncoder setTexture:_texture[i]
                                atIndex:AAPLArgumentBufferIDExampleTextures+i];
        }

        for(uint32_t i = 0; i < AAPLNumBufferArguments; i++)
        {
            [argumentEncoder setBuffer:_dataBuffer[i]
                                offset:0
                                atIndex:AAPLArgumentBufferIDExampleBuffers+i];

            uint32_t *elementCountAddress =
                [argumentEncoder constantDataAtIndex:AAPLArgumentBufferIDExampleConstants+i];

            *elementCountAddress = (uint32_t)_dataBuffer[i].length / 4;
        }
    }

    return self;
}

/// Creates a texture descriptor from a texture object.  Used to create a texture object in a heap
/// for the given texture
+ (nonnull MTLTextureDescriptor*) newDescriptorFromTexture:(nonnull id<MTLTexture>)texture
                                               storageMode:(MTLStorageMode)storageMode
{
    MTLTextureDescriptor * descriptor = [MTLTextureDescriptor new];

    descriptor.textureType      = texture.textureType;
    descriptor.pixelFormat      = texture.pixelFormat;
    descriptor.width            = texture.width;
    descriptor.height           = texture.height;
    descriptor.depth            = texture.depth;
    descriptor.mipmapLevelCount = texture.mipmapLevelCount;
    descriptor.arrayLength      = texture.arrayLength;
    descriptor.sampleCount      = texture.sampleCount;
    descriptor.storageMode      = storageMode;

    return descriptor;
}

/// Loads textures from the asset catalog and programmatically generates buffer objects
- (void) loadResources
{
    MTKTextureLoader *textureLoader = [[MTKTextureLoader alloc] initWithDevice:_device];

    NSError *error;

    for(NSUInteger i = 0; i < AAPLNumTextureArguments; i++)
    {
        NSString *textureName = [[NSString alloc] initWithFormat:@"Texture%lu", i];

        _texture[i] = [textureLoader newTextureWithName:textureName
                                            scaleFactor:1.0
                                                 bundle:nil
                                                options:nil
                                                  error:&error];
        if(!_texture[i])
        {
            [NSException raise:NSGenericException
                        format:@"Could not load texture with name %@: %@", textureName, error.localizedDescription];
        }

        _texture[i].label = textureName;
    }

    // Seed random number generator used to create data for our buffers
    srandom(32420934);

    uint32_t elementCounts[AAPLNumBufferArguments];

    // Create buffers which will be accessed indirectly via the argument buffer

    for(NSUInteger i = 0; i < AAPLNumBufferArguments; i++)
    {
        // Randomly choose the number of 32-bit floating-point values we'll sorce in each buffer
        uint32_t elementCount = random() % 384 + 128;

        // Save the element count in order to store it in the argument buffer later
        // as a constant for shader access in the future
        elementCounts[i] = elementCount;

        NSUInteger bufferSize = elementCount * sizeof(float);

        _dataBuffer[i] = [_device newBufferWithLength:bufferSize
                                              options:MTLResourceStorageModeShared];

        _dataBuffer[i].label = [[NSString alloc] initWithFormat:@"DataBuffer%lu", i];

        // Generate floating-point values for the buffer that modulates between 0 and 1
        // in a sin wave just so there is something interesting to see in each buffer

        float *elements = (float*)_dataBuffer[i].contents;

        for(NSUInteger k = 0; k < elementCount; k++)
        {
            // Calculate where in the wave this element is
            float point = (k * 2 * M_PI) / elementCount;

            // Generate wave and convert from [-1, 1] to [0, 1]
            elements[k] = sin(point * i) * 0.5 + 0.5;
        }

        // Save the element count in order to store it in the argument buffer
        // as a constant and access in the shader
        elementCounts[i] = elementCount;
    }
}

#if ENABLE_RESOURCE_HEAP

/// Creates a resource heap to store texture and buffer object
- (void) createHeap
{
    MTLHeapDescriptor *heapDescriptor = [MTLHeapDescriptor new];
    heapDescriptor.storageMode = MTLStorageModePrivate;
    heapDescriptor.size =  0;

    // Build a descriptor for each texture and calculate the size required to store all textures in the heap
    for(uint32_t i = 0; i < AAPLNumTextureArguments; i++)
    {
        // Create a descriptor using the texture's properties
        MTLTextureDescriptor *descriptor = [AAPLRenderer newDescriptorFromTexture:_texture[i]
                                                                      storageMode:heapDescriptor.storageMode];

        // Determine the size required for the heap for the given descriptor
        MTLSizeAndAlign sizeAndAlign = [_device heapTextureSizeAndAlignWithDescriptor:descriptor];

        // Align the size so that more resources will fit in the heap after this texture
        sizeAndAlign.size += (sizeAndAlign.size & (sizeAndAlign.align - 1)) + sizeAndAlign.align;

        // Accumulate the size required to store this texture in the heap
        heapDescriptor.size += sizeAndAlign.size;
    }

    // Calculate the size required to store all buffers in the heap
    for(uint32_t i = 0; i < AAPLNumBufferArguments; i++)
    {
        // Determine the size required for the heap for the given buffer size
        MTLSizeAndAlign sizeAndAlign = [_device heapBufferSizeAndAlignWithLength:_dataBuffer[i].length
                                                                         options:MTLResourceStorageModePrivate];

        // Align the size so that more resources will fit in the heap after this buffer
        sizeAndAlign.size +=  (sizeAndAlign.size & (sizeAndAlign.align - 1)) + sizeAndAlign.align;

        // Accumulate the size required to store this buffer in the heap
        heapDescriptor.size += sizeAndAlign.size;
    }

    // Create a heap large enough to store all resources
    _heap = [_device newHeapWithDescriptor:heapDescriptor];
}

/// Moves texture and buffer data from their original objects to objects in the heap
- (void)moveResourcesToHeap
{
    // Create a command buffer and blit encoder to copy data from the existing resources to
    // the new resources created from the heap
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Heap Copy Command Buffer";

    id <MTLBlitCommandEncoder> blitEncoder = commandBuffer.blitCommandEncoder;
    blitEncoder.label = @"Heap Transfer Blit Encoder";

    // Create new textures from the heap and copy the contents of the existing textures to
    // the new textures
    for(uint32_t i = 0; i < AAPLNumTextureArguments; i++)
    {
        // Create a descriptor using the texture's properties
        MTLTextureDescriptor *descriptor = [AAPLRenderer newDescriptorFromTexture:_texture[i]
                                                                      storageMode:_heap.storageMode];

        // Create a texture from the heap
        id<MTLTexture> heapTexture = [_heap newTextureWithDescriptor:descriptor];

        heapTexture.label = _texture[i].label;

        [blitEncoder pushDebugGroup:[NSString stringWithFormat:@"%@ Blits", heapTexture.label]];

        // Blit every slice of every level from the existing texture to the new texture
        MTLRegion region = MTLRegionMake2D(0, 0, _texture[i].width, _texture[i].height);
        for(NSUInteger level = 0; level < _texture[i].mipmapLevelCount;  level++)
        {

            [blitEncoder pushDebugGroup:[NSString stringWithFormat:@"Level %lu Blit", level]];

            for(NSUInteger slice = 0; slice < _texture[i].arrayLength; slice++)
            {
                [blitEncoder copyFromTexture:_texture[i]
                                 sourceSlice:slice
                                 sourceLevel:level
                                sourceOrigin:region.origin
                                  sourceSize:region.size
                                   toTexture:heapTexture
                            destinationSlice:slice
                            destinationLevel:level
                           destinationOrigin:region.origin];
            }
            region.size.width /= 2;
            region.size.height /= 2;
            if(region.size.width == 0) region.size.width = 1;
            if(region.size.height == 0) region.size.height = 1;

            [blitEncoder popDebugGroup];
        }

        [blitEncoder popDebugGroup];

        // Replace the existing texture with the new texture
        _texture[i] = heapTexture;
    }

    // Create new buffers from the heap and copy the contents of existing buffers to the
    // new buffers
    for(uint32_t i = 0; i < AAPLNumBufferArguments; i++)
    {
        // Create a buffer from the heap
        id<MTLBuffer> heapBuffer = [_heap newBufferWithLength:_dataBuffer[i].length
                                                      options:MTLResourceStorageModePrivate];

        heapBuffer.label = _dataBuffer[i].label;

        // Blit contents of the original buffer to the new buffer
        [blitEncoder copyFromBuffer:_dataBuffer[i]
                       sourceOffset:0
                           toBuffer:heapBuffer
                  destinationOffset:0
                               size:heapBuffer.length];

        // Replace the existing buffer with the new buffer
        _dataBuffer[i] = heapBuffer;
    }

    [blitEncoder endEncoding];
    [commandBuffer commit];
}

#endif // ENABLE_RESOURCE_HEAP

/// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view
{
    // Create a new command buffer for each render pass to the current drawable
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Per Frame Commands";

    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    if(renderPassDescriptor != nil)
    {
        // Create a render command encoder so we can render into something
        id <MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"Per Frame Rendering";

        [renderEncoder setViewport:_viewport];

#if ENABLE_RESOURCE_HEAP
        // Make a single `useHeap:` call for the entire heap, instead of one
        // `useResource:usage:` call per texture and per buffer
        [renderEncoder useHeap:_heap];
#else
        for(uint32_t i = 0; i < AAPLNumTextureArguments; i++)
        {
            // Indicate to Metal that these textures will be accessed by the GPU and
            // therefore must be mapped to the GPU's address space
            [renderEncoder useResource:_texture[i] usage:MTLResourceUsageSample];
        }

        for(uint32_t i = 0; i < AAPLNumBufferArguments; i++)
        {
            // Indicate to Metal that these buffers will be accessed by the GPU and
            // therefore must be mapped to the GPU's address space
            [renderEncoder useResource:_dataBuffer[i] usage:MTLResourceUsageRead];
        }
#endif

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

    [commandBuffer waitUntilCompleted];
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Calculate a viewport so that it's always square and and in the middle of the drawable

    if(size.width < size.height)
    {
        _viewport.originX = 0;
        _viewport.originY = (size.height - size.width) / 2.0;;
        _viewport.width = _viewport.height = size.width;
        _viewport.zfar = 1.0;
        _viewport.znear = -1.0;
    }
    else
    {
        _viewport.originX = (size.width - size.height) / 2.0;
        _viewport.originY = 0;
        _viewport.width = _viewport.height = size.height;
        _viewport.zfar = 1.0;
        _viewport.znear = -1.0;
    }
}

@end


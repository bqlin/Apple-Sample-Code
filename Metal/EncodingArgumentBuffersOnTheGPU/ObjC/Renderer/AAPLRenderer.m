/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per frame rendering
*/
@import simd;
@import MetalKit;

#import "AAPLRenderer.h"

// The max number of command buffers in flight
static const NSUInteger AAPLMaxBuffersInFlight = 3;

// Main class performing the rendering
@implementation AAPLRenderer
{
    dispatch_semaphore_t  _inFlightSemaphore;
    id<MTLDevice>         _device;
    id<MTLCommandQueue>   _commandQueue;

    // Compute pipeline which updates instances and encodes instance parameters
    id<MTLComputePipelineState> _computePipeline;

    // The Metal buffer storing vertex data
    id<MTLBuffer> _vertexBuffer;

    // The number of vertices in the vertex buffer
    NSUInteger _numVertices;

    // The Metal buffers storing per frame uniform data
    id<MTLBuffer> _frameStateBuffer[AAPLMaxBuffersInFlight];

    // Index into _frameStateBuffer to use for the current frame
    NSUInteger _inFlightIndex;

    // Render pipeline used to draw instances
    id<MTLRenderPipelineState> _renderPipeline;

    // Metal texture object to be referenced via an argument buffer
    id<MTLTexture> _textures[AAPLNumTextures];

    // Buffer with each texture encoded into it
    id<MTLBuffer> _sourceTextures;

    // Buffer with parameters for each instance.  Provides location and textures for quad instances.
    // Written by a compute kernel. Read by a render pipeline.
    id<MTLBuffer> _instanceParameters;

    // Resource Heap to contain all resources encoded in our argument buffer
    id<MTLHeap> _heap;

    // Compute kernel dispatch parameters
    MTLSize _threadgroupSize;
    MTLSize _threadgroupCount;

    float _blendTheta;
    uint32_t _textureIndexOffset;

    vector_float2 _quadScale;
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        NSError *error;

        _device = mtkView.device;

        _inFlightSemaphore = dispatch_semaphore_create(AAPLMaxBuffersInFlight);

        // Create the command queue
        _commandQueue = [_device newCommandQueue];

        mtkView.clearColor = MTLClearColorMake(0.0, 0.5, 0.5, 1.0f);

        // Set up a MTLBuffer for a small quad with texture coordinates
        static const AAPLVertex vertexData[] =
        {
            //             Vertex             |   Texture   |
            //            Positions           | Coordinates |
            { {  AAPLQuadSize,            0 }, { 1.f, 0.f } },
            { {             0,            0 }, { 0.f, 0.f } },
            { {             0, AAPLQuadSize }, { 0.f, 1.f } },
            { {  AAPLQuadSize,            0 }, { 1.f, 0.f } },
            { {             0, AAPLQuadSize }, { 0.f, 1.f } },
            { {  AAPLQuadSize, AAPLQuadSize }, { 1.f, 1.f } }
        };

        // Create a vertex buffer, and initialize it with our generics array
        _vertexBuffer = [_device newBufferWithBytes:vertexData
                                             length:sizeof(vertexData)
                                            options:MTLResourceStorageModeShared];

        _vertexBuffer.label = @"Vertices";

        // Load data for resources
        [self loadResources];

        // Create a heap large enough to contain all resources
        [self createHeap];

        /// Move resources loaded into heap
        [self moveResorucesToHeap];

        // Load all the shader files with a metal file extension in the project
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

        /// Create compute pipeline and objects used in the compute pass
        ///////////////////////////////////////////////////////////////////

        id<MTLFunction> computeFunction = [defaultLibrary newFunctionWithName:@"updateInstances"];

        _computePipeline = [_device newComputePipelineStateWithFunction:computeFunction
                                                                  error:&error];

        NSAssert(_computePipeline, @"Failed to create compute pipeline state, error %@", error.localizedDescription);

        _threadgroupSize = MTLSizeMake(16, 1, 1);
        _threadgroupCount = MTLSizeMake(1, 1, 1);
        _threadgroupCount.width = (2 * AAPLNumInstances -  1) / _threadgroupSize.width;

        _threadgroupCount.width = MAX(_threadgroupCount.width, 1);

        /// Create and encode argument buffers
        ///////////////////////////////////////

        // Create an argument encoder for arguments to pass into the compute kernel.
        id<MTLArgumentEncoder> argumentEncoder =
            [computeFunction newArgumentEncoderWithBufferIndex:AAPLComputeBufferIndexSourceTextures];

        // Determine the size of a texture argument in a buffer.
        NSUInteger textureArgumentSize = argumentEncoder.encodedLength;

        // Calculate the size of the array of texture arguments neccessary to fit all textures in the buffer.
        NSUInteger textureArgumentArrayLength = textureArgumentSize * AAPLNumTextures;

        // Create a buffer that will hold the arguments for all textures
        _sourceTextures = [_device newBufferWithLength:textureArgumentArrayLength options:0];

        _sourceTextures.label = @"Texture List";

        // Encode inputs arguments for our compute kernel
        for(uint32_t i = 0; i < AAPLNumTextures; i++)
        {
            // Calculate offset of the current texture argument in the argument buffer array.
            NSUInteger argumentBufferOffset = i * textureArgumentSize;

            // Set the offset to which the renderer will write the texture argument.
            [argumentEncoder setArgumentBuffer:_sourceTextures
                                        offset:argumentBufferOffset];

            // Set the texture at the offset specified above.
            [argumentEncoder setTexture:_textures[i]
                                atIndex:AAPLArgumentBufferIDTexture];
        }

        // Create an argument encoder to encode arguments output by the compute kernel and input
        // to the render pipeline
        id<MTLArgumentEncoder> instanceParameterEncoder =
            [computeFunction newArgumentEncoderWithBufferIndex:AAPLComputeBufferIndexInstanceParams];

        // Create an argument buffer used for outputs from the compute kernel and
        // inputs for the render pipeline.

        // The encodedLength represents the size of the structure used to define the argument
        // buffer.  Each instance needs its own structure, so we multiply encodedLength by the
        // number of instances so that we create a buffer which can hold data for each instance
        // rendered.
        NSUInteger instanceParameterLength = instanceParameterEncoder.encodedLength * AAPLNumInstances;

        _instanceParameters = [_device newBufferWithLength:instanceParameterLength options:0];

        _instanceParameters.label = @"Instance Parameters Array";

        /// Create render pipeline and objects used in the render pass
        //////////////////////////////////////////////////////////////////

        // Load shader functions
        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

        // Create a pipeline state object
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Argument Buffer Pipeline";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
        _renderPipeline = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                 error:&error];

        NSAssert(_renderPipeline, @"Failed to create render pipeline state, error %@", error.localizedDescription);

        for(NSUInteger bufferIndex = 0; bufferIndex < AAPLMaxBuffersInFlight; bufferIndex++)
        {
            _frameStateBuffer[bufferIndex] = [_device newBufferWithLength:sizeof(AAPLFrameState)
                                                                  options:MTLResourceStorageModeShared];
            _frameStateBuffer[bufferIndex].label = [[NSString alloc] initWithFormat:@"FrameDataBuffer %lu", bufferIndex];
        }
    }

    return self;
}

/// Creates a texture descriptor from a texture object.  Used to create a texture object from
/// a heap for the given texture
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

/// Loads textures from the asset catalog
- (void) loadResources
{
    MTKTextureLoader *textureLoader = [[MTKTextureLoader alloc] initWithDevice:_device];

    NSError *error;

    for(NSUInteger i = 0; i < AAPLNumTextures; i++)
    {
        NSString *textureName = [[NSString alloc] initWithFormat:@"Texture%lu", i];

        _textures[i] = [textureLoader newTextureWithName:textureName
                                            scaleFactor:1.0
                                                 bundle:nil
                                                options:nil
                                                  error:&error];

        if(!_textures[i])
        {
            [NSException raise:NSGenericException
                        format:@"Could not load texture with name %@: %@", textureName, error.localizedDescription];
        }

        _textures[i].label = textureName;
    }
}

/// Creates a resource heap to store texture and buffer object
- (void) createHeap
{
    MTLHeapDescriptor *heapDescriptor = [MTLHeapDescriptor new];

    heapDescriptor.storageMode = MTLStorageModePrivate;
    heapDescriptor.size =  0;

    // Build a descriptor for each texture and calculate size needed to put the texture in the heap

    for(uint32_t i = 0; i < AAPLNumTextures; i++)
    {
        // Create descriptor using the texture's properties and
        MTLTextureDescriptor *descriptor = [AAPLRenderer newDescriptorFromTexture:_textures[i]
                                                                      storageMode:heapDescriptor.storageMode];

        // Determine size of needed from the heap given the descriptor
        MTLSizeAndAlign sizeAndAlign = [_device heapTextureSizeAndAlignWithDescriptor:descriptor];

        // Align the size so that more resources will fit after this texture
        sizeAndAlign.size += (sizeAndAlign.size & (sizeAndAlign.align - 1)) + sizeAndAlign.align;

        // Accumulate the size required for the heap to hold this texture
        heapDescriptor.size += sizeAndAlign.size;
    }

    for(uint32_t i = 0; i < AAPLNumTextures; i++)
    {
        // Create descriptor using the texture's properties and
        MTLTextureDescriptor *descriptor = [AAPLRenderer newDescriptorFromTexture:_textures[i]
                                                                      storageMode:heapDescriptor.storageMode];

        // Determine size of needed from the heap given the descriptor
        MTLSizeAndAlign sizeAndAlign = [_device heapTextureSizeAndAlignWithDescriptor:descriptor];

        // Align the size so that more resources will fit after this texture
        sizeAndAlign.size += (sizeAndAlign.size & (sizeAndAlign.align - 1)) + sizeAndAlign.align;

        // Accumulate the size required for the heap to hold this texture
        heapDescriptor.size += sizeAndAlign.size;
    }

    // Create heap large enough to hold all resources
    _heap = [_device newHeapWithDescriptor:heapDescriptor];
    _heap.label = @"Texture heap";
}

/// Moves texture and buffer data from their original objects to objects in the heap
- (void)moveResorucesToHeap
{
    // Create a command buffer and blit encoder to upload date from original resources to newly created
    // resources from the heap

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Heap Upload Command Buffer";

    id<MTLBlitCommandEncoder> blitEncoder = commandBuffer.blitCommandEncoder;
    blitEncoder.label = @"Heap Transfer Blit Encoder";

    // Create new textures from the heap and copy contents of existing textures into the new textures
    for(uint32_t i = 0; i < AAPLNumTextures; i++)
    {
        // Create descriptor using the texture's properties and
        MTLTextureDescriptor *descriptor = [AAPLRenderer newDescriptorFromTexture:_textures[i]
                                                                      storageMode:_heap.storageMode];

        // Create a texture form the heap
        id<MTLTexture> heapTexture = [_heap newTextureWithDescriptor:descriptor];

        heapTexture.label = _textures[i].label;

        [blitEncoder pushDebugGroup:[NSString stringWithFormat:@"%@ Blits", heapTexture.label]];

        // Blit every slice of every level from the original texture to the texture created from the heap
        MTLRegion region = MTLRegionMake2D(0, 0, _textures[i].width, _textures[i].height);

        for(NSUInteger level = 0; level < _textures[i].mipmapLevelCount;  level++)
        {
            [blitEncoder pushDebugGroup:[NSString stringWithFormat:@"Level %lu Blit", level]];

            for(NSUInteger slice = 0; slice < _textures[i].arrayLength; slice++)
            {
                [blitEncoder copyFromTexture:_textures[i]
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

        // Replace the original texture with our texture from the heap
        _textures[i] = heapTexture;
    }

    [blitEncoder endEncoding];

    [commandBuffer commit];
}

/// Updates non-Metal state for the current frame including updates to uniforms used in shaders
- (void)updateState
{
    AAPLFrameState * frameState = _frameStateBuffer[_inFlightIndex].contents;

    _blendTheta += 0.025;
    frameState->quadScale = _quadScale;

    vector_float2 halfGridDimensions = { 0.5 *AAPLGridWidth, 0.5 * AAPLGridHeight };

    // Calculate the position of the lower-left vertex of the upper-left quad
    frameState->offset.x = AAPLQuadSpacing * _quadScale.x * (halfGridDimensions.x-1);
    frameState->offset.y = AAPLQuadSpacing * _quadScale.y * -halfGridDimensions.y;


    // Calculate a blend factor between 0 and 1.  Using a sinusoidal equation makes the transiton
    //   period quicker and the a single unblended image on the quad for longer (i.e. we move
    //   quickly through a blend factor of 0.5 where the two textures are presented equally)
    frameState->slideFactor = (cosf(_blendTheta+M_PI)+1.0)/2.0;

    frameState->textureIndexOffset = _textureIndexOffset;

    if(_blendTheta >= M_PI)
    {
        _blendTheta = 0;
        _textureIndexOffset++;
    }
}

/// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view
{
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    CGSize size = view.drawableSize;
    size = size;
    _inFlightIndex = (_inFlightIndex + 1) % AAPLMaxBuffersInFlight;

    [self updateState];

    // Create a new command buffer for each render pass to the current drawable
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Per Frame Commands";

    {
        id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
        computeEncoder.label = @"Per Frame Compute Commands";

        [computeEncoder setComputePipelineState:_computePipeline];

        [computeEncoder setBuffer:_sourceTextures
                           offset:0
                          atIndex:AAPLComputeBufferIndexSourceTextures];

        [computeEncoder  setBuffer:_frameStateBuffer[_inFlightIndex]
                             offset:0
                            atIndex:AAPLComputeBufferIndexFrameState];

        [computeEncoder setBuffer:_instanceParameters
                           offset:0
                           atIndex:AAPLComputeBufferIndexInstanceParams];

        [computeEncoder dispatchThreadgroups:_threadgroupCount
                       threadsPerThreadgroup:_threadgroupSize];

        [computeEncoder endEncoding];
    }

    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    if(renderPassDescriptor != nil)
    {
        // Create a render command encoder so we can render into something
        id<MTLRenderCommandEncoder> renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"Per Frame Rendering";

        // Make a single useHeap call instead of one useResource call per texture and per buffer,
        //   since all buffers have been moved memory in a heap
        [renderEncoder useHeap:_heap];

        [renderEncoder setRenderPipelineState:_renderPipeline];

        [renderEncoder setVertexBuffer:_vertexBuffer
                                offset:0
                               atIndex:AAPLVertexBufferIndexVertices];

        [renderEncoder setVertexBuffer:_frameStateBuffer[_inFlightIndex]
                                  offset:0
                                 atIndex:AAPLVertexBufferIndexFrameState];

        [renderEncoder setVertexBuffer:_instanceParameters
                                offset:0
                               atIndex:AAPLVertexBufferIndexInstanceParams];

        [renderEncoder setFragmentBuffer:_instanceParameters
                                  offset:0
                                 atIndex:AAPLFragmentBufferIndexInstanceParams];

        [renderEncoder setFragmentBuffer:_frameStateBuffer[_inFlightIndex]
                                  offset:0
                                 atIndex:AAPLFragmentBufferIndexFrameState];

        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:6
                        instanceCount:AAPLNumInstances];

        [renderEncoder endEncoding];

        // Schedule a present once the framebuffer is complete using the current drawable
        [commandBuffer presentDrawable:view.currentDrawable];
    }

    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
     {
         dispatch_semaphore_signal(block_sema);
     }];

    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];

    [commandBuffer waitUntilCompleted];
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Calculate scale for quads so that they are always square when working with the default
    // viewport and sending down clip space corrdinates.

    if(size.width < size.height)
    {
        _quadScale.x = 1.0;
        _quadScale.y = (float)size.width / (float)size.height;
    }
    else
    {
        _quadScale.x = (float)size.height / (float)size.width;
        _quadScale.y = 1.0;
    }
}

@end

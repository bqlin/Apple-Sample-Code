/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per frame rendering
*/
@import simd;
@import MetalKit;

#import "AAPLRenderer.h"

// Include header shared between C code here, which executes Metal API commands, and .metal files
#import "AAPLShaderTypes.h"

// The max number of frames in flight
static const NSUInteger AAPLMaxFramesInFlight = 3;

// Main class performing the rendering
@implementation AAPLRenderer
{
    dispatch_semaphore_t _inFlightSemaphore;

    id<MTLDevice> _device;

    id<MTLCommandQueue> _commandQueue;

    // Array of Metal buffers storing vertex data for each rendered object
    id<MTLBuffer> _vertexBuffer[AAPLNumObjects];

    // The Metal buffer storing per object parameters for each rendered object
    id<MTLBuffer> _objectParameters;

    // The Metal buffers storing per frame uniform data
    id<MTLBuffer> _frameStateBuffer[AAPLMaxFramesInFlight];

    // Render pipeline executinng indirect command buffer
    id<MTLRenderPipelineState> _renderPipelineState;

    // When using an indirect command buffer encoded by the CPU, buffer updated by the CPU must be
    // blit into a seperate buffer that is set in the indirect command buffer.
    id<MTLBuffer> _indirectFrameStateBuffer;

    // Index into per frame uniforms to use for the current frame
    NSUInteger _inFlightIndex;

    // Number of frames rendered
    NSUInteger _frameNumber;

    // The indirect command buffer encoded and executed
    id<MTLIndirectCommandBuffer> _indirectCommandBuffer;

    vector_float2 _aspectScale;
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device.  We'll also use this
/// mtkView object to set the pixel format and other properties of our drawable
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];

    if(self)
    {
        mtkView.clearColor = MTLClearColorMake(0.0, 0.0, 0.5, 1.0f);

        _device = mtkView.device;

        _inFlightSemaphore = dispatch_semaphore_create(AAPLMaxFramesInFlight);

        // Create the command queue
        _commandQueue = [_device newCommandQueue];

        // Load the shaders from default library
        id <MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
        id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
        id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

        mtkView.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
        mtkView.sampleCount = 1;

        // Create a reusable pipeline state
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"MyPipeline";
        pipelineStateDescriptor.sampleCount = mtkView.sampleCount;
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
        pipelineStateDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat;
        // Needed for this pipeline state to be used in indirect command buffers.
        pipelineStateDescriptor.supportIndirectCommandBuffers = TRUE;

        NSError *error = nil;
        _renderPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];

        NSAssert(_renderPipelineState, @"Failed to create pipeline state: %@", error);

        for(int objectIdx = 0; objectIdx < AAPLNumObjects; objectIdx++)
        {
            // Choose parameters to generate a mesh for this object so that each mesh is unique
            // and looks diffent than the mesh it's next to in the grid drawn
            uint32_t numTeeth = (objectIdx < 8) ? objectIdx + 3 : objectIdx * 3;

            // Create a vertex buffer, and initialize it with a unique 2D gear mesh
            _vertexBuffer[objectIdx] = [self newGearMeshWithNumTeeth:numTeeth];

            _vertexBuffer[objectIdx].label = [[NSString alloc] initWithFormat:@"Object %i Buffer", objectIdx];
        }

        /// Create and fill array containing parameters for each object

        NSUInteger objectParameterArraySize = AAPLNumObjects * sizeof(AAPLObjectPerameters);

        _objectParameters = [_device newBufferWithLength:objectParameterArraySize options:0];

        _objectParameters.label = @"Object Parameters Array";

        AAPLObjectPerameters *params = _objectParameters.contents;

        static const vector_float2 gridDimensions = { AAPLGridWidth, AAPLGridHeight };

        const vector_float2 offset = (AAPLObjecDistance / 2.0) * (gridDimensions-1);

        for(int objectIdx = 0; objectIdx < AAPLNumObjects; objectIdx++)
        {
            // Calculate position of each object such that each occupies a space in a grid
            vector_float2 gridPos = (vector_float2){objectIdx % AAPLGridWidth, objectIdx / AAPLGridWidth};
            vector_float2 position = -offset + gridPos * AAPLObjecDistance;

            // Write the position of each object to the object parameter buffer
            params[objectIdx].position = position;
        }

        for(int i = 0; i < AAPLMaxFramesInFlight; i++)
        {
            _frameStateBuffer[i] = [_device newBufferWithLength:sizeof(AAPLFrameState)
                                                        options:MTLResourceStorageModeShared];

            _frameStateBuffer[i].label = [NSString stringWithFormat:@"Frame state buffer %d", i];
        }

        // When encoding commands with the CPU, the app sets this indirect frame state buffer
        // dynamically in the indirect command buffer.   Each frame data will be blit from the
        // _frameStateBuffer that has just been updated by the CPU to this buffer.  This allow
        // a synchronous update of values set by the CPU.
        _indirectFrameStateBuffer = [_device newBufferWithLength:sizeof(AAPLFrameState)
                                                         options:MTLResourceStorageModePrivate];

        _indirectFrameStateBuffer.label = @"Indirect Frame State Buffer";

        MTLIndirectCommandBufferDescriptor* icbDescriptor = [MTLIndirectCommandBufferDescriptor new];

        // Indicate that the only draw commands will be standard (non-indexed) draw commands.
        icbDescriptor.commandTypes = MTLIndirectCommandTypeDraw;

        // Indicate that buffers will be set for each command IN the indirect command buffer.
        icbDescriptor.inheritBuffers = NO;

        // Indicate that a max of 3 buffers will be set for each command.
        icbDescriptor.maxVertexBufferBindCount = 3;
        icbDescriptor.maxFragmentBufferBindCount = 0;

#if defined TARGET_MACOS || defined(__IPHONE_13_0)
        // Indicate that the render pipeline state object will be set in the render command encoder
        // (not by the indirect command buffer).
        // On iOS, this property only exists on iOS 13 and later.  It defaults to YES in earlier
        // versions
        if (@available(iOS 13.0, *)) {
            icbDescriptor.inheritPipelineState = YES;
        }
#endif

        _indirectCommandBuffer = [_device newIndirectCommandBufferWithDescriptor:icbDescriptor
                                                                 maxCommandCount:AAPLNumObjects
                                                                         options:0];

        _indirectCommandBuffer.label = @"Scene ICB";

        //  Encode a draw command for each object drawn in the indirect command buffer.
        for (int objIndex = 0; objIndex < AAPLNumObjects; objIndex++)
        {
            id<MTLIndirectRenderCommand> ICBCommand =
                [_indirectCommandBuffer indirectRenderCommandAtIndex:objIndex];

            [ICBCommand setVertexBuffer:_vertexBuffer[objIndex]
                                 offset:0
                                atIndex:AAPLVertexBufferIndexVertices];

            [ICBCommand setVertexBuffer:_indirectFrameStateBuffer
                                 offset:0
                                atIndex:AAPLVertexBufferIndexFrameState];

            [ICBCommand setVertexBuffer:_objectParameters
                                 offset:0
                                atIndex:AAPLVertexBufferIndexObjectParams];

            const NSUInteger vertexCount = _vertexBuffer[objIndex].length/sizeof(AAPLVertex);

            [ICBCommand drawPrimitives:MTLPrimitiveTypeTriangle
                           vertexStart:0
                           vertexCount:vertexCount
                         instanceCount:1
                          baseInstance:objIndex];
        }
    }

    return self;
}

/// Create a Metal buffer containing a 2D "gear" mesh
- (id<MTLBuffer>)newGearMeshWithNumTeeth:(uint32_t)numTeeth
{
    NSAssert(numTeeth >= 3, @"Can only build a gear with at least 3 teeth");

    static const float innerRatio = 0.8;
    static const float toothWidth = 0.25;
    static const float toothSlope = 0.2;

    // For each tooth, this function generates 2 triangles for tooth itself, 1 triangle to fill
    // the inner portion of the gear from bottom of the tooth to the center of the gear,
    // and 1 triangle to fill the inner portion of the gear below the groove beside the tooth.
    // Hence, the buffer needs 4 triangles or 12 vertices for each tooth.
    uint32_t numVertices = numTeeth * 12;
    uint32_t bufferSize = sizeof(AAPLVertex) * numVertices;
    id<MTLBuffer> metalBuffer = [_device newBufferWithLength:bufferSize options:0];
    metalBuffer.label = [[NSString alloc] initWithFormat:@"%d Toothed Cog Vertices", numTeeth];

    AAPLVertex *meshVertices = (AAPLVertex *)metalBuffer.contents;

    const double angle = 2.0*M_PI/(double)numTeeth;
    static const packed_float2 origin = (packed_float2){0.0, 0.0};
    int vtx = 0;

    // Build triangles for teeth of gear
    for(int tooth = 0; tooth < numTeeth; tooth++)
    {
        // Calculate angles for tooth and groove
        const float toothStartAngle = tooth * angle;
        const float toothTip1Angle  = (tooth+toothSlope) * angle;
        const float toothTip2Angle  = (tooth+toothSlope+toothWidth) * angle;;
        const float toothEndAngle   = (tooth+2*toothSlope+toothWidth) * angle;
        const float nextToothAngle  = (tooth+1.0) * angle;

        // Calculate positions of vertices needed for the tooth
        const packed_float2 groove1    = { sin(toothStartAngle)*innerRatio, cos(toothStartAngle)*innerRatio };
        const packed_float2 tip1       = { sin(toothTip1Angle), cos(toothTip1Angle) };
        const packed_float2 tip2       = { sin(toothTip2Angle), cos(toothTip2Angle) };
        const packed_float2 groove2    = { sin(toothEndAngle)*innerRatio, cos(toothEndAngle)*innerRatio };
        const packed_float2 nextGroove = { sin(nextToothAngle)*innerRatio, cos(nextToothAngle)*innerRatio };

        // Right top triangle of tooth
        meshVertices[vtx].position = groove1;
        meshVertices[vtx].texcoord = (groove1 + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = tip1;
        meshVertices[vtx].texcoord = (tip1 + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = tip2;
        meshVertices[vtx].texcoord = (tip2 + 1.0) / 2.0;
        vtx++;

        // Left bottom triangle of tooth
        meshVertices[vtx].position = groove1;
        meshVertices[vtx].texcoord = (groove1 + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = tip2;
        meshVertices[vtx].texcoord = (tip2 + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = groove2;
        meshVertices[vtx].texcoord = (groove2 + 1.0) / 2.0;
        vtx++;

        // Slice of circle from bottom of tooth to center of gear
        meshVertices[vtx].position = origin;
        meshVertices[vtx].texcoord = (origin + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = groove1;
        meshVertices[vtx].texcoord = (groove1 + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = groove2;
        meshVertices[vtx].texcoord = (groove2 + 1.0) / 2.0;
        vtx++;

        // Slice of circle from the groove to the center of gear
        meshVertices[vtx].position = origin;
        meshVertices[vtx].texcoord = (origin + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = groove2;
        meshVertices[vtx].texcoord = (groove2 + 1.0) / 2.0;
        vtx++;

        meshVertices[vtx].position = nextGroove;
        meshVertices[vtx].texcoord = (nextGroove + 1.0) / 2.0;
        vtx++;
    }

    return metalBuffer;
}


/// Updates non-Metal state for the current frame including updates to uniforms used in shaders
- (void)updateState
{
    _frameNumber++;

    _inFlightIndex = _frameNumber % AAPLMaxFramesInFlight;

    AAPLFrameState * frameState = _frameStateBuffer[_inFlightIndex].contents;

    frameState->aspectScale = _aspectScale;
}

/// Called whenever view changes orientation or layout is changed
- (void) mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Calculate scale for quads so that they are always square when working with the default
    // viewport and sending down clip space corrdinates.

    _aspectScale.x = (float)size.height / (float)size.width;
    _aspectScale.y = 1.0;
}

/// Called whenever the view needs to render
- (void) drawInMTKView:(nonnull MTKView *)view
{
    // Wait to ensure only AAPLMaxFramesInFlight are getting processed by any stage in the Metal
    //   pipeline (App, Metal, Drivers, GPU, etc)
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    [self updateState];

    // Create a new command buffer for each render pass to the current drawable
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Frame Command Buffer";

    // Add completion hander which signals _inFlightSemaphore when Metal and the GPU has fully
    // finished processing the commands encoded this frame.  This indicates when the dynamic
    // _frameStateBuffer, that written by the CPU in this frame, has been read by Metal and the GPU
    // meaning we can change the buffer contents without corrupting the rendering
    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
     {
         dispatch_semaphore_signal(block_sema);
     }];

    /// Encode blit commands to update the buffer holding the frame state.
    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];

    [blitEncoder copyFromBuffer:_frameStateBuffer[_inFlightIndex] sourceOffset:0
                       toBuffer:_indirectFrameStateBuffer destinationOffset:0
                           size:_indirectFrameStateBuffer.length];

    [blitEncoder endEncoding];

    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    // If we've gotten a renderPassDescriptor we can render to the drawable, otherwise we'll skip
    //   any rendering this frame because we have no drawable to draw to
    if(renderPassDescriptor != nil)
    {
        // Create a render command encoder so we can render into something
        id <MTLRenderCommandEncoder> renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"Main Render Encoder";

        [renderEncoder setCullMode:MTLCullModeBack];

        [renderEncoder setRenderPipelineState:_renderPipelineState];

        // Make a useResource call for each buffer needed by the indirect command buffer.
        for (int i = 0; i < AAPLNumObjects; i++)
        {
            [renderEncoder useResource:_vertexBuffer[i] usage:MTLResourceUsageRead];
        }

        [renderEncoder useResource:_objectParameters usage:MTLResourceUsageRead];

        [renderEncoder useResource:_indirectFrameStateBuffer usage:MTLResourceUsageRead];

        // Draw everything in the indirect command buffer.
        [renderEncoder executeCommandsInBuffer:_indirectCommandBuffer withRange:NSMakeRange(0, AAPLNumObjects)];

        // We're done encoding commands
        [renderEncoder endEncoding];

        // Schedule a present once the framebuffer is complete using the current drawable
        [commandBuffer presentDrawable:view.currentDrawable];
    }

    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
}

@end

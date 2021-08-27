/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per frame rendering
*/
@import MetalKit;

#import <simd/simd.h>
#import "AAPLRenderer.h"

// Include header shared between C code here, which executes Metal API commands, and .metal files
#import "AAPLShaderTypes.h"

#define MOVE_GRID 1

// The max number of frames in flight
static const NSUInteger AAPLMaxFramesInFlight = 3;

typedef enum AAPLMovementDirection {
    AAPLMovementDirectionRight,
    AAPLMovementDirectionUp,
    AAPLMovementDirectionLeft,
    AAPLMovementDirectionDown,
} AAPLMovementDirection;

// Main class performing the rendering
@implementation AAPLRenderer
{
    dispatch_semaphore_t _inFlightSemaphore;

    id<MTLDevice> _device;

    id<MTLCommandQueue> _commandQueue;

    // Array of Metal buffers storing vertex data for each rendered object
    // If using a single combined buffer to store all mesh this will be an array of size 1
    id<MTLBuffer> _vertexBuffer;

    // The Metal buffer storing per object parameters for each rendered object
    id<MTLBuffer> _objectParameters;

    // The Metal buffers storing per frame uniform data
    id<MTLBuffer> _frameStateBuffer[AAPLMaxFramesInFlight];

    // Render pipeline executinng indirect command buffer
    id<MTLRenderPipelineState> _renderPipelineState;

    // Compute pipeline used to build indirect command buffer when we do culling on GPU
    id<MTLComputePipelineState> _computePipelineState;

    // Argument buffer containing the indirect command buffer encoded in the kernel
    id<MTLBuffer> _icbArgumentBuffer;

    // Index into per frame uniforms to use for the current frame
    NSUInteger _inFlightIndex;

    // Number of frames rendered
    NSUInteger _frameNumber;

    // The indirect command buffer encoded and executed
    id<MTLIndirectCommandBuffer> _indirectCommandBuffer;

    // Variables affecting position of objects in scene
    vector_float2         _gridCenter;
    float                 _movementSpeed;
    AAPLMovementDirection _objectDirection;

    vector_float2 _aspectScale;
}

typedef struct AAPLObjectMesh {
    AAPLVertex *vertices;
    uint32_t numVerts;
} AAPLObjectMesh;

/// Initialize with the MetalKit view from which we'll obtain our Metal device.  We'll also use this
/// mtkView object to set the pixel format and other properties of our drawable
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        NSError *error;

        mtkView.clearColor = MTLClearColorMake(0.0, 0.0, 0.5, 1.0f);

        _device = mtkView.device;

        // Initialize ivars affecting object position
        _gridCenter      = (vector_float2){ 0.0, 0.0 };
        _movementSpeed   = 0.15;
        _objectDirection = AAPLMovementDirectionUp;

        _inFlightSemaphore = dispatch_semaphore_create(AAPLMaxFramesInFlight);

        // Create the command queue
        _commandQueue = [_device newCommandQueue];

        // Load the shaders from default library
        id <MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
        id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
        id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

        mtkView.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
        mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
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

        _renderPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];

        NSAssert(_renderPipelineState, @"Failed to create pipeline state: %@", error);

        id<MTLFunction> GPUCommandEncodingKernel = [defaultLibrary newFunctionWithName:@"cullMeshesAndEncodeCommands"];
        _computePipelineState = [_device newComputePipelineStateWithFunction:GPUCommandEncodingKernel
                                                                       error:&error];

        NSAssert(_computePipelineState ,@"Failed to create compute pipeline state: %@", error);

        // Generate gear mesh data in malloced memory to later copy into a single Metal buffer
        AAPLObjectMesh *tempMeshes;
        {
            tempMeshes = malloc(sizeof(AAPLObjectMesh)*AAPLNumObjects);

            for(int objectIdx = 0; objectIdx < AAPLNumObjects; objectIdx++)
            {
                // Choose the parameters to generate a mesh so that each one is unique.
                uint32_t numTeeth = random() % 50 + 3;
                float innerRatio = 0.2 + (random() / (1.0 * RAND_MAX)) * 0.7;
                float toothWidth = 0.1 + (random() / (1.0 * RAND_MAX)) * 0.4;
                float toothSlope = (random() / (1.0 * RAND_MAX)) * 0.2;

                // Create a vertex buffer and initialize it with a unique 2D gear mesh.
                tempMeshes[objectIdx] = [self newGearMeshWithNumTeeth:numTeeth
                                                           innerRatio:innerRatio
                                                           toothWidth:toothWidth
                                                           toothSlope:toothSlope];
            }
        }

        // Create and fill array containing parameters for each object
        {
            NSUInteger objectParameterArraySize = AAPLNumObjects * sizeof(AAPLObjectPerameters);

            _objectParameters = [_device newBufferWithLength:objectParameterArraySize options:0];

            _objectParameters.label = @"Object Parameters Array";
        }

        // Create a single buffer with vertices for all gears
        {
            size_t bufferSize = 0;

            for(int objectIdx = 0; objectIdx < AAPLNumObjects; objectIdx++)
            {
                size_t meshSize = sizeof(AAPLVertex) * tempMeshes[objectIdx].numVerts;
                bufferSize += meshSize;
            }

            _vertexBuffer = [_device newBufferWithLength:bufferSize options:0];

            _vertexBuffer.label = @"Combined Vertex Buffer";
        }

        // Copy each mesh's data into the vertex buffer
        {
            uint32_t currentStartVertex = 0;

            AAPLObjectPerameters *params = _objectParameters.contents;

            for(int objectIdx = 0; objectIdx < AAPLNumObjects; objectIdx++)
            {
                // Store the mesh metadata in the `params` buffer.

                params[objectIdx].numVertices = tempMeshes[objectIdx].numVerts;

                size_t meshSize = sizeof(AAPLVertex) * tempMeshes[objectIdx].numVerts;

                params[objectIdx].startVertex = currentStartVertex;

                // Pack the current mesh data in the combined vertex buffer.

                AAPLVertex* meshStartAddress = ((AAPLVertex*)_vertexBuffer.contents) + currentStartVertex;

                memcpy(meshStartAddress, tempMeshes[objectIdx].vertices, meshSize);

                currentStartVertex += tempMeshes[objectIdx].numVerts;

                free(tempMeshes[objectIdx].vertices);

                // Set the other culling and mesh rendering parameters.

                // Set the position of each object to a unique space in a grid.
                vector_float2 gridPos = (vector_float2){objectIdx % AAPLGridWidth, objectIdx / AAPLGridWidth};
                params[objectIdx].position = gridPos * AAPLObjecDistance;

                params[objectIdx].boundingRadius = AAPLObjectSize / 2.0;
            }
        }

        free(tempMeshes);


        // Create buffers to contain dynamic shader data

        for(int i = 0; i < AAPLMaxFramesInFlight; i++)
        {
            _frameStateBuffer[i] = [_device newBufferWithLength:sizeof(AAPLFrameState)
                                                                  options:MTLResourceStorageModeShared];

            _frameStateBuffer[i].label = [NSString stringWithFormat:@"Frame state buffer %d", i];
        }

        MTLIndirectCommandBufferDescriptor* icbDescriptor = [MTLIndirectCommandBufferDescriptor new];
        
        // Only standard (non-indexed) draw commands are allowed.
        icbDescriptor.commandTypes = MTLIndirectCommandTypeDraw;

        // Indicate that buffers will be set for each command in the indirect command buffer.
        icbDescriptor.inheritBuffers = NO;

        // Indicate that a maximum of 3 buffers will be set for each command.
        icbDescriptor.maxVertexBufferBindCount = 3;
        icbDescriptor.maxFragmentBufferBindCount = 0;

#if defined TARGET_MACOS || defined(__IPHONE_13_0)
        // Indicate that the render pipeline state object will be set in the render command encoder
        // (not by the indirect command buffer).
        // On iOS, this property only exists on iOS 13 and later.  Earlier versions of iOS did not
        // support settings pipelinestate within an indirect command buffer, so indirect command
        // buffers always inherited the pipeline state.
        if (@available(iOS 13.0, *)) {
            icbDescriptor.inheritPipelineState = YES;
        }
#endif

        // Create indirect command buffer using private storage mode; since only the GPU will
        // write to and read from the indirect command buffer, the CPU never needs to access the
        // memory
        _indirectCommandBuffer = [_device newIndirectCommandBufferWithDescriptor:icbDescriptor
                                                                 maxCommandCount:AAPLNumObjects
                                                                         options:MTLResourceStorageModePrivate];
        _indirectCommandBuffer.label = @"Scene ICB";


        id<MTLArgumentEncoder> argumentEncoder =
            [GPUCommandEncodingKernel newArgumentEncoderWithBufferIndex:AAPLKernelBufferIndexCommandBufferContainer];

        _icbArgumentBuffer = [_device newBufferWithLength:argumentEncoder.encodedLength
                                               options:MTLResourceStorageModeShared];
        _icbArgumentBuffer.label = @"ICB Argument Buffer";

        [argumentEncoder setArgumentBuffer:_icbArgumentBuffer offset:0];

        [argumentEncoder setIndirectCommandBuffer:_indirectCommandBuffer
                                          atIndex:AAPLArgumentBufferIDCommandBuffer];
    }
    return self;
}

/// Create a Metal buffer containing a 2D "gear" mesh
- (AAPLObjectMesh)newGearMeshWithNumTeeth:(uint32_t)numTeeth
                               innerRatio:(float)innerRatio
                               toothWidth:(float)toothWidth
                               toothSlope:(float)toothSlope
{
    NSAssert(numTeeth >= 3, @"Can only build a gear with at least 3 teeth");
    NSAssert(toothWidth + 2 * toothSlope < 1.0, @"Configuration of gear invalid");

    AAPLObjectMesh mesh;

    // For each tooth, this function generates 2 triangles for tooth itself, 1 triangle to fill
    // the inner portion of the gear from bottom of the tooth to the center of the gear,
    // and 1 triangle to fill the inner portion of the gear below the groove beside the tooth.
    // Hence, the buffer needs 4 triangles or 12 vertices for each tooth.
    uint32_t numVertices = numTeeth * 12;
    uint32_t bufferSize = sizeof(AAPLVertex) * numVertices;

    mesh.numVerts = numVertices;
    mesh.vertices = (AAPLVertex*)malloc(bufferSize);

    const double angle = 2.0*M_PI/(double)numTeeth;
    static const packed_float2 origin = (packed_float2){0.0, 0.0};
    uint32_t vtx = 0;

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
        mesh.vertices[vtx].position = groove1;
        mesh.vertices[vtx].texcoord = (groove1 + 1.0) / 2.0;
        vtx++;

        mesh.vertices[vtx].position = tip1;
        mesh.vertices[vtx].texcoord = (tip1 + 1.0) / 2.0;
        vtx++;

        mesh.vertices[vtx].position = tip2;
        mesh.vertices[vtx].texcoord = (tip2 + 1.0) / 2.0;
        vtx++;

        // Left bottom triangle of tooth
        mesh.vertices[vtx].position = groove1;
        mesh.vertices[vtx].texcoord = (groove1 + 1.0) / 2.0;
        vtx++;

        mesh.vertices[vtx].position = tip2;
        mesh.vertices[vtx].texcoord = (tip2 + 1.0) / 2.0;
        vtx++;

        mesh.vertices[vtx].position = groove2;
        mesh.vertices[vtx].texcoord = (groove2 + 1.0) / 2.0;
        vtx++;

        // Slice of circle from bottom of tooth to center of gear
        mesh.vertices[vtx].position = origin;
        mesh.vertices[vtx].texcoord = (origin + 1.0) / 2.0;
        vtx++;

        mesh.vertices[vtx].position = groove1;
        mesh.vertices[vtx].texcoord = (groove1 + 1.0) / 2.0;
        vtx++;

        mesh.vertices[vtx].position = groove2;
        mesh.vertices[vtx].texcoord = (groove2 + 1.0) / 2.0;
        vtx++;

        // Slice of circle from the groove to the center of gear
        mesh.vertices[vtx].position = origin;
        mesh.vertices[vtx].texcoord = (origin + 1.0) / 2.0;
        vtx++;

        mesh.vertices[vtx].position = groove2;
        mesh.vertices[vtx].texcoord = (groove2 + 1.0) / 2.0;
        vtx++;

        mesh.vertices[vtx].position = nextGroove;
        mesh.vertices[vtx].texcoord = (nextGroove + 1.0) / 2.0;
        vtx++;
    }

    return mesh;
}

/// Updates non-Metal state for the current frame including updates to uniforms used in shaders
- (void)updateState
{
    _frameNumber++;

    _inFlightIndex = _frameNumber % AAPLMaxFramesInFlight;

    _movementSpeed = .15;

    static const float rightBounds =  AAPLObjecDistance * AAPLGridWidth  / 2.0;
    static const float leftBounds  = -AAPLObjecDistance * AAPLGridWidth  / 2.0;
    static const float upperBounds =  AAPLObjecDistance * AAPLGridHeight / 2.0;
    static const float lowerBounds = -AAPLObjecDistance * AAPLGridHeight / 2.0;

    // Check if we've moved outside the grid boundaries and reverse direction if we have
    if(_gridCenter.x < leftBounds ||
       _gridCenter.x > rightBounds ||
       _gridCenter.y < lowerBounds ||
       _gridCenter.y > upperBounds)
    {
        _objectDirection = (_objectDirection + 2) % 4;
    }
    else if(_frameNumber % 300 == 0)
    {
        _objectDirection = random() % 4;
    }

#if MOVE_GRID
    switch(_objectDirection)
    {
        case AAPLMovementDirectionRight:
            _gridCenter.x += _movementSpeed;
            break;
        case AAPLMovementDirectionUp:
            _gridCenter.y += _movementSpeed;
            break;
        case AAPLMovementDirectionLeft:
            _gridCenter.x -= _movementSpeed;
            break;
        case AAPLMovementDirectionDown:
            _gridCenter.y -= _movementSpeed;
            break;
    }
#endif

    static const vector_float2 gridDimensions = { AAPLGridWidth, AAPLGridHeight };

    AAPLFrameState * frameState = _frameStateBuffer[_inFlightIndex].contents;

    frameState->aspectScale = _aspectScale;

    const vector_float2 viewOffset = (AAPLObjecDistance / 2.0) * (gridDimensions-1);

    // Calculate the position of the center of the lower-left object
    frameState->translation = _gridCenter - viewOffset;
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
    // pipeline (App, Metal, Drivers, GPU, etc)
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    [self updateState];

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
    
    
    // Encode command to reset the indirect command buffer
    {
        id<MTLBlitCommandEncoder> resetBlitEncoder = [commandBuffer blitCommandEncoder];
        resetBlitEncoder.label = @"Reset ICB Blit Encoder";
        
        [resetBlitEncoder resetCommandsInBuffer:_indirectCommandBuffer
                                      withRange:NSMakeRange(0, AAPLNumObjects)];
        
        [resetBlitEncoder endEncoding];
    }

    
    // Encode commands to determine visibility of objects using a compute kernel
    {
        id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
        computeEncoder.label = @"Object Visibility Kernel";
        
        [computeEncoder setComputePipelineState:_computePipelineState];
        
        [computeEncoder setBuffer:_frameStateBuffer[_inFlightIndex] offset:0 atIndex:AAPLKernelBufferIndexFrameState];
        [computeEncoder setBuffer:_objectParameters offset:0 atIndex:AAPLKernelBufferIndexObjectParams];
        [computeEncoder setBuffer:_vertexBuffer offset:0 atIndex:AAPLKernelBufferIndexVertices];
        [computeEncoder setBuffer:_icbArgumentBuffer offset:0 atIndex:AAPLKernelBufferIndexCommandBufferContainer];
        
        // Call useResource on '_indirectCommandBuffer' which indicates to Metal that the kernel will
        // access '_indirectCommandBuffer'.  It is necessary because the app cannot directly set
        // '_indirectCommandBuffer' in 'computeEncoder', but, rather, must pass it to the kernel via
        // an argument buffer which indirectly contains '_indirectCommandBuffer'.
        
        [computeEncoder useResource:_indirectCommandBuffer usage:MTLResourceUsageWrite];
        
        NSUInteger threadExecutionWidth = _computePipelineState.threadExecutionWidth;
        
        [computeEncoder dispatchThreads:MTLSizeMake(AAPLNumObjects, 1, 1)
                  threadsPerThreadgroup:MTLSizeMake(threadExecutionWidth, 1, 1)];
        
        [computeEncoder endEncoding];
    }

    // Encode command to optimize the indirect command buffer after encoding
    {
        id<MTLBlitCommandEncoder> optimizeBlitEncoder = [commandBuffer blitCommandEncoder];
        optimizeBlitEncoder.label = @"Optimize ICB Blit Encoder";
        
        [optimizeBlitEncoder optimizeIndirectCommandBuffer:_indirectCommandBuffer
                                                 withRange:NSMakeRange(0, AAPLNumObjects)];
        
        [optimizeBlitEncoder endEncoding];
    }
    
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    // If we've gotten a renderPassDescriptor we can render to the drawable, otherwise we'll skip
    // any rendering this frame because we have no drawable to draw to
    if(renderPassDescriptor != nil)
    {
        id <MTLRenderCommandEncoder> renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"Main Render Encoder";

        [renderEncoder setCullMode:MTLCullModeBack];

        [renderEncoder setRenderPipelineState:_renderPipelineState];

        // Make a useResource call for each buffer needed by the indirect command buffer
        [renderEncoder useResource:_vertexBuffer usage:MTLResourceUsageRead];

        [renderEncoder useResource:_objectParameters usage:MTLResourceUsageRead];

        [renderEncoder useResource:_frameStateBuffer[_inFlightIndex] usage:MTLResourceUsageRead];

        // Draw everything in the indirect command buffer
        [renderEncoder executeCommandsInBuffer:_indirectCommandBuffer withRange:NSMakeRange(0, AAPLNumObjects)];

        [renderEncoder endEncoding];

#if TARGET_IOS
        // Present drawable to screen only after previous drawable has been on screen for a
        // mimimum of 16ms to achieve a smooth framerate of 60 FPS.  This prevents jittering on
        // devices with ProMotion displays that support a variable refresh rate from 120 to 30 FPS.
        [commandBuffer presentDrawable:view.currentDrawable
                  afterMinimumDuration:0.02];
#else
        [commandBuffer presentDrawable:view.currentDrawable];
#endif
    }

    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
}

@end

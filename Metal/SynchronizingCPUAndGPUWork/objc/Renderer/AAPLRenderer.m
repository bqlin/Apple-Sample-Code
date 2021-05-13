/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation for a renderer class that performs Metal setup and per-frame rendering.
*/

@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLTriangle.h"
#import "AAPLShaderTypes.h"

// The maximum number of frames in flight.
static const NSUInteger MaxFramesInFlight = 3;

// The number of triangles in the scene, determined to fit the screen.
static const NSUInteger NumTriangles = 50;

// The main class performing the rendering.
@implementation AAPLRenderer
{
    // A semaphore used to ensure that buffers read by the GPU are not simultaneously written by the CPU.
    dispatch_semaphore_t _inFlightSemaphore;

    // A series of buffers containing dynamically-updated vertices.
    id<MTLBuffer> _vertexBuffers[MaxFramesInFlight];

    // The index of the Metal buffer in _vertexBuffers to write to for the current frame.
    NSUInteger _currentBuffer;

    id<MTLDevice> _device;

    id<MTLCommandQueue> _commandQueue;

    id<MTLRenderPipelineState> _pipelineState;

    vector_uint2 _viewportSize;

    NSArray<AAPLTriangle*> *_triangles;

    NSUInteger _totalVertexCount;

    float _wavePosition;
}

/// Initializes the renderer with the MetalKit view from which you obtain the Metal device.
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        _device = mtkView.device;

        _inFlightSemaphore = dispatch_semaphore_create(MaxFramesInFlight);

        // Load all the shader files with a metal file extension in the project.
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

        // Load the vertex shader.
        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];

        // Load the fragment shader.
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

        // Create a reusable pipeline state object.
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"MyPipeline";
        pipelineStateDescriptor.sampleCount = mtkView.sampleCount;
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
        pipelineStateDescriptor.vertexBuffers[AAPLVertexInputIndexVertices].mutability = MTLMutabilityImmutable;

        NSError *error;

        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        
        NSAssert(_pipelineState, @"Failed to create pipeline state: %@", error);
        
        // Create the command queue.
        _commandQueue = [_device newCommandQueue];

        // Generate the triangles rendered by the app.
        [self generateTriangles];

        // Calculate vertex data and allocate vertex buffers.
        const NSUInteger triangleVertexCount = [AAPLTriangle vertexCount];
        _totalVertexCount = triangleVertexCount * _triangles.count;
        const NSUInteger triangleVertexBufferSize = _totalVertexCount * sizeof(AAPLVertex);

        for(NSUInteger bufferIndex = 0; bufferIndex < MaxFramesInFlight; bufferIndex++)
        {
            _vertexBuffers[bufferIndex] = [_device newBufferWithLength:triangleVertexBufferSize
                                                               options:MTLResourceStorageModeShared];
            _vertexBuffers[bufferIndex].label = [NSString stringWithFormat:@"Vertex Buffer #%lu", (unsigned long)bufferIndex];
        }
    }
    return self;
}

/// Generates an array of triangles, initializing each and inserting it into `_triangles`.
- (void)generateTriangles
{
    // Array of colors.
    const vector_float4 Colors[] =
    {
        { 1.0, 0.0, 0.0, 1.0 },  // Red
        { 0.0, 1.0, 0.0, 1.0 },  // Green
        { 0.0, 0.0, 1.0, 1.0 },  // Blue
        { 1.0, 0.0, 1.0, 1.0 },  // Magenta
        { 0.0, 1.0, 1.0, 1.0 },  // Cyan
        { 1.0, 1.0, 0.0, 1.0 },  // Yellow
    };

    const NSUInteger NumColors = sizeof(Colors) / sizeof(vector_float4);

    // Horizontal spacing between each triangle.
    const float horizontalSpacing = 16;

    NSMutableArray *triangles = [[NSMutableArray alloc] initWithCapacity:NumTriangles];
    
    // Initialize each triangle.
    for(NSUInteger t = 0; t < NumTriangles; t++)
    {
        vector_float2 trianglePosition;

        // Determine the starting position of the triangle in a horizontal line.
        trianglePosition.x = ((-((float)NumTriangles) / 2.0) + t) * horizontalSpacing;
        trianglePosition.y = 0.0;

        // Create the triangle, set its properties, and add it to the array.
        AAPLTriangle * triangle = [AAPLTriangle new];
        triangle.position = trianglePosition;
        triangle.color = Colors[t % NumColors];
        [triangles addObject:triangle];
    }
    _triangles = triangles;
}

/// Updates the position of each triangle and also updates the vertices for each triangle in the current buffer.
- (void)updateState
{
    // Simplified wave properties.
    const float waveMagnitude = 128.0;  // Vertical displacement.
    const float waveSpeed     = 0.05;   // Displacement change from the previous frame.

    // Increment wave position from the previous frame
    _wavePosition += waveSpeed;

    // Vertex data for a single default triangle.
    const AAPLVertex *triangleVertices = [AAPLTriangle vertices];
    const NSUInteger triangleVertexCount = [AAPLTriangle vertexCount];

    // Vertex data for the current triangles.
    AAPLVertex *currentTriangleVertices = _vertexBuffers[_currentBuffer].contents;

    // Update each triangle.
    for(NSUInteger triangle = 0; triangle < NumTriangles; triangle++)
    {
        vector_float2 trianglePosition = _triangles[triangle].position;

        // Displace the y-position of the triangle using a sine wave.
        trianglePosition.y = (sin(trianglePosition.x/waveMagnitude + _wavePosition) * waveMagnitude);

        // Update the position of the triangle.
        _triangles[triangle].position = trianglePosition;

        // Update the vertices of the current vertex buffer with the triangle's new position.
        for(NSUInteger vertex = 0; vertex < triangleVertexCount; vertex++)
        {
            NSUInteger currentVertex = vertex + (triangle * triangleVertexCount);
            currentTriangleVertices[currentVertex].position = triangleVertices[vertex].position + _triangles[triangle].position;
            currentTriangleVertices[currentVertex].color = _triangles[triangle].color;
        }
    }
}

#pragma mark - MetalKit View Delegate

/// Handles view orientation or size changes.
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Regenerate the triangles.
    [self generateTriangles];

    // Save the size of the drawable as you'll pass these
    // values to the vertex shader when you render.
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
}

/// Handles view rendering for a new frame.
- (void)drawInMTKView:(nonnull MTKView *)view
{
    // Wait to ensure only `MaxFramesInFlight` number of frames are getting processed
    // by any stage in the Metal pipeline (CPU, GPU, Metal, Drivers, etc.).
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    // Iterate through the Metal buffers, and cycle back to the first when you've written to the last.
    _currentBuffer = (_currentBuffer + 1) % MaxFramesInFlight;

    // Update buffer data.
    [self updateState];

    // Create a new command buffer for each rendering pass to the current drawable.
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommandBuffer";

    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if(renderPassDescriptor != nil)
    {
        // Create a render command encoder to encode the rendering pass.
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"MyRenderEncoder";

        // Set render command encoder state.
        [renderEncoder setRenderPipelineState:_pipelineState];

        // Set the current vertex buffer.
        [renderEncoder setVertexBuffer:_vertexBuffers[_currentBuffer]
                                offset:0
                               atIndex:AAPLVertexInputIndexVertices];

        // Set the viewport size.
        [renderEncoder setVertexBytes:&_viewportSize
                               length:sizeof(_viewportSize)
                              atIndex:AAPLVertexInputIndexViewportSize];

        // Draw the triangle vertices.
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:_totalVertexCount];

        // Finalize encoding.
        [renderEncoder endEncoding];

        // Schedule a drawable's presentation after the rendering pass is complete.
        [commandBuffer presentDrawable:view.currentDrawable];
    }

    // Add a completion handler that signals `_inFlightSemaphore` when Metal and the GPU have fully
    // finished processing the commands that were encoded for this frame.
    // This completion indicates that the dynamic buffers that were written-to in this frame, are no
    // longer needed by Metal and the GPU; therefore, the CPU can overwrite the buffer contents
    // without corrupting any rendering operations.
    __block dispatch_semaphore_t block_semaphore = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
     {
         dispatch_semaphore_signal(block_semaphore);
     }];

    // Finalize CPU work and submit the command buffer to the GPU.
    [commandBuffer commit];
}

@end

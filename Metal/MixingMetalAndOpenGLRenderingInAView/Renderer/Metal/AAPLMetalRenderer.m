/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per frame rendering
*/

@import simd;
@import MetalKit;

#import "AAPLMetalRenderer.h"
#import "AAPLMathUtilities.h"

// Include header shared between C code here, which executes Metal API commands, and .metal files
#import "AAPLShaderTypes.h"

// The max number of command buffers in flight
static const NSUInteger AAPLMaxBuffersInFlight = 3;

// Main class performing the rendering
@implementation AAPLMetalRenderer
{
    dispatch_semaphore_t _inFlightSemaphore;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;

    // Metal objects
    id<MTLRenderPipelineState> _pipelineState;

    id<MTLTexture> _baseMap;
    id<MTLTexture> _labelMap;

    id<MTLBuffer> _quadVertexBuffer;

    id<MTLBuffer> _dynamicUniformBuffers[AAPLMaxBuffersInFlight];

    // Current buffer to fill with dynamic uniform data and set for the current frame
    uint8_t _currentBufferIndex;

    // Projection matrix calculated as a function of view size
    matrix_float4x4 _projectionMatrix;

    // Current rotation of the object (in radians)
    float _rotation;

    float _rotationIncrement;

    MTLRenderPassDescriptor *_renderPassDescriptor;
}

/// Initialize with a Metal device and the pixel format of the render target
- (nonnull instancetype)initWithDevice:(nonnull id<MTLDevice>)device
                      colorPixelFormat:(MTLPixelFormat)colorPixelFormat
{
    self = [super init];

    if(self)
    {
        _device = device;
        _inFlightSemaphore = dispatch_semaphore_create(AAPLMaxBuffersInFlight);

        // Load all the shader files with a .metal file extension in the project
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

        // Load the vertex function from the library
        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];

        // Load the fragment function from the library
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

        // Create a reusable pipeline state
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"MyPipeline";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat;

        NSError *error = nil;
        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        
        NSAssert(_pipelineState, @"Failed to create create render pipeline state, error %@", error);

        // Create and allocate the dynamic uniform buffer objects.
        for(NSUInteger i = 0; i < AAPLMaxBuffersInFlight; i++)
        {
            // Indicate shared storage so that both the  CPU can access the buffers
            const MTLResourceOptions storageMode = MTLResourceStorageModeShared;

            _dynamicUniformBuffers[i] = [_device newBufferWithLength:sizeof(AAPLUniforms)
                                                             options:storageMode];

            _dynamicUniformBuffers[i].label = [NSString stringWithFormat:@"UniformBuffer%lu", i];
        }

        // Create the command queue
        _commandQueue = [_device newCommandQueue];
        static const AAPLVertex QuadVertices[] =
        {
            //  Positions                        TexCoords
            { { -0.75,  -0.75,  0.0,  1.0 }, { 0.0, 1.0 } },
            { { -0.75,   0.75,  0.0,  1.0 }, { 0.0, 0.0 } },
            { {  0.75,  -0.75,  0.0,  1.0 }, { 1.0, 1.0 } },

            { {  0.75,  -0.75,  0.0,  1.0 }, { 1.0, 1.0 } },
            { { -0.75,   0.75,  0.0,  1.0 }, { 0.0, 0.0 } },
            { {  0.75,   0.75,  0.0,  1.0 }, { 1.0, 0.0 } },
        };

        _quadVertexBuffer = [_device newBufferWithBytes:QuadVertices
                                                 length:sizeof(QuadVertices)
                                                options:0];

        _renderPassDescriptor = [MTLRenderPassDescriptor new];
        _renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 1, 0, 1);
        _renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        _renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;

        _rotationIncrement = 0.01;
    }

    return self;
}

- (void)useInteropTextureAsBaseMap:(nonnull id<MTLTexture>)texture
{
    _baseMap = texture;

    MTKTextureLoader *textureLoader = [[MTKTextureLoader alloc] initWithDevice:_device];

    NSURL *labelMapURL = [[NSBundle mainBundle] URLForResource:@"Assets/QuadWithMetalToView" withExtension:@"png"];

    NSError *error = nil;
    _labelMap = [textureLoader newTextureWithContentsOfURL:labelMapURL options:nil error:&error];

    NSAssert(_labelMap, @"Error loading Metal texture from file %@: %@", labelMapURL.absoluteString, error);

    _rotationIncrement = 0.01;
}

- (void)useTextureFromFileAsBaseMap
{
    MTKTextureLoader *textureLoader = [[MTKTextureLoader alloc] initWithDevice:_device];

    NSURL *baseTextureURL = [[NSBundle mainBundle] URLForResource:@"Assets/Colors" withExtension:@"png"];

    NSError *error;

    _baseMap = [textureLoader newTextureWithContentsOfURL:baseTextureURL options:nil error:&error];

    NSAssert(_baseMap, @"Error loading Metal texture from file @: %@", baseTextureURL.absoluteString, error.localizedDescription);

    NSURL *labelMapURL = [[NSBundle mainBundle] URLForResource:@"Assets/QuadWithMetalToPixelBuffer" withExtension:@"png"];

    _labelMap = [textureLoader newTextureWithContentsOfURL:labelMapURL options:nil error:&error];

    NSAssert(_labelMap, @"Error loading Metal texture from file %@: %@", labelMapURL.absoluteString, error);
    
    _rotationIncrement = -0.01;
}

/// Called whenever view changes orientation or layout is changed
- (void)resize:(CGSize)size
{
    float aspect = (float)size.width / size.height;
    _projectionMatrix = matrix_perspective_right_hand(1, aspect, .1, 5.0);
}


- (void)updateState
{
    if(_rotation > 30*(M_PI/180.0f))
    {
        _rotationIncrement = -0.01;
    }
    else if(_rotation < -30*(M_PI/180.0f))
    {
        _rotationIncrement = 0.01;
    }
    _rotation += _rotationIncrement;

    matrix_float4x4 rotation = matrix4x4_rotation(_rotation, 0.0, 1.0, 0.0);
    matrix_float4x4 translation = matrix4x4_translation(0.0, 0.0, -2.0);
    matrix_float4x4 modelView = matrix_multiply(translation, rotation);

    matrix_float4x4 mvp = matrix_multiply(_projectionMatrix, modelView);

    AAPLUniforms *uniforms = (AAPLUniforms *)_dynamicUniformBuffers[_currentBufferIndex].contents;
    uniforms->mvp = mvp;
}

- (id<MTLCommandBuffer>) drawToTexture:(id<MTLTexture>)texture
{
    // Wait to ensure only AAPLMaxBuffersInFlight are getting proccessed by any stage in the Metal
    // pipeline (App, Metal, Drivers, GPU, etc)
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    [self updateState];

    // Create a new command buffer for each renderpass to the current drawable
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";

    // Add completion hander which signals _inFlightSemaphore when Metal and the GPU has fully
    // finished proccessing the commands encoded this frame.  This indicates when the dynamic
    // buffers, written to this frame, will no longer be needed by Metal and the GPU, meaning the
    // buffer contents can be changed without corrupting rendering
    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
     {
         dispatch_semaphore_signal(block_sema);
     }];


    _renderPassDescriptor.colorAttachments[0].texture = texture;

    // If a renderPassDescriptor has been obtained, render to the drawable, otherwise skip
    // any rendering this frame because there is no drawable to draw to

    id<MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:_renderPassDescriptor];
    renderEncoder.label = @"MyRenderEncoder";

    // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
    [renderEncoder pushDebugGroup:@"DrawMesh"];

    // Set render command encoder state
    [renderEncoder setCullMode:MTLCullModeBack];
    [renderEncoder setRenderPipelineState:_pipelineState];

    // Set any buffers fed into the render pipeline
    [renderEncoder setVertexBuffer:_dynamicUniformBuffers[_currentBufferIndex]
                            offset:0
                           atIndex:AAPLBufferIndexUniforms];

    [renderEncoder setFragmentBuffer:_dynamicUniformBuffers[_currentBufferIndex]
                              offset:0
                             atIndex:AAPLBufferIndexUniforms];

    // Set buffer with vertices for the quad
    [renderEncoder setVertexBuffer:_quadVertexBuffer
                            offset:0
                           atIndex:AAPLBufferIndexVertices];

    // Set base texture (which is either loaded from file or the texture rendered to with OpenGL)
    [renderEncoder setFragmentTexture:_baseMap
                              atIndex:AAPLTextureIndexBaseMap];

    // Set label texture that set "This quad is rendered with Metal"
    [renderEncoder setFragmentTexture:_labelMap
                              atIndex:AAPLTextureIndexLabelMap];

    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:6];

    [renderEncoder popDebugGroup];

    // Done encoding commands
    [renderEncoder endEncoding];

    return commandBuffer;
}

- (void)drawToMTKView:(nonnull MTKView *)view
{
    id<MTLTexture> drawableTexture = view.currentDrawable.texture;

    if(drawableTexture)
    {
        id<MTLCommandBuffer> commandBuffer = [self drawToTexture:drawableTexture];

        // Schedule a present once the framebuffer is complete using the current drawable
        [commandBuffer presentDrawable:view.currentDrawable];

        [commandBuffer commit];


    }
}

- (void)drawToInteropTexture:(id<MTLTexture>)interopTexture
{
    id<MTLCommandBuffer> commandBuffer = [self drawToTexture:interopTexture];

    [commandBuffer commit];
}

@end

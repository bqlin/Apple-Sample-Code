/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per frame rendering
*/
@import simd;
@import ModelIO;
@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLMathUtilities.h"

// Include header shared between C code here, which executes Metal API commands, and .metal files
#import "AAPLShaderTypes.h"

// The max number of command buffers in flight
static const NSUInteger AAPLMaxBuffersInFlight = 3;

@implementation AAPLRenderer
{
    dispatch_semaphore_t _inFlightSemaphore;
    id<MTLCommandQueue> _commandQueue;

    // Metal objects
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLDepthStencilState> _depthState;
    id<MTLTexture> _baseColorMap;
    id<MTLTexture> _normalMap;
    id<MTLTexture> _specularMap;
    id<MTLBuffer> _dynamicUniformBuffers[AAPLMaxBuffersInFlight];

    // The index in uniform buffers in _dynamicUniformBuffers to use for the current frame
    uint8_t _uniformBufferIndex;

    // Vertex descriptor specifying how vertices will by laid out for input into our render
    // pipeline and how ModelIO should layout vertices
    MTLVertexDescriptor *_mtlVertexDescriptor;

    // Projection matrix calculated as a function of view size
    matrix_float4x4 _projectionMatrix;

    // MetalKit mesh containing vertex data and index buffer for our object
    MTKMesh *_mesh;
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device.  We'll also use this
/// mtkView object to set the pixel format and other properties of our drawable
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView device:(id<MTLDevice>) device
{
    self = [super init];
    if(self)
    {
        _device = device;
        _inFlightSemaphore = dispatch_semaphore_create(AAPLMaxBuffersInFlight);
        [self loadMetal:mtkView];
        [self loadAssets];
    }

    return self;
}

/// Create our metal render state objects including our shaders and render state pipeline objects
- (void) loadMetal:(nonnull MTKView *)mtkView
{
    // Create and load our basic Metal state objects

    // Load all the shader files with a metal file extension in the project
    id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

    for(NSUInteger i = 0; i < AAPLMaxBuffersInFlight; i++)
    {
        // Create and allocate our uniform buffer object.  Indicate shared storage so that both the
        //  CPU can access the buffer
        _dynamicUniformBuffers[i] = [_device newBufferWithLength:sizeof(AAPLUniforms)
                                                     options:MTLResourceStorageModeShared];

        _dynamicUniformBuffers[i].label = [NSString stringWithFormat:@"UniformBuffer%lu", i];
    }

    _mtlVertexDescriptor = [[MTLVertexDescriptor alloc] init];

    // Positions.
    _mtlVertexDescriptor.attributes[AAPLVertexAttributePosition].format = MTLVertexFormatFloat3;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributePosition].offset = 0;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributePosition].bufferIndex = AAPLBufferIndexMeshPositions;

    // Texture coordinates.
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeTexcoord].format = MTLVertexFormatFloat2;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeTexcoord].offset = 0;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeTexcoord].bufferIndex = AAPLBufferIndexMeshGenerics;

    // Normals.
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeNormal].format = MTLVertexFormatHalf4;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeNormal].offset = 8;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeNormal].bufferIndex = AAPLBufferIndexMeshGenerics;

    // Tangents
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeTangent].format = MTLVertexFormatHalf4;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeTangent].offset = 16;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeTangent].bufferIndex = AAPLBufferIndexMeshGenerics;

    // Bitangents
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeBitangent].format = MTLVertexFormatHalf4;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeBitangent].offset = 24;
    _mtlVertexDescriptor.attributes[AAPLVertexAttributeBitangent].bufferIndex = AAPLBufferIndexMeshGenerics;

    // Position Buffer Layout
    _mtlVertexDescriptor.layouts[AAPLBufferIndexMeshPositions].stride = 12;
    _mtlVertexDescriptor.layouts[AAPLBufferIndexMeshPositions].stepRate = 1;
    _mtlVertexDescriptor.layouts[AAPLBufferIndexMeshPositions].stepFunction = MTLVertexStepFunctionPerVertex;

    // Generic Attribute Buffer Layout
    _mtlVertexDescriptor.layouts[AAPLBufferIndexMeshGenerics].stride = 32;
    _mtlVertexDescriptor.layouts[AAPLBufferIndexMeshGenerics].stepRate = 1;
    _mtlVertexDescriptor.layouts[AAPLBufferIndexMeshGenerics].stepFunction = MTLVertexStepFunctionPerVertex;

    id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentLighting"];
    id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexTransform"];

    // Create a reusable pipeline state
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.label = @"MyPipeline";
    pipelineStateDescriptor.sampleCount = mtkView.sampleCount;
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.vertexDescriptor = _mtlVertexDescriptor;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
    pipelineStateDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat;
    pipelineStateDescriptor.stencilAttachmentPixelFormat = mtkView.depthStencilPixelFormat;

    NSError *error = Nil;
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                             error:&error];
    
    NSAssert(_pipelineState, @"Failed to create pipeline state: %@", error);
    
    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = YES;
    _depthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];

    // Create the command queue
    _commandQueue = [_device newCommandQueue];
}

/// Create and load our assets into Metal objects including meshes and textures
- (void) loadAssets
{
    NSError *error;

    // Create a ModelIO vertexDescriptor so that we format/layout our ModelIO mesh vertices to
    // fit our Metal render pipeline's vertex descriptor layout
    MDLVertexDescriptor *modelIOVertexDescriptor =
        MTKModelIOVertexDescriptorFromMetal(_mtlVertexDescriptor);

    // Indicate how each Metal vertex descriptor attribute maps to each ModelIO  attribute
    modelIOVertexDescriptor.attributes[AAPLVertexAttributePosition].name  = MDLVertexAttributePosition;
    modelIOVertexDescriptor.attributes[AAPLVertexAttributeTexcoord].name  = MDLVertexAttributeTextureCoordinate;
    modelIOVertexDescriptor.attributes[AAPLVertexAttributeNormal].name    = MDLVertexAttributeNormal;
    modelIOVertexDescriptor.attributes[AAPLVertexAttributeTangent].name   = MDLVertexAttributeTangent;
    modelIOVertexDescriptor.attributes[AAPLVertexAttributeBitangent].name = MDLVertexAttributeBitangent;

    // Create a MetalKit mesh buffer allocator so that ModelIO  will load mesh data directly into
    // Metal buffers accessible by the GPU
    MTKMeshBufferAllocator *metalAllocator =
        [[MTKMeshBufferAllocator alloc] initWithDevice: _device];

    // Use ModelIO  to create a cylinder mesh as our object
    MDLMesh *modelIOMesh = [MDLMesh newCylinderWithHeight:4
                                                    radii:(vector_float2){1.5, 1.5}
                                           radialSegments:60
                                         verticalSegments:1
                                             geometryType:MDLGeometryTypeTriangles
                                            inwardNormals:NO
                                                allocator:metalAllocator];

    // Have ModelIO  create the tangents from mesh texture coordinates and normals
    [modelIOMesh addTangentBasisForTextureCoordinateAttributeNamed:MDLVertexAttributeTextureCoordinate
                                              normalAttributeNamed:MDLVertexAttributeNormal
                                             tangentAttributeNamed:MDLVertexAttributeTangent];

    // Have ModelIO  create bitangents from mesh texture coordinates and the newly created tangents
    [modelIOMesh addTangentBasisForTextureCoordinateAttributeNamed:MDLVertexAttributeTextureCoordinate
                                             tangentAttributeNamed:MDLVertexAttributeTangent
                                           bitangentAttributeNamed:MDLVertexAttributeBitangent];

    // Perform the format/re-layout of mesh vertices by setting the new vertex descriptor in our  ModelIO mesh
    modelIOMesh.vertexDescriptor = modelIOVertexDescriptor;

    // Create a MetalKit mesh (and submeshes) backed by Metal buffers
    _mesh = [[MTKMesh alloc] initWithMesh:modelIOMesh
                                   device:_device
                                    error:&error];

    NSAssert(_mesh, @"Error creating MetalKit mesh %@", error);

    // Use MetalKit's to load textures from our asset catalog (Assets.xcassets)
    MTKTextureLoader *textureLoader = [[MTKTextureLoader alloc] initWithDevice:_device];

    // Load our textures with shader read using private storage
    NSDictionary *textureLoaderOptions =
    @{
      MTKTextureLoaderOptionTextureUsage       : @(MTLTextureUsageShaderRead),
      MTKTextureLoaderOptionTextureStorageMode : @(MTLStorageModePrivate)
      };

    _baseColorMap = [textureLoader newTextureWithName:@"CanBaseColorMap"
                                          scaleFactor:1.0
                                               bundle:nil
                                              options:textureLoaderOptions
                                                error:&error];

    NSAssert(_baseColorMap, @"Error creating base color texture %@", error);
    
    _normalMap = [textureLoader newTextureWithName:@"CanNormalMap"
                                       scaleFactor:1.0
                                            bundle:nil
                                           options:textureLoaderOptions
                                             error:&error];
    
    NSAssert(_normalMap, @"Error normal map texture %@", error);
    
    _specularMap = [textureLoader newTextureWithName:@"CanSpecularMap"
                                         scaleFactor:1.0
                                              bundle:nil
                                             options:textureLoaderOptions
                                               error:&error];
    
    NSAssert(_specularMap, @"Error specular texture %@", error);
}

/// Update any per frame shading state (including updating dynamically changing Metal buffer)
- (void) updateStateForFrameNumber:(NSUInteger)frameNumber
{
    float rotation = frameNumber * .01;

    _uniformBufferIndex = frameNumber % 3;

    AAPLUniforms * uniforms = (AAPLUniforms*)_dynamicUniformBuffers[_uniformBufferIndex].contents;

    vector_float3 ambientLightColor = {0.02, 0.02, 0.02};
    uniforms->ambientLightColor = ambientLightColor;

    vector_float3 directionalLightDirection = vector_normalize ((vector_float3){0.0,  0.0, 1.0});

    uniforms->directionalLightInvDirection = -directionalLightDirection;

    vector_float3 directionalLightColor = {.7, .7, .7};
    uniforms->directionalLightColor = directionalLightColor;;

    uniforms->materialShininess = 2;

    const vector_float3   modelRotationAxis = {1, 0, 0};
    const matrix_float4x4 modelRotationMatrix = matrix4x4_rotation(rotation, modelRotationAxis);
    const matrix_float4x4 modelMatrix = modelRotationMatrix;

    const vector_float3 cameraTranslation = {0.0, 0.0, -8.0};
    const matrix_float4x4 viewMatrix = matrix4x4_translation(-cameraTranslation);
    const matrix_float4x4 viewProjectionMatrix = matrix_multiply(_projectionMatrix, viewMatrix);

    uniforms->modelMatrix = modelMatrix;
    uniforms->modelViewProjectionMatrix = matrix_multiply(viewProjectionMatrix, modelMatrix);

    uniforms->normalMatrix = matrix3x3_upper_left(modelMatrix);
}

/// Called whenever view changes orientation or layout is changed
- (void)updateDrawableSize:(CGSize)size
{
    /// React to resize of our draw rect.  In particular update our perspective matrix
    // Update the aspect ratio and projection matrix since the view orientation or size has changed
    float aspect = size.width / (float)size.height;
    _projectionMatrix = matrix_perspective_left_hand(65.0f * (M_PI / 180.0f), aspect, 0.1f, 100.0);
}

// Called whenever the view needs to render
- (void)drawFrameNumber:(NSUInteger)frameNumber toView:(nonnull MTKView *)view
{
    // Wait to ensure only AAPLMaxBuffersInFlight are getting processed by any stage in the Metal
    // pipeline (App, Metal, Drivers, GPU, etc)
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    [self updateStateForFrameNumber:frameNumber];

    // Create a new command buffer for each render pass to the current drawable
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";

    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    // If we've gotten a renderPassDescriptor we can render to the drawable, otherwise we'll skip
    // any rendering this frame because we have no drawable to draw to
    if(renderPassDescriptor != nil)
    {
        // Create a render command encoder so we can render into something
        id<MTLRenderCommandEncoder> renderEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"MyRenderEncoder";

        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        [renderEncoder pushDebugGroup:@"DrawMesh"];

        [renderEncoder setCullMode:MTLCullModeBack];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setDepthStencilState:_depthState];

        [renderEncoder setVertexBuffer:_dynamicUniformBuffers[_uniformBufferIndex]
                                offset:0
                               atIndex:AAPLBufferIndexUniforms];

        [renderEncoder setFragmentBuffer:_dynamicUniformBuffers[_uniformBufferIndex]
                                  offset:0
                                 atIndex:AAPLBufferIndexUniforms];

        // Set mesh's vertex buffers
        for (NSUInteger bufferIndex = 0; bufferIndex < _mesh.vertexBuffers.count; bufferIndex++)
        {
            MTKMeshBuffer *vertexBuffer = _mesh.vertexBuffers[bufferIndex];
            if((NSNull*)vertexBuffer != [NSNull null])
            {
                [renderEncoder setVertexBuffer:vertexBuffer.buffer
                                        offset:vertexBuffer.offset
                                       atIndex:bufferIndex];
            }
        }

        // Set any textures read/sampled from our render pipeline
        [renderEncoder setFragmentTexture:_baseColorMap
                                  atIndex:AAPLTextureIndexBaseColor];

        [renderEncoder setFragmentTexture:_normalMap
                                  atIndex:AAPLTextureIndexNormal];

        [renderEncoder setFragmentTexture:_specularMap
                                  atIndex:AAPLTextureIndexSpecular];

        // Draw each submesh of our mesh
        for(MTKSubmesh *submesh in _mesh.submeshes)
        {
            [renderEncoder drawIndexedPrimitives:submesh.primitiveType
                                      indexCount:submesh.indexCount
                                       indexType:submesh.indexType
                                     indexBuffer:submesh.indexBuffer.buffer
                               indexBufferOffset:submesh.indexBuffer.offset];
        }

        [renderEncoder popDebugGroup];

        [renderEncoder endEncoding];

        [commandBuffer presentDrawable:view.currentDrawable];
    }

    // Add completion hander which signals _inFlightSemaphore when Metal and the GPU has fully
    // finished processing the commands we're encoding this frame.
    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer)
     {
         dispatch_semaphore_signal(block_sema);
     }];

    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
}

@end

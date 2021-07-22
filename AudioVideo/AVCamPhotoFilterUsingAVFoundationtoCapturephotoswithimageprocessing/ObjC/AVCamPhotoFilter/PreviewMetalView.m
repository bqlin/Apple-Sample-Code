//
//  PreviewMetalView.m
//  AVCamPhotoFilter
//
//  Created by bqlin on 2018/9/3.
//  Copyright © 2018年 Bq. All rights reserved.
//

#import "PreviewMetalView.h"

@interface PreviewMetalView()

@property (nonatomic, assign) BOOL internalMirroring;

@property (nonatomic, assign) PreviewMetalViewRotation internalRotation;

@property (nonatomic, assign) CVPixelBufferRef internalPixelBuffer;

@property (nonatomic, strong) dispatch_queue_t syncQueue;

@property (nonatomic, assign) CVMetalTextureCacheRef textureCache;

@property (nonatomic, assign) NSInteger textureWidth;
@property (nonatomic, assign) NSInteger textureHeight;

@property (nonatomic, assign) BOOL textureMirroring;

@property (nonatomic, assign) PreviewMetalViewRotation textureRotation;

@property (nonatomic, strong) id<MTLSamplerState> sampler;
@property (nonatomic, strong) id<MTLRenderPipelineState> renderPipelineState;

@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;

@property (nonatomic, strong) id<MTLBuffer> vertexCoordBuffer;

@property (nonatomic, strong) id<MTLBuffer> textCoordBuffer;

@property (nonatomic, assign) CGRect internalBounds;

@property (nonatomic, assign) CGAffineTransform textureTranform;

@end

@implementation PreviewMetalView

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        [self commonInit];
    }
    return self;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self commonInit];
    }
    return self;
}
- (instancetype)initWithFrame:(CGRect)frameRect device:(id<MTLDevice>)device {
    if (self = [super initWithFrame:frameRect device:device]) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _syncQueue = dispatch_queue_create("Preview View Sync Queue", DISPATCH_QUEUE_SERIAL);
    
    self.device = MTLCreateSystemDefaultDevice();
    [self configureMetal];
    [self createTextureCache];
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
}

- (void)configureMetal {
    id<MTLLibrary> defaultLibrary = [self.device newDefaultLibrary];
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipelineDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"vertexPassThrough"];
    pipelineDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentPassThrough"];
    
    // To determine how our textures are sampled, we create a sampler descriptor, which
    // will be used to ask for a sampler state object from our device below.
    MTLSamplerDescriptor *samplerDescriptor = [[MTLSamplerDescriptor alloc] init];
    samplerDescriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
    samplerDescriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
    samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
    samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
    _sampler = [self.device newSamplerStateWithDescriptor:samplerDescriptor];
    
    NSError *error = nil;
    _renderPipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    NSAssert(!error, @"Unable to create preview Metal view pipeline state. (%@)", error);
    
    _commandQueue = [self.device newCommandQueue];
}

- (void)createTextureCache {
    CVMetalTextureCacheRef newTextureCache = nil;
    if (CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, self.device, nil, &newTextureCache) == kCVReturnSuccess) {
        _textureCache = newTextureCache;
    } else {
        NSAssert(false, @"Unable to allocate texture cache");
    }
}

- (void)drawRect:(CGRect)rect {
    __block CVPixelBufferRef pixelBuffer = NULL;
    __block BOOL mirroring = NO;
    __block PreviewMetalViewRotation rotation = PreviewMetalViewRotation0Degrees;
    
    dispatch_sync(_syncQueue, ^{
        pixelBuffer = self->_internalPixelBuffer;
        mirroring = self->_internalMirroring;
        rotation = self->_internalRotation;
    });
    
    id <CAMetalDrawable> drawable = self.currentDrawable;
    MTLRenderPassDescriptor *currentRenderPassDescriptor = self.currentRenderPassDescriptor;
    CVPixelBufferRef previewPixelBuffer = pixelBuffer;
    
    // Create a Metal texture from the image buffer
    size_t width = CVPixelBufferGetWidth(previewPixelBuffer);
    size_t height = CVPixelBufferGetHeight(previewPixelBuffer);
    
    if (!_textureCache) {
        [self createTextureCache];
    }
    CVMetalTextureRef cvTextureOut = NULL;
    CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, previewPixelBuffer, nil, MTLPixelFormatBGRA8Unorm, width, height, 0, &cvTextureOut);
    CVMetalTextureRef cvTexture = cvTextureOut;
    id<MTLTexture> texture = CVMetalTextureGetTexture(cvTexture);
    if (!texture) {
        NSLog(@"Failed to create preview texture");
        CVMetalTextureCacheFlush(_textureCache, 0);
        return;
    }
    
    if (texture.width != _textureWidth ||
        texture.height != _textureHeight ||
        CGRectEqualToRect(self.bounds, _internalBounds) ||
        mirroring != _textureMirroring ||
        rotation != _textureRotation) {
        [self setupTransformWithWidth:texture.width height:texture.height mirroring:mirroring rotation:rotation];
    }
    
    // Set up command buffer and encoder
    id<MTLCommandQueue> commandQueue = _commandQueue;
    if (!commandQueue) {
        NSLog(@"Failed to create Metal command queue");
        CVMetalTextureCacheFlush(_textureCache, 0);
        return;
    }
    
    id<MTLCommandBuffer> commandBuffer = commandQueue.commandBuffer;
    if (!commandBuffer) {
        NSLog(@"Failed to create Metal command buffer");
        CVMetalTextureCacheFlush(_textureCache, 0);
        return;
    }
    
    id<MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:currentRenderPassDescriptor];
    if (commandEncoder) {
        NSLog(@"Failed to create Metal command encoder");
        CVMetalTextureCacheFlush(_textureCache, 0);
        return;
    }
    
    commandEncoder.label = @"Preview display";
    [commandEncoder setRenderPipelineState:_renderPipelineState];
    [commandEncoder setVertexBuffer:_vertexCoordBuffer offset:0 atIndex:0];
    [commandEncoder setVertexBuffer:_textCoordBuffer offset:0 atIndex:1];
    [commandEncoder setFragmentTexture:texture atIndex:0];
    [commandEncoder setFragmentSamplerState:_sampler atIndex:0];
    [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [commandEncoder endEncoding];
    
    [commandBuffer presentDrawable:drawable]; // Draw to the screen
    [commandBuffer commit];
}

#pragma mark - property

- (void)setMirroring:(BOOL)mirroring {
    _mirroring = mirroring;
    dispatch_sync(_syncQueue, ^{
        self.internalMirroring = mirroring;
    });
}

- (void)setRotation:(PreviewMetalViewRotation)rotation {
    _rotation = rotation;
    dispatch_sync(_syncQueue, ^{
        self.internalRotation = rotation;
    });
}

- (void)setPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    _pixelBuffer = pixelBuffer;
    dispatch_sync(_syncQueue, ^{
        self.internalPixelBuffer = pixelBuffer;
    });
}

#pragma mark -

- (CGPoint)texturePointForViewWithPoint:(CGPoint)point {
    CGAffineTransform transform = _textureTranform;
    CGPoint transformPoint = CGPointApplyAffineTransform(point, transform);
    
    if (CGRectContainsPoint(CGRectMake(0, 0, _textureWidth, _textureHeight), transformPoint)) {
        return transformPoint;
    }
    return CGPointZero;
}

- (CGPoint)viewPointForTextureWithPoint:(CGPoint)point {
    CGAffineTransform transform = CGAffineTransformInvert(_textureTranform);
    CGPoint transformPoint = CGPointApplyAffineTransform(point, transform);
    
    if (CGRectContainsPoint(_internalBounds, transformPoint)) {
        return transformPoint;
    }
    return CGPointZero;
}

- (void)flushTextureCache {
    _textureCache = nil;
}

- (void)setupTransformWithWidth:(NSInteger)width height:(NSInteger)height mirroring:(BOOL)mirroring rotation:(PreviewMetalViewRotation)rotation {
    CGFloat scaleX = 1.0, scaleY = 1.0, resizeAspect = 1.0;
    
    _internalBounds = self.bounds;
    _textureWidth = width;
    _textureHeight = height;
    _textureMirroring = mirroring;
    _textureRotation = rotation;
    
    if (_textureWidth > 0 && _textureHeight > 0) {
        switch (_textureRotation) {
            case PreviewMetalViewRotation0Degrees:
            case PreviewMetalViewRotation180Degrees:{
                scaleX = 1.0 * CGRectGetWidth(_internalBounds) / _textureWidth;
                scaleY = 1.0 * CGRectGetHeight(_internalBounds) / _textureHeight;
            } break;
            case PreviewMetalViewRotation90Degrees:
            case PreviewMetalViewRotation270Degrees:{
                scaleX = 1.0 * CGRectGetWidth(_internalBounds) / _textureHeight;
                scaleY = 1.0 * CGRectGetHeight(_internalBounds) / _textureWidth;
            } break;
        }
    }
    
    // Resize aspect
    resizeAspect = MIN(scaleX, scaleY);
    if (scaleX < scaleY) {
        scaleY = scaleX / scaleY;
        scaleX = 1.0;
    } else {
        scaleX = scaleY / scaleX;
        scaleY = 1.0;
    }
    
    if (_textureMirroring) scaleX *= -1.0;
    
    // Vertex coordinate takes the gravity into account
    float vertexData[] = {
        -scaleX, -scaleY, 0.0, 1.0,
        scaleX, -scaleY, 0.0, 1.0,
        -scaleX, scaleY, 0.0, 1.0,
        scaleX, scaleY, 0.0, 1.0
    };
    _vertexCoordBuffer = [self.device newBufferWithBytes:vertexData length:sizeof(vertexData) options:0];
    
    // Texture coordinate takes the rotation into account
    float *textData = NULL;
    switch (_textureRotation) {
        case PreviewMetalViewRotation0Degrees:{
            float _textData[] = {
                0.0, 1.0,
                1.0, 1.0,
                0.0, 0.0,
                1.0, 0.0
            };
            textData = _textData;
        } break;
        case PreviewMetalViewRotation180Degrees:{
            float _textData[] = {
                1.0, 0.0,
                0.0, 0.0,
                1.0, 1.0,
                0.0, 1.0
            };
            textData = _textData;
        } break;
        case PreviewMetalViewRotation90Degrees:{
            float _textData[] = {
                1.0, 1.0,
                1.0, 0.0,
                0.0, 1.0,
                0.0, 0.0
            };
            textData = _textData;
        } break;
        case PreviewMetalViewRotation270Degrees:{
            float _textData[] = {
                0.0, 0.0,
                0.0, 1.0,
                1.0, 0.0,
                1.0, 1.0
            };
            textData = _textData;
        } break;
    }
    _textCoordBuffer = [self.device newBufferWithBytes:textData length:sizeof(textData) options:0];
    
    // Calculate the transform from texture coordinates to view coordinates
    CGAffineTransform transform = CGAffineTransformIdentity;
    if (_textureMirroring) {
        transform = CGAffineTransformScale(transform, -1, 1);
        transform = CGAffineTransformTranslate(transform, _textureWidth, 0);
    }
    
    switch (_textureRotation) {
        case PreviewMetalViewRotation0Degrees:{
            transform = CGAffineTransformRotate(transform, 0);
        } break;
        case PreviewMetalViewRotation180Degrees:{
            transform = CGAffineTransformRotate(transform, M_PI);
            transform = CGAffineTransformTranslate(transform, _textureWidth, _textureHeight);
        } break;
        case PreviewMetalViewRotation90Degrees:{
            transform = CGAffineTransformRotate(transform, M_PI / 2.0);
            transform = CGAffineTransformTranslate(transform, _textureHeight, 0);
        } break;
        case PreviewMetalViewRotation270Degrees:{
            transform = CGAffineTransformRotate(transform, M_PI * 3.0 / 2.0);
            transform = CGAffineTransformTranslate(transform, 0, _textureWidth);
        } break;
    }
    transform = CGAffineTransformScale(transform, resizeAspect, resizeAspect);
    CGRect transformRect = CGRectApplyAffineTransform(CGRectMake(0, 0, _textureWidth, _textureHeight), transform);
    CGFloat tx = .5 * (CGRectGetWidth(_internalBounds) - CGRectGetWidth(transformRect));
    CGFloat ty = .5 * (CGRectGetHeight(_internalBounds) - CGRectGetHeight(transformRect));
    transform = CGAffineTransformTranslate(transform, tx, ty);
    _textureTranform = CGAffineTransformInvert(transform);
}



@end

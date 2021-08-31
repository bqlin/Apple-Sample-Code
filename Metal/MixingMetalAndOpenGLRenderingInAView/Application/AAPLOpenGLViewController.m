/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the cross-platform OpenGL view controller AND a minimal cross-platform OpenGL View
*/
#import "AAPLOpenGLViewController.h"
#import "AAPLOpenGLRenderer.h"
#import "AAPLOpenGLMetalInteropTexture.h"
#import "AAPLMetalRenderer.h"

static const MTLPixelFormat AAPLOpenGLViewInteropPixelFormat = MTLPixelFormatBGRA8Unorm;

@implementation AAPLOpenGLView

#if TARGET_IOS
+ (Class) layerClass
{
    return [CAEAGLLayer class];
}
#endif

@end

@implementation AAPLOpenGLViewController
{
    AAPLOpenGLView *_view;
    AAPLOpenGLRenderer *_openGLRenderer;
    PlatformGLContext *_context;
    GLuint _defaultFBOName;

    id<MTLDevice> _metalDevice;
    AAPLMetalRenderer * _metalRenderer;

    AAPLOpenGLMetalInteropTexture *_interopTexture;

#if defined(TARGET_IOS) || defined(TARGET_TVOS)
    GLuint _colorRenderbuffer;
    CADisplayLink *_displayLink;
#else
    CVDisplayLinkRef _displayLink;
#endif
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _view = (AAPLOpenGLView *)self.view;

    [self prepareView];

    [self makeCurrentContext];

    _openGLRenderer = [[AAPLOpenGLRenderer alloc] initWithDefaultFBOName:_defaultFBOName];

    NSAssert(_openGLRenderer, @"OpenGL Renderer failed initialization");

    _metalDevice = MTLCreateSystemDefaultDevice();

    _metalRenderer = [[AAPLMetalRenderer alloc] initWithDevice:_metalDevice
                                              colorPixelFormat:AAPLOpenGLViewInteropPixelFormat];

    _interopTexture = [[AAPLOpenGLMetalInteropTexture alloc] initWithMetalDevice:_metalDevice
                                                                   openGLContext:_context
                                                                metalPixelFormat:AAPLOpenGLViewInteropPixelFormat
                                                                            size:AAPLInteropTextureSize];

    // Set texture that OpenGL renders as the interop texture
    [_openGLRenderer useInteropTextureAsBaseMap:_interopTexture.openGLTexture];

    [_openGLRenderer resize:self.drawableSize];

    // Set texture that Metal will render to load from file
    [_metalRenderer useTextureFromFileAsBaseMap];


    [_metalRenderer resize:AAPLInteropTextureSize];
}

#if TARGET_MACOS

- (CGSize) drawableSize
{
    CGSize viewSizePoints = _view.bounds.size;

    CGSize viewSizePixels = [_view convertSizeToBacking:viewSizePoints];

    return viewSizePixels;
}

- (void)makeCurrentContext
{
    [_context makeCurrentContext];
}

static CVReturn OpenGLDisplayLinkCallback(CVDisplayLinkRef displayLink,
                                         const CVTimeStamp* now,
                                         const CVTimeStamp* outputTime,
                                         CVOptionFlags flagsIn,
                                         CVOptionFlags* flagsOut,
                                         void* displayLinkContext)
{
    AAPLOpenGLViewController *viewController = (__bridge AAPLOpenGLViewController*)displayLinkContext;

    [viewController draw];
    return YES;
}

- (void)draw
{
    CGLLockContext(_context.CGLContextObj);

    [_context makeCurrentContext];

    [_metalRenderer drawToInteropTexture:_interopTexture.metalTexture];
    [_openGLRenderer draw];

    CGLFlushDrawable(_context.CGLContextObj);
    CGLUnlockContext(_context.CGLContextObj);
}

- (void)prepareView
{
    NSOpenGLPixelFormatAttribute attrs[] =
    {
        NSOpenGLPFAColorSize, 32,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFADepthSize, 24,
        0
    };

    NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];

    NSAssert(pixelFormat, @"No OpenGL pixel format");

    _context = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];

    CGLLockContext(_context.CGLContextObj);

    [_context makeCurrentContext];

    CGLUnlockContext(_context.CGLContextObj);

    _view.pixelFormat = pixelFormat;
    _view.openGLContext = _context;
    _view.wantsBestResolutionOpenGLSurface = YES;

    // Default FBO is 0 on macOS since it uses a traditional OpenGL pixel format model
    _defaultFBOName = 0;

    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);

    // Set the renderer output callback function
    CVDisplayLinkSetOutputCallback(_displayLink, &OpenGLDisplayLinkCallback, (__bridge void*)self);

    CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, _context.CGLContextObj, pixelFormat.CGLPixelFormatObj);
}

- (void)viewDidLayout
{
    CGLLockContext(_context.CGLContextObj);

    NSSize viewSizePoints = _view.bounds.size;

    NSSize viewSizePixels = [_view convertSizeToBacking:viewSizePoints];

    [self makeCurrentContext];

    [_openGLRenderer resize:viewSizePixels];

    CGLUnlockContext(_context.CGLContextObj);


    if(!CVDisplayLinkIsRunning(_displayLink))
    {
        CVDisplayLinkStart(_displayLink);
    }
}

- (void) viewWillDisappear
{
    CVDisplayLinkStop(_displayLink);
}

- (void)dealloc
{
    CVDisplayLinkStop(_displayLink);

    CVDisplayLinkRelease(_displayLink);
}

#else

- (void)draw:(id)sender
{
    [EAGLContext setCurrentContext:_context];
    [_metalRenderer drawToInteropTexture:_interopTexture.metalTexture];
    [_openGLRenderer draw];

    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
    [_context presentRenderbuffer:GL_RENDERBUFFER];
}

- (void)makeCurrentContext
{
    [EAGLContext setCurrentContext:_context];
}

- (void)prepareView
{
    // Get the layer
    CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.view.layer;

    eaglLayer.drawableProperties = @{kEAGLDrawablePropertyRetainedBacking : @NO,
                                     kEAGLDrawablePropertyColorFormat     : kEAGLColorFormatRGBA8 };
    eaglLayer.opaque = YES;

    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    NSAssert(_context, @"Could Not Create OpenGL ES Context");
    
    BOOL isSetCurrent = [EAGLContext setCurrentContext:_context];
    
    NSAssert(isSetCurrent, @"Could not make OpenGL ES context current");
    
    [self makeCurrentContext];

    self.view.contentScaleFactor = [UIScreen mainScreen].nativeScale;
    
    // On iOS & tvOS you must create an FBO and attach a CoreAnimation allocated drawable texture
    // to use as the "defaultFBO" for a view
    glGenFramebuffers(1, &_defaultFBOName);
    glBindFramebuffer(GL_FRAMEBUFFER, _defaultFBOName);

    glGenRenderbuffers(1, &_colorRenderbuffer);

    [self resizeDrawable];

    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorRenderbuffer);

    // Create the display link so that we render at 60FPS
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(draw:)];

    _displayLink.preferredFramesPerSecond = 60;

    // Have the display link run on the default runn loop (and the main thread)
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
}

- (CGSize)drawableSize
{
    GLint backingWidth, backingHeight;
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
    CGSize drawableSize = {backingWidth, backingHeight};
    return drawableSize;
}

- (void)resizeDrawable
{
    [self makeCurrentContext];

    // Ensure we've actually got a render buffer first;
    assert(_colorRenderbuffer != 0);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(id<EAGLDrawable>)_view.layer];

    [_openGLRenderer resize:self.drawableSize];
}

- (void)viewDidLayoutSubviews
{
    [self resizeDrawable];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self resizeDrawable];
}

#endif


@end

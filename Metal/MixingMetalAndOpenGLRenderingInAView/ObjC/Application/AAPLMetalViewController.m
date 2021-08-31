/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the cross-platform Metal view controller
*/

#import "AAPLMetalViewController.h"
#import "AAPLMetalRenderer.h"
#import "AAPLOpenGLMetalInteropTexture.h"
#import "AAPLOpenGLRenderer.h"

static const MTLPixelFormat AAPLMetalViewInteropPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

@implementation AAPLMetalViewController
{
    MTKView *_view;

    AAPLOpenGLMetalInteropTexture *_interopTexture;
    PlatformGLContext *_openGLContext;
    AAPLMetalRenderer *_metalRenderer;
    AAPLOpenGLRenderer *_openGLRenderer;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Set the view to use the default device
    _view = (MTKView *)self.view;
    _view.device = MTLCreateSystemDefaultDevice();
    _view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

    _metalRenderer = [[AAPLMetalRenderer alloc] initWithDevice:_view.device
                                              colorPixelFormat:_view.colorPixelFormat];

    NSAssert(_metalRenderer, @"Metal Renderer failed initialization");

    // Initialize  metal renderer with the view size
    [_metalRenderer resize:_view.drawableSize];

    [self createOpenGLContext];

    // After a Metal device has been retrieved and an OpenGL context has been created and made
    // current, a interop texture can be created
    _interopTexture = [[AAPLOpenGLMetalInteropTexture alloc] initWithMetalDevice:_view.device
                                                                   openGLContext:_openGLContext
                                                                metalPixelFormat:AAPLMetalViewInteropPixelFormat
                                                                            size:AAPLInteropTextureSize];

    // Initialize OpenGL renderer to render into the interop texture
    [self intializeOpenGLRendererWithInteropTexture:_interopTexture];

    _view.delegate = self;

    // Set initial Metal rendering size to the view size
    [_metalRenderer resize:_view.drawableSize];

    // Set initial OpenGL rendering size to interop texture size
    [_openGLRenderer resize:AAPLInteropTextureSize];

    // Set interop texture as texture to sample from
    [_metalRenderer useInteropTextureAsBaseMap:_interopTexture.metalTexture];
}

- (void)createOpenGLContext
{
#if TARGET_MACOS

    NSOpenGLPixelFormatAttribute attrs[] =
    {
        NSOpenGLPFAAccelerated,
        0
    };

    NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];

    NSAssert(pixelFormat, @"No OpenGL pixel format found");

    _openGLContext = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];

#else

    _openGLContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    NSAssert(_openGLContext, @"Could Not Create OpenGL ES Context");
    
    BOOL isSetCurrent = [EAGLContext setCurrentContext:_openGLContext];
    
    NSAssert(isSetCurrent, @"Could not make OpenGL ES context current");
    
#endif
}

- (GLuint)defaultFBOWithInterOpTexture:(nonnull AAPLOpenGLMetalInteropTexture *)interopTexture
{
    GLuint defaultFBOName;
    glGenFramebuffers(1, &defaultFBOName);
    glBindFramebuffer(GL_FRAMEBUFFER, defaultFBOName);

#if TARGET_MACOS
    // macOS CVPixelBuffer textures created as rectangle textures
    const GLenum texType = GL_TEXTURE_RECTANGLE;
#else // if!(TARGET_IOS || TARGET_TVOS)
    // iOS & tvOS CVPixelBuffer textures are created as 2D textures
    const GLenum texType = GL_TEXTURE_2D;
#endif // !(TARGET_IOS || TARGET_TVOS)

    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, texType, _interopTexture.openGLTexture, 0);

    return defaultFBOName;
}

- (void)intializeOpenGLRendererWithInteropTexture:(nonnull AAPLOpenGLMetalInteropTexture *)interopTexture;
{
    // Make OpenGL context current to before issuing and OpenGL command
    [self makeCurrentContext];

    // Create a "defaultFBO" with the interop texture as the color buffer
    GLuint defaultFBOName = [self defaultFBOWithInterOpTexture:interopTexture];

    // Initialize the renderer with the FBO build with the interop texture
    _openGLRenderer = [[AAPLOpenGLRenderer alloc] initWithDefaultFBOName:defaultFBOName];

    // Indicate that the scene to render in OpenGL (texture sampled from) will be loaded from a file
    [_openGLRenderer useTextureFromFileAsBaseMap];
}

- (void)makeCurrentContext
{
#if TARGET_MACOS
    [_openGLContext makeCurrentContext];
#else // if!(TARGET_IOS || TARGET_TVOS)
    [EAGLContext setCurrentContext:_openGLContext];
#endif // !(TARGET_IOS || TARGET_TVOS)
}

- (void) drawInMTKView:(nonnull MTKView *)view
{
    [self makeCurrentContext];

    // Execute OpenGL renderer draw routine to build
    [_openGLRenderer draw];

    // When rendering to a CVPixelBuffer with OpenGL, call glFlush to ensure OpenGL commands are
    // excuted on the pixel buffer before Metal reads the buffer
    glFlush();

    [_metalRenderer drawToMTKView:view];
}

- (void) mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    [_metalRenderer resize:size];
}

@end

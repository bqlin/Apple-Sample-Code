/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the sample's main view controller that drives the main renderer.
*/

#import "AAPLGameViewController.h"
#import "AAPLMainRenderer.h"
#import "AAPLBufferFormats.h"

using namespace simd;

// List the keys in use within this sample
// The enum value is the NSEvent key code
NS_OPTIONS(uint8_t, Controls)
{
    // Keycodes that control translation
    controlsForward     = 0x0d, // W key
    controlsBackward    = 0x01, // S key
    controlsStrafeUp    = 0x31, // Spacebar
    controlsStrafeDown  = 0x08, // C key
    controlsStrafeLeft  = 0x00, // A key
    controlsStrafeRight = 0x02, // D key

    // Keycodes that control rotation
    controlsRollLeft    = 0x0c, // Q key
    controlsRollRight   = 0x0e, // E key
    controlsTurnLeft    = 0x7b, // Left arrow
    controlsTurnRight   = 0x7c, // Right arrow
    controlsTurnUp      = 0x7e, // Up arrow
    controlsTurnDown    = 0x7d, // Down arrow
    
    // The brush size
    controlsIncBrush    = 0x1E, // Right bracket
    controlsDecBrush    = 0x21, // Left bracket
    
    // Additional virtual keys
    controlsFast        = 0x80,
    controlsSlow        = 0x81
};

@implementation AAPLGameView

// Opt the window into user input first responder
- (BOOL)acceptsFirstResponder                   { return YES; }

#if TARGET_OS_OSX
- (void)awakeFromNib
{
    // Create a tracking area to keep track of the mouse movements and events
    NSTrackingAreaOptions options = (NSTrackingActiveAlways | NSTrackingInVisibleRect | NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved);
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:[self bounds]
                                                        options:options
                                                          owner:self
                                                       userInfo:nil];
    [self addTrackingArea:area];
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event      { return YES; }
#endif
@end

@implementation AAPLGameViewController
{
    // The MetalKit view containing the viewport
    MTKView* _view;
    
    // The main renderer and game logic
    AAPLMainRenderer* _renderer;
    
    // The camera that's used to view the scene
    AAPLCamera* _camera;
    
    // The current key state
    NSMutableSet<NSNumber*>* _pressedKeys;
    
    // current drag offset of mouse this frame
    float2 _mouseDrag;
}

#if (TARGET_OS_IOS)

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{

}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGPoint l0 = [((UITouch*)touches.anyObject) previousLocationInView:_view];
    CGPoint l1 = [((UITouch*)touches.anyObject) locationInView:_view];
    _mouseDrag = (simd::float2) { float(l0.x - l1.x), float(l0.y - l1.y) };
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{

    
}

-(IBAction) ModifyTerrain: (id)sender
{
    static bool busyRightNowComeBackLater = false;
    if (busyRightNowComeBackLater) return;
    busyRightNowComeBackLater = true;
    
    static int mask = 1;
    _renderer.mouseButtonMask = mask;
    mask = mask ^ 3;
    
    double delayInSeconds = 2.0;
    dispatch_time_t popTime = dispatch_time (DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after (popTime, dispatch_get_main_queue(), ^(void)
    {
        self->_renderer.mouseButtonMask = 0;
        busyRightNowComeBackLater = false;
    });
}

#else

// Capture Shift and Control keys
-(void)flagsChanged:(NSEvent*)event
{
    if (event.modifierFlags&NSEventModifierFlagShift)
        [_pressedKeys addObject:@(controlsFast)];
    else
        [_pressedKeys removeObject:@(controlsFast)];

    if (event.modifierFlags&NSEventModifierFlagControl)
        [_pressedKeys addObject:@(controlsSlow)];
    else
        [_pressedKeys removeObject:@(controlsSlow)];
}

// For capturing mouse and keyboard events
-(void)mouseExited:(NSEvent *)event         { _renderer.cursorPosition = (simd::float2) { -1, -1 }; }
-(void)rightMouseDown:(NSEvent *)event      { _renderer.mouseButtonMask |= 2; }
-(void)rightMouseUp:(NSEvent *)event        { _renderer.mouseButtonMask &= (~2); }
-(void)mouseDown:(NSEvent *)event           { _renderer.mouseButtonMask |= 1; }
-(void)mouseUp:(NSEvent *)event             { _renderer.mouseButtonMask &= (~1); }
-(void)mouseMoved:(NSEvent *)event          { _renderer.cursorPosition = (simd::float2) { static_cast<float>(event.locationInWindow.x), static_cast<float>(_view.drawableSize.height - event.locationInWindow.y) }; }
-(void)mouseDragged:(NSEvent *)event        { _mouseDrag = { (float)event.deltaX, (float)event.deltaY }; }
-(void)rightMouseDragged:(NSEvent *)event   { _mouseDrag = { (float)event.deltaX, (float)event.deltaY }; }
-(void)keyUp:(NSEvent*)event                { [_pressedKeys removeObject:[NSNumber numberWithUnsignedInteger:event.keyCode] ]; }
-(void)keyDown:(NSEvent*)event              { if (! event.ARepeat) [_pressedKeys addObject:[NSNumber numberWithUnsignedInteger:event.keyCode] ]; }

#endif

- (void) viewDidLoad
{
    [super viewDidLoad];
    _view = (MTKView*) self.view;
    
    _view.device = MTLCreateSystemDefaultDevice ();
    NSLog(@"sample running on: %@", [_view.device name]);
    
    bool isHardwareCompatible =
#if TARGET_OS_IOS
        _view.device != nil;
#else
        (_view.device != nil && [_view.device argumentBuffersSupport] == MTLArgumentBuffersTier2);
#endif
    
    if (!isHardwareCompatible)
    {
        NSLog (@"Metal (or Argument Buffers tier 2 on macOS) is not supported on this device");
        assert (false);
#if TARGET_OS_IOS
        self.view = [[UIView alloc] initWithFrame:self.view.frame];
#else
        self.view = [[NSView alloc] initWithFrame:self.view.frame];
#endif
        return;
    }
    
    _view.framebufferOnly           = NO;
    _view.colorPixelFormat          = BufferFormats::backBufferformat;
    _view.sampleCount               = 1;
#if TARGET_OS_IOS
    _view.backgroundColor           = UIColor.clearColor;
#endif
    _view.drawableSize              = (CGSize)
    {
        // Using _view.frame.size gives the "scaled" view dimesions. ie. likely not native retina resolution
        fmax(_view.frame.size.width, 320),
        fmax(_view.frame.size.height, 240)
    };

    _pressedKeys = [NSMutableSet set];
#if TARGET_OS_IOS
    const float startupAltitude = 3094.38989;
#else
    const float startupAltitude = 2694.38989;
#endif
    _camera = [[AAPLCamera alloc] initPerspectiveWithPosition:(float3) { 6183.96094, startupAltitude, 5665.08008 }
                                                    direction:(float3) { -0.56, -0.412, -0.715 }
                                                    up:(float3) { 0, 1, 0}
                                                    viewAngle:3.14159265f / 3.0f
                                                    aspectRatio:_view.drawableSize.width / _view.drawableSize.height
                                                    nearPlane:10.0f
                                                    farPlane:60000.0f];
    
    _renderer = [[AAPLMainRenderer alloc] initWithDevice:_view.device size:_view.drawableSize];
    _view.delegate = self;
    _renderer.camera = _camera;
    

    
}

- (void) mtkView:(nonnull MTKView*) view drawableSizeWillChange:(CGSize) size
{
    assert (view == _view);
    [_renderer DrawableSizeWillChange:size];
}

- (void) drawInMTKView:(nonnull MTKView*) view
{
    @autoreleasepool
    {
        // Camera manipulation through keyboard and mouse
        float translation_speed = 8.0f; // In meters
        float rotation_speed = 0.05f; // In radians
            
        // Modifier keys to speed up/slow down the camera
        if ([_pressedKeys containsObject: @(controlsFast)])         { translation_speed *= 10; }
        if ([_pressedKeys containsObject: @(controlsSlow)])         { translation_speed *= 0.1; rotation_speed *= 0.1f; }
 
        // Brush adjustments
        if ([_pressedKeys containsObject: @(controlsIncBrush)])     _renderer.brushSize *= 1.1f;
        if ([_pressedKeys containsObject: @(controlsDecBrush)])     _renderer.brushSize /= 1.1f;
        
        // Action keys to manipulate the camera
        if ([_pressedKeys containsObject: @(controlsForward)])      _camera.position += _camera.forward * translation_speed;
        if ([_pressedKeys containsObject: @(controlsStrafeRight)])  _camera.position += _camera.right * translation_speed;
        if ([_pressedKeys containsObject: @(controlsStrafeLeft)])   _camera.position += _camera.left * translation_speed;
        if ([_pressedKeys containsObject: @(controlsStrafeUp)])     _camera.position += _camera.up * translation_speed;
        if ([_pressedKeys containsObject: @(controlsStrafeDown)])   _camera.position += _camera.down * translation_speed;
        if ([_pressedKeys containsObject: @(controlsBackward)])     _camera.position += _camera.backward * translation_speed;

        if ([_pressedKeys containsObject: @(controlsTurnLeft)])     [_camera rotateOnAxis: (float3) {0, 1, 0} radians: rotation_speed ];
        if ([_pressedKeys containsObject: @(controlsTurnRight)])    [_camera rotateOnAxis: (float3) {0, 1, 0} radians: -rotation_speed ];
        if ([_pressedKeys containsObject: @(controlsTurnUp)])       [_camera rotateOnAxis:_camera.right radians: rotation_speed ];
        if ([_pressedKeys containsObject: @(controlsTurnDown)])     [_camera rotateOnAxis:_camera.right radians: -rotation_speed ];
        if ([_pressedKeys containsObject: @(controlsRollLeft)])     [_camera rotateOnAxis:_camera.direction radians: -rotation_speed ];
        if ([_pressedKeys containsObject: @(controlsRollRight)])    [_camera rotateOnAxis:_camera.direction radians: rotation_speed ];

        [_camera rotateOnAxis: (float3) {0, 1, 0}   radians: _mouseDrag.x * -0.02f ];
        [_camera rotateOnAxis: _camera.right        radians: _mouseDrag.y * -0.02f ];
        _mouseDrag = (float2) { 0, 0 };

        id<MTLDrawable> drawable = _view.currentDrawable;
        MTLRenderPassDescriptor* renderPassDescriptor = _view.currentRenderPassDescriptor;
        if (drawable != NULL && renderPassDescriptor != NULL)
        {
            [_renderer UpdateWithDrawable: drawable
                     renderPassDescriptor: renderPassDescriptor
                        waitForCompletion: false ];
        }
    }
}

@end

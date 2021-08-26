/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of our cross-platform view controller
*/

#import "AAPLViewController.h"
#import "AAPLRenderer.h"

@implementation AAPLViewController
{
    MTKView *_view;

    AAPLRenderer *_renderer;
}


#ifdef TARGET_MACOS
-(void)viewDidAppear
{
    [super viewDidAppear];

    NSSize size = {AAPLGridWidth, AAPLGridHeight};

    self.view.window.contentAspectRatio = size;
}
#endif

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Set the view to use the default device
    _view = (MTKView *)self.view;

    _view.device = MTLCreateSystemDefaultDevice();

    NSAssert(_view.device, @"Metal is not supported on this device");

    // Check for required capabilities
    if(_view.device.argumentBuffersSupport != MTLArgumentBuffersTier2)
    {
        NSAssert(0, @"This sample requires a Metal device that supports Tier 2 argument buffers.");
    }

    _renderer = [[AAPLRenderer alloc] initWithMetalKitView:_view];

    NSAssert(_renderer, @"Renderer failed initialization");

    // Initialize our renderer with the view size
    [_renderer mtkView:_view drawableSizeWillChange:_view.drawableSize];

    _view.delegate = _renderer;
}

@end

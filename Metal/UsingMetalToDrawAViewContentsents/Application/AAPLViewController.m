/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the cross-platform view controller.
*/

#import "AAPLViewController.h"
#import "AAPLRenderer.h"

@implementation AAPLViewController
{
    MTKView *_view;

    AAPLRenderer *_renderer;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _view = (MTKView *)self.view;
    
    _view.enableSetNeedsDisplay = YES;
    
    _view.device = MTLCreateSystemDefaultDevice();
    
    _view.clearColor = MTLClearColorMake(0.0, 0.5, 1.0, 1.0);

    _renderer = [[AAPLRenderer alloc] initWithMetalKitView:_view];

    if(!_renderer)
    {
        NSLog(@"Renderer initialization failed");
        return;
    }

    // Initialize the renderer with the view size.
    [_renderer mtkView:_view drawableSizeWillChange:_view.drawableSize];

    
    _view.delegate = _renderer;
    
    
}

@end

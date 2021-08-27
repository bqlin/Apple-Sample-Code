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

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Set the view to use the default device
    _view = (MTKView *)self.view;
    _view.device = MTLCreateSystemDefaultDevice();

    NSAssert(_view.device, @"Metal is not supported on this device");

    BOOL sampleSupported = NO;
#if TARGET_IOS
    sampleSupported = [_view.device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily4_v2];
#else
    sampleSupported = [_view.device supportsFeatureSet:MTLFeatureSet_macOS_GPUFamily2_v1];
#endif

    NSAssert(sampleSupported, @"Sample requires macOS_GPUFamily2_v1 or iOS_GPUFamily3_v4 for Indirect Command Buffers");

    _renderer = [[AAPLRenderer alloc] initWithMetalKitView:_view];

    NSAssert(_renderer, @"Renderer failed initialization");

    [_renderer mtkView:_view drawableSizeWillChange:_view.drawableSize];

    _view.delegate = _renderer;
}

@end

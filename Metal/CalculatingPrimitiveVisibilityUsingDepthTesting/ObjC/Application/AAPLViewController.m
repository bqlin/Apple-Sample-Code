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
    
#ifdef TARGET_MACOS
    __weak IBOutlet NSTextField *_topVertexDepthLabel;
    __weak IBOutlet NSTextField *_leftVertexDepthLabel;
    __weak IBOutlet NSTextField *_rightVertexDepthLabel;
    __weak IBOutlet NSSlider *_topVertexDepthSlider;
    __weak IBOutlet NSSlider *_leftVertexDepthSlider;
    __weak IBOutlet NSSlider *_rightVertexDepthSlider;
#else    
    __weak IBOutlet UILabel *_topVertexDepthLabel;
    __weak IBOutlet UILabel *_leftVertexDepthLabel;
    __weak IBOutlet UILabel *_rightVertexDepthLabel;
    __weak IBOutlet UISlider *_topVertexDepthSlider;
    __weak IBOutlet UISlider *_leftVertexDepthSlider;
    __weak IBOutlet UISlider *_rightVertexDepthSlider;
#endif
}

#pragma mark - macOS IBAction Methods

#ifdef TARGET_MACOS
- (IBAction)setTopVertexDepth:(NSSlider *)slider
{
    _renderer.topVertexDepth = slider.floatValue;
    _topVertexDepthLabel.stringValue = [NSString stringWithFormat:@"%.2f", _renderer.topVertexDepth];
    
}
- (IBAction)setLeftVertexDepth:(NSSlider *)slider
{
    _renderer.leftVertexDepth = slider.floatValue;
    _leftVertexDepthLabel.stringValue = [NSString stringWithFormat:@"%.2f", _renderer.leftVertexDepth];
}

- (IBAction)setRightVertexDepth:(NSSlider *)slider
{
    _renderer.rightVertexDepth = slider.floatValue;
    _rightVertexDepthLabel.stringValue = [NSString stringWithFormat:@"%.2f", _renderer.rightVertexDepth];
}
#else

#pragma mark - iOS IBAction Methods

- (IBAction)setTopVertexDepth:(UISlider *)slider {
    _renderer.topVertexDepth = slider.value;
    _topVertexDepthLabel.text =  [NSString stringWithFormat:@"%.2f", _renderer.topVertexDepth];
}

- (IBAction)setLeftVertexDepth:(UISlider *)slider {
    _renderer.leftVertexDepth = slider.value;
    _leftVertexDepthLabel.text =  [NSString stringWithFormat:@"%.2f", _renderer.leftVertexDepth];
}

- (IBAction)setRightVertexDepth:(UISlider *)slider {
    _renderer.rightVertexDepth = slider.value;
    _rightVertexDepthLabel.text = [NSString stringWithFormat:@"%.2f", _renderer.rightVertexDepth];
}

#endif
- (void)viewDidLoad
{
    [super viewDidLoad];

    // Set the view to use the default device.
    _view = (MTKView *)self.view;
    _view.device = MTLCreateSystemDefaultDevice();

    NSAssert(_view.device, @"Metal is not supported on this device");

    _renderer = [[AAPLRenderer alloc] initWithMetalKitView:_view];

    NSAssert(_renderer, @"Renderer failed initialization");

    // Initialize the renderer with the view size.
    [_renderer mtkView:_view drawableSizeWillChange:_view.drawableSize];

    _view.delegate = _renderer;
    
#ifdef TARGET_MACOS
    _renderer.topVertexDepth = _topVertexDepthSlider.floatValue;
    _topVertexDepthLabel.stringValue = [NSString stringWithFormat:@"%.2f", _renderer.topVertexDepth];
    
    _renderer.rightVertexDepth = _rightVertexDepthSlider.floatValue;
    _rightVertexDepthLabel.stringValue = [NSString stringWithFormat:@"%.2f", _renderer.rightVertexDepth];
    
    _renderer.leftVertexDepth = _leftVertexDepthSlider.floatValue;
    _leftVertexDepthLabel.stringValue = [NSString stringWithFormat:@"%.2f", _renderer.leftVertexDepth];
#else
    _renderer.topVertexDepth = _topVertexDepthSlider.value;
    _topVertexDepthLabel.text = [NSString stringWithFormat:@"%.2f", _renderer.topVertexDepth];
    
    _renderer.rightVertexDepth = _rightVertexDepthSlider.value;
    _rightVertexDepthLabel.text = [NSString stringWithFormat:@"%.2f", _renderer.rightVertexDepth];
    
    _renderer.leftVertexDepth = _leftVertexDepthSlider.value;
    _leftVertexDepthLabel.text = [NSString stringWithFormat:@"%.2f", _renderer.leftVertexDepth];
#endif
}

@end

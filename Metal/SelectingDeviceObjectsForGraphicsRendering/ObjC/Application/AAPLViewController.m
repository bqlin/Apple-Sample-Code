/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the view controller
*/

#import "AAPLViewController.h"
#import "AAPLRenderer.h"

#include <pthread.h>

// Default indices of the two drop down lists
typedef enum AAPLDeviceSelectionMode {
    AAPLDeviceSelectionModeDisplayOptimal,
    AAPLDeviceSelectionModeManual
} AAPLDeviceSelectionMode;

typedef enum AAPLHotPlugEvent {
    AAPLHotPlugEventDeviceAdded,
    AAPLHotPlugEventDeviceEjected,
    AAPLHotPlugEventDevicePulled,
} AAPLHotPlugEvent;

@implementation AAPLViewController
{
    MTKView *_view;

    NSMutableArray<AAPLRenderer*> *_rendererList;
    NSMutableArray<id<MTLDevice>> *_supportedDevices;

    NSUInteger    _currentDeviceIndex;
    id<MTLDevice> _directDisplayDevice;
    id<NSObject>  _metalDeviceObserver;

    // UI elements
    IBOutlet NSPopUpButton *_devicePolicyPopUp;
    IBOutlet NSPopUpButton *_supportedDevicePopUp;
    IBOutlet NSTextField *_directDisplayDeviceLabel;

    // Frame number, tracked in view controller not render since renderers can be switched or added
    NSUInteger _frameNumber;

    // If non-null, the device a hot-plug notification refers to
    id<MTLDevice> _hotPlugDevice;

    // If _hotPlugDevice is non-null, the type of hot-plug notification received.  Only valid if
    // _hotPlugDevice is non-null.
    AAPLHotPlugEvent _hotPlugEvent;
}

/// MTKViewDelegate callback to handle view resizes
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    [self handlePossibleHotPlugEvent];

    // Update all renderers with the new size
    for(uint32 i = 0; i < _supportedDevices.count; i++)
    {
        [_rendererList[i] updateDrawableSize:size];
    }
}

/// MTKViewDelegate callback to handle view redraw
- (void)drawInMTKView:(nonnull MTKView *)view
{
    [self handlePossibleHotPlugEvent];

    [_rendererList[_currentDeviceIndex] drawFrameNumber:_frameNumber toView:view];

    _frameNumber++;
}

/// NSViewController callback to handle view loading
- (void)viewDidLoad
{
    [super viewDidLoad];

    [_devicePolicyPopUp removeAllItems];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Auto Select Best Device for Display"
                                                  action:nil
                                           keyEquivalent:@""];
    [_devicePolicyPopUp.menu addItem:item];

    [_supportedDevicePopUp removeAllItems];
    _supportedDevicePopUp.enabled = NO;

    MTLDeviceNotificationHandler notificationHandler;

    AAPLViewController * __weak controller = self;
    notificationHandler = ^(id<MTLDevice> device, MTLDeviceNotificationName name)
    {
        [controller markHotPlugNotificationForDevice:device name:name];
    };

    // Query all supported metal devices with an observer, so the app can receive notifications
    // when external GPUs are added to or removed from the system
    id<NSObject> metalDeviceObserver = nil;
    NSArray<id<MTLDevice>> * availableDevices =
        MTLCopyAllDevicesWithObserver(&metalDeviceObserver,
                                      notificationHandler);
    
    BOOL devicesAvailable = availableDevices && availableDevices.count > 0;
    
    if(!devicesAvailable) NSAssert(devicesAvailable, @"No Metal support on this Mac");

    // Save observer reference so we can remove observer upon exit
    _metalDeviceObserver = metalDeviceObserver;

    // Init view
    _view = (MTKView *)self.view;
    _view.delegate = self;
    _view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    _view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    _view.sampleCount = 1;

    // Initialize a renderer for each device including loading all assets for that renderer

    _rendererList = [NSMutableArray new];
    _supportedDevices = [NSMutableArray new];

    // Initialize the renderer for all devices now even though app will only render on one device at
    // a time.  This way, if a new device becomes available or the window is moved on to a display
    // driven by by another device, the renderer can immediately switch to that device.  Otherwise
    // the app would need to initialize the renderer when the switch occurred.  This would cause
    // stall to rendering during the switch as the renderer loads resources at that time.

    for(uint32 i = 0; i < availableDevices.count; i++)
    {
        id<MTLDevice> device = availableDevices[i];

        if(![self initalizeDevice:device])
        {
            return;
        }
    }
}

/// NSViewController callback to handle view appearing
- (void)viewDidAppear
{
    [self chooseSystemPreferredDevice];

    [self registerForDisplayChangeNotifications];
}

/// Initializes device with Renderer and also updated UI elements
- (BOOL)initalizeDevice:(id<MTLDevice>)device
{
    AAPLRenderer *rendererForDevice =
        [[AAPLRenderer alloc] initWithMetalKitView:_view
                                            device:(id<MTLDevice>)device];

    NSAssert(rendererForDevice, @"Renderer initialization failed for device %@", device.name);

    [_rendererList addObject:rendererForDevice];

    NSLog(@"Added device %@ to supported device list", device.name);

    [_supportedDevices addObject:device];

    // Now add device to UI list for user to select.
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:device.name action:nil keyEquivalent:@""];
    item.representedObject = device;
    [_supportedDevicePopUp.menu addItem:item];

    // Add "Custom" item to device preference button only if you have more than 1 device support.
    if(_supportedDevices.count > 1 && [_devicePolicyPopUp indexOfItemWithTitle:@"Manually Select Device"] == -1)
    {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Manually Select Device" action:nil keyEquivalent:@""];
        [_devicePolicyPopUp.menu addItem:item];
    }

    [rendererForDevice updateDrawableSize:_view.drawableSize];

    return YES;
}

/// Register for notifications for when displays have been added or removed or when the view's
/// window has moved to a different display
- (void)registerForDisplayChangeNotifications
{
    // Register for the NSApplicationDidChangeScreenParametersNotification, which triggers
    // when the system's display configuration changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleScreenChanges:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];

    // Register for the NSWindowDidChangeScreenNotification, which triggers when the window
    // changes screens
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleScreenChanges:)
                                                 name:NSWindowDidChangeScreenNotification
                                               object:nil];
}

// Remove all renderer assets associated with device and also update UI elements to reflect the
// device's removal
- (void)removeDevice:(id<MTLDevice>)device
{
    NSLog(@"Removing device %@ from supported device list", device.name);

    for(NSUInteger index = 0; index < _rendererList.count; index++)
    {
        if(_rendererList[index].device == device)
        {
            [_rendererList removeObjectAtIndex:index];
            break;
        }
    }

    [_supportedDevices removeObject:device];

    NSUInteger menuIndex = [_supportedDevicePopUp.menu indexOfItemWithRepresentedObject:device];

    NSMenuItem *item = [_supportedDevicePopUp itemAtIndex:menuIndex];

    item.representedObject = nil;

    [_supportedDevicePopUp.menu removeItemAtIndex:menuIndex];

    // If there is only one device, it doesn't make sense to have a "Custom" option so remove it
    NSInteger itemIndex = [_devicePolicyPopUp indexOfItemWithTitle:@"Custom"];
    if(_supportedDevices.count <= 1 && itemIndex != -1)
    {
        [_devicePolicyPopUp.menu removeItemAtIndex:itemIndex];
    }
}

/// Query for the best device to display the view in its currently location (i.e. query for
/// the device driving the display that the view is on)
- (void)queryForDeviceDrivingDisplay
{
    _directDisplayDevice = nil;

    // Get the display ID of the display in which the view appears
    CGDirectDisplayID viewDisplayID = (CGDirectDisplayID) [_view.window.screen.deviceDescription[@"NSScreenNumber"] unsignedIntegerValue];

    // Get the Metal device that drives the display
    id<MTLDevice> newPreferredDevice = CGDirectDisplayCopyCurrentMetalDevice(viewDisplayID);
    NSLog(@"Current device driving display %@", newPreferredDevice.name);

    if(viewDisplayID == 0 || newPreferredDevice == nil)
    {
        // This could also occur if there is no display attached or Metal is not supported by the
        // device driving the display,.
        NSLog(@"Could not get a device driving display");
        return;
    }

    // If the old preferred device is not the new preferred device, set the preferred device
    // so long as it's already in the supported devices list
    if(_directDisplayDevice != newPreferredDevice)
    {
        for(uint32 i = 0; i < _supportedDevices.count; i++)
        {
            if(newPreferredDevice == _supportedDevices[i])
            {
                _directDisplayDevice = _supportedDevices[i];
            }
        }
    }
}

- (void) chooseSystemPreferredDevice
{
    [self queryForDeviceDrivingDisplay];

    if(!_directDisplayDevice)
    {
        // Deal with not being able to obtain a Metal device for GPU driving the display
        [self handleDeviceSelection:MTLCreateSystemDefaultDevice()];
    }
    else if(((_devicePolicyPopUp.indexOfSelectedItem == AAPLDeviceSelectionModeDisplayOptimal) &&
             (_supportedDevices[_currentDeviceIndex] != _directDisplayDevice)) ||
            (_view.device == nil))
    {
        // If the view is not already using the _directDisplayDevice, switch to system preferred
        // device if "system" is selected in _devicePolicyPopUp
        [self handleDeviceSelection:_directDisplayDevice];
    }
}

/// Called when a NSApplicationDidChangeScreenParametersNotification if there are changes to screen when and
/// occurs or when the window is moved to another screen and NSWindowDidChangeScreenNotification occurs
- (void)handleScreenChanges:(NSNotification *)notification
{
    NSLog(@"Got: NSApplicationDidChangeScreenParametersNotification or NSWindowDidChangeScreenNotification");

    [self chooseSystemPreferredDevice];
}

- (void)handlePossibleHotPlugEvent
{
    AAPLHotPlugEvent hotPlugEvent;
    id<MTLDevice> hotPlugDevice;

    @synchronized(self)
    {
        hotPlugEvent = _hotPlugEvent;
        hotPlugDevice = _hotPlugDevice;
        _hotPlugDevice = nil;
    }

    if(hotPlugDevice)
    {
        switch (hotPlugEvent)
        {
            case AAPLHotPlugEventDeviceAdded:
                [self handleMTLDeviceAddedNotification:hotPlugDevice];
                break;
            case AAPLHotPlugEventDeviceEjected:
            case AAPLHotPlugEventDevicePulled:
                [self handleMTLDeviceRemovalNotification:hotPlugDevice];
                break;
        }
    }
}

/// Called bu Metal whenever external GPU is added or removed
- (void)markHotPlugNotificationForDevice:(nonnull id<MTLDevice>)device
                                    name:(nonnull MTLDeviceNotificationName)name
{
    @synchronized(self)
    {
        if ([name isEqualToString:MTLDeviceWasAddedNotification])
        {
            _hotPlugEvent = AAPLHotPlugEventDeviceAdded;
        }
        else if ([name isEqualToString:MTLDeviceRemovalRequestedNotification])
        {
            _hotPlugEvent = AAPLHotPlugEventDeviceEjected;
        }
        else if ([name isEqualToString:MTLDeviceWasRemovedNotification])
        {
            _hotPlugEvent = AAPLHotPlugEventDevicePulled;
        }

        _hotPlugDevice = device;
    }
}

/// Initializes the render assets for newly added device
- (void)handleMTLDeviceAddedNotification:(id<MTLDevice>)device
{
    NSLog(@"handleMTLDeviceAddedNotification %@", device.name);

    NSAssert(![_supportedDevices containsObject:device],
             @"Error %@ Device is already in the list",
             device.name);

    [self initalizeDevice:device];
}

/// Switches to system preferred device and cleanup assets associated with device being removed
- (void)handleMTLDeviceRemovalNotification:(id<MTLDevice>)device
{
    NSLog(@"handleMTLDeviceRemovalNotification %@", device.name);

    id<MTLDevice> currentDevice = _supportedDevices[_currentDeviceIndex];


    // Remove the device from our list
    if([_supportedDevices containsObject:device])
    {
        // Determine if it's necessary to switch to another device since the currently selected
        // device has been removed.  Muse be done before we remove the device
        BOOL usingRemovedDevice = (currentDevice == device);

        [self removeDevice:device];

        // Select a new device if necessary (Must do this after removal since indices will have changed)
        if(usingRemovedDevice)
        {
            // Query system preferred renderer.
            [self queryForDeviceDrivingDisplay];

            // The _directDisplayDevice should never be the device that was removed
            NSAssert(_directDisplayDevice != device, @"_directDisplayDevice will never be the device that was removed");

            if(_directDisplayDevice)
            {
                // Switch to new system preferred device
                [self handleDeviceSelection:_directDisplayDevice];
            }
            else
            {
                [self handleDeviceSelection:MTLCreateSystemDefaultDevice()];
            }
        }
        else
        {
            // Indices in _supportedDevices and _rendererList may have shifted when we remove the
            // device, so _currentDeviceIndex must be updated
            _currentDeviceIndex = [_supportedDevices indexOfObject:currentDevice];
        }
    }
}

/// Switch App rendering to given device.
- (void)handleDeviceSelection:(id<MTLDevice>)device
{
    _view.device = device;

    _currentDeviceIndex = [_supportedDevices indexOfObject:device];

    [self updateDeviceListMenuSelection:device];
}

/// Updates device list popup selection
- (void)updateDeviceListMenuSelection: (id<MTLDevice>)device
{
    // Update current device selection in popup box
    for (NSMenuItem *item in _supportedDevicePopUp.menu.itemArray)
    {
        if ([device isEqual:item.representedObject])
        {
            [_supportedDevicePopUp selectItem:item];
        }
    }

    if(!_directDisplayDevice)
    {
        _directDisplayDeviceLabel.stringValue = @"None";
    }
    else if(device == _directDisplayDevice)
    {
        _directDisplayDeviceLabel.stringValue = _directDisplayDevice.name;
        [_devicePolicyPopUp selectItemAtIndex:AAPLDeviceSelectionModeDisplayOptimal];
        _supportedDevicePopUp.enabled = false;
    }
}

/// Updates display preference popup selection
- (void)updatePreferenceMenuSelection:(NSInteger)index
{
    // User selected the device driving the display as preference
    if(index == AAPLDeviceSelectionModeDisplayOptimal)
    {
        // Disable supported list UI element so user cannot select device from list
        _supportedDevicePopUp.enabled = NO;

        // And switch to system preferred device.
        if(_supportedDevices[_currentDeviceIndex] != _directDisplayDevice)
        {
            [self handleDeviceSelection:_directDisplayDevice];
        }
    }
    // User selected custom device as preference.
    else if(index == AAPLDeviceSelectionModeManual)
    {
        // Enable supported list UI element so user can select device from list
        _supportedDevicePopUp.enabled = YES;
    }
}

/// Handles user changes to device preferences popup
- (IBAction)changePreference:(id)sender
{
    NSInteger index = _devicePolicyPopUp.indexOfSelectedItem;

    [self updatePreferenceMenuSelection:index];
}

/// Handles switch to custom device selection popup
- (IBAction)changeRenderer:(id)sender
{
    id<MTLDevice> device = _supportedDevicePopUp.selectedItem.representedObject;

    NSLog(@"Application requested switch to %@", device.name);
    
    [self handleDeviceSelection:device];
}

/// Remove observers when the view disappears
- (void)viewDidDisappear
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSApplicationDidChangeScreenParametersNotification
                                                  object:nil];

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSWindowDidChangeScreenNotification
                                                  object:nil];

    MTLRemoveDeviceObserver(_metalDeviceObserver);
}

@end

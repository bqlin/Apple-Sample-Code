/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the macOS view controller
*/

#import "AAPLViewController.h"
#import "AAPLRenderer.h"
#import "AAPLSimulation.h"

// Enum indicating reason for execution of Metal device notification handler block
typedef enum AAPLHotPlugEvent {
    AAPLHotPlugEventDeviceAdded,
    AAPLHotPlugEventDeviceEjected,
    AAPLHotPlugEventDevicePulled,
} AAPLHotPlugEvent;

// Table with various simulation configurations.  Apps would typically load simulation parameters
// such as these from a file or UI controls, but to simplify the sample and focus on Metal usage,
// this table is hardcoded
static const AAPLSimulationConfig AAPLSimulationConfigTable[] =
{
    // damping softening numBodies clusterScale velocityScale renderScale renderBodies simInterval simDuration
    {      1.0,    1.000,    65536,        1.54,            8,       25.0,        8192,     0.0160,        2.0 },
    {      1.0,    1.000,    65536,        0.32,          276,        2.5,        8192,     0.0006,        0.3 },
    {      1.0,    0.100,    65536,        0.68,           20,     1700.0,        8192,     0.0160,        3.0 },
    {      1.0,    1.000,    65536,        1.54,            8,       25.0,        8192,     0.0160,        3.0 },
    {      1.0,    1.000,    65536,        6.04,            0,      300.0,        8192,     0.0160,        3.0 },
    {      1.0,    0.145,    65536,        0.32,          272,        2.5,        8192,     0.0006,        0.3 },
};

static const NSUInteger AAPLNumSimulationConfigs = sizeof(AAPLSimulationConfigTable) / sizeof(AAPLSimulationConfig);

static const CFTimeInterval AAPLSecondsToPresentSimulationResults = 4.0;

@implementation AAPLViewController
{
    MTKView *_view;

    AAPLRenderer *_renderer;

    AAPLSimulation *_simulation;

    id<NSObject> _metalDeviceObserver;

    // The current time (in simulation time units) that the simulation has processed
    CFAbsoluteTime _simulationTime;

    // When rendering is paused (such as immediately after a simulation has completed), the time
    // to unpause and continue simulations.
    CFAbsoluteTime _continuationTime;

    // If non-null, the device a hot-plug notification refers to
    id<MTLDevice> _hotPlugDevice;

    // If _hotPlugDevice is non-null, the type of hot-plug notification received.  Only valid if
    // _hotPlugDevice is non-null.
    AAPLHotPlugEvent _hotPlugEvent;

    id<MTLDevice> _computeDevice;

    // Index of the current simulation config in the simulation config table
    NSUInteger _configNum;

    // Currently running simulation config
    const AAPLSimulationConfig *_config;

    // Command queue used when simulation and renderer are using the same device.
    // Set to nil when using different devices
    id<MTLCommandQueue> _commandQueue;

    // When true, stop running any more simulations (such as when the window closes).
    BOOL _terminateAllSimulations;

    // When true, restart the current simulation if it was interrupted and data could not
    // be retrieved
    BOOL _restartSimulation;

    // UI showing current simulation name and percentage complete
    IBOutlet NSTextField *_simulationName;
    IBOutlet NSTextField *_simulationPercentage;

    // Timer used to make the text fields blink when results have been completed
    NSTimer *_blinker;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Set the view to use the default device
    _view = (MTKView *)self.view;

    [self selectDevices];

    _view.delegate = self;
}

- (void)viewDidAppear
{
    [self beginSimulation];
}

- (void)viewDidDisappear
{
    MTLRemoveDeviceObserver(_metalDeviceObserver);

    @synchronized(self)
    {
        // Stop simulation if on another thread
        _simulation.halt = YES;

        // Indicate that simulation should not continue and results will not be needed
        _terminateAllSimulations = YES;
    }
}

- (void)selectDevices
{
    NSArray<id<MTLDevice>> * availableDevices = nil;

    // Query for available devices and set observer block
    {

        AAPLViewController * __weak controller = self;

        MTLDeviceNotificationHandler notificationHandler;

        notificationHandler = ^(id<MTLDevice> device, MTLDeviceNotificationName name)
        {
            [controller markHotPlugNotificationForDevice:device name:name];
        };

        // Query all supported metal devices with observer so app can get external device add/remove notifications
        id<NSObject> metalDeviceObserver = nil;

        availableDevices = MTLCopyAllDevicesWithObserver(&metalDeviceObserver,
                                                         notificationHandler);

        if(availableDevices == nil || ([availableDevices count] == 0))
        {
            assert(!"Metal is not supported on this Mac");
            self.view = [[NSView alloc] initWithFrame:self.view.frame];
            return;
        }

        MTLRemoveDeviceObserver(_metalDeviceObserver);

        // Save observer reference so we can remove observer upon exit
        _metalDeviceObserver = metalDeviceObserver;
    }

    // Select compute device
    {
        _computeDevice = MTLCreateSystemDefaultDevice();

        for(id<MTLDevice> device in availableDevices)
        {
            if(device.isRemovable)
            {
                // Select removable device if available since if there is one, it's probably the most
                // powerful device available
                _computeDevice = device;
                break;
            }
            else if(device.isHeadless)
            {
                // Select headless device since if there is one it's probably dedicated to compute
                // tasks
                _computeDevice = device;
            }
        }

        NSLog(@"Selected compute device: %@", _computeDevice.name);
    }

    // Select renderer device (stored as _view.device)
    {
        // Query for device driving the display
        CGDirectDisplayID viewDisplayID = (CGDirectDisplayID) [_view.window.screen.deviceDescription[@"NSScreenNumber"] unsignedIntegerValue];

        id<MTLDevice> rendererDevice = CGDirectDisplayCopyCurrentMetalDevice(viewDisplayID);

        if(rendererDevice != _view.device)
        {
            _view.device = rendererDevice;

            NSLog(@"New render device: %@", _view.device.name);

            _renderer = [[AAPLRenderer alloc] initWithMetalKitView:_view];

            if(!_renderer)
            {
                NSLog(@"Renderer failed initialization");
                return;
            }

            [self mtkView:_view drawableSizeWillChange:_view.drawableSize];
        }
    }
}

- (void)beginSimulation
{
    _simulationTime = 0;

    _simulationName.stringValue = [[NSString alloc]initWithFormat:@"Simulation %lu", _configNum];
    _config = &AAPLSimulationConfigTable[_configNum];

    _simulation = [[AAPLSimulation alloc] initWithComputeDevice:_computeDevice
                                                                config:_config];

    [_renderer setRenderScale:_config->renderScale withDrawableSize:_view.drawableSize];

    NSLog(@"Starting Simulation Config: %lu", _configNum);

    if(_computeDevice == _renderer.device)
    {
        // If the device used for rendering and compute are the same, create a command queue shared
        // by both components
        _commandQueue = [_renderer.device newCommandQueue];
    }
    else
    {
        // If the device used for rendering is different than that used for compute, run the
        // the simulation asynchronously on the compute device
        [self runSimulationOnAlternateDevice];
    }
}

// Asynchronously begins or continues a simulation on a different than the device used for rendering
- (void)runSimulationOnAlternateDevice
{
    assert(_computeDevice != _renderer.device);

    _commandQueue = nil;

    AAPLDataUpdateHandler updateHandler = ^(NSData * __nonnull updateData,
                                            CFAbsoluteTime simulationTime)
    {
        // Update the renderer's position data so that it can show forward progress
        [self updateWithNewPositionData:updateData
                      forSimulationTime:simulationTime];
    };

    AAPLFullDatasetProvider dataProvider = ^(NSData * __nonnull positionData,
                                             NSData * __nonnull velocityData,
                                             CFAbsoluteTime simulationTime)
    {
        [self handleFullyProvidedSetOfPositionData:positionData
                                      velocityData:velocityData
                                 forSimulationTime:simulationTime];
    };

    [_simulation runAsyncWithUpdateHandler:updateHandler
                              dataProvider:dataProvider];
}

/// Receive and update of new positions for the simulation time given.
- (void) updateWithNewPositionData:(nonnull NSData*)updateData
                 forSimulationTime:(CFAbsoluteTime)simulationTime
{
    // Lock with updateData so thus thread does not update data during an update on another thread
    @synchronized(updateData)
    {
        // Update the renderer's position data so that it can show forward progress
        [_renderer providePositionData:updateData];
    }

    // Lock around _simulation time since it will be accessed on another thread
    @synchronized(self)
    {
        _simulationTime = simulationTime;
    }
}

// Handle the passing of full data set from asynchronous simulation executed on device different
// the the device used for rendering
- (void)handleFullyProvidedSetOfPositionData:(nonnull NSData *)positionData
                                velocityData:(nonnull NSData *)velocityData
                           forSimulationTime:(CFAbsoluteTime)simulationTime
{
    @synchronized(self)
    {
        if(_terminateAllSimulations)
        {
            NSLog(@"Terminating all simulations");
            return;
        }
        _simulationTime = simulationTime;

        if(_simulationTime >= _config->simDuration)
        {
            NSLog(@"Simulation Config %lu Complete", _configNum);

            // If the simulation is complete, provide all the final positions to render
            [_renderer providePositionData:positionData];
        }
        else
        {
            NSLog(@"Simulation Config %lu Cannot complete with current simulation object", _configNum);
            // If the simulation is not complete, this indicates that compute device cannot complete
            // the simulation, so data has been transferred from that device so the app can continue
            // the simulation on another device

            // Reselect a new device to continue the simulation
            [self selectDevices];

            // Create a new simulation object with the data provided
            _simulation = [[AAPLSimulation alloc] initWithComputeDevice:_computeDevice
                                                                 config:_config
                                                           positionData:positionData
                                                           velocityData:velocityData
                                                      forSimulationTime:simulationTime];

            if(_computeDevice == _renderer.device)
            {
                // If the device used for rendering and compute are the same, create a command queue shared
                // by both components
                _commandQueue = [_renderer.device newCommandQueue];
            }
            else
            {
                // If the device used for rendering is different than that used for compute, run the
                // the simulation asynchronously on the compute device
                [self runSimulationOnAlternateDevice];
            }
        }
    }
}

/// Called by Metal whenever external GPU is added or removed.  This is not necessarily executed
//  on the main thread, so only mark the event, but don't fully respond to it
- (void)markHotPlugNotificationForDevice:(nonnull id<MTLDevice>)device
                                    name:(nonnull MTLDeviceNotificationName)name
{
    // Synchronize around _hotPlugEvent and _hotPlugDevice since they are read on another thread
    @synchronized(self)
    {
        if ([name isEqualToString:MTLDeviceWasAddedNotification])
        {
            _hotPlugEvent = AAPLHotPlugEventDeviceAdded;
            NSLog(@"Hot Plug Notification Device Added");
        }
        else if ([name isEqualToString:MTLDeviceRemovalRequestedNotification])
        {
            _hotPlugEvent = AAPLHotPlugEventDeviceEjected;
            NSLog(@"Hot Plug Notification Device Ejected");
        }
        else if ([name isEqualToString:MTLDeviceWasRemovedNotification])
        {
            _hotPlugEvent = AAPLHotPlugEventDevicePulled;
            NSLog(@"Hot Plug Notification Device Pulled");
        }

        _hotPlugDevice = device;
    }
}

/// Deal with the hot plug even on the main thread
- (void)handlePossibleHotPlugEvent
{
    AAPLHotPlugEvent hotPlugEvent;
    id<MTLDevice> hotPlugDevice;

    // Synchronize around _hotPlugEvent and _hotPlugDevice since are written on another thread
    @synchronized(self)
    {
        hotPlugEvent = _hotPlugEvent;
        hotPlugDevice = _hotPlugDevice;
        _hotPlugDevice = nil;
    }
    if(hotPlugDevice == _computeDevice)
    {
        if(hotPlugEvent == AAPLHotPlugEventDeviceEjected)
        {
            NSLog(@"Compute Hot Plug Device Ejection for %@", hotPlugDevice.name);
            // Halt simulation (occurring on another thread )that it must stop due to its device
            // getting ejected.
            // Note that when the simulation is halted, it will call back to the view controller
            // which will create a new simulation with a new device. (So no need to select a
            // new compute device now)
            _simulation.halt = YES;
        }
        else if(hotPlugEvent == AAPLHotPlugEventDevicePulled)
        {
            NSLog(@"Compute Hot Plug Device Pulled for %@", hotPlugDevice.name);
            // Halt simulation (occurring on another thread ) since device no longer attached and
            // Metal commands will be sent to oblivion.
            // Note that when the simulation is halted, it will call back to the view controller
            // which will create a new simulation with a new device. (So no need to select a
            // new compute device now)
            _simulation.halt = YES;

            // If the device is gone, there is no opportunity to transfer results back so restart
            // the simulation.  (A more robust implementation would occasionally save all simulation
            // data and restart the simulation with that intermediate data instead fully restarting
            // the simulation)
            _restartSimulation = YES;
        }
    }
}

/// Called whenever view changes orientation or layout is changed
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    [_renderer drawableSizeWillChange:size];
}

/// Called whenever the view needs to render
- (void)drawInMTKView:(MTKView *)view
{
    CFAbsoluteTime currentTime = CACurrentMediaTime();

    [self handlePossibleHotPlugEvent];

    // Number of bodies to render this frame
    NSUInteger numBodies = _config->renderBodies;

    // Handle simulations completion
    if(_simulationTime >= _config->simDuration)
    {
        // If the simulation is over, render all the bodies in the simulation to show final results
        numBodies = _config->numBodies;

        if(_continuationTime == 0)
        {
            _continuationTime = currentTime + AAPLSecondsToPresentSimulationResults;

            // Make text blink while showing final results (so it doesn't look like the app hung)
            _simulationName.stringValue = [[NSString alloc]initWithFormat:@"Simulation %lu Complete", _configNum];

            void (^animationGroup)(NSAnimationContext *context) = ^(NSAnimationContext *context)
            {
                context.duration = 0.55;
                self->_simulationName.animator.alphaValue = 0.0;
                self->_simulationPercentage.animator.alphaValue = 0.0;
            };

            void (^animationCompletion)(void) = ^()
            {
                self->_simulationName.alphaValue = 1.0;
                self->_simulationPercentage.alphaValue = 1.0;
            };

            void (^blinkyBlock)(NSTimer *timer) =  ^(NSTimer *timer)
            {
                [NSAnimationContext runAnimationGroup:animationGroup
                                    completionHandler:animationCompletion];
            };

            _blinker = [NSTimer scheduledTimerWithTimeInterval:1.1
                                                       repeats:true
                                                         block:blinkyBlock];

            [_blinker fire];

        }
        else if(currentTime >= _continuationTime)
        {
            // If the continuation time has been reached, select a new simulation and begin execution
            _configNum = (_configNum + 1) % AAPLNumSimulationConfigs;

            _continuationTime = 0;

            [_blinker invalidate];

            _blinker = nil;

            [self selectDevices];

            [self beginSimulation];
        }
        else
        {
            // If showing final results, don't unnecessarily redraw
            return;
        }
    }

    // If the simulation and device are using the same device _commandQueue will be set
    if(_commandQueue)
    {
        // Create a command buffer to both execute a simulation frame and render an update
        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

        [commandBuffer pushDebugGroup:@"Controller Frame"];

        // Simulate the frame and obtain the new positions for the update.  If this is the final
        // frame positionBuffer will be filled with the all positions used for the simulation
        id<MTLBuffer> positionBuffer = [_simulation simulateFrameWithCommandBuffer:commandBuffer];

        // Render the updated positions (or all positions in the case that the simulation is complete)
        [_renderer drawWithCommandBuffer:commandBuffer
                         positionsBuffer:positionBuffer
                               numBodies:numBodies
                                  inView:_view];

        [commandBuffer commit];

        [commandBuffer popDebugGroup];

        _simulationTime += _config->simInterval;
    }
    else
    {
        [_renderer drawProvidedPositionDataWithNumBodies:numBodies
                                                  inView:_view];
    }

    NSUInteger percentComplete;

    // Lock when using _simulationTime since it can be updated on a separate thread
    @synchronized(self)
    {
        percentComplete = (_simulationTime / _config->simDuration) * 100;
    }

    if(percentComplete < 100)
    {
        _simulationPercentage.stringValue = [NSString stringWithFormat:@"%lu%%", percentComplete];
    }
    else
    {
        _simulationPercentage.stringValue = @"Final Result";
    }
}

@end

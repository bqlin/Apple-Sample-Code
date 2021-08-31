/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Interface for the class responsible for executing the N-Body simulation, provide updates and final data set
*/

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>
#import "AAPLShaderTypes.h"

// Parameters to perform the N-Body simulation
typedef struct AAPLSimulationConfig {
    float          damping;       // Factor for reducing simulation instability
    float          softeningSqr;  // Factor for simulating collisions
    uint32_t       numBodies;     // Number of bodies in the simulations
    float          clusterScale;  // Factor for grouping the initial set of bodies
    float          velocityScale; // Scaling of  each body's speed
    float          renderScale;   // The scale of the viewport to render the results
    NSUInteger     renderBodies;  // Number of bodies to transfer and render for an intermediate update
    float          simInterval;   // The "time" (in "simulation time" units) of each frame of the simulation
    CFAbsoluteTime simDuration;   // The "duration" (in "simulation time" units) for the simulation
} AAPLSimulationConfig;

// Block executed by simulation when run asynchronously whenever simulation has made forward
// progress.  Provides an array of vector_float4 elements representing a summary of positions
// calculated by the simulation at the given simulation time
typedef void (^AAPLDataUpdateHandler)(NSData * __nonnull updateData,
                                      CFAbsoluteTime simulationTime);

// Block executed by asynchronous simulation simulation is complete or has been halted (such as
// when the simulation device has been ejected).  Provides all data at the given simulation time so
// that it can be rendered (if the simulation time is greater than the configuration's duration)
// or continued on another device (if the simulation time is less than the configuration's duration)
typedef void (^AAPLFullDatasetProvider)(NSData * __nonnull positionData,
                                        NSData * __nonnull velocityData,
                                        CFAbsoluteTime simulationTime);

// Interface of class performing the compute simulation
@interface AAPLSimulation : NSObject

// Initializer used to start a simulation already from the beginning
- (nonnull instancetype)initWithComputeDevice:(nonnull id<MTLDevice>)computeDevice
                                       config:(nonnull const AAPLSimulationConfig *)config;

// Initializer used to continue a simulation already begun on another device
- (nonnull instancetype)initWithComputeDevice:(nonnull id<MTLDevice>)computeDevice
                                       config:(nonnull const AAPLSimulationConfig *)config
                                 positionData:(nonnull NSData *)positionData
                                 velocityData:(nonnull NSData *)velocityData
                            forSimulationTime:(CFAbsoluteTime)simulationTime;

// Execute simulation on another thread, providing updates and final results with supplied blocks
- (void)runAsyncWithUpdateHandler:(nonnull AAPLDataUpdateHandler)updateHandler
                     dataProvider:(nonnull AAPLFullDatasetProvider)dataProvider;

// Execute a single frame of the simulation (on the current thread)
- (nonnull id<MTLBuffer>)simulateFrameWithCommandBuffer:(nonnull id<MTLCommandBuffer>)commandBuffer;

// When set to true, stop an asynchronously executed simulation
@property (atomic) BOOL halt;

@end


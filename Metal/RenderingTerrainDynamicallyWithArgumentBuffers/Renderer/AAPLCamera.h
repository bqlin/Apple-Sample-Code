/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Declaration of the AAPLCamera object.
*/

#import <Foundation/Foundation.h>
#import <simd/simd.h>

#import "AAPLMainRenderer_shared.h"

// The camera object has only six writable properties:
// - position, direction, up define the orientation and position of the camera
// - nearPlane and farPlane define the projection planes
// - viewAngle defines the view angle in radians
//  All other properties are generated from these values.
//  - Note: the AAPLCameraUniforms struct is populated lazily on demand to reduce CPU overhead

@interface AAPLCamera : NSObject
{
    // Internally generated camera uniforms used/defined by the renderer
    AAPLCameraUniforms _uniforms;
    
    // A boolean value that denotes if the intenral uniforms structure needs rebuilding
    bool _uniformsDirty;

    // - Note: The camera can be either perspective or parallel, depending on a defined angle OR a defined width
    
    // Full view angle inradians for perspective view; 0 for parallel view
    float _viewAngle;
    
    // Width of back plane for parallel view; 0 for perspective view
    float _width;
    
    // Direction of the camera; is normalized
    simd::float3 _direction;
    
    // Position of the camera/observer point
    simd::float3 _position;
    
    // Up direction of the camera; perpendicular to _direction
    simd::float3 _up;
    
    // Distance of the near plane to _position in world space
    float _nearPlane;
    
    // Distance of the far plane to _position in world space
    float _farPlane;
    
    // Aspect ratio of the horizontal against the vertical (widescreen gives < 1.0 value)
    float _aspectRatio;
}

// Updates internal uniforms from the various properties
-(void) updateUniforms;

// Rotates camera around axis; updating many properties at once
-(void) rotateOnAxis: (simd::float3) inAxis radians: (float) inRadians;
-(instancetype) initPerspectiveWithPosition:(simd::float3)position
                               direction:(simd::float3) direction
                               up:(simd::float3)up
                               viewAngle:(float) viewAngle
                               aspectRatio:(float) aspectRatio
                               nearPlane:(float) nearPlane
                               farPlane:(float) farPlane;

-(instancetype) initParallelWithPosition:(simd::float3)position
                               direction:(simd::float3) direction
                               up:(simd::float3)up
                               width:(float) width
                               height:(float) height
                               nearPlane:(float) nearPlane
                               farPlane:(float) farPlane;

// Internally generated uniform; maps to _uniforms
@property (readonly) AAPLCameraUniforms uniforms;

// Left of the camera
@property (readonly) simd::float3 left;

// Right of the camera
@property (readonly) simd::float3 right;

// Down direction of the camera
@property (readonly) simd::float3 down;

// Facing direction of the camera (alias of direction)
@property (readonly) simd::float3 forward;

// Backwards direction of the camera
@property (readonly) simd::float3 backward;

// Returns true if perspective (viewAngle != 0, width == 0)
@property (readonly) bool isPerspective;

// Returns true if perspective (width != 0, viewAngle == 0)
@property (readonly) bool isParallel;

// Position/observer point of the camera
@property simd::float3 position;

// Facing direction of the camera
@property simd::float3 direction;

// Up direction of the camera; perpendicular to direction
@property simd::float3 up;

// Full viewing angle in radians
@property float viewAngle;

// Aspect ratio in width / height
@property float aspectRatio;

// Distance from near plane to observer point (position)
@property float nearPlane;

// Distance from far plane to observer point (position)
@property float farPlane;

// Accessors for position, direction, angle
-(float) viewAngle;
-(float) width;
-(simd::float3) position;
-(simd::float3) direction;
-(float) nearPlane;
-(float) farPlane;
-(float) aspectRatio;
-(AAPLCameraUniforms) uniforms;

-(bool) isPerspective;
-(bool) isParallel;

// Accessors for read-only derivitives
-(simd::float3) left;
-(simd::float3) right;
-(simd::float3) down;
-(simd::float3) forward;
-(simd::float3) backward;

// Setters for posing properties
-(void) setViewAngle:   (float)         newAngle;
-(void) setWidth:       (float)         newWidth;
-(void) setPosition:    (simd::float3)  newPosition;
-(void) setDirection:   (simd::float3)  newDirection;
-(void) setNearPlane:   (float)         newNearPlane;
-(void) setFarPlane:    (float)         newFarPlane;
-(void) setAspectRatio: (float)         newAspectRatio;
@end

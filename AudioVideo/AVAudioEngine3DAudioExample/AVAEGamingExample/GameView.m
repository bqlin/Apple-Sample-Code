/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    GameView
*/

#import "GameView.h"
#import "AudioEngine.h"

@interface GameView()

@property (readwrite) CGPoint previousTouch;

@end

@implementation GameView


- (void)awakeFromNib
{
    [super awakeFromNib];
    
#if TARGET_OS_IOS || TARGET_OS_TV
    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGesture:)]];
#endif
}

- (CGFloat)degreesFromRad:(CGFloat)rad
{
    return (rad/M_PI) *180;
}

- (CGFloat)radFromDegrees:(CGFloat)degree
{
    return (degree/180) *M_PI;
}

-(void)updateEulerAnglesAndListenerFromDeltaX:(CGFloat)dx DeltaY:(CGFloat)dy
{
    //estimate the position deltas as the angular change and convert it to radians for scene kit
    float dYaw = [self radFromDegrees:dx];
    float dPitch = [self radFromDegrees:dy];

    //scale the feedback to make the transitions smooth and natural
    float scalar = 0.1;
    
    [self.pointOfView setEulerAngles:SCNVector3Make(self.pointOfView.eulerAngles.x+dPitch*scalar,
                                                    self.pointOfView.eulerAngles.y+dYaw*scalar,
                                                    self.pointOfView.eulerAngles.z)];

    
    SCNNode *listener = [self.scene.rootNode childNodeWithName:@"listenerLight" recursively:YES];
    [listener setEulerAngles:SCNVector3Make(self.pointOfView.eulerAngles.x,
                                            self.pointOfView.eulerAngles.y,
                                            self.pointOfView.eulerAngles.z)];
    
    
    //convert the scene kit angular orientation (radians) to degrees for AVAudioEngine and match the orientation
    [self.gameAudioEngine
     updateListenerOrientation:AVAudioMake3DAngularOrientation([self degreesFromRad:-1*self.pointOfView.eulerAngles.y],
                                                               [self degreesFromRad:-1*self.pointOfView.eulerAngles.x],
                                                               [self degreesFromRad:self.pointOfView.eulerAngles.z])];
}

#if TARGET_OS_IOS || TARGET_OS_TV

- (void)panGesture:(UIPanGestureRecognizer *)panRecognizer
{
    //capture the first touch
    if(panRecognizer.state == UIGestureRecognizerStateBegan)
        self.previousTouch = [panRecognizer locationInView:self];
    
    CGPoint currentTouch = [panRecognizer locationInView:self];
    
    //Calculate the change in position
    float dX = currentTouch.x-self.previousTouch.x;
    float dY = currentTouch.y-self.self.previousTouch.y;
    
    self.previousTouch = currentTouch;
    
    [self updateEulerAnglesAndListenerFromDeltaX:dX DeltaY:dY];
}

#else
-(void)mouseDown:(NSEvent *)theEvent
{
    /* Called when a mouse click occurs */
    [super mouseDown:theEvent];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
    /* Called when a mouse dragged occurs */
    [super mouseDragged:theEvent];
    
    [self updateEulerAnglesAndListenerFromDeltaX:theEvent.deltaX DeltaY:theEvent.deltaY];
    
}

- (void)magnifyWithEvent:(NSEvent *)event
{
    //implement this method to zoom in and out
    //[super magnifyWithEvent:event];
}

- (void)rotateWithEvent:(NSEvent *)event
{
    //implement this to have to listener roll along the perpendicular axis to the screen plane
    //[super rotateWithEvent:event];
}

#endif //TARGET_OS_IOS || TARGET_OS_TV


@end

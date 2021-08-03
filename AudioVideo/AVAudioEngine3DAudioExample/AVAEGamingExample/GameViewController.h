/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    GameViewController
*/

@import SceneKit;

#if TARGET_OS_IOS || TARGET_OS_TV
@interface GameViewController : UIViewController <SCNPhysicsContactDelegate>
#else
@interface GameViewController : NSViewController <SCNPhysicsContactDelegate>
#endif

@end

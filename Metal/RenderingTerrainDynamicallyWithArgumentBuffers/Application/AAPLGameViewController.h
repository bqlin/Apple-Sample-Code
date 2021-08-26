/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Declaration of this sample's main view controller that drives the main renderer.
*/

#pragma once

#import "TargetConditionals.h"

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

@interface AAPLGameView : MTKView
- (BOOL)acceptsFirstResponder;
#if !TARGET_OS_IOS
- (BOOL)acceptsFirstMouse:(NSEvent *)event;
#endif

@end

#if TARGET_OS_IOS
@interface AAPLGameViewController : UIViewController <MTKViewDelegate>
-(IBAction) ModifyTerrain: (id)sender;
@end
#else
@interface AAPLGameViewController : NSViewController <MTKViewDelegate>
@end
#endif

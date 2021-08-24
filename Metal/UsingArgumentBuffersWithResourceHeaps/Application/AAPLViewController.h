/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for the cross-platform view controller
*/

#if defined(TARGET_IOS) || defined(TARGET_TVOS)
@import UIKit;
#define PlatformViewController UIViewController
#else
@import AppKit;
#define PlatformViewController NSViewController
#endif

@import MetalKit;

#import "AAPLRenderer.h"

// Our view controller
@interface AAPLViewController : PlatformViewController

@end

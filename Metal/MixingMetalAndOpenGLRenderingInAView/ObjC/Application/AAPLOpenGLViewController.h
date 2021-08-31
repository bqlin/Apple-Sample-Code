/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for the cross-platform OpenGL view controller AND a minimal cross-platform OpenGL View
*/

#if defined(TARGET_IOS) || defined(TARGET_TVOS)
@import UIKit;
#define PlatformViewBase UIView
#define PlatformViewController UIViewController
#else
@import AppKit;
#define PlatformViewBase NSOpenGLView
#define PlatformViewController NSViewController
#endif

@interface AAPLOpenGLView : PlatformViewBase

@end

@interface AAPLOpenGLViewController : PlatformViewController

@end

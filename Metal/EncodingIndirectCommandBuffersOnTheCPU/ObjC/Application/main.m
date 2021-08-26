/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Application entry point for all platforms
*/

#if defined(TARGET_IOS)
#import <UIKit/UIKit.h>
#import <TargetConditionals.h>
#import "AAPLAppDelegate.h"
#else
#import <Cocoa/Cocoa.h>
#endif

#if defined(TARGET_IOS)

int main(int argc, char * argv[]) {

#if TARGET_OS_SIMULATOR
#error This sample does not have simulator support and must be built for a device.
#endif

    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AAPLAppDelegate class]));
    }
}

#else

int main(int argc, const char * argv[]) {
    return NSApplicationMain(argc, argv);
}

#endif

/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Entry point.
*/

#import "TargetConditionals.h"

#import "AAPLAppDelegate.h"

int main (int argc, char* argv[])
{
    @autoreleasepool
    {
        srandom(0);
#if TARGET_OS_IOS
    
        return UIApplicationMain (argc, argv, nil, NSStringFromClass ([AAPLAppDelegate class]));
#else
        return NSApplicationMain (argc, (const char* _Nonnull * _Nonnull) argv);
#endif
    }
}

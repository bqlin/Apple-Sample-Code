/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of the Application Delegate object
*/

#import "AAPLAppDelegate.h"
#import "AAPLGameViewController.h"

@interface AAPLAppDelegate ()
@end

#if TARGET_OS_IOS

@implementation AAPLAppDelegate

- (BOOL) application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary*) launchOptions
{
    return YES;
}

@end

#else

@implementation AAPLAppDelegate

- (void) applicationDidFinishLaunching:(NSNotification*) aNotification
{
    // Insert code here to initialize your application
}

- (void) applicationWillTerminate:(NSNotification*) aNotification
{
    // Insert code here to tear down your application
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed:(NSApplication*) sender
{
    return YES;
}

@end

#endif

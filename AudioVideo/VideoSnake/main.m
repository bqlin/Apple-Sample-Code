/*
 <codex>
 <abstract>Standard main file.</abstract>
 </codex>
 */

#import <UIKit/UIKit.h>

#import "VideoSnakeAppDelegate.h"

int main(int argc, char *argv[])
{
	int retVal = 0;
	@autoreleasepool {
	    retVal = UIApplicationMain(argc, argv, nil, NSStringFromClass([VideoSnakeAppDelegate class]));
	}
	return retVal;
}

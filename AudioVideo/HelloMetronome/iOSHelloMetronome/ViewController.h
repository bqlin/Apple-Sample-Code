/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

*/

@import UIKit;
@import AVFoundation;

#import "iOSHelloMetronome-Swift.h"

@interface ViewController : UIViewController <MetronomeDelegate> {
    Metronome *metronome;
}

@end


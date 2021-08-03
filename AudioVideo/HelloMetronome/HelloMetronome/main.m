/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

*/

#import <Foundation/Foundation.h>
#import "Metronome.h"

// Set to use the included file for metronome bip.
#define USE_FILE_FOR_BIP 1

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        printf("Hello, Metronome!\n");
        
        NSURL *fileURL = nil;
        
    #if USE_FILE_FOR_BIP
        printf("Usage:\n -f use the MoreCowbell.caf file for the metronome bip.\n\n");
        if (argc == 2 && (0 == strcmp(argv[1], "-f"))) {
            printf("Using MoreCowbell.caf for Metronome bips.\n");
            fileURL = [[NSBundle mainBundle] URLForResource:@"MoreCowbell" withExtension:@"caf"];
        } else {
            printf("Using generated audio for Metronome bips.\n\n");
        }
    #endif
        
        Metronome *metronome = [[Metronome alloc] init:fileURL];
        
        [metronome start];
        
        sleep(10);
        
        [metronome stop];
    }
    
    return 0;
}

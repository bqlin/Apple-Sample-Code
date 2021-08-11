/*
     File: main.m
 Abstract:  Standard main file. Reads in and parses arguments to either read/write timecode samples. 
  Version: 1.2
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 
 */

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <getopt.h>
#import "AVTimecodeReader.h"
#import "AVTimecodeWriter.h"

static void usage()
{
	printf("Usage: avtimecodereadwrite mode_name [options] [input_source] [output_file]\n");
	printf("By default, input_source is a path to a local file.\n");
	
	printf("\nModes:\n");
	printf("  read\n");
	printf("  write\n");
	
	printf("\nOptions:\n");
	printf("  -i, --input=timecode file,		A file containing frame numbers and timecodes, where each line represents a pair frameNum HH:MM:SS./,FF (. for non-drop and , drop frame) to be written out to a movie\n");
	printf("					Example file format: \n");
	printf("					frame1 H1:M1:S1.F1\n");
	printf("					frame2 H2:M2:S2.F2\n");
	printf("  -h, --help				Print this message and exit\n");
	exit(1);
}

int main(int argc, char *argv[])
{

    @autoreleasepool {
		
		int c = -1;
		NSString *timecodeInput = NULL;
		NSURL *sourceURL = NULL;
		NSURL *destURL = NULL;
		NSFileManager *fm = [NSFileManager defaultManager];
		
		static struct option longopts[] =
		{
			{"input", required_argument, NULL, 'i'},
			{"help", no_argument, NULL, 'h'},
			{0, 0, 0, 0}
		};

		const char *shortopts = "i:h";
        
        if (argc < 2) {
            usage();
            exit(-1);
        }
		
		while ((c = getopt_long(argc, argv, shortopts, longopts, NULL)) != -1) {
			
			switch (c) {
				case 'i':
					timecodeInput = [NSString stringWithUTF8String:optarg];
					break;
				case 'h':
					usage();
					break;
				default:
					usage();
					break;
			}
		}
		
		int nextArgIndex = optind;
		
		if (nextArgIndex >= argc)
		{
			printf("%s: missing required mode name\n", argv[0]);
			usage();
			exit(-1);
		}
		
		const char *mode = argv[nextArgIndex];
		++nextArgIndex;
		
		BOOL testTakesDestURL = (strcmp(mode, "write") == 0);
		
		if (nextArgIndex < argc) {
			const char *sourceSpecifier = argv[nextArgIndex];
			sourceURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:sourceSpecifier]];
			
			NSCAssert(sourceURL != nil, @"Invalid source URL");
			++nextArgIndex;
		}
		
		if ((nextArgIndex < argc) && testTakesDestURL)
		{
			NSString *destPath = [fm stringWithFileSystemRepresentation:argv[nextArgIndex] length:strlen(argv[nextArgIndex])];
			
			destPath = [destPath stringByStandardizingPath];
			destURL = [NSURL fileURLWithPath:destPath];
			NSError *error = nil;
			[fm removeItemAtPath:destPath error:&error];
			
			NSCAssert(destURL != nil, @"Invalid destination URL");
			++nextArgIndex;
		} else if (testTakesDestURL) {
			printf("%s: writer needs destination URL\n", argv[0]);
			usage();
			exit(-1);
		}
		
		if (nextArgIndex > argc)
		{
			printf("%s: too many arguments\n", argv[0]);
			usage();
			exit(-1);
		}
		
		AVURLAsset *sourceAsset = [[AVURLAsset alloc] initWithURL:sourceURL options:nil];
		
		if (strcmp(mode, "read") == 0) {
			
			AVTimecodeReader *timecodeReader = [[AVTimecodeReader alloc] initWithSourceAsset:sourceAsset];
			NSArray *outputTimecodes = [timecodeReader readTimecodeSamples];
			
			for (NSValue *timecodeValue in outputTimecodes) {
				CVSMPTETime timecode = {0};
				[timecodeValue getValue:&timecode];
				NSLog(@"%@",[NSString stringWithFormat:@"HH:MM:SS:FF => %02d:%02d:%02d:%02d", timecode.hours, timecode.minutes, timecode.seconds, timecode.frames]);
			}
			
		} else if (strcmp(mode, "write") == 0) {
			
			NSMutableDictionary *timecodeSamples = [NSMutableDictionary dictionary];
			NSError *error = nil;
			
			NSString *timecodes = [NSString stringWithContentsOfFile:timecodeInput encoding:NSUTF8StringEncoding error:&error];
			
			if (error) {
				
				NSLog(@"%s: Could not read timecode input file", argv[0]);
				
			} else {
				
				NSArray *timecodeInputValues = [timecodes componentsSeparatedByString:@"\n"];
				
				for (NSString *frameNumTimecodePair in timecodeInputValues) {
					NSArray *frameTcValues = [frameNumTimecodePair componentsSeparatedByString:@" "];
					if ([frameTcValues count] > 1) {
						[timecodeSamples setObject:[frameTcValues objectAtIndex:1] forKey:[NSNumber numberWithInt:[(NSString*)[frameTcValues objectAtIndex:0] intValue]]];
					}
				}
				
				AVTimecodeWriter *timecodeWriter = [[AVTimecodeWriter alloc] initWithSourceAsset:sourceAsset destinationAssetURL:destURL timecodeSamples:timecodeSamples];
				
				[timecodeWriter writeTimecodeSamples];
				
			}
		} else {
			printf("%s: unrecognized mode %s\n", argv[0], mode);
			usage();
			exit(-1);
		}
    }
	
    return 0;
}


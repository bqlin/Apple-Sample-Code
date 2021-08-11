/*
     File: AVTimecodeReader.m
 Abstract:  Reader class which sets up AVAssetReader and AVAssetReaderTrackOutput to read in timecode tracks and output timecode values. 
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

#import "AVTimecodeReader.h"
#import "AVTimecodeUtilities.h"
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CVBase.h>

@interface AVTimecodeReader ()
{
	AVAssetReader				*assetReader;
	AVAssetReaderOutput			*timecodeOutput;
};

@property AVAsset				*sourceAsset;
@property NSMutableArray		*timecodeSamples;

@end

@implementation AVTimecodeReader

- (id)initWithSourceAsset:(AVAsset *)sourceAsset
{
    self = [super init];
    if (self)
    {
		self.sourceAsset = sourceAsset;
		self.timecodeSamples = [NSMutableArray array];
    }
    return self;
}

- (NSArray *)readTimecodeSamples
{
    AVAsset *localAsset = self.sourceAsset;
	
	//  The use of dispatch_semaphore here is to block the command line tool from exiting before task completion.
	//  This should however not be used in an app based on AppKit. Instead of blocking until loading completes, you must allow your main runloop to run while loading continues; to accomplish that, remove the use of the dispatch_semaphore and use the completion block to perform any tasks you need to perform upon completion.
	
	dispatch_semaphore_t dispatchSemaphore = dispatch_semaphore_create(0);
	
	[localAsset loadValuesAsynchronouslyForKeys:[NSArray arrayWithObjects:@"tracks", @"duration", nil] completionHandler:^{
		
		BOOL success = YES;
		NSError *localError = nil;
		
		success = ([localAsset statusOfValueForKey:@"tracks" error:&localError] == AVKeyValueStatusLoaded);
		if (success)
			success = ([localAsset statusOfValueForKey:@"duration" error:&localError] == AVKeyValueStatusLoaded);
		
		// Set up the AVAssetReader reading samples or flag an error
		if (success)
			success = [self setUpReaderReturningError:&localError];
		if (success)
			success = [self startReadingAndOutputReturningError:&localError];
		if (!success)
			[self readingDidFinishSuccessfully:success withError:localError];
		
		dispatch_semaphore_signal(dispatchSemaphore);
	}];
	
	dispatch_semaphore_wait(dispatchSemaphore, DISPATCH_TIME_FOREVER);
	
	return self.timecodeSamples;
}

- (BOOL)setUpReaderReturningError:(NSError **)outError
{
	BOOL success = YES;
	NSError *localError = nil;
	AVAsset *localAsset = self.sourceAsset;
		
	// Create asset reader
	assetReader = [[AVAssetReader alloc] initWithAsset:localAsset error:&localError];
	success = (assetReader != nil);
	
	// Create asset reader output for the first timecode track of the asset
	if (success) {
		AVAssetTrack *timecodeTrack = nil;
		
		// Grab first timecode track, if the asset has them
		NSArray *timecodeTracks = [localAsset tracksWithMediaType:AVMediaTypeTimecode];
		if ([timecodeTracks count] > 0)
			timecodeTrack = [timecodeTracks objectAtIndex:0];
		
		if (timecodeTrack) {
			timecodeOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:timecodeTrack outputSettings:nil];
			[assetReader addOutput:timecodeOutput];
		} else {
			NSLog(@"%@ has no timecode tracks", localAsset);
		}
	}

	if (!success && outError)
		*outError = localError;
	
	return success;
}

- (BOOL)startReadingAndOutputReturningError:(NSError **)outError
{
	BOOL success = YES;
	NSError *localError = nil;
	
	// Instruct the asset reader to get ready to do work
	success = [assetReader startReading];
	
	if (!success) {
		localError = [assetReader error];
	} else {
		CMSampleBufferRef currentSampleBuffer = NULL;
		
		while ((currentSampleBuffer = [timecodeOutput copyNextSampleBuffer])) {
			[self outputTimecodeDescriptionForSampleBuffer:currentSampleBuffer];
		}
		
		if (currentSampleBuffer) {
			CFRelease(currentSampleBuffer);
		}
	}
	
	if (!success && outError)
		*outError = localError;

	return success;
}

- (void)readingDidFinishSuccessfully:(BOOL)success withError:(NSError *)error
{
	if (!success) {
		[assetReader cancelReading];
	}
}

- (void)outputTimecodeDescriptionForSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
	CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
	CMFormatDescriptionRef formatDescription =  CMSampleBufferGetFormatDescription(sampleBuffer);
	
	if (blockBuffer && formatDescription) {
		
		size_t length = 0;
		size_t totalLength = 0;
		char *rawData = NULL;
		
		OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, &length, &totalLength, &rawData);
		if (status != kCMBlockBufferNoErr) {
			NSLog(@"Could not get data from block buffer");
		}
		else {
			
			CMMediaType type = CMFormatDescriptionGetMediaSubType(formatDescription);
			uint32_t frameQuanta = CMTimeCodeFormatDescriptionGetFrameQuanta(formatDescription);
			uint32_t tcFlag = CMTimeCodeFormatDescriptionGetTimeCodeFlags(formatDescription);
			
			if (type == kCMTimeCodeFormatType_TimeCode32) {
				
				int32_t *frameNumberRead = (int32_t *)rawData;
				
				// frameNumberRead is stored big-endian. Convert it to native before passing in to the utility function.
				CVSMPTETime timecode = timecodeForFrameNumberUsingFrameQuanta(EndianS32_BtoN(*frameNumberRead), frameQuanta, tcFlag);
				[self.timecodeSamples addObject:[NSValue value:&timecode withObjCType:@encode(CVSMPTETime)]];
				
			} else if (type == kCMTimeCodeFormatType_TimeCode64) {
				
				int64_t *frameNumberRead = (int64_t *)rawData;
				
				// frameNumberRead is stored big-endian. Convert it to native before passing in to the utility function.
				CVSMPTETime timecode = timecodeForFrameNumberUsingFrameQuanta(EndianS64_BtoN(*frameNumberRead), frameQuanta, tcFlag);
				[self.timecodeSamples addObject:[NSValue value:&timecode withObjCType:@encode(CVSMPTETime)]];
			}
		}
	}
}

@end

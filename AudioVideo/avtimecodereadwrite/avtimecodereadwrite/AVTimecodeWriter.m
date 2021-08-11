/*
     File: AVTimecodeWriter.m
 Abstract:  Writer class which sets up AVAssetReader and AVAssetWriter to passthrough audio and video tracks and to add a new timecode track to the given asset. 
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

#import "AVTimecodeWriter.h"
#import "AVTimecodeUtilities.h"
#import <CoreVideo/CVBase.h>

#define WRITE_32BIT_TIMECODE_SAMPLE_FOR_INTEROPERABILITY 0 // Use this as a flip between 32 bit and 64 bit timecodes

@protocol AVSampleBufferGenerator <NSObject>

- (CMSampleBufferRef)copyNextSampleBuffer;

@end

@interface AVAssetReaderTrackOutput (SampleBufferGenerator) <AVSampleBufferGenerator>

@end

@interface AVTimecodeSampleBufferGenerator : NSObject <AVSampleBufferGenerator>
{
@private
	AVAssetTrack			*sourceVideoTrack;
	NSDictionary			*timecodeSamples;
	NSArray					*timecodeSampleKeys;
	
	float					frameRate;
	NSUInteger				numOfTimecodeSamples;
	NSUInteger				currentSampleNum;
};

- (id)initWithVideoTrack:(AVAssetTrack *)videoTrack timecodeSamples:(NSDictionary*)timecodeSamples;

@end

@interface AVSampleBufferChannel : NSObject
{
@private
	id <AVSampleBufferGenerator> sampleBufferGenerator;
	AVAssetWriterInput			 *assetWriterInput;
	
	dispatch_block_t		completionHandler;
	dispatch_queue_t		serializationQueue;
	BOOL					finished;  // only accessed on serialization queue
}

- (id)initWithSampleBufferGenerator:(id <AVSampleBufferGenerator>)sampleBufferGenerator assetWriterInput:(AVAssetWriterInput *)assetWriterInput;
- (void)startReadingAndWritingWithCompletionHandler:(dispatch_block_t)completionHandler;
- (void)cancel;

@end

/*
	AVTimecodeWriter 
															   -------------------------------
				 ----> Audio (AVAssetReaderTrackOutput) ----> | Audio (AVSampleBufferChannel) |    ---->
				|											   -------------------------------			|
	Media File -|																						|
				|											   -------------------------------			| AVAssetWriter
				 ----> Video (AVAssetReaderTrackOutput) ----> | Video (AVSampleBufferChannel) |    ---->| -------------> Output Media File 
															   -------------------------------			|
																										|
															   ----------------------------------		|
		  Timecode (AVTimecodeSampleBufferGenerator)    ----> | Timecode (AVSampleBufferChannel) | ---->
															   ----------------------------------

 
 */

@interface AVTimecodeWriter ()
{
	dispatch_queue_t			serializationQueue;
	dispatch_semaphore_t		globalDispatchSemaphore;
	// All of these are created, accessed, and torn down exclusively on the serializaton queue
	AVAssetReader				*assetReader;
	AVAssetWriter				*assetWriter;
	AVSampleBufferChannel		*audioSampleBufferChannel;
	AVSampleBufferChannel		*videoSampleBufferChannel;
	AVSampleBufferChannel		*timecodeSampleBufferChannel;
}

@property AVAsset				*sourceAsset;
@property NSURL					*destinationAssetURL;
@property NSDictionary			*timecodeSamples;

@end

@implementation AVTimecodeWriter

- (id)initWithSourceAsset:(AVAsset *)sourceAsset destinationAssetURL:(NSURL *)destinationAssetURL timecodeSamples:(NSDictionary *)timecodeSamples
{
    self = [super init];
    if (self) {
        self.sourceAsset = sourceAsset;
        self.destinationAssetURL = destinationAssetURL;
        self.timecodeSamples = timecodeSamples;
		
		NSString *serializationQueueDescription = [NSString stringWithFormat:@"%@ serialization queue", self];
		serializationQueue = dispatch_queue_create([serializationQueueDescription UTF8String], NULL);
		
		globalDispatchSemaphore = dispatch_semaphore_create(0);
	}
    
    return self;
}

- (void)writeTimecodeSamples
{
	AVAsset *localAsset = self.sourceAsset;
	
	//  The use of dispatch_semaphore here is to block the command line tool from exiting before task completion.
	//  This should however not be used in an app based on AppKit. Instead of blocking until loading completes, you must allow your main runloop to run while loading continues; to accomplish that, remove the use of the dispatch_semaphore and use the completion block to perform any tasks you need to perform upon completion.
	
	[localAsset loadValuesAsynchronouslyForKeys:[NSArray arrayWithObjects:@"tracks", @"duration", nil] completionHandler:^{
		
		// Dispatch the setup work to the serialization queue, to ensure this work is serialized with potential cancellation
		dispatch_async(serializationQueue, ^{
			
			BOOL success = YES;
			NSError *localError = nil;
			
			success = ([localAsset statusOfValueForKey:@"tracks" error:&localError] == AVKeyValueStatusLoaded);
			if (success)
				success = ([localAsset statusOfValueForKey:@"duration" error:&localError] == AVKeyValueStatusLoaded);
			
			if (success) {
				// AVAssetWriter does not overwrite files for us, so remove the destination file if it already exists
				NSFileManager *fm = [NSFileManager defaultManager];
				NSString *localOutputPath = [self.destinationAssetURL path];
				if ([fm fileExistsAtPath:localOutputPath])
					success = [fm removeItemAtPath:localOutputPath error:&localError];
			}
			
			// Set up the AVAssetReader and AVAssetWriter, then begin writing samples or flag an error
			if (success)
				success = [self setUpReaderAndWriterReturningError:&localError];
			if (success)
				success = [self startReadingAndWritingReturningError:&localError];
			if (!success)
				[self readingAndWritingDidFinishSuccessfully:success withError:localError];
		});
	}];
	
	dispatch_semaphore_wait(globalDispatchSemaphore, DISPATCH_TIME_FOREVER);
}

- (BOOL)setUpReaderAndWriterReturningError:(NSError **)outError
{
	BOOL success = YES;
	NSError *localError = nil;
	AVAsset *localAsset = self.sourceAsset;
	NSURL *localOutputURL = self.destinationAssetURL;
	
	// Create asset reader and asset writer
	assetReader = [[AVAssetReader alloc] initWithAsset:localAsset error:&localError];
	success = (assetReader != nil);
	if (success) {
		assetWriter = [[AVAssetWriter alloc] initWithURL:localOutputURL fileType:AVFileTypeQuickTimeMovie error:&localError];
		success = (assetWriter != nil);
	}
	
	// Create asset reader outputs and asset writer inputs for the first audio track and first video track of the asset
	if (success) {
		AVAssetTrack *audioTrack = nil, *videoTrack = nil;
		
		// Grab first audio track and first video track, if the asset has them
		NSArray *audioTracks = [localAsset tracksWithMediaType:AVMediaTypeAudio];
		if ([audioTracks count] > 0)
			audioTrack = [audioTracks objectAtIndex:0];
		NSArray *videoTracks = [localAsset tracksWithMediaType:AVMediaTypeVideo];
		if ([videoTracks count] > 0)
			videoTrack = [videoTracks objectAtIndex:0];
		
		// Setup passthrough for audio and video tracks
		if (audioTrack) {
			AVAssetReaderTrackOutput *audioOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:audioTrack outputSettings:nil];
			[assetReader addOutput:audioOutput];
			
			AVAssetWriterInput *audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:[audioTrack mediaType] outputSettings:nil];
			[assetWriter addInput:audioInput];
			
			// Create and save an instance of AVSampleBufferChannel, which will coordinate the work of reading and writing sample buffers
			audioSampleBufferChannel = [[AVSampleBufferChannel alloc] initWithSampleBufferGenerator:audioOutput assetWriterInput:audioInput];
		}
		
		if (videoTrack) {
			AVAssetReaderTrackOutput *videoOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack outputSettings:nil];
			[assetReader addOutput:videoOutput];
			
			AVAssetWriterInput *videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:[videoTrack mediaType] outputSettings:nil];
			[assetWriter addInput:videoInput];
			
			// Create and save an instance of AVSampleBufferChannel, which will coordinate the work of reading and writing sample buffers
			videoSampleBufferChannel = [[AVSampleBufferChannel alloc] initWithSampleBufferGenerator:videoOutput assetWriterInput:videoInput];
			
			// Setup timecode track in order to write timecode samples
			AVAssetWriterInput *timecodeInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeTimecode outputSettings:nil];
			
			// The default size of a timecode track is 0x0. Uncomment the following line to make the timecode samples viewable in QT7-based apps that use the timecode media handler APIs for timecode display. Some older QT7-based apps may not recognize that 64-bit timecode tracks are eligible for timecode display.
			//[timecodeInput setNaturalSize:CGSizeMake(videoTrack.naturalSize.width, 16)];
			
			[videoInput addTrackAssociationWithTrackOfInput:timecodeInput type:AVTrackAssociationTypeTimecode];
			[assetWriter addInput:timecodeInput];
			
			AVTimecodeSampleBufferGenerator *sampleBufferGenerator = [[AVTimecodeSampleBufferGenerator alloc] initWithVideoTrack:videoTrack timecodeSamples:self.timecodeSamples];
			
			timecodeSampleBufferChannel = [[AVSampleBufferChannel alloc] initWithSampleBufferGenerator:sampleBufferGenerator assetWriterInput:timecodeInput];
		}
		
	}
	
	if (!success && outError)
		*outError = localError;
	
	return success;
}

- (BOOL)startReadingAndWritingReturningError:(NSError **)outError
{
	BOOL success = YES;
	NSError *localError = nil;
	
	// Instruct the asset reader and asset writer to get ready to do work
	success = [assetReader startReading];
	if (!success)
		localError = [assetReader error];
	if (success) {
		success = [assetWriter startWriting];
		if (!success)
			localError = [assetWriter error];
	}
	
	if (success) {
		// Start a sample-writing session
		[assetWriter startSessionAtSourceTime:kCMTimeZero];
		
		dispatch_group_t dispatchGroup = dispatch_group_create();
		
		// Start reading and writing samples
		if (audioSampleBufferChannel) {
			dispatch_group_enter(dispatchGroup);
			[audioSampleBufferChannel startReadingAndWritingWithCompletionHandler:^{
				dispatch_group_leave(dispatchGroup);
			}];
		}
		if (videoSampleBufferChannel) {
			dispatch_group_enter(dispatchGroup);
			[videoSampleBufferChannel startReadingAndWritingWithCompletionHandler:^{
				dispatch_group_leave(dispatchGroup);
			}];
		}
		if (timecodeSampleBufferChannel) {
			dispatch_group_enter(dispatchGroup);
			[timecodeSampleBufferChannel startReadingAndWritingWithCompletionHandler:^{
				dispatch_group_leave(dispatchGroup);
			}];
		}
		
		// Set up a callback for when the sample writing is finished
		dispatch_group_notify(dispatchGroup, serializationQueue, ^{
			__block BOOL finalSuccess = YES;
			NSError *finalError = nil;
			
			if ([assetReader status] == AVAssetReaderStatusFailed) {
				finalSuccess = NO;
				finalError = [assetReader error];
			}
			
			if (finalSuccess) {
				dispatch_group_enter(dispatchGroup);
				
				[assetWriter finishWritingWithCompletionHandler:^{
					
					finalSuccess = ([assetWriter status] == AVAssetWriterStatusCompleted) ? YES : NO;
					
					dispatch_group_leave(dispatchGroup);
					
				}];
				
				dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
				
				if (!finalSuccess) {
					
					finalError = [assetWriter error];
					
					[self readingAndWritingDidFinishSuccessfully:finalSuccess withError:finalError];
					
				}
				
				dispatch_semaphore_signal(globalDispatchSemaphore);
			}
		});
	}
	
	if (!success && outError)
		*outError = localError;
	
	return success;
}

- (void)readingAndWritingDidFinishSuccessfully:(BOOL)success withError:(NSError *)error
{
	if (!success) {
		[assetReader cancelReading];
		[assetWriter cancelWriting];
		
		NSLog(@"Writing timecode failed with the following error: %@", error);
	}
}

@end

@interface AVSampleBufferChannel ()

- (void)callCompletionHandlerIfNecessary;  // always called on the serialization queue

@end

@implementation AVSampleBufferChannel

- (id)initWithSampleBufferGenerator:(id<AVSampleBufferGenerator>)localSampleBufferGenerator assetWriterInput:(AVAssetWriterInput *)localAssetWriterInput
{
	self = [super init];
	
	if (self) {
		sampleBufferGenerator = localSampleBufferGenerator;
		assetWriterInput = localAssetWriterInput;
		
		finished = NO;
		NSString *serializationQueueDescription = [NSString stringWithFormat:@"%@ serialization queue", self];
		serializationQueue = dispatch_queue_create([serializationQueueDescription UTF8String], NULL);
	}
	
	return self;
}

- (void)startReadingAndWritingWithCompletionHandler:(dispatch_block_t)localCompletionHandler
{
	completionHandler = [localCompletionHandler copy];
	
	[assetWriterInput requestMediaDataWhenReadyOnQueue:serializationQueue usingBlock:^{
		if (finished)
			return;
		
		BOOL completedOrFailed = NO;
		
		// Read samples in a loop as long as the asset writer input is ready
		while ([assetWriterInput isReadyForMoreMediaData] && !completedOrFailed) {
			CMSampleBufferRef sampleBuffer = NULL;
			
			sampleBuffer = [sampleBufferGenerator copyNextSampleBuffer];
			
			if (sampleBuffer != NULL) {
				BOOL success = [assetWriterInput appendSampleBuffer:sampleBuffer];
				CFRelease(sampleBuffer);
				sampleBuffer = NULL;
				
				completedOrFailed = !success;
			} else {
				completedOrFailed = YES;
			}
			
		}
		
		if (completedOrFailed)
			[self callCompletionHandlerIfNecessary];
	}];
}

- (void)cancel
{
	dispatch_async(serializationQueue, ^{
		[self callCompletionHandlerIfNecessary];
	});
}

- (void)callCompletionHandlerIfNecessary
{
	// Set state to mark that we no longer need to call the completion handler, grab the completion handler, and clear out the ivar
	BOOL oldFinished = finished;
	finished = YES;
	
	if (oldFinished == NO) {
		[assetWriterInput markAsFinished];  // let the asset writer know that we will not be appending any more samples to this input
		
		if (completionHandler) {
			completionHandler();
		}
	}
}

@end

@implementation AVTimecodeSampleBufferGenerator

- (id)initWithVideoTrack:(AVAssetTrack *)localVideoTrack timecodeSamples:(NSDictionary *)localTimecodeSamples
{
	self = [super init];
	
	if (self) {
		sourceVideoTrack = localVideoTrack;
		timecodeSamples = localTimecodeSamples;
		timecodeSampleKeys = [timecodeSamples allKeys];
		
		frameRate = localVideoTrack.nominalFrameRate;
		numOfTimecodeSamples = [timecodeSampleKeys count];
		currentSampleNum = 0;
	}
	
	return self;
}

- (CVSMPTETime)timecodeFromStringDescription:(NSString *)timecodeString isDropFrame:(BOOL *)dropFrame;
{
	CVSMPTETime timecode = {0};
	NSArray *timecodeComponents;
	*dropFrame = NO;
	
	if ([timecodeString rangeOfString:@","].location != NSNotFound) { // If dropFrame -> HH:MM:SS,FF
		
		*dropFrame = YES;
		timecodeComponents = [timecodeString componentsSeparatedByString:@","]; // @"HH:MM:SS", @"FF"
		
	} else if ([timecodeString rangeOfString:@"."].location != NSNotFound) { // If not dropFrame -> HH:MM:SS.FF
		
		*dropFrame = NO;
		timecodeComponents = [timecodeString componentsSeparatedByString:@"."]; // @"HH:MM:SS", @"FF"
		
	}
	
	timecode.frames  = [(NSString*)[timecodeComponents objectAtIndex:1] intValue]; // FF
	
	NSArray *timecodeValues = [[timecodeComponents objectAtIndex:0] componentsSeparatedByString:@":"]; // HH:MM:SS
	timecode.hours   = [(NSString*)[timecodeValues objectAtIndex:0] intValue]; // HH
	timecode.minutes = [(NSString*)[timecodeValues objectAtIndex:1] intValue]; // MM
	timecode.seconds = [(NSString*)[timecodeValues objectAtIndex:2] intValue]; // SS
	
	return timecode;
}

- (CMSampleBufferRef)copyNextSampleBuffer
{
	CMSampleBufferRef sampleBuffer = NULL;
	
	if (currentSampleNum < numOfTimecodeSamples) {
		
		CMTimeCodeFormatDescriptionRef formatDescription = NULL;
		CMBlockBufferRef dataBuffer = NULL;
		CVSMPTETime timecodeSample = {0};
		OSStatus status = noErr;
		
		// timecodeSampleKeys contains all the input frame numbers at which we need to add supplied timecode values
		NSNumber *absoluteFrameNum = [timecodeSampleKeys objectAtIndex:currentSampleNum++];
		NSNumber *nextFrameNum = nil;
		
		if (currentSampleNum < numOfTimecodeSamples) {
			nextFrameNum = [timecodeSampleKeys objectAtIndex:currentSampleNum];
		} else {
			nextFrameNum = [NSNumber numberWithInt:(CMTimeGetSeconds([[sourceVideoTrack asset] duration]) * frameRate)]; // Total number of frames (last frame)
		}
		
		// Parse the input timecode string to extract hours, minutes, seconds and frames
		NSString *timecodeString = [timecodeSamples objectForKey:absoluteFrameNum];
		BOOL dropFrame;
		timecodeSample = [self timecodeFromStringDescription:timecodeString isDropFrame:&dropFrame];
		
		uint32_t tcFlags = 0;
		if (dropFrame) {
			tcFlags = kCMTimeCodeFlag_DropFrame;
		}
		
		uint32_t frameQuanta = 30;
		int64_t frameNumberData = frameNumberForTimecodeUsingFrameQuanta(timecodeSample, frameQuanta, tcFlags);
		int64_t bigEndianFrameNumberData64 = EndianS64_NtoB(frameNumberData);
		CMMediaType timeCodeFormatType = kCMTimeCodeFormatType_TimeCode64;
		size_t sizes = sizeof(int64_t);
		void *frameNumberDataBytes = &bigEndianFrameNumberData64;
		
#if WRITE_32BIT_TIMECODE_SAMPLE_FOR_INTEROPERABILITY
		int32_t bigEndianFameNumberData32;
		
		timeCodeFormatType = kCMTimeCodeFormatType_TimeCode32;
		sizes = sizeof(int32_t);
		bigEndianFameNumberData32 = EndianS32_NtoB((int32_t)frameNumberData);
		frameNumberDataBytes = &bigEndianFameNumberData32;
		
#endif
		
		status = CMTimeCodeFormatDescriptionCreate(kCFAllocatorDefault, timeCodeFormatType, CMTimeMake(100, 2997), frameQuanta, tcFlags, NULL, &formatDescription);
		
		if ((status != noErr) || !formatDescription) {
			NSLog(@"Could not create format description");
		}
		
		status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, NULL, sizes, kCFAllocatorDefault, NULL, 0, sizes, kCMBlockBufferAssureMemoryNowFlag, &dataBuffer);
		
		if ((status != kCMBlockBufferNoErr) || !dataBuffer) {
			NSLog(@"Could not create block buffer");
		}

		status = CMBlockBufferReplaceDataBytes(frameNumberDataBytes, dataBuffer, 0, sizes);
		
		if (status != kCMBlockBufferNoErr) {
			NSLog(@"Could not write into block buffer");
		}
		
		CMSampleTimingInfo timingInfo;
		// Duration of each timecode sample is from the current frame to the next frame specified along with a timecode
		timingInfo.duration =  CMTimeMake([nextFrameNum intValue] - [absoluteFrameNum intValue], frameRate);
		timingInfo.decodeTimeStamp = kCMTimeInvalid;
		timingInfo.presentationTimeStamp = CMTimeMake([absoluteFrameNum intValue], frameRate);
		
		status = CMSampleBufferCreate(kCFAllocatorDefault, dataBuffer, true, NULL, NULL, formatDescription, 1, 1, &timingInfo, 1, &sizes, &sampleBuffer);
		if ((status != noErr) || !sampleBuffer) {
			NSLog(@"Could not create block buffer");
		}
		
		CFRelease(formatDescription);
		CFRelease(dataBuffer);
	}
	
	return sampleBuffer;
}

@end

/*
     File: main.m
 Abstract: This implementation file covers writing out subtitles to a new movie file. This is accomplished with AVAssetReader, AVAssetWriter, and the SubtitlesTextReader. Steps are taken to preserve much of the source movies tracks and metadata in the new movie it writes out.
  Version: 1.0.1
 
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
 
 Copyright (C) 2013 Apple Inc. All Rights Reserved.
 
 */

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <getopt.h>

#import "SubtitlesTextReader.h"

void writeSubtitles(NSString *inputPath, NSString *outputPath, NSArray *subtitlesTextPaths);

int main(int argc, char * const *argv)
{
	@autoreleasepool
	{
		NSString *inputPath;
		NSString *outputPath;
		NSMutableArray *subtitlesTextPaths = [NSMutableArray array];
		
		int option = -1;
		static struct option longopts[] =
		{
			{"input", required_argument, NULL, 'i'},
			{"output", required_argument, NULL, 'o'},
			{"subtitles", required_argument, NULL, 's'},
			{0, 0, 0, 0}
		};
		const char *shortopts = "i:o:s:";
		while ((option = getopt_long(argc, argv, shortopts, longopts, NULL)) != -1)
		{
			switch (option)
			{
				case 'i':
				{
					inputPath = [NSString stringWithCString:optarg encoding:NSMacOSRomanStringEncoding];
					break;
				}
				case 'o':
				{
					outputPath = [NSString stringWithCString:optarg encoding:NSMacOSRomanStringEncoding];
					break;
				}
				case 's':
				{
					[subtitlesTextPaths addObject:[NSString stringWithCString:optarg encoding:NSMacOSRomanStringEncoding]];
					break;
				}
			}
		}
		
		if (inputPath && outputPath)
		{
			writeSubtitles(inputPath, outputPath, subtitlesTextPaths);
		}
		else
		{
			printf("Usage:	subtitleswriter -i [input_file] -o [output_file] -s [subtitles_file]\n");
			printf("		Creates a new movie file at the specified output location, with audio, video, and subtitles from the input source, adding subtitles from the provide subtitles file(s). Each subtitles file will become a subtitle track in the output movie.\n");
		}
	}
	return 0;
}

void writeSubtitles(NSString *inputPath, NSString *outputPath, NSArray *subtitlesTextPaths)
{
	NSError *error;
	
	// Setup the asset reader and writer
	AVAsset *asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:[inputPath stringByExpandingTildeInPath]]];
	AVAssetReader *assetReader = [AVAssetReader assetReaderWithAsset:asset error:&error];
	if (error)
	{
		NSLog(@"error creating asset reader. exiting: %@", error);
		return;
	}
	
	NSURL *outputURL = [NSURL fileURLWithPath:[outputPath stringByExpandingTildeInPath]];
	AVAssetWriter *assetWriter = [AVAssetWriter assetWriterWithURL:outputURL fileType:AVFileTypeQuickTimeMovie error:&error];
	if (error)
	{
		NSLog(@"error creating asset writer. exiting: %@", error);
		return;
	}
	
	// Copy metadata from the asset to the asset writer
	NSMutableArray *assetMetadata = [NSMutableArray array];
	for (NSString *metadataFormat in asset.availableMetadataFormats)
		[assetMetadata addObjectsFromArray:[asset metadataForFormat:metadataFormat]];
	assetWriter.metadata = assetMetadata;
	assetWriter.shouldOptimizeForNetworkUse = YES;
	
	// Build up inputs and outputs for the reader and writer to carry over the tracks from the input movie into the new movie
	NSMutableDictionary *assetWriterInputsCorrespondingToOriginalTrackIDs = [NSMutableDictionary dictionary];
	NSMutableArray *inputsOutputs = [NSMutableArray array];
	for (AVAssetTrack *track in asset.tracks)
	{
		NSString *mediaType = track.mediaType;
		
		// Make the reader
		AVAssetReaderTrackOutput *trackOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:nil];
		[assetReader addOutput:trackOutput];
		
		// Make the writer input, using a source format hint if a format description is available
		AVAssetWriterInput *input;
		CMFormatDescriptionRef formatDescription = CFBridgingRetain([track.formatDescriptions firstObject]);
		if (formatDescription)
		{
			input = [AVAssetWriterInput assetWriterInputWithMediaType:mediaType outputSettings:nil sourceFormatHint:formatDescription];
			CFRelease(formatDescription);
		}
		else
		{
			NSLog(@"skipping track on the assumption that there is no media data to carry over");
			continue;
		}
		
		// Carry over language code
		input.languageCode = track.languageCode;
		input.extendedLanguageTag = track.extendedLanguageTag;
		
		// Copy metadata from the asset track to the asset writer input
		NSMutableArray *trackMetadata = [NSMutableArray array];
		for (NSString *metadataFormat in track.availableMetadataFormats)
			[trackMetadata addObjectsFromArray:[track metadataForFormat:metadataFormat]];
		input.metadata = trackMetadata;
		
		// Add the input, if that's okay to do
		if ([assetWriter canAddInput:input])
		{
			[assetWriter addInput:input];
			
			// Store the input and output to be used later when actually writing out the new movie
			[inputsOutputs addObject:@{@"input" : input, @"output" : trackOutput}];
			
			// Track inputs corresponsing to track IDs for later preservation of track groups
			assetWriterInputsCorrespondingToOriginalTrackIDs[@(track.trackID)] = input;
		}
		else
		{
			NSLog(@"skipping input because it cannot be added to the asset writer");
		}
	}
	
	// Setup the inputs and outputs for new subtitle tracks
	NSMutableArray *newSubtitlesInputs = [NSMutableArray array];
	NSMutableArray *subtitlesInputsOutputs = [NSMutableArray array];
	for (NSString *subtitlesPath in subtitlesTextPaths)
	{
		// Read the contents of the subtitles file
		NSString *text = [NSString stringWithContentsOfURL:[NSURL fileURLWithPath:subtitlesPath] encoding:NSUTF8StringEncoding error:&error];
		if (!text)
		{
			NSLog(@"there was a problem reading a subtitles file: %@", error);
			continue;
		}
		
		// Make the subtitles reader
		SubtitlesTextReader *subtitlesTextReader = [SubtitlesTextReader subtitlesTextReaderWithText:text];
		
		// Make the writer input, using a source format hint if a format description is available
		AVAssetWriterInput *subtitlesInput;
		CMFormatDescriptionRef formatDescription = [subtitlesTextReader copyFormatDescription];
		if (formatDescription)
		{
			subtitlesInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeSubtitle outputSettings:nil sourceFormatHint:formatDescription];
			CFRelease(formatDescription);
		}
		else
		{
			NSLog(@"skipping subtitles reader on the assumption that there is no media data to carry over");
			continue;
		}
		
		subtitlesInput.languageCode = subtitlesTextReader.languageCode;
		subtitlesInput.extendedLanguageTag = subtitlesTextReader.extendedLanguageTag;
		subtitlesInput.metadata = subtitlesTextReader.metadata;
		
		if ([assetWriter canAddInput:subtitlesInput])
		{
			[assetWriter addInput:subtitlesInput];
			
			// Store the input and output to be used later when actually writing out the new movie
			[subtitlesInputsOutputs addObject:@{@"input" : subtitlesInput, @"output" : subtitlesTextReader}];
			[newSubtitlesInputs addObject:subtitlesInput];
		}
		else
		{
			NSLog(@"skipping subtitles input because it cannot be added to the asset writer");
		}
	}
	
	// Preserve track groups from the original asset
	BOOL groupedSubtitles = NO;
	for (AVAssetTrackGroup *trackGroup in asset.trackGroups)
	{
		// Collect the inputs that correspond to the group's track IDs in an array
		NSMutableArray *inputs = [NSMutableArray array];
		AVAssetWriterInput *defaultInput;
		for (NSNumber *trackID in trackGroup.trackIDs)
		{
			AVAssetWriterInput *input = assetWriterInputsCorrespondingToOriginalTrackIDs[trackID];
			if (input)
				[inputs addObject:input];
			
			// Determine which of the inputs is the default according to the enabled state of the corresponding tracks
			if (!defaultInput && [asset trackWithTrackID:(CMPersistentTrackID)[trackID intValue]].enabled)
				defaultInput = input;
		}
		
		// See if this is a legible (all of the tracks have characteristic AVMediaCharacteristicLegible), and group the new subtitle tracks with it if so
		BOOL isLegibleGroup = NO;
		for (NSNumber *trackID in trackGroup.trackIDs)
		{
			if ([[asset trackWithTrackID:(CMPersistentTrackID)[trackID intValue]] hasMediaCharacteristic:AVMediaCharacteristicLegible])
			{
				isLegibleGroup = YES;
			}
			else if (isLegibleGroup)
			{
				isLegibleGroup = NO;
				break;
			}
		}
		
		// If it is a legible group, add the new subtitles to this group
		if (!groupedSubtitles && isLegibleGroup)
		{
			[inputs addObjectsFromArray:newSubtitlesInputs];
			groupedSubtitles = YES;
		}
		
		AVAssetWriterInputGroup *inputGroup = [AVAssetWriterInputGroup assetWriterInputGroupWithInputs:inputs defaultInput:defaultInput];
		if ([assetWriter canAddInputGroup:inputGroup])
		{
			[assetWriter addInputGroup:inputGroup];
		}
		else
		{
			NSLog(@"cannot add asset writer group");
		}
	}
	
	// If no legible group was found to add the new subtitles to, create a group for them (if there are any)
	if (!groupedSubtitles && (newSubtitlesInputs.count > 0))
	{
		AVAssetWriterInputGroup *inputGroup = [AVAssetWriterInputGroup assetWriterInputGroupWithInputs:newSubtitlesInputs defaultInput:nil];
		if ([assetWriter canAddInputGroup:inputGroup])
		{
			[assetWriter addInputGroup:inputGroup];
		}
		else
		{
			NSLog(@"cannot add asset writer group");
		}
	}
	
	// Preserve track references from original asset
	NSMutableDictionary *trackReferencesCorrespondingToOriginalTrackIDs = [NSMutableDictionary dictionary];
	for (AVAssetTrack *track in asset.tracks)
	{
		NSMutableDictionary *trackReferencesForTrack = [NSMutableDictionary dictionary];
		NSMutableSet *availableTrackAssociatonTypes = [NSMutableSet setWithArray:track.availableTrackAssociationTypes];
		for (NSString *trackAssociationType in availableTrackAssociatonTypes)
		{
			NSArray *associatedTracks = [track associatedTracksOfType:trackAssociationType];
			if (associatedTracks.count > 0)
			{
				NSMutableArray *associatedTrackIDs = [NSMutableArray arrayWithCapacity:associatedTracks.count];
				for (AVAssetTrack *associatedTrack in associatedTracks)
				{
					[associatedTrackIDs addObject:@(associatedTrack.trackID)];
				}
				trackReferencesForTrack[trackAssociationType] = associatedTrackIDs;
			}
		}
		
		trackReferencesCorrespondingToOriginalTrackIDs[@(track.trackID)] = trackReferencesForTrack;
	}
	for (NSNumber *referencingTrackIDKey in trackReferencesCorrespondingToOriginalTrackIDs)
	{
		AVAssetWriterInput *referencingInput = assetWriterInputsCorrespondingToOriginalTrackIDs[referencingTrackIDKey];
		NSDictionary *trackReferences = trackReferencesCorrespondingToOriginalTrackIDs[referencingTrackIDKey];
		for (NSString *trackReferenceTypeKey in trackReferences)
		{
			NSArray *referencedTrackIDs = trackReferences[trackReferenceTypeKey];
			for (NSNumber *thisReferencedTrackID in referencedTrackIDs)
			{
				AVAssetWriterInput *referencedInput = assetWriterInputsCorrespondingToOriginalTrackIDs[thisReferencedTrackID];
				
				if (referencingInput && referencedInput && [referencingInput canAddTrackAssociationWithTrackOfInput:referencedInput type:trackReferenceTypeKey])
					[referencingInput addTrackAssociationWithTrackOfInput:referencedInput type:trackReferenceTypeKey];
			}
		}
	}
	
	// Write the movie
	if ([assetWriter startWriting])
	{
		[assetWriter startSessionAtSourceTime:kCMTimeZero];
		
		dispatch_group_t dispatchGroup = dispatch_group_create();
		
		[assetReader startReading];
		
		// Write samples from AVAssetReaderTrackOutputs
		for (NSDictionary *inputOutput in inputsOutputs)
		{
			dispatch_group_enter(dispatchGroup);
			dispatch_queue_t requestMediaDataQueue = dispatch_queue_create("request media data", DISPATCH_QUEUE_SERIAL);
			AVAssetWriterInput *input = inputOutput[@"input"];
			AVAssetReaderTrackOutput *assetReaderTrackOutput = inputOutput[@"output"];
			[input requestMediaDataWhenReadyOnQueue:requestMediaDataQueue usingBlock:^{
				while ([input isReadyForMoreMediaData])
				{
					CMSampleBufferRef nextSampleBuffer = [assetReaderTrackOutput copyNextSampleBuffer];
					if (nextSampleBuffer)
					{
						[input appendSampleBuffer:nextSampleBuffer];
						CFRelease(nextSampleBuffer);
					}
					else
					{
						[input markAsFinished];
						dispatch_group_leave(dispatchGroup);
						
						if (assetReader.status == AVAssetReaderStatusFailed)
							NSLog(@"the reader failed: %@", assetReader.error);
						
						break;
					}
				}
			}];
		}
		
		// Write samples from SubtitlesTextReaders
		for (NSDictionary *subtitlesInputOutput in subtitlesInputsOutputs)
		{
			dispatch_group_enter(dispatchGroup);
			dispatch_queue_t requestMediaDataQueue = dispatch_queue_create("request media data", DISPATCH_QUEUE_SERIAL);
			AVAssetWriterInput *input = subtitlesInputOutput[@"input"];
			SubtitlesTextReader *subtitlesTextReader = subtitlesInputOutput[@"output"];
			[input requestMediaDataWhenReadyOnQueue:requestMediaDataQueue usingBlock:^{
				while ([input isReadyForMoreMediaData])
				{
					CMSampleBufferRef nextSampleBuffer = [subtitlesTextReader copyNextSampleBuffer];
					if (nextSampleBuffer)
					{
						[input appendSampleBuffer:nextSampleBuffer];
						CFRelease(nextSampleBuffer);
					}
					else
					{
						[input markAsFinished];
						dispatch_group_leave(dispatchGroup);
						break;
					}
				}
			}];
		}
		
		dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
		[assetReader cancelReading];
		
		dispatch_group_enter(dispatchGroup);
		[assetWriter finishWritingWithCompletionHandler:^(void) {
			if (AVAssetWriterStatusCompleted == assetWriter.status)
				NSLog(@"writing success to %@", assetWriter.outputURL);
			else if (AVAssetWriterStatusFailed == assetWriter.status)
				NSLog (@"writer failed with error: %@", assetWriter.error);
			dispatch_group_leave(dispatchGroup);
		}];
		dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
	}
	else
	{
		NSLog(@"asset writer failed to start writing: %@", assetWriter.error);
	}
}

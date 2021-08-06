/*
	Copyright (C) 2015 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	'AAPLMovieMutator' wraps AVMutableMovie to implement cut, copy, and paste and provides an interface for interacting with the AVMutableMovie. This class uses an AVMutableMovie as an internal pasteboard to keep track of edits, and this class uses the general NSPasteboard to move movie header data to other documents.
 */

@import AppKit;
@import AVFoundation;
@import CoreMedia;
#import "AAPLMovieMutator.h"

static NSString* const movieEditorPasteboardType = @"com.example.apple-samplecode.AVMovieEditor";

@interface AAPLMovieMutator()

@property AVMutableMovie *internalMovie;
@property AVMutableMovie *internalPasteboard;

@end

@implementation AAPLMovieMutator

- (instancetype)initWithMovie:(AVMovie *)movie {
	if (self = [super init]) {
		self.internalMovie = movie.mutableCopy;
		self.internalPasteboard = [[AVMutableMovie alloc] init];
	}
	
	return self;
}

#pragma mark - Cut, Copy, Paste

- (BOOL)cutTimeRange:(CMTimeRange)range error:(NSError *)error{
	// Clear what we have on the Pasteboard, then insert the new data on the Pasteboard.
	self.internalPasteboard = [[AVMutableMovie alloc] init];
	BOOL didSucceed = [self.internalPasteboard insertTimeRange:range ofAsset:self.internalMovie atTime:kCMTimeZero copySampleData:NO error:&error];
	
	if (!didSucceed) {
		return false;
	}
	
	// Add the piece that was cut out to the Pasteboard so we can Paste it later if necessary.
	[self addPasteboardMovieDataToPasteBoard];
	
	// Perform the cut operation
	[self.internalMovie removeTimeRange:range];
	[self internalMovieDidChange];
	
	return true;
}

- (BOOL)copyTimeRange:(CMTimeRange)range error:(NSError *)error {
	//Clear what we have on the Pasteboard, then insert the new data on the Pasteboard.
	self.internalPasteboard = [[AVMutableMovie alloc] init];
	BOOL didSucceed = [self.internalPasteboard insertTimeRange:range ofAsset:self.internalMovie atTime:kCMTimeZero copySampleData:NO error:&error];
	
	if (!didSucceed) {
		return false;
	}
	
	// Add the copied range to the Pasteboard so we can Paste it later if necessary.
	[self addPasteboardMovieDataToPasteBoard];
	
	return true;
}

- (BOOL)pasteAtTime:(CMTime)time error:(NSError *)error{
	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	if ([pasteboard canReadItemWithDataConformingToTypes:@[movieEditorPasteboardType]]) {
		NSData *videoData = [pasteboard dataForType:movieEditorPasteboardType];
		AVMovie *insertionMovie = [AVMovie movieWithData:videoData options:nil];
		//It’s possible to examine “insertionMovie” here to determine whether some additional work could be done to preserve the track associations and track groupings.
		
		CMTimeRange insertionRange = CMTimeRangeMake(kCMTimeZero, insertionMovie.duration);
		BOOL didSucceed = [self.internalMovie insertTimeRange:insertionRange ofAsset:insertionMovie atTime:time copySampleData:NO error:&error];
		// If the insertion did not succeed return NO before we notify that the internal movie was changed.
		if (!didSucceed) {
			return NO;
		}
		[self internalMovieDidChange];
		return YES;
	} else {
		return NO;
	}
}

#pragma mark - PlayerItem Creation

- (AVPlayerItem *)makePlayerItem {
	AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:self.internalMovie.copy];
	playerItem.videoComposition = [self makeVideoComposition];
	return playerItem;
}

- (AVVideoComposition *)makeVideoComposition {
	// If we have more than one video track we need to create a video composition in order to playback the movie correctly.
	if ([self.internalMovie tracksWithMediaType:AVMediaTypeVideo].count > 1) {
		return [AVVideoComposition videoCompositionWithPropertiesOfAsset:self.internalMovie];
	}
	
	return nil;
}

#pragma mark - Percentage to CMTime mapping

- (CMTime)timePercentageThroughMovie:(float)percentage{
	float elapsedTime = percentage * CMTimeGetSeconds(self.internalMovie.duration);
	
	return CMTimeMakeWithSeconds(elapsedTime, 1000);
}

#pragma mark - Image Generation

- (void)generateImages:(NSUInteger)numberOfImages withCompletionHandler:(ImageGenerationCompletionHandler)completionHandler{
	if (CMTIME_COMPARE_INLINE(kCMTimeZero, !=, self.internalMovie.duration) && [self.internalMovie tracksWithMediaType:AVMediaTypeVideo] > 0) {
		NSArray<NSValue *> *times = [self imageTimesForNumberOfImages:numberOfImages];
		AVAssetImageGenerator *imageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:self.internalMovie];
		
		// Set a videoComposition on the ImageGenerator if the underlying movie has more than 1 video track.
		imageGenerator.videoComposition = [self makeVideoComposition];
		[imageGenerator generateCGImagesAsynchronouslyForTimes:times completionHandler:^(CMTime requestedTime, CGImageRef  __nullable image, CMTime actualTime, AVAssetImageGeneratorResult result, NSError * __nullable error) {
			if (image != nil) {
				NSImage *nextImage = [[NSImage alloc] initWithCGImage:image size:NSMakeSize(CGImageGetWidth(image), CGImageGetHeight(image))];
				completionHandler(nextImage);
			} else {
				NSLog(@"There was an error creating an image at time: %f", CMTimeGetSeconds(requestedTime));
			}
		}];
	}
}

- (NSArray<NSValue *>*)imageTimesForNumberOfImages:(NSUInteger)numberOfImages {
	float movieSeconds = CMTimeGetSeconds(self.internalMovie.duration);
	float incrementSeconds = movieSeconds / numberOfImages;
	CMTime movieDuration = self.internalMovie.duration;
	
	CMTime incrementTime = CMTimeMakeWithSeconds(incrementSeconds, 1000);
	NSMutableArray <NSValue *> *times = [NSMutableArray array];
	
	// Generate an image at time zero.
	CMTime startTime = kCMTimeZero;
	while (CMTIME_COMPARE_INLINE(startTime, <=, movieDuration)) {
		NSValue *nextValue = [NSValue valueWithCMTime:startTime];
		if (CMTIME_COMPARE_INLINE(startTime, ==, movieDuration)) {
			// Ensure that one image is always the last image in the movie.
			nextValue = [NSValue valueWithCMTime:movieDuration];
		}
		[times addObject:nextValue];
		startTime = CMTimeAdd(startTime, incrementTime);
	}
	
	return [times copy];
}

#pragma mark - Notifications

- (void)internalMovieDidChange {
	// Post a notification for all observers to respond to when the internal movie has had new data added (cut or paste).
	[[NSNotificationCenter defaultCenter] postNotificationName:movieWasMutated object:self];
}

#pragma mark - Pasteboard

- (void)addPasteboardMovieDataToPasteBoard{
	NSError *error = nil;
	// Get the movie header data.
	NSData *movieData = [self.internalPasteboard movieHeaderWithFileType:AVFileTypeQuickTimeMovie error:&error];
	if (!error) {
		// Clear what is currently on the pasteboard and then put the movie data on the pasteboard.
		NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
		[pasteboard clearContents];
		[pasteboard setData:movieData forType:movieEditorPasteboardType];
	} else {
		NSLog(@"There was an error getting data for the movie: %@", error);
	}
}

#pragma mark - Write self-contained Movie

- (BOOL)writeMovieToURL:(NSURL *)outputURL fileType:(NSString *)fileType error:(NSError *)error {
	// Create a new move then copy all the sampes to the outputURL.
	AVMutableMovie *writingMovie = [AVMutableMovie movieWithSettingsFromMovie:self.internalMovie options:nil error:&error];
	writingMovie.defaultMediaDataStorage = [[AVMediaDataStorage alloc] initWithURL:outputURL options:nil];

	// Copy all of the samples to the output movie from the internal movie that has been created.
	BOOL didSucceed = [writingMovie insertTimeRange:CMTimeRangeMake(kCMTimeZero, self.internalMovie.duration) ofAsset:self.internalMovie atTime:kCMTimeZero copySampleData:YES error:&error];
	if (!didSucceed) {
		return NO;
	}
	// Work can be done here to preserve track references and alternate groups in the self-contained output movie
	
	// Write the movie header at the output URL to create a self-contained movie.
	didSucceed = [writingMovie writeMovieHeaderToURL:outputURL fileType:fileType options:0 error:&error];
	if (!didSucceed) {
		return NO;
	}
	
	return YES;
}

@end

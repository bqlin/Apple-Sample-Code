/*
	Copyright (C) 2015 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	The 'AAPLDocument' provides a way for documents to be opened and backed by AVMovie. This document does work to ensure that the documents that are saved and opened are compatible with the underlying AVMovie.
 */

@import AVFoundation;
#import "AAPLDocument.h"
#import "AAPLMovieMutator.h"
#import "AAPLMovieViewController.h"

@interface AAPLDocument() <AAPLMovieViewControllerDelegate>

#pragma mark - Properties

@property AAPLMovieMutator *movieMutator;
@property AAPLMovieViewController *movieViewController;

@end

@implementation AAPLDocument

#pragma mark - Window setup

- (void)makeWindowControllers {
	NSStoryboard *storyboard = [NSStoryboard storyboardWithName:@"Main" bundle:nil];
	NSWindowController* windowController = [storyboard instantiateControllerWithIdentifier:@"Document Window Controller"];
	[self addWindowController:windowController];
	self.movieViewController = (AAPLMovieViewController *)windowController.contentViewController;
	self.movieViewController.delegate = self;
	self.movieViewController.playerView.player = [AVPlayer playerWithPlayerItem:[self.movieMutator makePlayerItem]];

	// Add an observer for the MovieMutator to know if data has been pasted into it or cut out of it, and then update accordingly.
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(underlyingMovieWasMutated) name:movieWasMutated object:self.movieMutator];
	windowController.window.backgroundColor = [NSColor blackColor];
}

- (void)underlyingMovieWasMutated {
	self.movieViewController.playerView.player = [AVPlayer playerWithPlayerItem:[self.movieMutator makePlayerItem]];
	[self.movieViewController updateMovieTimeline];
	self.movieViewController.view.needsDisplay = YES;
}

- (BOOL)readFromURL:(nonnull NSURL *)url ofType:(nonnull NSString *)typeName error:(NSError * __nullable __autoreleasing * __nullable)outError{
	NSString *fileType = [self UTIFromPathExtension:url.pathExtension];

	// If the UTI is not one of AVMovie.movieTypes() then this movie is not supported by AVMovie and should not be opened.
	if (![[AVMovie movieTypes] containsObject:fileType]) {
		return false;
	}
	
	AVMovie *currentMovie = [AVMovie movieWithURL:url options:nil];
	self.movieMutator = [[AAPLMovieMutator alloc] initWithMovie:currentMovie];

	return true;
}

- (BOOL)cutMovieTimeRange:(CMTimeRange)timeRange error:(NSError *)error {
	return [self.movieMutator cutTimeRange:timeRange error:error];
}

- (BOOL)copyMovieTimeRange:(CMTimeRange)timeRange error:(NSError *)error {
	return [self.movieMutator copyTimeRange:timeRange error:error];
}

- (BOOL)pasteMovieAtTime:(CMTime)time error:(NSError *)error {
	return [self.movieMutator pasteAtTime:time error:error];
}

- (void)movieViewController:(AAPLMovieViewController *)movieViewController needsNumberOfImages:(NSUInteger)numberOfImages completionHandler:(ImageGenerationCompletionHandler)completionHandler {
	[self.movieMutator generateImages:numberOfImages withCompletionHandler:completionHandler];
}

- (CMTime)timeAtPercentage:(float)percentage {
	return [self.movieMutator timePercentageThroughMovie:percentage];
}

#pragma mark - File -> Save

- (void)saveDocument:(nullable id)sender {
	NSSavePanel *savePanel = [NSSavePanel savePanel];

	// The only UTIs that AVMovie can write to are in AVMovie.movieTypes()
	savePanel.allowedFileTypes = [AVMovie movieTypes];
	[savePanel beginWithCompletionHandler:^(NSInteger result) {
		if (result == 1) {
			NSURL *url = savePanel.URL;
			NSString *fileType = [self UTIFromPathExtension:url.pathExtension];
			NSError *error = nil;
			BOOL didSucceed = [self.movieMutator writeMovieToURL:url fileType:fileType error:error];
			if (!didSucceed || error) {
				NSLog(@"There was a problem saving the movie.");
			}
		}
	}];
}

#pragma mark - Cleanup

- (void)canCloseDocumentWithDelegate:(nonnull id)delegate shouldCloseSelector:(nullable SEL)shouldCloseSelector contextInfo:(nullable void *)contextInfo {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:movieWasMutated object:self.movieMutator];
	[super canCloseDocumentWithDelegate:delegate shouldCloseSelector:shouldCloseSelector contextInfo:contextInfo];
}

- (NSString *)UTIFromPathExtension:(NSString *)pathExtension {
	// Figure out the correct UTI from the path extension.
	NSString *fileType = AVFileTypeQuickTimeMovie;
	if ([pathExtension.lowercaseString isEqualToString:@"mp4"])
		fileType = AVFileTypeMPEG4;
	else if ([pathExtension.lowercaseString isEqualToString:@"m4v"])
		fileType = AVFileTypeAppleM4V;
	else if ([pathExtension.lowercaseString isEqualToString:@"m4a"])
		fileType = AVFileTypeAppleM4A;
	
	return fileType;
}

@end

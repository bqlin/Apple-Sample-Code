/*
	Copyright (C) 2015 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	The 'AAPLMovieViewController' and 'AAPLMovieViewControllerDelegate' provide a way for this ViewController and it's subviews to talk to a data source that understands how to manipulate the QuickTime File Format and edit movies.
 */

@import Cocoa;
@import AVFoundation;
@import AVKit;

typedef void (^ImageGenerationCompletionHandler)(NSImage *);

@class AAPLMovieViewController;

@protocol AAPLMovieViewControllerDelegate

- (void)movieViewController:(AAPLMovieViewController *)movieViewController needsNumberOfImages:(NSUInteger)numberOfImages completionHandler:(ImageGenerationCompletionHandler)completionHandler;
- (CMTime)timeAtPercentage:(float)percentage;
- (BOOL)cutMovieTimeRange:(CMTimeRange)timeRange error:(NSError *)error;
- (BOOL)copyMovieTimeRange:(CMTimeRange)timeRange error:(NSError *)error;
- (BOOL)pasteMovieAtTime:(CMTime)time error:(NSError *)error;

@end

@interface AAPLMovieViewController : NSViewController

@property (weak) IBOutlet AVPlayerView *playerView;
@property id<AAPLMovieViewControllerDelegate> delegate;
- (void)updateMovieTimeline;

@end

/*
	Copyright (C) 2015 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	The `AAPLMovieTimeline` and `AAPLMovieTimelineDelegate` protocols provide the infrastructure for drawing video track images in a timeline like view and track cursor movements and selections.
 */

#import <Cocoa/Cocoa.h>

@class AAPLMovieTimeline;

@protocol AAPLMovieTimelineUpdateDelgate <NSObject>

- (void)movieTimeline:(AAPLMovieTimeline *)timeline didUpdateCursorToPoint:(NSPoint)toPoint;
- (void)didSelectTimelineRangeFromPoint:(NSPoint)fromPoint toPoint:(NSPoint)toPoint;
- (void)didSelectTimelinePoint:(NSPoint)point;

@end

@interface AAPLMovieTimeline : NSView

@property id<AAPLMovieTimelineUpdateDelgate> delegate;

- (void)removeAllPositionalSubviews;
- (NSUInteger)countOfImagesRequiredToFillView;
- (void)addImageView:(NSImage *)image;
- (void)updateTimeLabel:(NSString *)newLabel;

@end

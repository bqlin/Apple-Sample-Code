/*
	Copyright (C) 2015 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	The `AAPLMovieTimeline` and `AAPLMovieTimelineDelegate` protocols provide the infrastructure for drawing video track images in a timeline like view and track cursor movements and selections.
 */

#import "AAPLMovieTimeline.h"
#import "AAPLTimeRangeView.h"
#import <QuartzCore/QuartzCore.h>

@interface AAPLMovieTimeline()

@property NSUInteger imagesAdded;
@property CALayer *markerLayer;
@property NSTrackingArea *trackingArea;
@property CALayer *startPointMarker;
@property NSPoint startingPoint;
@property NSPoint endingPoint;
@property NSUInteger numberOfMarkers;
@property AAPLTimeRangeView *timeRangeView;
@property NSTextField *timeLabel;

@end

@implementation AAPLMovieTimeline

#pragma mark - initializers

- (instancetype)initWithCoder:(nonnull NSCoder *)coder {
	if (self = [super initWithCoder:coder]) {
		// Setup a layer with a black background color
		self.wantsLayer = YES;
		self.layer = [CALayer layer];
		self.layer.backgroundColor = [NSColor blackColor].CGColor;
		self.timeLabel = [[NSTextField alloc] init];
		[self setupMarkerLayer];

		//Add a tracking area to track the cursor in this view
		self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSMakeRect(-1.0, 0.0, self.frame.size.width, self.frame.size.height) options:(NSTrackingMouseMoved | NSTrackingActiveAlways) owner:self userInfo:nil];
		[self addTrackingArea:self.trackingArea];
	}
	
	return self;
}

- (CGFloat)imageViewWidth {
	return (self.frame.size.height * 16) / 9;
}

#pragma mark - Subview/Layer Management

- (void)layout {
	// Remove the tracking area and re-add it when we layout in case the frame has changed size.
	if (self.trackingArea != nil) {
		[self removeTrackingArea:self.trackingArea];
		self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSMakeRect(-1.0, 0.0, self.frame.size.width, self.frame.size.height) options:(NSTrackingMouseMoved | NSTrackingActiveAlways) owner:self userInfo:nil];
		[self addTrackingArea:self.trackingArea];
	}
	
	[super layout];
}

- (void)setupMarkerLayer {
	// Add the markerlayer and the timelabel for the timeline.
	self.markerLayer = [CALayer layer];
	self.markerLayer.frame = CGRectMake(0.0f, 0.0f, 5.0, self.frame.size.height);
	self.markerLayer.backgroundColor = [NSColor redColor].CGColor;
	[self.layer addSublayer:self.markerLayer];

	self.timeLabel.frame = NSMakeRect(self.frame.origin.x, self.frame.origin.y, 50.0f, 25.0f);
	self.timeLabel.backgroundColor = [NSColor clearColor];
	self.timeLabel.textColor = [NSColor whiteColor];
	self.timeLabel.drawsBackground = NO;
	self.timeLabel.editable = NO;
	self.timeLabel.bezeled = NO;
	[self addSubview:self.timeLabel];
}

- (void)updateTimeLabel:(NSString *)newLabel {
	self.timeLabel.stringValue = newLabel;
}

- (void)addImageView:(NSImage *)image {
	CGFloat nextX = self.imagesAdded * self.imageViewWidth;
	NSImageView *nextView = [[NSImageView alloc] initWithFrame:NSMakeRect(nextX, 0.0, self.imageViewWidth, self.frame.size.height)];
	nextView.image = image;
	
	[self addSubview:nextView];
	[self setNeedsDisplayInRect:self.frame];
	self.imagesAdded++;
	
	// Remove the marker layer and time label then re add them to draw above the images.
	[self.markerLayer removeFromSuperlayer];
	[self.timeLabel removeFromSuperview];
	[self addSubview:self.timeLabel];
	[self.layer addSublayer:self.markerLayer];
}

- (void)removeAllPositionalSubviews {
	[self.subviews enumerateObjectsUsingBlock:^(__kindof NSView * __nonnull subView, NSUInteger idx, BOOL * __nonnull stop) {
		[subView removeFromSuperview];
	}];
	self.imagesAdded = 0;
}

- (NSUInteger)countOfImagesRequiredToFillView {
	return floor(self.frame.size.width / self.imageViewWidth);
}

#pragma mark - Cursor Movement methods

- (void)moveMarkerLayerAndtimeLabelWithMouse:(NSEvent *)theEvent {
	NSPoint windowLocation = theEvent.locationInWindow;
	NSPoint newPoint = [self convertPoint:windowLocation fromView:nil];
	
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	self.markerLayer.frame = CGRectMake(newPoint.x, 0.0f, 5.0f, self.frame.size.height);
	self.timeLabel.frame = NSMakeRect(newPoint.x + 5.0f, 0.0f, 50.0f, 25.0f);
	[CATransaction commit];
	[self.delegate movieTimeline:self didUpdateCursorToPoint:newPoint];
}

- (void)mouseDown:(nonnull NSEvent *)theEvent {
	[self.timeRangeView removeFromSuperview];
	self.startingPoint = [self convertPoint:theEvent.locationInWindow toView:nil];
}

- (void)mouseMoved:(nonnull NSEvent *)theEvent {
	[self moveMarkerLayerAndtimeLabelWithMouse:theEvent];
}

- (void)mouseDragged:(nonnull NSEvent *)theEvent {
	[self moveMarkerLayerAndtimeLabelWithMouse:theEvent];
}

- (void)mouseUp:(nonnull NSEvent *)theEvent {
	self.endingPoint = [self convertPoint:theEvent.locationInWindow fromView:nil];
	
	if (self.startingPoint.x == self.endingPoint.x) {
		[self.timeRangeView removeFromSuperview];
		self.startPointMarker.frame = CGRectMake(self.endingPoint.x, 0.0f, 5.0f, self.frame.size.height);
		self.startPointMarker.backgroundColor = [NSColor yellowColor].CGColor;
		[self.delegate didSelectTimelinePoint:self.endingPoint];
	} else {
		[self.startPointMarker removeFromSuperlayer];
		self.timeRangeView = [[AAPLTimeRangeView alloc] initWithFrame:NSMakeRect(self.startingPoint.x, 0.0, self.endingPoint.x - self.startingPoint.x, self.frame.size.height)];
		[self addSubview:self.timeRangeView];
		[self.delegate didSelectTimelineRangeFromPoint:self.startingPoint toPoint:self.endingPoint];
		self.endingPoint = NSZeroPoint;
	}
}

@end

/*
	Copyright (C) 2015 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	'AAPLTimeRangView' is a simple view that draws a yellow highlight.
 */

#import "AAPLTimeRangeView.h"

@implementation AAPLTimeRangeView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
	
	CGContextRef currentContext = [NSGraphicsContext currentContext].CGContext;
	CGContextSaveGState(currentContext);

	[[NSColor yellowColor] set];

	NSBezierPath *bezierPath = [NSBezierPath bezierPathWithRoundedRect:dirtyRect xRadius:0.0 yRadius:2.0];
	bezierPath.lineWidth = 5.0;
	[bezierPath stroke];

	CGContextRestoreGState(currentContext);
}

@end

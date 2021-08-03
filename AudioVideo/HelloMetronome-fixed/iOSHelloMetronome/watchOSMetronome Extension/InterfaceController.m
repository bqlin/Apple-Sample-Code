/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

*/

#import "InterfaceController.h"
#import "Metronome.h"

static const CGFloat    kArcWidth       = 8.0f;                        // points
static const CGFloat    kArcGapAngle    = (16.0f * M_PI) / 180.0f;     // radians

@interface InterfaceController() <WKCrownDelegate, MetronomeDelegate> {
    NSMutableArray  *_foregroundArcArray;
    double          _accumulatedRotations;
    BOOL            _wasRunning;
}

@property (weak, nonatomic) IBOutlet WKInterfaceGroup* backgroundArcsGroup;
@property (weak, nonatomic) IBOutlet WKInterfaceGroup* foregroundArcsGroup;
@property (weak, nonatomic) IBOutlet WKInterfaceLabel* tempoLabel;
@property (weak, nonatomic) IBOutlet WKInterfaceLabel* meterLabel;

@end

@implementation InterfaceController

- (void)awakeWithContext:(id)context {
    [super awakeWithContext:context];
    
    // Create and Initialize Metronome Object
    [Metronome sharedInstance];
    
    // Draw Background and Foreground Arcs
    [self drawArcs];
    
    // Register for Crown Turn Notifications
    [self.crownSequencer setDelegate:self];
    [self.crownSequencer focus];
    
    [[Metronome sharedInstance] setDelegate:self];
    
    // if media services are reset, we need to rebuild our audio chain
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMediaServicesWereReset:)
                                                 name:AVAudioSessionMediaServicesWereResetNotification
                                               object:[AVAudioSession sharedInstance]];
}

- (void)willActivate {
    // This method is called when watch view controller is about to be visible to user
    [super willActivate];
    
    [self updateMeterLabel];
    [self updateTempoLabel];
}

- (void)didDeactivate {
    // This method is called when watch view controller is no longer visible
    
    [[Metronome sharedInstance] stopClock];
    
    [super didDeactivate];
}

#pragma mark - Metronome Delegate

- (void)metronomeTick:(NSInteger)currentTick {
    [self updateArcWithTick:currentTick];
}

#pragma mark - WKCrownSequencer Delegate

- (void)crownDidRotate:(WKCrownSequencer *)crownSequencer rotationalDelta:(double)rotationalDelta {
    
   if ([[Metronome sharedInstance] isRunning]) {
        [[Metronome sharedInstance] stopClock];
        [self updateArcWithTick:0];
       _wasRunning = YES;
    }
    
    NSInteger value = 0;
    _accumulatedRotations += rotationalDelta;
    if (_accumulatedRotations >= 0.15) {
        value = 1;
        _accumulatedRotations = 0;
    } else if (_accumulatedRotations <= -0.15) {
        value = -1;
        _accumulatedRotations = 0;
    }
    
    if (value) {
        [[Metronome sharedInstance] incrementTempo:value];
        [self updateTempoLabel];
    }
}

- (void)crownDidBecomeIdle:(nullable WKCrownSequencer *)crownSequencer {
    if (_wasRunning) {
        [[Metronome sharedInstance] startClock];
        _wasRunning = NO;
    }
}

#pragma mark - User Interface Methods

- (IBAction)tapGestureRecognized:(id)sender {
    if ([[Metronome sharedInstance] isRunning]) {
        [[Metronome sharedInstance] stopClock];
        [self updateArcWithTick:0];
    } else {
        [[Metronome sharedInstance] startClock];
    }
}

- (IBAction)swipeRightGestureRecognized:(id)sender {
    
    BOOL wasRunning = [[Metronome sharedInstance] isRunning];
    
    if (wasRunning) {
        [[Metronome sharedInstance] stopClock];
    }
    
    [[Metronome sharedInstance] incrementMeter:-1];
    [self drawArcs];
    [self updateMeterLabel];
    
    if (wasRunning) {
        [[Metronome sharedInstance] startClock];
    }
}

- (IBAction)swipeLeftGestureRecognized:(id)sender {
    
    BOOL wasRunning = [[Metronome sharedInstance] isRunning];
    
    if (wasRunning) {
        [[Metronome sharedInstance] stopClock];
    }
    
    [[Metronome sharedInstance] incrementMeter:+1];
    [self drawArcs];
    [self updateMeterLabel];
    
    if (wasRunning) {
        [[Metronome sharedInstance] startClock];
    }
}

- (IBAction)swipeUpGestureRecognized:(id)sender {
    [[Metronome sharedInstance] incrementDivisionIndex:+1];
    [self updateMeterLabel];
}


- (IBAction)swipeDownGestureRecognized:(id)sender {
    [[Metronome sharedInstance] incrementDivisionIndex:-1];
    [self updateMeterLabel];
}

#pragma mark - Private Methods

- (void)updateArcWithTick:(NSInteger)currentTick {
    if ([[Metronome sharedInstance] isRunning]) {
        [self.foregroundArcsGroup setBackgroundImage:(UIImage*)[_foregroundArcArray objectAtIndex:currentTick]];
    } else {
        [self.foregroundArcsGroup setBackgroundImage:NULL];
    }
}

- (void)updateMeterLabel {
    [self.meterLabel setText:[NSString stringWithFormat:@"%d / %d", (int)[[Metronome sharedInstance] meter], (int)[[Metronome sharedInstance] division]]];
}

- (void)updateTempoLabel {
    [self.tempoLabel setText:[NSString stringWithFormat:@"%d BPM", (int)[[Metronome sharedInstance] tempo]]];
}

#pragma mark - Drawing Methods

- (void)drawArcs {
    
    NSUInteger meter = [[Metronome sharedInstance] meter];
    
    CGFloat scale = [WKInterfaceDevice currentDevice].screenScale;
    CGColorRef foregroundFillColor = [UIColor colorWithRed:0.301f green:0.556f blue:0.827f alpha:1.0f].CGColor;
    CGColorRef firstElementFillColor = [UIColor colorWithRed:0.301f green:0.729f blue:0.478f alpha:1.0f].CGColor;
    CGColorRef backgroundFillColor = [UIColor colorWithRed:0.5f green:0.5f blue:0.5f alpha:1.0f].CGColor;
    
    CGFloat contentFrameWidth = self.contentFrame.size.width;
    CGFloat contentFrameHeight = self.contentFrame.size.height;
    CGPoint center = CGPointMake(contentFrameWidth / 2.0, contentFrameHeight / 2.0);
    CGFloat radius = MIN(contentFrameWidth / 2.0, contentFrameHeight/ 2.0) - (kArcWidth/2.0f);
    
    CGFloat stepAngle = ((2.0f * M_PI) / meter) - kArcGapAngle;
    
    // Draw Background Rings
    CGFloat startAngle = (kArcGapAngle / 2.0f) - (1.5f * M_PI_2);
    UIGraphicsBeginImageContextWithOptions(self.contentFrame.size, false, scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextBeginPath(context);
    for (NSUInteger i = 0; i < meter; i++) {
        CGPathRef strokedArc = [self newDonutArcWithCenter:center withRadius:radius fromStartAngle:startAngle toEndAngle:startAngle + stepAngle];
        CGContextAddPath(context, strokedArc);
        CGPathRelease(strokedArc);
        startAngle += stepAngle + kArcGapAngle;
    }
    CGContextClosePath(context);
    CGContextSetFillColorWithColor(context, backgroundFillColor);
    CGContextFillPath(context);
    
    CGImageRef cgBackgroundImage = CGBitmapContextCreateImage(context);
    UIImage* backgroundImage = [UIImage imageWithCGImage:cgBackgroundImage];
    [self.backgroundArcsGroup setBackgroundImage:backgroundImage];
    CGImageRelease(cgBackgroundImage);
    UIGraphicsEndImageContext();
    
    // Draw and Store Foreground Rings
    [_foregroundArcArray removeAllObjects];
    _foregroundArcArray = nil;
    _foregroundArcArray = [[NSMutableArray alloc] init];
    
    startAngle = (kArcGapAngle / 2.0f) - (1.5f * M_PI_2);
    for (NSUInteger i = 0; i < meter; i++) {
        UIGraphicsBeginImageContextWithOptions(self.contentFrame.size, false, scale);
        context = UIGraphicsGetCurrentContext();
        CGContextBeginPath(context);
        CGPathRef strokedArc = [self newDonutArcWithCenter:center withRadius:radius fromStartAngle:startAngle toEndAngle:startAngle+stepAngle];
        CGContextAddPath(context, strokedArc);
        CGPathRelease(strokedArc);
        CGContextClosePath(context);
        
        if (i==0) {
            CGContextSetFillColorWithColor(context, firstElementFillColor);
        } else {
            CGContextSetFillColorWithColor(context, foregroundFillColor);
        }
        CGContextFillPath(context);
        
        CGImageRef cgImage = CGBitmapContextCreateImage(context);
        UIImage* foregroundImage = [UIImage imageWithCGImage:cgImage];
        [_foregroundArcArray addObject:foregroundImage];
        CGImageRelease(cgImage);
        UIGraphicsEndImageContext();
        
        startAngle += stepAngle + kArcGapAngle;
    }
}

- (CGPathRef)newDonutArcWithCenter:(CGPoint)centerPoint withRadius:(CGFloat)radius fromStartAngle:(CGFloat)startAngle toEndAngle:(CGFloat)endAngle {
    
    CGMutablePathRef arc = CGPathCreateMutable();
    
    CGPathAddArc(arc, NULL,
                 centerPoint.x, centerPoint.y,
                 radius,
                 startAngle,
                 endAngle,
                 NO);
    
    CGPathRef strokedArc = CGPathCreateCopyByStrokingPath(arc, NULL, kArcWidth, kCGLineCapSquare,
                                                          kCGLineJoinMiter,
                                                          10); // 10 is default miter limit
    CGPathRelease(arc);
    
    return strokedArc;
}

#pragma mark- AVAudioSession Notifications
// see https://developer.apple.com/library/content/qa/qa1749/_index.html
- (void)handleMediaServicesWereReset:(NSNotification *)notification
{
    NSLog(@"Media services have reset...");
    
    // reset
    [[Metronome sharedInstance] setDelegate:nil];
    [[Metronome sharedInstance] reset];
    
    // reset label and draw background and foreground arcs
    [self updateMeterLabel];
    [self drawArcs];
    
    [[Metronome sharedInstance] setDelegate:self];
    
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (error) {
        NSLog(@"AVAudioSession error %d, %@", error.code, error.localizedDescription);
    }
}

@end

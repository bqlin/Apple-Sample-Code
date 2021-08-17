/*
     File: APLDocument.m
 Abstract: The players document class. It sets up four AVPlaybackViews each of which handle their own AVPlayers.It manages adjusting the playback rate, enables and disables UI elements as appropriate, sets up a time observer for updating the current time (which the UI's time slider is bound to).
  Version: 1.0
 
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

#import "APLDocument.h"
#import "APLPlaybackView.h"

NSString* const AVMSDMouseDownNotification = @"AVMSDMouseDownNotification";
NSString* const AVMSDMouseUpNotification = @"AVMSDMouseUpNotification";

#pragma mark - Timer slider

@interface TimeSliderCell : NSSliderCell

@end

@interface TimeSlider : NSSlider

@end


@implementation TimeSliderCell

- (void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint inView:(NSView *)controlView mouseIsUp:(BOOL)flag
{
	if (flag) {
		[[NSNotificationCenter defaultCenter] postNotificationName:AVMSDMouseUpNotification object:self];
	}
	[super stopTracking:lastPoint at:stopPoint inView:controlView mouseIsUp:flag];
}

@end


@implementation TimeSlider

- (void)mouseDown:(NSEvent *)theEvent
{
	[[NSNotificationCenter defaultCenter] postNotificationName:AVMSDMouseDownNotification object:self];
	[super mouseDown:theEvent];
}

@end


#pragma mark - Document

@interface APLDocument () <AVPlaybackViewEventHandlingDelegate>
{
	NSInteger		_currentlyActiveViewIndex;
	NSArray		   *_playbackViewsArray;
}

@property double			currentTime;
@property (readonly) double duration;
@property float				playRateToRestore;
@property id				timeObserverToken;

@property (weak) IBOutlet APLPlaybackView *bottomLeftView;
@property (weak) IBOutlet APLPlaybackView *bottomRightView;
@property (weak) IBOutlet APLPlaybackView *topLeftView;
@property (weak) IBOutlet APLPlaybackView *topRightView;

@property (weak) IBOutlet TimeSlider *timeSlider;

@end

@implementation APLDocument


- (NSString *)windowNibName
{
	return @"APLDocument";
}


- (void)windowControllerDidLoadNib:(NSWindowController *)aController
{
	[super windowControllerDidLoadNib:aController];
	
	_playbackViewsArray = @[self.bottomLeftView, self.bottomRightView, self.topLeftView, self.topRightView];
	
	for (APLPlaybackView *playbackView in _playbackViewsArray) {
			playbackView.delegate = self;
			[playbackView setupPlaybackUsingURL:self.fileURL];
	}
	
	[self addTimeObserverToPlayer];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(beginScrubbing:)
												 name:AVMSDMouseDownNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(endScrubbing:)
												 name:AVMSDMouseUpNotification
											   object:nil];
}

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
	return YES;
}


- (void)close
{
	[self.topLeftView.player removeTimeObserver:_timeObserverToken];
	[super close];
}


- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVMSDMouseUpNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVMSDMouseDownNotification object:nil];
}


- (void)prerollPlayersAndStartPlayback
{
	dispatch_group_t dispatchGroup = dispatch_group_create();
	
	for (APLPlaybackView *view in _playbackViewsArray) {
		dispatch_group_enter(dispatchGroup);
		[view.player prerollAtRate:1.0 completionHandler:^(BOOL finished){
			if (!finished) {
				printf("Prerolling at rate 1.0 interrupted\n");
			}
			dispatch_group_leave(dispatchGroup);
		}];
	}
	
	// Wait until all 4 players complete preroll
	dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^(){
		// Start playback when host time is 0.01 sec from now
		CMTime hostTimeNow = CMClockGetTime(CMClockGetHostTimeClock());
		CMTime hostTimeDelta = CMTimeMakeWithSeconds(0.01, hostTimeNow.timescale);
		
		for (APLPlaybackView *view in _playbackViewsArray) { // Start playback for all views
			[view.player setRate:1.0 time:CMTimeMakeWithSeconds([self currentTime], 1) atHostTime:CMTimeAdd(hostTimeNow, hostTimeDelta)];
		}
	});
}

- (void)addTimeObserverToPlayer
{
	if (_timeObserverToken)
		return;
	
	__weak APLDocument *weakSelf = self;
	_timeObserverToken = [self.topLeftView.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1, 2) queue:dispatch_get_main_queue() usingBlock:
						  ^(CMTime time) {
							  [weakSelf syncScrubber];
						  }];
}

- (void)removeTimeObserverFromPlayer
{
	if (_timeObserverToken) {
		[self.topLeftView.player removeTimeObserver:_timeObserverToken];
		_timeObserverToken = nil;
	}
}

#pragma mark - AVPlaybackViewEventHandlingDelegate

- (void)playbackViewDidTogglePlayPause:(APLPlaybackView *)playbackView
{
	if ([[self.bottomLeftView player] rate] != 1.f)
    {
		[self prerollPlayersAndStartPlayback];
	}
    else
    {
		for (APLPlaybackView *subView in _playbackViewsArray) {
			[subView.player pause];
		}
    }
}

- (void)playbackViewDidToggleActiveAudio:(APLPlaybackView *)playbackView
{
	// Mute the audio on the previously active video
	APLPlaybackView *currentView = _playbackViewsArray[_currentlyActiveViewIndex++];
	currentView.player.muted = YES;
	
	// _currentlyActiveViewIndex keeps track of the view that is currently active
	if (_currentlyActiveViewIndex > 3) { // 0 -> 1 -> 2 -> 3 -> 0
		_currentlyActiveViewIndex = 0;
	}
	
	// Unmute the audio on the currently active video
	currentView = _playbackViewsArray[_currentlyActiveViewIndex];
	currentView.player.muted = NO;
}


- (void)playbackViewWillBeginPlaying:(APLPlaybackView *)playbackView
{
	// Audio is active only for the top-left view by default
	_currentlyActiveViewIndex = 1;
	[self playbackViewDidToggleActiveAudio:playbackView];
}

- (void)playbackViewDidMouseDown:(APLPlaybackView *)playbackView
{
	// Unmute the audio on the view on which mouseDown event occurred
	APLPlaybackView *currentlyActiveView = [_playbackViewsArray objectAtIndex:_currentlyActiveViewIndex];
	[currentlyActiveView.player setMuted:YES];
	
	_currentlyActiveViewIndex = [_playbackViewsArray indexOfObject:playbackView];
	[playbackView.player setMuted:NO];
}

#pragma mark - Scrubbing Utilities

- (void)beginScrubbing:(NSNotification *)notification
{
	_playRateToRestore = self.topLeftView.player.rate;
	
	[self removeTimeObserverFromPlayer];
	
	for (APLPlaybackView *subView in _playbackViewsArray) {
		subView.player.rate = 0.0;
	}
}


- (void)endScrubbing:(NSNotification *)notification
{
	if (_playRateToRestore != 0.0) {
		[self prerollPlayersAndStartPlayback];
	}
	
	[self addTimeObserverToPlayer];
}


- (void)syncScrubber
{
	double time = CMTimeGetSeconds(self.topLeftView.player.currentTime);
	
	self.timeSlider.doubleValue = time;
}


+ (NSSet *)keyPathsForValuesAffectingDuration
{
	return [NSSet setWithObjects:@"topLeftView.player.currentItem", @"topLeftView.player.currentItem.status", nil];
}


- (double)duration
{
	AVPlayerItem *playerItem = self.topLeftView.player.currentItem;
	
	if (playerItem.status == AVPlayerItemStatusReadyToPlay)
		return CMTimeGetSeconds(playerItem.asset.duration);
	else
		return 0.f;
}


- (double)currentTime
{
	return CMTimeGetSeconds(self.topLeftView.player.currentTime);
}


- (void)setCurrentTime:(double)time
{
	for (APLPlaybackView *subView in _playbackViewsArray) {
		[subView.player seekToTime:CMTimeMakeWithSeconds(time, 1) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
	}
}


@end

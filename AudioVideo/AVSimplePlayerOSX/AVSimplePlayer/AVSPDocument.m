/*
     File: AVSPDocument.m
 Abstract: The players document class. It sets up the AVPlayer, AVPlayerLayer, manages adjusting the playback rate, enables and disables UI elements as appropriate, sets up a time observer for updating the current time (which the UI's time slider is bound to), and handles adjusting the volume of the AVPlayer.
  Version: 1.1
 
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

#import "AVSPDocument.h"
#import <AVFoundation/AVFoundation.h>

static void *AVSPPlayerItemStatusContext = &AVSPPlayerItemStatusContext;
static void *AVSPPlayerRateContext = &AVSPPlayerRateContext;
static void *AVSPPlayerLayerReadyForDisplay = &AVSPPlayerLayerReadyForDisplay;

@interface AVSPDocument ()

@property (strong) AVPlayer *player;
@property (strong) AVPlayerLayer *playerLayer;
@property (assign) double currentTime;
@property (readonly) double duration;
@property (assign) float volume;

@property (weak) IBOutlet NSProgressIndicator *loadingSpinner;
@property (weak) IBOutlet NSTextField *unplayableLabel;
@property (weak) IBOutlet NSTextField *noVideoLabel;
@property (weak) IBOutlet NSView *playerView;
@property (weak) IBOutlet NSButton *playPauseButton;
@property (weak) IBOutlet NSButton *fastForwardButton;
@property (weak) IBOutlet NSButton *rewindButton;
@property (weak) IBOutlet NSSlider *timeSlider;

@property (strong) id timeObserverToken;

@end

@implementation AVSPDocument

- (NSString *)windowNibName
{
	return @"AVSPDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)windowController
{
	[super windowControllerDidLoadNib:windowController];
	windowController.window.movableByWindowBackground = YES;
	self.playerView.layer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
	[self.loadingSpinner startAnimation:self];
	
	// Create the AVPlayer, add rate and status observers
	self.player = [[AVPlayer alloc] init];
	[self addObserver:self forKeyPath:@"player.rate" options:NSKeyValueObservingOptionNew context:AVSPPlayerRateContext];
	[self addObserver:self forKeyPath:@"player.currentItem.status" options:NSKeyValueObservingOptionNew context:AVSPPlayerItemStatusContext];
	
	// Create an asset with our URL, asychronously load its tracks and whether it's playable or protected.
	// When that loading is complete, configure a player to play the asset.
	AVURLAsset *asset = [AVAsset assetWithURL:[self fileURL]];
	NSArray *assetKeysToLoadAndTest = @[@"playable", @"hasProtectedContent", @"tracks"];
	[asset loadValuesAsynchronouslyForKeys:assetKeysToLoadAndTest completionHandler:^(void) {
		
		// The asset invokes its completion handler on an arbitrary queue when loading is complete.
		// Because we want to access our AVPlayer in our ensuing set-up, we must dispatch our handler to the main queue.
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			
			[self setUpPlaybackOfAsset:asset withKeys:assetKeysToLoadAndTest];
			
		});
		
	}];
}

- (void)setUpPlaybackOfAsset:(AVAsset *)asset withKeys:(NSArray *)keys
{
	// This method is called when the AVAsset for our URL has completing the loading of the values of the specified array of keys.
	// We set up playback of the asset here.
	
	// First test whether the values of each of the keys we need have been successfully loaded.
	for (NSString *key in keys)
	{
		NSError *error = nil;
		
		if ([asset statusOfValueForKey:key error:&error] == AVKeyValueStatusFailed)
		{
			[self stopLoadingAnimationAndHandleError:error];
			return;
		}
	}
	
	if (![asset isPlayable] || [asset hasProtectedContent])
	{
		// We can't play this asset. Show the "Unplayable Asset" label.
		[self stopLoadingAnimationAndHandleError:nil];
		self.unplayableLabel.hidden = NO;
		return;
	}
	
	// We can play this asset.
	// Set up an AVPlayerLayer according to whether the asset contains video.
	if ([[asset tracksWithMediaType:AVMediaTypeVideo] count] != 0)
	{
		// Create an AVPlayerLayer and add it to the player view if there is video, but hide it until it's ready for display
		AVPlayerLayer *newPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
		newPlayerLayer.frame = self.playerView.layer.bounds;
		newPlayerLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
		newPlayerLayer.hidden = YES;
		[self.playerView.layer addSublayer:newPlayerLayer];
		self.playerLayer = newPlayerLayer;
		[self addObserver:self forKeyPath:@"playerLayer.readyForDisplay" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:AVSPPlayerLayerReadyForDisplay];
	}
	else
	{
		// This asset has no video tracks. Show the "No Video" label.
		[self stopLoadingAnimationAndHandleError:nil];
		self.noVideoLabel.hidden = NO;
	}
	
	// Create a new AVPlayerItem and make it our player's current item.
	AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
	
	// If needed, configure player item here (example: adding outputs, setting text style rules, selecting media options) before associating it with a player
	[self.player replaceCurrentItemWithPlayerItem:playerItem];
	
	// Use a weak self variable to avoid a retain cycle in the block
	__weak AVSPDocument *weakSelf = self;
	[self setTimeObserverToken:[[self player] addPeriodicTimeObserverForInterval:CMTimeMake(1, 10) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
		weakSelf.timeSlider.doubleValue = CMTimeGetSeconds(time);
	}]];
	
}

- (void)stopLoadingAnimationAndHandleError:(NSError *)error
{
	[self.loadingSpinner stopAnimation:self];
	self.loadingSpinner.hidden = YES;
	if (error)
	{
		[self presentError:error
			modalForWindow:[self windowForSheet]
				  delegate:nil
		didPresentSelector:NULL
			   contextInfo:nil];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context == AVSPPlayerItemStatusContext)
	{
		AVPlayerStatus status = [change[NSKeyValueChangeNewKey] integerValue];
		BOOL enable = NO;
		switch (status)
		{
			case AVPlayerItemStatusUnknown:
				break;
			case AVPlayerItemStatusReadyToPlay:
				enable = YES;
				break;
			case AVPlayerItemStatusFailed:
				[self stopLoadingAnimationAndHandleError:[[[self player] currentItem] error]];
				break;
		}
		
		self.playPauseButton.enabled = enable;
		self.fastForwardButton.enabled = enable;
		self.rewindButton.enabled = enable;
	}
	else if (context == AVSPPlayerRateContext)
	{
		float rate = [change[NSKeyValueChangeNewKey] floatValue];
		if (rate != 1.f)
		{
			self.playPauseButton.title = @"Play";
		}
		else
		{
			self.playPauseButton.title = @"Pause";
		}
	}
	else if (context == AVSPPlayerLayerReadyForDisplay)
	{
		if ([change[NSKeyValueChangeNewKey] boolValue] == YES)
		{
			// The AVPlayerLayer is ready for display. Hide the loading spinner and show it.
			[self stopLoadingAnimationAndHandleError:nil];
			self.playerLayer.hidden = NO;
		}
	}
	else
	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)close
{
	[self.player pause];
	[self.player removeTimeObserver:[self timeObserverToken]];
	self.timeObserverToken = nil;
	[self removeObserver:self forKeyPath:@"player.rate"];
	[self removeObserver:self forKeyPath:@"player.currentItem.status"];
	if (self.playerLayer)
		[self removeObserver:self forKeyPath:@"playerLayer.readyForDisplay"];
	[super close];
}

+ (NSSet *)keyPathsForValuesAffectingDuration
{
	return [NSSet setWithObjects:@"player.currentItem", @"player.currentItem.status", nil];
}

- (double)duration
{
	AVPlayerItem *playerItem = self.player.currentItem;
	
	if (playerItem.status == AVPlayerItemStatusReadyToPlay)
		return CMTimeGetSeconds(playerItem.asset.duration);
	else
		return 0.f;
}

- (double)currentTime
{
	return CMTimeGetSeconds(self.player.currentTime);
}

- (void)setCurrentTime:(double)time
{
	[self.player seekToTime:CMTimeMakeWithSeconds(time, 1) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

+ (NSSet *)keyPathsForValuesAffectingVolume
{
	return [NSSet setWithObject:@"player.volume"];
}

- (float)volume
{
	return self.player.volume;
}

- (void)setVolume:(float)volume
{
	self.player.volume = volume;
}

- (IBAction)playPauseToggle:(id)sender
{
	if (self.player.rate != 1.f)
	{
		if (self.currentTime == [self duration])
			[self setCurrentTime:0.f];
		[self.player play];
	}
	else
	{
		[self.player pause];
	}
}

- (IBAction)fastForward:(id)sender
{
	if (self.player.rate < 2.f)
	{
		self.player.rate = 2.f;
	}
	else
	{
		self.player.rate = self.player.rate + 2.f;
	}
}

- (IBAction)rewind:(id)sender
{
	if (self.player.rate > -2.f)
	{
		self.player.rate = -2.f;
	}
	else
	{
		self.player.rate = self.player.rate - 2.f;
	}
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
	if (outError != NULL)
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:NULL];
	return nil;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
	if (outError != NULL)
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:NULL];
	return YES;
}

@end

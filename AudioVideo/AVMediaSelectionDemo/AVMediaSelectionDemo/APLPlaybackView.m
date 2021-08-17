/*
     File: APLPlaybackView.m
 Abstract: The player view class. It sets up AVPlayer and AVPlayerLayer. It defines a protocol for its delegate to receive all user interactions like keyboard hits (spacebar to play/pause and tab to toggle active audio selection) and mouse down events (to display a pop-up menu with list of available media selection options).
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

#import "APLPlaybackView.h"
#import <CoreMedia/CMAudioDeviceClock.h>

static void *AVMSPlayerItemTracksContext = &AVMSPlayerItemTracksContext;

@interface APLPlaybackView ()
{
	int					audibleIndex;
	int					legibleIndex;
	NSMutableArray		*audioOptions;
	NSMutableArray		*legibleOptions;
	id					_notificationToken;
	BOOL				_playbackDidBegin;
	NSInteger			_currentlySelectedAudioItem;
	NSInteger			_currentlySelectedLegibleItem;
}

@property NSMenu		*optionsMenu;
@property AVAsset		*asset;

@end


@implementation APLPlaybackView

- (id)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	
	if (self) {
		CALayer *layer = [CALayer layer];
		self.layer = layer;
		self.wantsLayer = YES;
		self.layer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
		
		// Create the AVPlayer, add rate and status observers
		self.player = [[AVPlayer alloc] init];
		self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
		
		[self addObserver:self forKeyPath:@"player.currentItem.tracks" options:NSKeyValueObservingOptionNew context:AVMSPlayerItemTracksContext];
		
		audioOptions = [NSMutableArray array];
		legibleOptions = [NSMutableArray array];
		
		// Add the default audio device clock as the players clock
		[self setMasterClockOnPlayerToDefaultAudioDeviceClock];
		
		_playbackDidBegin = NO;
	}
	
	return self;
}

- (void)setMasterClockOnPlayerToDefaultAudioDeviceClock
{
	CMClockRef audioDeviceClock = NULL;
	AudioDeviceID defaultAudioDevice = kAudioObjectUnknown;
	UInt32 size = 0;
	OSStatus audioErr;
	AudioObjectPropertyAddress propAddress = {
												kAudioHardwarePropertyDefaultOutputDevice,
												kAudioObjectPropertyScopeGlobal,
												kAudioObjectPropertyElementMaster };
	
	size = sizeof( defaultAudioDevice );
	audioErr = AudioObjectGetPropertyData(
										  kAudioObjectSystemObject,		//AudioObjectID						inObjectID,
										  &propAddress,					//const AudioObjectPropertyAddress*	inAddress,
										  0,							//UInt32							inQualifierDataSize,
										  NULL,							//const void*						inQualifierData,
										  &size,						//UInt32*							ioDataSize,
										  (void *)&defaultAudioDevice);	//void*								outData)
	
	if (defaultAudioDevice != kAudioObjectUnknown) {
		CMAudioDeviceClockCreateFromAudioDeviceID(kCFAllocatorDefault, defaultAudioDevice, &audioDeviceClock);
	}
	
	self.player.masterClock = audioDeviceClock;
	
	if (audioDeviceClock) {
		CFRelease(audioDeviceClock);
	}
}

- (void)addDidPlayToEndTimeNotificationForPlayerItem:(AVPlayerItem *)item
{
    if (_notificationToken)
        _notificationToken = nil;
    
    /*
     Setting actionAtItemEnd to None prevents the movie from getting paused at item end. A very simplistic, and not gapless, looped playback.
     */
    _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    _notificationToken = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:item queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        // Simple item playback rewind.
        [_player.currentItem seekToTime:kCMTimeZero];
    }];
}

- (void)setupPlaybackUsingURL:(NSURL *)url
{
	// Create an asset with our URL, asychronously load its tracks, its duration, and whether it's playable or protected.
	// When that loading is complete, configure a player to play the asset.
	AVURLAsset *asset = [AVAsset assetWithURL:url];
	self.asset = asset;
	
	NSArray *assetKeysToLoadAndTest = @[@"playable", @"hasProtectedContent", @"duration", @"availableMediaCharacteristicsWithMediaSelectionOptions"];
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
	// This method is called when the AVAsset for our URL has completed the loading of the values of the specified array of keys.
	// We set up playback of the asset here.
	
	// First test whether the values of each of the keys we need have been successfully loaded.
	for (NSString *key in keys) {
		NSError *error;
		
		if ([asset statusOfValueForKey:key error:&error] == AVKeyValueStatusFailed) {
			NSLog(@"Key value loading failed for key: %@ with error: %@", key, error);
			return;
		}
	}
	
	if (!asset.playable || asset.hasProtectedContent) {
		NSLog(@"Asset is not playable");
		return;
	}
	
	// We can play this asset. Create a new AVPlayerItem and make it our player's current item.
	AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
	[self.player replaceCurrentItemWithPlayerItem:playerItem];
	[self addDidPlayToEndTimeNotificationForPlayerItem:playerItem];
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context == AVMSPlayerItemTracksContext) {
		BOOL foundVideoTrack = NO;
		
		for (AVPlayerItemTrack *playerItemTrack in self.player.currentItem.tracks) {
			if ([playerItemTrack.assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) {
				foundVideoTrack = YES;
				break;
			}
		}
		
		if (self.playerLayer == nil && foundVideoTrack) {
			self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
			self.playerLayer.frame = self.layer.bounds;
			self.playerLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
			[self.layer addSublayer:self.playerLayer];
			
			self.playerLayer.hidden = NO;
			
			if (!_playbackDidBegin) {
				self.player.muted = YES;
				
				[self.delegate playbackViewWillBeginPlaying:self];
				_playbackDidBegin = YES;
			}
		}
	}
	else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)viewWillMoveToSuperview:(NSView *)newSuperview
{
	if (!newSuperview) {
		[self.player pause];
		[self removeObserver:self forKeyPath:@"player.currentItem.tracks"];
		
		self.player = nil;
		self.delegate = nil;
		self.playerLayer = nil;
		self.asset = nil;
		self.optionsMenu = nil;
	}
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
}

- (void)respondToMediaOptionSelection:(NSMenuItem *)selectedItem
{	
	NSInteger selectedItemIndex = [self.optionsMenu indexOfItem:selectedItem];
	if ( selectedItemIndex < legibleIndex) {
		// Audio option selected
		[self.player.currentItem selectMediaOption:audioOptions[(selectedItemIndex - audibleIndex - 1)] inMediaSelectionGroup:[self.asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible]];
		_currentlySelectedAudioItem = selectedItemIndex;
	} else {
		// Legible option selected
		[self.player.currentItem selectMediaOption:legibleOptions[(selectedItemIndex - legibleIndex - 1)] inMediaSelectionGroup:[self.asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicLegible]];
		_currentlySelectedLegibleItem = selectedItemIndex;
	}
	
	// Update the menu item selection
	for (NSMenuItem *item in [self.optionsMenu itemArray]) {
		NSInteger index = [self.optionsMenu indexOfItem:item];
		if (index == _currentlySelectedAudioItem || index == _currentlySelectedLegibleItem) {
			item.state = NSOnState;
		} else {
			item.state = NSOffState;
		}
	}
}

- (void)listMediaSelectionOptionsForCurrentItemWithEvent:(NSEvent *)theEvent
{
	if (!self.optionsMenu) {
		int index = 0;
		
		// Audible Options
		AVMediaSelectionGroup *audibleGroup = [self.asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible];
		
		self.optionsMenu = [[NSMenu alloc] initWithTitle:@"Contextual Menu"];
    	
		if ([[audibleGroup options] count] > 0) {
			
			NSArray *filteredAudioOptions = [AVMediaSelectionGroup mediaSelectionOptionsFromArray:[audibleGroup options] withMediaCharacteristics:@[AVMediaCharacteristicIsMainProgramContent]];
			audibleIndex = index;
			[self.optionsMenu insertItemWithTitle:@"Audio" action:nil keyEquivalent:@"" atIndex:index++];
			
			for (AVMediaSelectionOption *thisOption in filteredAudioOptions) {
				[self.optionsMenu insertItemWithTitle:[thisOption displayName] action:@selector(respondToMediaOptionSelection:) keyEquivalent:@"" atIndex:index++];
				[audioOptions addObject:thisOption];
			}
		}
		
		// Legible Options
		AVMediaSelectionGroup *legibleGroup = [self.asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicLegible];
		
		if ([[legibleGroup options] count] > 0) {
			
			NSArray *filteredSubtitleOptions = [AVMediaSelectionGroup mediaSelectionOptionsFromArray:[legibleGroup options] withoutMediaCharacteristics:@[AVMediaCharacteristicContainsOnlyForcedSubtitles, AVMediaCharacteristicIsAuxiliaryContent]];
			
			[self.optionsMenu insertItem:[NSMenuItem separatorItem] atIndex:index++];
			legibleIndex = index;
			[self.optionsMenu insertItemWithTitle:@"Subtitles" action:nil keyEquivalent:@"" atIndex:index++];
			
			for (AVMediaSelectionOption *thisOption in filteredSubtitleOptions) {
				[self.optionsMenu insertItemWithTitle:[thisOption displayName] action:@selector(respondToMediaOptionSelection:) keyEquivalent:@"" atIndex:index++];
				
				[legibleOptions addObject:thisOption];
			}
		}
	}
			
	[NSMenu popUpContextMenu:self.optionsMenu withEvent:theEvent forView:self];
}

- (void)mouseDown:(NSEvent *)theEvent
{	
	[self listMediaSelectionOptionsForCurrentItemWithEvent:theEvent];
	
	// Inform the delegate that the current view's audio has to be active
	[self.delegate playbackViewDidMouseDown:self];
	
	[super mouseDown:theEvent];
}

- (void)keyDown:(NSEvent *)theEvent
{
	if ([theEvent.characters isEqualToString:@" "]) { // Space bar is used to toggle play pause
		[self.delegate playbackViewDidTogglePlayPause:self];
	} else if ([theEvent.characters isEqualToString:@"	"]) { // Tab is used to switch between active view for audio
		[self.delegate playbackViewDidToggleActiveAudio:self];
	}
	
	[super keyDown:theEvent];
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (void)drawFocusRingMask
{
    NSRectFill([self bounds]);
}

- (NSRect)focusRingMaskBounds
{
    return [self bounds];
}

@end

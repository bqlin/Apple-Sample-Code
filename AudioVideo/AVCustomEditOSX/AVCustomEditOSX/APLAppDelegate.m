/*
     File: APLAppDelegate.m
 Abstract:  The app delegate which handles setup, playback and export of AVMutableComposition along with other user interactions like scrubbing, toggling play/pause, selecting transition type. 
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
 
 Copyright (C) 2013 Apple Inc. All Rights Reserved.
 
 */

#import "APLAppDelegate.h"
#import "APLSimpleEditor.h"
#import <AVFoundation/AVFoundation.h>

#define kDiagonalWipeTransition 0
#define kCrossDissolveTransition 1

@interface APLAppDelegate ()
{	
	float		_transitionDuration;
	NSInteger	_transitionType;
}

@property APLSimpleEditor *editor;
@property NSMutableArray *clips;
@property NSMutableArray *clipTimeRanges;

@property AVPlayer *player;
@property AVPlayerItem *playerItem;

@end

@implementation APLAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	_editor = [[APLSimpleEditor alloc] init];
	_clips = [[NSMutableArray alloc] initWithCapacity:2];
	_clipTimeRanges = [[NSMutableArray alloc] initWithCapacity:2];
	
	// Default cross fade duration is set to 2.0 seconds
	_transitionDuration = 2.0;
	_transitionType = kDiagonalWipeTransition; // Default transition type is set Diagonal Wipe
	
	// Add clips to pass to the editor
	[self addClipsToEditor];
	
	// Initialize an AVPlayer and set it as the player on the AVPlayerView
	if (!self.player) {
		self.player = [[AVPlayer alloc] init];
		self.playerView.player = self.player;
	}
	
	// Synchronize the player with editor
	[self synchronizePlayerWithEditor];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:self.window];
	
	NSMenu *transitionMenu = [[NSMenu alloc] initWithTitle:@"Transitions Menu"];
	[transitionMenu insertItemWithTitle:@"Diagonal Wipe" action:@selector(respondToTransitionSelection:) keyEquivalent:@"" atIndex:kDiagonalWipeTransition];
	[transitionMenu insertItemWithTitle:@"Cross Dissolve" action:@selector(respondToTransitionSelection:) keyEquivalent:@"" atIndex:kCrossDissolveTransition];
	[(NSMenuItem *)transitionMenu.itemArray[kDiagonalWipeTransition] setState:NSOnState];
	self.playerView.actionPopUpButtonMenu = transitionMenu;
	
}

- (void)addClipsToEditor
{
	// The two assets in the projects bundle are used
	AVURLAsset *asset1 = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"sample_clip1" ofType:@"m4v"]]];
	AVURLAsset *asset2 = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"sample_clip2" ofType:@"mov"]]];
	
	// Set the timeRanges to 5 seconds each. Note: that we set our default transitionDuration to 2.0 seconds.
	[self.clips addObject:asset1];
	[self.clipTimeRanges addObject:[NSValue valueWithCMTimeRange:CMTimeRangeMake(CMTimeMakeWithSeconds(0, 1), CMTimeMakeWithSeconds(5, 1))]];
	
	[self.clips addObject:asset2];
	[self.clipTimeRanges addObject:[NSValue valueWithCMTimeRange:CMTimeRangeMake(CMTimeMakeWithSeconds(0, 1), CMTimeMakeWithSeconds(5, 1))]];
	
	// Synchronize these clips with the editor object.
	[self synchronizeWithEditor];
}

- (void)synchronizePlayerWithEditor
{
	AVPlayerItem *playerItem = nil;
	
	if ( self.player == nil )
		return;
	
	playerItem = [self.editor getPlayerItem];
	
	// Replace the currentItem with our playerItem on the player
	if (self.playerItem != playerItem) {
		self.playerItem = playerItem;
		[self.player replaceCurrentItemWithPlayerItem:playerItem];
	}
}

- (void)synchronizeWithEditor
{
	// Clips
	[self synchronizeEditorClipsWithOurClips];
	[self synchronizeEditorClipTimeRangesWithOurClipTimeRanges];
	
	// Transition
	self.editor.transitionDuration = CMTimeMakeWithSeconds(_transitionDuration, 600);
	self.editor.transitionType = _transitionType;
	
	[self.editor buildCompositionObjectsForPlayback];
	[self synchronizePlayerWithEditor];
}

- (void)synchronizeEditorClipsWithOurClips
{
	NSMutableArray *validClips = [NSMutableArray arrayWithCapacity:3];
	for (AVURLAsset *asset in self.clips) {
		if (![asset isKindOfClass:[NSNull class]]) {
			[validClips addObject:asset];
		}
	}
	
	self.editor.clips = validClips;
}

- (void)synchronizeEditorClipTimeRangesWithOurClipTimeRanges
{
	NSMutableArray *validClipTimeRanges = [NSMutableArray arrayWithCapacity:3];
	for (NSValue *timeRange in self.clipTimeRanges) {
		if (! [timeRange isKindOfClass:[NSNull class]]) {
			[validClipTimeRanges addObject:timeRange];
		}
	}
	
	self.editor.clipTimeRanges = validClipTimeRanges;
}

- (void)windowWillClose:(NSNotification*)notification
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:self.window];
	self.window = nil;
	self.player = nil;
	self.editor = nil;
	self.playerView = nil;
}

- (void)respondToTransitionSelection:(NSMenuItem *)item
{
	for (NSMenuItem *menuItem in [self.playerView.actionPopUpButtonMenu itemArray]) {
		if (menuItem == item) {
			menuItem.state = NSOnState;
		} else {
			menuItem.state = NSOffState;
		}
	}
	
	// Index 0 is Diagonal Wipe
	// Index 1 is Cross Dissolve
	_transitionType = [self.playerView.actionPopUpButtonMenu indexOfItem:item];
	
	[self synchronizeWithEditor];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
    return YES;
}

@end

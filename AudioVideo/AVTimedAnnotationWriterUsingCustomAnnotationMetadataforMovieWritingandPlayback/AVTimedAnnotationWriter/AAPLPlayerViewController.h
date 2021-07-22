/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 
  Player view controller which sets up playback of movie file with metadata and uses AVPlayerItemMetadataOutput to render circle and text annotation during playback.
  
 */

@import UIKit;
@import AVKit;

/// 实现的是 AVPlayerViewController 的子类，用于根据在元数据中的信息生成 layer 和 label
@interface AAPLPlayerViewController : AVPlayerViewController

- (void)setupPlaybackWithURL:(NSURL *)movieURL;

@end

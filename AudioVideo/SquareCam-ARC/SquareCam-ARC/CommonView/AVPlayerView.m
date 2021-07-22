//
//  AVPlayerView.m
//  AVReaderWriter
//
//  Created by bqlin on 2018/8/22.
//  Copyright © 2018年 Bq. All rights reserved.
//

#import "AVPlayerView.h"
#import <AVFoundation/AVFoundation.h>

@implementation AVPlayerView

+ (Class)layerClass {
    return [AVPlayerLayer class];
}

- (AVPlayer *)player {
    return [(AVPlayerLayer *)self.layer player];
}

- (void)setPlayer:(AVPlayer *)player {
    [(AVPlayerLayer *)self.layer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    [(AVPlayerLayer *)self.layer setPlayer:player];
}

@end

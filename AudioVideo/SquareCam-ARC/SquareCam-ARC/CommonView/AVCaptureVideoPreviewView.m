//
//  AVCaptureVideoPreviewView.m
//  SquareCam-ARC
//
//  Created by bqlin on 2018/8/31.
//  Copyright © 2018年 Bq. All rights reserved.
//

#import "AVCaptureVideoPreviewView.h"

@implementation AVCaptureVideoPreviewView

+ (Class)layerClass {
    return [AVCaptureVideoPreviewLayer class];
}

- (AVCaptureVideoPreviewLayer *)videoPreviewLayer {
    return (AVCaptureVideoPreviewLayer *)self.layer;
}

- (AVCaptureSession *)session {
    return self.videoPreviewLayer.session;
}
- (void)setSession:(AVCaptureSession *)session {
    self.videoPreviewLayer.session = session;
}

@end

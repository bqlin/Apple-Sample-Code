//
//  AVCaptureVideoPreviewView.h
//  SquareCam-ARC
//
//  Created by bqlin on 2018/8/31.
//  Copyright © 2018年 Bq. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface AVCaptureVideoPreviewView : UIView

@property (nonatomic, strong, readonly) AVCaptureVideoPreviewLayer *videoPreviewLayer;
@property (nonatomic, strong) AVCaptureSession *session;

@end

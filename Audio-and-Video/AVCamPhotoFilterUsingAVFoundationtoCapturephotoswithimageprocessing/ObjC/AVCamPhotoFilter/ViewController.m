//
//  ViewController.m
//  AVCamPhotoFilter
//
//  Created by bqlin on 2018/9/3.
//  Copyright © 2018年 Bq. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Photos/Photos.h>
#import <MobileCoreServices/MobileCoreServices.h>

@interface ViewController () <AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate, AVCaptureDataOutputSynchronizerDelegate>

@property (nonatomic, weak) IBOutlet UIButton *cameraButton;
@property (nonatomic, weak) IBOutlet UIButton *photoButton;
@property (nonatomic, weak) IBOutlet UIButton *resumeButton;
@property (nonatomic, weak) IBOutlet UILabel *cameraUnavailableLabel;
@property (nonatomic, weak) IBOutlet UILabel *filterLabel;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end

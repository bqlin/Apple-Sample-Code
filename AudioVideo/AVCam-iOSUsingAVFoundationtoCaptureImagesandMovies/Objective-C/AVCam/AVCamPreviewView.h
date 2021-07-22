/*
See LICENSE.txt for this sample’s licensing information.

Abstract:
Application preview view.
*/

@import UIKit;

@class AVCaptureSession;

/**
 layer 为 AVCaptureVideoPreviewLayer，预览捕获的视频
 */
@interface AVCamPreviewView : UIView

/// 自身的 layer
@property (nonatomic, readonly) AVCaptureVideoPreviewLayer *videoPreviewLayer;

/// 访问和设置 AVCaptureVideoPreviewLayer 的 session 属性
@property (nonatomic) AVCaptureSession *session;

@end

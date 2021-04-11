//
//  ViewController.m
//  SquareCam-ARC
//
//  Created by bqlin on 2018/8/31.
//  Copyright © 2018年 Bq. All rights reserved.
//

#import "ViewController.h"
#import "AVCaptureVideoPreviewView.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <AssetsLibrary/AssetsLibrary.h>

static const NSString *AVCaptureStillImageIsCapturingStillImageContext = @"AVCaptureStillImageIsCapturingStillImageContext";

static NSString * const kFaceLayerName = @"FaceLayer";

/// 弧度转角度
static CGFloat DegreesToRadians(CGFloat degrees) {return degrees * M_PI / 180;};

/// 作为 CGDataProviderRef 的回调，解锁并释放 CVPixelBufferRef
static void ReleaseCVPixelBuffer(void *pixel, const void *data, size_t size)
{
    CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)pixel;
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    CVPixelBufferRelease(pixelBuffer);
}

// create a CGImage with provided pixel buffer, pixel buffer must be uncompressed kCVPixelFormatType_32ARGB or kCVPixelFormatType_32BGRA
/// 使用提供的 pixel buffer 创建 CGImage，pixel buffer 必须是未压缩的 kCVPixelFormatType_32ARGB 或 kCVPixelFormatType_32BGRA
static OSStatus CreateCGImageFromCVPixelBuffer(CVPixelBufferRef pixelBuffer, CGImageRef *imageOut)
{
    OSStatus err = noErr;
    CGBitmapInfo bitmapInfo;
    //OSType sourcePixelFormat;
    //size_t width, height, sourceRowBytes;
    //void *sourceBaseAddr = NULL;
    //CGColorSpaceRef colorspace = NULL;
    //CGDataProviderRef provider = NULL;
    //CGImageRef image = NULL;
    
    // bitmapInfo
    OSType sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    if (kCVPixelFormatType_32ARGB == sourcePixelFormat)
        bitmapInfo = kCGBitmapByteOrder32Big | kCGImageAlphaNoneSkipFirst;
    else if (kCVPixelFormatType_32BGRA == sourcePixelFormat) // 小端模式
        bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst;
    else
        return -95014; // only uncompressed pixel formats
    
    // 图像大小
    size_t sourceRowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
    
    // 在此给 pixel buffer 加锁，取地址，建 CGDataProviderRef，获得 CGImageRef；而在其 provider 销毁回调中解锁并释放 pixelBuffer。
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *sourceBaseAddr = CVPixelBufferGetBaseAddress(pixelBuffer);
    CVPixelBufferRetain(pixelBuffer); // 对 pixelBuffer 增加引用计数
    CGDataProviderRef provider = CGDataProviderCreateWithData((void *)pixelBuffer, sourceBaseAddr, sourceRowBytes * height, ReleaseCVPixelBuffer); // 数据提供者，数据来源
    CGImageRef image = CGImageCreate(width, height, 8, 32, sourceRowBytes, colorspace, bitmapInfo, provider, NULL, true, kCGRenderingIntentDefault);
	
	// 若图片存在错误则释放图片资源
    if (err && image) {
        CGImageRelease(image);
        image = NULL;
    }
    if (provider) CGDataProviderRelease(provider);
    if (colorspace) CGColorSpaceRelease(colorspace);
//	CVPixelBufferRelease(pixelBuffer); // 是否需要对应地进行 release 呢？此处 release 后会导致保存到相册时野指针，因为已经在 dataProvider 中的回调中做了释放
    *imageOut = image;
    return err;
}

// 用于 newSquareOverlayedImageForFeatures 的工具
/// 创建位图上下文
static CGContextRef CreateCGBitmapContextForSize(CGSize size)
{
    CGContextRef    context = NULL;
    CGColorSpaceRef colorSpace;
    int             bitmapBytesPerRow;
    
    bitmapBytesPerRow = (size.width * 4);
    
    colorSpace = CGColorSpaceCreateDeviceRGB();
    context = CGBitmapContextCreate (NULL,
                                     size.width,
                                     size.height,
                                     8,      // bits per component
                                     bitmapBytesPerRow,
                                     colorSpace,
                                     kCGImageAlphaPremultipliedLast);
    CGContextSetAllowsAntialiasing(context, NO);
    CGColorSpaceRelease(colorSpace);
    return context;
}

#pragma mark-

@interface UIImage (RotationMethods)
- (UIImage *)imageRotatedByDegrees:(CGFloat)degrees;
@end

@implementation UIImage (RotationMethods)

/// 旋转并重绘图片
- (UIImage *)imageRotatedByDegrees:(CGFloat)degrees
{
    // 通过应用 transform 到一个临时 UIView，计算绘制空间的旋转视图包含框的大小
    UIView *rotatedViewBox = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.size.width, self.size.height)];
    CGAffineTransform t = CGAffineTransformMakeRotation(DegreesToRadians(degrees));
    rotatedViewBox.transform = t;
    CGSize rotatedSize = rotatedViewBox.frame.size;
    rotatedViewBox = nil;
    
    // 创建位图上下文
    UIGraphicsBeginImageContext(rotatedSize);
    CGContextRef bitmap = UIGraphicsGetCurrentContext();
    
    // 移动原点到图像中间位置，以便围绕中心旋转和缩放
    CGContextTranslateCTM(bitmap, rotatedSize.width/2, rotatedSize.height/2);
    
    // 旋转图像上下文
    CGContextRotateCTM(bitmap, DegreesToRadians(degrees));
    
    // 将旋转/缩放的图像绘制到上下文中
    CGContextScaleCTM(bitmap, 1.0, -1.0);
    CGContextDrawImage(bitmap, CGRectMake(-self.size.width / 2, -self.size.height / 2, self.size.width, self.size.height), [self CGImage]);
    
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

@end


@interface ViewController ()<UIGestureRecognizerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property (weak, nonatomic) IBOutlet AVCaptureVideoPreviewView *previewView;
@property (weak, nonatomic) IBOutlet UISegmentedControl *camerasControl;

/// 视频数据输出
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
/// 视频数据输出队列
@property (nonatomic, strong) dispatch_queue_t videoDataOutputQueue;
/// 静态图片输出
@property (nonatomic, strong) AVCaptureStillImageOutput *stillImageOutput;
@property (nonatomic, strong) UIView *flashView;
/// 方形框图片
@property (nonatomic, strong) UIImage *square;
/// 是否使用前置摄像头
@property (nonatomic, assign) BOOL isUsingFrontFacingCamera;
/// 是否开启人脸检测
@property (nonatomic, assign) BOOL detectFaces;
/// 人脸检测器
@property (nonatomic, strong) CIDetector *faceDetector;
/// 手势开始时的缩放率
@property (nonatomic, assign) CGFloat beginGestureScale;
/// 缩放率
@property (nonatomic, assign) CGFloat effectiveScale;

@end

@implementation ViewController

- (void)dealloc {
    [self teardownAVCapture];
}

/// 捕捉会话相关配置，并启动会话
- (void)setupAVCapture {
    NSError *error = nil;

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        session.sessionPreset = AVCaptureSessionPreset640x480;
    } else {
        session.sessionPreset = AVCaptureSessionPresetPhoto;
    }
    
    // 选择视频设备，添加输入到捕捉会话
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    
    _isUsingFrontFacingCamera = NO;
    if ([session canAddInput:deviceInput]) {
        [session addInput:deviceInput];
    }
    
    // 创建静态图像输出，添加到捕捉会话
    _stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    [_stillImageOutput addObserver:self forKeyPath:@"capturingStillImage" options:NSKeyValueObservingOptionNew context:(__bridge void *)(AVCaptureStillImageIsCapturingStillImageContext)];
    if ([session canAddOutput:_stillImageOutput]) {
        [session addOutput:_stillImageOutput];
    }
    
    // 创建视频数据输出，添加到捕捉会话
    _videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    // 使用 BGRA 格式，以能与 CoreGraphics 和 OpenGL 配合使用
    NSDictionary *outputSetings =
    @{
      (id)kCVPixelBufferPixelFormatTypeKey: @(kCMPixelFormat_32BGRA)
      };
    _videoDataOutput.videoSettings = outputSetings;
    _videoDataOutput.alwaysDiscardsLateVideoFrames = YES; // 如果数据输出队列阻塞（处理静态图像时）则丢弃
    
    // 创建用于 sample buffer 委托的串行调度队列。捕捉静态图像时，必须使用串行调度队列来保证视频帧按顺序传递，参阅 `-setSampleBufferDelegate:queue:`
    _videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    [_videoDataOutput setSampleBufferDelegate:self queue:_videoDataOutputQueue];
    if ([session canAddOutput:_videoDataOutput]) {
        [session addOutput:_videoDataOutput];
    }
    [_videoDataOutput connectionWithMediaType:AVMediaTypeVideo].enabled = NO;
    
    _effectiveScale = 1.0;
    _previewView.videoPreviewLayer.backgroundColor = [UIColor blackColor].CGColor;
    _previewView.videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    _previewView.session = session;
    [session startRunning];
    
    if (error) {
        NSLog(@"AVCaptureDeviceInput deviceInputWithDevice error: %@", error);
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Failed with error %@", @(error.code)] message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {}]];
        [self presentViewController:alertController animated:YES completion:nil];
        [self teardownAVCapture];
    }
}

/// 清理捕捉会话相关配置
- (void)teardownAVCapture {
    [_stillImageOutput removeObserver:self forKeyPath:@"isCapturingStillImage"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context == (__bridge void *)(AVCaptureStillImageIsCapturingStillImageContext)) {
        BOOL isCapturingStillImage = [change[NSKeyValueChangeNewKey] boolValue];
		
		// 在拍摄时进行快门闪光动画
        if (isCapturingStillImage) {
            // 快门动画
            _flashView = [[UIView alloc] initWithFrame:_previewView.frame];
            _flashView.backgroundColor = [UIColor whiteColor];
            _flashView.alpha = 0;
            [self.view.window addSubview:_flashView];
            [UIView animateWithDuration:.4 animations:^{
                [self.flashView setAlpha:1];
            }];
        } else {
            [UIView animateWithDuration:.4 animations:^{
                self.flashView.alpha = 0;
            } completion:^(BOOL finished) {
                [self.flashView removeFromSuperview];
                self.flashView = nil;
            }];
        }
    }
}

#pragma mark - util

- (AVCaptureVideoOrientation)avOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation {
    AVCaptureVideoOrientation result = (AVCaptureVideoOrientation)deviceOrientation;
    if (deviceOrientation == UIDeviceOrientationLandscapeLeft) {
        result = AVCaptureVideoOrientationLandscapeRight;
    } else if (deviceOrientation == UIDeviceOrientationLandscapeRight) {
        result = AVCaptureVideoOrientationLandscapeLeft;
    }
    return result;
}

/// 给人脸添加方向框，并返回新图像
- (CGImageRef)newSquareOverlayedImageForFeatures:(NSArray *)features inCGImage:(CGImageRef)backgroundImage withOrientation:(UIDeviceOrientation)orientation frontFacing:(BOOL)isFrontFacing {
	// 使用 CoreGraph 绘制拍摄的图片到上下文
    CGRect backgroundImageRect = CGRectMake(0, 0, CGImageGetWidth(backgroundImage), CGImageGetHeight(backgroundImage));
    CGContextRef bitmapContext = CreateCGBitmapContextForSize(backgroundImageRect.size);
    CGContextClearRect(bitmapContext, backgroundImageRect);
    CGContextDrawImage(bitmapContext, backgroundImageRect, backgroundImage);
	
	// 通过 CoreGraph 重绘修正人脸框方向
    CGFloat rotationDegress = .0;
    switch (orientation) {
        case UIDeviceOrientationPortrait:{
            rotationDegress = -90;
        } break;
        case UIDeviceOrientationPortraitUpsideDown:{
            rotationDegress = 90;
        } break;
        case UIDeviceOrientationLandscapeLeft:{
            rotationDegress = isFrontFacing ? 180 : 0;
        } break;
        case UIDeviceOrientationLandscapeRight:{
            rotationDegress = isFrontFacing ? 0 : 180;
        } break;
        case UIDeviceOrientationFaceUp:
        case UIDeviceOrientationFaceDown:
        default:{} break;
    }
    UIImage *rotatedSquareImage = [_square imageRotatedByDegrees:rotationDegress];
    
    // 检测到的人脸信息则再绘制人脸框
    for (CIFaceFeature *faceFeature in features) {
        CGRect faceRect = faceFeature.bounds;
        CGContextDrawImage(bitmapContext, faceRect, rotatedSquareImage.CGImage);
    }
    CGImageRef returnImage = CGBitmapContextCreateImage(bitmapContext);
    CGContextRelease(bitmapContext);
    
    return returnImage;
}

/// 在捕捉输出 sample buffer 时，给方形框设置合适的方向
- (void)drawFaceBoxesForFeatures:(NSArray *)features forVideoBox:(CGRect)clap orientation:(UIDeviceOrientation)orientation {
    [CATransaction begin];
    [CATransaction setValue:@(YES) forKey:kCATransactionDisableActions];
	
    AVCaptureVideoPreviewLayer *previewLayer = _previewView.videoPreviewLayer;
    
    // 隐藏所有人脸图层
    for (CALayer *layer in previewLayer.sublayers) {
        if ([kFaceLayerName isEqualToString:layer.name]) {
            layer.hidden = YES;
        }
    }
    if (features.count == 0 || !_detectFaces) {
        [CATransaction commit];
        return;
    }
    
    CGSize parentFrameSize = _previewView.frame.size;
    AVLayerVideoGravity gravity = previewLayer.videoGravity;
    BOOL isMirrored = previewLayer.connection.videoMirrored;
    CGRect previewBox = [self.class insideRectForGravity:gravity boundingSize:parentFrameSize apertureSize:clap.size];
    
    [features enumerateObjectsUsingBlock:^(CIFaceFeature *faceFeature, NSUInteger i, BOOL * _Nonnull stop) {
        // 在 previewLayer 中找到方形图层的正确位置，基于左下角原点，如果打开镜像，则在右下角
        CGRect faceRect = faceFeature.bounds;
        
        // 翻转人脸信息矩形的所有值：w、h、x、y
        CGFloat temp = faceRect.size.width;
        faceRect.size.width = faceRect.size.height;
        faceRect.size.height = temp;
        
        temp = faceRect.origin.x;
        faceRect.origin.x = faceRect.origin.y;
        faceRect.origin.y = temp;
        
        // 缩放坐标以适合预览框
        CGFloat widthScaleBy = previewBox.size.width / clap.size.height;
        CGFloat heightScaleBy = previewBox.size.height / clap.size.width;
        faceRect.size.width *= widthScaleBy;
        faceRect.size.height *= heightScaleBy;
        faceRect.origin.x *= widthScaleBy;
        faceRect.origin.y *= heightScaleBy;
		
		// 根据是否镜像调整偏移
        if (isMirrored)
            faceRect = CGRectOffset(faceRect, previewBox.origin.x + previewBox.size.width - faceRect.size.width - (faceRect.origin.x * 2), previewBox.origin.y);
        else
            faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y);
        
        CALayer *featureLayer = nil;
        NSUInteger sublayerIndex = 0;
        
        // 尝试使用现有图层
        while (!featureLayer && (sublayerIndex < previewLayer.sublayers.count)) {
            CALayer *layer = previewLayer.sublayers[sublayerIndex++];
            if ([kFaceLayerName isEqualToString:layer.name]) {
                featureLayer = layer;
                layer.hidden = NO;
            }
        }
        
        // 若无则创建新图层，设置人脸框图片
        if (!featureLayer) {
            featureLayer = [CALayer layer];
            featureLayer.contents = (id)self->_square.CGImage;
            featureLayer.name = kFaceLayerName;
            [previewLayer addSublayer:featureLayer];
        }
        featureLayer.frame = faceRect;
		
		// 根据传入的方向同步旋转人脸框图层
        switch (orientation) {
            case UIDeviceOrientationPortrait:
                [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
                break;
            case UIDeviceOrientationPortraitUpsideDown:
                [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
                break;
            case UIDeviceOrientationLandscapeLeft:
                [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
                break;
            case UIDeviceOrientationLandscapeRight:
                [featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
                break;
            case UIDeviceOrientationFaceUp:
            case UIDeviceOrientationFaceDown:
            default:
                break; // leave the layer in its last known orientation
        }
        
        [CATransaction commit];
    }];
}


/// 拍摄静止图像后，写入相册
- (BOOL)writeCGImageToCameraRoll:(CGImageRef)cgImage withMetadata:(NSDictionary *)metadata {
    CFMutableDataRef destinationData = CFDataCreateMutable(kCFAllocatorDefault, 0);
    CGImageDestinationRef destination = CGImageDestinationCreateWithData(destinationData, CFSTR("public.jpeg"), 1, NULL);
    NSAssert(destination != NULL, @"destination creeate error.");
    
    const float JPEGCompQuality = 0.85f; // JPEGHigherQuality
    CFMutableDictionaryRef optionsDict = NULL;
    CFNumberRef qualityNum = CFNumberCreate(0, kCFNumberFloatType, &JPEGCompQuality);
    if (qualityNum) {
        optionsDict = CFDictionaryCreateMutable(0, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (optionsDict) {
            CFDictionarySetValue(optionsDict, kCGImageDestinationLossyCompressionQuality, qualityNum);
        }
        CFRelease(qualityNum);
    }
    
    CGImageDestinationAddImage(destination, cgImage, optionsDict);
    BOOL success = CGImageDestinationFinalize(destination);
    
    if (optionsDict) {
        CFRelease(optionsDict);
    }
    
    CFRetain(destinationData);
    [[[ALAssetsLibrary alloc] init] writeImageDataToSavedPhotosAlbum:(__bridge id)destinationData metadata:metadata completionBlock:^(NSURL *assetURL, NSError *error) {
        if (destinationData) CFRelease(destinationData);
    }];
//    [self requestPhotoLibraryAuthorizationWithSuccessHandler:^{
//        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
//            // TODO: 保存 metadata
//            PHAssetResourceCreationOptions *options = [[PHAssetResourceCreationOptions alloc] init];
//            PHAssetCreationRequest *creationRequest = [PHAssetCreationRequest creationRequestForAsset];
//            [creationRequest addResourceWithType:PHAssetResourceTypePhoto data:(__bridge id)destinationData options:options];
//        } completionHandler:^(BOOL success, NSError * _Nullable error) {
//            if (!success) {
//                NSLog(@"Error occurred while saving photo to photo library: %@", error);
//            }
//            if (destinationData) CFRelease(destinationData);
//        }];
//    }];
    
    return success;
}

- (void)requestPhotoLibraryAuthorizationWithSuccessHandler:(void (^)(void))successHandler {
    switch ([PHPhotoLibrary authorizationStatus]) {
        case PHAuthorizationStatusAuthorized:{
            if (successHandler) successHandler();
        } break;
        case PHAuthorizationStatusDenied:
        case PHAuthorizationStatusRestricted:{
            NSString *message = NSLocalizedString(@"SquareCam doesn't have permission to use the PhotoLibrary, please change privacy settings", @"Alert message when the user has denied access to the PhotoLibrary");
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"SquareCam" message:message preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Alert OK button") style:UIAlertActionStyleCancel handler:nil];
            [alertController addAction:cancelAction];
            // Provide quick access to Settings.
            UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Settings", @"Alert button to open Settings") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
            }];
            [alertController addAction:settingsAction];
            [self presentViewController:alertController animated:YES completion:nil];
        } break;
        case PHAuthorizationStatusNotDetermined:{
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                switch (status) {
                    case PHAuthorizationStatusAuthorized:{
                        if (successHandler) successHandler();
                    } break;
                    default:{
                        NSLog(@"Could not assess PhotoLibrary authoriztion.");
                    } break;
                }
            }];
        } break;
    }
}

/// 显示错误弹窗
- (void)displayErrorOnMainQueue:(NSError *)error withMessage:(NSString *)message {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ (%@)", message, @(error.code)] message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {}]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alertController animated:YES completion:nil];
    });
}

+ (CGRect)insideRectForGravity:(AVLayerVideoGravity)gravity boundingSize:(CGSize)boundingSize apertureSize:(CGSize)apertureSize {
    CGFloat apertureRatio = apertureSize.height / apertureSize.width;
    CGFloat boundingRatio = boundingSize.width / boundingSize.height;
    
    CGSize size = CGSizeZero;
    if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
        if (boundingRatio > apertureRatio) {
            size.width = boundingSize.width;
            size.height = apertureSize.width * (boundingSize.width / apertureSize.height);
        } else {
            size.width = apertureSize.height * (boundingSize.height / apertureSize.width);
            size.height = boundingSize.height;
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
        if (boundingRatio > apertureRatio) {
            size.width = apertureSize.height * (boundingSize.height / apertureSize.width);
            size.height = boundingSize.height;
        } else {
            size.width = boundingSize.width;
            size.height = apertureSize.width * (boundingSize.width / apertureSize.height);
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResize]) {
        size.width = boundingSize.width;
        size.height = boundingSize.height;
    }
    
    CGRect insideRect = CGRectZero;
    insideRect.size = size;
    if (size.width < boundingSize.width) {
        insideRect.origin.x = (boundingSize.width - size.width) / 2;
    } else {
        insideRect.origin.x = (size.width - boundingSize.width) / 2;
    }
    if (size.height < boundingSize.height) {
        insideRect.origin.y = (boundingSize.height - size.height) / 2;
    } else {
        insideRect.origin.y = (size.height - boundingSize.height) / 2;
    }
    
    return insideRect;
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // 获取图像
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer options:(__bridge NSDictionary *)attachments];
    if (attachments) CFRelease(attachments);
    
    UIDeviceOrientation currentDeviceOrientation = [UIDevice currentDevice].orientation;
    int exifOrientation;
    // kCGImagePropertyOrientation 值
    // 图像的预期显示方向。如果存在，则此 key 是 CFNumber 值，其值与 TIFF 和 EXIF 规范定义的值相同。指定图像的原点(0, 0)所在的值，如果不存在，则假定值为 1。
    // 调用 featuresInImage: options:此键的值是 kCGImagePropertyOrientation 中的 1 到 8 的整数 NSNumber。如果存在，根据该方向进行检测，但返回的要素中的坐标仍要基于图像。
    enum {
        PHOTOS_EXIF_0ROW_TOP_0COL_LEFT            = 1, //   1  =  0th row is at the top, and 0th column is on the left (THE DEFAULT).
        PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT            = 2, //   2  =  0th row is at the top, and 0th column is on the right.
        PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3, //   3  =  0th row is at the bottom, and 0th column is on the right.
        PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4, //   4  =  0th row is at the bottom, and 0th column is on the left.
        PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5, //   5  =  0th row is on the left, and 0th column is the top.
        PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6, //   6  =  0th row is on the right, and 0th column is the top.
        PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7, //   7  =  0th row is on the right, and 0th column is the bottom.
        PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8  //   8  =  0th row is on the left, and 0th column is the bottom.
    };
    
    switch (currentDeviceOrientation) {
        case UIDeviceOrientationPortraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM;
            break;
        case UIDeviceOrientationLandscapeLeft:       // Device oriented horizontally, home button on the right
            exifOrientation = _isUsingFrontFacingCamera ? PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT : PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
            break;
        case UIDeviceOrientationLandscapeRight:      // Device oriented horizontally, home button on the left
            exifOrientation = _isUsingFrontFacingCamera ? PHOTOS_EXIF_0ROW_TOP_0COL_LEFT : PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
            break;
        case UIDeviceOrientationPortrait:            // Device oriented vertically, home button on the bottom
        default:
            exifOrientation = PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP;
            break;
    }
    NSDictionary *imageOptions = @{CIDetectorImageOrientation: @(exifOrientation)};
    NSArray *features = [_faceDetector featuresInImage:ciImage options:imageOptions];
    
    // 获取有效孔径，有效图像大小
    // 有效孔径是编码像素尺寸的一部分矩形，其表示对显示有效的图像数据
    CMFormatDescriptionRef fdesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    CGRect clap = CMVideoFormatDescriptionGetCleanAperture(fdesc, false); // originIsTopLeft == false
	//NSLog(@"calp: %@", NSStringFromCGRect(clap));
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self drawFaceBoxesForFeatures:features forVideoBox:clap orientation:currentDeviceOrientation];
    });
}

#pragma mark - view controller

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [self setupAVCapture];
    _square = [UIImage imageNamed:@"squarePNG"];
    NSDictionary *detectorOptins =
    @{
      CIDetectorAccuracy: CIDetectorAccuracyLow
      };
    _faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectorOptins];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - action

// 拍摄静止图片，如果开启人脸检测，则在捕捉的图片中添加人脸方形框
- (IBAction)takePicture:(UIBarButtonItem *)sender {
    // 获取并设置 connection 方向
    AVCaptureConnection *stillImageConnection = [_stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
    UIDeviceOrientation curDeviceOrientation = [UIDevice currentDevice].orientation;
    AVCaptureVideoOrientation avcaptureOrientation = [self avOrientationForDeviceOrientation:curDeviceOrientation];
    stillImageConnection.videoOrientation = avcaptureOrientation;
    stillImageConnection.videoScaleAndCropFactor = _effectiveScale;
    
    BOOL doingFaceDetection = _detectFaces && (_effectiveScale == 1.0);
    
    // 设置格式
    if (doingFaceDetection) {
        _stillImageOutput.outputSettings =
        @{
          (id)kCVPixelBufferPixelFormatTypeKey: @(kCMPixelFormat_32BGRA)
          };
    } else {
        _stillImageOutput.outputSettings =
        @{
          AVVideoCodecKey: AVVideoCodecJPEG
          };
    }
    
    [_stillImageOutput captureStillImageAsynchronouslyFromConnection:stillImageConnection completionHandler:^(CMSampleBufferRef  _Nullable imageDataSampleBuffer, NSError * _Nullable error) {
        if (error) {
            [self displayErrorOnMainQueue:error withMessage:@"Take picture failed"];
        } else {
            if (doingFaceDetection) {
                // 获取图像
                CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(imageDataSampleBuffer);
                CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);
                CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer options:(__bridge NSDictionary *)attachments];
                if (attachments) CFRelease(attachments);
				
				// 获取方向信息
                NSDictionary *imageOptions = nil;
                NSNumber *orientation = CMGetAttachment(imageDataSampleBuffer, kCGImagePropertyOrientation, NULL);
                if (orientation) imageOptions = @{CIDetectorImageOrientation: orientation};
                
                dispatch_sync(self->_videoDataOutputQueue, ^{
					// 获取人脸数据
                    NSArray *features = [self->_faceDetector featuresInImage:ciImage options:imageOptions];
					// 创建 CGImage
                    CGImageRef srcImage = NULL;
                    OSStatus err = CreateCGImageFromCVPixelBuffer(CMSampleBufferGetImageBuffer(imageDataSampleBuffer), &srcImage);
                    NSAssert(!err, @"CreateCGImageFromCVPixelBuffer err: %@", @(err));

                    CGImageRef cgImageResult = [self newSquareOverlayedImageForFeatures:features inCGImage:srcImage withOrientation:curDeviceOrientation frontFacing:self->_isUsingFrontFacingCamera];
                    if (srcImage) CFRelease(srcImage);
                    
                    CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);
                    [self writeCGImageToCameraRoll:cgImageResult withMetadata:(__bridge NSDictionary *)attachments];
                    if (attachments) CFRelease(attachments);
                    if (cgImageResult) CFRelease(cgImageResult);
                });
            } else { // JPEG
                NSData *jpegData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate);
                [[[ALAssetsLibrary alloc] init] writeImageDataToSavedPhotosAlbum:jpegData metadata:(__bridge NSDictionary *)attachments completionBlock:^(NSURL *assetURL, NSError *error) {
                    if (error) {
                        [self displayErrorOnMainQueue:error withMessage:@"Save to camera roll failed"];
                    }
                }];
                if (attachments) CFRelease(attachments);
            }
        }
    }];
}

- (IBAction)switchCameras:(UISegmentedControl *)sender {
    AVCaptureDevicePosition desiredPosition = _isUsingFrontFacingCamera ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
    
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if (device.position == desiredPosition) {
            [_previewView.session beginConfiguration];
            
            AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];
            for (AVCaptureInput *input in _previewView.session.inputs) {
                [_previewView.session removeInput:input];
            }
            [_previewView.session addInput:input];
            
            [_previewView.session commitConfiguration];
            break;
        }
    }
    _isUsingFrontFacingCamera = !_isUsingFrontFacingCamera;
}

- (IBAction)toggleFaceDetection:(UISwitch *)sender {
    _detectFaces = sender.on;
	
	// 启用对应的 connection
    [_videoDataOutput connectionWithMediaType:AVMediaTypeVideo].enabled = _detectFaces;
    if (!_detectFaces) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // 清除当前显示的任何方形框
			for (CALayer *layer in self.previewView.layer.sublayers) {
				if ([kFaceLayerName isEqualToString:layer.name]) {
					layer.hidden = YES;
				}
			}
        });
    }
}

- (IBAction)handlePinchGesture:(UIPinchGestureRecognizer *)sender {
    BOOL allTouchesAreOnThePreviewLayer = YES;
    for (NSUInteger i = 0; i < sender.numberOfTouches; i++) {
        CGPoint location = [sender locationOfTouch:i inView:_previewView];
        if (![_previewView.layer containsPoint:location]) {
            allTouchesAreOnThePreviewLayer = NO;
            break;
        }
    }
    // 直接对预览 layer 做缩放 transform
    if (allTouchesAreOnThePreviewLayer) {
        _effectiveScale = _beginGestureScale * sender.scale;
        if (_effectiveScale < 1) _effectiveScale = 1;
        CGFloat maxScaleAndCropFactor = [_stillImageOutput connectionWithMediaType:AVMediaTypeVideo].videoMaxScaleAndCropFactor;
        if (_effectiveScale > maxScaleAndCropFactor) _effectiveScale = maxScaleAndCropFactor;
        
        [CATransaction begin];
        [CATransaction setAnimationDuration:.025];
        _previewView.videoPreviewLayer.affineTransform = CGAffineTransformMakeScale(_effectiveScale, _effectiveScale);
        [CATransaction commit];
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]]) {
        _beginGestureScale = _effectiveScale;
    }
    return YES;
}

@end

# RosyWriter

## 采集管线

RosyWriterCapturePipeline

### 外部调用

```objective-c
// 创建
_capturePipeline = [[RosyWriterCapturePipeline alloc] initWithDelegate:self callbackQueue:dispatch_get_main_queue()];

// 启用预览
_allowedToUseGPU = ( [UIApplication sharedApplication].applicationState != UIApplicationStateBackground );
_capturePipeline.renderingEnabled = _allowedToUseGPU;

// 开始/停止采集会话
[_capturePipeline startRunning];
[_capturePipeline stopRunning];

// 开始/停止录制
[_capturePipeline startRecording];
[_capturePipeline stopRecording];

// 获取预览图层的transform
UIInterfaceOrientation currentInterfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
_previewView.transform = [_capturePipeline transformFromVideoBufferOrientationToOrientation:(AVCaptureVideoOrientation)currentInterfaceOrientation withAutoMirroring:YES]; // Front camera preview should be mirrored

// 同步设备方向
_capturePipeline.recordingOrientation = (AVCaptureVideoOrientation)deviceOrientation;

// 获取帧率、分辨率
NSString *frameRateString = [NSString stringWithFormat:@"%d FPS", (int)roundf( _capturePipeline.videoFrameRate )];
NSString *dimensionsString = [NSString stringWithFormat:@"%d x %d", _capturePipeline.videoDimensions.width, _capturePipeline.videoDimensions.height];
```

### 配置采集会话

`-setupCaptureSession`

输入：音频、视频

输出：

- 音频数据
- 视频数据
    + 设置像素格式为renderer的格式
    + `alwaysDiscardsLateVideoFrames = NO`

视频连接直接从视频输出获取。

通过帧时长的方式设置帧率：

```objective-c
frameDuration = CMTimeMake( 1, frameRate );

NSError *error = nil;
if ( [videoDevice lockForConfiguration:&error] ) {
    videoDevice.activeVideoMaxFrameDuration = frameDuration;
    videoDevice.activeVideoMinFrameDuration = frameDuration;
    [videoDevice unlockForConfiguration];
}
else {
    NSLog( @"videoDevice lockForConfiguration returned error %@", error );
}
```

从输出获取推荐的设置字典，稍后会会用来创建录制的AVAssetWriterInput。

### 数据回调

视频：

1. 从sample buffer获取格式，以输入格式设置到renderer，然后获取其输出格式。
2. 渲染sample buffer。
    1. 获取pixel buffer作为输入；
    2. 交给renderer渲染，得出输出pixel buufer；
    3. 展示pixel buffer。

音频则直接拼接sample buffer。

## 细节

### 旋转

该Demo控制器是不支持旋转的，但录制的视频是支持旋转的。

```objective-c
// 控制器不跟随旋转
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

// 同步记录设备方向
- (void)deviceOrientationDidChange
{
    UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
    
    // Update the recording orientation if the device changes to portrait or landscape orientation (but not face up/down)
    if ( UIDeviceOrientationIsPortrait( deviceOrientation ) || UIDeviceOrientationIsLandscape( deviceOrientation ) )
    {
        _capturePipeline.recordingOrientation = (AVCaptureVideoOrientation)deviceOrientation;
    }
}

// 应用到录制
CGAffineTransform videoTransform = [self transformFromVideoBufferOrientationToOrientation:self.recordingOrientation withAutoMirroring:NO]; // Front camera recording shouldn't be mirrored

[recorder addVideoTrackWithSourceFormatDescription:self.outputVideoFormatDescription transform:videoTransform settings:_videoCompressionSettings];
```

### 选择分辨率

这里使用`[NSProcessInfo processInfo].processorCount`来选择分辨率和帧率。

```objective-c
int frameRate;
NSString *sessionPreset = AVCaptureSessionPresetHigh;
CMTime frameDuration = kCMTimeInvalid;
// For single core systems like iPhone 4 and iPod Touch 4th Generation we use a lower resolution and framerate to maintain real-time performance.
if ( [NSProcessInfo processInfo].processorCount == 1 )
{
    if ( [_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480] ) {
        sessionPreset = AVCaptureSessionPreset640x480;
    }
    frameRate = 15;
}
else
{
#if ! USE_OPENGL_RENDERER
    // When using the CPU renderers or the CoreImage renderer we lower the resolution to 720p so that all devices can maintain real-time performance (this is primarily for A5 based devices like iPhone 4s and iPod Touch 5th Generation).
    if ( [_captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720] ) {
        sessionPreset = AVCaptureSessionPreset1280x720;
    }
#endif // ! USE_OPENGL_RENDERER

    frameRate = 30;
}
```

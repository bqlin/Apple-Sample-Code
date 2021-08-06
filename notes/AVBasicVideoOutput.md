# AVBasicVideoOutput

使用AVPlayerItemVideoOutput实现视频预览。所以项目中没有使用AVPlayerLayer，取而代之的是使用GL视图，得到的收益是可以控制输出的颜色。

## 视频输出

AVPlayerItemVideoOutput对象`videoOutput`在`-viewDidLoad`中已经创建，后续一直沿用：

```objective-c
// Setup AVPlayerItemVideoOutput with the required pixelbuffer attributes.
NSDictionary *pixBuffAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)};
self.videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixBuffAttributes];
_myVideoOutputQueue = dispatch_queue_create("myVideoOutputQueue", DISPATCH_QUEUE_SERIAL);
[[self videoOutput] setDelegate:self queue:_myVideoOutputQueue];
```

创建AVPlayerItem时添加视频输出：

```objective-c
[item addOutput:self.videoOutput];
[_player replaceCurrentItemWithPlayerItem:item];
[self.videoOutput requestNotificationOfMediaDataChangeWithAdvanceInterval:ONE_FRAME_DURATION];
[_player play];
```

`ONE_FRAME_DURATION`定义为0.03，大概是30FPS。

使用display link从视频输出中获取pixel buffer：

```objective-c
- (void)displayLinkCallback:(CADisplayLink *)sender
{
    /*
     The callback gets called once every Vsync.
     Using the display link's timestamp and duration we can compute the next time the screen will be refreshed, and copy the pixel buffer for that time
     This pixel buffer can then be processed and later rendered on screen.
     */
    CMTime outputItemTime = kCMTimeInvalid;
    
    // Calculate the nextVsync time which is when the screen will be refreshed next.
    CFTimeInterval nextVSync = ([sender timestamp] + [sender duration]);
    
    outputItemTime = [[self videoOutput] itemTimeForHostTime:nextVSync];
    
    if ([[self videoOutput] hasNewPixelBufferForItemTime:outputItemTime]) {
        CVPixelBufferRef pixelBuffer = NULL;
        pixelBuffer = [[self videoOutput] copyPixelBufferForItemTime:outputItemTime itemTimeForDisplay:NULL];
        
        [[self playerView] displayPixelBuffer:pixelBuffer];
        
        if (pixelBuffer != NULL) {
            CFRelease(pixelBuffer);
        }
    }
}
```

## AVPlayerItemOutputPullDelegate

在视频输出回调中开启display link。

## 细节

### 设置预览视图的旋转

从视频轨取出`preferredTransform`键：

```objective-c
CGAffineTransform preferredTransform = [videoTrack preferredTransform];

/*
 The orientation of the camera while recording affects the orientation of the images received from an AVPlayerItemVideoOutput. Here we compute a rotation that is used to correctly orientate the video.
 */
self.playerView.preferredRotation = -1 * atan2(preferredTransform.b, preferredTransform.a);
```
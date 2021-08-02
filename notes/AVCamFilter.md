# AVCamFilter

## 示例基本流程

CameraViewController的逻辑：

### 初始配置

`viewDidLoad()`

1. 配置UI初始状态。
2. 添加手势：
	1. 点击手势：对焦和测光
	2. 左滑手势、右滑手势：切换滤镜
3. 请求摄像头权限。
4. 在采集队列中配置采集会话。

配置采集会话：

1. 获取默认视频设备，创建AVCaptureDeviceInput。
2. `beginConfiguration()`
3. 设置`photo`预设。
4. 添加视频输入。
5. 添加视频数据输出。
6. 添加图片输出。启用`isHighResolutionCaptureEnabled`、`isDepthDataDeliveryEnabled`。
7. 添加深度数据输出。
8. 如果支持深度数据，则把深度数据格式中的最小帧时长设置到视频设备。
9. `commitConfiguration()`
10. 设置相关UI。

### 切换滤镜

`changeFilterSwipe(_:)`

1. 更新索引；
2. 从`filterRenderers`取出对应滤镜信息，更新UI。
3. dataOutputQueue：
	1. 若之前设置了`videoFilter`滤镜，则`reset()`；
	2. `self.videoFilter = self.filterRenderers[newIndex]`
4. processingQueue：
	1. 若之前设置了`photoFilter`滤镜，则`reset()`；
	2. `self.photoFilter = self.photoRenderers[newIndex]`

注意，这里只是简单地设置了属性而已。因为有视频数据回调，就自然在下一帧回调时就已经更新了配置。

### 处理视频帧

`captureOutput(_:didOutput:from:)`、`processVideo(sampleBuffer:)`

1. 从sample buffer获取pixel buffer、format description；
2. 就绪滤镜；
3. 滤镜处理得出新的pixel buffer；
4. 若深度开启，则混合什么pixel buffer和当前的pixel buffer；
5. 把pixel buffer传入预览视图进行预览。

### 细节

#### 请求权限挂起会话操作队列

请求权限时，会将`sessionQueue`挂起，当获得结果才进行恢复。

```swift
sessionQueue.suspend()
AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
    if !granted {
        self.setupResult = .notAuthorized
    }
    self.sessionQueue.resume()
})
```

这种方式可以延迟采集会话的配置到权限到达的时候。避免因在请求权限的过程中导致的错误。

#### 两个队列的初始化

```swift
// Communicate with the session and other session objects on this queue.
private let sessionQueue = DispatchQueue(label: "SessionQueue", attributes: [], autoreleaseFrequency: .workItem)
    
private let dataOutputQueue = DispatchQueue(label: "VideoDataQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
```

这里的两个队列都是串行队列。且指定每个任务都自动添加 autorelease pool。并且`dataOutputQueue`指定了较高的优先级。

#### 获取视频设备的方式

设定设备发现会话常量：

```swift
private let videoDeviceDiscoverySession =
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera,
                                                       .builtInWideAngleCamera],
                                         mediaType: .video,
                                         position: .unspecified)
```

初始配置时使用默认设备：

```swift
let defaultVideoDevice: AVCaptureDevice? = videoDeviceDiscoverySession.devices.first
```

而切换摄像头时，只是从设备中找到第一个符合方向的设备：

```swift
let devices = self.videoDeviceDiscoverySession.devices
let videoDevice = devices.first(where: { $0.position == preferredPosition })
```

#### 错误结果

示例用了一个`setupResult`属性表达了停止中断的原因：

```swift
private var setupResult: SessionSetupResult = .success
```

#### 处理中断与错误

注册通知：

- `AVCaptureSessionWasInterrupted`
- `AVCaptureSessionInterruptionEnded`
- `AVCaptureSessionRuntimeError`

响应通知：

`AVCaptureSessionWasInterrupted`：输出中断原因，更新相关UI。

`AVCaptureSessionInterruptionEnded`：恢复相关UI。

`AVCaptureSessionRuntimeError`：

1. 输出错误；
2. 如果错误码是`.mediaServicesWereReset`，则启动采集会话。

```swift
/*
 Automatically try to restart the session running if media services were
 reset and the last start running succeeded. Otherwise, enable the user
 to try to resume the session running.
 */
if error.code == .mediaServicesWereReset {
    sessionQueue.async {
        if self.isSessionRunning {
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
        } else {
            DispatchQueue.main.async {
                self.resumeButton.isHidden = false
            }
        }
    }
} else {
    resumeButton.isHidden = false
}
```

注意，除了上面是自动恢复采集会话的，示例其他的中断都是需要点击恢复按钮恢复采集会话的。

```swift
@IBAction private func resumeInterruptedSession(_ sender: UIButton) {
    sessionQueue.async {
        /*
         The session might fail to start running. A failure to start the session running will be communicated via
         a session runtime error notification. To avoid repeatedly failing to start the session
         running, we only try to restart the session running in the session runtime error handler
         if we aren't trying to resume the session running.
         */
        self.session.startRunning()
        self.isSessionRunning = self.session.isRunning
        if !self.session.isRunning {
            DispatchQueue.main.async {
                let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                let actions = [
                    UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                  style: .cancel,
                                  handler: nil)]
                self.alert(title: "AVCamFilter", message: message, actions: actions)
            }
        } else {
            DispatchQueue.main.async {
                self.resumeButton.isHidden = true
            }
        }
    }
}
```

#### 处理横竖屏切换

#### 为什么要分开`videoFilter`和`photoFilter`

## 滤镜处理

### FilterRenderer

FilterRenderer是一套协议，定义了可用CoreImage和Metal实现的的渲染器，方法很清晰：

```swift
// 准备资源
func prepare(with inputFormatDescription: CMFormatDescription, outputRetainedBufferCountHint: Int)

// 释放资源
func reset()

// 渲染pixel buffer
func render(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer?
```

此外当提供两个工具方法：

```swift
// 创建pixel buffer池
allocateOutputBufferPool(with:outputRetainedBufferCountHint:)

// 预分配一组pixel buffer到池
preallocateBuffers(pool:allocationThreshold:)
```

实现中，RosyCIRenderer和RosyMetalRenderer都自己管理一个输出pixel buffer池。

### RosyCIRenderer

#### 准备

`prepare(with:outputRetainedBufferCountHint:)`：对属性进行初始化

1. 输出pxiel buffer池、输出颜色空间、输出格式；
2. 输入格式
3. CoreImage上下文
4. 使用的CIFilter，并对其配置
5. 就绪标识`isPrepared`

#### 重置

`reset()`：清空所有属性

#### 渲染

`render(pixelBuffer:)`：进行CoreImage滤镜的渲染流程

1. 使用CVPixelBuffer创建CIImage作为链路的输入源。
2. CIFilter设置输入源。
3. 获取输出CIImage。
4. 从`outputPixelBufferPool`创建输出CVPixelBuffer。
5. CIContext调用render方法渲染到输出CVPixelBuffer。

### FilterRenderer

#### 构造

`init()`

1. 初始化MTLLibrary，获取内核计算着色器函数。
2. 获取计算管线并设置到`computePipelineState`。

注意这里使用的是计算着色器而不是渲染着色器。

#### 准备

`prepare(with:outputRetainedBufferCountHint:)`：对属性进行初始化

1. 输出pxiel buffer池、输出格式；
2. 输入格式
3. 创建纹理缓存到`textureCache`
4. 就绪标识`isPrepared`

#### 重置

`reset()`：清空所有属性

#### 渲染

`render(pixelBuffer:)`：进行Metal滤镜的渲染流程

1. 准备相关资源：
2. 
- 从`outputPixelBufferPool`创建输出CVPixelBuffer。
- 从输入CVPixelBuffer创建输入纹理（绑定关系，共享内存），顺便指定纹理格式为`.bgra8Unorm`。
- 从输出CVPixelBuffer创建输出纹理（绑定关系，共享内存），顺便指定纹理格式为`.bgra8Unorm`。

2. 创建从设备创建命令队列，存储到`commandQueue`。
3. 从命令队列创建命令缓冲区。
4. 命令缓冲区创建计算命令编码器。
5. 对命令编码器进行相关配置：

- 设置管线状态（`computePipelineState`）；
- 设备纹理，输入、输出分别设置到0、1的位置。
- 分配并配置线程组：

```swift
// Set up the thread groups.
let width = computePipelineState!.threadExecutionWidth
let height = computePipelineState!.maxTotalThreadsPerThreadgroup / width
let threadsPerThreadgroup = MTLSizeMake(width, height, 1)
let threadgroupsPerGrid = MTLSize(width: (inputTexture.width + width - 1) / width,
                                  height: (inputTexture.height + height - 1) / height,
                                  depth: 1)
commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
```

6. 结束编码器编码。
7. 提交命令缓冲区。

从CVPixelBuffer创建Metal纹理对象：

```swift
func makeTextureFromCVPixelBuffer(pixelBuffer: CVPixelBuffer, textureFormat: MTLPixelFormat) -> MTLTexture? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    
    // Create a Metal texture from the image buffer.
    var cvTextureOut: CVMetalTexture?
    CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, textureFormat, width, height, 0, &cvTextureOut)
    
    guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
        CVMetalTextureCacheFlush(textureCache, 0)
        
        return nil
    }
    
    return texture
}
```

## 预览视图

PreviewMetalView：MTKView子类，对pixel buffer预览，并支持设置`mirroring`、`rotation`。

在`draw(_:)`执行绘制。MTKView会自动调用该方法。当然所谓的绘制也都是用命令缓冲区预览到Drawable。
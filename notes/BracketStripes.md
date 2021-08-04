# BracketStripes

通过配置采集输入，传递多个拍摄参数，让一次输出多个参数对应的帧，然后进行条纹绘制。

## 采集会话链路

输入：后置摄像头

输出：AVCaptureStillImageOutput

让输出支持多帧：

1. 创建多个AVCaptureXXXBracketedStillImageSettings配置；
2. 通过`-prepareToCaptureStillImageBracketFromConnection:withSettingsArray:completionHandler:`设置到采集输出中。

## 拍摄

`-_performBrackedCaptureWithCompletionHandler:`

调用的`_stillImageOutput`的`-captureStillImageBracketAsynchronouslyFromConnection:withSettingsArray:completionHandler:`方法，在回调中获取sample buffer。

调用`_imageStripes`的`-addSampleBuffer:`方法拼接绘制条纹图片。

## 绘制条纹

StripedImage`-addSampleBuffer:`：把每次传入的帧绘制到一定间距的矩形中，进行绘制。




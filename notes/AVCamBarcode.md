# AVCamBarcode

使用AVFoundation的图像识别。

## 采集与识别

CameraViewController

### 采集会话初始配置

`configureSession()`：

1. 添视频采集设备作为输入；
2. 添加元数据输出。并设置其兴趣矩形。

## 预览

PreviewView，其layerClass是AVCaptureVideoPreviewLayer。

比较有意思的是在旋转后，识别区域还可以保持不变。

### 布局

组成部分：

- `maskLayer`：CAShapeLayer，全屏的暗色遮罩。
    + `fillRule = kCAFillRuleEvenOdd`
- `regionOfInterestOutline`：CAShapeLayer，识别的兴趣区域，黄色边框。
- `topLeftControl`、`topRightControl`、`bottomLeftControl`、`bottomRightControl`：CAShapeLayer，四个角的thumb。

挖空效果：

```swift
// Create the path for the mask layer. We use the even odd fill rule so that the region of interest does not have a fill color.
let path = UIBezierPath(rect: CGRect(x: 0, y: 0, width: frame.size.width, height: frame.size.height))
path.append(UIBezierPath(rect: regionOfInterest))
path.usesEvenOddFillRule = true
maskLayer.path = path.cgPath
```

### 手势调整识别区域

添加了一个pan手势`resizeRegionOfInterestGestureRecognizer`。

`resizeRegionOfInterestWithGestureRecognizer(_:)`：

began：

获取手势所在的thumb。

`cornerOfRect(_:closestToPointWithinTouchThreshold:)`：

1. 选出与触摸点距离最近的corner及其与距离。
2. 若距离大于`regionOfInterestCornerTouchThreshold`（50）则视为`.none`。

changed：

根据得出的corner改变识别矩形或对其进行整个移动。

## 细节

### 兴趣区域的更新

兴趣区域的是KVO监听`previewView`的`\.regionOfInterest`进行更新的。直接设置元数据输出对象的`rectOfInterest`属性。

### 识别矩形的处理

通过`createMetadataObjectOverlayWithMetadataObject(_:)`方法绘制一个Layer，添加到预览视图上。

绘制过程使用信号量加锁：

```swift
// 元数据回调
if metadataObjectsOverlayLayersDrawingSemaphore.wait(timeout: .now()) == .success {
    // 切到主队列绘制
    DispatchQueue.main.async {
        // 绘制逻辑。。。
        self.metadataObjectsOverlayLayersDrawingSemaphore.signal()
    }
}
```

添加图层后，设置了1秒的定时器，定时移除图层。

### 对识别出来的URL还支持点击跳转

识别出的内容，通过尝试创建URL对象，并跳转到SFSafariViewController进行浏览。

### 旋转后，保持识别区域不变

示例做到了屏幕旋转前后，其识别区域在屏幕中的绝对位置保持不变。

`viewWillTransition(to:with:)`

```swift
/*
    When we transition to a new size, we need to recalculate the preview
    view's region of interest rect so that it stays in the same
    position relative to the camera.
*/
coordinator.animate(alongsideTransition: { context in
        let newRegionOfInterest = self.previewView.videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: self.metadataOutput.rectOfInterest)
        self.previewView.setRegionOfInterestWithProposedRegionOfInterest(newRegionOfInterest)
    },
    completion: { context in
        // ...
    }
)
```

### 探索更好的旋转体验

#### 让AVCaptureVideoPreviewLayer内容不旋转

通过AVCaptureVideoPreviewLayer设置`videoOrientation`的逻辑放入`animate(alongsideTransition:completion:)`的动画block中，可以让AVCaptureVideoPreviewLayer的内容在旋转的过程中保持不变。

但这里有个前提是AVCaptureVideoPreviewLayer要作为某个UIView的layer。

`viewWillTransition(to:with:)`

```swift
/*
    When we transition to a new size, we need to recalculate the preview
    view's region of interest rect so that it stays in the same
    position relative to the camera.
*/
coordinator.animate(alongsideTransition: { context in
        
        // 让videoPreviewLayer保持不动的秘诀
        videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        // ...
    },
    completion: { context in
        // ...
    }
)
```

#### 让AVCaptureVideoPreviewLayer跟随旋转

如果想要把AVCaptureVideoPreviewLayer跟随屏幕旋转而旋转，可以把AVCaptureVideoPreviewLayer作为某个layer的子视图，这样就可以实现跟随其他UI一起旋转。

注意，不同的布局系统可能在旋转的时候会有不同步的情况。最保险的方式是所有UI都是用UIView进行AutoLayout。

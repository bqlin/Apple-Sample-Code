# AVSimpleEditoriOS

项目结构很清晰，通过Command子类实现各种视频编辑功能。

项目展示了视频编辑的导出和预览两个管线，但个人觉得两者的效果并不是对等的。

其中预览使用AVAsset子类创建的AVPlayerItem实现。导出则使用同样的子类创建AVAssetExportSession对象。两者都可以设置`videoComposition`、`audioMix`，但在以下功能上是不对等的：

- AVVideoComposition：`animationTool`是AVAssetExportSession独享的，AVPlayerItem无法预览。
    + 所以创建AVPlayerItem时，要将AVVideoComposition的`animationTool`属性清空。
    + 这本来是视频叠加素材最便捷的方式，但如果要预览，还要自己构建对应的预览逻辑。
    + 这其中的CALayer，首先不能是某个UIView的`layer`，因为这添加到图层都无法预览。其次不能被添加到布局系统，即添加到图层中，否则其大小会变化，这尤其是在不设置CALayer的大小时尤为明显。当然只添加到布局系统而不修改相关的布局参数也是没问题的。这说明要正确地预览，可能还是遵循Demo那样需要构建不同的CALayer实例。


## 具体编辑功能

时间裁剪：

- 时间裁剪是对AVMutableComposition的操作。
- 对AVMutableCompositionTrack插入时间区间和移除时间区间。

添加背景音乐：

1. 用输入asset构建composition。
2. 添加用背景音乐填充的音频轨。
3. （可选）设置音量渐变。

添加水印：

- 水印在这里是构建一个CALayer，当然其大小要跟视频尺寸相匹配。
- 除此以外，因为要使用AVVideoComposition的`animationTool`属性，所以还要创建一个直通的AVVideoComposition。

画幅裁剪：

- 裁剪的原理是设置`renderSize`+transform。这里使用的是改变`renderSize`，然后平移画面。
- 设置transform是在AVMutableVideoCompositionLayerInstruction对象，所以还需构建对应的AVMutableVideoCompositionInstruction，并进行组合。

画面旋转：跟画幅裁剪原理一致，也是设置`renderSize`+transform。只是这里的transform包含旋转和平移。

## 导出

示例中的导出完整逻辑是分为ViewController和ExportCommand的实现。

### ViewController

`exportWillBegin()`

- 配置ExportCommand的`composition`、`videoComposition`、`audioMix`。
- 添加定时器，用于轮询导出进度。
- 构建图层层级。构建AVMutableVideoComposition的`animationTool`（AVVideoCompositionCoreAnimationTool对象）。

### ExportCommand

这里基本就是对AVAssetExportSession进行属性配置，并调用导出方法。

## 细节

### 音量渐变

AVMutableAudioMixInputParameters，使用对应的音频轨道创建。可设置时间点和时间段的渐变。

添加到AVMutableAudioMix的`inputParameters`数组中。


### 直通AVVideoComposition

```swift
static func makeVideoComposition(compostion: AVComposition) -> AVMutableVideoComposition {
    let videoTrack = compostion.tracks(withMediaType: .video).first!
    
    // 设置基本参数
    let videoCompositon = AVMutableVideoComposition()
    videoCompositon.frameDuration = CMTime(value: 1, timescale: 30)
    videoCompositon.renderSize = videoTrack.naturalSize
    
    // 构建与配置AVMutableVideoCompositionInstruction
    let passThroughInstruction = AVMutableVideoCompositionInstruction()
    passThroughInstruction.timeRange = CMTimeRange(start: .zero, duration: compostion.duration)
    
    // 构建与视频轨关联的AVMutableVideoCompositionLayerInstruction
    let passThroughLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
    
    // 组合
    passThroughInstruction.layerInstructions = [passThroughLayer]
    videoCompositon.instructions = [passThroughInstruction]
    
    return videoCompositon
}
```
# AVCustomEdit

使用自定义视频合成器，实现过渡。

## AVMutableComposition组成

APLSimpleEditor管理asset如何组合与应用composition。

和视频和音频各设置两个，交叉叠放，并记录这些时间范围：

- passThroughTimeRanges
- transitionTimeRanges

## 预览

使用compostionin创建AVPlayerItem，并设置其`videoComposition`。

使用AVPlayer + AVPlayerLayer进行预览。

## 具体的自定义合成器

### 使用

```swift
let videoComposition = AVMutableVideoComposition()

if self.transitionType == TransitionType.diagonalWipe.rawValue {
    videoComposition.customVideoCompositorClass = APLDiagonalWipeCompositor.self
} else {
    videoComposition.customVideoCompositorClass = APLCrossDissolveCompositor.self
}

// Every videoComposition needs these properties to be set:
videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30) // 30 fps.
videoComposition.renderSize = videoSize

// 设置其`instructions`属性
buildTransitionComposition(composition, andVideoComposition: videoComposition)
```

核心方法：

```swift
func newRenderedPixelBufferForRequest(_ request: AVAsynchronousVideoCompositionRequest) -> CVPixelBuffer? {

    /*
     tweenFactor indicates how far within that timeRange are we rendering this frame. This is normalized to vary
     between 0.0 and 1.0. 0.0 indicates the time at first frame in that videoComposition timeRange. 1.0 indicates
     the time at last frame in that videoComposition timeRange.
     */
    let tweenFactor =
        factorForTimeInRange(request.compositionTime, range: request.videoCompositionInstruction.timeRange)

    guard let currentInstruction =
        request.videoCompositionInstruction as? APLCustomVideoCompositionInstruction else {
        return nil
    }

    // Source pixel buffers are used as inputs while rendering the transition.
    guard let foregroundSourceBuffer = request.sourceFrame(byTrackID: currentInstruction.foregroundTrackID) else {
        return nil
    }
    guard let backgroundSourceBuffer = request.sourceFrame(byTrackID: currentInstruction.backgroundTrackID) else {
        return nil
    }

    // Destination pixel buffer into which we render the output.
    guard let dstPixels = renderContext?.newPixelBuffer() else { return nil }

    if renderContextDidChange { renderContextDidChange = false }

    metalRenderer.renderPixelBuffer(dstPixels, usingForegroundSourceBuffer:foregroundSourceBuffer,
                                    andBackgroundSourceBuffer:backgroundSourceBuffer,
                                    forTweenFactor:Float(tweenFactor))

    return dstPixels
}
```

所以最终的渲染逻辑落到了两个Renderer的实现中。
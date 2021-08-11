# avTouchController

项目的亮点恰恰不在AVAudioPlayer的调用，而是一些细节。

## 细节

### 按下快进/快退

该功能类似于以前DVD的快进/快退功能的效果，按下快进/快退，抬起则恢复播放。

```swift
// 按下事件
ffwButton.addTarget(self, action: #selector(self.ffwButtonPressed), for: .touchDown)
// 所有抬起事件
ffwButton.addTarget(self, action: #selector(self.ffwButtonReleased), for: [.touchUpInside, .touchUpOutside, .touchDragOutside])

func ffwd() {
    guard let player = player else { return }
    player.currentTime += SkipTime
    //print("前进\(SkipTime) -> \(player.currentTime)")
    updateCurrentTimeForPlayer(player)
}

@objc func ffwButtonPressed() {
    // 使用定时器实现连续调用
    ffwTimer?.invalidate()
    ffwTimer = Timer.scheduledTimer(withTimeInterval: SkipInterval, repeats: true, block: { [weak self] (_) in
        self?.ffwd()
    })
}

@objc func ffwButtonReleased() {
    // 停止连续调用
    ffwTimer?.invalidate()
    ffwTimer = nil
}
```

### 音频电平展示

使用MeterTable对AVAudioPlayer的`averagePower(forChannel:)`和`peakPower(forChannel:)`的电平转换成百分比，并进行缓存。

然后通过两种方案进行展示：

- LevelMeter：使用CoreGraphics在`draw(_:)`方法中绘制。
- GLLevelMeter：使用GLES 1.0绘制。

因为使用的是GLES 1.0，所以也省去了着色器的编写。

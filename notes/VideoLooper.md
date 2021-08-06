# VideoLooper

## Demo基本流程

SetupViewController选择配置，在`prepare(for:sender:)`方法创建对应的Lopper，传递给LooperViewController。

LooperViewController：`looper`调用`start(in:)`方法与视图关联，并开始循环播放。`viewDidDisappear(_:)`时停止循环播放。

## PlayerLooper

这里是使用AVQueuePlayer+AVPlayerLooper实现循环播放。

### AVQueuePlayer、AVPlayerItem与AVPlayerLooper的关联

AVPlayerItem使用URL创建，但没有立即设置到AVQueuePlayer，而是在加载asset keys后，创建AVPlayerLooper，关联AVQueuePlayer和AVPlayerItem。

```swift
self.playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
```

关联之后才开始KVO监听。

### 停止

```swift
func stop() {
    player?.pause()
    stopObserving()

    playerLooper?.disableLooping()
    playerLooper = nil

    playerLayer?.removeFromSuperlayer()
    playerLayer = nil

    player = nil
}
```

1. AVQueuePlayer暂停播放；
2. 移除KVO监听；
3. AVPlayerLooper停止循环；
4. 移除AVPlayerLayer；
5. 置空相关对象。

## QueuePlayerLooper

这里不使用AVPlayerLooper，而是通过不断地插入item实现循环播放。

### AVQueuePlayer与AVPlayerItem的关联

与PlayerLooper不同，这里没有直接创建AVPlayerItem，而是创建AVURLAsset。

加载keys后，创建多个AVPlayerItem：

```swift
/*
 Based on the duration of the asset, we decide the number of player 
 items to add to demonstrate gapless playback of the same asset.
 */
let numberOfPlayerItems = (Int)(1.0 / CMTimeGetSeconds(videoAsset.duration)) + 2

for _ in 1...numberOfPlayerItems {
    let loopItem = AVPlayerItem(asset: videoAsset)
    self.player?.insert(loopItem, after: nil)
}
```

### 实现循环

使用插入item实现循环：

```swift
if context == &ObserverContexts.currentItem {
    guard let player = player else { return }

    if player.items().isEmpty {
        print("Play queue emptied out due to bad player item. End looping")
        stop()
    }
    else {
        // If `loopCount` has been set, check if looping needs to stop.
        if numberOfTimesToPlay > 0 {
            numberOfTimesPlayed = numberOfTimesPlayed + 1

            if numberOfTimesPlayed >= numberOfTimesToPlay {
                print("Looped \(numberOfTimesToPlay) times. Stopping.");
                stop()
            }
        }

        /*
            Append the previous current item to the player's queue. An initial
            change from a nil currentItem yields NSNull here. Check to make
            sure the class is AVPlayerItem before appending it to the end
            of the queue.
        */
        if let itemRemoved = change?[.oldKey] as? AVPlayerItem {
            itemRemoved.seek(to: CMTime.zero)

            stopObserving()
            player.insert(itemRemoved, after: nil)
            startObserving()
        }
    }
}
```

其他流程基本一致。

## 细节
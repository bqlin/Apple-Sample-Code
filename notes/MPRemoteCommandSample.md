# MPRemoteCommandSample

## asset列表与AssetPlaybackManager的交互

AssetListTableViewController

主动从本地加载m4a文件为Asset模型，存放在`assets`数组中，用于展示。

接收来自AssetPlaybackManager的`nextTrackNotification`、`previousTrackNotification`的通知，给AssetPlaybackManager传递对应索引的Asset模型进行播放。

## AssetPlaybackManager

主要管理对象：

- `player`（AVPlayer）
- `playerItem`（AVPlayerItem）
    + 在属性观察器监听、移除通知：
        - `AVPlayerItem.status`：决定是否调用播放方法
        - `.AVPlayerItemDidPlayToEndTime`：`player.replaceCurrentItem(with: nil)`
- `asset`（Asset）
    + 在属性观察期监听、移除`AVURLAsset.isPlayable`通知：创建AVPlayerItem并给`player`设置。
    + 发出`currentAssetDidChangeNotification`通知。
- `nowPlayingInfoCenter`（MPNowPlayingInfoCenter）

### 构造方法

`init()`

1. 注册监听：
    - `AVAudioSession.interruptionNotification`：中断时进行log，以及进行恢复
    - `AVPlayer.currentItem`：更新元数据信息
    - `AVPlayer.rate`：更新元数据信息、发出`AssetPlaybackManager.playerRateDidChangeNotification`通知
    - 时间监听：更新属性：`playbackPosition`、`percentProgress`

### 更新元数据信息

#### `updateGeneralMetadata()`

更新封面、标题、专辑标题。

从`player.currentItem`取出元数据，最终设置到`nowPlayingInfoCenter.nowPlayingInfo`字典中。

这些元数据都是从`AVMetadataKeySpace.common`key space中获取。

- MPMediaItemPropertyTitle：`commonKeyTitle`
- MPMediaItemPropertyAlbumTitle：`commonKeyAlbumName`
- MPMediaItemPropertyArtwork：`commonKeyArtwork`

MPMediaItemPropertyArtwork类型是MPMediaItemArtwork，需要通过UIImage创建。

#### `updatePlaybackRateMetadata()`

更新时间进度信息。

- MPMediaItemPropertyPlaybackDuration：`player.currentItem!.duration.seconds`
- MPNowPlayingInfoPropertyElapsedPlaybackTime：`player.currentItem!.currentTime().seconds`
- MPNowPlayingInfoPropertyPlaybackRate：`player.rate`
- MPNowPlayingInfoPropertyDefaultPlaybackRate：`player.rate`

### 播放相关方法

这些方法都是由外部调用。

`play()`、`pause()`、`togglePlayPause()`：比较常规，就是调用player的`play()`、`pause()`方法。

`stop()`：

- 情况属性：`asset`、`playerItem`
- `player.replaceCurrentItem(with: nil)`

`nextTrack()`、`previousTrack()`：只是发送通知，由AssetListTableViewController响应来设置Asset实现播放。

`skipForward(_:)`、`skipBackward(_:)`、`seekTo(_:)`：seek，在完成回调更新元数据。

`beginRewind()`、`beginFastForward()`、`endRewindFastForward()`：简单设置`player`的`rate`属性。

## RemoteCommandManager

主要管理对象：

- `remoteCommandCenter`（MPRemoteCommandCenter）
- `assetPlaybackManager`（AssetPlaybackManager）

该类基本就是MPRemoteCommandCenter的全部基本使用了，其使用跟UIControl很类似，都是启用，然后添加事件响应。但这个时间响应都要返回一个是否成功的状态。

## AppDelegate中的处理

- 管理`assetPlaybackManager`和`remoteCommandManager`，并赋值给响应的controller。
- 设置AVAudioSession。

## 细节

## 遍历目录

使用FileManager.DirectoryEnumerator对象，对指定的目录路径进行遍历。

```swift
// Populate `assetListTableView` with all the m4a files in the Application bundle.
guard let enumerator = FileManager.default.enumerator(at: Bundle.main.bundleURL, includingPropertiesForKeys: nil, options: [], errorHandler: nil) else { return }

assets = enumerator.compactMap { element in
    guard let url = element as? URL, url.pathExtension == "m4a" else { return nil }
    
    let fileName = url.lastPathComponent
    return Asset(assetName: fileName, urlAsset: AVURLAsset(url: url))
}
```

### URL在Swift中的处理

NSString有很多path的处理方法，而String则一律去除了，其实是挪到了URL结构体中，所有的URL处理方法都有。

如果需要结构化处理URL，可以使用URLComponents结构体。
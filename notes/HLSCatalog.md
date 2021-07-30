# HLSCatalog

## 播放

使用AVPlayerViewController进行播放。

### AssetPlaybackManager

播放器管理类，单例，最后把播放器和播放器状态回调出去，由Controller调用播放。管理：

- player（AVPlayer）整个生命周期
- asset（Asset）：要播放的媒体
- playerItem（AVPlayerItem）：对应创建的player item。

`asset`和`playerItem`的核心都是在其setter。

播放：

`setAssetForPlayback(_:)`：set asset

1. willSet：
	取消`\AVURLAsset.isPlayable`的监听。
2. didSet：
	监听`\AVURLAsset.isPlayable`，并在可播放时创建AVPlayerItem，赋值给`playerItem`和`player`。

playerItme setter:

1. willSet：
	1. 取消`\AVPlayerItem.status`的监听。
	2. 取消`TimebaseEffectiveRateChangedNotification`、`AVPlayerItemPlaybackStalled`通知。
2. didSet：
	1. 监听`\AVPlayerItem.status`，并在就绪播放时回调`streamPlaybackManager(_:playerReadyToPlay:)`。
		回调中调用`play()`方法播放。
	3. 创建测量类PerfMeasurements。
	4. 监听通知：`TimebaseEffectiveRateChangedNotification`、`AVPlayerItemPlaybackStalled`。这两个通知都是用来与测量类交互的。


## 下载

### AssetListManager

单例，提供显示的资源列表。

管理：

- Asset（用于展示）数组。

Asset数组在接到`AssetPersistenceManagerDidRestoreState`通知时才进行获取：

基本逻辑：用Stream.name换取Asset。

细节：

1. 从正在下载的`activeDownloadsMap`获取Asset。
2. 否则，尝试检查本地已下载的，并从本地URL创建Asset。
3. 否则，直接用Stream的在线URL创建Asset。
4. 发出`AssetListManagerDidLoad`通知。

### StreamListManager

单例，从本地plist加载列表。

管理：

- Stream（本地数据模型）数组。

### AssetPersistenceManager

管理HLS下载，及其相关的本地恢复（本地恢复也是通过下载的本地URL和下载会话实现的）。

#### 初始化

创建可后台下载的AVAssetDownloadURLSession，专门用于HLS下载的URLSection。

后台会话配置有一个唯一字符串标识，在创建的时候如果系统服务有现存的会话会直接沿用那个会话。即在启动App的时候，创建的会话可能是之前正在下载的后台会话。

#### 下载

1. 创建下载任务，可以指定自定义的标题、封面。
2. 存储任务到`activeDownloadsMap`字典。
3. 开始任务。
4. 发出`AssetDownloadStateChanged`通知。

#### 下载回调

__获取下载本地位置：`urlSession(_:aggregateAssetDownloadTask:willDownloadTo:)`__

存储本地URL到`willDownloadToUrlMap`。

__媒体选项完成回调：`urlSession(_:aggregateAssetDownloadTask:didCompleteFor:)`__

发出`AssetDownloadStateChanged`通知。

__进度回调：`urlSession(_:aggregateAssetDownloadTask:didLoad:totalTimeRangesLoaded:timeRangeExpectedToLoad:for:)`__

发出`AssetDownloadProgress`通知。

__完成回调：`urlSession(_:task:didCompleteWithError:)`__

1. 从`activeDownloadsMap`移除任务。
2. 从`willDownloadToUrlMap`移除并获得本地URL。
3. 处理错误。存储本地URL的bookmarkData，到user default。
4. 发出`AssetDownloadStateChanged`通知。

#### 取消下载

简单调用下载任务的`cancel()`方法。

#### 删除本地

1. 删除本地URL对应的资源；
2. 删除user default中的记录；
3. 发出`AssetDownloadStateChanged`通知。

#### 恢复

`restorePersistenceManager()`

在启动时，在AppDelegate的`application(_:didFinishLaunchingWithOptions:)`调用恢复方法。

只是简单地从创建的后台下载会话中获得下载任务，并通过其`taskDescription`自定义配置的值恢复模型数据。

#### 细节专题

如何存取本地URL/本示例中userDefaults的使用：

```swift
// 移除（deleteAsset(_:)、urlSession(_:task:didCompleteWithError:)）
userDefaults.removeObject(forKey: asset.stream.name)

// 存储（urlSession(_:task:didCompleteWithError:)）
guard let downloadURL = willDownloadToUrlMap.removeValue(forKey: task) else { return }
let bookmark = try downloadURL.bookmarkData()
userDefaults.set(bookmark, forKey: asset.stream.name)

// 读取（localAssetForStream(withName:)）
guard let localFileLocation = userDefaults.value(forKey: name) as? Data else { return nil }
let url = try URL(resolvingBookmarkData: localFileLocation, bookmarkDataIsStale: &bookmarkDataIsStale)
if bookmarkDataIsStale {
    fatalError("Bookmark data is stale!")
}
```

获取下载状态：

`downloadState(for:)`

1. 获取本地URL，检查本地文件是否存在。-> `.downloaded`
2. 检查是否在当前下载字典`activeDownloadsMap`中。-> `.downloading`
3. 否则`.notDownloaded`

几个模型的使用：

- `activeDownloadsMap`：当前下载<AVAggregateAssetDownloadTask: Asset>。存储当前下载的任务。以下载任务为key可以在下载任务回调中方便地取出Asset。
	+ 存：
		* 恢复时，后台下载任务即使App退出了也可以通过相同的ID从系统重新获取，并获得其下载任务。
		* 开始下载。
	+ 删：下载结束时。

这里取消时没有直接从中移除task，而是等待在结束回调中进行移除。

- `willDownloadToUrlMap`：下载任务对应的本地URL<AVAggregateAssetDownloadTask: URL>。
	+ 存：`urlSession(_:aggregateAssetDownloadTask:willDownloadTo:)`
	+ 删：下载结束时。

如何更新进度：

1. 在`urlSession(_:aggregateAssetDownloadTask:didLoad:totalTimeRangesLoaded:timeRangeExpectedToLoad:for:)`发出`AssetDownloadProgress`通知。
2. Cell接收`AssetDownloadProgress`通知，并更新对应asset的progressView。

如果更新下载状态：

Cell接收`AssetDownloadStateChanged`通知：

1. 更新自身视图：
2. 回调状态。Controller响应回调，进行`reloadRows`。


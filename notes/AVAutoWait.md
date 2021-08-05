# AVAutoWait

## 播放预览

PlaybackViewController

主要是基本的播放操作，并根据`player?.reasonForWaitingToPlay != .toMinimizeStalls`隐藏/显示菊花视图。

其中有个开关是设置AVPlayer的`automaticallyWaitsToMinimizeStalling`属性。

另外，有个控件事件是调用AVPlayer的`playImmediately(atRate:)`方法。该方法解释如下：

这个方法以指定的速率播放可用的媒体数据，不管是否有足够的媒体缓冲来确保顺利播放。如果媒体数据存在于播放缓冲区，调用此方法将播放器的播放速率改为指定的速率，并将其`timeControlStatus`改为`AVPlayer.TimeControlStatus.playing`值。如果播放器没有足够的媒体数据缓冲来开始播放，播放器的行为就像它在播放过程中遇到卡顿一样，不同的是不会发布`AVPlayerItemPlaybackStalled`变更。

也就是说，调用该方法能够更快地预览画面。

## 播放器参数细节

PlaybackDetailsViewController

预览了AVPlayer及其AVPlayerItem的属性值。

使用KVO监听：

- `player.rate`
- `player.timeControlStatus`
- `player.reasonForWaitingToPlay`
- `player.currentItem.playbackLikelyToKeepUp`
- `player.currentItem.loadedTimeRanges`
- `player.currentItem.playbackBufferFull`
- `player.currentItem.playbackBufferEmpty`

对于无法使用KVO监听的，则使用GCD定时器轮询：

- `player?.currentItem?.currentTime().description`
- `CMTimebaseGetRate(player!.currentItem!.timebase!).description`

注意这里的`description`是在本类实现的扩展。

## 细节

### PlaybackViewController与PlaybackDetailsViewController的结合

比较有意思的是，这两个控制器是在MediaViewController中进行结合的。过程也很简单：

1. 从`storyboard`中用id加载对应的控制。
2. 插入对自身的`stackView`中。

我觉得比较严谨的做法还应把这两个控制器设置为自身控制器的子控制器。

另外`player`对象也是由MediaViewController创建管理的，并传递给PlaybackViewController和PlaybackDetailsViewController，这样确保两个控制器使用的是同一个AVPlayer。
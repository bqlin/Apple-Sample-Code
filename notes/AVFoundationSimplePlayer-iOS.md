# AVFoundationSimplePlayer-iOS

> 使用AVPlayer实现简单播放器

AVPlayer直接就定义为常量。而不是通过player item初始化。后续通过`replaceCurrentItem(with:)`设置player item。

AVURLAsset加载的是本地的URL。异步加载`playable`、`hasProtectedContent`键。当然回调中也要检查这些键的状态。

asset属性异步加载后，进行：

- 给player注册监听
- 给预览时图设置播放器
- 替换player item

把状态处理都放在同一个队列中，示例中是放到主队列中。所以asset异步加载key后要切回状态处理的队列。

asset加载到键值之后才给player注册相关的监听。响应监听要处理UI需切换回主队列。

播放按钮使用player的`timeControlStatus`状态更新。

使用NSDateComponents + DateComponentsFormatter实现时间格式化。

由于是对player进行监听，虽然监听的key path是`\AVPlayer.currentItem?.status`，即对currentItem的属性监听，即使currentItem在注册监听时不存在也可以监听。

AVPlayer的`play()`、`pause()`只是把`rate`切换1.0、0.0，所以要实现变速的暂停、播放，还需记住之前改变的速度值，播放时进行恢复。

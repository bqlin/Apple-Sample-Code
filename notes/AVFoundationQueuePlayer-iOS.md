# AVFoundationQueuePlayer-iOS

AVQueuePlayer与AVPlayer用法基本一致。基本是使用AVURLAsset加载URL，异步加载key，然后创建对应的AVPlayerItem。

使用上与AVPlayer较大不同的是设置playerItem的方式。使用`insert(_:after:)`方法，after传入nil则为在末尾插入。

另外，在播放行为上，播放完一个item，就会直接dequeue删除item，然后enqueue一个item进行播放。播放完成就会执行这样的操作，如果设置了倒序播放，则一开始播放就会直接完成，然后切往下一个item。可以通过设置`actionAtItemEnd`改变行为。

另外注意Swift的KVO方式会导致使用可选类型、枚举类型的change结果里面值为空。但回调时机还是正确的。

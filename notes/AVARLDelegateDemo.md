# AVARLDelegateDemo

使用AVAssetResourceLoaderDelegate自定义加载资源。

Demo中加载的URL是`cplp://devimages.apple.com/samplecode/AVARLDelegateDemo/BipBop_gear3_segmented/redirect_prog_index.m3u8`，显然这不是常规的URL。在用URL创建AVURLAsset后，设置自定义的AVAssetResourceLoaderDelegate实现，后续像处理一般AVURLAsset即可。

```objective-c
//Setup the delegate for custom URL.
self->delegate = [[APLCustomAVARLDelegate alloc] init];
AVAssetResourceLoader *resourceLoader = asset.resourceLoader;
[resourceLoader setDelegate:delegate queue:dispatch_queue_create("AVARLDelegateDemo loader", nil)];
```

## AVAssetResourceLoaderDelegate

### Processing Resource Requests

```swift
optional func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool
```

是否加载请求的资源。
Asks the delegate if it wants to load the requested resource.

参数：

- `resourceLoader`：发起请求的AVAssetResourceLoader对象
- `loadingRequest`：包含请求资源信息的请求对象

返回：是否处理给定的资源请求。

讨论：

当需要你的代码协助加载指定的资源时，资源加载器对象会调用这个方法。例如，资源加载器可以调用这个方法来加载使用自定义URL方案指定的解密密钥。

从这个方法返回`true`，仅意味着接收方将加载，或至少尝试加载该资源。在一些实现中，加载资源的实际工作可能在另一个线程上启动，异步运行于资源加载委托；工作是否立即开始或仅仅是很快开始，是客户端App的实现细节。

你可以同步地或异步地加载资源。在这两种情况下，你必须在完成时调用请求对象的`finishLoading(with:data:redirect:)`或`finishLoading(with:)`方法来指示操作的成功或失败。如果你是异步加载资源，你也必须在从这个方法返回之前在`loadingRequest`参数中存储一个对该对象的强引用。

如果你从这个方法返回false，资源加载器会将资源的加载视为失败。

```swift
optional func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool
```

是否需要协助更新资源。

参数：

- `resourceLoader`
- `renewalRequest`：请求资源信息

返回：是否可以更新资源

讨论

`resourceLoader(_:shouldWaitForLoadingOfRequestedResource:)`在加载资源后，才会调用该方法。例如，在该方法调用时更新解密密钥。

如果结果为`true`，资源加载器期望随后或立即调用AVAssetResourceRenewalRequest的`finishLoading`或`finishLoadingWithError:`方法。如果你打算在处理此消息返回后完成资源的加载，你必须持有`renewalRequest`直到加载完成。

如果结果是`false`，资源加载器会将资源的加载视为失败。

注意

如果委托对`-resourceLoader(_:shouldWaitForLoadingOfRequestedResource:)`的实现返回`true`而没有立即完成加载请求，那么在先前的请求完成之前，它可能会被另一个加载请求再次调用；因此在这种情况下，委托应该准备好管理多个加载请求。

Content Key Types

The types of custom URLs that should be handled as content keys.

- `let AVStreamingKeyDeliveryPersistentContentKeyType: String`
- `let AVStreamingKeyDeliveryContentKeyType: String`

```swift
optional func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest)
```

之前的加载请求已经被取消。

参数：

- `resourceLoader`
- `loadingRequest`：取消的加载请求。

讨论

当不再需要资源中的数据时，或者当加载请求被同一资源中的数据的新请求所取代时，先前发出的加载请求可以被取消。

例如，如果为了完成一个搜索操作，有必要加载一个与之前请求的字节范围不同的字节范围，那么之前的请求可以被取消，而委托仍然在处理它。


### Processing Authentication Challenges

```swift
optional func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel authenticationChallenge: URLAuthenticationChallenge)
```

之前的认证挑战已经取消。

参数：

- `resourceLoader`
- `authenticationChallenge`：被取消的认证挑战

```swift
optional func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForResponseTo authenticationChallenge: URLAuthenticationChallenge) -> Bool
```

是否需要App协助响应认证挑战。

参数：

- `resourceLoader`
- `authenticationChallenge`

讨论

当需要应用程序协助响应认证挑战时，代理会收到这个消息。

如果你期望随后或立即对`authenticationChallenger`对象的发送者作出响应，则返回`true`。

如果你打算在处理完`resourceLoader:shouldWaitForResponseToAuthenticationChallenge:`返回后再响应认证挑战，你必须保留认证挑战，直到你做出响应。

## APLCustomAVARLDelegate实现

该类只实现了的AVAssetResourceLoaderDelegate的`-resourceLoader:shouldWaitForLoadingOfRequestedResource:`方法

根据scheme进行处理，对AVAssetResourceLoadingRequest进行操作。：

### 重定向

`-handleRedirectRequest:`

1. 把scheme从`rdtp`改成`http`。并创建NSURLRequest。设置到`redirect`属性。
2. 创建302响应。设置到`response`属性。
3. 调用`finishLoading`。

整个过程由于只是简单地修改scheme，所以都是同步操作。

### 自定义播放列表

异步到主队列执行`-handleCustomPlaylistRequest:`方法。

1. 把scheme从`cplp`改成`rdtp`。
2. 裁剪末尾`/`后面的路径，得出`prefix`。
3. 把scheme从`rdtp`改成`ckey`，得出`keyPrefix`。
4. 传入`-getCustomPlaylist:andKeyPrefix:totalElements:`方法得出data。
5. 用data创建响应。`[loadingRequest.dataRequest respondWithData:data];`
6. `-finishLoading`

`-getCustomPlaylist:andKeyPrefix:totalElements:`：

拼接成带加密key的m3u8文本。

### 自定义密钥

1. 把scheme从`ckey`替换成`http`，并简单使用NSData从URL获取数据。
2. 用data创建响应。`[loadingRequest.dataRequest respondWithData:data];`
3. `-finishLoading`

## 扩展

- [iOS AVPlayer 视频缓存的设计与实现 | 楚权的世界](http://chuquan.me/2019/12/03/ios-avplayer-support-cache/)
- [可能是目前最好的 AVPlayer 音视频缓存方案](https://mp.weixin.qq.com/s/v1sw_Sb8oKeZ8sWyjBUXGA)


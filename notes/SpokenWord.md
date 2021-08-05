# SpokenWord

## 开始录制

1. 若已经开始或`recognitionTask`已创建，则需要调用`cancel()`方法。
2. 配置audio session。
3. 创建语音视频对象SFSpeechAudioBufferRecognitionRequest，存储到`recognitionRequest`属性。
4. 配置属性：`shouldReportPartialResults = true`、`requiresOnDeviceRecognition = false`
5. 开始识别，返回结果存储到`recognitionTask`。从回调中获取识别的文字。
6. 从AVAudioEngine获取`inputNode`。
7. `inputNode`调用安装方法，在回调中拼接音频buffer。
8. 调用`audioEngine`的`prepare()`和`start()`方法，开始识别。

整个流程较为简单，基本就是获取AVAudioPCMBuffer，然后塞给识别器进行语音识别。

### 错误处理

```swift
// Stop recognizing speech if there is a problem.
self.audioEngine.stop()
inputNode.removeTap(onBus: 0)

// 清空相关识别过程中的属性
```

## 细节

### 权限请求

使用语音识别需要权限请求：

```swift
// Asynchronously make the authorization request.
SFSpeechRecognizer.requestAuthorization { authStatus in
    // 异步回调
}
```

### 识别的语言

识别的语言在创建SFSpeechRecognizer时就指定了，即在识别的过程中不能切换语言，也意味着一个识别器不能识别多种语言。

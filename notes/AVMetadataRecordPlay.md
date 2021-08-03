# AVMetadataRecordPlay


## 配置采集会话

输入：视频、音频

输出：

- AVCaptureMovieFileOutput
- AVCaptureMetadataInput

元数据输出的特殊处理：

input和connection要分开添加。

```swift
// Create the metadata input and add it to the session.
let newLocationMetadataInput = AVCaptureMetadataInput(formatDescription: locationMetadataDesc!, clock: CMClockGetHostTimeClock())
session.addInputWithNoConnections(newLocationMetadataInput)

// Connect the location metadata input to the movie file output.
let inputPort = newLocationMetadataInput.ports[0]
session.addConnection(AVCaptureConnection(inputPorts: [inputPort], output: movieFileOutput))
```

判断输入是否支持指定的元数据：

```swift
/**
    Iterates through all the movieFileOutput’s connections and returns true if the
    input port for one of the connections matches portType.
*/
private func isConnectionActiveWithInputPort(_ portType: String) -> Bool {
    
    for connection in movieFileOutput.connections {
        for inputPort in connection.inputPorts {
            if let formatDescription = inputPort.formatDescription, CMFormatDescriptionGetMediaType(formatDescription) == kCMMediaType_Metadata {
                if let metadataIdentifiers = CMMetadataFormatDescriptionGetIdentifiers(inputPort.formatDescription!) as? [String] {
                    if metadataIdentifiers.contains(portType) {
                        return connection.isActive
                    }
                }
            }
        }
    }
    
    return false
}
```

## 写入元数据

定位信息元数据直接向`locationMetadataInput`拼接即可。详见`locationManager(_:didUpdateLocations:)`。

而人脸信息元数据则是通过直接建立connection即可。

```swift
// Face metadata
if !isConnectionActiveWithInputPort(AVMetadataIdentifier.quickTimeMetadataDetectedFace.rawValue) {
    connectSpecificMetadataPort(AVMetadataIdentifier.quickTimeMetadataDetectedFace.rawValue)
}

/**
    Connect a specified video input port to the output of AVCaptureSession.
    This is necessary because connections for certain ports are not added automatically on addInput.
*/
private func connectSpecificMetadataPort(_ metadataIdentifier: String) {
    
    // Iterate over the videoDeviceInput's ports (individual streams of media data) and find the port that matches metadataIdentifier.
    for inputPort in videoDeviceInput.ports {
        
        guard (inputPort.formatDescription != nil) && (CMFormatDescriptionGetMediaType(inputPort.formatDescription!) == kCMMediaType_Metadata),
            let metadataIdentifiers = CMMetadataFormatDescriptionGetIdentifiers(inputPort.formatDescription!) as? [String] else {
                continue
        }
        
        if metadataIdentifiers.contains(metadataIdentifier) {
            // Add an AVCaptureConnection to connect the input port to the AVCaptureOutput (movieFileOutput).
            let connection = AVCaptureConnection(inputPorts: [inputPort], output: movieFileOutput)
            session.addConnection(connection)
        }
    }
}
```

## 细节

### 后台任务

开始录制时开启后台任务：

```swift
if UIDevice.current.isMultitaskingSupported {
    /*
        Set up background task.
        This is needed because the `capture(_:, didFinishRecordingToOutputFileAt:, fromConnections:, error:)`
        callback is not received until AVCam returns to the foreground unless you request background execution time.
        This also ensures that there will be time to write the file to the photo library when AVCam is backgrounded.
        To conclude this background execution, endBackgroundTask(_:) is called in
        `capture(_:, didFinishRecordingToOutputFileAt:, fromConnections:, error:)` after the recorded file has been saved.
    */
    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
}
```

清理资源时，结束后台任务：

```swift
/*
Note that currentBackgroundRecordingID is used to end the background task
associated with this recording. This allows a new recording to be started,
associated with a new UIBackgroundTaskIdentifier, once the movie file output's
`isRecording` property is back to false — which happens sometime after this method
returns.

Note: Since we use a unique file path for each recording, a new recording will
not overwrite a recording currently being saved.
*/
func cleanUp() {
    let path = outputFileURL.path
    if FileManager.default.fileExists(atPath: path) {
        do {
            try FileManager.default.removeItem(atPath: path)
        }
        catch {
            print("Could not remove file at url: \(outputFileURL)")
        }
    }

    if let currentBackgroundRecordingID = backgroundRecordingID {
        backgroundRecordingID = UIBackgroundTaskIdentifier.invalid

        if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
        }
    }
}
```
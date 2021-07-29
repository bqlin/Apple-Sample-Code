/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 `AssetPersistenceManager` is the main class in this sample that demonstrates how to manage downloading HLS streams.  It includes APIs for starting and canceling downloads, deleting existing assets off the users device, and monitoring the download progress.
`AssetPersistenceManager` 如何管理下载 HLS 流的主要类。它包含了用于开始、取消下载、删除存在视频和见日那个下载进度的演示。
 */

import Foundation
import AVFoundation

/// Notification for when download progress has changed.
/// 当下载进度改变时进行通知。
let AssetDownloadProgressNotification: NSNotification.Name = NSNotification.Name(rawValue: "AssetDownloadProgressNotification")

/// Notification for when the download state of an Asset has changed.
/// 当资源的下载装填改变时进行通知。
let AssetDownloadStateChangedNotification: NSNotification.Name = NSNotification.Name(rawValue: "AssetDownloadStateChangedNotification")

/// Notification for when AssetPersistenceManager has completely restored its state.
/// 当 AssetPersistenceManager 完成恢复期状态时进行通知。
let AssetPersistenceManagerDidRestoreStateNotification: NSNotification.Name = NSNotification.Name(rawValue: "AssetPersistenceManagerDidRestoreStateNotification")

class AssetPersistenceManager: NSObject {
    // MARK: Properties - 属性
    
    /// Singleton for AssetPersistenceManager.
	/// AssetPersistenceManager 的单例。
    static let sharedManager = AssetPersistenceManager()
    
    /// Internal Bool used to track if the AssetPersistenceManager finished restoring its state.
	/// 用于跟踪 AssetPersistenceManager 完成恢复期状态的内部布尔值。
    private var didRestorePersistenceManager = false
    
    /// The AVAssetDownloadURLSession to use for managing AVAssetDownloadTasks.
	/// AVAssetDownloadURLSession 用于管理 AVAssetDownloadURLSession。
    fileprivate var assetDownloadURLSession: AVAssetDownloadURLSession!
    
    /// Internal map of AVAssetDownloadTask to its corresponding Asset.
	/// 对应资产的 AVAssetDownloadTask 的映射。
    fileprivate var activeDownloadsMap = [AVAssetDownloadTask : Asset]()
    
    /// Internal map of AVAssetDownloadTask to its resoled AVMediaSelection
	/// 恢复的 AVMediaSelection 到 AVAssetDownloadTask 的映射。
    fileprivate var mediaSelectionMap = [AVAssetDownloadTask : AVMediaSelection]()
    
    /// The URL to the Library directory of the application's data container.
	/// 应用数据容器的库目录 URL。
    fileprivate let baseDownloadURL: URL
    
    // MARK: Intialization - 初始化
    
    override private init() {
        
        baseDownloadURL = URL(fileURLWithPath: NSHomeDirectory())
        
        super.init()
        
        // Create the configuration for the AVAssetDownloadURLSession.
		// 创建 AVAssetDownloadURLSession 配置。
        let backgroundConfiguration = URLSessionConfiguration.background(withIdentifier: "AAPL-Identifier")
        
        // Create the AVAssetDownloadURLSession using the configuration.
		// 通过配置创建 AVAssetDownloadURLSession。
        assetDownloadURLSession = AVAssetDownloadURLSession(configuration: backgroundConfiguration, assetDownloadDelegate: self, delegateQueue: OperationQueue.main)
    }
    
    /// Restores the Application state by getting all the AVAssetDownloadTasks and restoring their Asset structs.
	/// 通过获取所有 AVAssetDownloadTasks 并恢复其资产结构来恢复应用状态。
    func restorePersistenceManager() {
        guard !didRestorePersistenceManager else { return }
        
        didRestorePersistenceManager = true
        
        // Grab all the tasks associated with the assetDownloadURLSession
		// 抓取 assetDownloadURLSession 相关的所有任务
        assetDownloadURLSession.getAllTasks { tasksArray in
            // For each task, restore the state in the app by recreating Asset structs and reusing existing AVURLAsset objects.
			// 对每个任务，通过重新创建资产结构和重用现有的 AVURLAsset 对象恢复任务状态。
            for task in tasksArray {
                guard let assetDownloadTask = task as? AVAssetDownloadTask, let assetName = task.taskDescription else { break }
                
                let asset = Asset(name: assetName, urlAsset: assetDownloadTask.urlAsset)
                self.activeDownloadsMap[assetDownloadTask] = asset
            }
            
            NotificationCenter.default.post(name: AssetPersistenceManagerDidRestoreStateNotification, object: nil)
        }
    }
    
    /// Triggers the initial AVAssetDownloadTask for a given Asset.
	/// 为给定资产触发 AVAssetDownloadTask 的初始化
    func downloadStream(for asset: Asset) {
        /*
         For the initial download, we ask the URLSession for an AVAssetDownloadTask
         with a minimum bitrate corresponding with one of the lower bitrate variants
         in the asset.
		对首次下载，我们要求 AVAssetDownloadTask 的 URLSession 使用资产中的最小比率
         */
        guard let task = assetDownloadURLSession.makeAssetDownloadTask(asset: asset.urlAsset, assetTitle: asset.name, assetArtworkData: nil, options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 265000]) else { return }
        
        // To better track the AVAssetDownloadTask we set the taskDescription to something unique for our sample.
		// 为更好追踪 AVAssetDownloadTask，我们设置了任务描述。
        task.taskDescription = asset.name
        
        activeDownloadsMap[task] = asset
        
        task.resume()
        
        var userInfo = [String: Any]()
        userInfo[Asset.Keys.name] = asset.name
        userInfo[Asset.Keys.downloadState] = Asset.DownloadState.downloading.rawValue
        
        NotificationCenter.default.post(name: AssetDownloadStateChangedNotification, object: nil, userInfo:  userInfo)
    }
    
    /// Returns an Asset given a specific name if that Asset is asasociated with an active download.
	/// 如果资源关联了一个激活的下载，则返回资源一个给定的名称
    func assetForStream(withName name: String) -> Asset? {
        var asset: Asset?
        
        for (_, assetValue) in activeDownloadsMap {
            if name == assetValue.name {
                asset = assetValue
                break
            }
        }
        
        return asset
    }
    
    /// Returns an Asset pointing to a file on disk if it exists.
	/// 返回一个本地磁盘存在的资产
    func localAssetForStream(withName name: String) -> Asset? {
        let userDefaults = UserDefaults.standard
        guard let localFileLocation = userDefaults.value(forKey: name) as? String else { return nil }
        
        var asset: Asset?
        let url = baseDownloadURL.appendingPathComponent(localFileLocation)
        asset = Asset(name: name, urlAsset: AVURLAsset(url: url))
        
        return asset
    }
    
    /// Returns the current download state for a given Asset.
	/// 返回指定资产的下载状态
    func downloadState(for asset: Asset) -> Asset.DownloadState {
        let userDefaults = UserDefaults.standard
        
        // Check if there is a file URL stored for this asset.
		// 检查该URL是否已存储
        if let localFileLocation = userDefaults.value(forKey: asset.name) as? String{
            // Check if the file exists on disk
			// 检查是否在磁盘
            let localFilePath = baseDownloadURL.appendingPathComponent(localFileLocation).path
            
            if localFilePath == baseDownloadURL.path {
                return .notDownloaded
            }
            
            if FileManager.default.fileExists(atPath: localFilePath) {
                return .downloaded
            }
        }
        
        // Check if there are any active downloads in flight.
		// 检查是否在下载
        for (_, assetValue) in activeDownloadsMap {
            if asset.name == assetValue.name {
                return .downloading
            }
        }
        
        return .notDownloaded
    }
    
    /// Deletes an Asset on disk if possible.
	/// 如果可以的话，删除磁盘上的资源
    func deleteAsset(_ asset: Asset) {
        let userDefaults = UserDefaults.standard
        
        do {
            if let localFileLocation = userDefaults.value(forKey: asset.name) as? String {
                let localFileLocation = baseDownloadURL.appendingPathComponent(localFileLocation)
                try FileManager.default.removeItem(at: localFileLocation)
                
                userDefaults.removeObject(forKey: asset.name)
                
                var userInfo = [String: Any]()
                userInfo[Asset.Keys.name] = asset.name
                userInfo[Asset.Keys.downloadState] = Asset.DownloadState.notDownloaded.rawValue
                
                NotificationCenter.default.post(name: AssetDownloadStateChangedNotification, object: nil, userInfo:  userInfo)
            }
        } catch {
            print("An error occured deleting the file: \(error)")
        }
    }
    
    /// Cancels an AVAssetDownloadTask given an Asset.
	/// 取消给定资源的的 AVAssetDownloadTask
    func cancelDownload(for asset: Asset) {
        var task: AVAssetDownloadTask?
        
        for (taskKey, assetVal) in activeDownloadsMap {
            if asset == assetVal  {
                task = taskKey
                break
            }
        }
        
        task?.cancel()
    }
    
    // MARK: Convenience - 便利方法
    
    /**
     This function demonstrates returns the next `AVMediaSelectionGroup` and
     `AVMediaSelectionOption` that should be downloaded if needed. This is done
     by querying an `AVURLAsset`'s `AVAssetCache` for its available `AVMediaSelection`
     and comparing it to the remote versions.
	该函数演示了，返回下一需要下载的 `AVMediaSelectionGroup` 和 `AVMediaSelectionOption`。这通过查询 AVURLAsset 对 AVMediaSelection 可用的 AVAssetCache，并对比远程的版本来实现的。
     */
    fileprivate func nextMediaSelection(_ asset: AVURLAsset) -> (mediaSelectionGroup: AVMediaSelectionGroup?, mediaSelectionOption: AVMediaSelectionOption?) {
        guard let assetCache = asset.assetCache else { return (nil, nil) }
        
        let mediaCharacteristics = [AVMediaCharacteristicAudible, AVMediaCharacteristicLegible]
        
        for mediaCharacteristic in mediaCharacteristics {
            if let mediaSelectionGroup = asset.mediaSelectionGroup(forMediaCharacteristic: mediaCharacteristic) {
                let savedOptions = assetCache.mediaSelectionOptions(in: mediaSelectionGroup)
                
                if savedOptions.count < mediaSelectionGroup.options.count {
                    // There are still media options left to download.
					// 仍有媒体项在下载
                    for option in mediaSelectionGroup.options {
                        if !savedOptions.contains(option) {
                            // This option has not been download.
							// 该项还没下载
                            return (mediaSelectionGroup, option)
                        }
                    }
                }
            }
        }
        
        // At this point all media options have been downloaded.
		// 此时所有的媒体项都已下载
        return (nil, nil)
    }
}

/**
 Extend `AVAssetDownloadDelegate` to conform to the `AVAssetDownloadDelegate` protocol.
 */
extension AssetPersistenceManager: AVAssetDownloadDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let userDefaults = UserDefaults.standard
        
        /*
         This is the ideal place to begin downloading additional media selections
         once the asset itself has finished downloading.
		当资产本身下载完成后是最理想下载额外的媒体项的时刻。
         */
        guard let task = task as? AVAssetDownloadTask , let asset = activeDownloadsMap.removeValue(forKey: task) else { return }
        
        // Prepare the basic userInfo dictionary that will be posted as part of our notification.
        var userInfo = [String: Any]()
        userInfo[Asset.Keys.name] = asset.name
        
        if let error = error as? NSError {
            switch (error.domain, error.code) {
            case (NSURLErrorDomain, NSURLErrorCancelled):
                /*
                 This task was canceled, you should perform cleanup using the
                 URL saved from AVAssetDownloadDelegate.urlSession(_:assetDownloadTask:didFinishDownloadingTo:).
				这任务被取消，你应清理从 AVAssetDownloadDelegate.urlSession 保存的 URL
                 */
                guard let localFileLocation = userDefaults.value(forKey: asset.name) as? String else { return }
                
                do {
                    let fileURL = baseDownloadURL.appendingPathComponent(localFileLocation)
                    try FileManager.default.removeItem(at: fileURL)
                    
                    userDefaults.removeObject(forKey: asset.name)
                } catch {
                    print("An error occured trying to delete the contents on disk for \(asset.name): \(error)")
                }
                
                userInfo[Asset.Keys.downloadState] = Asset.DownloadState.notDownloaded.rawValue
                
            case (NSURLErrorDomain, NSURLErrorUnknown):
                fatalError("Downloading HLS streams is not supported in the simulator.")
                
            default:
                fatalError("An unexpected error occured \(error.domain)")
            }
        }
        else { // 无错误
            let mediaSelectionPair = nextMediaSelection(task.urlAsset)
            
            if mediaSelectionPair.mediaSelectionGroup != nil {
                /*
                 This task did complete sucessfully. At this point the application
                 can download additional media selections if needed.
				该任务下载成功。此时，如果有需要，应用可以下载其他的媒体部分。
                 
                 To download additional `AVMediaSelection`s, you should use the
                 `AVMediaSelection` reference saved in `AVAssetDownloadDelegate.urlSession(_:assetDownloadTask:didResolve:)`.
				要下载额外的 AVMediaSelection，你应使用保存在 AVAssetDownloadDelegate.urlSession 的 AVMediaSelection 引用
                 */
                
                guard let originalMediaSelection = mediaSelectionMap[task] else { return }
                
                /*
                 There are still media selections to download.
				仍有媒体选集需下载。
                 
                 Create a mutable copy of the AVMediaSelection reference saved in
                 `AVAssetDownloadDelegate.urlSession(_:assetDownloadTask:didResolve:)`.
                 */
                let mediaSelection = originalMediaSelection.mutableCopy() as! AVMutableMediaSelection
                
                // Select the AVMediaSelectionOption in the AVMediaSelectionGroup we found earlier.
				// 选择我们之前保存在 AVMediaSelectionGroup 的 AVMediaSelectionOption。
                mediaSelection.select(mediaSelectionPair.mediaSelectionOption!, in: mediaSelectionPair.mediaSelectionGroup!)
                
                /*
                 Ask the `URLSession` to vend a new `AVAssetDownloadTask` using
                 the same `AVURLAsset` and assetTitle as before.
				要求 URLSession 通过使用相同的 AVURLAsset 和 assetTitle 声明新 AVAssetDownloadTask
                 
                 This time, the application includes the specific `AVMediaSelection`
                 to download as well as a higher bitrate.
                 */
                guard let task = assetDownloadURLSession.makeAssetDownloadTask(asset: task.urlAsset, assetTitle: asset.name, assetArtworkData: nil, options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 2000000, AVAssetDownloadTaskMediaSelectionKey: mediaSelection]) else { return }
                
                task.taskDescription = asset.name
                
                activeDownloadsMap[task] = asset
                
                task.resume()
                
                userInfo[Asset.Keys.downloadState] = Asset.DownloadState.downloading.rawValue
                userInfo[Asset.Keys.downloadSelectionDisplayName] = mediaSelectionPair.mediaSelectionOption!.displayName
            }
            else {
                // All additional media selections have been downloaded.
				// 所有额外的媒体选集都已下载
                userInfo[Asset.Keys.downloadState] = Asset.DownloadState.downloaded.rawValue
                
            }
        }
        
        NotificationCenter.default.post(name: AssetDownloadStateChangedNotification, object: nil, userInfo: userInfo)
    }
    
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        let userDefaults = UserDefaults.standard
        print("location: \(location.absoluteString)")
        /*
         This delegate callback should only be used to save the location URL
         somewhere in your application. Any additional work should be done in
         `URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:)`.
         */
        if let asset = activeDownloadsMap[assetDownloadTask] {
            
            userDefaults.set(location.relativePath, forKey: asset.name)
        }
    }
    
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        // This delegate callback should be used to provide download progress for your AVAssetDownloadTask.
        guard let asset = activeDownloadsMap[assetDownloadTask] else { return }
        
        var percentComplete = 0.0
        for value in loadedTimeRanges {
            let loadedTimeRange : CMTimeRange = value.timeRangeValue
            percentComplete += CMTimeGetSeconds(loadedTimeRange.duration) / CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
        }
        
        var userInfo = [String: Any]()
        userInfo[Asset.Keys.name] = asset.name
        userInfo[Asset.Keys.percentDownloaded] = percentComplete
        
        NotificationCenter.default.post(name: AssetDownloadProgressNotification, object: nil, userInfo:  userInfo)
    }
    
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didResolve resolvedMediaSelection: AVMediaSelection) {
        /*
         You should be sure to use this delegate callback to keep a reference
         to `resolvedMediaSelection` so that in the future you can use it to
         download additional media selections.
         */
        mediaSelectionMap[assetDownloadTask] = resolvedMediaSelection
    }
}

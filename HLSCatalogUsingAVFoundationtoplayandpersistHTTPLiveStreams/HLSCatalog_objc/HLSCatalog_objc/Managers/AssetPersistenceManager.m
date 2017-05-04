//
//  AssetPersistenceManager.m
//  HLSCatalog_objc
//
//  Created by LinBq on 16/12/12.
//  Copyright © 2016年 POLYV. All rights reserved.
//

#import "AssetPersistenceManager.h"
@import Foundation;
@import AVFoundation;

/// 下载进度改变时通知
static NSString * const AssetDownloadProgressNotification = @"AssetDownloadProgressNotification";
/// 下载状态改变时通知
static NSString * const AssetDownloadStateChangedNotification = @"AssetDownloadStateChangedNotification";
/// 状态恢复时通知
static NSString * const AssetPersistenceManagerDidRestoreStateNotification = @"AssetPersistenceManagerDidRestoreStateNotification";

/// mediaSelectionGroup key
static NSString * const MediaSelectionGroupKey = @"MediaSelectionGroupKey";
/// AVMediaSelectionOption key
static NSString * const MediaSelectionOptionKey = @"MediaSelectionOptionKey";

@interface AssetPersistenceManager ()<AVAssetDownloadDelegate>
/// 用于跟踪 AssetPersistenceManager 完成恢复期状态的内部布尔值
@property (nonatomic, assign) BOOL didRestorePersistenceManager;

/// AVAssetDownloadURLSession 用于管理 AVAssetDownloadURLSession
@property (nonatomic, strong) AVAssetDownloadURLSession *assetDownloadURLSession;

/// 对应资产的 AVAssetDownloadTask 的映射
@property (nonatomic, strong) NSMutableDictionary<AVAssetDownloadTask *, Asset *> *activeDownloadsMap;

/// 恢复的 AVMediaSelection 到 AVAssetDownloadTask 的映射
@property (nonatomic, strong) NSMutableDictionary<AVAssetDownloadTask *, AVMediaSelection *> *mediaSelectionMap;

/// 应用数据容器的库目录 URL
@property (nonatomic, strong) NSURL *baseDownloadURL;

@end

@implementation AssetPersistenceManager

#pragma mark - 存取器
- (NSMutableDictionary<AVAssetDownloadTask *,Asset *> *)activeDownloadsMap{
	if (!_activeDownloadsMap) {
		_activeDownloadsMap = [NSMutableDictionary dictionary];
	}
	return _activeDownloadsMap;
}

- (NSMutableDictionary<AVAssetDownloadTask *,AVMediaSelection *> *)mediaSelectionMap{
	if (!_mediaSelectionMap) {
		_mediaSelectionMap = [NSMutableDictionary dictionary];
	}
	return _mediaSelectionMap;
}

#pragma mark - 初始化

+ (instancetype)sharedManager {
	static id _sharedManager = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		_sharedManager = [[self alloc] init];
	});
	
	return _sharedManager;
}

- (instancetype)init{
	if (self = [super init]) {
		NSURLSessionConfiguration *backgroundConfiguration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"AAPL-Identifier"];
		_assetDownloadURLSession = [AVAssetDownloadURLSession sessionWithConfiguration:backgroundConfiguration assetDownloadDelegate:self delegateQueue:NSOperationQueue.mainQueue];
		
	}
	return self;
}

/// 恢复
- (void)restorePersistenceManager{
	if (!self.didRestorePersistenceManager) return;
	
	self.didRestorePersistenceManager = YES;
	
	// 抓取任务
	[self.assetDownloadURLSession getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> * _Nonnull tasks) {
		for (AVAssetDownloadTask *assetDownloadTask in tasks) {
			if (![assetDownloadTask isKindOfClass:[AVAssetDownloadTask class]]) break;
			Asset *asset = [Asset assetWithName:assetDownloadTask.taskDescription urlAsset:assetDownloadTask.URLAsset];
			self.activeDownloadsMap[assetDownloadTask] = asset;
		}
		
		[[NSNotificationCenter defaultCenter] postNotificationName:AssetPersistenceManagerDidRestoreStateNotification object:nil];
	}];
}

/// 为给定资产触发 AVAssetDownloadTask 的初始化
- (void)downloadStreamForAsset:(Asset *)asset{
	AVAssetDownloadTask *task = [self.assetDownloadURLSession assetDownloadTaskWithURLAsset:asset.urlAsset assetTitle:asset.name assetArtworkData:nil options:@{AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: @265000}];
	if (!task) return;
	
	task.taskDescription = asset.name;
	self.activeDownloadsMap[task] = asset;
	[task resume];
	
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
	userInfo[AssetNameKey] = asset.name;
	userInfo[AssetDownloadStateKey] = @(AssetDownloadStateDownloading);
	
	[[NSNotificationCenter defaultCenter] postNotificationName:AssetDownloadStateChangedNotification object:nil userInfo:userInfo];
}

/// 获取资源
- (Asset *)assetForStreamWithName:(NSString *)name{
	Asset *asset;
	for (Asset *assetValue in self.activeDownloadsMap.allValues) {
		if ([name isEqualToString:assetValue.name]) {
			asset = assetValue;
			break;
		}
	}
	return asset;
}

/// 获取本地资源
- (Asset *)localAssetForStreamWithName:(NSString *)name{
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	NSString *localFileLocation = [userDefaults valueForKey:name];
	if (!localFileLocation) return nil;
	
	Asset *asset;
	NSURL *url = [self.baseDownloadURL URLByAppendingPathComponent:localFileLocation];
	asset = [Asset assetWithName:name urlAsset:[AVURLAsset assetWithURL:url]];
	
	return asset;
}

/// 获取下载状态
- (AssetDownloadState)downloadStateForAsset:(Asset *)asset{
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	NSString *localFileLocation = [userDefaults valueForKey:asset.name];
	if (localFileLocation) {
		// 检查是否在磁盘
		NSString *localFilePath = [self.baseDownloadURL URLByAppendingPathComponent:localFileLocation].path;
		if ([localFilePath isEqualToString:self.baseDownloadURL.path]) {
			return AssetDownloadStateNotDownloaded;
		}
		
		if ([[NSFileManager defaultManager] fileExistsAtPath:localFilePath]) {
			return AssetDownloadStateDownloaded;
		}
	}
	
	// 检查是否正在下载
	for (Asset *assetValue in self.activeDownloadsMap.allValues) {
		if ([asset.name isEqualToString:assetValue.name]) {
			return AssetDownloadStateDownloading;
		}
	}
	return AssetDownloadStateNotDownloaded;
}

/// 删除资源
- (void)deleteAsset:(Asset *)asset{
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	
	NSError *error = nil;
	@try {
		NSString *localFileLocation = [userDefaults valueForKey:asset.name];
		if (localFileLocation) {
			localFileLocation = [self.baseDownloadURL URLByAppendingPathComponent:localFileLocation].path;
			[[NSFileManager defaultManager] removeItemAtPath:localFileLocation error:&error];
			
			[userDefaults removeObjectForKey:asset.name];
			
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			userInfo[AssetNameKey] = asset.name;
			userInfo[AssetDownloadStateKey] = @(AssetDownloadStateNotDownloaded);
			
			[[NSNotificationCenter defaultCenter] postNotificationName:AssetDownloadStateChangedNotification object:nil userInfo:userInfo];
		}
	}
	@catch (NSException *exception) {
		NSLog(@"An error occured deleting the file: %@\n%@", exception, error.localizedDescription);
	}
}

/// 取消给定资源对应的下载任务
- (void)cancelDownloadForAsset:(Asset *)asset{
	AVAssetDownloadTask *task = nil;
	for (AVAssetDownloadTask *taskKey in self.activeDownloadsMap) {
		if ([asset isEqual:self.activeDownloadsMap[taskKey]]) {
			task = taskKey;
			break;
		}
	}
	[task cancel];
}

#pragma mark - 便利方法
- (NSDictionary *)nextMediaSelection:(AVURLAsset *)asset{
	AVAssetCache *assetCache = asset.assetCache;
	if (!assetCache) return nil;
	
	NSArray *mediaCharacteristics = @[AVMediaCharacteristicAudible, AVMediaCharacteristicLegible];
	
	for (NSString *mediaCharacteristic in mediaCharacteristics) {
		AVMediaSelectionGroup *mediaSelectionGroup = [asset mediaSelectionGroupForMediaCharacteristic:mediaCharacteristic];
		if (mediaSelectionGroup) {
			NSArray *savedOptions = [assetCache mediaSelectionOptionsInMediaSelectionGroup:mediaSelectionGroup];
			
			if (savedOptions.count < mediaSelectionGroup.options.count) {
				// 仍有媒体项在下载
				for (AVMediaSelectionOption *option in mediaSelectionGroup.options) {
					// 该项还没下载
					if (![savedOptions containsObject:option]) return @{MediaSelectionGroupKey: mediaSelectionGroup, MediaSelectionOptionKey: option};
				}
			}
		}
	}
	// 此时所有媒体项都已下载
	return nil;
}

#pragma mark - AVAssetDownloadDelegate
- (void)URLSession:(NSURLSession *)session task:(AVAssetDownloadTask *)task didCompleteWithError:(NSError *)error{
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	
	Asset *asset = self.activeDownloadsMap[task];
	[self.activeDownloadsMap removeObjectForKey:task];
	if (!asset) return;
	
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
	
	if (error) {
		if ([error.domain isEqualToString:NSURLErrorDomain]) {
			switch (error.code) {
				case NSURLErrorCancelled:{
					// 任务被取消，进行清理
					NSString *localFileLocation = [userDefaults valueForKey:asset.name];
					if (!localFileLocation) break;
					NSString *filePath = [self.baseDownloadURL URLByAppendingPathComponent:localFileLocation].path;
					NSError *error;
					[[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
					if (error) NSLog(@"An error occured trying to delete the contents on disk for %@: %@", asset.name, error);
					
					userInfo[AssetDownloadStateKey] = @(AssetDownloadStateNotDownloaded);
				}break;
				case NSURLErrorUnknown:{
					NSLog(@"Downloading HLS streams is not supported in the simulator.");
				}break;
					//			case 2:{
					//
					//			}break;
					//			case 3:{
					//
					//			}break;
					//			case 4:{
					//
					//			}break;
					//			case 5:{
					//
					//			}break;
				default:{
					NSLog(@"An unexpected error occured %@", error.domain);
				}break;
			}
		}else{
			NSLog(@"An unexpected error occured %@", error.domain);
		}
	}else{ // 无错误
		NSDictionary *mediaSelectionPair = [self nextMediaSelection:[task URLAsset]];
		if (mediaSelectionPair.allValues.count) {
			// 该任务下载成功。此时，如果有需要，应用可以下载其他的媒体部分。
			// 要下载额外的 AVMediaSelection，你应使用保存在 AVAssetDownloadDelegate.urlSession 的 AVMediaSelection 引用
			AVMediaSelection *originalMediaSelection = self.mediaSelectionMap[task];
			if (!originalMediaSelection) return;
			// 仍有媒体下载
			AVMutableMediaSelection *mediaSelection = originalMediaSelection.mutableCopy;
			// 选择我们之前保存在 AVMediaSelectionGroup 的 AVMediaSelectionOption
			[mediaSelection selectMediaOption:mediaSelectionPair[MediaSelectionOptionKey] inMediaSelectionGroup:mediaSelectionPair[MediaSelectionGroupKey]];
			// 要求 URLSession 通过使用相同的 AVURLAsset 和 assetTitle 声明新 AVAssetDownloadTask
			AVAssetDownloadTask *assetDonwloadTask = [self.assetDownloadURLSession assetDownloadTaskWithURLAsset:[task URLAsset] assetTitle:asset.name assetArtworkData:nil options:@{AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: @2000000, AVAssetDownloadTaskMediaSelectionKey: mediaSelection}];
			if (!assetDonwloadTask) return;
			assetDonwloadTask.taskDescription = asset.name;
			self.activeDownloadsMap[assetDonwloadTask] = asset;
			[assetDonwloadTask resume];
			userInfo[AssetDownloadStateKey] = @(AssetDownloadStateDownloading);
			userInfo[AssetDownloadSelectionDisplayNameKey] = [(AVMediaSelectionOption *)mediaSelectionPair[MediaSelectionOptionKey] displayName];
		}else{
			// 所有额外的媒体选集都已下载
			userInfo[AssetDownloadStateKey] = @(AssetDownloadStateDownloaded);
		}
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:AssetDownloadStateChangedNotification object:nil userInfo:userInfo];
}

/// Called when a download task has finished downloading a requested asset.
- (void)URLSession:(NSURLSession *)session assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask didFinishDownloadingToURL:(NSURL *)location{
	Asset *asset = self.activeDownloadsMap[assetDownloadTask];
	if (!asset) return;
	NSUserDefaults *userDefaluts = [NSUserDefaults standardUserDefaults];
	[userDefaluts setValue:location.relativePath forKey:asset.name];
}

/// Called a to update the delegate of progress updates occuring in the download task
- (void)URLSession:(NSURLSession *)session assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask didLoadTimeRange:(CMTimeRange)timeRange totalTimeRangesLoaded:(NSArray<NSValue *> *)loadedTimeRanges timeRangeExpectedToLoad:(CMTimeRange)timeRangeExpectedToLoad{
	// 该代理应用于提供下载进度
	Asset *asset = self.activeDownloadsMap[assetDownloadTask];
	if (!asset) return;
	
	CGFloat percentComplete = 0.0;
	for (NSValue *value in loadedTimeRanges) {
		CMTimeRange loadedTimeRange = value.CMTimeRangeValue;
		percentComplete += CMTimeGetSeconds(loadedTimeRange.duration) / CMTimeGetSeconds(timeRangeExpectedToLoad.duration);
	}
	
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
	userInfo[AssetNameKey] = asset.name;
	userInfo[AssetPercentDownloadedKey] = @(percentComplete);
	[[NSNotificationCenter defaultCenter] postNotificationName:AssetDownloadProgressNotification object:nil userInfo:userInfo];
}

/// Called when the media selection for the download is fully resolved, including any automatic selections.
- (void)URLSession:(NSURLSession *)session assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask didResolveMediaSelection:(AVMediaSelection *)resolvedMediaSelection{
	self.mediaSelectionMap[assetDownloadTask] = resolvedMediaSelection;
}



@end

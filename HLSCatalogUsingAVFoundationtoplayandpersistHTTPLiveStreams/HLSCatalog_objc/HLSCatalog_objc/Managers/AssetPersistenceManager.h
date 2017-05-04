//
//  AssetPersistenceManager.h
//  HLSCatalog_objc
//
//  Created by LinBq on 16/12/12.
//  Copyright © 2016年 POLYV. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Asset.h"

@interface AssetPersistenceManager : NSObject

+ (instancetype)sharedManager;

/// 恢复
- (void)restorePersistenceManager;

/// 为给定资产触发 AVAssetDownloadTask 的初始化
- (void)downloadStreamForAsset:(Asset *)asset;

/// 获取资源
- (Asset *)assetForStreamWithName:(NSString *)name;

/// 获取本地资源
- (Asset *)localAssetForStreamWithName:(NSString *)name;

/// 获取下载状态
- (AssetDownloadState)downloadStateForAsset:(Asset *)asset;

/// 删除资源
- (void)deleteAsset:(Asset *)asset;

/// 取消给定资源对应的下载任务
- (void)cancelDownloadForAsset:(Asset *)asset;

@end

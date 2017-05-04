//
//  Asset.h
//  HLSCatalog_objc
//
//  Created by LinBq on 16/12/12.
//  Copyright © 2016年 POLYV. All rights reserved.
//

#import <Foundation/Foundation.h>
@import AVFoundation;

typedef NS_ENUM(NSUInteger, AssetDownloadState) {
	AssetDownloadStateNotDownloaded,
	AssetDownloadStateDownloading,
	AssetDownloadStateDownloaded,
};

static NSString * const AssetNameKey = @"AssetNameKey";
static NSString * const AssetPercentDownloadedKey = @"AssetPercentDownloadedKey";
static NSString * const AssetDownloadStateKey = @"AssetDownloadStateKey";
static NSString * const AssetDownloadSelectionDisplayNameKey = @"AssetDownloadSelectionDisplayNameKey";

@interface Asset : NSObject

/// 资源名称
@property (nonatomic, copy) NSString *name;

/// 资源对应的 AVURLAsset
@property (nonatomic, strong) AVURLAsset *urlAsset;

+ (instancetype)assetWithName:(NSString *)name urlAsset:(AVURLAsset *)urlAsset;

@end

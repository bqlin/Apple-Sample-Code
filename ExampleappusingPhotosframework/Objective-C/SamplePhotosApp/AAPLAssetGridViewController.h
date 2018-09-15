/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 A view controller displaying a grid of assets.
 */

@import UIKit;
@import Photos;

@interface AAPLAssetGridViewController : UICollectionViewController

/// 相册内容
@property (nonatomic, strong) PHFetchResult *assetsFetchResults;

/// 相册
@property (nonatomic, strong) PHAssetCollection *assetCollection;

@end

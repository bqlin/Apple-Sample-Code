//
//  Asset.m
//  HLSCatalog_objc
//
//  Created by LinBq on 16/12/12.
//  Copyright © 2016年 POLYV. All rights reserved.
//

#import "Asset.h"


@interface Asset ()

@end

@implementation Asset

- (BOOL)isEqual:(Asset *)object{
	if (!object) return NO;
	if (![object isKindOfClass:self.class]) return NO;
	return [self.name isEqualToString:object.name];
}

- (NSUInteger)hash{
	return self.name.hash ^ self.urlAsset.hash;
}

+ (instancetype)assetWithName:(NSString *)name urlAsset:(AVURLAsset *)urlAsset{
	Asset *asset = [Asset new];
	asset.name = name;
	asset.urlAsset = urlAsset;
	return asset;
}

@end

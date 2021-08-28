//
// Created by Bq Lin on 2021/8/28.
// Copyright © 2021 Bq. All rights reserved.
//

#import <Foundation/Foundation.h>
@import Metal;

@interface Util : NSObject

+ (id<MTLBuffer>)makeVertexBufferAndInfo:(NSMutableArray *)info device:(id<MTLDevice>)device;

@end

//
//  FilterRendererUtil.h
//  AVCamPhotoFilter
//
//  Created by bqlin on 2018/9/3.
//  Copyright © 2018年 Bq. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

// FourCharCode 转 char*
#if TARGET_RT_BIG_ENDIAN
#   define FourCC2Str(fourcc) (const char[]){*((char*)&fourcc), *(((char*)&fourcc)+1), *(((char*)&fourcc)+2), *(((char*)&fourcc)+3),0}
#else
#   define FourCC2Str(fourcc) (const char[]){*(((char*)&fourcc)+3), *(((char*)&fourcc)+2), *(((char*)&fourcc)+1), *(((char*)&fourcc)+0),0}
#endif

typedef NSArray* ArrayTuple;
static const NSUInteger kOutputBufferPoolTupleKey = 0;
static const NSUInteger kOutputColorSpaceTupleKey = 1;
static const NSUInteger kOutputFormatDescription = 2;

@interface FilterRendererUtil : NSObject

/// @return [outputBufferPool: CVPixelBufferPool?, outputColorSpace: CGColorSpace?, outputFormatDescription: CMFormatDescription?]
+ (ArrayTuple)allocateOutputBufferPoolWithInputFormatDescription:(CMFormatDescriptionRef)inputFormatDescription outputRetainedBufferCountHint:(NSInteger)outputRetainedBufferCountHint;

@end

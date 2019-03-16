/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 
  Annotation writer class which writes a given set of timed metadata groups into a movie file.
  
 */

@import Foundation;
@import AVFoundation;

/// 圆形中点坐标
NSString *const AAPLTimedAnnotationWriterCircleCenterCoordinateIdentifier;
/// 圆形半径
NSString *const AAPLTimedAnnotationWriterCircleRadiusIdentifier;
/// 评论内容
NSString *const AAPLTimedAnnotationWriterCommentFieldIdentifier;

@interface AAPLTimedAnnotationWriter : NSObject

- (instancetype)initWithAsset:(AVAsset *)asset;
- (void)writeMetadataGroups:(NSArray *)metadataGroups;

@property (readonly) NSURL *outputURL;

@end

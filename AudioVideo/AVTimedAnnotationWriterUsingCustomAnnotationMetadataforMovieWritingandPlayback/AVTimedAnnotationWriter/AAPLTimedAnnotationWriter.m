/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 
  Annotation writer class which writes a given set of timed metadata groups into a movie file.
  
 */

#import "AAPLTimedAnnotationWriter.h"
#import <CoreMedia/CoreMedia.h>
#import <CoreMedia/CMMetadata.h>

NSString *const AAPLTimedAnnotationWriterCircleCenterCoordinateIdentifier = @"mdta/com.example.circle.center.coordinate";
NSString *const AAPLTimedAnnotationWriterCircleRadiusIdentifier = @"mdta/com.example.circle.radius";
NSString *const AAPLTimedAnnotationWriterCommentFieldIdentifier = @"mdta/com.example.comment.field";

@protocol AAPLAssetWriterInputSampleProvider <NSObject>

@optional
- (CMSampleBufferRef)copyNextSampleBuffer;
// 只有元数据的提供者才会该方法吧？
- (AVTimedMetadataGroup *)copyNextTimedMetadataGroup;

@end

/// 对 AVAssetReaderTrackOutput 扩展 AAPLAssetWriterInputSampleProvider 协议的两个方法
@interface AVAssetReaderTrackOutput (SampleProvider) <AAPLAssetWriterInputSampleProvider>
// AVAssetReader 有 -copyNextSampleBuffer 方法实现，但没 -copyNextTimedMetadataGroup 方法实现

@end

/// 元数据供应者
@interface AVMetadataSampleProvider : NSObject <AAPLAssetWriterInputSampleProvider>
{
@private
    NSArray					*metadataSamples;
	/// 当前读取的样本索引
    NSUInteger				currentSampleNum;
	// metadataSamples 的个数
    NSUInteger				numOfSamples;
};

- (id)initWithMetadataSamples:(NSArray *)samples;

@end

/// sampleBuffer 轨道封装
@interface AVSampleBufferChannel : NSObject
{
@private
    id<AAPLAssetWriterInputSampleProvider>	sampleProvider;
    AVAssetWriterInput						*assetWriterInput;
    AVAssetWriterInputMetadataAdaptor		*assetWriterAdaptor;
    
    dispatch_block_t						completionHandler;
	/// 序列化串行队列
    dispatch_queue_t						serializationQueue;
    BOOL									finished;  // only accessed on serialization queue
}

- (id)initWithSampleProvider:(id<AAPLAssetWriterInputSampleProvider>)sampleProvider assetWriterInput:(AVAssetWriterInput *)assetWriterInput assetWriterAdaptor:(AVAssetWriterInputMetadataAdaptor *)adaptor;
- (void)startReadingAndWritingWithCompletionHandler:(dispatch_block_t)completionHandler;
- (void)cancel;

@end

/*
	AAPLTimedAnnotationWriter
															   -------------------------------
				 ----> Audio (AVAssetReaderTrackOutput) ----> | Audio (AVSampleBufferChannel) |    ---->
				|											   -------------------------------			|
	Media File -|																						|
				|											   -------------------------------			| AVAssetWriter
				 ----> Video (AVAssetReaderTrackOutput) ----> | Video (AVSampleBufferChannel) |    ---->| -------------> Output Media File 
															   -------------------------------			|
																										|
															   ----------------------------------		|
		  Metadata (AVMetadataSampleProvider)			----> | Metadata (AVSampleBufferChannel) | ---->
															   ----------------------------------
 */

/// 注解写入器
@interface AAPLTimedAnnotationWriter ()
{
	/// 序列化队列，串行
	dispatch_queue_t			serializationQueue;
	/// 全局信号量
	dispatch_semaphore_t		globalDispatchSemaphore;
	
	// All of these are created, accessed, and torn down exclusively on the serializaton queue
	AVAssetReader				*assetReader;
	AVAssetWriter				*assetWriter;
	
	AVSampleBufferChannel		*audioSampleBufferChannel;
	AVSampleBufferChannel		*videoSampleBufferChannel;
	AVSampleBufferChannel		*metadataSampleBufferChannel;
}

@property AVAsset	*sourceAsset;
@property NSArray   *metadataGroups;
/// tmp/Movie.MOV
@property NSURL		*destinationAssetURL;

@end

@implementation AAPLTimedAnnotationWriter

- (instancetype)initWithAsset:(AVAsset *)asset
{
	self = [super init];
	
	if (self)
	{
		self.sourceAsset = asset;
		
		NSString *serializationQueueDescription = [NSString stringWithFormat:@"%@ serialization queue", self];
		serializationQueue = dispatch_queue_create([serializationQueueDescription UTF8String], NULL);
		
		globalDispatchSemaphore = dispatch_semaphore_create(0);
		
		// The temporary path for the video before saving it to the photo album
		self.destinationAssetURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@%@", NSTemporaryDirectory(), @"Movie.MOV"]];
	}
	
	return self;
}

- (NSURL *)outputURL
{
	return self.destinationAssetURL;
}

/// 写入元数据组
- (void)writeMetadataGroups:(NSArray *)metadataGroups
{
	self.metadataGroups = metadataGroups;
	
	dispatch_async(serializationQueue, ^{
		
		BOOL success = YES;
		NSError *localError = nil;
		
		success = ([self.sourceAsset statusOfValueForKey:@"tracks" error:&localError] == AVKeyValueStatusLoaded);
		
		if (success)
		{
			// 先移除已存在的导出资源
			// AVAssetWriter does not overwrite files for us, so remove the destination file if it already exists
			NSFileManager *fm = [NSFileManager defaultManager];
			NSString *localOutputPath = [self.destinationAssetURL path];
			if ([fm fileExistsAtPath:localOutputPath])
				success = [fm removeItemAtPath:localOutputPath error:&localError];
		}
		
		// 配置 reader 和 writer，并开始读取与写入
		// Set up the AVAssetReader and AVAssetWriter, then begin writing samples or flag an error
		if (success)
			success = [self setUpReaderAndWriterReturningError:&localError];
		if (success)
			success = [self startReadingAndWritingReturningError:&localError];
		if (!success)
			[self readingAndWritingDidFinishSuccessfully:success withError:localError];
	});
	
	// Wait for export to complete so we can return movie URL
	dispatch_semaphore_wait(globalDispatchSemaphore, DISPATCH_TIME_FOREVER);
}

/// 配置 reader 和 writer
- (BOOL)setUpReaderAndWriterReturningError:(NSError **)outError
{
	BOOL success = YES;
	NSError *localError = nil;
	AVAsset *localAsset = self.sourceAsset;
	NSURL *localOutputURL = self.destinationAssetURL;
	
	// 创建 reader 和 writer
	// Create asset reader and asset writer
	assetReader = [[AVAssetReader alloc] initWithAsset:localAsset error:&localError];
	success = (assetReader != nil);
	if (success) {
		assetWriter = [[AVAssetWriter alloc] initWithURL:localOutputURL fileType:AVFileTypeQuickTimeMovie error:&localError];
		success = (assetWriter != nil);
	}
	
	// 创建音频、视频轨道的 trackOuput 和 writerInput
	// Create asset reader outputs and asset writer inputs for the first audio track and first video track of the asset
	if (success) {
		// 获取音频和视频轨道
		// Grab first audio track and first video track, if the asset has them
		AVAssetTrack *audioTrack = nil, *videoTrack = nil;
		NSArray *audioTracks = [localAsset tracksWithMediaType:AVMediaTypeAudio];
		if ([audioTracks count] > 0)
			audioTrack = [audioTracks objectAtIndex:0];
		NSArray *videoTracks = [localAsset tracksWithMediaType:AVMediaTypeVideo];
		if ([videoTracks count] > 0)
			videoTrack = [videoTracks objectAtIndex:0];
		
		// Setup passthrough for audio and video tracks
		if (audioTrack)
		{
			AVAssetReaderTrackOutput *audioOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:audioTrack outputSettings:nil];
			[assetReader addOutput:audioOutput];
			
			AVAssetWriterInput *audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:[audioTrack mediaType] outputSettings:nil];
			[assetWriter addInput:audioInput];
			
			// Create and save an instance of AVSampleBufferChannel, which will coordinate the work of reading and writing sample buffers
			audioSampleBufferChannel = [[AVSampleBufferChannel alloc] initWithSampleProvider:audioOutput assetWriterInput:audioInput assetWriterAdaptor:nil];
		}
		
		if (videoTrack)
		{
			AVAssetReaderTrackOutput *videoOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack outputSettings:nil];
			[assetReader addOutput:videoOutput];
			
			AVAssetWriterInput *videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:[videoTrack mediaType] outputSettings:nil];
			[assetWriter addInput:videoInput];
			
			// Create and save an instance of AVSampleBufferChannel, which will coordinate the work of reading and writing sample buffers
			videoSampleBufferChannel = [[AVSampleBufferChannel alloc] initWithSampleProvider:videoOutput assetWriterInput:videoInput assetWriterAdaptor:nil];
			
			//
			// Setup metadata track in order to write metadata samples
			CMFormatDescriptionRef metadataFormatDescription = NULL;
			NSArray *specs =
			@[
			  @{(__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier : AAPLTimedAnnotationWriterCircleCenterCoordinateIdentifier,
				(__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType : (__bridge NSString *)kCMMetadataBaseDataType_PointF32},
			  @{(__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier : AAPLTimedAnnotationWriterCircleRadiusIdentifier,
				(__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType : (__bridge NSString *)kCMMetadataBaseDataType_Float64},
			  @{(__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier : AAPLTimedAnnotationWriterCommentFieldIdentifier,
				(__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType : (__bridge NSString *)kCMMetadataBaseDataType_UTF8}];
			
			
			OSStatus err = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(kCFAllocatorDefault, kCMMetadataFormatType_Boxed, (__bridge CFArrayRef)specs, &metadataFormatDescription);
			if (!err)
			{
				// 用上面的配置信息创建 AVAssetWriterInput 和 AVAssetWriterInputMetadataAdaptor
				AVAssetWriterInput *assetWriterMetadataIn = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeMetadata outputSettings:nil sourceFormatHint:metadataFormatDescription];
				AVAssetWriterInputMetadataAdaptor *assetWriterMetadataAdaptor = [AVAssetWriterInputMetadataAdaptor assetWriterInputMetadataAdaptorWithAssetWriterInput:assetWriterMetadataIn];
				assetWriterMetadataIn.expectsMediaDataInRealTime = YES;
				
				// 元数据关联到视频轨道
				[assetWriterMetadataIn addTrackAssociationWithTrackOfInput:videoInput type:AVTrackAssociationTypeMetadataReferent];
				[assetWriter addInput:assetWriterMetadataIn];
				
				// 创建元数据数据源
				AVMetadataSampleProvider *metadataSampleProvider = [[AVMetadataSampleProvider alloc] initWithMetadataSamples:self.metadataGroups];
				
				metadataSampleBufferChannel = [[AVSampleBufferChannel alloc] initWithSampleProvider:metadataSampleProvider assetWriterInput:assetWriterMetadataIn assetWriterAdaptor:assetWriterMetadataAdaptor];
			}
			else
			{
				NSLog(@"CMMetadataFormatDescriptionCreateWithMetadataSpecifications failed with error %d", (int)err);
			}
		}
		
	}
	
	if (!success && outError)
		*outError = localError;
	
	return success;
}

/// 开始读取与写入
- (BOOL)startReadingAndWritingReturningError:(NSError **)outError
{
	BOOL success = YES;
	NSError *localError = nil;
	
	// Instruct the asset reader and asset writer to get ready to do work
	success = [assetReader startReading];
	if (!success)
		localError = [assetReader error];
	if (success) {
		success = [assetWriter startWriting];
		if (!success)
			localError = [assetWriter error];
	}
	
	if (success) {
		// Start a sample-writing session
		[assetWriter startSessionAtSourceTime:kCMTimeZero];
		
		dispatch_group_t dispatchGroup = dispatch_group_create();
		
		// Start reading and writing samples
		if (audioSampleBufferChannel) {
			dispatch_group_enter(dispatchGroup);
			[audioSampleBufferChannel startReadingAndWritingWithCompletionHandler:^{
				dispatch_group_leave(dispatchGroup);
			}];
		}
		if (videoSampleBufferChannel) {
			dispatch_group_enter(dispatchGroup);
			[videoSampleBufferChannel startReadingAndWritingWithCompletionHandler:^{
				dispatch_group_leave(dispatchGroup);
			}];
		}
		if (metadataSampleBufferChannel) {
			dispatch_group_enter(dispatchGroup);
			[metadataSampleBufferChannel startReadingAndWritingWithCompletionHandler:^{
				dispatch_group_leave(dispatchGroup);
			}];
		}
		
		// Set up a callback for when the sample writing is finished
		dispatch_group_notify(dispatchGroup, serializationQueue, ^{
			__block BOOL finalSuccess = YES;
			NSError *finalError = nil;
			
			if ([assetReader status] == AVAssetReaderStatusFailed) {
				finalSuccess = NO;
				finalError = [assetReader error];
			}
			
			if (finalSuccess) {
				dispatch_group_enter(dispatchGroup);
				
				[assetWriter finishWritingWithCompletionHandler:^{
					
					finalSuccess = ([assetWriter status] == AVAssetWriterStatusCompleted) ? YES : NO;
					
					dispatch_group_leave(dispatchGroup);
					
				}];
				
				dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
				
				if (!finalSuccess) {
					
					finalError = [assetWriter error];
					
					[self readingAndWritingDidFinishSuccessfully:finalSuccess withError:finalError];
					
				}
				
				dispatch_semaphore_signal(globalDispatchSemaphore);
			}
		});
	}
	
	if (!success && outError)
		*outError = localError;
	
	return success;
}

- (void)readingAndWritingDidFinishSuccessfully:(BOOL)success withError:(NSError *)error
{
	if (!success) {
		[assetReader cancelReading];
		[assetWriter cancelWriting];
		
		NSLog(@"Writing metadata failed with the following error: %@", error);
	}
}

@end

@interface AVSampleBufferChannel ()

- (void)callCompletionHandlerIfNecessary;  // always called on the serialization queue

@end

@implementation AVSampleBufferChannel

- (id)initWithSampleProvider:(id<AAPLAssetWriterInputSampleProvider>)localSampleProvider assetWriterInput:(AVAssetWriterInput *)localAssetWriterInput assetWriterAdaptor:(AVAssetWriterInputMetadataAdaptor *)localAssetWriterAdaptor
{
	self = [super init];
	
	if (self)
	{
		sampleProvider = localSampleProvider;
		assetWriterInput = localAssetWriterInput;
		assetWriterAdaptor = localAssetWriterAdaptor;
		
		finished = NO;
		NSString *serializationQueueDescription = [NSString stringWithFormat:@"%@ serialization queue", self];
		serializationQueue = dispatch_queue_create([serializationQueueDescription UTF8String], NULL);
	}
	
	return self;
}

/// 开始读取与写入
- (void)startReadingAndWritingWithCompletionHandler:(dispatch_block_t)localCompletionHandler
{
	completionHandler = [localCompletionHandler copy];
	
	// 请求媒体数据
	[assetWriterInput requestMediaDataWhenReadyOnQueue:serializationQueue usingBlock:^{
		if (finished)
			return;
		
		BOOL completedOrFailed = NO;
		
		// 循环读取文件帧数据，直到读取完毕，在这过程中 writer 写入数据
		// Read samples in a loop as long as the asset writer input is ready
		while ([assetWriterInput isReadyForMoreMediaData] && !completedOrFailed) {
			CMSampleBufferRef sampleBuffer = NULL;
			AVTimedMetadataGroup *metadataGroup = nil;
			if ([[assetWriterInput mediaType] isEqualToString:AVMediaTypeMetadata]) // 元数据
			{
				metadataGroup = [sampleProvider copyNextTimedMetadataGroup];
			}
			else // 音频或视频轨道
			{
				sampleBuffer = [sampleProvider copyNextSampleBuffer];
			}
			
			// 分别拼接 sampleBuffer 和 timedMetadataGroup
			if (sampleBuffer != NULL) {
				BOOL success = [assetWriterInput appendSampleBuffer:sampleBuffer];
				CFRelease(sampleBuffer);
				sampleBuffer = NULL;
				
				completedOrFailed = !success;
			} else if (metadataGroup != nil) {
				BOOL success = [assetWriterAdaptor appendTimedMetadataGroup:metadataGroup];
				completedOrFailed = !success;
			} else {
				completedOrFailed = YES;
			}
			
		}
		
		if (completedOrFailed)
			[self callCompletionHandlerIfNecessary];
	}];
}

- (void)cancel
{
	dispatch_async(serializationQueue, ^{
		[self callCompletionHandlerIfNecessary];
	});
}

- (void)callCompletionHandlerIfNecessary
{
	// Set state to mark that we no longer need to call the completion handler, grab the completion handler, and clear out the ivar
	BOOL oldFinished = finished;
	finished = YES;
	
	if (oldFinished == NO) {
		[assetWriterInput markAsFinished];  // let the asset writer know that we will not be appending any more samples to this input
		
		if (completionHandler) {
			completionHandler();
		}
	}
}

@end

@implementation AVMetadataSampleProvider

- (id)initWithMetadataSamples:(NSArray *)samples
{
	self = [super init];
	
	if (self)
	{
		metadataSamples = samples;
		numOfSamples = [samples count];
		currentSampleNum = 0;
	}
	
	return self;
}

- (AVTimedMetadataGroup *)copyNextTimedMetadataGroup
{
	AVTimedMetadataGroup *group = nil;
	if (currentSampleNum < numOfSamples)
	{
		group = metadataSamples[currentSampleNum];
		currentSampleNum++;
	}
	
	return group;
}

@end

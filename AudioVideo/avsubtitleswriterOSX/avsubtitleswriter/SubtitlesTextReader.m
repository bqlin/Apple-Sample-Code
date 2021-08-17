/*
     File: SubtitlesTextReader.m
 Abstract: A class for reading subtitles text, in the form of an NSString. It will turn the text into CMSampleBufferRefs, and extract language code, extended language tag, and other metadata. See subtitles_text_en-US.txt for an example of the subtitles file format this class expects.
  Version: 1.0.1
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2013 Apple Inc. All Rights Reserved.
 
 */

#import "SubtitlesTextReader.h"
#import <AVFoundation/AVFoundation.h>

@interface Subtitle : NSObject

+ (instancetype)subtitleWithText:(NSString *)text timeRange:(CMTimeRange)timeRange forced:(BOOL)forced;
- (CMFormatDescriptionRef)copyFormatDescription;
- (CMSampleBufferRef)copySampleBuffer;

@property NSString *text;
@property CMTimeRange timeRange;
@property BOOL forced;
@property CMTextDisplayFlags displayFlags;

@end

@implementation SubtitlesTextReader
{
	NSUInteger _index;
	NSArray *_subtitles;
	BOOL _wantsSDH;
}

- (instancetype)initWithText:(NSString *)text
{
	self = [super init];
	if (self)
	{
		_index = 0;
		
		if (text)
		{
			NSMutableArray *mutableSubtitles = [NSMutableArray array];
			
			// Check for a language
			NSRegularExpression *languageExpression = [NSRegularExpression regularExpressionWithPattern:@"language: (.*)" options:0 error:nil];
			NSTextCheckingResult *languageResult = [languageExpression firstMatchInString:text options:0 range:NSMakeRange(0, [text length])];
			_languageCode = [text substringWithRange:[languageResult rangeAtIndex:1]];
			
			// Check for an extended language
			NSRegularExpression *extendedLanguageExpression = [NSRegularExpression regularExpressionWithPattern:@"extended language: (.*)" options:0 error:nil];
			NSTextCheckingResult *extendedLanguageResult = [extendedLanguageExpression firstMatchInString:text options:0 range:NSMakeRange(0, [text length])];
			_extendedLanguageTag = [text substringWithRange:[extendedLanguageResult rangeAtIndex:1]];
			
			// See if SDH has been requested
			NSRegularExpression *characteristicsExpression = [NSRegularExpression regularExpressionWithPattern:@"characteristics:.*(SDH)" options:NSRegularExpressionCaseInsensitive error:nil];
			NSTextCheckingResult *characteristicsResult = [characteristicsExpression firstMatchInString:text options:0 range:NSMakeRange(0, [text length])];
			_wantsSDH = ([[text substringWithRange:[characteristicsResult rangeAtIndex:1]] caseInsensitiveCompare:@"SDH"] == NSOrderedSame) ? YES : NO;
			
			// Find the subtitle time ranges and text
			__block int forcedCount = 0;
			NSRegularExpression *subtitlesExpression = [NSRegularExpression regularExpressionWithPattern:@"(..):(..):(..),(...) --> (..):(..):(..),(...)( !!!)?\n(.*)" options:0 error:nil];
			[subtitlesExpression enumerateMatchesInString:text options:0 range:NSMakeRange(0, [text length]) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
				// Get the text
				NSString *subtitleText = [text substringWithRange:[result rangeAtIndex:10]];
				
				// Create the time range
				double startTime = ([[text substringWithRange:[result rangeAtIndex:1]] doubleValue] * 60.0 * 60.0) + ([[text substringWithRange:[result rangeAtIndex:2]] doubleValue] * 60.0) + [[text substringWithRange:[result rangeAtIndex:3]] doubleValue] + ([[text substringWithRange:[result rangeAtIndex:4]] doubleValue] / 1000.0);
				
				double endTime = ([[text substringWithRange:[result rangeAtIndex:5]] doubleValue] * 60.0 * 60.0) + ([[text substringWithRange:[result rangeAtIndex:6]] doubleValue] * 60.0) + [[text substringWithRange:[result rangeAtIndex:7]] doubleValue] + ([[text substringWithRange:[result rangeAtIndex:8]] doubleValue] / 1000.0);
				
				CMTimeRange timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(startTime, 600), CMTimeMakeWithSeconds(endTime - startTime, 600));
				
				// Is it forced?
				BOOL forced = NO;
				if (([result rangeAtIndex:9].length > 0) && [[text substringWithRange:[result rangeAtIndex:9]] isEqualToString:@" !!!"])
				{
					forced = YES;
					forcedCount++;
				}
				
				// Stash a Subtitle object for later use by -copyNextSampleBuffer
				[mutableSubtitles addObject:[Subtitle subtitleWithText:subtitleText timeRange:timeRange forced:forced]];
			}];
			
			// Set forced subtitles display flags as appropriate.
			if ([mutableSubtitles count] == forcedCount)
			{
				for (Subtitle *subtitle in mutableSubtitles)
				{
					subtitle.displayFlags = kCMTextDisplayFlag_forcedSubtitlesPresent | kCMTextDisplayFlag_allSubtitlesForced;
				}
			}
			else if (forcedCount > 0)
			{
				for (Subtitle *subtitle in mutableSubtitles)
				{
					subtitle.displayFlags = kCMTextDisplayFlag_forcedSubtitlesPresent;
				}
			}
			
			_subtitles = [mutableSubtitles copy];
		}
	}
	return self;
}

+ (instancetype)subtitlesTextReaderWithText:(NSString *)text
{
	return [[[self class] alloc] initWithText:text];
}

- (CMFormatDescriptionRef)copyFormatDescription
{
	// Take the format description from the first object. They are all the same since the display flag are all the same.
	return [[_subtitles firstObject] copyFormatDescription];
}

- (NSArray *)metadata
{
	NSMutableArray *mutableMetadata = [NSMutableArray array];
	
	// All subtitles must have the AVMediaCharacteristicTranscribesSpokenDialogForAccessibility characteristic.
	AVMutableMetadataItem *spokenItem = [AVMutableMetadataItem metadataItem];
	[spokenItem setKey:AVMetadataQuickTimeUserDataKeyTaggedCharacteristic];
	[spokenItem setKeySpace:AVMetadataKeySpaceQuickTimeUserData];
	[spokenItem setValue:AVMediaCharacteristicTranscribesSpokenDialogForAccessibility];
	[mutableMetadata addObject:spokenItem];
	
	if (_wantsSDH)
	{
		// SDH subtitles must also have the AVMediaCharacteristicDescribesMusicAndSoundForAccessibility characteristic.
		AVMutableMetadataItem *describesItem = [AVMutableMetadataItem metadataItem];
		[describesItem setKey:AVMetadataQuickTimeUserDataKeyTaggedCharacteristic];
		[describesItem setKeySpace:AVMetadataKeySpaceQuickTimeUserData];
		[describesItem setValue:AVMediaCharacteristicDescribesMusicAndSoundForAccessibility];
		
		[mutableMetadata addObject:describesItem];
	}
	
	return [mutableMetadata copy];
}

- (CMSampleBufferRef)copyNextSampleBuffer
{
	CMSampleBufferRef sampleBuffer = NULL;
	
	if (_index < _subtitles.count)
	{
		sampleBuffer = [(Subtitle *)_subtitles[_index] copySampleBuffer];
		_index++;
	}
	
	return sampleBuffer;
}

@end

@implementation Subtitle

+ (instancetype)subtitleWithText:(NSString *)text timeRange:(CMTimeRange)timeRange forced:(BOOL)forced
{
	Subtitle *subtitle = [[Subtitle alloc] init];
	subtitle.text = text;
	subtitle.timeRange = timeRange;
	subtitle.forced = forced;
	return subtitle;
}

- (CMFormatDescriptionRef)copyFormatDescription
{
	// Create a subtitle 3g text format description with extensions
	NSDictionary *extensions = @{(id)kCMTextFormatDescriptionExtension_DisplayFlags : @(self.displayFlags),
								 (id)kCMTextFormatDescriptionExtension_BackgroundColor : @{
										 (id)kCMTextFormatDescriptionColor_Red : @0,
										 (id)kCMTextFormatDescriptionColor_Green : @0,
										 (id)kCMTextFormatDescriptionColor_Blue : @0,
										 (id)kCMTextFormatDescriptionColor_Alpha : @255},
								 (id)kCMTextFormatDescriptionExtension_DefaultTextBox : @{
										 (id)kCMTextFormatDescriptionRect_Top : @0,
										 (id)kCMTextFormatDescriptionRect_Left : @0,
										 (id)kCMTextFormatDescriptionRect_Bottom : @0,
										 (id)kCMTextFormatDescriptionRect_Right : @0},
								 (id)kCMTextFormatDescriptionExtension_DefaultStyle : @{
										 (id)kCMTextFormatDescriptionStyle_StartChar : @0,
										 (id)kCMTextFormatDescriptionStyle_EndChar : @0,
										 (id)kCMTextFormatDescriptionStyle_Font : @1,
										 (id)kCMTextFormatDescriptionStyle_FontFace : @0,
										 (id)kCMTextFormatDescriptionStyle_ForegroundColor : @{
												 (id)kCMTextFormatDescriptionColor_Red : @255,
												 (id)kCMTextFormatDescriptionColor_Green : @255,
												 (id)kCMTextFormatDescriptionColor_Blue : @255,
												 (id)kCMTextFormatDescriptionColor_Alpha : @255},
										 (id)kCMTextFormatDescriptionStyle_FontSize : @255},
								 (id)kCMTextFormatDescriptionExtension_HorizontalJustification : @0,
								 (id)kCMTextFormatDescriptionExtension_VerticalJustification : @0,
								 (id)kCMTextFormatDescriptionExtension_FontTable : @{@"1" : @"Sans-Serif"}};
	CMFormatDescriptionRef formatDescription;
	CMFormatDescriptionCreate(NULL, kCMMediaType_Subtitle, kCMTextFormatType_3GText, (__bridge CFDictionaryRef)extensions, &formatDescription);
	
	return formatDescription;
}

- (CMSampleBufferRef)copySampleBuffer
{
	const char *text = self.text.UTF8String;
	
	// Setup the sample size
	uint16_t textLength = 0;
	size_t sampleSize = 0;
	
	if (text != NULL)
		textLength = strlen(text); // don't include terminator in the length
	
	sampleSize = textLength + sizeof(uint16_t);
	
	if (self.forced)
		sampleSize += (sizeof (uint32_t) * 2); // for the 'frcd' atom
	
	uint8_t *samplePtr = malloc(sampleSize); // malloc space for length of text, text, and extensions. This variable should be char *, uint8_t *, UInt8 * for byte alignment reasons.
	
	uint16_t textLengthBigEndian = CFSwapInt16HostToBig(textLength);
	memcpy(samplePtr, &textLengthBigEndian, sizeof(textLengthBigEndian));
	
	if (textLength)
		memcpy ((samplePtr + sizeof(uint16_t)), text, textLength);
	
	uint8_t *ptr = samplePtr + sizeof (uint16_t) + textLength;
	
	if (self.forced)
	{
		// Make room for the forced atom.
		(*(uint32_t *) ptr) = CFSwapInt32HostToBig((sizeof (uint32_t) * 2));
		
		ptr += sizeof(uint32_t);
		
		// Set the forced atom.
		(*(uint32_t *) ptr) = CFSwapInt32HostToBig('frcd');
	}
	
	CMBlockBufferRef dataBuffer;
	CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, samplePtr, sampleSize, kCFAllocatorMalloc, NULL, 0, sampleSize, 0, &dataBuffer);
	
	CMSampleTimingInfo sampleTiming;
	sampleTiming.duration = self.timeRange.duration;
	sampleTiming.presentationTimeStamp = self.timeRange.start;
	sampleTiming.decodeTimeStamp = kCMTimeInvalid;
	
	CMFormatDescriptionRef formatDescription = [self copyFormatDescription];
	CMSampleBufferRef sampleBuffer;
	CMSampleBufferCreate(kCFAllocatorDefault, dataBuffer, true, NULL, 0, formatDescription, 1, 1, &sampleTiming, 1, &sampleSize, &sampleBuffer);
	
	if (formatDescription)
		CFRelease(formatDescription);
	
	if (dataBuffer)
		CFRelease(dataBuffer);
	
	return sampleBuffer;
}

@end

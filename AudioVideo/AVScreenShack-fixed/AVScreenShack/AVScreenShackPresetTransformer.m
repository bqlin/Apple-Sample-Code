
/*
     File: AVScreenShackPresetTransformer.m
 Abstract: Transforms an AVCaptureSessionPreset to a number
  Version: 2.1
 
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
 
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 
 */

#import "AVScreenShackPresetTransformer.h"
#import <AVFoundation/AVFoundation.h>

@implementation AVScreenShackPresetTransformer

+ (Class)transformedValueClass
{
	return [NSNumber class];
}

+ (BOOL)allowsReverseTransformation
{
	return YES;
}

- (id)transformedValue:(id)value
{
	NSNumber *number;
	
	if ([(NSString *)value isEqualToString:AVCaptureSessionPresetLow])
		number = @0;
	else if ([(NSString *)value isEqualToString:AVCaptureSessionPresetMedium])
		number = @1;
	else if ([(NSString *)value isEqualToString:AVCaptureSessionPresetHigh])
		number = @2;
	else if ([(NSString *)value isEqualToString:AVCaptureSessionPreset320x240])
		number = @3;
	else if ([(NSString *)value isEqualToString:AVCaptureSessionPreset352x288])
		number = @4;
	else if ([(NSString *)value isEqualToString:AVCaptureSessionPreset640x480])
		number = @5;
	else if ([(NSString *)value isEqualToString:AVCaptureSessionPreset960x540])
		number = @6;
	else if ([(NSString *)value isEqualToString:AVCaptureSessionPreset1280x720])
		number = @7;
	else if ([(NSString *)value isEqualToString:AVCaptureSessionPresetPhoto])
		number = @8;
	
    return number;
}

- (id)reverseTransformedValue:(id)value
{
	NSString *preset;
	
	switch ([(NSNumber *)value integerValue]) {
		case 0:
			preset = AVCaptureSessionPresetLow;
			break;
		case 1:
			preset = AVCaptureSessionPresetMedium;
			break;
		case 2:
			preset = AVCaptureSessionPresetHigh;
			break;
		case 3:
			preset = AVCaptureSessionPreset320x240;
			break;
		case 4:
			preset = AVCaptureSessionPreset352x288;
			break;
		case 5:
			preset = AVCaptureSessionPreset640x480;
			break;
		case 6:
			preset = AVCaptureSessionPreset960x540;
			break;
		case 7:
			preset = AVCaptureSessionPreset1280x720;
			break;
		case 8:
            preset = AVCaptureSessionPresetPhoto;
			break;
	}
	
	return preset;
}

@end

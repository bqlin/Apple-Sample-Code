/*
     File: AVTimecodeUtilities.m
 Abstract:  Timecode utilities to convert frame number to timecode and vice versa. 
  Version: 1.2
 
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

#import "AVTimecodeUtilities.h"

enum {
    tcNegativeFlag = 0x80  /* negative bit is in minutes */
};

int64_t frameNumberForTimecodeUsingFrameQuanta(CVSMPTETime timecode, uint32_t frameQuanta, uint32_t tcFlag)
{
	int64_t frameNumber = 0;
	frameNumber = timecode.frames;
	frameNumber += timecode.seconds * frameQuanta;
	frameNumber += (timecode.minutes & ~tcNegativeFlag) * frameQuanta * 60;
	frameNumber += timecode.hours * frameQuanta * 60 * 60;
	
	int64_t fpm = frameQuanta * 60;
	
	if (tcFlag & kCMTimeCodeFlag_DropFrame) {
		int64_t fpm10 = fpm * 10;
		int64_t num10s = frameNumber / fpm10;
		int64_t frameAdjust = -num10s*(9*2);
		int64_t numFramesLeft = frameNumber % fpm10;
		
		if (numFramesLeft > 1) {
			int64_t num1s = numFramesLeft / fpm;
			if (num1s > 0) {
				frameAdjust -= (num1s-1)*2;
				numFramesLeft = numFramesLeft % fpm;
				if (numFramesLeft > 1)
					frameAdjust -= 2;
				else
					frameAdjust -= (numFramesLeft+1);
			}
		}
		frameNumber += frameAdjust;
	}
	
	if (timecode.minutes & tcNegativeFlag) //check for kCMTimeCodeFlag_NegTimesOK here
		frameNumber = -frameNumber;
	
	return frameNumber;
}

CVSMPTETime timecodeForFrameNumberUsingFrameQuanta(int64_t frameNumber, uint32_t frameQuanta, uint32_t tcFlag)
{
	CVSMPTETime timecode = {0};
	
	short fps = frameQuanta;
	BOOL neg = FALSE;
	
	if (frameNumber < 0) {
		neg = TRUE;
		frameNumber = -frameNumber;
	}
	
	if (tcFlag & kCMTimeCodeFlag_DropFrame) {
		int64_t fpm = fps*60 - 2;
		int64_t fpm10 = fps*10*60 - 9*2;
		int64_t num10s = frameNumber / fpm10;
		int64_t frameAdjust = num10s*(9*2);
		int64_t numFramesLeft = frameNumber % fpm10;
		
		if (numFramesLeft >= fps*60) {
			numFramesLeft -= fps*60;
			int64_t num1s = numFramesLeft / fpm;
			frameAdjust += (num1s+1)*2;
		}
		frameNumber += frameAdjust;
	}
	
	timecode.frames = frameNumber % fps;
	frameNumber /= fps;
	timecode.seconds = frameNumber % 60;
	frameNumber /= 60;
	timecode.minutes = frameNumber % 60;
	frameNumber /= 60;
	
	if (tcFlag & kCMTimeCodeFlag_24HourMax) {
		frameNumber %= 24;
		if (neg && !(tcFlag & kCMTimeCodeFlag_NegTimesOK)) {
			neg = FALSE;
			frameNumber = 23 - frameNumber;
		}
	}
	timecode.hours = frameNumber;
	if (neg) {
		timecode.minutes |= tcNegativeFlag;
	}
	
	timecode.flags = kCVSMPTETimeValid;
	
	return timecode;
}


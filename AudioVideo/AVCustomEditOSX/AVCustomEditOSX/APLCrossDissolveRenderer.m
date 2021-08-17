/*
     File: APLCrossDissolveRenderer.m
 Abstract:  APLCrossDissolveRenderer subclass of APLOpenGLRenderer, renders the given source buffers to perform a cross dissolve over the time range of the transition. 
  Version: 1.1
 
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

#import "APLCrossDissolveRenderer.h"

@implementation APLCrossDissolveRenderer

- (id)init
{
    self = [super init];
    
    return self;
}

- (void)renderPixelBuffer:(CVPixelBufferRef)destinationPixelBuffer usingForegroundSourceBuffer:(CVPixelBufferRef)foregroundPixelBuffer andBackgroundSourceBuffer:(CVPixelBufferRef)backgroundPixelBuffer forTweenFactor:(float)tween
{
	CGLSetCurrentContext(_currentContext);
    
    CGLLockContext(_currentContext);
	
    if (foregroundPixelBuffer != NULL || backgroundPixelBuffer != NULL) {
        
        CVOpenGLTextureRef foregroundTexture  = [self textureForPixelBuffer:foregroundPixelBuffer];
		
        CVOpenGLTextureRef backgroundTexture = [self textureForPixelBuffer:backgroundPixelBuffer];
		
        CVOpenGLTextureRef destTexture = [self textureForPixelBuffer:destinationPixelBuffer];
                
		glUseProgram(self.program);
		
		// Set the render transform
		GLfloat preferredRenderTransform [] = {
			self.renderTransform.a, self.renderTransform.b, self.renderTransform.tx, 0.0,
			self.renderTransform.c, self.renderTransform.d, self.renderTransform.ty, 0.0,
			0.0,					   0.0,										1.0, 0.0,
			0.0,					   0.0,										0.0, 1.0,
		};
		
		glUniformMatrix4fv(uniforms[UNIFORM_RENDER_TRANSFORM], 1, GL_FALSE, preferredRenderTransform);
		
        glBindFramebuffer(GL_FRAMEBUFFER, self.offscreenBufferHandle);
        glViewport(0, 0, (int)CVPixelBufferGetWidth(destinationPixelBuffer), (int)CVPixelBufferGetHeight(destinationPixelBuffer));
		
		// Y planes of foreground and background frame are used to render the Y plane of the destination frame
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(CVOpenGLTextureGetTarget(foregroundTexture), CVOpenGLTextureGetName(foregroundTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(CVOpenGLTextureGetTarget(backgroundTexture), CVOpenGLTextureGetName(backgroundTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(CVOpenGLTextureGetTarget(destTexture), CVOpenGLTextureGetName(destTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR); // GL_NEAREST
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR); // GL_NEAREST
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		
		// Attach the destination texture as a color attachment to the off screen frame buffer
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, CVOpenGLTextureGetTarget(destTexture), CVOpenGLTextureGetName(destTexture), 0);
		
		if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
			NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
			goto bail;
		}
		
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
		glClear(GL_COLOR_BUFFER_BIT);
        
        GLfloat quadVertexData1 [] = {
			-1.0, -1.0,
			1.0, -1.0,
			-1.0, 1.0,
			1.0, 1.0,
		};
		
		size_t frameWidth = CVPixelBufferGetWidth(destinationPixelBuffer);
        size_t frameHeight = CVPixelBufferGetHeight(destinationPixelBuffer);
		
		// texture data varies from 0 -> w and 0 -> h, whereas vertex data varies from -1 -> 1
		GLfloat quadTextureData1 [] = {
            (0.5 + quadVertexData1[0]/2) * frameWidth, (0.5 + quadVertexData1[1]/2) * frameHeight,
            (0.5 + quadVertexData1[2]/2) * frameWidth, (0.5 + quadVertexData1[3]/2) * frameHeight,
            (0.5 + quadVertexData1[4]/2) * frameWidth, (0.5 + quadVertexData1[5]/2) * frameHeight,
            (0.5 + quadVertexData1[6]/2) * frameWidth, (0.5 + quadVertexData1[7]/2) * frameHeight,
        };
        
		glUniform1i(uniforms[UNIFORM_RGB], 0);
		
        glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData1);
        glEnableVertexAttribArray(ATTRIB_VERTEX);
        
        glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, quadTextureData1);
        glEnableVertexAttribArray(ATTRIB_TEXCOORD);
		
		// Blend function to draw the foreground frame
		glEnable(GL_BLEND);
		glBlendFunc(GL_ONE, GL_ZERO);
		
		// Draw the foreground frame
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		
        glUniform1i(uniforms[UNIFORM_RGB], 1);
        
        glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData1);
        glEnableVertexAttribArray(ATTRIB_VERTEX);
        
        glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, quadTextureData1);
        glEnableVertexAttribArray(ATTRIB_TEXCOORD);
		
		// Blend function to draw the background frame
        glBlendColor(0, 0, 0, tween);
        glBlendFunc(GL_CONSTANT_ALPHA, GL_ONE_MINUS_CONSTANT_ALPHA);
        
		// Draw the background frame
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		
        glFlush();
		
	bail:
		CFRelease(foregroundTexture);
		CFRelease(backgroundTexture);
		CFRelease(destTexture);
		
		// Periodic texture cache flush every frame
		CVOpenGLTextureCacheFlush(self.videoTextureCache, 0);
		
		CGLUnlockContext(_currentContext);
		
		CGLSetCurrentContext(_previousContext);
    }
	
}

@end

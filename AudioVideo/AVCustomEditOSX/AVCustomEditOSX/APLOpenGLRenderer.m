/*
     File: APLOpenGLRenderer.m
 Abstract:  OpenGL base class renderer setups a CGLContextObj for rendering, it also loads, compiles and links the vertex and fragment shaders. 
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

#import "APLOpenGLRenderer.h"

static const char kSimpleVertexShader[] = {
    "attribute vec4 position; \n \
     attribute vec2 texCoord; \n \
	 uniform mat4 renderTransform; \n \
     varying vec2 texCoordVarying; \n \
     void main() \n \
     { \n \
        gl_Position = position * renderTransform; \n \
        texCoordVarying = texCoord; \n \
     }"
};

static const char kSimpleFragmentShader[] = {
    "varying vec2 texCoordVarying; \n \
     uniform sampler2DRect Sampler; \n \
     void main() \n \
     { \n \
		gl_FragColor = texture2DRect(Sampler, texCoordVarying); \n \
     }"
};

@interface APLOpenGLRenderer ()

- (void)setupOffscreenRenderContext;

- (BOOL)loadShaders;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type source:(NSString *)source;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;

@end

@implementation APLOpenGLRenderer

- (id)init
{
    self = [super init];
    if(self) {
        [self setupOffscreenRenderContext];
        [self loadShaders];
    }
    
    return self;
}

- (void)dealloc
{
    if (_videoTextureCache) {
        CFRelease(_videoTextureCache);
    }
    if (_offscreenBufferHandle) {
        glDeleteFramebuffers(1, &_offscreenBufferHandle);
        _offscreenBufferHandle = 0;
    }
}

- (void)renderPixelBuffer:(CVPixelBufferRef)destinationPixelBuffer usingForegroundSourceBuffer:(CVPixelBufferRef)foregroundPixelBuffer andBackgroundSourceBuffer:(CVPixelBufferRef)backgroundPixelBuffer forTweenFactor:(float)tween
{
	[self doesNotRecognizeSelector:_cmd];
}

- (void)setupOffscreenRenderContext
{
	CGDirectDisplayID display = CGMainDisplayID (); // 1
    CGOpenGLDisplayMask myDisplayMask = CGDisplayIDToOpenGLDisplayMask (display); // 2
    
	// Check capabilities of display represented by display mask
	CGLPixelFormatAttribute attribs[] = {kCGLPFADisplayMask,
		myDisplayMask,
		0}; // 3
	CGLPixelFormatObj pixelFormat = NULL;
	GLint numPixelFormats = 0;
	CGLContextObj myCGLContext = 0;
	
	CGLChoosePixelFormat (attribs, &pixelFormat, &numPixelFormats); // 5
	if (pixelFormat) {
		CGLCreateContext (pixelFormat, NULL, &myCGLContext); // 6
		CGLDestroyPixelFormat (pixelFormat); // 7
		_previousContext = CGLGetCurrentContext();
		CGLRetainContext(_previousContext);
		CGLSetCurrentContext (myCGLContext); // 8
		_currentContext = myCGLContext;
		CGLRetainContext(_currentContext);
	}
	
	//-- Create CVOpenGLESTextureCacheRef for optimal CVPixelBufferRef to GLES texture conversion.
    if (_videoTextureCache) {
        CFRelease(_videoTextureCache);
        _videoTextureCache = NULL;
    }
    CVReturn err = CVOpenGLTextureCacheCreate(kCFAllocatorDefault, NULL, myCGLContext, pixelFormat, NULL, &_videoTextureCache);
    if (err != noErr) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
    }
	
	glDisable(GL_DEPTH_TEST);
	glGenFramebuffers(1, &_offscreenBufferHandle);
	glBindFramebuffer(GL_FRAMEBUFFER, _offscreenBufferHandle);
}

- (CVOpenGLTextureRef)textureForPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    CVOpenGLTextureRef texture = NULL;
    CVReturn err;
    
    if (!_videoTextureCache) {
        NSLog(@"No video texture cache");
        goto bail;
    }
    
    // Periodic texture cache flush every frame
    CVOpenGLTextureCacheFlush(_videoTextureCache, 0);
    
    // CVOpenGLTextureCacheCreateTextureFromImage will create GL texture optimally from CVPixelBufferRef.
	
	err = CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
													 _videoTextureCache,
													 pixelBuffer,
													 NULL,
													 &texture);
    
    if (!texture || err) {
        NSLog(@"Error at creating luma texture using CVOpenGLTextureCacheCreateTextureFromImage %d", err);
    }
    
bail:
    return texture;
}

#pragma mark -  OpenGL shader compilation

- (BOOL)loadShaders
{
	GLuint vertShader, fragShader;
	NSString *vertShaderSource, *fragShaderSource;
	
	// Create the shader program.
	_program = glCreateProgram();
	
	// Create and compile the vertex shader.
	vertShaderSource = [NSString stringWithCString:kSimpleVertexShader encoding:NSUTF8StringEncoding];
	if (![self compileShader:&vertShader type:GL_VERTEX_SHADER source:vertShaderSource]) {
		NSLog(@"Failed to compile vertex shader");
		return NO;
	}
	
	// Create and compile the fragment shader.
	fragShaderSource = [NSString stringWithCString:kSimpleFragmentShader encoding:NSUTF8StringEncoding];
	if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER source:fragShaderSource]) {
		NSLog(@"Failed to compile Y fragment shader");
		return NO;
	}
	
	// Attach vertex shader to programY.
	glAttachShader(_program, vertShader);
	
	// Attach fragment shader to programY.
	glAttachShader(_program, fragShader);
	
	// Bind attribute locations. This needs to be done prior to linking.
	glBindAttribLocation(_program, ATTRIB_VERTEX, "position");
	glBindAttribLocation(_program, ATTRIB_TEXCOORD, "texCoord");

	// Link the program.
	if (![self linkProgram:_program]) {
		NSLog(@"Failed to link program: %d", _program);
		
		if (vertShader) {
			glDeleteShader(vertShader);
			vertShader = 0;
		}
		if (fragShader) {
			glDeleteShader(fragShader);
			fragShader = 0;
		}
       
		if (_program) {
			glDeleteProgram(_program);
			_program = 0;
		}
		
		return NO;
	}
	
	// Get uniform locations.
	uniforms[UNIFORM_RGB] = glGetUniformLocation(_program, "Sampler");
    uniforms[UNIFORM_RENDER_TRANSFORM] = glGetUniformLocation(_program, "renderTransform");
	
	// Release vertex and fragment shaders.
	if (vertShader) {
		glDetachShader(_program, vertShader);
		glDeleteShader(vertShader);
	}
	if (fragShader) {
		glDetachShader(_program, fragShader);
		glDeleteShader(fragShader);
	}
	
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type source:(NSString *)sourceString
{
    if (sourceString == nil) {
		NSLog(@"Failed to load vertex shader: Empty source string");
        return NO;
    }
    
	GLint status;
	const GLchar *source;
	source = (GLchar *)[sourceString UTF8String];
	
	*shader = glCreateShader(type);
	glShaderSource(*shader, 1, &source, NULL);
	glCompileShader(*shader);
	
#if defined(DEBUG)
	GLint logLength;
	glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0) {
		GLchar *log = (GLchar *)malloc(logLength);
		glGetShaderInfoLog(*shader, logLength, &logLength, log);
		NSLog(@"Shader compile log:\n%s", log);
		free(log);
	}
#endif
	
	glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
	if (status == 0) {
		glDeleteShader(*shader);
		return NO;
	}
	
	return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
	GLint status;
	glLinkProgram(prog);
	
#if defined(DEBUG)
	GLint logLength;
	glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0) {
		GLchar *log = (GLchar *)malloc(logLength);
		glGetProgramInfoLog(prog, logLength, &logLength, log);
		NSLog(@"Program link log:\n%s", log);
		free(log);
	}
#endif
	
	glGetProgramiv(prog, GL_LINK_STATUS, &status);
	if (status == 0) {
		return NO;
	}
	
	return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
	GLint logLength, status;
	
	glValidateProgram(prog);
	glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0) {
		GLchar *log = (GLchar *)malloc(logLength);
		glGetProgramInfoLog(prog, logLength, &logLength, log);
		NSLog(@"Program validate log:\n%s", log);
		free(log);
	}
	
	glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
	if (status == 0) {
		return NO;
	}
	
	return YES;
}

@end

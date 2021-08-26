/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of utility functions that are shared across renderers.
*/
#import <MetalKit/MetalKit.h>

#import "AAPLRendererCommon.h"

// This function repeats boilerplate texture loading parameters and error checking
// - it is implemented with MetalKit's texture loader
id<MTLTexture> CreateTextureWithDevice (id<MTLDevice>        device,
                                        NSString*            filePath,
                                        bool                 sRGB,
                                        bool                 generateMips,
                                        MTLResourceOptions   storageMode)
{
    static MTKTextureLoader* sLoader = [[MTKTextureLoader alloc] initWithDevice:device];
    
    NSDictionary *options =
    @{
      MTKTextureLoaderOptionSRGB:                 [NSNumber numberWithBool:sRGB],
      MTKTextureLoaderOptionGenerateMipmaps:      [NSNumber numberWithBool:generateMips],
      MTKTextureLoaderOptionTextureUsage:         [NSNumber numberWithInteger:MTLTextureUsagePixelFormatView | MTLTextureUsageShaderRead],
      MTKTextureLoaderOptionTextureStorageMode:   [NSNumber numberWithUnsignedLong:storageMode]
      };
    
    NSURL* url;
    if ([[filePath substringToIndex:1] isEqualToString:@"/"])
        url = [NSURL fileURLWithPath:filePath];
    else
        url = [[NSBundle mainBundle] URLForResource:filePath withExtension:@""];
    NSError *error = nil;
    id <MTLTexture> texture = [sLoader newTextureWithContentsOfURL:url
                                                           options:options
                                                             error:&error];
    if (texture) { texture.label = filePath; }
    else
    {
        NSString* reason = [NSString stringWithFormat:@"Error loading texture (%@) : %@", filePath, error];
        NSException* exc = [NSException
                            exceptionWithName: @"Texture loading exception"
                            reason: reason
                            userInfo: nil];
        @throw exc;
    }
    return texture;
}

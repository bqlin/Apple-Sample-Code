/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of a very simple container for image data
*/

#import "AAPLImage.h"
#include <simd/simd.h>
@implementation AAPLImage

-(nullable instancetype) initWithTGAFileAtLocation:(nonnull NSURL *)tgaLocation
{
    self = [super init];
    if(self)
    {
        NSString * fileExtension = tgaLocation.pathExtension;
        
        if(!([fileExtension caseInsensitiveCompare:@"TGA"] == NSOrderedSame))
        {
            NSLog(@"This image loader only loads TGA files");
            return nil;
        }
        
        // Structure fitting the layout of a TGA header containing image metadata.
        typedef struct __attribute__ ((packed)) TGAHeader
        {
            uint8_t  IDSize;         // Size of ID info following header
            uint8_t  colorMapType;   // Whether this is a paletted image
            uint8_t  imageType;      // type of image 0=none, 1=indexed, 2=rgb, 3=grey, +8=rle packed
            
            int16_t  colorMapStart;  // Offset to color map in palette
            int16_t  colorMapLength; // Number of colors in palette
            uint8_t  colorMapBpp;    // Number of bits per palette entry
            
            uint16_t xOrigin;        // X Origin pixel of lower left corner if tile of larger image
            uint16_t yOrigin;        // Y Origin pixel of lower left corner if tile of larger image
            uint16_t width;          // Width in pixels
            uint16_t height;         // Height in pixels
            uint8_t  bitsPerPixel;   // Bits per pixel 8,16,24,32
            union {
                struct
                {
                    uint8_t bitsPerAlpha : 4;
                    uint8_t topOrigin    : 1;
                    uint8_t rightOrigin  : 1;
                    uint8_t reserved     : 2;
                };
                uint8_t descriptor;
            };
        } TGAHeader;
        
        NSError * error;
        
        // Copy the entire file to this fileData variable
        NSData *fileData = [[NSData alloc] initWithContentsOfURL:tgaLocation
                                                         options:0x0
                                                           error:&error];
        
        if (!fileData)
        {
            NSLog(@"Could not open TGA File:%@", error.localizedDescription);
            return nil;
        }
        
        // 这操作好他妈骚啊！直接用强制转换把头部数据拿了出来。
        TGAHeader *tgaInfo = (TGAHeader *) fileData.bytes;
        
        if(tgaInfo->imageType != 2)
        {
            NSLog(@"This image loader only supports non-compressed BGR(A) TGA files");
            return nil;
        }
        
        if(tgaInfo->colorMapType)
        {
            NSLog(@"This image loader doesn't support TGA files with a colormap");
            return nil;
        }
        
        if(tgaInfo->xOrigin || tgaInfo->yOrigin)
        {
            NSLog(@"This image loader doesn't support TGA files with a non-zero origin");
            return nil;
        }
        
        NSUInteger srcBytesPerPixel;
        if(tgaInfo->bitsPerPixel == 32)
        {
            srcBytesPerPixel = 4;
            
            if(tgaInfo->bitsPerAlpha != 8)
            {
                NSLog(@"This image loader only supports 32-bit TGA files with 8 bits of alpha");
                return nil;
            }
            
        }
        else if(tgaInfo->bitsPerPixel == 24)
        {
            srcBytesPerPixel = 3;
            
            if(tgaInfo->bitsPerAlpha != 0)
            {
                NSLog(@"This image loader only supports 24-bit TGA files with no alpha");
                return nil;
            }
        }
        else
        {
            NSLog(@"This image loader only supports 24-bit and 32-bit TGA files");
            return nil;
        }
        
        _width = tgaInfo->width;
        _height = tgaInfo->height;
        
        // The image data is stored as 32-bits per pixel BGRA data.
        NSUInteger dataSize = _width * _height * 4;

        // Metal will not understand an image with 24-bit BGR format so the pixels
        // are converted to a 32-bit BGRA format that Metal does understand
        // (MTLPixelFormatBGRA8Unorm)

        NSMutableData *mutableData = [[NSMutableData alloc] initWithLength:dataSize];

        // TGA spec says the image data is immediately after the header and the ID so set
        //   the pointer to file's start + size of the header + size of the ID
        // Initialize a source pointer with the source image data that's in BGR form
        // 去掉头部数据和IDSize，剩下的就是图像数据了
        uint8_t *srcImageData = ((uint8_t*)fileData.bytes +
                                 sizeof(TGAHeader) +
                                 tgaInfo->IDSize);

        // Initialize a destination pointer to which you'll store the converted BGRA
        // image data
        uint8_t *dstImageData = mutableData.mutableBytes;

        // For every row of the image
        for(NSUInteger y = 0; y < _height; y++)
        {
            // If bit 5 of the descriptor is not set, flip vertically
            // to transform the data to Metal's top-left texture origin
            NSUInteger srcRow = (tgaInfo->topOrigin) ? y : _height - 1 - y;

            // For every column of the current row
            for(NSUInteger x = 0; x < _width; x++)
            {
                // If bit 4 of the descriptor is set, flip horizontally
                // to transform the data to Metal's top-left texture origin
                NSUInteger srcColumn = (tgaInfo->rightOrigin) ? _width - 1 - x : x;

                // Calculate the index for the first byte of the pixel you're
                // converting in both the source and destination images
                NSUInteger srcPixelIndex = srcBytesPerPixel * (srcRow * _width + srcColumn);
                NSUInteger dstPixelIndex = 4 * (y * _width + x);

                // Copy BGR channels from the source to the destination
                // Set the alpha channel of the destination pixel to 255
                dstImageData[dstPixelIndex + 0] = srcImageData[srcPixelIndex + 0];
                dstImageData[dstPixelIndex + 1] = srcImageData[srcPixelIndex + 1];
                dstImageData[dstPixelIndex + 2] = srcImageData[srcPixelIndex + 2];

                if(tgaInfo->bitsPerPixel == 32)
                {
                    dstImageData[dstPixelIndex + 3] =  srcImageData[srcPixelIndex + 3];
                }
                else
                {
                    dstImageData[dstPixelIndex + 3] = 255;
                }
            }
        }
        _data = mutableData;
    }
    
    return self;
}

@end

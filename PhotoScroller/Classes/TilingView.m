/*
     File: TilingView.m
 Abstract: The main view controller for this application.
  Version: 1.3
 
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
 
 Copyright (C) 2012 Apple Inc. All Rights Reserved.
 
 */

#import "TilingView.h"
#import <QuartzCore/CATiledLayer.h>


@implementation TilingView
{
    NSString *_imageName;
}

+ (Class)layerClass
{
	return [CATiledLayer class];
}

- (id)initWithImageName:(NSString *)name size:(CGSize)size
{
    self = [super initWithFrame:CGRectMake(0, 0, size.width, size.height)];
    if (self) {
        _imageName = name;

        CATiledLayer *tiledLayer = (CATiledLayer *)[self layer];
        tiledLayer.levelsOfDetail = 4;
    }
    return self;
}

// to handle the interaction between CATiledLayer and high resolution screens, we need to
// always keep the tiling view's contentScaleFactor at 1.0. UIKit will try to set it back
// to 2.0 on retina displays, which is the right call in most cases, but since we're backed
// by a CATiledLayer it will actually cause us to load the wrong sized tiles.
// 要处理CATiledLayer和高分辨率屏幕之间的交互，我们需要始终将平铺视图的contentScaleFactor保持为1.0。 UIKit将尝试在视网膜显示器上将其设置回2.0，这在大多数情况下是正确的调用，但由于我们使用CATiledLayer支持，它实际上会导致我们加载错误大小的磁贴。
- (void)setContentScaleFactor:(CGFloat)contentScaleFactor
{
    [super setContentScaleFactor:1.f];
}

- (void)drawRect:(CGRect)rect
{
 	CGContextRef context = UIGraphicsGetCurrentContext();
    
    // get the scale from the context by getting the current transform matrix, then asking
    // for its "a" component, which is one of the two scale components. We could also ask
    // for "d". This assumes (safely) that the view is being scaled equally in both dimensions.
    // 通过获取当前变换矩阵从上下文中获取比例，然后询问其“a”组件，它是两个比例组件之一。 我们也可以要求“d”。 这假定（安全地）视图在两个维度上均等地缩放。
    CGFloat scale = CGContextGetCTM(context).a;
	
	__block CATiledLayer *tiledLayer = nil;
	if (![NSThread isMainThread]) {
		dispatch_sync(dispatch_get_main_queue(), ^{
			tiledLayer = (CATiledLayer *)[self layer];
		});
	}
    CGSize tileSize = tiledLayer.tileSize;
    
    // Even at scales lower than 100%, we are drawing into a rect in the coordinate system
    // of the full image. One tile at 50% covers the width (in original image coordinates)
    // of two tiles at 100%. So at 50% we need to stretch our tiles to double the width
    // and height; at 25% we need to stretch them to quadruple the width and height; and so on.
    // (Note that this means that we are drawing very blurry images as the scale gets low.
    // At 12.5%, our lowest scale, we are stretching about 6 small tiles to fill the entire
    // original image area. But this is okay, because the big blurry image we're drawing
    // here will be scaled way down before it is displayed.)
    // 即使在低于100％的比例下，我们也会在完整图像的坐标系中绘制一个矩形。 50％的一个瓷砖覆盖100％的两个瓷砖的宽度（在原始图像坐标中）。 因此在50％时我们需要拉伸瓷砖以使宽度和高度加倍; 在25％时，我们需要将它们拉伸到四倍宽度和高度; 等等。 （请注意，这意味着我们正在绘制非常模糊的图像，因为比例变低。在12.5％，我们的最低比例，我们正在拉伸大约6个小瓦片来填充整个原始图像区域。但这没关系，因为大模糊 我们在这里绘制的图像将在显示之前按比例缩小。）
    tileSize.width /= scale;
    tileSize.height /= scale;
    
    // calculate the rows and columns of tiles that intersect the rect we have been asked to draw
    // 计算与我们被要求绘制的矩形相交的瓷砖的行和列
    int firstCol = floorf(CGRectGetMinX(rect) / tileSize.width);
    int lastCol = floorf((CGRectGetMaxX(rect)-1) / tileSize.width);
    int firstRow = floorf(CGRectGetMinY(rect) / tileSize.height);
    int lastRow = floorf((CGRectGetMaxY(rect)-1) / tileSize.height);

	// 获取并绘制瓷砖图片
    for (int row = firstRow; row <= lastRow; row++) {
        for (int col = firstCol; col <= lastCol; col++) {
            UIImage *tile = [self tileForScale:scale row:row col:col];
            __block CGRect tileRect = CGRectMake(tileSize.width * col, tileSize.height * row,
                                         tileSize.width, tileSize.height);

            // if the tile would stick outside of our bounds, we need to truncate it so as
            // to avoid stretching out the partial tiles at the right and bottom edges
            // 如果瓷砖会粘在我们的边界之外，我们需要将其截断，以避免拉出右边和底边的部分瓷砖
			if (![NSThread isMainThread]) {
				dispatch_sync(dispatch_get_main_queue(), ^{
					tileRect = CGRectIntersection(self.bounds, tileRect);
				});
			}
            [tile drawInRect:tileRect];            
        }
    }
}

/// 获取瓷砖图片
- (UIImage *)tileForScale:(CGFloat)scale row:(int)row col:(int)col
{
    // we use "imageWithContentsOfFile:" instead of "imageNamed:" here because we don't
    // want UIImage to cache our tiles
    //
    NSString *tileName = [NSString stringWithFormat:@"%@_%d_%d_%d", _imageName, (int)(scale * 1000), col, row];
    NSString *path = [[NSBundle mainBundle] pathForResource:tileName ofType:@"png"];
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    return image;
}

@end

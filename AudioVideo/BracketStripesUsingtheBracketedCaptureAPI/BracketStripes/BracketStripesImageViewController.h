/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Photo view controller
 */


@class BracketStripesImageViewController;

@protocol BracketStripesImageViewDelegate

- (void)imageViewControllerDidFinish:(BracketStripesImageViewController *)controller;

@end


@interface BracketStripesImageViewController : UIViewController

@property (nonatomic, weak) id<BracketStripesImageViewDelegate> delegate;

// Designated initializer
- (instancetype)initWithImage:(UIImage *)image;

@end

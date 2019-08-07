/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 The initial view controller for the Custom Presentation demo.
 */

#import "AAPLCustomPresentationFirstViewController.h"
#import "AAPLCustomPresentationController.h"
#import "SlidePresentationController.h"

@implementation AAPLCustomPresentationFirstViewController

- (void)dealloc{
	NSLog(@"%s", __FUNCTION__);
}

#pragma mark -
#pragma mark Presentation

//| ----------------------------------------------------------------------------
- (IBAction)buttonAction:(UIButton*)sender
{
    UIViewController *secondViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"SecondViewController"];
    
    // For presentations which will use a custom presentation controller,
    // it is possible for that presentation controller to also be the
    // transitioningDelegate.  This avoids introducing another object
    // or implementing <UIViewControllerTransitioningDelegate> in the
    // source view controller.
    //
    // transitioningDelegate does not hold a strong reference to its
    // destination object.  To prevent presentationController from being
    // released prior to calling -presentViewController:animated:completion:
    // the NS_VALID_UNTIL_END_OF_SCOPE attribute is appended to the declaration.
	
//    AAPLCustomPresentationController *presentationController NS_VALID_UNTIL_END_OF_SCOPE;
//    presentationController = [[AAPLCustomPresentationController alloc] initWithPresentedViewController:secondViewController presentingViewController:self];
//    secondViewController.transitioningDelegate = presentationController;
	
	SlidePresentationController *presentation = [[SlidePresentationController alloc] initWithPresentedViewController:secondViewController presentingViewController:self];
	secondViewController.transitioningDelegate = presentation;
	
    [self presentViewController:secondViewController animated:YES completion:NULL];
}

@end

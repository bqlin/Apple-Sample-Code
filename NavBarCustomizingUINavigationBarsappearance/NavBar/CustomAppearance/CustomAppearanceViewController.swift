/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Demonstrates applying a custom background to a navigation bar.
 */

import UIKit

class CustomAppearanceViewController: UITableViewController {

    @IBOutlet var backgroundSwitcher: UISegmentedControl!

	/// Our data source is an array of city names, populated from Cities.json.
	let dataSource = CitiesDataSource()
	
    override func viewDidLoad() {
        super.viewDidLoad()
		
		tableView.dataSource = dataSource
		
        // Place the background switcher in the toolbar.
        let backgroundSwitcherItem = UIBarButtonItem(customView: backgroundSwitcher)
        toolbarItems = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            backgroundSwitcherItem,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        ]
        
        applyImageBackgroundToTheNavigationBar()
    }
	
    /**
     *  Configures the navigation bar to use an image as its background.
     */
    func applyImageBackgroundToTheNavigationBar() {
        // These background images contain a small pattern which is displayed
        // in the lower right corner of the navigation bar.
        var backgroundImageForDefaultBarMetrics = #imageLiteral(resourceName: "NavigationBarDefault")
        var backgroundImageForLandscapePhoneBarMetrics = #imageLiteral(resourceName: "NavigationBarLandscapePhone")
        
        // Both of the above images are smaller than the navigation bar's
        // size.  To enable the images to resize gracefully while keeping their
        // content pinned to the bottom right corner of the bar, the images are
        // converted into resizable images width edge insets extending from the
        // bottom up to the second row of pixels from the top, and from the
        // right over to the second column of pixels from the left.  This results
        // in the topmost and leftmost pixels being stretched when the images
        // are resized.  Not coincidentally, the pixels in these rows/columns
        // are empty.
        backgroundImageForDefaultBarMetrics =
			backgroundImageForDefaultBarMetrics.resizableImage(withCapInsets: UIEdgeInsets(top: 0,
																						   left: 0,
																						   bottom: backgroundImageForDefaultBarMetrics.size.height - 1,
																						   right: backgroundImageForDefaultBarMetrics.size.width - 1))
        backgroundImageForLandscapePhoneBarMetrics =
			backgroundImageForLandscapePhoneBarMetrics.resizableImage(withCapInsets: UIEdgeInsets(top: 0,
																								  left: 0,
																								  bottom: backgroundImageForLandscapePhoneBarMetrics.size.height - 1,
																								  right: backgroundImageForLandscapePhoneBarMetrics.size.width - 1))
        
        // You should use the appearance proxy to customize the appearance of
        // UIKit elements.  However changes made to an element's appearance
        // proxy do not effect any existing instances of that element currently
        // in the view hierarchy.  Normally this is not an issue because you
        // will likely be performing your appearance customizations in
        // -application:didFinishLaunchingWithOptions:.  However, this example
        // allows you to toggle between appearances at runtime which necessitates
        // applying appearance customizations directly to the navigation bar.
        /* let navigationBarAppearance = UINavigationBar.appearance(whenContainedInInstancesOf: [UINavigationController.self]) */
        let navigationBarAppearance = self.navigationController!.navigationBar
        
        // The bar metrics associated with a background image determine when it
        // is used.  The background image associated with the Default bar metrics
        // is used when a more suitable background image can not be found.
        navigationBarAppearance.setBackgroundImage(backgroundImageForDefaultBarMetrics, for: .default)
        // The background image associated with the LandscapePhone bar metrics
        // is used by the shorter variant of the navigation bar that is used on
        // iPhone when in landscape.
        navigationBarAppearance.setBackgroundImage(backgroundImageForLandscapePhoneBarMetrics, for: .compact)
    }
    
    /**
     *  Configures the navigation bar to use a transparent background (see-through
     *  but without any blur).
     */
    func applyTransparentBackgroundToTheNavigationBar(_ opacity: CGFloat) {
        var transparentBackground: UIImage
        
        // The background of a navigation bar switches from being translucent
        // to transparent when a background image is applied.  The intensity of
        // the background image's alpha channel is inversely related to the
        // transparency of the bar.  That is, a smaller alpha channel intensity
        // results in a more transparent bar and vis-versa.
        //
        // Below, a background image is dynamically generated with the desired
        // opacity.
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 1, height: 1),
											   false,
											   navigationController!.navigationBar.layer.contentsScale)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: opacity)
        UIRectFill(CGRect(x: 0, y: 0, width: 1, height: 1))
        transparentBackground = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        // You should use the appearance proxy to customize the appearance of
        // UIKit elements.  However changes made to an element's appearance
        // proxy do not effect any existing instances of that element currently
        // in the view hierarchy.  Normally this is not an issue because you
        // will likely be performing your appearance customizations in
        // -application:didFinishLaunchingWithOptions:.  However, this example
        // allows you to toggle between appearances at runtime which necessitates
        // applying appearance customizations directly to the navigation bar.
        /* let navigationBarAppearance = UINavigationBar.appearance(whenContainedInInstancesOf: [UINavigationController.self]) */
        let navigationBarAppearance = self.navigationController!.navigationBar
        
        navigationBarAppearance.setBackgroundImage(transparentBackground, for: .default)
    }
    
    /**
     *  Configures the navigation bar to use a custom color as its background.
     *  The navigation bar remains translucent.
     */
    func applyBarTintColorToTheNavigationBar() {
        // Be aware when selecting a barTintColor for a translucent bar that
        // the tint color will be blended with the content passing under
        // the translucent bar.  See QA1808 for more information.
        // <https://developer.apple.com/library/ios/qa/qa1808/_index.html>
        let barTintColor =
			UIColor(red: 176.0/255.0, green: 226.0/255.0, blue: 172.0/255.0, alpha: 1)
        let darkendBarTintColor =
			UIColor(red: 176.0/255.0 - 0.05, green: 226.0/255.0 - 0.02, blue: 172.0/255.0 - 0.05, alpha: 1)
        
        // You should use the appearance proxy to customize the appearance of
        // UIKit elements.  However changes made to an element's appearance
        // proxy do not effect any existing instances of that element currently
        // in the view hierarchy.  Normally this is not an issue because you
        // will likely be performing your appearance customizations in
        // -application:didFinishLaunchingWithOptions:.  However, this example
        // allows you to toggle between appearances at runtime which necessitates
        // applying appearance customizations directly to the navigation bar.
        /* let navigationBarAppearance = UINavigationBar.appearance(whenContainedInInstancesOf: [UINavigationController.self]) */
        let navigationBarAppearance = self.navigationController!.navigationBar
        
        navigationBarAppearance.barTintColor = darkendBarTintColor
        
        // For comparison, apply the same barTintColor to the toolbar, which
        // has been configured to be opaque.
        navigationController!.toolbar.barTintColor = barTintColor
        navigationController!.toolbar.isTranslucent = false
    }
	
	// MARK: - UIContentContainer
	
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		
		// This works around a bug in iOS 8.0 - 8.2 in which the navigation bar
		// will not display the correct background image after rotating the device.
		// This bug affects bars in navigation controllers that are presented
		// modally. A bar in the window's rootViewController would not be affected.
		coordinator.animate(alongsideTransition: { context in
			// The workaround is to toggle some appearance related setting on the
			// navigation bar when we detect that the view controller has changed
			// interface orientations.  In our example, we call the
			// -configureNewNavBarBackground: which reapplies our appearance
			// based on the current selection.  In a real app, changing just the
			// barTintColor or barStyle would have the same effect.
			self.configureNewNavBarBackground(self.backgroundSwitcher)
		}, completion: nil)
	}
	
    // MARK: - Background Switcher
    
    @IBAction func configureNewNavBarBackground(_ sender: UISegmentedControl) {
        // Reset everything.
        self.navigationController!.navigationBar.setBackgroundImage(nil, for: .default)
        self.navigationController!.navigationBar.setBackgroundImage(nil, for: .compact)
        self.navigationController!.navigationBar.barTintColor = nil
        self.navigationController!.toolbar.barTintColor = nil
        self.navigationController!.toolbar.isTranslucent = true
        
        switch sender.selectedSegmentIndex {
        case 0: // Transparent Background
            applyImageBackgroundToTheNavigationBar()
            
        case 1: // Transparent
            applyTransparentBackgroundToTheNavigationBar(0.87)
            
        case 2: // Colored
            applyBarTintColorToTheNavigationBar()
            
        default:
            break
        }
    }
	
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if navigationItem.prompt == dataSource.city(index: indexPath.row) {
            navigationItem.prompt = nil
            tableView.deselectRow(at: indexPath, animated: true)
        }
        else {
			navigationItem.prompt = dataSource.city(index: indexPath.row)
        }
    }
}

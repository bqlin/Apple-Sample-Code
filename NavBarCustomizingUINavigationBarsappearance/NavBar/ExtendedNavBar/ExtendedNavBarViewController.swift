/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Demonstrates vertically extending the navigation bar.
 */

import UIKit

class ExtendedNavBarViewController: UITableViewController {

	/// Our data source is an array of city names, populated from Cities.json.
	let dataSource = CitiesDataSource()

    override func viewDidLoad() {
        super.viewDidLoad()

		tableView.dataSource = dataSource
		
        // For the extended navigation bar effect to work, a few changes
        // must be made to the actual navigation bar.  Some of these changes could
        // be applied in the storyboard but are made in code for clarity.
        
        // Translucency of the navigation bar is disabled so that it matches with
        // the non-translucent background of the extension view.
        navigationController!.navigationBar.isTranslucent = false
        
        // The navigation bar's shadowImage is set to a transparent image.  In
        // addition to providing a custom background image, this removes
        // the grey hairline at the bottom of the navigation bar.  The
        // ExtendedNavBarView will draw its own hairline.
		navigationController!.navigationBar.shadowImage = UIImage(named: "TransparentPixel")
        // "Pixel" is a solid white 1x1 image.
        //navigationController!.navigationBar.setBackgroundImage(#imageLiteral(resourceName: "Pixel"), for: .default)
    }
}

/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 The application's main (initial) view controller.
 */

import UIKit

class MainViewController: UITableViewController, UIActionSheetDelegate {

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    /**
     *  Unwind action that is targeted by the demos which present a modal view
     *  controller, to return to the main screen.
     */
    @IBAction func unwindToMainViewController(_ sender: UIStoryboardSegue) { }
    
    // MARK: - Style AlertController
	
    /**
     *  IBAction for the 'Style' bar button item.
     */
    @IBAction func styleAction(_ sender: AnyObject) {
        let title = NSLocalizedString("Choose a UIBarStyle:", comment: "")
        let cancelButtonTitle = NSLocalizedString("Cancel", comment: "")
        let defaultButtonTitle = NSLocalizedString("Default", comment: "")
        let blackOpaqueTitle = NSLocalizedString("Black Opaque", comment: "")
        let blackTranslucentTitle = NSLocalizedString("Black Translucent", comment: "")
		
		let alertController = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)

		alertController.addAction(UIAlertAction(title: NSLocalizedString(cancelButtonTitle, comment: ""),
		                                        style: .cancel) { _ in })
		alertController.addAction(UIAlertAction(title: NSLocalizedString(defaultButtonTitle, comment: ""),
		                                        style: .default) { _ in
			self.navigationController!.navigationBar.barStyle = .default
			// Bars are translucent by default.
			self.navigationController!.navigationBar.isTranslucent = true
			// Reset the bar's tint color to the system default.
			self.navigationController!.navigationBar.tintColor = nil
		})
		alertController.addAction(UIAlertAction(title: NSLocalizedString(blackOpaqueTitle, comment: ""),
		                                        style: .default) { _ in
			// Change to black-opaque.
			self.navigationController!.navigationBar.barStyle = .black
			self.navigationController!.navigationBar.isTranslucent = false
			self.navigationController!.navigationBar.tintColor = #colorLiteral(red: 1, green: 0.99997437, blue: 0.9999912977, alpha: 1)
		})
		alertController.addAction(UIAlertAction(title: NSLocalizedString(blackTranslucentTitle, comment: ""),
		                                        style: .default) { _ in
			// Change to black-translucent.
			self.navigationController!.navigationBar.barStyle = .black
			self.navigationController!.navigationBar.isTranslucent = true
			self.navigationController!.navigationBar.tintColor = #colorLiteral(red: 1, green: 0.99997437, blue: 0.9999912977, alpha: 1)
		})
		self.present(alertController, animated: true, completion: nil)
    }

	override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
		var shouldPerform = true
		let indexPath = self.tableView.indexPathForSelectedRow
		if indexPath?.row == 6 {
			if #available(iOS 11.0, *) { }
			else {
				// LargeTitle feature available in iOS 11 and later.
				let title = NSLocalizedString("LargeTitle message", comment: "")
				let alertController = UIAlertController(title: title, message: nil, preferredStyle: .alert)
				alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
				                                        style: .default) { _ in })
				self.present(alertController, animated: true, completion: nil)
				
				tableView.deselectRow(at: indexPath!, animated: true)
				shouldPerform = false
			}
		}
		return shouldPerform
	}
	
}

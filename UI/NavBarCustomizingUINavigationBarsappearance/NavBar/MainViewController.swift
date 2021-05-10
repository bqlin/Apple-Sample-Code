/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 The application's main (initial) view controller.

跳转由 storyboard 完成
 */

import UIKit

class MainViewController: UITableViewController, UIActionSheetDelegate {

	// 支持竖屏
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
	设置 MainViewController 的导航栏样式
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
		// 默认样式
		alertController.addAction(UIAlertAction(title: NSLocalizedString(defaultButtonTitle, comment: ""),
		                                        style: .default) { _ in
			self.navigationController!.navigationBar.barStyle = .default
			// Bars are translucent by default.
			self.navigationController!.navigationBar.isTranslucent = true
			// Reset the bar's tint color to the system default.
			self.navigationController!.navigationBar.tintColor = nil
		})
		// 暗黑样式
		alertController.addAction(UIAlertAction(title: NSLocalizedString(blackOpaqueTitle, comment: ""),
		                                        style: .default) { _ in
			// Change to black-opaque.
			self.navigationController!.navigationBar.barStyle = .black
			self.navigationController!.navigationBar.isTranslucent = false
			self.navigationController!.navigationBar.tintColor = #colorLiteral(red: 1, green: 0.99997437, blue: 0.9999912977, alpha: 1)
		})
		// 暗黑透明样式
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
		// 勘误，6 -> 5
		if indexPath?.row == 5 {
			// 若为 iOS 11 之前则不允许在该单元格跳转，并弹窗提醒
			if #available(iOS 11.0, *) { }
			else {
				// LargeTitle feature available in iOS 11 and later.
				let title = NSLocalizedString("LargeTitle message", comment: "")
				let alertController = UIAlertController(title: title, message: nil, preferredStyle: .alert)
				alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
				                                        style: .default) { _ in }) // 使用默认的实现，即撤下弹窗
				self.present(alertController, animated: true, completion: nil)
				
				// 取消选中
				tableView.deselectRow(at: indexPath!, animated: true)
				shouldPerform = false
			}
		}
		return shouldPerform
	}
	
}

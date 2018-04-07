/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 The application delegate class.
 */

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UINavigationControllerDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]?) -> Bool {
        (window!.rootViewController as! UINavigationController).delegate = self
        
        return true
    }
    
    // MARK: - UINavigationControllerDelegate
    
    /**  
     *  Force the navigation controller to defer to the topViewController for
     *  its supportedInterfaceOrientations.  This allows some of the demos
     *  to rotate into landscape while keeping the rest in portrait.
     */
    func navigationControllerSupportedInterfaceOrientations(_ navigationController: UINavigationController) -> UIInterfaceOrientationMask {
        return navigationController.topViewController!.supportedInterfaceOrientations
    }
}

/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    The application delegate.
*/

import UIKit


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    var navigationController: UINavigationController!
    
    var transitionController: AssetTransitionController!
    

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]? = [:]) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)

        navigationController = UINavigationController(rootViewController: AssetViewController(layoutStyle: .grid))
        transitionController = AssetTransitionController(navigationController: navigationController)
        
        window.rootViewController = navigationController
        navigationController.delegate = transitionController

        window.makeKeyAndVisible()
        self.window = window
        
        return true
    }
}

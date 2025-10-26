//
//  AppDelegate.swift
//  
//  Created by Bq on 2025/10/24.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        let window = UIWindow()
        window.rootViewController = UINavigationController(rootViewController: MenuViewController())
        window.rootViewController?.view.backgroundColor = .systemYellow
        window.makeKeyAndVisible()
        self.window = window
        
        return true
    }
}

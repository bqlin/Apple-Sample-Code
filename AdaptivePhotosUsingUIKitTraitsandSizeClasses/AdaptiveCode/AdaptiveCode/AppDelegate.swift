/*
Copyright (C) 2016 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
The application delegate and split view controller delegate.
*/

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Load the conversations from disk and create our root model object.
        
        let user: User
        if let url = Bundle.main.url(forResource: "User", withExtension: "plist"),
            let userDictionary = NSDictionary(contentsOf: url) as? [String: AnyObject],
            let loadedUser = User(dictionary: userDictionary) {
                user = loadedUser
        }
        else {
            user = User()
        }
    
        let window = UIWindow()
        self.window = window
        
        let splitViewController = UISplitViewController()
        splitViewController.delegate = self
        splitViewController.preferredDisplayMode = .allVisible
        
        let userListTableViewController = ListTableViewController(user: user)
        let primaryViewController = UINavigationController(rootViewController: userListTableViewController)
        
        let secondaryViewController = EmptyViewController()
        
        splitViewController.viewControllers = [primaryViewController, secondaryViewController]
        window.rootViewController = splitViewController
        
        window.makeKeyAndVisible()
        
        return true
    }
}

extension AppDelegate: UISplitViewControllerDelegate {
    // Collapse the secondary view controller onto the primary view controller.
    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {
        /*
            The secondary view is not showing a photo. Return true to tell the
            splitViewController to use its default behavior: just hide the
            secondaryViewController and show the primaryViewController.
        */
        guard let photo = secondaryViewController.containedPhoto() else { return true }
        
        /*
            The secondary view is showing a photo. Set the primary navigation
            controller to contain a path of view controllers that lead to that photo.
        */
        if let primaryNavController = primaryViewController as? UINavigationController {
            let viewControllersLeadingToPhoto = primaryNavController.viewControllers.filter { $0.containsPhoto(photo) }
            
            primaryNavController.viewControllers = viewControllersLeadingToPhoto
        }
        
        /*
            We handled the collapse. Return false to tell the splitViewController
            not to do anything else.
        */
        return false
    }
    
    // Separate the secondary view controller from the primary view controller.
    func splitViewController(_ splitViewController: UISplitViewController, separateSecondaryFrom primaryViewController: UIViewController) -> UIViewController? {
        
        if let primaryNavController = primaryViewController as? UINavigationController {
            /*
                One of the view controllers in the navigation stack is showing a
                photo. Return nil to tell the splitViewController to use its
                default behavior: show the secondary view controller that was
                present when it collapsed.
            */
            let anyViewControllerContainsPhoto = primaryNavController.viewControllers.contains { controller in
                return controller.containedPhoto() != nil
            }
            
            if anyViewControllerContainsPhoto {
                return nil
            }
        }
        
        /*
            None of the view controllers in the navigation stack contained a photo,
            so show a new empty view controller as the secondary.
        */
        return EmptyViewController()
    }
}

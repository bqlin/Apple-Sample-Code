/*
Copyright (C) 2016 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
A view controller that shows a list of conversations that can be viewed.
*/

import UIKit

class ListTableViewController: UITableViewController {
    // MARK: Properties

    let user: User
    
    static let cellIdentifier = "ConversationCell"
    
    // MARK: Initialization
    
    init(user: User) {
        self.user = user

        super.init(style: .plain)

        title = NSLocalizedString("Conversations", comment: "Conversations")
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("About", comment: "About"), style: .plain, target: self, action: #selector(ListTableViewController.showAboutViewController(_:)))
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Profile", comment: "Profile"), style: .plain, target: self, action: #selector(ListTableViewController.showProfileViewController(_:)))
        
        clearsSelectionOnViewWillAppear = false
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: View Controller
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: ListTableViewController.cellIdentifier)
        
        NotificationCenter.default.addObserver(self, selector: #selector(ListTableViewController.showDetailTargetDidChange(_:)), name: NSNotification.Name.UIViewControllerShowDetailTargetDidChange, object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Deselect any index paths that push when tapped
        for indexPath in tableView.indexPathsForSelectedRows ?? [] {
            let pushes: Bool

            if shouldShowConversationViewForIndexPath(indexPath) {
                pushes = willShowingViewControllerPushWithSender(self)
            }
            else {
                pushes = willShowingDetailViewControllerPushWithSender(self)
            }
            
            if pushes {
                // If we're pushing for this indexPath, deselect it when we appear.
                tableView.deselectRow(at: indexPath, animated: animated)
            }
        }
        
        if let visiblePhoto = currentVisibleDetailPhotoWithSender(self) {
            for indexPath in tableView.indexPathsForVisibleRows ?? [] {
                let photo = photoForIndexPath(indexPath)
                
                if photo == visiblePhoto {
                    tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
                }
            }
        }
    }
    
    func showDetailTargetDidChange(_ notification: Notification) {
        /*
            Whenever the target for showDetailViewController: changes, update all
            of our cells (to ensure they have the right accessory type).
        */
        for cell in tableView.visibleCells {
            if let indexPath = tableView.indexPath(for: cell) {
                tableView(tableView, willDisplay: cell, forRowAt: indexPath)
            }
        }
    }
    
    override func containsPhoto(_ photo: Photo) -> Bool {
        return true
    }

    // MARK: About

    func showAboutViewController(_ sender: UIBarButtonItem) {
        if presentedViewController != nil {
            // Dismiss Profile if visible
            dismiss(animated: true, completion: nil)
        }
        
        let aboutViewController = AboutViewController()
        aboutViewController.navigationItem.title = NSLocalizedString("About", comment: "About")
        aboutViewController.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(ListTableViewController.closeAboutViewController(_:)))

        let navController = UINavigationController(rootViewController: aboutViewController)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true, completion: nil)
    }

    func closeAboutViewController(_ sender: UIBarButtonItem) {
        dismiss(animated: true, completion: nil)
    }

    // MARK: Profile
    
    func showProfileViewController(_ sender: UIBarButtonItem) {
        let profileController = ProfileViewController(user: user)
        profileController.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(ListTableViewController.closeProfileViewController(_:)))
        
        let profileNavController = UINavigationController(rootViewController: profileController)
        profileNavController.modalPresentationStyle = .popover
        profileNavController.popoverPresentationController?.barButtonItem = sender
        
        // Set self as the presentation controller's delegate so that we can adapt its appearance
        profileNavController.popoverPresentationController?.delegate = self

        present(profileNavController, animated: true, completion:nil)
    }

    func closeProfileViewController(_ sender: UIBarButtonItem) {
        dismiss(animated: true, completion: nil)
    }

    // MARK: Table View
    
    func conversationForIndexPath(_ indexPath: IndexPath) -> Conversation {
        return user.conversations[indexPath.row]
    }
    
    func photoForIndexPath(_ indexPath: IndexPath) -> Photo? {
        if shouldShowConversationViewForIndexPath(indexPath) {
            return nil
        }
        else {
            let conversation = conversationForIndexPath(indexPath)
            
            return conversation.photos.last
        }
    }
    
    // Returns whether the conversation at indexPath contains more than one photo.
    func shouldShowConversationViewForIndexPath(_ indexPath: IndexPath) -> Bool {
        let conversation  = conversationForIndexPath(indexPath)

        return conversation.photos.count > 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return user.conversations.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return tableView.dequeueReusableCell(withIdentifier: ListTableViewController.cellIdentifier, for: indexPath)
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // Whether to show the disclosure indicator for this cell.
        let pushes: Bool
        if shouldShowConversationViewForIndexPath(indexPath) {
            // If the conversation corresponding to this row has multiple photos.
            pushes = willShowingViewControllerPushWithSender(self)
        }
        else {
            // If the conversation corresponding to this row has a single photo.
            pushes = willShowingDetailViewControllerPushWithSender(self)
        }
        
        /*
            Only show a disclosure indicator if selecting this cell will trigger
            a push in the master view controller (the navigation controller above
            ourself).
        */
        cell.accessoryType = pushes ? .disclosureIndicator : .none
        
        let conversation = conversationForIndexPath(indexPath)
        cell.textLabel?.text = conversation.name
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let conversation = conversationForIndexPath(indexPath)
        
        if shouldShowConversationViewForIndexPath(indexPath) {
            let controller = ConversationViewController(conversation: conversation)
            controller.title = conversation.name
            
            // If this row has a conversation, we just want to show it.
            show(controller, sender: self)
        }
        else {
            if let photo = conversation.photos.last {
                let controller = PhotoViewController(photo: photo)
                controller.title = conversation.name
                
                // If this row has a single photo, then show it as the detail (if possible).
                showDetailViewController(controller, sender: self)
            }
        }
    }
}

extension ListTableViewController: UIPopoverPresentationControllerDelegate {
    func presentationController(_ presentationController: UIPresentationController, willPresentWithAdaptiveStyle style: UIModalPresentationStyle, transitionCoordinator: UIViewControllerTransitionCoordinator?) {
        guard let presentedNavigationController = presentationController.presentedViewController as? UINavigationController else { return }
        
        // We want to hide the navigation bar if we're presenting in our original style (Popover)
        let hidesNavigationBar = style == .none
        
        presentedNavigationController.setNavigationBarHidden(hidesNavigationBar, animated: false)
    }
}

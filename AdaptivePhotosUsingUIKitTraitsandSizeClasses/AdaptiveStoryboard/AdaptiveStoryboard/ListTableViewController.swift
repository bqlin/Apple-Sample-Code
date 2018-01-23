/*
Copyright (C) 2016 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
A view controller that shows a list of conversations that can be viewed.
*/

import UIKit

class ListTableViewController: UITableViewController {
    // MARK: Properties
    
    var user: User? {
        didSet {
            if isViewLoaded {
                tableView.reloadData()
            }
        }
    }
    
    static let conversationCellIdentifier = "ConversationCell"
    static let photoCellIdentifier = "PhotoCell"
    
    // MARK: Initialization
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: View Controller
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
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
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let indexPath = tableView.indexPathForSelectedRow,
               let conversation = conversationForIndexPath(indexPath) {
            if segue.identifier == "ShowConversation" {
                // Set up our ConversationViewController to have its conversation and title
                let destination = segue.destination as! ConversationViewController
                destination.conversation = conversation
                destination.title = conversation.name
            }
            else if segue.identifier == "ShowPhoto" {
                // Set up our PhotoViewController to have its photo and title
                let destination = segue.destination as! PhotoViewController
                destination.photo = conversation.photos.last
                destination.title = conversation.name
            }
        }
        
        if segue.identifier == "ShowAbout" {
            if presentedViewController != nil {
                // Dismiss Profile if visible.
                dismiss(animated: true, completion: nil)
            }
        }
        else if segue.identifier == "ShowProfile" {
            // Set up our ProfileViewController to have its user
            let navigationController = segue.destination as! UINavigationController
            let destination = navigationController.topViewController as! ProfileViewController
            destination.user = user
            
            // Set self as the presentation controller's delegate so that we can adapt its appearance
            navigationController.popoverPresentationController?.delegate = self
        }
    }
    
    // MARK: Table View
    
    func conversationForIndexPath(_ indexPath: IndexPath) -> Conversation? {
        return user?.conversations[(indexPath as NSIndexPath).row]
    }
    
    func photoForIndexPath(_ indexPath: IndexPath) -> Photo? {
        if shouldShowConversationViewForIndexPath(indexPath) {
            return nil
        }
        else {
            let conversation = conversationForIndexPath(indexPath)

            return conversation?.photos.last
        }
    }
    
    // Returns whether the conversation at indexPath contains more than one photo.
    func shouldShowConversationViewForIndexPath(_ indexPath: IndexPath) -> Bool {
        let conversation  = conversationForIndexPath(indexPath)
        
        return (conversation?.photos.count ?? 0) > 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return user?.conversations.count ?? 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if shouldShowConversationViewForIndexPath(indexPath) {
            return tableView.dequeueReusableCell(withIdentifier: ListTableViewController.conversationCellIdentifier, for: indexPath)
        }
        else {
            return tableView.dequeueReusableCell(withIdentifier: ListTableViewController.photoCellIdentifier, for: indexPath)
        }
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
        cell.textLabel?.text = conversation?.name ?? ""
    }
}

extension ListTableViewController: UIPopoverPresentationControllerDelegate {
    func presentationController(_ presentationController: UIPresentationController, willPresentWithAdaptiveStyle style: UIModalPresentationStyle, transitionCoordinator: UIViewControllerTransitionCoordinator?) {
        guard let presentedNavigationController = presentationController.presentedViewController as? UINavigationController else { return }

        // We want to show the navigation bar if we're presenting in full screen.
        
        let hidesNavigationBar = style != .fullScreen
        
        presentedNavigationController.setNavigationBarHidden(hidesNavigationBar, animated: false)
    }
}

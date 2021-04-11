/*
Copyright (C) 2016 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
A view controller that shows the contents of a conversation.
*/

import UIKit

class ConversationViewController: UITableViewController {
    // MARK: Properties
    
    let conversation: Conversation
    
    static let cellIdentifier = "PhotoCell"
    
    // MARK: Initialization
    
    init(conversation: Conversation) {
        self.conversation = conversation
        
        super.init(style: .plain)

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

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: ConversationViewController.cellIdentifier)
        
        NotificationCenter.default.addObserver(self, selector: #selector(ConversationViewController.showDetailTargetDidChange(_:)), name: UIViewController.showDetailTargetDidChangeNotification, object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        for indexPath in tableView.indexPathsForSelectedRows ?? [] {
            let indexPathPushes = willShowingDetailViewControllerPushWithSender(self)
            
            if indexPathPushes {
                // If we're pushing for this indexPath, deselect it when we appear.
                tableView.deselectRow(at: indexPath, animated: animated)
            }
        }
                
        let visiblePhoto = currentVisibleDetailPhotoWithSender(self)

        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            let photo = photoForIndexPath(indexPath)

            if photo == visiblePhoto {
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            }
        }
    }
    
    // This method is originally declared in the PhotoContents extension on `UIViewController`.
    override func containsPhoto(_ photo: Photo) -> Bool {
        conversation.photos.contains(photo)
    }
    
    @objc func showDetailTargetDidChange(_ notification: Notification) {
        for cell in tableView.visibleCells {
            if let indexPath = tableView.indexPath(for: cell) {
                tableView(tableView, willDisplay: cell, forRowAt: indexPath)
            }
        }
    }
    
    // MARK: Table View
    
    func photoForIndexPath(_ indexPath: IndexPath) -> Photo {
        conversation.photos[indexPath.row]
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        conversation.photos.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        tableView.dequeueReusableCell(withIdentifier: ConversationViewController.cellIdentifier, for: indexPath)
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let pushes = willShowingDetailViewControllerPushWithSender(self)
        
        // Only show a disclosure indicator if we're pushing.
        cell.accessoryType = pushes ? .disclosureIndicator : .none
        
        let photo = photoForIndexPath(indexPath)
       
        cell.textLabel?.text = photo.comment
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let photo = photoForIndexPath(indexPath)
        let controller = PhotoViewController(photo: photo)
        let photoNumber = indexPath.row + 1
        let photoCount = conversation.photos.count
        
        let localizedStringFormat = NSLocalizedString("%d of %d", comment: "X of X")
        controller.title = String.localizedStringWithFormat(localizedStringFormat, photoNumber, photoCount)
        
        // Show the photo as the detail (if possible).
        showDetailViewController(controller, sender: self)
    }
}

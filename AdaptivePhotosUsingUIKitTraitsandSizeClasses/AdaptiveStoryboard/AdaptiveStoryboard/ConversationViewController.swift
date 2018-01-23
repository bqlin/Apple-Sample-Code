/*
Copyright (C) 2016 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
A view controller that shows the contents of a conversation.
*/

import UIKit

class ConversationViewController: UITableViewController {
    // MARK: Properties
    
    var conversation: Conversation?
    
    static let cellIdentifier = "PhotoCell"
    
    // MARK: Initialization
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: View Controller
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(ConversationViewController.showDetailTargetDidChange(_:)), name: NSNotification.Name.UIViewControllerShowDetailTargetDidChange, object: nil)
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
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let indexPath = tableView.indexPathForSelectedRow,
                  let photo = photoForIndexPath(indexPath)
              , segue.identifier == "ShowPhoto" else { return }

        let destination = segue.destination as! PhotoViewController
        destination.photo = photo
        let photoNumber = (indexPath as NSIndexPath).row + 1
        let photoCount = conversation?.photos.count ?? 0
        
        let localizedStringFormat = NSLocalizedString("%d of %d", comment: "X of X")
        destination.title = String.localizedStringWithFormat(localizedStringFormat, photoNumber, photoCount)
    }
    
    // This method is originally declared in the PhotoContents extension on `UIViewController`.
    override func containsPhoto(_ photo: Photo) -> Bool {
        return conversation?.photos.contains(photo) ?? false
    }
    
    func showDetailTargetDidChange(_ notification: Notification) {
        for cell in tableView.visibleCells {
            if let indexPath = tableView.indexPath(for: cell) {
                tableView(tableView, willDisplay: cell, forRowAt: indexPath)
            }
        }
    }
    
    // MARK: Table View
    
    func photoForIndexPath(_ indexPath: IndexPath) -> Photo? {
        return conversation?.photos[(indexPath as NSIndexPath).row]
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return conversation?.photos.count ?? 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return tableView.dequeueReusableCell(withIdentifier: ConversationViewController.cellIdentifier, for: indexPath)
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let pushes = willShowingDetailViewControllerPushWithSender(self)
        
        // Only show a disclosure indicator if we're pushing.
        cell.accessoryType = pushes ? .disclosureIndicator : .none
        
        let photo = photoForIndexPath(indexPath)
        
        cell.textLabel?.text = photo?.comment ?? ""
    }
}

/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	Defines the view controller for the progress scene.
*/

import UIKit

class ProgressViewController: UIViewController {
    // MARK: Properties

    var sourceURL: URL?
	
    var outputURL: URL?
    
    lazy var operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        
        operationQueue.name = "com.example.apple-samplecode.progressviewcontroller.operationQueue"
        
        return operationQueue
    }()
    
    weak var cyanifier: CyanifyOperation?
    
    static let finishingSegueName = "finishing"
    
    static let cancelSegueName = "cancel"
    
    // MARK: IBActions
	
	@IBAction func cancel() {
        cyanifier?.cancel()
	}
    
    // MARK: View Controller

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
        
        guard let outputURL = outputURL, let sourceURL = sourceURL else {
            fatalError("`outputURL` and `sourceURL` should not be nil when \(#function) is called.")
        }
		
		// Create video processing operation and add it to our operation queue.

		let cyanifier = CyanifyOperation(sourceURL: sourceURL, outputURL: outputURL)
		
		cyanifier.completionBlock = { [weak cyanifier] in
			/*
                Operation must still be alive when it invokes its completion handler.
                It also must have set a non-nil result by the time it finishes.
            */
			let result = cyanifier!.result!

			DispatchQueue.main.async {
				self.cyanificationDidFinish(result: result)
			}
		}
		
		operationQueue.addOperation(cyanifier)
		
		self.cyanifier = cyanifier
	}
	
	private func cyanificationDidFinish(result: CyanifyOperation.Result) {
		switch result {
            case .success:
				performSegue(withIdentifier: ProgressViewController.finishingSegueName, sender: self)

            case .failure(let error):
                presentError(error: error as NSError)

            case .cancellation:
				performSegue(withIdentifier: ProgressViewController.cancelSegueName, sender: self)
		}
	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == ProgressViewController.finishingSegueName {
			let nextViewController = segue.destination as! ResultViewController

            nextViewController.outputURL = outputURL
		}
	}
	
    /// Present an `NSError` to the user.
	func presentError(error: NSError) {
		let failureTitle = error.localizedDescription

        let failureMessage = error.localizedRecoverySuggestion ?? error.localizedFailureReason
		
        let alertController = UIAlertController(title: failureTitle, message: failureMessage, preferredStyle: .alert)
        
		let alertAction = UIAlertAction(title: "OK", style: .default) { _ in
			self.performSegue(withIdentifier: "error", sender: self)
		}
		
        alertController.addAction(alertAction)
		
		present(alertController, animated: true, completion: nil)
	}
}

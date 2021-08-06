/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	Demonstrates how to use AVAssetExportSession to export and transcode media files
*/

import AVFoundation

/*
    Perform all of the argument parsing / set up. The interesting AV exporting
    code is done in the `Exporter` type.
*/
actOnCommandLineArguments()

/// The type that performs all of the asset exporting.
struct Exporter {
	// MARK: Properties
	
	let sourceURL: URL
	
	let destinationURL: URL
	
    var destinationFileType = AVFileType.mov
	
	var presetName = AVAssetExportPresetPassthrough
	
	var timeRange: CMTimeRange?
	
	var filterMetadata = false
	
	var injectMetadata = false
	
	var hasDeleteExistingFile = false
	
	var isVerbose = false
	
	// MARK: Initialization
	
	init(sourceURL: URL, destinationURL: URL) {
		self.sourceURL = sourceURL
		self.destinationURL = destinationURL
	}
	
	func export() throws {
        let asset = AVURLAsset(url: sourceURL)
		
        printVerbose(string: "Exporting \"\(sourceURL)\" to \"\(destinationURL)\" (file type \(destinationFileType)), using preset \(presetName).")
		
		// Set up export session.
        let exportSession = try setUpExportSession(asset: asset, destinationURL: destinationURL)
        
        // AVAssetExportSession will not overwrite existing files.
        try deleteExistingFile(destinationURL: destinationURL)

        describeSourceFile(asset: asset)
		
		// Kick off asynchronous export operation.
        let group = DispatchGroup()
        group.enter()
        exportSession.exportAsynchronously {
            group.leave()
		}
		
        waitForExportToFinish(exportSession: exportSession, group: group)
		
        if exportSession.status == .failed {
			// `error` is non-nil when in the "failed" status.
			throw exportSession.error!
		}
		else {
            describeDestFile(destinationURL: destinationURL)
		}
		
        printVerbose(string: "Export completed successfully.")
	}
	
	func setUpExportSession(asset: AVAsset, destinationURL: URL) throws -> AVAssetExportSession {
		guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
			throw CommandLineError.InvalidArgument(reason: "Invalid preset \(presetName).")
		}
		
		// Set required properties.
        exportSession.outputURL = destinationURL
		exportSession.outputFileType = destinationFileType
		
		if let timeRange = timeRange {
			exportSession.timeRange = timeRange
			
            printVerbose(string: "Trimming to time range \(CMTimeRangeCopyDescription(allocator: nil, range: timeRange)!).")
		}
		
		if filterMetadata {
            printVerbose(string: "Filtering metadata.")
			
            exportSession.metadataItemFilter = AVMetadataItemFilter.forSharing()
		}
		
		if injectMetadata {
            printVerbose(string: "Injecting metadata")
			
			let now = Date()
            let currentDate = DateFormatter.localizedString(from: now, dateStyle: .medium, timeStyle: .short)
			
			let userDataCommentItem = AVMutableMetadataItem()
            userDataCommentItem.identifier = AVMetadataIdentifier.quickTimeUserDataComment
            userDataCommentItem.value = "QuickTime userdata: Exported to preset \(presetName) using AVFoundationExporter at: \(currentDate)." as NSString
			
			let metadataCommentItem = AVMutableMetadataItem()
            metadataCommentItem.identifier = AVMetadataIdentifier.quickTimeMetadataComment
			metadataCommentItem.value = "QuickTime metadata: Exported to preset \(presetName) using AVFoundationExporter at: \(currentDate)." as NSString
			
			let iTunesCommentItem = AVMutableMetadataItem()
            iTunesCommentItem.identifier = AVMetadataIdentifier.iTunesMetadataUserComment
			iTunesCommentItem.value = "iTunes metadata: Exported to preset \(presetName) using AVFoundationExporter at: \(currentDate)." as NSString
			
			/*
                To avoid replacing metadata from the asset:
                    1. Fetch existing metadata from the asset.
                    2. Combine it with the new metadata.
                    3. Set the result on the export session.
			*/
			exportSession.metadata = asset.metadata + [
				userDataCommentItem,
				metadataCommentItem,
				iTunesCommentItem
			]
		}
		
		return exportSession
	}
	
	func deleteExistingFile(destinationURL: URL) throws {
        let fileManager = FileManager()

        let destinationPath = destinationURL.path
        if hasDeleteExistingFile && fileManager.fileExists(atPath: destinationPath) {
            printVerbose(string: "Removing pre-existing file at destination path \"\(destinationPath)\".")
            
            try fileManager.removeItem(at: destinationURL)
        }
	}
	
	func describeSourceFile(asset: AVAsset) {
		guard isVerbose else { return }
		
        printVerbose(string: "Tracks in source file:")
		
        let trackDescriptions = trackDescriptionsForAsset(asset: asset)
		let tracksDescription = trackDescriptions.joined(separator: "\n\t")
        printVerbose(string: "\t\(tracksDescription)")
		
        printVerbose(string: "Metadata in source file:")
        let metadataDescriptions = metadataDescriptionsForAsset(asset: asset)
		let metadataDescription = metadataDescriptions.joined(separator: "\n\t")
		
        printVerbose(string: "\t\(metadataDescription)")
	}
	
	// Periodically polls & prints export session progress while waiting for the export to finish.
	func waitForExportToFinish(exportSession: AVAssetExportSession, group: DispatchGroup) {
        while exportSession.status == .waiting || exportSession.status == .exporting {
            printVerbose(string: "Progress: \(exportSession.progress * 100.0)%.")
			
            _ = group.wait(timeout: .now() + 0.5)
		}
		
        printVerbose(string: "Progress: \(exportSession.progress * 100.0)%.")
	}
	
	func describeDestFile(destinationURL: URL) {
		guard isVerbose else { return }
		
        let destinationAsset = AVAsset(url:destinationURL)
		
        printVerbose(string: "Tracks in written file:")
		
        let trackDescriptions = trackDescriptionsForAsset(asset: destinationAsset)
        let tracksDescription = trackDescriptions.joined(separator: "\n\t")
        printVerbose(string: "\t\(tracksDescription)")
		
        printVerbose(string: "Metadata in written file:")
		
        let metadataDescriptions = metadataDescriptionsForAsset(asset: destinationAsset)
        let metadataDescription = metadataDescriptions.joined(separator: "\n\t")
        printVerbose(string: "\t\(metadataDescription)")
	}
	
	func trackDescriptionsForAsset(asset: AVAsset) -> [String] {
		return asset.tracks.map { track in
            let enabledString = track.isEnabled ? "YES" : "NO"
			
            let selfContainedString = track.isSelfContained ? "YES" : "NO"
			
            let formatDescriptions = track.formatDescriptions as! [CMFormatDescription]
			
			let formatStrings = formatDescriptions.map { formatDescription -> String in
                let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)

                let mediaSubTypeString = NSFileTypeForHFSTypeCode(mediaSubType)!
				
				return "'\(track.mediaType)'/\(mediaSubTypeString)"
			}
			
			let formatString = !formatStrings.isEmpty ? formatStrings.joined(separator: ", ") : "'\(track.mediaType)'"
			
			return "Track ID \(track.trackID): \(formatString), data length: \(track.totalSampleDataLength), enabled: \(enabledString), self-contained: \(selfContainedString)"
		}
	}
	
	func metadataDescriptionsForAsset(asset: AVAsset) -> [String] {
		return asset.metadata.map { item in
            let identifier = item.identifier ?? AVMetadataIdentifier(rawValue: "<no identifier>")
			
			let value = item.value?.description ?? "<no value>"
			
			return "metadata item \(identifier): \(value)"
		}
	}
	
	func printVerbose(string: String) {
		if isVerbose {
			print(string)
		}
	}
}

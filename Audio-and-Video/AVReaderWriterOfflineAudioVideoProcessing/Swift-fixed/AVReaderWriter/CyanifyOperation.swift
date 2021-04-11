/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	Defines a subclass of NSOperation that adjusts the color of a video file.
*/

import AVFoundation
import Dispatch

enum CyanifyError: Error {
    case NoMediaData
}

class CyanifyOperation: Operation {
    // MARK: Types
    
    enum Result {
        case success
        case cancellation
        case failure(Error)
    }
    
    // MARK: Properties
    
    override var isExecuting: Bool {
        result == nil
    }
    
    override var isFinished: Bool {
        result != nil
    }
    
    private let asset: AVAsset
    
    private let outputURL: URL
    
    private var sampleTransferError: Error?
    
    var result: Result? {
        willSet {
            willChangeValue(forKey: "isExecuting")
            willChangeValue(forKey: "isFinished")
        }
        didSet {
            didChangeValue(forKey: "isExecuting")
            didChangeValue(forKey: "isFinished")
        }
    }
    
    // MARK: Initialization
    
    init(sourceURL: URL, outputURL: URL) {
        asset = AVAsset(url: sourceURL)
        self.outputURL = outputURL
    }
    
    override var isAsynchronous: Bool { true }
    
    // Every path through `start()` must call `finish()` exactly once.
    override func start() {
        guard !isCancelled else {
            finish(.cancellation)
            return
        }
        
        // Load asset properties in the background, to avoid blocking the caller with synchronous I/O.
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
            guard !self.isCancelled else {
                self.finish(.cancellation)
                return
            }
            
            // These are all initialized in the below 'do' block, assuming no errors are thrown.
            let assetReader: AVAssetReader
            let assetWriter: AVAssetWriter
            let videoReaderOutputsAndWriterInputs: [ReaderOutputAndWriterInput]
            let passthroughReaderOutputsAndWriterInputs: [ReaderOutputAndWriterInput]
            
            do {
                // Make sure that the asset tracks loaded successfully.
                
                var trackLoadingError: NSError?
                guard self.asset.statusOfValue(forKey: "tracks", error: &trackLoadingError) == .loaded else {
                    throw trackLoadingError!
                }
                let tracks = self.asset.tracks
                
                // Create reader/writer objects.
                
                assetReader = try AVAssetReader(asset: self.asset)
                assetWriter = try AVAssetWriter(outputURL: self.outputURL, fileType: AVFileType.mov)
                
                let (videoReaderOutputs, passthroughReaderOutputs) = try self.makeReaderOutputs(for: tracks, availableMediaTypes: assetWriter.availableMediaTypes)
                
                videoReaderOutputsAndWriterInputs = try self.makeVideoWriterInputs(for: videoReaderOutputs)
                passthroughReaderOutputsAndWriterInputs = try self.makePassthroughWriterInputs(for: passthroughReaderOutputs)
                
                // Hook everything up.
                
                for (readerOutput, writerInput) in videoReaderOutputsAndWriterInputs {
                    assetReader.add(readerOutput)
                    assetWriter.add(writerInput)
                }
                
                for (readerOutput, writerInput) in passthroughReaderOutputsAndWriterInputs {
                    assetReader.add(readerOutput)
                    assetWriter.add(writerInput)
                }
                
                /*
                    Remove file if necessary. AVAssetWriter will not overwrite
                    an existing file.
                */
                
                let fileManager = FileManager()
                let outputPath = self.outputURL.path
                if fileManager.fileExists(atPath: outputPath) {
                    try fileManager.removeItem(at: self.outputURL)
                }
                
                // Start reading/writing.
                
                guard assetReader.startReading() else {
                    // `error` is non-nil when startReading returns false.
                    throw assetReader.error!
                }
                
                guard assetWriter.startWriting() else {
                    // `error` is non-nil when startWriting returns false.
                    throw assetWriter.error!
                }
                
                assetWriter.startSession(atSourceTime: CMTime.zero)
            } catch {
                self.finish(.failure(error))
                return
            }
            
            let writingGroup = DispatchGroup()
            
            // Transfer data from input file to output file.
            self.transferVideoTracks(videoReaderOutputsAndWriterInputs: videoReaderOutputsAndWriterInputs, group: writingGroup)
            self.transferPassthroughTracks(passthroughReaderOutputsAndWriterInputs: passthroughReaderOutputsAndWriterInputs, group: writingGroup)
            
            // Handle completion.
            let queue = DispatchQueue.global()
            
            writingGroup.notify(queue: queue) {
                // `readingAndWritingDidFinish()` is guaranteed to call `finish()` exactly once.
                self.readingAndWritingDidFinish(assetReader: assetReader, assetWriter: assetWriter)
            }
        }
    }
    
    /**
        A type used for correlating an `AVAssetWriterInput` with the `AVAssetReaderOutput`
        that is the source of appended samples.
    */
    private typealias ReaderOutputAndWriterInput = (readerOutput: AVAssetReaderOutput, writerInput: AVAssetWriterInput)
    
    /// 视频轨以32ARGB读取，其他轨道保持不变
    private func makeReaderOutputs(for tracks: [AVAssetTrack], availableMediaTypes: [AVMediaType]) throws -> (videoReaderOutputs: [AVAssetReaderTrackOutput], passthroughReaderOutputs: [AVAssetReaderTrackOutput]) {
        // Decompress source video to 32ARGB.
        let videoDecompressionSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        // Partition tracks into "video" and "passthrough" buckets, create reader outputs.
        
        var videoReaderOutputs = [AVAssetReaderTrackOutput]()
        var passthroughReaderOutputs = [AVAssetReaderTrackOutput]()
        
        for track in tracks {
            guard availableMediaTypes.contains(track.mediaType) else { continue }
            
            switch track.mediaType {
                case AVMediaType.video:
                    let videoReaderOutput = AVAssetReaderTrackOutput(track: track, outputSettings: videoDecompressionSettings)
                    videoReaderOutputs += [videoReaderOutput]
                
                default:
                    // `nil` output settings means "passthrough."
                    let passthroughReaderOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                    passthroughReaderOutputs += [passthroughReaderOutput]
            }
        }
        
        return (videoReaderOutputs, passthroughReaderOutputs)
    }
    
    ///
    private func makeVideoWriterInputs(for videoReaderOutputs: [AVAssetReaderTrackOutput]) throws -> [ReaderOutputAndWriterInput] {
        // Compress modified source frames to H.264.
        let videoCompressionSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecH264
        ]
        
        /*
            In order to find the source format we need to create a temporary asset
            reader, plus a temporary track output for each "real" track output.
            We will only read as many samples (typically just one) as necessary
            to discover the format of the buffers that will be read from each "real"
            track output.
        */
        
        let tempAssetReader = try AVAssetReader(asset: asset)
        
        // 这是把videoReaderOutputs里面的output拷贝了一份变成tempVideoReaderOutput？后面对其copyNextSampleBuffer，得到sample buffer的format，然后创建writer input
        let videoReaderOutputsAndTempVideoReaderOutputs: [(videoReaderOutput: AVAssetReaderTrackOutput, tempVideoReaderOutput: AVAssetReaderTrackOutput)] = videoReaderOutputs.map { videoReaderOutput in
            let tempVideoReaderOutput = AVAssetReaderTrackOutput(track: videoReaderOutput.track, outputSettings: videoReaderOutput.outputSettings)
            
            tempAssetReader.add(tempVideoReaderOutput)
            
            return (videoReaderOutput, tempVideoReaderOutput)
        }
        
        // Start reading.
        
        guard tempAssetReader.startReading() else {
            // 'error' will be non-nil if startReading fails.
            throw tempAssetReader.error!
        }
        
        /*
            Create video asset writer inputs, using the source format hints read   
            from the "temporary" reader outputs.
        */
        
        var videoReaderOutputsAndWriterInputs = [ReaderOutputAndWriterInput]()
        
        for (videoReaderOutput, tempVideoReaderOutput) in videoReaderOutputsAndTempVideoReaderOutputs {
            // Fetch format of source sample buffers.
            
            var videoFormatHint: CMFormatDescription?
            
            while videoFormatHint == nil {
                guard let sampleBuffer = tempVideoReaderOutput.copyNextSampleBuffer() else {
                    // We ran out of sample buffers before we found one with a format description
                    throw CyanifyError.NoMediaData
                }
                
                videoFormatHint = CMSampleBufferGetFormatDescription(sampleBuffer)
            }
            
            // Create asset writer input.
            
            let videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoCompressionSettings, sourceFormatHint: videoFormatHint)
            
            videoReaderOutputsAndWriterInputs.append((readerOutput: videoReaderOutput, writerInput: videoWriterInput))
        }
        
        // Shut down processing pipelines, since only a subset of the samples were read.
        tempAssetReader.cancelReading()
        
        return videoReaderOutputsAndWriterInputs
    }
    
    private func makePassthroughWriterInputs(for passthroughReaderOutputs: [AVAssetReaderTrackOutput]) throws -> [ReaderOutputAndWriterInput] {
        /*
            Create passthrough writer inputs, using the source track's format
            descriptions as the format hint for each writer input.
        */
        
        var passthroughReaderOutputsAndWriterInputs = [ReaderOutputAndWriterInput]()
        
        for passthroughReaderOutput in passthroughReaderOutputs {
            /*
                For passthrough, we can simply ask the track for its format 
                description and use that as the writer input's format hint.
            */
            let trackFormatDescriptions = passthroughReaderOutput.track.formatDescriptions as! [CMFormatDescription]
            
            guard let passthroughFormatHint = trackFormatDescriptions.first else {
                throw CyanifyError.NoMediaData
            }
            
            // Create asset writer input with nil (passthrough) output settings
            let passthroughWriterInput = AVAssetWriterInput(mediaType: passthroughReaderOutput.mediaType, outputSettings: nil, sourceFormatHint: passthroughFormatHint)
            
            passthroughReaderOutputsAndWriterInputs.append((readerOutput: passthroughReaderOutput, writerInput: passthroughWriterInput))
        }
        
        return passthroughReaderOutputsAndWriterInputs
    }
    
    private func transferVideoTracks(videoReaderOutputsAndWriterInputs: [ReaderOutputAndWriterInput], group: DispatchGroup) {
        for (videoReaderOutput, videoWriterInput) in videoReaderOutputsAndWriterInputs {
            let perTrackDispatchQueue = DispatchQueue(label: "Track data transfer queue: \(videoReaderOutput) -> \(videoWriterInput).")
            
            // A block for changing color values of each video frame.
            let videoProcessor: (CMSampleBuffer) throws -> Void = { sampleBuffer in
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), CFGetTypeID(pixelBuffer) == CVPixelBufferGetTypeID() {
                    
                    let redComponentIndex = 1
                    do {
                        try pixelBuffer.removeARGBColorComponent(at: redComponentIndex)
                    } catch {}
                }
            }
            
            group.enter()
            transferSamplesAsynchronously(from: videoReaderOutput, toWriterInput: videoWriterInput, onQueue: perTrackDispatchQueue, sampleBufferProcessor: videoProcessor) {
                group.leave()
            }
        }
    }
    
    private func transferPassthroughTracks(passthroughReaderOutputsAndWriterInputs: [ReaderOutputAndWriterInput], group: DispatchGroup) {
        for (passthroughReaderOutput, passthroughWriterInput) in passthroughReaderOutputsAndWriterInputs {
            let perTrackDispatchQueue = DispatchQueue(label: "Track data transfer queue: \(passthroughReaderOutput) -> \(passthroughWriterInput).")
            
            group.enter()
            transferSamplesAsynchronously(from: passthroughReaderOutput, toWriterInput: passthroughWriterInput, onQueue: perTrackDispatchQueue) {
                group.leave()
            }
        }
    }
    
    private func transferSamplesAsynchronously(from readerOutput: AVAssetReaderOutput, toWriterInput writerInput: AVAssetWriterInput, onQueue queue: DispatchQueue, sampleBufferProcessor: ((CMSampleBuffer) throws -> ())? = nil, completionHandler: @escaping () -> ()
    ) {
        
        // Provide the asset writer input with a block to invoke whenever it wants to request more samples
        
        writerInput.requestMediaDataWhenReady(on: queue) {
            var isDone = false
            
            /*
                Loop, transferring one sample per iteration, until the asset writer
                input has enough samples. At that point, exit the callback block
                and the asset writer input will invoke the block again when it
                needs more samples.
            */
            while writerInput.isReadyForMoreMediaData {
                guard !self.isCancelled else {
                    isDone = true
                    break
                }
                
                // Grab next sample from the asset reader output.
                guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                    /*
                        At this point, the asset reader output has no more samples
                        to vend.
                    */
                    isDone = true
                    break
                }
                
                // Process the sample, if requested.
                do {
                    try sampleBufferProcessor?(sampleBuffer)
                } catch {
                    // This error will be picked back up in `readingAndWritingDidFinish()`.
                    self.sampleTransferError = error
                    isDone = true
                }
                
                // Append the sample to the asset writer input.
                guard writerInput.append(sampleBuffer) else {
                    /*
                        The sample buffer could not be appended. Error information
                        will be fetched from the asset writer in
                        `readingAndWritingDidFinish()`.
                    */
                    isDone = true
                    break
                }
            }
            
            if isDone {
                /*
                    Calling `markAsFinished()` on the asset writer input will both:
                        1. Unblock any other inputs that need more samples.
                        2. Cancel further invocations of this "request media data"
                           callback block.
                */
                writerInput.markAsFinished()
                
                // Tell the caller that we are done transferring samples.
                completionHandler()
            }
        }
    }
    
    private func readingAndWritingDidFinish(assetReader: AVAssetReader, assetWriter: AVAssetWriter) {
        if isCancelled {
            assetReader.cancelReading()
            assetWriter.cancelWriting()
        }
        
        // Deal with any error that occurred during processing of the video.
        guard sampleTransferError == nil else {
            assetReader.cancelReading()
            assetWriter.cancelWriting()
            finish(.failure(sampleTransferError!))
            return
        }
        
        // Evaluate result of reading samples.
        
        guard assetReader.status == .completed else {
            let result: Result
            
            switch assetReader.status {
                case .cancelled:
                    assetWriter.cancelWriting()
                    result = .cancellation
                
                case .failed:
                    // `error` property is non-nil in the `.Failed` status.
                    result = .failure(assetReader.error!)
                
                default:
                    fatalError("Unexpected terminal asset reader status: \(assetReader.status).")
            }
            
            finish(result)
            
            return
        }
        
        // Finish writing, (asynchronously) evaluate result of writing samples.
        
        assetWriter.finishWriting {
            let result: Result
            
            switch assetWriter.status {
                case .completed:
                    result = .success
                
                case .cancelled:
                    result = .cancellation
                
                case .failed:
                    // `error` property is non-nil in the `.Failed` status.
                    result = .failure(assetWriter.error!)
                
                default:
                    fatalError("Unexpected terminal asset writer status: \(assetWriter.status).")
            }
            
            self.finish(result)
        }
    }
    
    func finish(_ result: Result) {
        self.result = result
    }
}

extension CVPixelBuffer {
    /**
        Iterates through each pixel in the receiver (assumed to be in ARGB format) 
        and overwrites the color component at the given index with a zero. This
        has the effect of "cyanifying," "rosifying," etc (depending on the chosen
        color component) the overall image represented by the pixel buffer.
    */
    func removeARGBColorComponent(at componentIndex: size_t) throws {
        // CVPixelBufferLockFlags(CVOptionFlags(0))
        let lockBaseAddressResult = CVPixelBufferLockBaseAddress(self, .readOnly)
        
        guard lockBaseAddressResult == kCVReturnSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(lockBaseAddressResult), userInfo: nil)
        }
        
        let bufferHeight = CVPixelBufferGetHeight(self)
        
        let bufferWidth = CVPixelBufferGetWidth(self)
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(self)
        
        let bytesPerPixel = bytesPerRow / bufferWidth
        
        let base = CVPixelBufferGetBaseAddress(self)!.assumingMemoryBound(to: Int8.self)
        
        // For each pixel, zero out selected color component.
        for row in 0 ..< bufferHeight {
            for column in 0 ..< bufferWidth {
                let pixel: UnsafeMutablePointer<Int8> = base + (row * bytesPerRow) + (column * bytesPerPixel)
                pixel[componentIndex] = 0
            }
        }
        
        // CVPixelBufferLockFlags(CVOptionFlags(0))
        let unlockBaseAddressResult = CVPixelBufferUnlockBaseAddress(self, .readOnly)
        
        guard unlockBaseAddressResult == kCVReturnSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(unlockBaseAddressResult), userInfo: nil)
        }
    }
}

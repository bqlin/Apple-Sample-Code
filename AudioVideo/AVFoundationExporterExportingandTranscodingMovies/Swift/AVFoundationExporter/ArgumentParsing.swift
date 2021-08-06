/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	Parses command-line arguments and invokes the appropriate command
*/

import CoreMedia
import AVFoundation

// Use enums to enforce uniqueness of option labels.
enum LongLabel: String {
	case fileType = "filetype"
	case presetName = "preset"
	case deleteExistingFile = "replace"
	case logEverything = "verbose"
	case trimStartTime = "trim-start-time"
	case trimEndTime = "trim-end-time"
	case filterMetadata = "filter-metadata"
	case injectMetadata = "inject-metadata"
}

enum ShortLabel: String {
	case fileType = "f"
	case presetName = "p"
	case deleteExistingFile = "r"
	case logEverything = "v"
}

let executableName = NSString(string: Process().arguments!.first!).pathComponents.last!

func usage() {
	print("Usage:")
	print("\t\(executableName) <source path> <dest path> [options]")
	print("\t\(executableName) list-presets [<source path>]")
	print("") // newline
	print("In the first form, \(executableName) performs an export of the file at <source path>, writing the result to a file at <dest path>.  If no options are given, a passthrough export to a QuickTime Movie file is performed.")
	print("")
	print("In the second form, \(executableName) lists the available parameters to the -preset option.  If <source path> is specified, only the presets compatible with the file at <source path> will be listed.")
	print("")
	print("Options for first form:")
	print("\t-f, -filetype <UTI>")
	print("\t\tThe file type (e.g. com.apple.m4v-video) for the output file")
	print("")
	print("\t-p, -preset <preset>")
	print("\t\tThe preset name; use commmand list-presets to see available preset names")
	print("")
	print("\t-r, -replace YES")
	print("\t\tIf there is a pre-existing file at the destination location, remove it before exporting")
	print("")
	print("\t-v, -verbose YES")
	print("\t\tPrint more information about the execution")
	print("")
	print("\t-trim-start-time <seconds>")
	print("\t\tWhen specified, all media before the start time will be trimmed out")
	print("")
	print("\t-trim-end-time <seconds>")
	print("\t\tWhen specified, all media after the end time will be trimmed out")
	print("")
	print("\t-filter-metadata YES")
	print("\t\tFilter out privacy-sensitive metadata")
	print("")
	print("\t-inject-metadata YES")
	print("\t\tAdd simple metadata during export")
}

// Errors that can occur during argument parsing.
enum CommandLineError: Error, CustomStringConvertible {
	case TooManyArguments
	case TooFewArguments(descriptionOfRequiredArguments: String)
	case InvalidArgument(reason: String)
	
	var description: String {
		switch self {
            case .TooManyArguments:
                return "Too many arguments"
                
            case .TooFewArguments(let descriptionOfRequiredArguments):
                return "Missing argument(s).  Must specify \(descriptionOfRequiredArguments)."
                
            case .InvalidArgument(let reason):
                return "Invalid argument. \(reason)."
		}
	}
}

/// A set of convenience methods to use with our specific command line arguments.
extension UserDefaults {
	func string(forLongLabel longLabel: LongLabel) -> String? {
        return string(forKey: longLabel.rawValue)
	}
	
    func string(forShortLabel shortLabel: ShortLabel) -> String? {
        return string(forKey: shortLabel.rawValue)
	}
	
    func bool(forLongLabel longLabel: LongLabel) -> Bool {
        return bool(forKey: longLabel.rawValue)
	}
	
    func bool(forShortLabel shortLabel: ShortLabel) -> Bool {
        return bool(forKey: shortLabel.rawValue)
	}

    func time(forLongLabel longLabel: LongLabel) throws -> CMTime? {
        if let timeAsString = string(forLongLabel: longLabel) {
			guard let timeAsSeconds = Float64(timeAsString) else {
				throw CommandLineError.InvalidArgument(reason: "Non-numeric time \"\(timeAsString)\".")
			}

            return CMTime(seconds: timeAsSeconds, preferredTimescale: 600)
		}

        return nil
	}

    func time(forShortLabel shortLabel: ShortLabel) throws -> CMTime? {
        if let timeAsString = string(forShortLabel: shortLabel) {
			guard let timeAsSeconds = Float64(timeAsString) else {
				throw CommandLineError.InvalidArgument(reason: "Non-numeric time \"\(timeAsString)\".")
			}
		
            return CMTime(seconds: timeAsSeconds, preferredTimescale: 600)
		}

        return nil
	}
}

// Lists all presets, or the presets compatible with the file at the given path
func listPresets(sourcePath: String? = nil) {
    let presets: [String]
    
    switch sourcePath {
        case let sourcePath?:
            print("Presets compatible with \(sourcePath):.")
            
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let asset = AVAsset(url: sourceURL)
            presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
            
        case nil:
            print("Available presets:")
            presets = AVAssetExportSession.allExportPresets()
    }
    
    let presetsDescription = presets.joined(separator: "\n\t")
    
    print("\t\(presetsDescription)")
}

/// The main function that handles all of the command line argument parsing.
func actOnCommandLineArguments() {
    guard let arguments = Process().arguments else {
        return
    }
	let firstArgumentAfterExecutablePath: String? = (arguments.count >= 2) ? arguments[1] : nil
	
	if arguments.contains("-help") || arguments.contains("-h") {
		usage()
		exit(0)
	}
	
	do {
		switch firstArgumentAfterExecutablePath {
            case nil, "help"?:
                usage()
                exit(0)
                
            case "list-presets"?:
                if arguments.count == 3 {
                    listPresets(sourcePath: arguments[2])
                }
                else if arguments.count > 3 {
                    throw CommandLineError.TooManyArguments
                }
                else {
                    listPresets()
                }
                
            default:
                guard arguments.count >= 3 else {
                    throw CommandLineError.TooFewArguments(descriptionOfRequiredArguments: "source and dest paths")
                }
               
                let sourceURL = URL(fileURLWithPath: arguments[1])
                let destinationURL = URL(fileURLWithPath: arguments[2])
                
                var exporter = Exporter(sourceURL: sourceURL, destinationURL: destinationURL)
                
                let options = UserDefaults.standard
                
                if let fileType = options.string(forLongLabel: .fileType) ?? options.string(forShortLabel: .fileType) {
                    exporter.destinationFileType = AVFileType(rawValue: fileType)
                }
                
                if let presetName = options.string(forLongLabel: .presetName) ?? options.string(forShortLabel: .presetName) {
                    exporter.presetName = presetName
                }
                
                exporter.hasDeleteExistingFile = options.bool(forLongLabel: .deleteExistingFile) || options.bool(forShortLabel: .deleteExistingFile)
                
                exporter.isVerbose = options.bool(forLongLabel: .logEverything) || options.bool(forShortLabel: .logEverything)
                
                let trimStartTime = try options.time(forLongLabel: .trimStartTime)
                let trimEndTime = try options.time(forLongLabel: .trimEndTime)
                
                switch (trimStartTime, trimEndTime) {
                    case (nil, nil):
                        exporter.timeRange = nil
                        
                    case (let realStartTime?, nil):
                        exporter.timeRange = CMTimeRange(start: realStartTime, duration: CMTime.positiveInfinity)
                        
                    case (nil, let realEndTime?):
                        exporter.timeRange = CMTimeRange(start: CMTime.zero, end: realEndTime)
                        
                    case (let realStartTime?, let realEndTime?):
                        exporter.timeRange = CMTimeRange(start: realStartTime, end: realEndTime)
                }
                
                exporter.filterMetadata = options.bool(forLongLabel: .filterMetadata)
                
                exporter.injectMetadata = options.bool(forLongLabel: .injectMetadata)
                
                try exporter.export()
            }
	}
    catch let error as CommandLineError {
        print("error parsing arguments: \(error).")
        print("") // newline
        usage()
        exit(1)
    }
	catch let error as NSError {
        let highLevelFailure = error.localizedDescription
        var errorOutput = highLevelFailure
        
        if let detailedFailure = error.localizedRecoverySuggestion ?? error.localizedFailureReason {
            errorOutput += ": \(detailedFailure)"
        }
        
        print("error: \(errorOutput).")
        
        exit(1)
	}
}

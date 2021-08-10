/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 
  
 Command line tool for editing metadata
  
  
 */

@import Foundation;
@import AVFoundation;

#import <dispatch/dispatch.h>
#import <getopt.h>

static NSString * stringForDataDescription(NSData *data);
static void printMetadata(AVURLAsset *asset, BOOL doDescriptionOut);
static void printMetadataItems(NSArray *items, NSString *metadataFormat, BOOL doDescriptionOut);
static void printMetadataItemsToURL(NSArray *items, NSString *metadataFormat, NSURL *printURL);
static NSArray * metadataFromAssetDictionary(NSArray *sourceMetadata, NSDictionary *metadataDict, BOOL editingMode, NSString *metadataFormat);
static BOOL processMetadata(NSURL *sourceURL, NSURL *destURL, NSString *outputFileType, NSURL *printURL, NSDictionary *writeMetadata, NSDictionary *appendMetadata, BOOL doPrintOut, BOOL doDescriptionOut, NSString *metadataFormat);

static void PrintUsage()
{
	printf("\n\nUsage:");
	printf("\navmetadataeditor [-w] [-a] [ <options> ] src dst");
	printf("\navmetadataeditor [-p] [-o] [ <options> ] src");
	printf("\nsrc is a path to a local file.");
	printf("\ndst is a path to a destination file.");
	
	printf("\nOptions:\n");
	printf("\n  -w, --write-metadata=PLISTFILE");
	printf("\n\t\t  Use a PLISTFILE as metadata for the destination file");
	printf("\n  -a, --append-metadata=PLISTFILE");
	printf("\n\t\t  Use a PLISTFILE as metadata to merge with the source metadata for the destination file");
	printf("\n  -p, --print-metadata=PLISTFILE");
	printf("\n\t\t  Write in a PLISTFILE the metadata from the source file");
	printf("\n  -f, --file-type=UTI");
	printf("\n\t\t  Use UTI as output file type");
	printf("\n  -o, --output-metadata");
	printf("\n\t\t  Output the metadata from the source file");
	printf("\n  -d, --description-metadata");
	printf("\n\t\t  Output the metadata description from the source file");
	printf("\n  -q, --quicktime-metadata");
	printf("\n\t\t  Quicktime metadata format");
	printf("\n  -u, --quicktime-user-metadata");
	printf("\n\t\t  Quicktime user metadata format");
	printf("\n  -i, --iTunes-metadata");
	printf("\n\t\t  iTunes metadata format");
	printf("\n  -h, --help");
	printf("\n\t\t  Print this message and exit\n");
	exit(1);
}

static BOOL processMetadata(NSURL *sourceURL, NSURL *destURL, NSString *outputFileType, NSURL *printURL, NSDictionary *writeMetadata, NSDictionary *appendMetadata, BOOL doPrintOut, BOOL doDescriptionOut, NSString *metadataFormat)
{
	AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
	if (!asset) {
		printf("\nInvalid source, asset creation failure");
		return NO;
	}
	/*
	 Print to the standard output the metadata from the source URL
	 */
	if (doPrintOut || doDescriptionOut) {
		printMetadata(asset, doDescriptionOut);
	}
	
	NSArray *sourceMetadata = nil;
	if (nil != metadataFormat) {
		sourceMetadata = [asset metadataForFormat:metadataFormat];
	}
	else {
		sourceMetadata = [asset commonMetadata];
	}
	/*
	 Save to a plist the metadata from the source URL
	 */
	if (printURL) {
		printMetadataItemsToURL(sourceMetadata, metadataFormat, printURL);
	}
	if (!destURL)
		return YES;
	
	if (![asset isExportable])
		return NO;
	if (nil == writeMetadata && nil == appendMetadata)
		return NO;
	
	/*
	 Create an export session to export the new metadata
	 */
	AVAssetExportSession *session = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetPassthrough];
	if (![[session supportedFileTypes] containsObject:outputFileType])
		return NO;
	
	[session setOutputFileType:outputFileType];
	[session setOutputURL:destURL];
	
	if (writeMetadata) {
		[session setMetadata:metadataFromAssetDictionary(sourceMetadata, writeMetadata, NO, metadataFormat)];
	}
	else {
		[session setMetadata:metadataFromAssetDictionary(sourceMetadata, appendMetadata, YES, metadataFormat)];
	}
	
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	
	__block NSError *error = nil;
	__block BOOL succeeded = NO;
	[session exportAsynchronouslyWithCompletionHandler:^{
		
		if (AVAssetExportSessionStatusCompleted == session.status) {
			succeeded = YES;
		}
		else {
			succeeded = NO;
			if (session.error)
				error = session.error;
		}
		dispatch_semaphore_signal(semaphore);
	}];
	
	printf("\n0--------------------100%%\n");
	float progress = 0.;
	long resSemaphore = 0;
	/*
	 Monitor the progress
	 */
	do {
		resSemaphore = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
		float curProgress = session.progress;
		while (curProgress > progress) {
			fprintf(stderr, "*"); // Force to be flush without end of line
			progress += 0.05;
		}
	} while( resSemaphore );
	
	if (succeeded) {
		printf("\nSuccess\n");
	}
	else {
		printf("\nError: %s", [[error localizedDescription] UTF8String]);
		printf("\nFailure\n");
	}
	return succeeded;
}

/*
 Get a string from a NSData value formatted as follow: [ data length = ??, bytes = 0x?? ... ?? ]
 */
static NSString * stringForDataDescription(NSData *data)
{
	NSMutableString *str = [NSMutableString stringWithCapacity:64];
	NSUInteger length = [data length];
	const unsigned char *bytes = (const unsigned char *)[data bytes];
	int i;
	
	[str appendFormat:@"[ data length = %u, bytes = 0x", (unsigned int)length];
	
	// Dump 24 bytes of data in hex
	if (length <= 24) {
		for (i = 0; i < length; i++) {
			[str appendFormat:@"%02x", bytes[i]];
		}
	} else {
		for (i = 0; i < 16; i++) {
			[str appendFormat:@"%02x", bytes[i]];
		}
		[str appendFormat:@" ... "];
		for (i = length - 8; i < length; i++) {
			[str appendFormat:@"%02x", bytes[i]];
		}
	}
	[str appendFormat:@" ]"];
	
	return str;
}

static void printMetadata(AVURLAsset *asset, BOOL doDescriptionOut)
{
	/*
	 Print the common metadata
	 */
	NSArray *commonMetadata = [asset commonMetadata];
	if ([commonMetadata count] > 0) {
		printf("\n\n\nCommon metadata:\n");
		printMetadataItems(commonMetadata, nil, doDescriptionOut);
	}
	/*
	 Print all the metadata	formats
	 */
	for (NSString *format in [asset availableMetadataFormats]) {
		NSArray *items = [asset metadataForFormat:format];
		if ([items count] > 0) {
			printf("\n\n\nMetadata format: %s\n", [format UTF8String]);
			printMetadataItems(items, format, doDescriptionOut);
		}
	}
	
	printf("\n\n");
}

static void printMetadataItems(NSArray *items, NSString *metadataFormat, BOOL doDescriptionOut)
{
	for (AVMetadataItem *item in items) {
		if (doDescriptionOut) {
			printf("\n%s", [[item description] UTF8String]);
		}
		if (nil != metadataFormat) {
			NSString *identifier = [item identifier];
			id value = [item value];
			if ([value isKindOfClass:[NSData class]]) {
				printf("\n%s: %s", [identifier UTF8String], [stringForDataDescription(value) UTF8String]);
			}
			else {
				printf("\n%s: %s", [identifier UTF8String], [[item stringValue] UTF8String]);
			}
		}
		else {
			NSString *commonIdentifier = [AVMetadataItem identifierForKey:[item commonKey] keySpace:AVMetadataKeySpaceCommon];
			printf("\n%s: %s", [commonIdentifier UTF8String], [[item stringValue] UTF8String]);
		}
	}
}

static void printMetadataItemsToURL(NSArray *items, NSString *metadataFormat, NSURL *printURL)
{
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
	if ([items count]) {
		for (AVMetadataItem *item in items) {
			if (nil != metadataFormat) {
				dictionary[item.identifier] = item.value;
			}
			else {
				NSString *commonIdentifier = [AVMetadataItem identifierForKey:[item commonKey] keySpace:AVMetadataKeySpaceCommon];
				dictionary[commonIdentifier] = item.value;
			}
		}
	}
	[dictionary writeToURL:printURL atomically:YES];
}

static NSArray * metadataFromAssetDictionary(NSArray *sourceMetadata, NSDictionary *metadataDict, BOOL editingMode, NSString *metadataFormat)
{
	NSMutableDictionary *mutableMetadataDict = [NSMutableDictionary dictionaryWithDictionary:metadataDict];
	NSMutableArray *newMetadata = [NSMutableArray array];
	if (editingMode) {
		
		if ([sourceMetadata count]) {
			/*
			 Find the identifiers that exist in the dictionary and the metadata
			 */
			for (AVMetadataItem *item in sourceMetadata) {
				
				AVMutableMetadataItem *newItem = [item mutableCopy];
				if (nil != metadataFormat) {
					NSString *identifier = [newItem identifier];
					/*
					 If the identifier is present in the dictionary, change the value to the one from the dictionary
					 */
					if (mutableMetadataDict[identifier]) {
						newItem.value = mutableMetadataDict[identifier];
						[mutableMetadataDict removeObjectForKey:identifier];
					}
				}
				else {
					/*
					 If the identifier is present in the dictionary, change the value to the one from the dictionary
					 */
					NSString *commonIdentifier = [AVMetadataItem identifierForKey:[newItem commonKey] keySpace:AVMetadataKeySpaceCommon];
					if (mutableMetadataDict[commonIdentifier]) {
						newItem.value = mutableMetadataDict[commonIdentifier];
						[mutableMetadataDict removeObjectForKey:commonIdentifier];
					}
				}
				if (newItem.value) {
					[newMetadata addObject:newItem];
				}
			}
		}
	}
	
	for (NSString *identifier in [mutableMetadataDict keyEnumerator]) {
		id value = [mutableMetadataDict objectForKey:identifier];
		if (value) {
			AVMutableMetadataItem *newItem = [AVMutableMetadataItem metadataItem];
			[newItem setIdentifier:identifier];
			[newItem setLocale:[NSLocale currentLocale]];
			[newItem setValue:value];
			[newItem setExtraAttributes:nil];
			[newMetadata addObject:newItem];
		}
	}
	return newMetadata;
}

int main (int argc, const char * argv[])
{
	BOOL result = YES;
	@autoreleasepool
	{
		NSFileManager *fm = [NSFileManager defaultManager];
		
		static struct option longopts[] = {
			{"write-metadata", required_argument, NULL, 'w'},
			{"append-metadata", required_argument, NULL, 'a'},
			{"print-metadata", required_argument, NULL, 'p'},
			{"file-type", required_argument, NULL, 'f'},
			{"output-metadata", no_argument, NULL, 'o'},
			{"description-metadata", no_argument, NULL, 'd'},
			{"quicktime-metadata", no_argument, NULL, 'q'},
			{"quicktime-user-metadata", no_argument, NULL, 'u'},
			{"itunes-metadata", no_argument, NULL, 'i'},
			{"help", no_argument, NULL, 'h'},
			{0, 0, 0, 0}
		};
		const char *shortopts = "w:a:p:f:odquih";
		
		int c = -1;
		
		NSURL *sourceURL = nil;
		NSURL *destURL = nil;
		NSURL *printURL = nil;
		NSString *outputFileType = AVFileTypeQuickTimeMovie;
		
		NSDictionary *writeMetadata = nil;
		NSDictionary *appendMetadata = nil;
		NSString *metadataFormat = nil;
		
		BOOL doPrintOut = NO;
		BOOL doDescriptionOut = NO;
		BOOL needDest = NO;
		
		c = getopt_long(argc, (char * const *)argv, shortopts, longopts, NULL);
		while (c != -1) {
			switch (c)
			{
				case 'w':
				{
					needDest = YES;
					NSString *filePath = [fm stringWithFileSystemRepresentation:optarg length:strlen(optarg)];
					writeMetadata = [NSDictionary dictionaryWithContentsOfFile:filePath];
					if (!writeMetadata) {
						printf("\nError: '%s' does not point to a valid property list file", optarg);
						PrintUsage();
					}
					break;
				}
				case 'a':
				{
					needDest = YES;
					NSString *filePath = [fm stringWithFileSystemRepresentation:optarg length:strlen(optarg)];
					appendMetadata = [NSDictionary dictionaryWithContentsOfFile:filePath];
					if (!appendMetadata) {
						printf("\nError: '%s' does not point to a valid property list file", optarg);
						PrintUsage();
					}
					break;
				}
				case 'p':
				{
					NSString *filePath = [fm stringWithFileSystemRepresentation:optarg length:strlen(optarg)];
					printURL = [NSURL fileURLWithPath:filePath isDirectory:NO];
					break;
				}
				case 'o':
				{
					doPrintOut = YES;
					break;
				}
				case 'd':
				{
					doDescriptionOut = YES;
					break;
				}
				case 'q':
				{
					// QuickTime metadata format
					metadataFormat = AVMetadataFormatQuickTimeMetadata;
					break;
				}
				case 'u':
				{
					// QuickTime user metadata (udta) format
					metadataFormat = AVMetadataFormatQuickTimeUserData;
					break;
				}
				case 'i':
				{
					// iTunes format
					metadataFormat = AVMetadataFormatiTunesMetadata;
					break;
				}
				case 'f':
				{
					/*
					 Output file format use during export, could be the following:
					 com.apple.quicktime-movie
					 public.mpeg-4
					 com.apple.m4v-video
					 com.apple.m4a-audio
					 public.3gpp
					 */
					outputFileType = [NSString stringWithCString:optarg encoding:NSMacOSRomanStringEncoding];
					if (!outputFileType)
					{
						printf("Error: '%s' is not a valid UTI\n", optarg);
						PrintUsage();
					}
					break;
				}
				case 'h':
				default:
					PrintUsage();
					break;
			}
			
			c = getopt_long(argc, (char * const *)argv, shortopts, longopts, NULL);
		}
		
		if (argc <= 2) {
			printf("\nMissing arguments");
			PrintUsage();
		}
		
		int nextArgIndex = optind;
		if (nextArgIndex >= argc) {
			printf("\nMissing source");
			PrintUsage();
		}
		const char *sourceInput = argv[nextArgIndex];
		NSString *filePath = [fm stringWithFileSystemRepresentation:sourceInput length:strlen(sourceInput)];
		sourceURL = [NSURL URLWithString:filePath];
		if (![sourceURL scheme]) {
			// No URL scheme, assuming file path
			sourceURL = [NSURL fileURLWithPath:filePath isDirectory:NO];
		}
		if (!sourceURL) {
			printf("\nInvalid source");
			PrintUsage();
		}
		++nextArgIndex;
		
		if (needDest) {
			if (nextArgIndex >= argc) {
				printf("\nMissing destination");
				PrintUsage();
			}
			const char *destInput = argv[nextArgIndex];
			NSString *destPath = [fm stringWithFileSystemRepresentation:destInput length:strlen(destInput)];
			destURL = [NSURL fileURLWithPath:destPath isDirectory:NO];
			if (nil == destURL) {
				printf("\nInvalid destination");
				PrintUsage();
			}
		}
		
		result = processMetadata(sourceURL, destURL, outputFileType, printURL, writeMetadata, appendMetadata, doPrintOut, doDescriptionOut, metadataFormat);
	}
	
	return (!result);
}


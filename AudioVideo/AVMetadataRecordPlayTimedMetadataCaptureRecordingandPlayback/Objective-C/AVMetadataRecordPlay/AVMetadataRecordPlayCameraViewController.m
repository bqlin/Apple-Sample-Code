/*
	Copyright (C) 2017 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	View controller for camera interface.
*/

@import AVFoundation;
@import CoreLocation;
@import CoreMedia;
@import Photos;

#import "AVMetadataRecordPlayCameraViewController.h"
#import "AVMetadataRecordPlayCameraPreviewView.h"

static void * SessionRunningContext = &SessionRunningContext;

typedef NS_ENUM( NSInteger, AVMetadataRecordPlaySetupResult ) {
	AVMetadataRecordPlaySetupResultSuccess,
	AVMetadataRecordPlaySetupResultCameraNotAuthorized,
	AVMetadataRecordPlaySetupResultSessionConfigurationFailed
};

@interface AVCaptureDeviceDiscoverySession (Utilities)

- (NSInteger)uniqueDevicePositionsCount;

@end

@implementation AVCaptureDeviceDiscoverySession (Utilities)

- (NSInteger)uniqueDevicePositionsCount
{
	NSMutableArray<NSNumber *> *uniqueDevicePositions = [NSMutableArray array];
	
	for ( AVCaptureDevice *device in self.devices ) {
		if ( ! [uniqueDevicePositions containsObject:@(device.position)] ) {
			[uniqueDevicePositions addObject:@(device.position)];
		}
	}
	
	return uniqueDevicePositions.count;
}

@end

@interface AVMetadataRecordPlayCameraViewController () <AVCaptureFileOutputRecordingDelegate, CLLocationManagerDelegate>

// Session management
@property (nonatomic, weak) IBOutlet AVMetadataRecordPlayCameraPreviewView *previewView;

@property (nonatomic) AVMetadataRecordPlaySetupResult setupResult;
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;

// Device configuration
@property (nonatomic, weak) IBOutlet UIButton *cameraButton;
@property (nonatomic, weak) IBOutlet UILabel *cameraUnavailableLabel;

@property (nonatomic) AVCaptureDeviceDiscoverySession *videoDeviceDiscoverySession;

// Recording movies
@property (nonatomic, weak) IBOutlet UIButton *recordButton;
@property (nonatomic, weak) IBOutlet UIButton *resumeButton;
@property (nonatomic, weak) IBOutlet UIBarButtonItem *playerButton;

@property (nonatomic) AVCaptureMovieFileOutput *movieFileOutput;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;

// Location
@property (nonatomic) CLLocationManager *locationManager;
@property (nonatomic) AVCaptureMetadataInput *locationMetadataInput;

@end

@implementation AVMetadataRecordPlayCameraViewController

#pragma mark View Controller Life Cycle

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	// Disable UI. The UI is enabled if and only if the session starts running.
	self.cameraButton.enabled = NO;
	self.recordButton.enabled = NO;
	
	// Create the AVCaptureSession.
	self.session = [[AVCaptureSession alloc] init];
	
	// Create a device discovery session.
	NSArray<AVCaptureDeviceType> *deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeBuiltInDuoCamera];
	self.videoDeviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
	
	// Set up the video preview view.
	self.previewView.session = self.session;
	
	// Communicate with the session and other session objects on this queue.
	self.sessionQueue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL );
	
	self.setupResult = AVMetadataRecordPlaySetupResultSuccess;
	
	/*
		Check video authorization status. Video access is required and audio
		access is optional. If audio access is denied, audio is not recorded
		during movie recording.
	*/
	switch ( [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] )
	{
		case AVAuthorizationStatusAuthorized:
		{
			// The user has previously granted access to the camera.
			break;
		}
		case AVAuthorizationStatusNotDetermined:
		{
			/*
				The user has not yet been presented with the option to grant
				video access. We suspend the session queue to delay session
				setup until the access request has completed.
				
				Note that audio access will be implicitly requested when we
				create an AVCaptureDeviceInput for audio during session setup.
			*/
			dispatch_suspend( self.sessionQueue );
			[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^( BOOL granted ) {
				if ( ! granted ) {
					self.setupResult = AVMetadataRecordPlaySetupResultCameraNotAuthorized;
				}
				dispatch_resume( self.sessionQueue );
			}];
			break;
		}
		default:
		{
			// The user has previously denied access.
			self.setupResult = AVMetadataRecordPlaySetupResultCameraNotAuthorized;
			break;
		}
	}
	
	/*
		Setup the capture session.
		In general it is not safe to mutate an AVCaptureSession or any of its
		inputs, outputs, or connections from multiple threads at the same time.
		
		Why not do all of this on the main queue?
		Because -[AVCaptureSession startRunning] is a blocking call which can
		take a long time. We dispatch session setup to the sessionQueue so
		that the main queue isn't blocked, which keeps the UI responsive.
	*/
	dispatch_async( self.sessionQueue, ^{
		[self configureSession];
	} );
	
	// Set up Core Location so that we can record a location metadata track
	self.locationManager = [[CLLocationManager alloc] init];
	self.locationManager.delegate = self;
	[self.locationManager requestWhenInUseAuthorization];
	self.locationManager.distanceFilter = kCLDistanceFilterNone;
	self.locationManager.headingFilter = 5.0;
	self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	dispatch_async( self.sessionQueue, ^{
		switch ( self.setupResult )
		{
			case AVMetadataRecordPlaySetupResultSuccess:
			{
				// Only set up observers and start the session running if setup succeeded.
				[self addObservers];
				[self.session startRunning];
				self.sessionRunning = self.session.isRunning;
				break;
			}
			case AVMetadataRecordPlaySetupResultCameraNotAuthorized:
			{
				dispatch_async( dispatch_get_main_queue(), ^{
					NSString *message = NSLocalizedString( @"AVMetadataRecordPlay doesn't have permission to use the camera, please change privacy settings", @"Alert message when the user has denied access to the camera" );
					UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVMetadataRecordPlay" message:message preferredStyle:UIAlertControllerStyleAlert];
					UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
					[alertController addAction:cancelAction];
					// Provide quick access to Settings.
					UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"Settings", @"Alert button to open Settings" ) style:UIAlertActionStyleDefault handler:^( UIAlertAction *action ) {
						[[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
					}];
					[alertController addAction:settingsAction];
					[self presentViewController:alertController animated:YES completion:nil];
				} );
				break;
			}
			case AVMetadataRecordPlaySetupResultSessionConfigurationFailed:
			{
				dispatch_async( dispatch_get_main_queue(), ^{
					NSString *message = NSLocalizedString( @"Unable to capture media", @"Alert message when something goes wrong during capture session configuration" );
					UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVMetadataRecordPlay" message:message preferredStyle:UIAlertControllerStyleAlert];
					UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
					[alertController addAction:cancelAction];
					[self presentViewController:alertController animated:YES completion:nil];
				} );
				break;
			}
		}
	} );
}

- (void)viewDidDisappear:(BOOL)animated
{
	dispatch_async( self.sessionQueue, ^{
		if ( self.setupResult == AVMetadataRecordPlaySetupResultSuccess ) {
			[self.session stopRunning];
			[self removeObservers];
		}
	} );
	
	[super viewDidDisappear:animated];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
	[super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
	
	[coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
		UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
		AVCaptureVideoOrientation initialVideoOrientation = AVCaptureVideoOrientationPortrait;
		if ( statusBarOrientation != UIInterfaceOrientationUnknown ) {
			initialVideoOrientation = (AVCaptureVideoOrientation)statusBarOrientation;
		}
		
		self.previewView.videoPreviewLayer.connection.videoOrientation = initialVideoOrientation;
	} completion:nil];
}

#pragma mark Session Management

// Call this on the session queue.
- (void)configureSession
{
	if ( self.setupResult != AVMetadataRecordPlaySetupResultSuccess ) {
		return;
	}
	
	NSError *error = nil;
	
	[self.session beginConfiguration];
	
	// Add video input.
	
	// Choose the back dual camera if available, otherwise default to a wide angle camera.
	AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInDuoCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
	if ( ! videoDevice ) {
		// If the back dual camera is not available, default to the back wide angle camera.
		videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
		
		// In some cases where users break their phones, the back wide angle camera is not available. In this case, we should default to the front wide angle camera.
		if ( ! videoDevice ) {
			videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
		}
	}
	AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
	if ( ! videoDeviceInput ) {
		NSLog( @"Could not create video device input: %@", error );
		self.setupResult = AVMetadataRecordPlaySetupResultSessionConfigurationFailed;
		[self.session commitConfiguration];
		return;
	}
	if ( [self.session canAddInput:videoDeviceInput] ) {
		[self.session addInput:videoDeviceInput];
		self.videoDeviceInput = videoDeviceInput;
		
		dispatch_async( dispatch_get_main_queue(), ^{
			/*
				Why are we dispatching this to the main queue?
				Because AVCaptureVideoPreviewLayer is the backing layer for AVMetdataRecordPlayCameraPreviewView and UIView
				can only be manipulated on the main thread.
				Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
				on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
				
				Use the status bar orientation as the initial video orientation. Subsequent orientation changes are
				handled by -[AVMetadataRecordPlayCameraViewController viewWillTransitionToSize:withTransitionCoordinator:].
			*/
			UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
			AVCaptureVideoOrientation initialVideoOrientation = AVCaptureVideoOrientationPortrait;
			if ( statusBarOrientation != UIInterfaceOrientationUnknown ) {
				initialVideoOrientation = (AVCaptureVideoOrientation)statusBarOrientation;
			}
			
			self.previewView.videoPreviewLayer.connection.videoOrientation = initialVideoOrientation;
		} );
	}
	else {
		NSLog( @"Could not add video device input to the session" );
		self.setupResult = AVMetadataRecordPlaySetupResultSessionConfigurationFailed;
		[self.session commitConfiguration];
		return;
	}
	
	// Add audio input.
	AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
	AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
	if ( ! audioDeviceInput ) {
		NSLog( @"Could not create audio device input: %@", error );
	}
	if ( [self.session canAddInput:audioDeviceInput] ) {
		[self.session addInput:audioDeviceInput];
	}
	else {
		NSLog( @"Could not add audio device input to the session" );
	}
	
	self.backgroundRecordingID = UIBackgroundTaskInvalid;
	
	// Add movie file output.
	AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
	if ( [self.session canAddOutput:movieFileOutput] ) {
		[self.session addOutput:movieFileOutput];
		self.movieFileOutput = movieFileOutput;
		
		AVCaptureConnection *movieFileOutputVideoConnection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
		// Enable video video stabilization.
		if ( movieFileOutputVideoConnection.isVideoStabilizationSupported ) {
			movieFileOutputVideoConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
		}
		
		// Enable video orientation timed metadata.
		[movieFileOutput setRecordsVideoOrientationAndMirroringChanges:YES asMetadataTrackForConnection:movieFileOutputVideoConnection];
	}
	else {
		NSLog( @"Could not add movie file output to the session" );
		self.setupResult = AVMetadataRecordPlaySetupResultSessionConfigurationFailed;
		[self.session commitConfiguration];
		return;
	}
	
	// Make connections between all metadataInputPorts and the session.
	[self connectMetadataPorts];
	
	[self.session commitConfiguration];
}

- (IBAction)resumeInterruptedSession:(id)sender
{
	dispatch_async( self.sessionQueue, ^{
		/*
			The session might fail to start running, e.g., if a phone or FaceTime call is still
			using audio or video. A failure to start the session running will be communicated via
			a session runtime error notification. To avoid repeatedly failing to start the session
			running, we only try to restart the session running in the session runtime error handler
			if we aren't trying to resume the session running.
		*/
		[self.session startRunning];
		self.sessionRunning = self.session.isRunning;
		if ( ! self.session.isRunning ) {
			dispatch_async( dispatch_get_main_queue(), ^{
				NSString *message = NSLocalizedString( @"Unable to resume", @"Alert message when unable to resume the session running" );
				UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVMetadataRecordPlay" message:message preferredStyle:UIAlertControllerStyleAlert];
				UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
				[alertController addAction:cancelAction];
				[self presentViewController:alertController animated:YES completion:nil];
			} );
		}
		else {
			dispatch_async( dispatch_get_main_queue(), ^{
				self.resumeButton.hidden = YES;
			} );
		}
	} );
}

#pragma mark Device Configuration

- (IBAction)changeCamera:(id)sender
{
	self.cameraButton.enabled = NO;
	self.recordButton.enabled = NO;
	
	dispatch_async( self.sessionQueue, ^{
		AVCaptureDevice *currentVideoDevice = self.videoDeviceInput.device;
		AVCaptureDevicePosition currentPosition = currentVideoDevice.position;
		
		AVCaptureDevicePosition preferredPosition;
		AVCaptureDeviceType preferredDeviceType;
		
		switch ( currentPosition )
		{
			case AVCaptureDevicePositionUnspecified:
			case AVCaptureDevicePositionFront:
				preferredPosition = AVCaptureDevicePositionBack;
				preferredDeviceType = AVCaptureDeviceTypeBuiltInDuoCamera;
				break;
			case AVCaptureDevicePositionBack:
				preferredPosition = AVCaptureDevicePositionFront;
				preferredDeviceType = AVCaptureDeviceTypeBuiltInWideAngleCamera;
				break;
		}
		
		NSArray<AVCaptureDevice *> *devices = self.videoDeviceDiscoverySession.devices;
		AVCaptureDevice *newVideoDevice = nil;
		
		// First, look for a device with both the preferred position and device type.
		for ( AVCaptureDevice *device in devices ) {
			if ( device.position == preferredPosition && [device.deviceType isEqualToString:preferredDeviceType] ) {
				newVideoDevice = device;
				break;
			}
		}
		
		// Otherwise, look for a device with only the preferred position.
		if ( ! newVideoDevice ) {
			for ( AVCaptureDevice *device in devices ) {
				if ( device.position == preferredPosition ) {
					newVideoDevice = device;
					break;
				}
			}
		}
		
		if ( newVideoDevice ) {
			AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:newVideoDevice error:NULL];
			
			[self.session beginConfiguration];
			
			// Remove the existing device input first, since using the front and back camera simultaneously is not supported.
			[self.session removeInput:self.videoDeviceInput];
			
			if ( [self.session canAddInput:videoDeviceInput] ) {
				[[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:currentVideoDevice];
				
				[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:newVideoDevice];
				
				[self.session addInput:videoDeviceInput];
				self.videoDeviceInput = videoDeviceInput;
			}
			else {
				[self.session addInput:self.videoDeviceInput];
			}
			
			// Rewire connections for metadata tracks because we removed videoDeviceInput and added a new one.
			[self connectMetadataPorts];
			
			AVCaptureConnection *movieFileOutputVideoConnection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
			
			// Enable video stabilization.
			if ( movieFileOutputVideoConnection.isVideoStabilizationSupported ) {
				movieFileOutputVideoConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
			}
			
			// Enable video orientation timed metadata.
			[self.movieFileOutput setRecordsVideoOrientationAndMirroringChanges:YES asMetadataTrackForConnection:movieFileOutputVideoConnection];
			
			[self.session commitConfiguration];
		}
		
		dispatch_async( dispatch_get_main_queue(), ^{
			self.cameraButton.enabled = YES;
			self.recordButton.enabled = YES;
		} );
	} );
}

- (IBAction)focusAndExposeTap:(UIGestureRecognizer *)gestureRecognizer
{
	CGPoint devicePoint = [self.previewView.videoPreviewLayer captureDevicePointOfInterestForPoint:[gestureRecognizer locationInView:gestureRecognizer.view]];
	[self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:devicePoint monitorSubjectAreaChange:YES];
}

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
	dispatch_async( self.sessionQueue, ^{
		AVCaptureDevice *device = self.videoDeviceInput.device;
		NSError *error = nil;
		if ( [device lockForConfiguration:&error] ) {
			/*
				Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
				Call set(Focus/Exposure)Mode() to apply the new point of interest.
			*/
			if ( device.isFocusPointOfInterestSupported && [device isFocusModeSupported:focusMode] ) {
				device.focusPointOfInterest = point;
				device.focusMode = focusMode;
			}
			
			if ( device.isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode] ) {
				device.exposurePointOfInterest = point;
				device.exposureMode = exposureMode;
			}
			
			device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange;
			[device unlockForConfiguration];
		}
		else {
			NSLog( @"Could not lock device for configuration: %@", error );
		}
	} );
}

#pragma mark Recording Movies

- (IBAction)toggleMovieRecording:(id)sender
{
	/*
		Disable the Camera button until recording finishes, and disable
		the Record and Player buttons until recording starts or finishes.
		
		See the AVCaptureFileOutputRecordingDelegate methods.
	*/
	self.cameraButton.enabled = NO;
	self.recordButton.enabled = NO;
	self.playerButton.enabled = NO;
	
	/*
		Retrieve the video preview layer's video orientation on the main queue
		before entering the session queue. We do this to ensure UI elements are
		accessed on the main thread and session configuration is done on the session queue.
	*/
	AVCaptureVideoOrientation videoPreviewLayerVideoOrientation = self.previewView.videoPreviewLayer.connection.videoOrientation;
	
	dispatch_async( self.sessionQueue, ^{
		if ( ! self.movieFileOutput.isRecording ) {
			[self.locationManager startUpdatingLocation];
			if ( [UIDevice currentDevice].isMultitaskingSupported ) {
				/*
					Set up background task.
					This is needed because the -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:]
					callback is not received until AVCam returns to the foreground unless you request background execution time.
					This also ensures that there will be time to write the file to the photo library when AVCam is backgrounded.
					To conclude this background execution, -[endBackgroundTask:] is called in
					-[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:] after the recorded file has been saved.
				*/
				self.backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
			}
			
			// Update the orientation on the movie file output video connection before starting recording.
			AVCaptureConnection *movieFileOutputConnection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
			movieFileOutputConnection.videoOrientation = videoPreviewLayerVideoOrientation;
			
			// Start recording to a temporary file.
			NSString *outputFileName = [NSUUID UUID].UUIDString;
			NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[outputFileName stringByAppendingPathExtension:@"mov"]];
			[self.movieFileOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputFilePath] recordingDelegate:self];
		}
		else {
			[self.movieFileOutput stopRecording];
			[self.locationManager stopUpdatingLocation];
		}
	} );
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
	// Enable the Record button to let the user stop the recording.
	dispatch_async( dispatch_get_main_queue(), ^{
		self.recordButton.enabled = YES;
		[self.recordButton setTitle:NSLocalizedString( @"Stop", @"Recording button stop title" ) forState:UIControlStateNormal];
	});
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
	/*
		Note that currentBackgroundRecordingID is used to end the background task
		associated with this recording. This allows a new recording to be started,
		associated with a new UIBackgroundTaskIdentifier, once the movie file output's
		`recording` property is back to NO — which happens sometime after this method
		returns.
		
		Note: Since we use a unique file path for each recording, a new recording will
		not overwrite a recording currently being saved.
	*/
	UIBackgroundTaskIdentifier currentBackgroundRecordingID = self.backgroundRecordingID;
	self.backgroundRecordingID = UIBackgroundTaskInvalid;
	
	dispatch_block_t cleanup = ^{
		if ( [[NSFileManager defaultManager] fileExistsAtPath:outputFileURL.path] ) {
			[[NSFileManager defaultManager] removeItemAtPath:outputFileURL.path error:NULL];
		}
		
		if ( currentBackgroundRecordingID != UIBackgroundTaskInvalid ) {
			[[UIApplication sharedApplication] endBackgroundTask:currentBackgroundRecordingID];
		}
	};
	
	BOOL success = YES;
	
	if ( error ) {
		NSLog( @"Movie file finishing error: %@", error );
		success = [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue];
	}
	if ( success ) {
		// Check authorization status.
		[PHPhotoLibrary requestAuthorization:^( PHAuthorizationStatus status ) {
			if ( status == PHAuthorizationStatusAuthorized ) {
				// Save the movie file to the photo library and cleanup.
				[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
					// In iOS 9 and later, it's possible to move the file into the photo library without duplicating the file data.
					// This avoids using double the disk space during save, which can make a difference on devices with limited free disk space.
					PHAssetResourceCreationOptions *options = [[PHAssetResourceCreationOptions alloc] init];
					options.shouldMoveFile = YES;
					
					PHAssetCreationRequest *creationRequest = [PHAssetCreationRequest creationRequestForAsset];
					[creationRequest addResourceWithType:PHAssetResourceTypeVideo fileURL:outputFileURL options:options];
				} completionHandler:^( BOOL success, NSError *error ) {
					if ( ! success ) {
						NSLog( @"Could not save movie to photo library: %@", error );
					}
					cleanup();
				}];
			}
			else {
				cleanup();
			}
		}];
	}
	else {
		cleanup();
	}
	
	// Enable the Camera and Record buttons to let the user switch camera and start another recording.
	dispatch_async( dispatch_get_main_queue(), ^{
		// Only enable the ability to change camera if there are cameras in more than one position, i.e., front and back.
		self.cameraButton.enabled = ( self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1 );
		self.recordButton.enabled = YES;
		self.playerButton.enabled = YES;
		[self.recordButton setTitle:NSLocalizedString( @"Record", @"Recording button record title") forState:UIControlStateNormal];
	});
}

#pragma mark Metadata Support

- (void)connectMetadataPorts
{
	// Location metadata
	if ( ! [self isConnectionActiveWithInputPort:AVMetadataIdentifierQuickTimeMetadataLocationISO6709] ) {
		// Create a format description for the location metadata.
		NSArray *specs = @[@{ (__bridge id)kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier : AVMetadataIdentifierQuickTimeMetadataLocationISO6709,
							  (__bridge id)kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType   : (__bridge id)kCMMetadataDataType_QuickTimeMetadataLocation_ISO6709 }];
		
		CMFormatDescriptionRef locationMetadataDesc = NULL;
		CMMetadataFormatDescriptionCreateWithMetadataSpecifications(kCFAllocatorDefault, kCMMetadataFormatType_Boxed, (__bridge CFArrayRef)specs, &locationMetadataDesc);
		
		// Create the metadata input and add it to the session.
		AVCaptureMetadataInput *newLocationMetadataInput = [[AVCaptureMetadataInput alloc] initWithFormatDescription:locationMetadataDesc clock:CMClockGetHostTimeClock()];
		CFRelease( locationMetadataDesc );
		
		[self.session addInputWithNoConnections:newLocationMetadataInput];
		
		// Connect the location metadata input to the movie file output.
		AVCaptureInputPort *inputPort = newLocationMetadataInput.ports[0];
		[self.session addConnection:[AVCaptureConnection connectionWithInputPorts:@[inputPort] output:self.movieFileOutput]];
		
		[self setLocationMetadataInput:newLocationMetadataInput];
	}
	
	// Face metadata
	if ( ! [self isConnectionActiveWithInputPort:AVMetadataIdentifierQuickTimeMetadataDetectedFace] ) {
		[self connectSpecificMetadataPort:AVMetadataIdentifierQuickTimeMetadataDetectedFace];
	}
}

/**
	Connect a specified video input port to the output of AVCaptureSession.
	This is necessary because connections for certain ports are not added automatically on addInput.
*/
- (void)connectSpecificMetadataPort:(NSString *)metadataIdentifier
{
	// Iterate over the videoDeviceInput's ports (individual streams of media data) and find the port that matches metadataIdentifier.
	for ( AVCaptureInputPort *inputPort in self.videoDeviceInput.ports ) {
		CMFormatDescriptionRef desc = inputPort.formatDescription;
		if ( desc && ( kCMMediaType_Metadata == CMFormatDescriptionGetMediaType( desc ) ) ) {
			CFArrayRef metadataIdentifiers = CMMetadataFormatDescriptionGetIdentifiers( desc );
			if ( [(__bridge NSArray *)metadataIdentifiers containsObject:metadataIdentifier] )
			{
				// Add an AVCaptureConnection to connect the input port to the AVCaptureOutput (movieFileOutput).
				AVCaptureConnection *connection = [AVCaptureConnection connectionWithInputPorts:@[inputPort] output:self.movieFileOutput];
				[self.session addConnection:connection];
			}
		}
	}
}

/**
	Iterates through all the movieFileOutput’s connections and returns true if the
	input port for one of the connections matches portType.
*/
- (BOOL)isConnectionActiveWithInputPort:(NSString *)portType
{
	for ( AVCaptureConnection *connection in self.movieFileOutput.connections ) {
		for ( AVCaptureInputPort *port in connection.inputPorts ) {
			CMFormatDescriptionRef formatDescription = port.formatDescription;
			if ( formatDescription && ( CMFormatDescriptionGetMediaType( formatDescription ) == kCMMediaType_Metadata ) ) {
				CFArrayRef metadataIdentifiers = CMMetadataFormatDescriptionGetIdentifiers( formatDescription );
				if ( [(__bridge NSArray *)metadataIdentifiers containsObject:portType] ) {
					return connection.isActive;
				}
			}
		}
	}
	return NO;
}

#pragma mark KVO and Notifications

- (void)addObservers
{
	[self.session addObserver:self forKeyPath:@"running" options:NSKeyValueObservingOptionNew context:SessionRunningContext];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDeviceInput.device];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];
	
	/*
		A session can only run when the app is full screen. It will be interrupted
		in a multi-app layout, introduced in iOS 9, see also the documentation of
		AVCaptureSessionInterruptionReason. Add observers to handle these session
		interruptions and show a preview is paused message. See the documentation
		of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
	*/
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.session];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:self.session];
	
	// Listen for device orientation changes so keep the video orientation metadata capture connection's orientation up-to-date
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceOrientationDidChange) name:UIDeviceOrientationDidChangeNotification object:nil];
}

- (void)removeObservers
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[self.session removeObserver:self forKeyPath:@"running" context:SessionRunningContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( context == SessionRunningContext ) {
		BOOL isSessionRunning = [change[NSKeyValueChangeNewKey] boolValue];
		
		dispatch_async( dispatch_get_main_queue(), ^{
			// Only enable the ability to change camera if there are cameras in more than one position, i.e., front and back.
			self.cameraButton.enabled = isSessionRunning && ( self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1 );
			self.recordButton.enabled = isSessionRunning;
		} );
	}
	else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)subjectAreaDidChange:(NSNotification *)notification
{
	CGPoint devicePoint = CGPointMake( 0.5, 0.5 );
	[self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
	NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
	NSLog( @"Capture session runtime error: %@", error );
	
	/*
		Automatically try to restart the session running if media services were
		reset and the last start running succeeded. Otherwise, enable the user
		to try to resume the session running.
	*/
	if ( error.code == AVErrorMediaServicesWereReset ) {
		dispatch_async( self.sessionQueue, ^{
			if ( self.isSessionRunning ) {
				[self.session startRunning];
				self.sessionRunning = self.session.isRunning;
			}
			else {
				dispatch_async( dispatch_get_main_queue(), ^{
					self.resumeButton.hidden = NO;
				} );
			}
		} );
	}
	else {
		self.resumeButton.hidden = NO;
	}
}

- (void)sessionWasInterrupted:(NSNotification *)notification
{
	/*
		In some scenarios we want to enable the user to resume the session running.
		For example, if music playback is initiated via control center while
		using AVMetadataRecordPlay, then the user can let AVMetadataRecordPlay resume
		the session running, which will stop music playback. Note that stopping
		music playback in control center will not automatically resume the session
		running. Also note that it is not always possible to resume, see -[resumeInterruptedSession:].
	*/
	AVCaptureSessionInterruptionReason reason = [notification.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
	NSLog( @"Capture session was interrupted with reason %ld", (long)reason );
	
	if ( reason == AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient ||
		reason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient ) {
		// Simply fade-in a button to enable the user to try to resume the session running.
		self.resumeButton.alpha = 0.0;
		self.resumeButton.hidden = NO;
		[UIView animateWithDuration:0.25 animations:^{
			self.resumeButton.alpha = 1.0;
		}];
	}
	else if ( reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps ) {
		// Simply fade-in a label to inform the user that the camera is unavailable.
		self.cameraUnavailableLabel.alpha = 0.0;
		self.cameraUnavailableLabel.hidden = NO;
		[UIView animateWithDuration:0.25 animations:^{
			self.cameraUnavailableLabel.alpha = 1.0;
		}];
	}
}

- (void)sessionInterruptionEnded:(NSNotification *)notification
{
	NSLog( @"Capture session interruption ended" );
	
	if ( ! self.resumeButton.hidden ) {
		[UIView animateWithDuration:0.25 animations:^{
			self.resumeButton.alpha = 0.0;
		} completion:^( BOOL finished ) {
			self.resumeButton.hidden = YES;
		}];
	}
	if ( ! self.cameraUnavailableLabel.hidden ) {
		[UIView animateWithDuration:0.25 animations:^{
			self.cameraUnavailableLabel.alpha = 0.0;
		} completion:^( BOOL finished ) {
			self.cameraUnavailableLabel.hidden = YES;
		}];
	}
}

- (void)deviceOrientationDidChange
{
	// Update capture orientation based on device orientation (if device orientation is one that
	// should affect capture, i.e. not face up, face down, or unknown)
	UIDeviceOrientation deviceOrientation = UIDevice.currentDevice.orientation;
	if ( UIDeviceOrientationIsPortrait( deviceOrientation ) || UIDeviceOrientationIsLandscape( deviceOrientation ) ) {
		[self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo].videoOrientation = ( AVCaptureVideoOrientation )deviceOrientation;
	}
}

#pragma mark Location

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
	// If we are recording a movie, then send the location to the AVCaptureMetadataInput for
	// location data so that it can be put into a timed metadata track
	if ( self.movieFileOutput.recording ) {
		CLLocation *newLocation = locations.lastObject;
		if ( CLLocationCoordinate2DIsValid( newLocation.coordinate ) ) {
			NSString *iso6709Notation;
			AVMutableMetadataItem *newLocationMetadataItem = [[AVMutableMetadataItem alloc] init];
			newLocationMetadataItem.identifier = AVMetadataIdentifierQuickTimeMetadataLocationISO6709;
			newLocationMetadataItem.dataType = (__bridge NSString *)kCMMetadataDataType_QuickTimeMetadataLocation_ISO6709;
			
			// CoreLocation objects contain altitude information as well if the verticalAccuracy is positive.
			if ( newLocation.verticalAccuracy < 0.0 ) {
				iso6709Notation = [NSString stringWithFormat:@"%+08.4lf%+09.4lf/", newLocation.coordinate.latitude, newLocation.coordinate.longitude];
			}
			else {
				iso6709Notation = [NSString stringWithFormat:@"%+08.4lf%+09.4lf%+08.3lf/", newLocation.coordinate.latitude, newLocation.coordinate.longitude, newLocation.altitude];
			}
			newLocationMetadataItem.value = iso6709Notation;
			
			AVTimedMetadataGroup *metadataItemGroup = [[AVTimedMetadataGroup alloc] initWithItems:@[newLocationMetadataItem] timeRange:CMTimeRangeMake( CMClockGetTime( CMClockGetHostTimeClock() ), kCMTimeInvalid )];
			
			NSError *error = nil;
			if ( ! [self.locationMetadataInput appendTimedMetadataGroup:metadataItemGroup error:&error] ) {
			    NSLog( @"appendTimedMetadataGroup failed with error %@", error );
			}
		}
	}
}

@end

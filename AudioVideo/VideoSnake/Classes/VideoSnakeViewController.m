
/*
 <codex/>
 */

#import "VideoSnakeViewController.h"

#import <QuartzCore/QuartzCore.h>
#import "VideoSnakeSessionManager.h"
#import "OpenGLPixelBufferView.h"

@interface VideoSnakeViewController () <VideoSnakeSessionManagerDelegate>
{
	BOOL _addedObservers;
	BOOL _recording;
	UIBackgroundTaskIdentifier _backgroundRecordingID;
	BOOL _allowedToUseGPU;
}

@property (nonatomic, retain) IBOutlet UIBarButtonItem *recordButton;
@property (nonatomic, retain) IBOutlet UILabel *framerateLabel;
@property (nonatomic, retain) IBOutlet UILabel *dimensionsLabel;
@property (nonatomic, retain) NSTimer *labelTimer;
@property (nonatomic, retain) OpenGLPixelBufferView *previewView;
@property (nonatomic, retain) VideoSnakeSessionManager *videoSnakeSessionManager;

@end

@implementation VideoSnakeViewController

- (void)dealloc
{
	if ( _addedObservers ) {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:[UIApplication sharedApplication]];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:[UIApplication sharedApplication]];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:[UIDevice currentDevice]];
		[[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
	}

	[_recordButton release];
	[_framerateLabel release];
	[_dimensionsLabel release];
	[_labelTimer release];
	[_previewView release];
	[_videoSnakeSessionManager release];
    
    [super dealloc];
}

#pragma mark - View lifecycle

- (void)applicationDidEnterBackground
{
	// Avoid using the GPU in the background
	_allowedToUseGPU = NO;
	[self.videoSnakeSessionManager setRenderingEnabled:NO];

	[self.videoSnakeSessionManager stopRecording]; // no-op if we aren't recording
	
	 // We reset the OpenGLPixelBufferView to ensure all resources have been clear when going to the background.
	[self.previewView reset];
}

- (void)applicationWillEnterForeground
{
	_allowedToUseGPU = YES;
	[self.videoSnakeSessionManager setRenderingEnabled:YES];
}

- (void)viewDidLoad
{
    self.videoSnakeSessionManager = [[[VideoSnakeSessionManager alloc] init] autorelease];
    [self.videoSnakeSessionManager setDelegate:self callbackQueue:dispatch_get_main_queue()];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(applicationDidEnterBackground)
												 name:UIApplicationDidEnterBackgroundNotification
											   object:[UIApplication sharedApplication]];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(applicationWillEnterForeground)
												 name:UIApplicationWillEnterForegroundNotification
											   object:[UIApplication sharedApplication]];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(deviceOrientationDidChange)
												 name:UIDeviceOrientationDidChangeNotification
											   object:[UIDevice currentDevice]];
	
    // Keep track of changes to the device orientation so we can update the session manager
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
	
	_addedObservers = YES;
	
	// the willEnterForeground and didEnterBackground notifications are subesquently used to udpate _allowedToUseGPU
	_allowedToUseGPU = ( [[UIApplication sharedApplication] applicationState] != UIApplicationStateBackground );
	[self.videoSnakeSessionManager setRenderingEnabled:_allowedToUseGPU];
	
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self.videoSnakeSessionManager startRunning];
	
	self.labelTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updateLabels) userInfo:nil repeats:YES];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	
	[self.labelTimer invalidate];
	self.labelTimer = nil;
	
	[self.videoSnakeSessionManager stopRunning];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

#pragma mark - UI

- (IBAction)toggleRecording:(id)sender
{
    if ( _recording ) {
        [self.videoSnakeSessionManager stopRecording];
    }
    else {
		// Disable the idle timer while recording
		[UIApplication sharedApplication].idleTimerDisabled = YES;
		
		// Make sure we have time to finish saving the movie if the app is backgrounded during recording
		if ( [[UIDevice currentDevice] isMultitaskingSupported] )
			_backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{}];
		
		[[self recordButton] setEnabled:NO]; // re-enabled once recording has finished starting
		[[self recordButton] setTitle:@"Stop"];
		
		[self.videoSnakeSessionManager startRecording];
		
		_recording = YES;
	}
}

- (void)recordingStopped
{
	_recording = NO;
	[[self recordButton] setEnabled:YES];
	[[self recordButton] setTitle:@"Record"];
	
	[UIApplication sharedApplication].idleTimerDisabled = NO;
	
	[[UIApplication sharedApplication] endBackgroundTask:_backgroundRecordingID];
	_backgroundRecordingID = UIBackgroundTaskInvalid;
}

- (void)setupPreviewView
{
    // Set up GL view
    self.previewView = [[[OpenGLPixelBufferView alloc] initWithFrame:CGRectZero] autorelease];
	self.previewView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
	
	UIInterfaceOrientation currentInterfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    self.previewView.transform = [self.videoSnakeSessionManager transformFromVideoBufferOrientationToOrientation:(AVCaptureVideoOrientation)currentInterfaceOrientation withAutoMirroring:YES]; // Front camera preview should be mirrored

    [self.view insertSubview:self.previewView atIndex:0];
    CGRect bounds = CGRectZero;
    bounds.size = [self.view convertRect:self.view.bounds toView:self.previewView].size;
    self.previewView.bounds = bounds;
    self.previewView.center = CGPointMake(self.view.bounds.size.width/2.0, self.view.bounds.size.height/2.0);	
}

- (void)deviceOrientationDidChange
{
    UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];
	
	// Update recording orientation if device changes to portrait or landscape orientation (but not face up/down)
    if ( UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation) )
        [self.videoSnakeSessionManager setRecordingOrientation:(AVCaptureVideoOrientation)deviceOrientation];
}

- (void)updateLabels
{	
	NSString *frameRateString = [NSString stringWithFormat:@"%d FPS", (int)roundf(self.videoSnakeSessionManager.videoFrameRate)];
	[self.framerateLabel setText:frameRateString];
	
	NSString *dimensionsString = [NSString stringWithFormat:@"%d x %d", self.videoSnakeSessionManager.videoDimensions.width, self.videoSnakeSessionManager.videoDimensions.height];
	[self.dimensionsLabel setText:dimensionsString];
}

- (void)showError:(NSError *)error
{
	UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[error localizedDescription]
														message:[error localizedFailureReason]
													   delegate:nil
											  cancelButtonTitle:@"OK"
											  otherButtonTitles:nil];
	[alertView show];
	[alertView release];
}

#pragma mark - VideoSnakeSessionManagerDelegate

- (void)sessionManager:(VideoSnakeSessionManager *)sessionManager didStopRunningWithError:(NSError *)error
{
	[self showError:error];
	
	[[self recordButton] setEnabled:NO];
}

// Preview
- (void)sessionManager:(VideoSnakeSessionManager *)sessionManager previewPixelBufferReadyForDisplay:(CVPixelBufferRef)previewPixelBuffer
{
	if ( ! _allowedToUseGPU )
		return;
	
	if ( ! self.previewView )
		[self setupPreviewView];
	
	[self.previewView displayPixelBuffer:previewPixelBuffer];
}

- (void)sessionManagerDidRunOutOfPreviewBuffers:(VideoSnakeSessionManager *)sessionManager
{
	if ( _allowedToUseGPU )
		[self.previewView flushPixelBufferCache];
}

// Recording
- (void)sessionManagerRecordingDidStart:(VideoSnakeSessionManager *)manager
{
	[[self recordButton] setEnabled:YES];
}

- (void)sessionManagerRecordingWillStop:(VideoSnakeSessionManager *)manager
{
	// Disable record button until we are ready to start another recording
	[[self recordButton] setEnabled:NO];
	[[self recordButton] setTitle:@"Record"];
}

- (void)sessionManagerRecordingDidStop:(VideoSnakeSessionManager *)manager
{
	[self recordingStopped];
}

- (void)sessionManager:(VideoSnakeSessionManager *)manager recordingDidFailWithError:(NSError *)error
{
	[self recordingStopped];
	[self showError:error];
}

@end

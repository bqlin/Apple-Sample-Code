/*
See LICENSE.txt for this sample’s licensing information.

Abstract:
View controller for camera interface.
*/
@import AVFoundation;
@import Photos;

#import "AVCamCameraViewController.h"
#import "AVCamPreviewView.h"
#import "AVCamPhotoCaptureDelegate.h"

static void * SessionRunningContext = &SessionRunningContext;

typedef NS_ENUM(NSInteger, AVCamSetupResult) {
	AVCamSetupResultSuccess,
	AVCamSetupResultCameraNotAuthorized,
	AVCamSetupResultSessionConfigurationFailed
};

typedef NS_ENUM(NSInteger, AVCamCaptureMode) {
	AVCamCaptureModePhoto = 0,
	AVCamCaptureModeMovie = 1
};

typedef NS_ENUM(NSInteger, AVCamLivePhotoMode) {
	AVCamLivePhotoModeOn,
	AVCamLivePhotoModeOff
};

typedef NS_ENUM(NSInteger, AVCamDepthDataDeliveryMode) {
    AVCamDepthDataDeliveryModeOn,
    AVCamDepthDataDeliveryModeOff
};

@interface AVCaptureDeviceDiscoverySession (Utilities)

- (NSInteger)uniqueDevicePositionsCount;

@end

@implementation AVCaptureDeviceDiscoverySession (Utilities)

- (NSInteger)uniqueDevicePositionsCount
{
	NSMutableArray<NSNumber *> *uniqueDevicePositions = [NSMutableArray array];
	
	for (AVCaptureDevice *device in self.devices) {
		if (![uniqueDevicePositions containsObject:@(device.position)]) {
			[uniqueDevicePositions addObject:@(device.position)];
		}
	}
	
	return uniqueDevicePositions.count;
}

@end

@interface AVCamCameraViewController () <AVCaptureFileOutputRecordingDelegate>

// Session management.

/// 预览视图
@property (nonatomic, weak) IBOutlet AVCamPreviewView *previewView;
@property (nonatomic, weak) IBOutlet UISegmentedControl *captureModeControl;

@property (nonatomic) AVCamSetupResult setupResult;
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;

// Device configuration.
@property (nonatomic, weak) IBOutlet UIButton *cameraButton;
@property (nonatomic, weak) IBOutlet UILabel *cameraUnavailableLabel;
@property (nonatomic) AVCaptureDeviceDiscoverySession *videoDeviceDiscoverySession;

// Capturing photos.
@property (nonatomic, weak) IBOutlet UIButton *photoButton;
@property (nonatomic, weak) IBOutlet UIButton *livePhotoModeButton;
@property (nonatomic) AVCamLivePhotoMode livePhotoMode;
@property (nonatomic, weak) IBOutlet UILabel *capturingLivePhotoLabel;
@property (nonatomic, weak) IBOutlet UIButton *depthDataDeliveryButton;
@property (nonatomic) AVCamDepthDataDeliveryMode depthDataDeliveryMode;

@property (nonatomic) AVCapturePhotoOutput *photoOutput;
@property (nonatomic) NSMutableDictionary<NSNumber *, AVCamPhotoCaptureDelegate *> *inProgressPhotoCaptureDelegates;
@property (nonatomic) NSInteger inProgressLivePhotoCapturesCount;

// Recording movies.
@property (nonatomic, weak) IBOutlet UIButton *recordButton;
@property (nonatomic, weak) IBOutlet UIButton *resumeButton;

@property (nonatomic, strong) AVCaptureMovieFileOutput *movieFileOutput;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;

@end

@implementation AVCamCameraViewController

#pragma mark View Controller Life Cycle

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	// Disable UI. The UI is enabled if and only if the session starts running.
	self.cameraButton.enabled = NO;
	self.recordButton.enabled = NO;
	self.photoButton.enabled = NO;
	self.livePhotoModeButton.enabled = NO;
	self.captureModeControl.enabled = NO;
    self.depthDataDeliveryButton.enabled = NO;
	
	// 创建 AVCaptureSession.
	self.session = [[AVCaptureSession alloc] init];
	
	// 创建设备发现会话
	NSArray<AVCaptureDeviceType> *deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeBuiltInDualCamera]; // 广角相机、双摄相机
	self.videoDeviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
	
	// 配置预览视图
	self.previewView.session = self.session;
	
	// 在此队列上的对话和其他会话对象进行通信
	self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
	
	self.setupResult = AVCamSetupResultSuccess;
	
    // 检查视频授权状态。
    // 视频访问是必须的，音频访问是可选的。如果拒绝音频访问，则在录制视频期间不会录制音频。
	switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo])
	{
		case AVAuthorizationStatusAuthorized:
		{
			// 用户已对相机授权
			break;
		}
		case AVAuthorizationStatusNotDetermined:
		{
			// 尚未请求授权。暂停会话队列，延迟会话设置，直到授权。
            // 注意：当在创建会话设置时，为音频创建 AVCaptureDeviceInput 时，将隐式请求音频访问。
			dispatch_suspend(self.sessionQueue);
			[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
				if (!granted) {
					self.setupResult = AVCamSetupResultCameraNotAuthorized;
				}
				dispatch_resume(self.sessionQueue); // 权限请求结果到达后才恢复队列
			}];
			break;
		}
		default:
		{
			// 用户之前已拒绝访问
			self.setupResult = AVCamSetupResultCameraNotAuthorized;
			break;
		}
	}
	
	// 配置捕捉会话
    // 通常，同时改变 AVCaptureSession 或其来自多个线程的任何输入、输出和连接，这种操作是非线程安全的。
    // 为什么不在主队列完成这些操作？
    // 因为 `-[AVCaptureSession startRunning]` 调用会导致阻塞，是耗时操作。把会话设置放到其他队列，以便不阻塞主队列，保持 UI 响应。
	dispatch_async(self.sessionQueue, ^{
		[self configureSession];
	});
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	dispatch_async(self.sessionQueue, ^{
		switch (self.setupResult)
		{
			case AVCamSetupResultSuccess:
			{
				// 前面配置成功后，则设置监听并启动会话
				[self addObservers];
				[self.session startRunning];
				self.sessionRunning = self.session.isRunning;
				break;
			}
			case AVCamSetupResultCameraNotAuthorized:
			{ // 未授权则弹窗警告
				dispatch_async(dispatch_get_main_queue(), ^{
					NSString *message = NSLocalizedString(@"AVCam doesn't have permission to use the camera, please change privacy settings", @"Alert message when the user has denied access to the camera");
					UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCam" message:message preferredStyle:UIAlertControllerStyleAlert];
					UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Alert OK button") style:UIAlertActionStyleCancel handler:nil];
					[alertController addAction:cancelAction];
					// Provide quick access to Settings.
					UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Settings", @"Alert button to open Settings") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
						[[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
					}];
					[alertController addAction:settingsAction];
					[self presentViewController:alertController animated:YES completion:nil];
				});
				break;
			}
			case AVCamSetupResultSessionConfigurationFailed:
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					NSString *message = NSLocalizedString(@"Unable to capture media", @"Alert message when something goes wrong during capture session configuration");
					UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCam" message:message preferredStyle:UIAlertControllerStyleAlert];
					UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Alert OK button") style:UIAlertActionStyleCancel handler:nil];
					[alertController addAction:cancelAction];
					[self presentViewController:alertController animated:YES completion:nil];
				});
				break;
			}
		}
	});
}

- (void)viewDidDisappear:(BOOL)animated
{
	dispatch_async(self.sessionQueue, ^{
		if (self.setupResult == AVCamSetupResultSuccess) {
			[self.session stopRunning];
			[self removeObservers];
		}
	});
	
	[super viewDidDisappear:animated];
}

- (BOOL)shouldAutorotate
{
	// Disable autorotation of the interface when recording is in progress.
	return !self.movieFileOutput.isRecording;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskAll;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
	[super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
	
	UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
	
    // 在竖屏或横屏更新 AVCaptureVideoPreviewLayer 的视频方向
	if (UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation)) {
		self.previewView.videoPreviewLayer.connection.videoOrientation = (AVCaptureVideoOrientation)deviceOrientation;
	}
}

#pragma mark Session Management

// Call this on the session queue.
/// 配置 AVCaptureSession
- (void)configureSession
{
	if (self.setupResult != AVCamSetupResultSuccess) { // 前置条件配置成功后才能配置 AVCaptureSession
		return;
	}
	
	NSError *error = nil;
	
	[self.session beginConfiguration];
	
	// 设置会话时，我们不创建 AVCaptureMovieFileOutput，因为 AVCaptureMovieFileOutput 不支持使用 AVCaptureSessionPresetPhoto 进行视频录制
	self.session.sessionPreset = AVCaptureSessionPresetPhoto;
	
	// 添加视频输入
	
	// 如果可用选择后置双摄，否则使用后置广角摄像头
	AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInDualCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
	if (!videoDevice) {
		// 如果双摄不可用，则使用后置广角摄像头
		videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
		
		// 如果后置摄像头损坏，无法使用，则使用前置广角摄像头
		if (!videoDevice) {
			videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
		}
	}
    // 使用 AVCaptureDevice 创建 AVCaptureDeviceInput
	AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
	if (!videoDeviceInput) {
		NSLog(@"Could not create video device input: %@", error);
		self.setupResult = AVCamSetupResultSessionConfigurationFailed;
		[self.session commitConfiguration];
		return;
	}
    // 添加 AVCaptureDeviceInput 到 AVCaptureSession
	if ([self.session canAddInput:videoDeviceInput]) {
		[self.session addInput:videoDeviceInput];
		self.videoDeviceInput = videoDeviceInput;
		
        // 配置预览方向
		dispatch_async(dispatch_get_main_queue(), ^{
			// 为什么将其分配到主队列
            // 因为 AVCaptureVideoPreviewLayer 是 AVCamPreviewView 的图层，UIView 只能在主线程上操作。
            // 注意：作为上述规则的例外，不需在 AVCaptureVideoPreviewLayer 与其他会话操作的连接上，序列化视频方向更改。
            // 使用状态栏方向作为初始视频方向。后续方向更改由 `-[AVCamCameraViewController viewWillTransitionToSize:withTransitionCoordinator:]` 处理。
			UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
			AVCaptureVideoOrientation initialVideoOrientation = AVCaptureVideoOrientationPortrait;
			if (statusBarOrientation != UIInterfaceOrientationUnknown) {
				initialVideoOrientation = (AVCaptureVideoOrientation)statusBarOrientation;
			}
			
			self.previewView.videoPreviewLayer.connection.videoOrientation = initialVideoOrientation;
		});
	}
	else {
		NSLog(@"Could not add video device input to the session");
		self.setupResult = AVCamSetupResultSessionConfigurationFailed;
		[self.session commitConfiguration];
		return;
	}
	
	// 添加音频输入
	AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
	AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
	if (!audioDeviceInput) {
		NSLog(@"Could not create audio device input: %@", error);
	}
	if ([self.session canAddInput:audioDeviceInput]) {
		[self.session addInput:audioDeviceInput];
	}
	else {
		NSLog(@"Could not add audio device input to the session");
	}
	
	// 添加照片输出，只在此处初始化
	AVCapturePhotoOutput *photoOutput = [[AVCapturePhotoOutput alloc] init];
	if ([self.session canAddOutput:photoOutput]) {
		[self.session addOutput:photoOutput];
		self.photoOutput = photoOutput;
		
		self.photoOutput.highResolutionCaptureEnabled = YES; // 开启高分辨率静态图像捕捉
		self.photoOutput.livePhotoCaptureEnabled = self.photoOutput.livePhotoCaptureSupported; // 开启 live photo 捕捉
        self.photoOutput.depthDataDeliveryEnabled = self.photoOutput.depthDataDeliverySupported; // 开启深度数据捕捉
        
		self.livePhotoMode = self.photoOutput.livePhotoCaptureSupported ? AVCamLivePhotoModeOn : AVCamLivePhotoModeOff;
        self.depthDataDeliveryMode = self.photoOutput.depthDataDeliverySupported ? AVCamDepthDataDeliveryModeOn : AVCamDepthDataDeliveryModeOff;
        
		self.inProgressPhotoCaptureDelegates = [NSMutableDictionary dictionary];
		self.inProgressLivePhotoCapturesCount = 0;
	}
	else {
		NSLog(@"Could not add photo output to the session");
		self.setupResult = AVCamSetupResultSessionConfigurationFailed;
		[self.session commitConfiguration];
		return;
	}
	
	self.backgroundRecordingID = UIBackgroundTaskInvalid;
	
	[self.session commitConfiguration];
}

/// 恢复按钮事件
- (IBAction)resumeInterruptedSession:(id)sender
{
	dispatch_async(self.sessionQueue, ^{
		// 会话可能无法运行。例如，电话或 FaceTime 呼叫仍在使用麦克风和摄像头，将无法通过会话运行时错误通知启动即将通信的会话。为了避免重复无法启动会话，我们不尝试恢复运行的会话。
		[self.session startRunning];
		self.sessionRunning = self.session.isRunning;
		if (!self.session.isRunning) {
            // 启动失败，弹窗
			dispatch_async(dispatch_get_main_queue(), ^{
				NSString *message = NSLocalizedString(@"Unable to resume", @"Alert message when unable to resume the session running");
				UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCam" message:message preferredStyle:UIAlertControllerStyleAlert];
				UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Alert OK button") style:UIAlertActionStyleCancel handler:nil];
				[alertController addAction:cancelAction];
				[self presentViewController:alertController animated:YES completion:nil];
			});
		}
		else {
            // 启动成功，隐藏恢复按钮
			dispatch_async(dispatch_get_main_queue(), ^{
				self.resumeButton.hidden = YES;
			});
		}
	});
}

/// 捕捉模式切换事件
- (IBAction)toggleCaptureMode:(UISegmentedControl *)captureModeControl
{
	if (captureModeControl.selectedSegmentIndex == AVCamCaptureModePhoto) { // 拍照
		self.recordButton.enabled = NO;
		
		dispatch_async(self.sessionQueue, ^{
			// 从会话中删除 AVCaptureMovieFileOutput，因为 AVCaptureMovieFileOutput 不支持视频录制。此外，AVCaptureMovieFileOutput 也不支持 live photo 捕捉。
			[self.session beginConfiguration];
			[self.session removeOutput:self.movieFileOutput];
			self.session.sessionPreset = AVCaptureSessionPresetPhoto;
			
			self.movieFileOutput = nil;
			
			if (self.photoOutput.livePhotoCaptureSupported) {
				self.photoOutput.livePhotoCaptureEnabled = YES;
				
				dispatch_async(dispatch_get_main_queue(), ^{
					self.livePhotoModeButton.enabled = YES;
					self.livePhotoModeButton.hidden = NO;
				});
			}
            
            if (self.photoOutput.depthDataDeliverySupported) {
                self.photoOutput.depthDataDeliveryEnabled = YES;
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.depthDataDeliveryButton.hidden = NO;
                    self.depthDataDeliveryButton.enabled = YES;
                });
            }
			
			[self.session commitConfiguration];
		});
	}
	else if (captureModeControl.selectedSegmentIndex == AVCamCaptureModeMovie) { // 录制
		self.livePhotoModeButton.hidden = YES;
        self.depthDataDeliveryButton.hidden = YES;
		
		dispatch_async(self.sessionQueue, ^{
            // 创建 AVCaptureMovieFileOutput，并添加到 AVCaptureSession
			AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
			
			if ([self.session canAddOutput:movieFileOutput])
			{
				[self.session beginConfiguration];
				[self.session addOutput:movieFileOutput];
				self.session.sessionPreset = AVCaptureSessionPresetHigh;
				AVCaptureConnection *connection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
				if (connection.isVideoStabilizationSupported) {
					connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
				}
				[self.session commitConfiguration];
				
				self.movieFileOutput = movieFileOutput;
				
				dispatch_async(dispatch_get_main_queue(), ^{
					self.recordButton.enabled = YES;
				});
			}
		});
	}
}

#pragma mark Device Configuration

/// 切换摄像头事件
- (IBAction)changeCamera:(id)sender
{
	self.cameraButton.enabled = NO;
	self.recordButton.enabled = NO;
	self.photoButton.enabled = NO;
	self.livePhotoModeButton.enabled = NO;
	self.captureModeControl.enabled = NO;
	
	dispatch_async(self.sessionQueue, ^{
		AVCaptureDevice *currentVideoDevice = self.videoDeviceInput.device;
		AVCaptureDevicePosition currentPosition = currentVideoDevice.position;
		
		AVCaptureDevicePosition preferredPosition; // 偏好设备位置
		AVCaptureDeviceType preferredDeviceType; // 偏好设备类型
		
		switch (currentPosition)
		{
			case AVCaptureDevicePositionUnspecified:
			case AVCaptureDevicePositionFront:
				preferredPosition = AVCaptureDevicePositionBack;
				preferredDeviceType = AVCaptureDeviceTypeBuiltInDualCamera;
				break;
			case AVCaptureDevicePositionBack:
				preferredPosition = AVCaptureDevicePositionFront;
				preferredDeviceType = AVCaptureDeviceTypeBuiltInWideAngleCamera;
				break;
		}
		
		NSArray<AVCaptureDevice *> *devices = self.videoDeviceDiscoverySession.devices;
		AVCaptureDevice *newVideoDevice = nil;
		
		// 首先，寻找符合偏好位置和设备类型的设备
		for (AVCaptureDevice *device in devices) {
			if (device.position == preferredPosition && [device.deviceType isEqualToString:preferredDeviceType]) {
				newVideoDevice = device;
				break;
			}
		}
		
		// 其次，查找仅符合偏好位置的设备
		if (!newVideoDevice) {
			for (AVCaptureDevice *device in devices) {
				if (device.position == preferredPosition) {
					newVideoDevice = device;
					break;
				}
			}
		}
		
		if (newVideoDevice) {
			AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:newVideoDevice error:NULL];
			
			[self.session beginConfiguration];
			
			// 首先移除现有的设备输入，因为不支持同时使用前后摄像头
			[self.session removeInput:self.videoDeviceInput];
			
			if ([self.session canAddInput:videoDeviceInput]) {
				[[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:currentVideoDevice];
				
				[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:newVideoDevice];
				
				[self.session addInput:videoDeviceInput];
				self.videoDeviceInput = videoDeviceInput;
			}
			else {
				[self.session addInput:self.videoDeviceInput];
			}
			
			AVCaptureConnection *movieFileOutputConnection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
			if (movieFileOutputConnection.isVideoStabilizationSupported) {
				movieFileOutputConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
			}
			
			// 如果支持，则设置 live photo 和深度数据传输。更换摄像头时，视频设备与绘画断开连接，AVCapturePhotoOutput 对象的 `livePhotoCaptureEnabled` 属性置为 NO。新视频设备添加到会话后，则按需重开这两个属性。
			self.photoOutput.livePhotoCaptureEnabled = self.photoOutput.livePhotoCaptureSupported;
            self.photoOutput.depthDataDeliveryEnabled = self.photoOutput.depthDataDeliverySupported;
			
			[self.session commitConfiguration];
		}
		
		dispatch_async(dispatch_get_main_queue(), ^{
			self.cameraButton.enabled = YES;
			self.recordButton.enabled = self.captureModeControl.selectedSegmentIndex == AVCamCaptureModeMovie;
			self.photoButton.enabled = YES;
			self.livePhotoModeButton.enabled = YES;
			self.captureModeControl.enabled = YES;
            self.depthDataDeliveryButton.enabled = self.photoOutput.isDepthDataDeliveryEnabled;
            self.depthDataDeliveryButton.hidden = !self.photoOutput.depthDataDeliverySupported;
		});
	});
}

/// 对焦手势事件
- (IBAction)focusAndExposeTap:(UIGestureRecognizer *)gestureRecognizer
{
	CGPoint devicePoint = [self.previewView.videoPreviewLayer captureDevicePointOfInterestForPoint:[gestureRecognizer locationInView:gestureRecognizer.view]];
	[self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:devicePoint monitorSubjectAreaChange:YES];
}

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
	dispatch_async(self.sessionQueue, ^{
		AVCaptureDevice *device = self.videoDeviceInput.device;
		NSError *error = nil;
		if ([device lockForConfiguration:&error]) {
			// 设置（对焦/曝光）不会单独启动（对焦/曝光）操作
            // 调用设置（对焦/曝光）模式方法来应用新兴趣点
			if (device.isFocusPointOfInterestSupported && [device isFocusModeSupported:focusMode]) {
				device.focusPointOfInterest = point;
				device.focusMode = focusMode;
			}
			
			if (device.isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode]) {
				device.exposurePointOfInterest = point;
				device.exposureMode = exposureMode;
			}
			
			device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange;
			[device unlockForConfiguration];
		}
		else {
			NSLog(@"Could not lock device for configuration: %@", error);
		}
	});
}

#pragma mark Capturing Photos

/// 拍照事件
- (IBAction)capturePhoto:(id)sender
{
	// 进入会话队列之前，在主队列上检索视频预览图层的视频方向。这样做是为了确保在主线程上访问 UI 元素，并在会话队列上完成会话配置。
	AVCaptureVideoOrientation videoPreviewLayerVideoOrientation = self.previewView.videoPreviewLayer.connection.videoOrientation;

	dispatch_async(self.sessionQueue, ^{
		// 更新照片输出的连接方式以匹配预览图层的视频方向
		AVCaptureConnection *photoOutputConnection = [self.photoOutput connectionWithMediaType:AVMediaTypeVideo];
		photoOutputConnection.videoOrientation = videoPreviewLayerVideoOrientation;
		
		AVCapturePhotoSettings *photoSettings;
		// 支持捕捉 HEIF 照片，闪光灯设置为自动，并启动高分辨率照片
		if ([self.photoOutput.availablePhotoCodecTypes containsObject:AVVideoCodecTypeHEVC]) {
			photoSettings = [AVCapturePhotoSettings photoSettingsWithFormat:@{ AVVideoCodecKey : AVVideoCodecTypeHEVC }];
		}
		else {
			photoSettings = [AVCapturePhotoSettings photoSettings];
		}
        
        if (self.videoDeviceInput.device.isFlashAvailable) {
            photoSettings.flashMode = AVCaptureFlashModeAuto;
        }
		photoSettings.highResolutionPhotoEnabled = YES;
		if (photoSettings.availablePreviewPhotoPixelFormatTypes.count > 0) {
			photoSettings.previewPhotoFormat = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : photoSettings.availablePreviewPhotoPixelFormatTypes.firstObject };
		}
        // live photo 设置视频 URL
		if (self.livePhotoMode == AVCamLivePhotoModeOn && self.photoOutput.livePhotoCaptureSupported) { // Live Photo capture is not supported in movie mode.
			NSString *livePhotoMovieFileName = [NSUUID UUID].UUIDString;
			NSString *livePhotoMovieFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[livePhotoMovieFileName stringByAppendingPathExtension:@"mov"]];
			photoSettings.livePhotoMovieFileURL = [NSURL fileURLWithPath:livePhotoMovieFilePath];
		}
        
        if (self.depthDataDeliveryMode == AVCamDepthDataDeliveryModeOn && self.photoOutput.isDepthDataDeliverySupported) {
            photoSettings.depthDataDeliveryEnabled = YES;
        } else {
            photoSettings.depthDataDeliveryEnabled = NO;
        }
		
		// 为照片捕捉委托使用单独的对象来隔离每个捕捉的生命周期
		AVCamPhotoCaptureDelegate *photoCaptureDelegate = [[AVCamPhotoCaptureDelegate alloc] initWithRequestedPhotoSettings:photoSettings willCapturePhotoAnimation:^{
			dispatch_async(dispatch_get_main_queue(), ^{
				self.previewView.videoPreviewLayer.opacity = 0.0;
				[UIView animateWithDuration:0.25 animations:^{
					self.previewView.videoPreviewLayer.opacity = 1.0;
				}];
			});
		} livePhotoCaptureHandler:^(BOOL capturing) {
			// 由于捕捉 live photo 可能会重叠，因此需要跟踪正在进行的 live photo 捕捉数量，以确保在这些捕捉过程中 live photo 标签可见
			dispatch_async(self.sessionQueue, ^{
				if (capturing) {
					self.inProgressLivePhotoCapturesCount++;
				}
				else {
					self.inProgressLivePhotoCapturesCount--;
				}
				
				NSInteger inProgressLivePhotoCapturesCount = self.inProgressLivePhotoCapturesCount;
				dispatch_async(dispatch_get_main_queue(), ^{
					if (inProgressLivePhotoCapturesCount > 0) {
						self.capturingLivePhotoLabel.hidden = NO;
					}
					else if (inProgressLivePhotoCapturesCount == 0) {
						self.capturingLivePhotoLabel.hidden = YES;
					}
					else {
						NSLog(@"Error: In progress live photo capture count is less than 0");
					}
				});
			});
		} completionHandler:^(AVCamPhotoCaptureDelegate *photoCaptureDelegate) {
			// 捕捉完成后，删除对照片捕捉委托的引用，以便可以取消分配
			dispatch_async(self.sessionQueue, ^{
				self.inProgressPhotoCaptureDelegates[@(photoCaptureDelegate.requestedPhotoSettings.uniqueID)] = nil;
			});
		}];
		
        // photoOutput 保留对照片捕捉委托的若引用，因此我们将其存储在数组中以保持对此对象的请引用，直到捕捉完成。
		self.inProgressPhotoCaptureDelegates[@(photoCaptureDelegate.requestedPhotoSettings.uniqueID)] = photoCaptureDelegate;
		[self.photoOutput capturePhotoWithSettings:photoSettings delegate:photoCaptureDelegate];
	});
}

/// live photo 按钮事件
- (IBAction)toggleLivePhotoMode:(UIButton *)livePhotoModeButton
{
	dispatch_async(self.sessionQueue, ^{
		self.livePhotoMode = (self.livePhotoMode == AVCamLivePhotoModeOn) ? AVCamLivePhotoModeOff : AVCamLivePhotoModeOn;
		AVCamLivePhotoMode livePhotoMode = self.livePhotoMode;
		
		dispatch_async(dispatch_get_main_queue(), ^{
			if (livePhotoMode == AVCamLivePhotoModeOn) {
				[self.livePhotoModeButton setTitle:NSLocalizedString(@"Live Photo Mode: On", @"Live photo mode button on title") forState:UIControlStateNormal];
			}
			else {
				[self.livePhotoModeButton setTitle:NSLocalizedString(@"Live Photo Mode: Off", @"Live photo mode button off title") forState:UIControlStateNormal];
			}
		});
	});
}

/// 深度数据分发按钮事件
- (IBAction)toggleDepthDataDeliveryMode:(UIButton *)depthDataDeliveryButton
{
    dispatch_async(self.sessionQueue, ^{
        self.depthDataDeliveryMode = (self.depthDataDeliveryMode == AVCamDepthDataDeliveryModeOn) ? AVCamDepthDataDeliveryModeOff : AVCamDepthDataDeliveryModeOn;
        AVCamDepthDataDeliveryMode depthDataDeliveryMode = self.depthDataDeliveryMode;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (depthDataDeliveryMode == AVCamDepthDataDeliveryModeOn) {
                [self.depthDataDeliveryButton setTitle:NSLocalizedString(@"Depth Data Delivery: On", @"Depth Data mode button on title") forState:UIControlStateNormal];
            }
            else {
                [self.depthDataDeliveryButton setTitle:NSLocalizedString(@"Depth Data Delivery: Off", @"Depth Data mode button off title") forState:UIControlStateNormal];
            }
        });
    });
}

#pragma mark Recording Movies

/// 录制按钮事件
- (IBAction)toggleMovieRecording:(id)sender
{
	// 禁用切换相机按钮，直到录制结束，办禁用录制按钮，直到录制开始或结束
	self.cameraButton.enabled = NO;
	self.recordButton.enabled = NO;
	self.captureModeControl.enabled = NO;
	
	// 在进入会话之前，在主队列上获取视频预览图层的视频方向。确保在主线程上访问 UI 元素，并在会话队列上完成会话配置
	AVCaptureVideoOrientation videoPreviewLayerVideoOrientation = self.previewView.videoPreviewLayer.connection.videoOrientation;
	
	dispatch_async(self.sessionQueue, ^{
		if (!self.movieFileOutput.isRecording) {
			if ([UIDevice currentDevice].isMultitaskingSupported) {
				// 配置后台任务。
                // 需要这么做时因为方法 `-[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:]` 只有返回到前台才会收到回调。
                // 这也确保了当应用在后台时，有时间把文件写入相册。要结束此后台执行，在保存录制的文件后，在 `-[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:]` 调用 `-[endBackgroundTask:]`。
				self.backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
			}
			
			// 在开始录制前更新 AVCaptureConnection 的视频方向
			AVCaptureConnection *movieFileOutputConnection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
			movieFileOutputConnection.videoOrientation = videoPreviewLayerVideoOrientation;
			
			// 如果支持，使用 HEVC 编解码器
			if ([self.movieFileOutput.availableVideoCodecTypes containsObject:AVVideoCodecTypeHEVC]) {
				[self.movieFileOutput setOutputSettings:@{ AVVideoCodecKey : AVVideoCodecTypeHEVC } forConnection:movieFileOutputConnection];
			}	
			
			// 开始录制到临时文件
			NSString *outputFileName = [NSUUID UUID].UUIDString;
			NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[outputFileName stringByAppendingPathExtension:@"mov"]];
			[self.movieFileOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputFilePath] recordingDelegate:self];
		}
		else {
			[self.movieFileOutput stopRecording];
		}
	});
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
	// 启用录制按钮，以便用户停止录制
	dispatch_async(dispatch_get_main_queue(), ^{
		self.recordButton.enabled = YES;
		[self.recordButton setTitle:NSLocalizedString(@"Stop", @"Recording button stop title") forState:UIControlStateNormal];
	});
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
	// 注意：`currentBackgroundRecordingID` 用于结束与此录制相关的后台任务。这样，一旦电影文件输出的 `recoding` 返回 NO 时，就会启动与新 UIBackgroundTaskIdentifier 相关联的新录制。这种情况在此方法返回后的某个时间发生。
    // 注意：由于我盟为每个录制使用唯一的文件路径，因此新录制不会覆盖正在保存的录制内容。
	UIBackgroundTaskIdentifier currentBackgroundRecordingID = self.backgroundRecordingID;
	self.backgroundRecordingID = UIBackgroundTaskInvalid;
	
	dispatch_block_t cleanUp = ^{
		if ([[NSFileManager defaultManager] fileExistsAtPath:outputFileURL.path]) {
			[[NSFileManager defaultManager] removeItemAtPath:outputFileURL.path error:NULL];
		}
		
		if (currentBackgroundRecordingID != UIBackgroundTaskInvalid) {
			[[UIApplication sharedApplication] endBackgroundTask:currentBackgroundRecordingID];
		}
	};
	
	BOOL success = YES;
	
	if (error) {
		NSLog(@"Movie file finishing error: %@", error);
		success = [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue];
	}
	if (success) {
		// Check authorization status.
		[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
			if (status == PHAuthorizationStatusAuthorized) {
				// Save the movie file to the photo library and cleanup.
				[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
					PHAssetResourceCreationOptions *options = [[PHAssetResourceCreationOptions alloc] init];
					options.shouldMoveFile = YES;
					PHAssetCreationRequest *creationRequest = [PHAssetCreationRequest creationRequestForAsset];
					[creationRequest addResourceWithType:PHAssetResourceTypeVideo fileURL:outputFileURL options:options];
				} completionHandler:^(BOOL success, NSError *error) {
					if (!success) {
						NSLog(@"Could not save movie to photo library: %@", error);
					}
					cleanUp();
				}];
			}
			else {
				cleanUp();
			}
		}];
	}
	else {
		cleanUp();
	}
	
	// 启用切换相机和录制按钮，以便让用户开始新录制
	dispatch_async(dispatch_get_main_queue(), ^{
		// 只在有多个摄像头时方可启用切换摄像头
		self.cameraButton.enabled = (self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1);
		self.recordButton.enabled = YES;
		self.captureModeControl.enabled = YES;
		[self.recordButton setTitle:NSLocalizedString(@"Record", @"Recording button record title") forState:UIControlStateNormal];
	});
}

#pragma mark KVO and Notifications

- (void)addObservers
{
	[self.session addObserver:self forKeyPath:@"running" options:NSKeyValueObservingOptionNew context:SessionRunningContext];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDeviceInput.device];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];
	
	// 会话只能在程序全屏时运行。它将在 iOS 9 中引入的多应用程序布局中被中断（参阅 AVCaptureSessionInterruptionReason 文档）。添加观察者来处理这些会话中断并显示预览暂停消息。
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.session];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:self.session];
}

- (void)removeObservers
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[self.session removeObserver:self forKeyPath:@"running" context:SessionRunningContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context == SessionRunningContext) {
		BOOL isSessionRunning = [change[NSKeyValueChangeNewKey] boolValue];
		BOOL livePhotoCaptureSupported = self.photoOutput.livePhotoCaptureSupported;
		BOOL livePhotoCaptureEnabled = self.photoOutput.livePhotoCaptureEnabled;
        BOOL depthDataDeliverySupported = self.photoOutput.depthDataDeliverySupported;
        BOOL depthDataDeliveryEnabled = self.photoOutput.depthDataDeliveryEnabled;
        
		dispatch_async(dispatch_get_main_queue(), ^{
			// 只有在设备有多个摄像头时才开启切换摄像头功能
			self.cameraButton.enabled = isSessionRunning && (self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1);
			self.recordButton.enabled = isSessionRunning && (self.captureModeControl.selectedSegmentIndex == AVCamCaptureModeMovie);
			self.photoButton.enabled = isSessionRunning;
			self.captureModeControl.enabled = isSessionRunning;
			self.livePhotoModeButton.enabled = isSessionRunning && livePhotoCaptureEnabled;
			self.livePhotoModeButton.hidden = !(isSessionRunning && livePhotoCaptureSupported);
            self.depthDataDeliveryButton.enabled = isSessionRunning && depthDataDeliveryEnabled ;
            self.depthDataDeliveryButton.hidden = !(isSessionRunning && depthDataDeliverySupported);
		});
	}
	else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

/// 场景发生变化时通知事件
- (void)subjectAreaDidChange:(NSNotification *)notification
{
	CGPoint devicePoint = CGPointMake(0.5, 0.5);
	[self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
	NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
	NSLog(@"Capture session runtime error: %@", error);
	
	// 如果重置了媒体服务，并上次开始运行成功，则自动尝试重新启动会话。否则，显示恢复按钮。
	if (error.code == AVErrorMediaServicesWereReset) {
		dispatch_async(self.sessionQueue, ^{
			if (self.isSessionRunning) {
				[self.session startRunning];
				self.sessionRunning = self.session.isRunning;
			}
			else {
				dispatch_async(dispatch_get_main_queue(), ^{
					self.resumeButton.hidden = NO;
				});
			}
		});
	}
	else {
		self.resumeButton.hidden = NO;
	}
}

- (void)sessionWasInterrupted:(NSNotification *)notification
{
	// 在某些情况下，我们希望使用户能在恢复运行的会话。
    // 例如，如果在使用应用是，通过控制中心启动音乐播放，在用户可以让应用恢复会话，这将使音乐停止播放。注意，在控制中心不会自动恢复会话运行。另外，也不是总可以恢复的，参阅 `-[resumeInterruptedSession:]`。
	BOOL showResumeButton = NO;
	
	AVCaptureSessionInterruptionReason reason = [notification.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
	NSLog(@"Capture session was interrupted with reason %ld", (long)reason);
	
	if (reason == AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient ||
		reason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient) {
		showResumeButton = YES;
	}
	else if (reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps) {
		// 简单淡入标签告知用户相机不可用
		self.cameraUnavailableLabel.alpha = 0.0;
		self.cameraUnavailableLabel.hidden = NO;
		[UIView animateWithDuration:0.25 animations:^{
			self.cameraUnavailableLabel.alpha = 1.0;
		}];
	}
	
	if (showResumeButton) {
		// 简单淡入按钮，让用户尝试恢复会话运行
		self.resumeButton.alpha = 0.0;
		self.resumeButton.hidden = NO;
		[UIView animateWithDuration:0.25 animations:^{
			self.resumeButton.alpha = 1.0;
		}];
	}
}

- (void)sessionInterruptionEnded:(NSNotification *)notification
{
	NSLog(@"Capture session interruption ended");
	
	if (!self.resumeButton.hidden) {
		[UIView animateWithDuration:0.25 animations:^{
			self.resumeButton.alpha = 0.0;
		} completion:^(BOOL finished) {
			self.resumeButton.hidden = YES;
		}];
	}
	if (!self.cameraUnavailableLabel.hidden) {
		[UIView animateWithDuration:0.25 animations:^{
			self.cameraUnavailableLabel.alpha = 0.0;
		} completion:^(BOOL finished) {
			self.cameraUnavailableLabel.hidden = YES;
		}];
	}
}

@end

/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	View controller for camera interface.
*/

@import AVFoundation;
@import Photos;

#import "AVCamManualCameraViewController.h"
#import "AVCamManualPreviewView.h"
#import "AVCamManualPhotoCaptureDelegate.h"

static void * SessionRunningContext = &SessionRunningContext;
static void * FocusModeContext = &FocusModeContext;
static void * ExposureModeContext = &ExposureModeContext;
static void * WhiteBalanceModeContext = &WhiteBalanceModeContext;
static void * LensPositionContext = &LensPositionContext;
static void * ExposureDurationContext = &ExposureDurationContext;
static void * ISOContext = &ISOContext;
static void * ExposureTargetBiasContext = &ExposureTargetBiasContext;
static void * ExposureTargetOffsetContext = &ExposureTargetOffsetContext;
static void * DeviceWhiteBalanceGainsContext = &DeviceWhiteBalanceGainsContext;

/// 配置结果
typedef NS_ENUM(NSInteger, AVCamManualSetupResult) {
	AVCamManualSetupResultSuccess,
	AVCamManualSetupResultCameraNotAuthorized,
	AVCamManualSetupResultSessionConfigurationFailed
};

/// 采集模式
typedef NS_ENUM(NSInteger, AVCamManualCaptureMode) {
	AVCamManualCaptureModePhoto = 0,
	AVCamManualCaptureModeMovie = 1
};

@interface AVCamManualCameraViewController () <AVCaptureFileOutputRecordingDelegate>

@property (nonatomic, weak) IBOutlet AVCamManualPreviewView *previewView;
@property (nonatomic, weak) IBOutlet UISegmentedControl *captureModeControl;
@property (nonatomic, weak) IBOutlet UILabel *cameraUnavailableLabel;
@property (nonatomic, weak) IBOutlet UIButton *resumeButton;
@property (nonatomic, weak) IBOutlet UIButton *recordButton;
@property (nonatomic, weak) IBOutlet UIButton *cameraButton;
@property (nonatomic, weak) IBOutlet UIButton *photoButton;
@property (nonatomic, weak) IBOutlet UIButton *HUDButton;

@property (nonatomic, weak) IBOutlet UIView *manualHUD;

@property (nonatomic) NSArray *focusModes;
@property (nonatomic, weak) IBOutlet UIView *manualHUDFocusView;
@property (nonatomic, weak) IBOutlet UISegmentedControl *focusModeControl;
@property (nonatomic, weak) IBOutlet UISlider *lensPositionSlider;
@property (nonatomic, weak) IBOutlet UILabel *lensPositionNameLabel;
@property (nonatomic, weak) IBOutlet UILabel *lensPositionValueLabel;

@property (nonatomic) NSArray *exposureModes;
@property (nonatomic, weak) IBOutlet UIView *manualHUDExposureView;
@property (nonatomic, weak) IBOutlet UISegmentedControl *exposureModeControl;
@property (nonatomic, weak) IBOutlet UISlider *exposureDurationSlider;
@property (nonatomic, weak) IBOutlet UILabel *exposureDurationNameLabel;
@property (nonatomic, weak) IBOutlet UILabel *exposureDurationValueLabel;
@property (nonatomic, weak) IBOutlet UISlider *ISOSlider;
@property (nonatomic, weak) IBOutlet UILabel *ISONameLabel;
@property (nonatomic, weak) IBOutlet UILabel *ISOValueLabel;
@property (nonatomic, weak) IBOutlet UISlider *exposureTargetBiasSlider;
@property (nonatomic, weak) IBOutlet UILabel *exposureTargetBiasNameLabel;
@property (nonatomic, weak) IBOutlet UILabel *exposureTargetBiasValueLabel;
@property (nonatomic, weak) IBOutlet UISlider *exposureTargetOffsetSlider;
@property (nonatomic, weak) IBOutlet UILabel *exposureTargetOffsetNameLabel;
@property (nonatomic, weak) IBOutlet UILabel *exposureTargetOffsetValueLabel;

@property (nonatomic) NSArray *whiteBalanceModes;
@property (nonatomic, weak) IBOutlet UIView *manualHUDWhiteBalanceView;
@property (nonatomic, weak) IBOutlet UISegmentedControl *whiteBalanceModeControl;
@property (nonatomic, weak) IBOutlet UISlider *temperatureSlider;
@property (nonatomic, weak) IBOutlet UILabel *temperatureNameLabel;
@property (nonatomic, weak) IBOutlet UILabel *temperatureValueLabel;
@property (nonatomic, weak) IBOutlet UISlider *tintSlider;
@property (nonatomic, weak) IBOutlet UILabel *tintNameLabel;
@property (nonatomic, weak) IBOutlet UILabel *tintValueLabel;

@property (nonatomic, weak) IBOutlet UIView *manualHUDLensStabilizationView;
@property (nonatomic, weak) IBOutlet UISegmentedControl *lensStabilizationControl;

@property (nonatomic, weak) IBOutlet UIView *manualHUDPhotoView;
@property (nonatomic, weak) IBOutlet UISegmentedControl *rawControl;

// Session management
/// 会话串行队列
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCaptureDeviceDiscoverySession *videoDeviceDiscoverySession;
@property (nonatomic) AVCaptureDevice *videoDevice;
@property (nonatomic) AVCaptureMovieFileOutput *movieFileOutput;
@property (nonatomic) AVCapturePhotoOutput *photoOutput;

@property (nonatomic) NSMutableDictionary<NSNumber *, AVCamManualPhotoCaptureDelegate *> *inProgressPhotoCaptureDelegates;

// Utilities
@property (nonatomic) AVCamManualSetupResult setupResult;
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;

@end

@implementation AVCamManualCameraViewController

static const float kExposureDurationPower = 5; // 数字越大，滑块在短时长的灵敏度越高
static const float kExposureMinimumDuration = 1.0/1000; // 将曝光持续时长限制在有用范围内


#pragma mark View Controller Life Cycle

- (void)viewDidLoad
{
	[super viewDidLoad];

	// 在会话开始之前禁用 UI
	self.cameraButton.enabled = NO;
	self.recordButton.enabled = NO;
	self.photoButton.enabled = NO;
	self.captureModeControl.enabled = NO;
	self.HUDButton.enabled = NO;
	
	self.manualHUD.hidden = YES;
	self.manualHUDPhotoView.hidden = YES;
	self.manualHUDFocusView.hidden = YES;
	self.manualHUDExposureView.hidden = YES;
	self.manualHUDWhiteBalanceView.hidden = YES;
	self.manualHUDLensStabilizationView.hidden = YES;
	
	// 创建 AVCaptureSession
	self.session = [[AVCaptureSession alloc] init];

	// 创建设置发现会话
	NSArray<NSString *> *deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeBuiltInDuoCamera, AVCaptureDeviceTypeBuiltInTelephotoCamera];
	self.videoDeviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];

	// 配置预览视图
	self.previewView.session = self.session;
	
	// 在该队列上，该会话与其他会话对象通信
	self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);

	self.setupResult = AVCamManualSetupResultSuccess;

	// 检查摄像头授权。摄像头访问是必须的，麦克风选项是可选的。若麦克风不可访问，则在录制时静音。
	switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo])
	{
		case AVAuthorizationStatusAuthorized:
		{
			// 用户之前已授权
			break;
		}
		case AVAuthorizationStatusNotDetermined:
		{
			// 尚未请求摄像头权限
			// 挂起队列，延迟队列运行，直到授权完成
			// 注意：我们在会话设置期间为音频创建 AVCaptureDeviceInput 时，将隐式请求麦克风访问
			dispatch_suspend(self.sessionQueue);
			[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
				if (!granted) {
					self.setupResult = AVCamManualSetupResultCameraNotAuthorized;
				}
				dispatch_resume(self.sessionQueue);
			}];
			break;
		}
		default:
		{
			// 用户之前已拒绝授权
			self.setupResult = AVCamManualSetupResultCameraNotAuthorized;
			break;
		}
	}
	
	// 配置捕捉会话。
	// 通常，同时改变 AVCaptureSession 或来自多个线程 AVCaptureSession 的输入、输出、连接都不是线程安全的。
	// 为什么不在主队列上做这些操作？
	// 因为 `-[AVCaptureSession startRunning]` 会阻塞线程，可能耗时。我们将会话设置放到 sessionQueue 中取完成。
	// 这样就不会阻塞主队列，从而使 UI 保持响应。
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
			case AVCamManualSetupResultSuccess:
			{
				// 只有前面配置成功了，在设置监听并启动会话
				[self addObservers];
				[self.session startRunning];
				self.sessionRunning = self.session.isRunning;
				break;
			}
			case AVCamManualSetupResultCameraNotAuthorized:
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					NSString *message = NSLocalizedString(@"AVCamManual doesn't have permission to use the camera, please change privacy settings", @"Alert message when the user has denied access to the camera");
					UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCamManual" message:message preferredStyle:UIAlertControllerStyleAlert];
					UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Alert OK button") style:UIAlertActionStyleCancel handler:nil];
					[alertController addAction:cancelAction];
					// 快速访问“设置”
					UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Settings", @"Alert button to open Settings") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
						[[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
					}];
					[alertController addAction:settingsAction];
					[self presentViewController:alertController animated:YES completion:nil];
				});
				break;
			}
			case AVCamManualSetupResultSessionConfigurationFailed:
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					NSString *message = NSLocalizedString(@"Unable to capture media", @"Alert message when something goes wrong during capture session configuration");
					UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCamManual" message:message preferredStyle:UIAlertControllerStyleAlert];
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
		if (self.setupResult == AVCamManualSetupResultSuccess) {
			[self.session stopRunning];
			[self removeObservers];
		}
	});

	[super viewDidDisappear:animated];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
	[super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
	
	UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
	
	if (UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation )) {
		AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.previewView.layer;
		previewLayer.connection.videoOrientation = (AVCaptureVideoOrientation)deviceOrientation;
	}
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate
{
	// 在录制过程中禁用界面的自动旋转
	return !self.movieFileOutput.isRecording;
}

- (BOOL)prefersStatusBarHidden
{
	return YES;
}

#pragma mark HUD

- (void)configureManualHUD
{
	// 手动对焦
	self.focusModes = @[@(AVCaptureFocusModeContinuousAutoFocus), @(AVCaptureFocusModeLocked)];
	
	self.focusModeControl.enabled = (self.videoDevice != nil);
	self.focusModeControl.selectedSegmentIndex = [self.focusModes indexOfObject:@(self.videoDevice.focusMode)];
	for (NSNumber *mode in self.focusModes) {
		[self.focusModeControl setEnabled:[self.videoDevice isFocusModeSupported:mode.intValue] forSegmentAtIndex:[self.focusModes indexOfObject:mode]];
	}
	
	self.lensPositionSlider.minimumValue = 0.0;
	self.lensPositionSlider.maximumValue = 1.0;
	self.lensPositionSlider.value = self.videoDevice.lensPosition;
	self.lensPositionSlider.enabled = (self.videoDevice && self.videoDevice.focusMode == AVCaptureFocusModeLocked && [self.videoDevice isFocusModeSupported:AVCaptureFocusModeLocked]);
	
    // 手动曝光，平常所说的快门时间就是曝光时长
    self.exposureModes = @[@(AVCaptureExposureModeContinuousAutoExposure), @(AVCaptureExposureModeLocked), @(AVCaptureExposureModeCustom)];
    NSLog(@"exposure duration: %f ~ %f", CMTimeGetSeconds(_videoDevice.activeFormat.minExposureDuration), CMTimeGetSeconds(_videoDevice.activeFormat.maxExposureDuration));
    
    self.exposureModeControl.enabled = (self.videoDevice != nil);
    self.exposureModeControl.selectedSegmentIndex = [self.exposureModes indexOfObject:@(self.videoDevice.exposureMode)];
    for (NSNumber *mode in self.exposureModes) {
        [self.exposureModeControl setEnabled:[self.videoDevice isExposureModeSupported:mode.intValue] forSegmentAtIndex:[self.exposureModes indexOfObject:mode]];
    }
    
    // 使用 0-1 作为滑块范围，并执行从滑块值到实际设备曝光时长的非线性映射
    self.exposureDurationSlider.minimumValue = 0;
    self.exposureDurationSlider.maximumValue = 1;
	double exposureDurationSeconds = CMTimeGetSeconds(self.videoDevice.exposureDuration);
	double minExposureDurationSeconds = MAX(CMTimeGetSeconds(self.videoDevice.activeFormat.minExposureDuration), kExposureMinimumDuration);
	double maxExposureDurationSeconds = CMTimeGetSeconds(self.videoDevice.activeFormat.maxExposureDuration);
	// 从时间非线性映射到 UI 范围的 0-1
	double p = (exposureDurationSeconds - minExposureDurationSeconds) / (maxExposureDurationSeconds - minExposureDurationSeconds); // Scale to 0-1
    // 5√p
	self.exposureDurationSlider.value = pow(p, 1 / kExposureDurationPower); // Apply inverse power
	self.exposureDurationSlider.enabled = (self.videoDevice && self.videoDevice.exposureMode == AVCaptureExposureModeCustom);
	
    // ISO
    NSLog(@"ISO: %f ~ %f", _videoDevice.activeFormat.minISO, _videoDevice.activeFormat.maxISO);
	self.ISOSlider.minimumValue = self.videoDevice.activeFormat.minISO;
	self.ISOSlider.maximumValue = self.videoDevice.activeFormat.maxISO;
	self.ISOSlider.value = self.videoDevice.ISO;
	self.ISOSlider.enabled = (self.videoDevice.exposureMode == AVCaptureExposureModeCustom);
	
    // 曝光偏移（EV）
    NSLog(@"EV: %f ~ %f", _videoDevice.minExposureTargetBias, _videoDevice.maxExposureTargetBias);
	self.exposureTargetBiasSlider.minimumValue = self.videoDevice.minExposureTargetBias;
	self.exposureTargetBiasSlider.maximumValue = self.videoDevice.maxExposureTargetBias;
	self.exposureTargetBiasSlider.value = self.videoDevice.exposureTargetBias;
	self.exposureTargetBiasSlider.enabled = (self.videoDevice != nil);
	
	self.exposureTargetOffsetSlider.minimumValue = self.videoDevice.minExposureTargetBias;
	self.exposureTargetOffsetSlider.maximumValue = self.videoDevice.maxExposureTargetBias;
	self.exposureTargetOffsetSlider.value = self.videoDevice.exposureTargetOffset;
	self.exposureTargetOffsetSlider.enabled = NO;
	
	// 手动白平衡
	self.whiteBalanceModes = @[@(AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance), @(AVCaptureWhiteBalanceModeLocked)];
	
	self.whiteBalanceModeControl.enabled = (self.videoDevice != nil);
	self.whiteBalanceModeControl.selectedSegmentIndex = [self.whiteBalanceModes indexOfObject:@(self.videoDevice.whiteBalanceMode)];
	for (NSNumber *mode in self.whiteBalanceModes) { // 设置可用时才启用 UI
		[self.whiteBalanceModeControl setEnabled:[self.videoDevice isWhiteBalanceModeSupported:mode.intValue] forSegmentAtIndex:[self.whiteBalanceModes indexOfObject:mode]];
	}
	
	AVCaptureWhiteBalanceGains whiteBalanceGains = self.videoDevice.deviceWhiteBalanceGains;
	AVCaptureWhiteBalanceTemperatureAndTintValues whiteBalanceTemperatureAndTint = [self.videoDevice temperatureAndTintValuesForDeviceWhiteBalanceGains:whiteBalanceGains];
	
    // 色温
	self.temperatureSlider.minimumValue = 3000;
	self.temperatureSlider.maximumValue = 8000;
	self.temperatureSlider.value = whiteBalanceTemperatureAndTint.temperature;
	self.temperatureSlider.enabled = (self.videoDevice && self.videoDevice.whiteBalanceMode == AVCaptureWhiteBalanceModeLocked);
	
    // 色调
	self.tintSlider.minimumValue = -150;
	self.tintSlider.maximumValue = 150;
	self.tintSlider.value = whiteBalanceTemperatureAndTint.tint;
	self.tintSlider.enabled = (self.videoDevice && self.videoDevice.whiteBalanceMode == AVCaptureWhiteBalanceModeLocked);
	
    // 拍照时的镜头稳定
	self.lensStabilizationControl.enabled = (self.videoDevice != nil);
	self.lensStabilizationControl.selectedSegmentIndex = 0;
	[self.lensStabilizationControl setEnabled:self.photoOutput.isLensStabilizationDuringBracketedCaptureSupported forSegmentAtIndex:1];
	
    // raw photo
	self.rawControl.enabled = (self.videoDevice != nil);
	self.rawControl.selectedSegmentIndex = 0;
}

/// HUD 按钮点击事件
- (IBAction)toggleHUD:(id)sender
{
	self.manualHUD.hidden = !self.manualHUD.hidden;
}

/// 子菜单选项事件
- (IBAction)changeManualHUD:(id)sender
{
	UISegmentedControl *control = sender;
	
	self.manualHUDPhotoView.hidden = (control.selectedSegmentIndex == 0) ? NO : YES;
	self.manualHUDFocusView.hidden = (control.selectedSegmentIndex == 1) ? NO : YES;
	self.manualHUDExposureView.hidden = (control.selectedSegmentIndex == 2) ? NO : YES;
	self.manualHUDWhiteBalanceView.hidden = (control.selectedSegmentIndex == 3) ? NO : YES;
	self.manualHUDLensStabilizationView.hidden = (control.selectedSegmentIndex == 4) ? NO : YES;
}

- (void)setSlider:(UISlider *)slider highlightColor:(UIColor *)color
{
	slider.tintColor = color;
	
    // 配置 slider 颜色的同时设置其相关的标签颜色
	if (slider == self.lensPositionSlider) {
		self.lensPositionNameLabel.textColor = self.lensPositionValueLabel.textColor = slider.tintColor;
	}
	else if (slider == self.exposureDurationSlider) {
		self.exposureDurationNameLabel.textColor = self.exposureDurationValueLabel.textColor = slider.tintColor;
	}
	else if (slider == self.ISOSlider) {
		self.ISONameLabel.textColor = self.ISOValueLabel.textColor = slider.tintColor;
	}
	else if (slider == self.exposureTargetBiasSlider) {
		self.exposureTargetBiasNameLabel.textColor = self.exposureTargetBiasValueLabel.textColor = slider.tintColor;
	}
	else if (slider == self.temperatureSlider) {
		self.temperatureNameLabel.textColor = self.temperatureValueLabel.textColor = slider.tintColor;
	}
	else if (slider == self.tintSlider) {
		self.tintNameLabel.textColor = self.tintValueLabel.textColor = slider.tintColor;
	}
}

/// 滑块按下
- (IBAction)sliderTouchBegan:(id)sender
{
	UISlider *slider = (UISlider *)sender;
	[self setSlider:slider highlightColor:[UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:1.0]];
}

/// 滑块抬起
- (IBAction)sliderTouchEnded:(id)sender
{
	UISlider *slider = (UISlider *)sender;
	[self setSlider:slider highlightColor:[UIColor yellowColor]];
}

#pragma mark Session Management

/// 在会话队列上调用，配置完成后进入 HUD 的配置
- (void)configureSession
{
	if (self.setupResult != AVCamManualSetupResultSuccess) {
		return;
	}
	
	NSError *error = nil;
	
    // 开始配置会话
	[self.session beginConfiguration];
	// 默认为图片预设
	self.session.sessionPreset = AVCaptureSessionPresetPhoto;
	
	// 添加视频输入
	AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
	AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
	if (!videoDeviceInput) {
		NSLog(@"Could not create video device input: %@", error);
		self.setupResult = AVCamManualSetupResultSessionConfigurationFailed;
		[self.session commitConfiguration];
		return;
	}
	if ([self.session canAddInput:videoDeviceInput]) {
		[self.session addInput:videoDeviceInput];
		self.videoDeviceInput = videoDeviceInput;
		self.videoDevice = videoDevice;
		
		dispatch_async(dispatch_get_main_queue(), ^{
			// 为什么要在主队列上进行操作？
            // 因为 AVCamManualPreviewView 的图层是 AVCaptureVideoPreviewLayer，UIView 只能在主线程上操作。
            // 注意：作为上述规则的一个例外：没有必要在 AVCaptureVideoPreviewLayer 与其他会话操作的连接上序列化视频方向更改。
            // 使用状态栏方向我初始视频方向。后续方向变更由 -[AVCamManualCameraViewController viewWillTransitionToSize:withTransitionCoordinator:] 处理。
			UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
			AVCaptureVideoOrientation initialVideoOrientation = AVCaptureVideoOrientationPortrait;
			if (statusBarOrientation != UIInterfaceOrientationUnknown) {
				initialVideoOrientation = (AVCaptureVideoOrientation)statusBarOrientation;
			}
			
			AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.previewView.layer;
			previewLayer.connection.videoOrientation = initialVideoOrientation;
		});
	}
	else {
		NSLog(@"Could not add video device input to the session");
		self.setupResult = AVCamManualSetupResultSessionConfigurationFailed;
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
	
	// 添加图图像输出
	AVCapturePhotoOutput *photoOutput = [[AVCapturePhotoOutput alloc] init];
	if ([self.session canAddOutput:photoOutput]) {
		[self.session addOutput:photoOutput];
		self.photoOutput = photoOutput;
		self.photoOutput.highResolutionCaptureEnabled = YES;
		
		self.inProgressPhotoCaptureDelegates = [NSMutableDictionary dictionary];
	}
	else {
		NSLog(@"Could not add photo output to the session");
		self.setupResult = AVCamManualSetupResultSessionConfigurationFailed;
		[self.session commitConfiguration];
		return;
	}
	
	// 配置会话后时，不创建 AVCaptureMovieFileOutput，因为 AVCaptureMovieFileOutput 不支持使用 AVCaptureSessionPresetPhoto 配置录制视频
	self.backgroundRecordingID = UIBackgroundTaskInvalid;
	
    // 结束配置
	[self.session commitConfiguration];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[self configureManualHUD];
	});
}

// 应在主线程上调用
/// 从 UI 上获取用户的配置
- (AVCapturePhotoSettings *)currentPhotoSettings
{
    // 相机稳定
	BOOL lensStabilizationEnabled = self.lensStabilizationControl.selectedSegmentIndex == 1;
    // raw
	BOOL rawEnabled = self.rawControl.selectedSegmentIndex == 1;
	AVCapturePhotoSettings *photoSettings = nil;
	
	if (lensStabilizationEnabled && self.photoOutput.isLensStabilizationDuringBracketedCaptureSupported) { // 支持相机稳定
		NSArray *bracketedSettings = nil;
		if (self.videoDevice.exposureMode == AVCaptureExposureModeCustom) { // 手动曝光
			bracketedSettings = @[[AVCaptureManualExposureBracketedStillImageSettings manualExposureSettingsWithExposureDuration:AVCaptureExposureDurationCurrent ISO:AVCaptureISOCurrent]];
		}
		else { // 自动曝光
			bracketedSettings = @[[AVCaptureAutoExposureBracketedStillImageSettings autoExposureSettingsWithExposureTargetBias:AVCaptureExposureTargetBiasCurrent]];
		}
		
		if (rawEnabled && self.photoOutput.availableRawPhotoPixelFormatTypes.count) { // raw
            photoSettings = [AVCapturePhotoBracketSettings photoBracketSettingsWithRawPixelFormatType:(OSType)(((NSNumber *)self.photoOutput.availableRawPhotoPixelFormatTypes[0]).unsignedLongValue) processedFormat:nil bracketedSettings:bracketedSettings];
		}
		else { // JPEG
            photoSettings = [AVCapturePhotoBracketSettings photoBracketSettingsWithRawPixelFormatType:0 processedFormat:@{ AVVideoCodecKey : AVVideoCodecJPEG } bracketedSettings:bracketedSettings];
		}
		
		((AVCapturePhotoBracketSettings *)photoSettings).lensStabilizationEnabled = YES;
	}
	else { // 不开启相机稳定
		if (rawEnabled && self.photoOutput.availableRawPhotoPixelFormatTypes.count > 0) { // JPEG
			photoSettings = [AVCapturePhotoSettings photoSettingsWithRawPixelFormatType:(OSType)(((NSNumber *)self.photoOutput.availableRawPhotoPixelFormatTypes[0]).unsignedLongValue) processedFormat:@{ AVVideoCodecKey : AVVideoCodecJPEG }];
		}
		else { // 使用默认配置
			photoSettings = [AVCapturePhotoSettings photoSettings];
		}
		
		// 在手动曝光是不适用闪光灯
		if (self.videoDevice.exposureMode == AVCaptureExposureModeCustom) {
			photoSettings.flashMode = AVCaptureFlashModeOff;
		}
		else {
			photoSettings.flashMode = [self.photoOutput.supportedFlashModes containsObject:@(AVCaptureFlashModeAuto)] ? AVCaptureFlashModeAuto : AVCaptureFlashModeOff;
		}
	}
	
	if (photoSettings.availablePreviewPhotoPixelFormatTypes.count > 0) {
		photoSettings.previewPhotoFormat = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : photoSettings.availablePreviewPhotoPixelFormatTypes[0] }; // 数组中的是第一种格式是首选格式
	}
	
    // 手动曝光时关闭相机稳定
	if (self.videoDevice.exposureMode == AVCaptureExposureModeCustom) {
		photoSettings.autoStillImageStabilizationEnabled = NO;
	}
	
	photoSettings.highResolutionPhotoEnabled = YES;

	return photoSettings;
}

/// 恢复按钮事件
- (IBAction)resumeInterruptedSession:(id)sender
{
	dispatch_async(self.sessionQueue, ^{
		// 会话可能无法运行，例如如果电话或 FaceTime 护肩仍在使用音频或视频。这将会通过会话运行时错误通知传达无法启动会话。
        // 为了避免重复无法启动会话运行，如果我们不尝试恢复会话进行，我们只尝试在会话运行时错误处理程序中重启会话。
		[self.session startRunning];
		self.sessionRunning = self.session.isRunning;
		if (!self.session.isRunning) {
			dispatch_async(dispatch_get_main_queue(), ^{
				NSString *message = NSLocalizedString(@"Unable to resume", @"Alert message when unable to resume the session running");
				UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCamManual" message:message preferredStyle:UIAlertControllerStyleAlert];
				UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Alert OK button") style:UIAlertActionStyleCancel handler:nil];
				[alertController addAction:cancelAction];
				[self presentViewController:alertController animated:YES completion:nil];
			});
		}
		else {
			dispatch_async(dispatch_get_main_queue(), ^{
				self.resumeButton.hidden = YES;
			});
		}
	});
}

/// 捕捉模式变更事件
- (IBAction)changeCaptureMode:(UISegmentedControl *)captureModeControl
{
	if (captureModeControl.selectedSegmentIndex == AVCamManualCaptureModePhoto) {
		self.recordButton.enabled = NO;
		
		dispatch_async(self.sessionQueue, ^{
			// 从会话中删除 AVCaptureMovieFileOutput，因为 AVCaptureSessionPresetPhoto 不支持视频录制。此外，AVCaptureMovieFileOutput 连接到会话时不支持 live photo 捕捉。
			[self.session beginConfiguration];
			[self.session removeOutput:self.movieFileOutput];
			self.session.sessionPreset = AVCaptureSessionPresetPhoto;
			[self.session commitConfiguration];
			
			self.movieFileOutput = nil;
		});
	}
	else if (captureModeControl.selectedSegmentIndex == AVCamManualCaptureModeMovie) {
		
		dispatch_async(self.sessionQueue, ^{
			AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
			
			if ([self.session canAddOutput:movieFileOutput]) {
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

/// 切换相机事件
- (IBAction)chooseNewCamera:(id)sender
{
	// 罗列所有可用相机
	UIAlertController *cameraOptionsController = [UIAlertController alertControllerWithTitle:@"Choose a camera" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
	[cameraOptionsController addAction:cancelAction];
	for (AVCaptureDevice *device in self.videoDeviceDiscoverySession.devices) {
		UIAlertAction *newDeviceOption = [UIAlertAction actionWithTitle:device.localizedName style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
			[self changeCameraWithDevice:device];
		}];
		[cameraOptionsController addAction:newDeviceOption];
	}
	
	[self presentViewController:cameraOptionsController animated:YES completion:nil];
}

- (void)changeCameraWithDevice:(AVCaptureDevice *)newVideoDevice
{
	// 检查设备是否更改
	if (newVideoDevice == self.videoDevice) {
		return;
	}
	
	self.manualHUD.userInteractionEnabled = NO;
	self.cameraButton.enabled = NO;
	self.recordButton.enabled = NO;
	self.photoButton.enabled = NO;
	self.captureModeControl.enabled = NO;
	self.HUDButton.enabled = NO;
	
	dispatch_async(self.sessionQueue, ^{
		AVCaptureDeviceInput *newVideoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:newVideoDevice error:nil];
		
		[self.session beginConfiguration];
		
		// 首先删除现有的设备输入，因为不支持同时使用前后摄像头
		[self.session removeInput:self.videoDeviceInput];
		if ([self.session canAddInput:newVideoDeviceInput]) {
			[[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDevice];
			
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:newVideoDevice];
			
			[self.session addInput:newVideoDeviceInput];
			self.videoDeviceInput = newVideoDeviceInput;
			self.videoDevice = newVideoDevice;
		}
		else {
			[self.session addInput:self.videoDeviceInput];
		}
		
		AVCaptureConnection *connection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
		if (connection.isVideoStabilizationSupported) {
			connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
		}
		
		[self.session commitConfiguration];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			[self configureManualHUD];
			
			self.cameraButton.enabled = YES;
			self.recordButton.enabled = self.captureModeControl.selectedSegmentIndex == AVCamManualCaptureModeMovie;
			self.photoButton.enabled = YES;
			self.captureModeControl.enabled = YES;
			self.HUDButton.enabled = YES;
			self.manualHUD.userInteractionEnabled = YES;
		});
	});
}

/// 对焦模式变更事件
- (IBAction)changeFocusMode:(id)sender
{
	UISegmentedControl *control = sender;
	AVCaptureFocusMode mode = (AVCaptureFocusMode)[self.focusModes[control.selectedSegmentIndex] intValue];

	NSError *error = nil;
	
	if ([self.videoDevice lockForConfiguration:&error]) {
		if ([self.videoDevice isFocusModeSupported:mode]) {
			self.videoDevice.focusMode = mode;
		}
		else {
			NSLog(@"Focus mode %@ is not supported. Focus mode is %@.", [self stringFromFocusMode:mode], [self stringFromFocusMode:self.videoDevice.focusMode]);
			self.focusModeControl.selectedSegmentIndex = [self.focusModes indexOfObject:@(self.videoDevice.focusMode)];
		}
		[self.videoDevice unlockForConfiguration];
	}
	else {
		NSLog(@"Could not lock device for configuration: %@", error);
	}
}

/// 焦距变更事件
- (IBAction)changeLensPosition:(id)sender
{
	UISlider *control = sender;
	NSError *error = nil;
	
	if ([self.videoDevice lockForConfiguration:&error]) {
		[self.videoDevice setFocusModeLockedWithLensPosition:control.value completionHandler:nil];
		[self.videoDevice unlockForConfiguration];
	}
	else {
		NSLog(@"Could not lock device for configuration: %@", error);
	}
}

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
	dispatch_async(self.sessionQueue, ^{
		AVCaptureDevice *device = self.videoDevice;
		
		NSError *error = nil;
		if ([device lockForConfiguration:&error]) {
			// 设置兴趣点（对焦/曝光）不会单独（对焦/曝光）操作
			if (focusMode != AVCaptureFocusModeLocked && device.isFocusPointOfInterestSupported && [device isFocusModeSupported:focusMode]) {
				device.focusPointOfInterest = point;
				device.focusMode = focusMode;
			}
			
			if (exposureMode != AVCaptureExposureModeCustom && device.isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode]) {
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

/// 点击调整对焦和曝光
- (IBAction)focusAndExposeTap:(UIGestureRecognizer *)gestureRecognizer
{
	CGPoint devicePoint = [(AVCaptureVideoPreviewLayer *)self.previewView.layer captureDevicePointOfInterestForPoint:[gestureRecognizer locationInView:[gestureRecognizer view]]];
	[self focusWithMode:self.videoDevice.focusMode exposeWithMode:self.videoDevice.exposureMode atDevicePoint:devicePoint monitorSubjectAreaChange:YES];
}

/// 曝光模式变更事件
- (IBAction)changeExposureMode:(id)sender
{
	UISegmentedControl *control = sender;
	AVCaptureExposureMode mode = (AVCaptureExposureMode)[self.exposureModes[control.selectedSegmentIndex] intValue];
	NSError *error = nil;
	
	if ([self.videoDevice lockForConfiguration:&error]) {
		if ([self.videoDevice isExposureModeSupported:mode]) {
			self.videoDevice.exposureMode = mode;
		}
		else {
			NSLog(@"Exposure mode %@ is not supported. Exposure mode is %@.", [self stringFromExposureMode:mode], [self stringFromExposureMode:self.videoDevice.exposureMode]);
			self.exposureModeControl.selectedSegmentIndex = [self.exposureModes indexOfObject:@(self.videoDevice.exposureMode)];
		}
		[self.videoDevice unlockForConfiguration];
	}
	else {
		NSLog(@"Could not lock device for configuration: %@", error);
	}
}

/// 曝光时长/快门时长变更事件
- (IBAction)changeExposureDuration:(id)sender
{
	UISlider *control = sender;
	NSError *error = nil;
	
    // p^5
	double p = pow(control.value, kExposureDurationPower); // Apply power function to expand slider's low-end range
	double minDurationSeconds = MAX(CMTimeGetSeconds(self.videoDevice.activeFormat.minExposureDuration), kExposureMinimumDuration);
	double maxDurationSeconds = CMTimeGetSeconds(self.videoDevice.activeFormat.maxExposureDuration);
	double newDurationSeconds = p * (maxDurationSeconds - minDurationSeconds) + minDurationSeconds; // Scale from 0-1 slider range to actual duration
	
	if ([self.videoDevice lockForConfiguration:&error]) {
		[self.videoDevice setExposureModeCustomWithDuration:CMTimeMakeWithSeconds(newDurationSeconds, 1000*1000*1000)  ISO:AVCaptureISOCurrent completionHandler:nil];
		[self.videoDevice unlockForConfiguration];
	}
	else {
		NSLog(@"Could not lock device for configuration: %@", error);
	}
}

/// ISO 变更事件
- (IBAction)changeISO:(id)sender
{
	UISlider *control = sender;
	NSError *error = nil;
	
	if ([self.videoDevice lockForConfiguration:&error]) {
		[self.videoDevice setExposureModeCustomWithDuration:AVCaptureExposureDurationCurrent ISO:control.value completionHandler:nil];
		[self.videoDevice unlockForConfiguration];
	}
	else {
		NSLog(@"Could not lock device for configuration: %@", error);
	}
}

/// 曝光偏移变更事件
- (IBAction)changeExposureTargetBias:(id)sender
{
	UISlider *control = sender;
	NSError *error = nil;
	
	if ([self.videoDevice lockForConfiguration:&error]) {
		[self.videoDevice setExposureTargetBias:control.value completionHandler:nil];
		[self.videoDevice unlockForConfiguration];
	}
	else {
		NSLog(@"Could not lock device for configuration: %@", error);
	}
}

/// 白平衡模式变更事件
- (IBAction)changeWhiteBalanceMode:(id)sender
{
	UISegmentedControl *control = sender;
	AVCaptureWhiteBalanceMode mode = (AVCaptureWhiteBalanceMode)[self.whiteBalanceModes[control.selectedSegmentIndex] intValue];
	NSError *error = nil;
	
	if ([self.videoDevice lockForConfiguration:&error]) {
		if ([self.videoDevice isWhiteBalanceModeSupported:mode]) {
			self.videoDevice.whiteBalanceMode = mode;
		}
		else {
			NSLog(@"White balance mode %@ is not supported. White balance mode is %@.", [self stringFromWhiteBalanceMode:mode], [self stringFromWhiteBalanceMode:self.videoDevice.whiteBalanceMode]);
			self.whiteBalanceModeControl.selectedSegmentIndex = [self.whiteBalanceModes indexOfObject:@(self.videoDevice.whiteBalanceMode)];
		}
		[self.videoDevice unlockForConfiguration];
	}
	else {
		NSLog(@"Could not lock device for configuration: %@", error);
	}
}

- (void)setWhiteBalanceGains:(AVCaptureWhiteBalanceGains)gains
{
	NSError *error = nil;
	
	if ([self.videoDevice lockForConfiguration:&error]) {
		AVCaptureWhiteBalanceGains normalizedGains = [self normalizedGains:gains]; // Conversion can yield out-of-bound values, cap to limits
		[self.videoDevice setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:normalizedGains completionHandler:nil];
		[self.videoDevice unlockForConfiguration];
	}
	else {
		NSLog(@"Could not lock device for configuration: %@", error);
	}
}

/// 色温变更事件
- (IBAction)changeTemperature:(id)sender
{
	AVCaptureWhiteBalanceTemperatureAndTintValues temperatureAndTint = {
		.temperature = self.temperatureSlider.value,
		.tint = self.tintSlider.value,
	};
	
	[self setWhiteBalanceGains:[self.videoDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:temperatureAndTint]];
}

/// 色调变更事件
- (IBAction)changeTint:(id)sender
{
	AVCaptureWhiteBalanceTemperatureAndTintValues temperatureAndTint = {
		.temperature = self.temperatureSlider.value,
		.tint = self.tintSlider.value,
	};
	
	[self setWhiteBalanceGains:[self.videoDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:temperatureAndTint]];
}

/// 灰度按钮事件
- (IBAction)lockWithGrayWorld:(id)sender
{
    // 以当前场景中的灰度校准白平衡
	[self setWhiteBalanceGains:self.videoDevice.grayWorldDeviceWhiteBalanceGains];
}

/// 防止白平衡结构体越界
- (AVCaptureWhiteBalanceGains)normalizedGains:(AVCaptureWhiteBalanceGains)gains
{
	AVCaptureWhiteBalanceGains g = gains;
	
	g.redGain = MAX(1.0, g.redGain);
	g.greenGain = MAX(1.0, g.greenGain);
	g.blueGain = MAX(1.0, g.blueGain);
	
	g.redGain = MIN(self.videoDevice.maxWhiteBalanceGain, g.redGain);
	g.greenGain = MIN(self.videoDevice.maxWhiteBalanceGain, g.greenGain);
	g.blueGain = MIN(self.videoDevice.maxWhiteBalanceGain, g.blueGain);
	
	return g;
}

#pragma mark Capturing Photos

/// 拍照
- (IBAction)capturePhoto:(id)sender
{
	// 在进入会话队列之前，在主队列检索视频预览图层的视频方向
	// 这样做是为了确保在主线程上访问 UI 元素，并在会话队列上完成会话配置
	AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.previewView.layer;
	AVCaptureVideoOrientation videoPreviewLayerVideoOrientation = previewLayer.connection.videoOrientation;
	
	AVCapturePhotoSettings *settings = [self currentPhotoSettings];
	dispatch_async(self.sessionQueue, ^{
		// 在捕捉之前更新方向
		AVCaptureConnection *photoOutputConnection = [self.photoOutput connectionWithMediaType:AVMediaTypeVideo];
		photoOutputConnection.videoOrientation = videoPreviewLayerVideoOrientation;
		
		// 为照片捕捉使用单独的对象来隔离每个捕捉的生命周期
		AVCamManualPhotoCaptureDelegate *photoCaptureDelegate = [[AVCamManualPhotoCaptureDelegate alloc] initWithRequestedPhotoSettings:settings willCapturePhotoAnimation:^{
			// 指定快门动画
			dispatch_async(dispatch_get_main_queue(), ^{
				self.previewView.layer.opacity = 0.0;
				[UIView animateWithDuration:0.25 animations:^{
					self.previewView.layer.opacity = 1.0;
				}];
			});
		} completed:^(AVCamManualPhotoCaptureDelegate *photoCaptureDelegate) {
			// 捕捉完成后，删除照片捕捉委托对象的引用，以便释放
			dispatch_async(self.sessionQueue, ^{
				self.inProgressPhotoCaptureDelegates[@(photoCaptureDelegate.requestedPhotoSettings.uniqueID)] = nil;
			});
		}];
		
		// 图片输出保留对照片捕捉委托对象的若引用，因此我们将其存储在数组中以保持对此对象的强引用，直到捕捉完成。
		self.inProgressPhotoCaptureDelegates[@(photoCaptureDelegate.requestedPhotoSettings.uniqueID)] = photoCaptureDelegate;
		[self.photoOutput capturePhotoWithSettings:settings delegate:photoCaptureDelegate];
	});
}

#pragma mark Recording Movies

/// 录制按钮事件
- (IBAction)toggleMovieRecording:(id)sender
{
	// 禁用相机按钮直到录制完成，并禁用录制按钮直到录制开始或结束。
	self.cameraButton.enabled = NO;
	self.recordButton.enabled = NO;
	self.captureModeControl.enabled = NO;
	
    // 在进入会话队列之前，在主队列检索视频预览图层的视频方向
    // 这样做是为了确保在主线程上访问 UI 元素，并在会话队列上完成会话配置
	AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.previewView.layer;
	AVCaptureVideoOrientation previewLayerVideoOrientation = previewLayer.connection.videoOrientation;
	dispatch_async(self.sessionQueue, ^{
		if (!self.movieFileOutput.isRecording) {
			if ([UIDevice currentDevice].isMultitaskingSupported) {
				// 设置后台任务。这是必需的，因为除非你请求后台执行时间，否则直到应用返回到前台才会收到 -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:] 的回调。这也确保了当应用在后台时，有足够的时间写入照片库。而结束这个后台指定，在保存录制文件后，在 -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:] 调用  -endBackgroundTask。
				self.backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
			}
			AVCaptureConnection *movieConnection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
			movieConnection.videoOrientation = previewLayerVideoOrientation;
			
			// 开始录制到临时文件
			NSString *outputFileName = [NSProcessInfo processInfo].globallyUniqueString;
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
	// 启用录制按钮以便用户停止录制
	dispatch_async(dispatch_get_main_queue(), ^{
		self.recordButton.enabled = YES;
		[self.recordButton setTitle:NSLocalizedString(@"Stop", @"Recording button stop title") forState:UIControlStateNormal];
	});
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
	// 注意，currentBackgroundRecordingID 用于结束与此录制相关的后台任务。这样，一旦影片文件输出的 isRecording 属性返回 NO，就可以启动与新的 UIBackgroundTaskIdentifier 关联新的录制。这个操作在该方法返回后的某个时间发生。
    // 注意：由于我们为每个录制使用唯一 的文件路径，因此新录制不会覆盖当前正在保存的录制内容。
	UIBackgroundTaskIdentifier currentBackgroundRecordingID = self.backgroundRecordingID;
	self.backgroundRecordingID = UIBackgroundTaskInvalid;

	dispatch_block_t cleanup = ^{
		if ([[NSFileManager defaultManager] fileExistsAtPath:outputFileURL.path]) {
			[[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
		}
		
		if (currentBackgroundRecordingID != UIBackgroundTaskInvalid) {
			[[UIApplication sharedApplication] endBackgroundTask:currentBackgroundRecordingID];
		}
	};

	BOOL success = YES;

	if (error) {
		NSLog(@"Error occurred while capturing movie: %@", error);
		success = [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue];
	}
	if (success) {
		// 检查相册授权状态
		[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
			if (status == PHAuthorizationStatusAuthorized) {
				// 把视频保存到相册并进行清理
				[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
					// 在 iOS 9 及其更高版本，可以将文件移入相册中。而不是复制文件数据。
                    // 这样可以避免在保存期间使用双倍的磁盘空间，这可能会对可用磁盘空间有限的设备产生影响。
					PHAssetResourceCreationOptions *options = [[PHAssetResourceCreationOptions alloc] init];
					options.shouldMoveFile = YES;
					PHAssetCreationRequest *changeRequest = [PHAssetCreationRequest creationRequestForAsset];
					[changeRequest addResourceWithType:PHAssetResourceTypeVideo fileURL:outputFileURL options:options];
				} completionHandler:^(BOOL success, NSError *error) {
					if (!success) {
						NSLog(@"Could not save movie to photo library: %@", error);
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

	// 启用相机和录制按钮，让用户可以切换相机并开始新录制
	dispatch_async(dispatch_get_main_queue(), ^{
		// 设备有多个摄像头才启用切换相机功能
		self.cameraButton.enabled = (self.videoDeviceDiscoverySession.devices.count > 1);
		self.recordButton.enabled = self.captureModeControl.selectedSegmentIndex == AVCamManualCaptureModeMovie;
		[self.recordButton setTitle:NSLocalizedString(@"Record", @"Recording button record title") forState:UIControlStateNormal];
		self.captureModeControl.enabled = YES;
	});
}

#pragma mark KVO and Notifications

- (void)addObservers
{
	[self addObserver:self forKeyPath:@"session.running" options:NSKeyValueObservingOptionNew context:SessionRunningContext];
	[self addObserver:self forKeyPath:@"videoDevice.focusMode" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:FocusModeContext];
	[self addObserver:self forKeyPath:@"videoDevice.lensPosition" options:NSKeyValueObservingOptionNew context:LensPositionContext];
	[self addObserver:self forKeyPath:@"videoDevice.exposureMode" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:ExposureModeContext];
	[self addObserver:self forKeyPath:@"videoDevice.exposureDuration" options:NSKeyValueObservingOptionNew context:ExposureDurationContext];
	[self addObserver:self forKeyPath:@"videoDevice.ISO" options:NSKeyValueObservingOptionNew context:ISOContext];
	[self addObserver:self forKeyPath:@"videoDevice.exposureTargetBias" options:NSKeyValueObservingOptionNew context:ExposureTargetBiasContext];
	[self addObserver:self forKeyPath:@"videoDevice.exposureTargetOffset" options:NSKeyValueObservingOptionNew context:ExposureTargetOffsetContext];
	[self addObserver:self forKeyPath:@"videoDevice.whiteBalanceMode" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:WhiteBalanceModeContext];
	[self addObserver:self forKeyPath:@"videoDevice.deviceWhiteBalanceGains" options:NSKeyValueObservingOptionNew context:DeviceWhiteBalanceGainsContext];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDevice];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];
	// 会话只能在应用程序全屏时运行。它将在 iOS 9 引入的多应用程序布局中被中断，另参阅 AVCaptureSessionInterruptionReason 文档。添加监听来处理会话中断并显示预览暂停消息。有关其他中断原因，请参阅 AVCaptureSessionWasInterruptedNotification 文档。
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.session];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:self.session];
    
    // for test
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interfaceWillChangeOrientation:) name:UIApplicationWillChangeStatusBarOrientationNotification object:nil];
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interfaceDidChangeOrientation:) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
}

//- (void)interfaceWillChangeOrientation:(NSNotification *)notification {
//    NSLog(@"%s, info: %@, %@", __FUNCTION__, notification.userInfo, @([UIApplication sharedApplication].statusBarOrientation));
//    UIInterfaceOrientation willOrientaion = [notification.userInfo[UIApplicationStatusBarOrientationUserInfoKey] integerValue];
//    AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.previewView.layer;
//    previewLayer.connection.videoOrientation = (AVCaptureVideoOrientation)willOrientaion;
//}
//- (void)interfaceDidChangeOrientation:(NSNotification *)notification {
//    NSLog(@"%s, info: %@, %@", __FUNCTION__, notification.userInfo, @([UIApplication sharedApplication].statusBarOrientation));
//}

- (void)removeObservers
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[self removeObserver:self forKeyPath:@"session.running" context:SessionRunningContext];
	[self removeObserver:self forKeyPath:@"videoDevice.focusMode" context:FocusModeContext];
	[self removeObserver:self forKeyPath:@"videoDevice.lensPosition" context:LensPositionContext];
	[self removeObserver:self forKeyPath:@"videoDevice.exposureMode" context:ExposureModeContext];
	[self removeObserver:self forKeyPath:@"videoDevice.exposureDuration" context:ExposureDurationContext];
	[self removeObserver:self forKeyPath:@"videoDevice.ISO" context:ISOContext];
	[self removeObserver:self forKeyPath:@"videoDevice.exposureTargetBias" context:ExposureTargetBiasContext];
	[self removeObserver:self forKeyPath:@"videoDevice.exposureTargetOffset" context:ExposureTargetOffsetContext];
	[self removeObserver:self forKeyPath:@"videoDevice.whiteBalanceMode" context:WhiteBalanceModeContext];
	[self removeObserver:self forKeyPath:@"videoDevice.deviceWhiteBalanceGains" context:DeviceWhiteBalanceGainsContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	id oldValue = change[NSKeyValueChangeOldKey];
	id newValue = change[NSKeyValueChangeNewKey];
	
	if (context == FocusModeContext) { // videoDevice.focusMode，对焦模式变更
		if (newValue && newValue != [NSNull null]) {
			AVCaptureFocusMode newMode = [newValue intValue];
			dispatch_async(dispatch_get_main_queue(), ^{
				self.focusModeControl.selectedSegmentIndex = [self.focusModes indexOfObject:@(newMode)];
				self.lensPositionSlider.enabled = (newMode == AVCaptureFocusModeLocked);
				
				if (oldValue && oldValue != [NSNull null]) {
					AVCaptureFocusMode oldMode = [oldValue intValue];
					NSLog(@"focus mode: %@ -> %@", [self stringFromFocusMode:oldMode], [self stringFromFocusMode:newMode]);
				}
				else {
					NSLog(@"focus mode: %@", [self stringFromFocusMode:newMode]);
				}
			});
		}
	}
	else if (context == LensPositionContext) { // 焦距变更
		if (newValue && newValue != [NSNull null]) {
			AVCaptureFocusMode focusMode = self.videoDevice.focusMode;
			float newLensPosition = [newValue floatValue];
			dispatch_async(dispatch_get_main_queue(), ^{
				if (focusMode != AVCaptureFocusModeLocked) {
					self.lensPositionSlider.value = newLensPosition;
				}
				
				self.lensPositionValueLabel.text = [NSString stringWithFormat:@"%.1f", newLensPosition];
			});
		}
	}
	else if (context == ExposureModeContext) { // videoDevice.exposureMode，曝光模式变更
		if (newValue && newValue != [NSNull null]) {
			AVCaptureExposureMode newMode = [newValue intValue];
			if (oldValue && oldValue != [NSNull null]) {
				AVCaptureExposureMode oldMode = [oldValue intValue];
				// 了解 exposureDuration 和 activeVideoMaxFrameDuration 所代表的最小帧率之间的关系非常重要。
                // 在手动模式下，如果 exposureDuration 设置大于 activeVideoMaxFrameDuration，则 activeVideoMaxFrameDuration 将会增加以匹配它，从而降低最小帧率。如果将 exposureMode 改为自动模式，则最小帧率将保持其默认值。如果这不是所需的行为，可以通过将 activeVideoMaxFrameDuration 和 activeVideoMinFrameDuration 设置为 kCMTimeInvalid，将最小和最大帧率重置为 activeFormat 的默认值
				if (oldMode != newMode && oldMode == AVCaptureExposureModeCustom) {
					NSError *error = nil;
					if ([self.videoDevice lockForConfiguration:&error]) {
						self.videoDevice.activeVideoMaxFrameDuration = kCMTimeInvalid;
						self.videoDevice.activeVideoMinFrameDuration = kCMTimeInvalid;
						[self.videoDevice unlockForConfiguration];
					}
					else {
						NSLog(@"Could not lock device for configuration: %@", error);
					}
				}
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				self.exposureModeControl.selectedSegmentIndex = [self.exposureModes indexOfObject:@(newMode)];
				self.exposureDurationSlider.enabled = (newMode == AVCaptureExposureModeCustom);
				self.ISOSlider.enabled = (newMode == AVCaptureExposureModeCustom);
				
				if (oldValue && oldValue != [NSNull null]) {
					AVCaptureExposureMode oldMode = [oldValue intValue];
					NSLog(@"exposure mode: %@ -> %@", [self stringFromExposureMode:oldMode], [self stringFromExposureMode:newMode]);
				}
				else {
					NSLog(@"exposure mode: %@", [self stringFromExposureMode:newMode]);
				}
			});
		}
	}
	else if (context == ExposureDurationContext) { // videoDevice.exposureDuration，曝光时长变更
		if (newValue && newValue != [NSNull null]) {
			double newDurationSeconds = CMTimeGetSeconds([newValue CMTimeValue]);
			AVCaptureExposureMode exposureMode = self.videoDevice.exposureMode;
			
			double minDurationSeconds = MAX(CMTimeGetSeconds(self.videoDevice.activeFormat.minExposureDuration), kExposureMinimumDuration);
			double maxDurationSeconds = CMTimeGetSeconds(self.videoDevice.activeFormat.maxExposureDuration);
			// Map from duration to non-linear UI range 0-1
			double p = (newDurationSeconds - minDurationSeconds) / (maxDurationSeconds - minDurationSeconds); // Scale to 0-1
			dispatch_async(dispatch_get_main_queue(), ^{
				if (exposureMode != AVCaptureExposureModeCustom) {
					self.exposureDurationSlider.value = pow(p, 1 / kExposureDurationPower); // Apply inverse power
				}
				if (newDurationSeconds < 1) {
					int digits = MAX(0, 2 + floor(log10(newDurationSeconds)));
					self.exposureDurationValueLabel.text = [NSString stringWithFormat:@"1/%.*f", digits, 1/newDurationSeconds];
				}
				else {
					self.exposureDurationValueLabel.text = [NSString stringWithFormat:@"%.2f", newDurationSeconds];
				}
			});
		}
	}
	else if (context == ISOContext) { // videoDevice.ISO，ISO 变更
		if (newValue && newValue != [NSNull null]) {
			float newISO = [newValue floatValue];
			AVCaptureExposureMode exposureMode = self.videoDevice.exposureMode;
			
			dispatch_async(dispatch_get_main_queue(), ^{
				if (exposureMode != AVCaptureExposureModeCustom) {
					self.ISOSlider.value = newISO;
				}
				self.ISOValueLabel.text = [NSString stringWithFormat:@"%i", (int)newISO];
			});
		}
	}
	else if (context == ExposureTargetBiasContext) { // videoDevice.exposureTargetBias，曝光目标偏移变更
		if (newValue && newValue != [NSNull null]) {
			float newExposureTargetBias = [newValue floatValue];
			dispatch_async(dispatch_get_main_queue(), ^{
				self.exposureTargetBiasValueLabel.text = [NSString stringWithFormat:@"%.1f", newExposureTargetBias];
			});
		}
	}
	else if (context == ExposureTargetOffsetContext) { // videoDevice.exposureTargetOffset，曝光目标偏移变更
		if (newValue && newValue != [NSNull null]) {
			float newExposureTargetOffset = [newValue floatValue];
			dispatch_async(dispatch_get_main_queue(), ^{
				self.exposureTargetOffsetSlider.value = newExposureTargetOffset;
				self.exposureTargetOffsetValueLabel.text = [NSString stringWithFormat:@"%.1f", newExposureTargetOffset];
			});
		}
	}
	else if (context == WhiteBalanceModeContext) { // videoDevice.whiteBalanceMode，白平衡模式变更
		if (newValue && newValue != [NSNull null]) {
			AVCaptureWhiteBalanceMode newMode = [newValue intValue];
			dispatch_async(dispatch_get_main_queue(), ^{
				self.whiteBalanceModeControl.selectedSegmentIndex = [self.whiteBalanceModes indexOfObject:@(newMode)];
				self.temperatureSlider.enabled = (newMode == AVCaptureWhiteBalanceModeLocked);
				self.tintSlider.enabled = (newMode == AVCaptureWhiteBalanceModeLocked);
				
				if (oldValue && oldValue != [NSNull null]) {
					AVCaptureWhiteBalanceMode oldMode = [oldValue intValue];
					NSLog(@"white balance mode: %@ -> %@", [self stringFromWhiteBalanceMode:oldMode], [self stringFromWhiteBalanceMode:newMode]);
				}
			});
		}
	}
	else if (context == DeviceWhiteBalanceGainsContext) { // videoDevice.deviceWhiteBalanceGains，白平衡值变更
		if (newValue && newValue != [NSNull null]) {
			AVCaptureWhiteBalanceGains newGains;
			[newValue getValue:&newGains];
			AVCaptureWhiteBalanceTemperatureAndTintValues newTemperatureAndTint = [self.videoDevice temperatureAndTintValuesForDeviceWhiteBalanceGains:newGains];
			AVCaptureWhiteBalanceMode whiteBalanceMode = self.videoDevice.whiteBalanceMode;
			dispatch_async(dispatch_get_main_queue(), ^{
				if (whiteBalanceMode != AVCaptureExposureModeLocked) {
					self.temperatureSlider.value = newTemperatureAndTint.temperature;
					self.tintSlider.value = newTemperatureAndTint.tint;
				}
				
				self.temperatureValueLabel.text = [NSString stringWithFormat:@"%i", (int)newTemperatureAndTint.temperature];
				self.tintValueLabel.text = [NSString stringWithFormat:@"%i", (int)newTemperatureAndTint.tint];
			});
		}
	}
	else if (context == SessionRunningContext) { // session.running，捕捉会话运行状态变更
		BOOL isRunning = NO;
		if (newValue && newValue != [NSNull null]) {
			isRunning = [newValue boolValue];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			self.cameraButton.enabled = isRunning && (self.videoDeviceDiscoverySession.devices.count > 1);
			self.recordButton.enabled = isRunning && (self.captureModeControl.selectedSegmentIndex == AVCamManualCaptureModeMovie);
			self.photoButton.enabled = isRunning;
			self.HUDButton.enabled = isRunning;
			self.captureModeControl.enabled = isRunning;
		});
	}
	else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)subjectAreaDidChange:(NSNotification *)notification
{
	// 焦点恢复到屏幕中央
	CGPoint devicePoint = CGPointMake(0.5, 0.5);
	[self focusWithMode:self.videoDevice.focusMode exposeWithMode:self.videoDevice.exposureMode atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
	NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
	NSLog(@"Capture session runtime error: %@", error);
	
	if (error.code == AVErrorMediaServicesWereReset) {
		dispatch_async(self.sessionQueue, ^{
			// If we aren't trying to resume the session, try to restart it, since it must have been stopped due to an error (see -[resumeInterruptedSession:])
			if (self.isSessionRunning) {
				[self.session startRunning];
				self.sessionRunning = self.session.isRunning;
			} else {
				dispatch_async(dispatch_get_main_queue(), ^{
					self.resumeButton.hidden = NO;
				});
			}
		});
	} else {
		self.resumeButton.hidden = NO;
	}
}

- (void)sessionWasInterrupted:(NSNotification *)notification
{
	// 在某些情况下，我们希望用户能重新启动捕捉会话。例如在使用该应用时通过控制中心播放音乐，则用户可以让应用恢复会话运行，这将使播放的音乐停止。
    // 注意，在控制中心通知播放音乐并不会自动恢复会话。
    // 而且，并不总是可以恢复会话的，参见 -[resumeInterruptedSession:] 文档。在 iOS 9 及其更高版本，通知中的 userInfo 字典包含有关会话中断原因的信息。
	AVCaptureSessionInterruptionReason reason = [notification.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
	NSLog(@"Capture session was interrupted with reason %ld", (long)reason);
	
	if (reason == AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient ||
		reason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient) {
		// Simply fade-in a button to enable the user to try to resume the session running
		self.resumeButton.hidden = NO;
		self.resumeButton.alpha = 0.0;
		[UIView animateWithDuration:0.25 animations:^{
			self.resumeButton.alpha = 1.0;
		}];
	}
	else if (reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps) {
		// Simply fade-in a label to inform the user that the camera is unavailable
		self.cameraUnavailableLabel.hidden = NO;
		self.cameraUnavailableLabel.alpha = 0.0;
		[UIView animateWithDuration:0.25 animations:^{
			self.cameraUnavailableLabel.alpha = 1.0;
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

#pragma mark Utilities

- (NSString *)stringFromFocusMode:(AVCaptureFocusMode)focusMode
{
	NSString *string = @"INVALID FOCUS MODE";
	
	if (focusMode == AVCaptureFocusModeLocked) {
		string = @"Locked";
	}
	else if (focusMode == AVCaptureFocusModeAutoFocus) {
		string = @"Auto";
	}
	else if (focusMode == AVCaptureFocusModeContinuousAutoFocus) {
		string = @"ContinuousAuto";
	}
	
	return string;
}

- (NSString *)stringFromExposureMode:(AVCaptureExposureMode)exposureMode
{
	NSString *string = @"INVALID EXPOSURE MODE";
	
	if (exposureMode == AVCaptureExposureModeLocked) {
		string = @"Locked";
	}
	else if (exposureMode == AVCaptureExposureModeAutoExpose) {
		string = @"Auto";
	}
	else if (exposureMode == AVCaptureExposureModeContinuousAutoExposure) {
		string = @"ContinuousAuto";
	}
	else if (exposureMode == AVCaptureExposureModeCustom) {
		string = @"Custom";
	}
	
	return string;
}

- (NSString *)stringFromWhiteBalanceMode:(AVCaptureWhiteBalanceMode)whiteBalanceMode
{
	NSString *string = @"INVALID WHITE BALANCE MODE";
	
	if (whiteBalanceMode == AVCaptureWhiteBalanceModeLocked) {
		string = @"Locked";
	}
	else if (whiteBalanceMode == AVCaptureWhiteBalanceModeAutoWhiteBalance) {
		string = @"Auto";
	}
	else if (whiteBalanceMode == AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance) {
		string = @"ContinuousAuto";
	}
	
	return string;
}

@end

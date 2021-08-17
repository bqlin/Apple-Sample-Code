About AVRecorder
================

AVRecorder demonstrates usage of AV Foundation capture API for recording movies and using transport controls.

The main components are:

• AVRecorderDocument.[h,m] -- The core AVRecorder code
• AVCaptureDeviceFormat_AVRecorderAdditions.[h,m] -- Prints a pretty device format NSString
• AVFrameRateRange_AVRecorderAdditions.[h,m] -- Prints a pretty frame rate NSString

Using the Sample
----------------
Begin and complete video recording with the Record button. If the selected video device supports transport controls, use the Rewind, Play, Stop, and FF buttons to control the tape.

How It Works
------------

AVRecorder makes use of the following AV Foundation AVCapture classes to provide movie recording:

AVCaptureDevice
AVCaptureFileOutput
AVCaptureInput
AVCaptureMovieFileOutput
AVCaptureOutput
AVCaptureSession
AVCaptureVideoPreviewLayer

See the AV Foundation documentation for more information.


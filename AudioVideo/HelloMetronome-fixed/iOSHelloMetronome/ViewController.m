/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

*/

#import "ViewController.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UIButton *button;
@property (weak, nonatomic) IBOutlet UITextField *barTextField;
@property (weak, nonatomic) IBOutlet UITextField *beatTextField;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    NSLog(@"Hello, Metronome!\n");
    
    NSError *error = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    [audioSession setCategory:AVAudioSessionCategoryAmbient error:&error];
    if (error) {
        NSLog(@"AVAudioSession error %ld, %@", error.code, error.localizedDescription);
    }
    
    [audioSession setActive:YES error:&error];
    if (error) {
        NSLog(@"AVAudioSession error %ld, %@", error.code, error.localizedDescription);
    }
    
    // if media services are reset, we need to rebuild our audio chain
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMediaServicesWereReset:)
                                                 name:AVAudioSessionMediaServicesWereResetNotification
                                               object:audioSession];
    
    metronome = [[Metronome alloc] init];
    metronome.delegate = self;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark- Actions
- (IBAction)buttonPressed:(UIButton*)sender {
    // change the selected state thereby the button color and title
    // toggle between Start & Stop
    sender.selected = !sender.selected;
    
    if (metronome.isPlaying) {
        [metronome stop];
    } else {
        [metronome start];
    }
}

#pragma mark- Delegate
- (void)metronomeTicking:(Metronome * _Nonnull)metronome bar:(int32_t)bar beat:(int32_t)beat {
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.barTextField.text = [NSString stringWithFormat:@"%d", bar];
        self.beatTextField.text = [NSString stringWithFormat:@"%d", beat];
    });
}

#pragma mark- AVAudioSession Notifications
// see https://developer.apple.com/library/content/qa/qa1749/_index.html
- (void)handleMediaServicesWereReset:(NSNotification *)notification
{
    NSLog(@"Media services have reset...");
    
    // tear down
    metronome.delegate = nil;
    metronome = nil;
    
    self.button.selected = NO;
    
    // re-create
    metronome = [[Metronome alloc] init];
    metronome.delegate = self;
    
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (error) {
        NSLog(@"AVAudioSession error %ld, %@", error.code, error.localizedDescription);
    }
}

@end

/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    GameViewController
*/

#import "AudioEngine.h"

#import "GameView.h"
#import "GameViewController.h"

@interface GameViewController() <AudioEngineDelegate> {
    AudioEngine *_audioEngine;
}

@property (assign) GameView *gameView;

@end

@implementation GameViewController

static float randFloat(float min, float max){
    return min + ((max-min)*(rand()/(float)RAND_MAX));
}

- (void)physicsWorld:(SCNPhysicsWorld *)world didEndContact:(SCNPhysicsContact *)contact
{
    if (contact.collisionImpulse > 0.6 /* arbitrary threshold */) {
        AVAudio3DPoint contactPoint = AVAudioMake3DPoint(contact.contactPoint.x, contact.contactPoint.y, contact.contactPoint.z);
        [_audioEngine playCollisionSoundForSCNNode:contact.nodeB position:contactPoint impulse:contact.collisionImpulse];
    }
}

- (void)setupPhysicsScene:(SCNScene *)scene
{
    SCNNode *cube = [scene.rootNode childNodeWithName:@"Cube" recursively:YES];
    cube.castsShadow = NO;
    
    SCNNode *lightNode = [scene.rootNode childNodeWithName:@"MainLight" recursively:YES];
    lightNode.light.shadowMode = SCNShadowModeModulated;

    SCNVector3 min, max;
    [cube getBoundingBoxMin:&min max:&max];
    
    float cubeSize = (max.y-min.y) * cube.scale.y;
    float wallWidth = 1;
    SCNBox *wallGeometry = [SCNBox boxWithWidth:cubeSize height:cubeSize length:wallWidth chamferRadius:0];
    wallGeometry.firstMaterial.transparency = 0;
    
    float wallPosition = (cubeSize/2 + wallWidth/2);
    
    SCNNode *wall1 = [SCNNode node];
    wall1.name = @"Wall";
    wall1.geometry = wallGeometry;
    wall1.physicsBody = [SCNPhysicsBody staticBody];
    wall1.physicsBody.contactTestBitMask = SCNPhysicsCollisionCategoryDefault;
    wall1.position = SCNVector3Make(0, 0, -wallPosition);
    [scene.rootNode addChildNode:wall1];
    
    SCNNode *wall2 = [wall1 copy];
    wall2.position = SCNVector3Make(0, 0, wallPosition);
    wall2.eulerAngles = SCNVector3Make(M_PI, 0, 0);
    [scene.rootNode addChildNode:wall2];

    SCNNode *wall3 = [wall1 copy];
    wall3.position = SCNVector3Make(-wallPosition, 0, 0);
    wall3.eulerAngles = SCNVector3Make(0, M_PI_2, 0);
    [scene.rootNode addChildNode:wall3];

    SCNNode *wall4 = [wall1 copy];
    wall4.position = SCNVector3Make(wallPosition, 0, 0);
    wall4.eulerAngles = SCNVector3Make(0, -M_PI_2, 0);
    [scene.rootNode addChildNode:wall4];

    SCNNode *wall5 = [wall1 copy];
    wall5.position = SCNVector3Make(0, wallPosition, 0);
    wall5.eulerAngles = SCNVector3Make(M_PI_2, 0, 0);
    [scene.rootNode addChildNode:wall5];

    SCNNode *wall6 = [wall1 copy];
    wall6.position = SCNVector3Make(0, -wallPosition, 0);
    wall6.eulerAngles = SCNVector3Make(-M_PI_2, 0, 0);
    [scene.rootNode addChildNode:wall6];
    
    SCNNode *pointOfViewCamera = [scene.rootNode childNodeWithName:@"Camera" recursively:YES];
    self.gameView.pointOfView = pointOfViewCamera;
    
    SCNNode *listener = [scene.rootNode childNodeWithName:@"listenerLight" recursively:YES];
    listener.position = pointOfViewCamera.position;
    
    // setup physics callbacks
    scene.physicsWorld.contactDelegate = self;
    
    // turn off gravity for more fun
    //scene.physicsWorld.gravity = SCNVector3Zero;
}

- (void)createAndLaunchBall:(NSString*)ballID
{
    [SCNTransaction begin];
    
    SCNNode *ball = [SCNNode node];
    ball.name = ballID;
    ball.geometry = [SCNSphere sphereWithRadius:0.2];
    ball.geometry.firstMaterial.diffuse.contents = @"assets.scnassets/texture.jpg";
    ball.geometry.firstMaterial.reflective.contents = @"assets.scnassets/envmap.jpg";
    
    ball.position = SCNVector3Make(0, -2, 2.5);
    
    ball.physicsBody = [SCNPhysicsBody dynamicBody];
    ball.physicsBody.restitution = 1.2; //bounce!
    
    // create an AVAudioEngine player which will be tied to this ball
    [_audioEngine createPlayerForSCNNode:ball];
    
    [self.gameView.scene.rootNode addChildNode:ball];
    
    // bias the direction towards one of the side walls
    float whichWall = roundf(randFloat(0, 1));  // 0 is left and 1 is right
    float xVal = (1 - whichWall) * randFloat(-8, -3) + whichWall * randFloat(3, 8);
    
    // initial force
    [ball.physicsBody applyForce:SCNVector3Make(xVal, randFloat(0,5), -randFloat(5,15)) atPosition:SCNVector3Zero impulse:YES];
    [ball.physicsBody applyTorque:SCNVector4Make(randFloat(-1,1), randFloat(-1,1), randFloat(-1,1), randFloat(-1,1)) impulse:YES];
    
    [SCNTransaction commit];
}

- (void)removeBall:(SCNNode *)ball
{
    [_audioEngine destroyPlayerForSCNNode:ball];
    [ball removeFromParentNode];
}

-(void)viewDidLoad
{
    [super viewDidLoad];
    
    // create a new scene
    SCNScene *scene = [SCNScene sceneNamed:@"cube.scn" inDirectory:@"assets.scnassets" options:nil];
    
    // find the SCNView
    for (id view in self.view.subviews) {
        if ([[view class] isSubclassOfClass:[SCNView class]]) {
            self.gameView = view;
        }
    }
    
    // set the scene to the view
    self.gameView.scene = scene;
    
    // setup the room
    [self setupPhysicsScene:scene];
    
    // setup audio engine
    _audioEngine = [[AudioEngine alloc] init];
    
    //make the listener position the same as the camera point of view
    [_audioEngine updateListenerPosition:AVAudioMake3DPoint(0, -2, 2.5)];
    
    self.gameView.gameAudioEngine = _audioEngine;
    
    // create a queue that will handle adding SceneKit nodes (balls) and corresponding AVAudioEngine players
    dispatch_queue_t queue = dispatch_queue_create("DemBalls", DISPATCH_QUEUE_SERIAL);
    dispatch_async(queue, ^{
        while (1) {
            while (_audioEngine.isRunning) {
                static int ballIndex = 0;
                
                // play the launch sound
                [_audioEngine playLaunchSoundAtPosition:AVAudioMake3DPoint(0, -2, 2.5) completionHandler:^{
                    
                    // launch sound has finished scheduling
                    // now create and launch a ball
                    NSString *ballID = [[NSNumber numberWithInt:ballIndex] stringValue];
                    [self createAndLaunchBall:ballID];
                    ++ballIndex;
                }];
                
                // wait for some time before launching the next ball
                sleep(4);
            }
        }
    });
    
    // configure the view
#if TARGET_OS_IOS ||TARGET_OS_TV
    self.gameView.backgroundColor = [UIColor blackColor];
#else
    self.gameView.backgroundColor = [NSColor blackColor];
#endif
}


@end

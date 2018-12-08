
//
//  IntoTheBox.m
//  Thailes
//
//  Created by Keny Ruyter on 1/6/15.
//  Copyright (c) 2015 Art Of Communication, Inc. All rights reserved.
//
// Reference Tutorial:
// http://www.raywenderlich.com/61289/how-to-make-a-line-drawing-game-with-sprite-kit

#import "IntoTheBox.h"
#import "Tile.h"
#import "Box.h"
#import "SoundManager.h"
#import "Blood.h"
#import "CharacterLookup.h"
#import "UIButtons.h"
#import "TextureManager.h"
#import "NSMutableArray+Shuffle.h"
#import "MessageScreen.h"

typedef struct _NSZone NSZone;

@implementation IntoTheBox
{
    NSTimeInterval _lastUpdateTime;
    NSTimeInterval _dt;
    // NSTimeInterval _currentSpawnTime;
    BOOL messageWasDisplayed;
    BOOL lock;
    int lastCorrectChallenge;
    ScoreBoard *scoreBoard;
    BOOL allLivesLost;
    UIButtons *uiButtons;
    SKTextureAtlas *smallGfxAtlas;
    BOOL challengesAreFinished;
    NSArray *intensityArray;
    float spawnRangeMax;
    float spawnRangeMin;
    NSMutableDictionary *lockData;
    NSString *genderAlternator;
    int initialScore;
    int initialLives;
    BOOL accrueScore;
}

- (instancetype)initWithScoreBoard:(ScoreBoard*)board
{
    self = [super init];
    if (self) {
        
        scoreBoard = board;
        scoreBoard.name = @"scoreBoard";
        initialScore = [scoreBoard getPoints];
        initialLives = [scoreBoard getLives];
        
        spawnRangeMax = 5;
        spawnRangeMin = 2;
        
        appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
        self.userInteractionEnabled = YES;
        [self initializeNodeArrays];
        boxNodes = [NSMutableSet set];
        self.name = @"IntoTheBox";
        [self registerObservers];
        
        _gameType = @"combo";
        
        lockData = [NSMutableDictionary dictionary];
             
        lastCorrectChallenge = 0;
        
        // Set Gravity in the world
        NSNumber *chall = [NSNumber numberWithFloat:.0];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"setGravityY" object:chall];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"registerForUpdates" object:self];
        
        NSString *edge = @"off";
        [[NSNotificationCenter defaultCenter] postNotificationName:@"edgeLoop" object:edge];
        
        NSArray *update = [NSArray arrayWithObjects:@"off",nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"toggleTileLock" object:update];
        
        uiButtons = [[UIButtons alloc] init];
        uiButtons.name = @"uiButtons";
        [self addChild:uiButtons];
        
        [self loadAtlases];
    }
    return self;
}

// kept aside for restarting the game later
- (void) initializeNodeArrays {

    uiNodes = [NSMutableArray array];
    nodes = [NSMutableArray array];
    
    // shouldSpawn = YES;
    lock = NO;

}

// Called upon from the tile group when a item in thailes game comes up in that data
- (void) newGameWithTextures:(NSArray*)textures usingPlist:(NSString*)plist {
    
    currentSpawn = 0;
    
    if (!gameTextures){
        gameTextures = textures;
    }
    // _currentSpawnTime = 5.0;
    
    // what could happen here is before sucking the plist into an ivar, the plist could be parsed into a separate array where repeats could be parsed and then that file added into memory.
    
    challengeData = [self analyzeDataFromPlistDict:[self loadDataPlist:plist withLevel:1]];
    [self createIntensityArray];
    
    
    // Debug
    // currentSpawn = (int)[challengeData count] -2;
    
    if ([challengeData[0] objectForKey:@"accrueScores"]){
        accrueScore = YES;
    }
    
    if ([challengeData[0] objectForKey:@"sectionDescription"]){
        [self presentIntro];
    }
    else {
        [self beginGame];
    }
}

#pragma mark Introduction
// First we display an intro scene that tells the user where he is / what to do.
- (void) presentIntro {
    MessageScreen *msgScreen = [[MessageScreen alloc]init];
    msgScreen.name = @"intro";
    [msgScreen presentIntroWithUnitDescription:[challengeData[0] objectForKey:@"unitDescription"] sectionDescription:[challengeData[0] objectForKey:@"sectionDescription"]];
    [self addChild:msgScreen];
}

- (void) introWasDismissed {
    
    [(MessageScreen*)[self childNodeWithName:@"intro"] introWasDismissed];
    
    // Run this code after message screen fades
    NSMutableArray *delayAction = [NSMutableArray array];
    SKAction *durationAction = [SKAction waitForDuration:.5];
    [delayAction addObject:durationAction];
    SKAction *action1 = [SKAction runBlock:^{
        
        [(MessageScreen*)[self childNodeWithName:@"intro"] seppuku];
        [self beginGame];

    }];
    [delayAction addObject:action1];
    SKAction* sequenceAction = [SKAction sequence:delayAction];
    [self runAction:sequenceAction];
}


- (void) beginGame {
    // begin
    [self drawBoxes]; // replace with call for atlases
    
    // scoreBoard = [[ScoreBoard alloc] init];
    // scoreBoard.name = @"scoreBoard";
    // [self addChild:scoreBoard];
    [scoreBoard showBasic];
    
    [self spawnTile];
}
#pragma mark Gameplay UI / Spawn

// the only static UI Elements during the game here. Could be deferred upon Texture Atlas completion later
- (void) drawBoxes {
    Box *box1 = [[Box alloc] initWithBoxOfClass:@"High Class" position:1];
    box1.name = @"High Class";
    [self addChild:box1];
    [boxNodes addObject:box1];
    
    Box *box2 = [[Box alloc] initWithBoxOfClass:@"Middle Class" position:2];
    box2.name = @"Middle Class";
    [self addChild:box2];
    [boxNodes addObject:box2];
    
    Box *box3 = [[Box alloc] initWithBoxOfClass:@"Low Class" position:3];
    box3.name = @"Low Class";
    [self addChild:box3];
    [boxNodes addObject:box3];
}

- (void)spawnTile {
    
    // so here we check the current entry to see if there is a message to be displayed first before presenting it. Within, we set a BOOL that indicates whether the message was displayed or not.
    if ([challengeData[currentSpawn] objectForKey:@"message"] && !messageWasDisplayed){
        
        [self waitForChallengesToFinish];
        
        messageWasDisplayed = YES;
    }
    else {

        messageWasDisplayed = NO;
        
        // if messageWasDisplayed the second call will hit the following code, using the unchanged currentSpawn
        
        if (currentSpawn < [challengeData count] && ![self checkForEndOfGame]){
            
            // no more than 10 nodes on board
            if ([nodes count] < 10){
                
//                _currentSpawnTime -= 0.2;
//                if(_currentSpawnTime < 2) {
//                    _currentSpawnTime = 2.0;
//                }
                
                CharacterLookup *lookup = [[CharacterLookup alloc]init];
                lookup.assertChallengeClass = @3;
                
                // convert thai to integer equivalent for tile creation
                int tileTitle = [[lookup getNSNumberEquivalentForThaiCharacter:[challengeData[currentSpawn] objectForKey:@"thai"]] intValue];
                
                int randTileName = (arc4random() % 100000);
                
                NSString *consonantClass = [lookup determineConsonantClass:[challengeData[currentSpawn] objectForKey:@"thai"]];
                
                // placeholder for the time being, chicken or the egg...
                CGPoint placement = CGPointMake(100, 100);
                
                Tile *tile = [[Tile alloc] initForGame:tileTitle position:placement tileNumber:randTileName class:consonantClass];
                tile.name = [NSString stringWithFormat:@"%i", randTileName];
                tile.zPosition = 1;
                
                [self addChild:tile];
                [nodes addObject:tile];
                
                // initialize physics on the tile
                [tile activateStationary];
                
                // populate waypoints to set it moving via update
                [tile moveRandom];
                
                // why minus 2?
                // current spawn starts at zero
                // challenge data has one extra key.
                if (currentSpawn == [challengeData count] - 2){
                    tile.isLastSpawn = YES;
                }
                
                // need to offset placement of tile by 1/2 of tile
                SKSpriteNode *tileObject = (SKSpriteNode*)[tile childNodeWithName:[NSString stringWithFormat:@"%i", randTileName]];
                tileObject.xScale = .75;
                tileObject.yScale = .75;
                
                int offset = tileObject.texture.size.width/2;
                
                // these are supposed to spawn from the top...
                int maximum = (int)[[UIScreen mainScreen] bounds].size.width - offset; // screen width minus the right offset
                float tileX = (arc4random() % maximum) + offset; // add left offset to random number
                
                // Place object directly underneath the top edge border.
                // Maybe Design a better tile in animation, maybe a scalein with a pop sound
                tileObject.position = CGPointMake(tileX, [[UIScreen mainScreen] bounds].size.height - 3);
                
                [[SoundManager sharedManager] playSample:@"tiledrop.caf"];
                
                currentSpawn += 1;
            }
            
            
            // recursively call this method
            [self runAction:
             [SKAction sequence:@[[SKAction waitForDuration:[intensityArray[currentSpawn -1] floatValue]],
                                  [SKAction performSelector:@selector(spawnTile) onTarget:self]]] withKey:@"spawnAction"] ;
        }
        
    }
}

- (void)superSpawn {
    
    float delay = .05;
    
    [[SoundManager sharedManager] playSample:@"astiledrop.caf"];
    
    // Set Gravity in the world
    NSNumber *chall = [NSNumber numberWithFloat:-5];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"setGravityY" object:chall];
    
    //NSString *edge = @"on";
    //[[NSNotificationCenter defaultCenter] postNotificationName:@"edgeLoop" object:edge];
    
    // loop through the data creating a tile for each challenge
    for (int i = 0; i < [challengeData count] -1; i++) {
        
        
        NSMutableArray *delayAction = [NSMutableArray array];
        SKAction *durationAction = [SKAction waitForDuration:delay];
        [delayAction addObject:durationAction];
        SKAction *action1 = [SKAction runBlock:^{
            
            CharacterLookup *lookup = [[CharacterLookup alloc]init];
            lookup.assertChallengeClass = @3;
            
            // convert thai to integer equivalent for tile creation
            int tileTitle = [[lookup getNSNumberEquivalentForThaiCharacter:[challengeData[i]objectForKey:@"thai"]] intValue];
            
            CGPoint placement = CGPointMake(100, 100);
            
            Tile *tile = [[Tile alloc] initWithTile:tileTitle position:placement];
            
            [tile activateBouncy];
            
            [self addChild:tile];
            // [nodes addObject:tile];
            
            // need to offset placement of tile by 1/2 of tile
            SKSpriteNode *tileObject = (SKSpriteNode*)[tile childNodeWithName:[NSString stringWithFormat:@"%i", tileTitle]];
            tileObject.xScale = .75;
            tileObject.yScale = .75;
            
            int offset = tileObject.texture.size.width/2;
            
            // these are supposed to spawn from the top...
            int maximum = (int)[[UIScreen mainScreen] bounds].size.width - offset; // screen width minus the right offset
            float tileX = (arc4random() % maximum) + offset; // add left offset to random number
            
            // Place object directly underneath the top edge border.
            // Maybe Design a better tile in animation, maybe a scalein with a pop sound
            tileObject.position = CGPointMake(tileX, [[UIScreen mainScreen] bounds].size.height - 3);
            
            // [[SoundManager sharedManager] playMusic:@"gulp.caf" looping:NO fadeIn:NO];
            
        }];
        [delayAction addObject:action1];
        SKAction* sequenceAction = [SKAction sequence:delayAction];
        [self runAction:sequenceAction];
        
        delay += .05;
    }
    
    // Now set a callback to indicate the superSpawn is over
    NSMutableArray *delayAction = [NSMutableArray array];
    SKAction *durationAction = [SKAction waitForDuration:delay + 3];
    [delayAction addObject:durationAction];
    SKAction *action1 = [SKAction runBlock:^{
        
        // Set Gravity in the world
        NSNumber *chall = [NSNumber numberWithFloat:0];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"setGravityY" object:chall];
        
        //NSString *edge = @"off";
        //[[NSNotificationCenter defaultCenter] postNotificationName:@"edgeLoop" object:edge];
        
        [self gameAwardFinished];
        
    }];
    [delayAction addObject:action1];
    SKAction* sequenceAction = [SKAction sequence:delayAction];
    [self runAction:sequenceAction];
}

// The memory usage of drawing lines kills regular animations in the simulator. Fine on devices.
- (void)drawLines {
    
    // remove existing lines
    NSMutableArray *temp = [NSMutableArray array];
    for(CALayer *layer in self.scene.view.layer.sublayers) {
        if([layer.name isEqualToString:@"line"]) {
            [temp addObject:layer];
        }
    }
    [temp makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    
    // redraw lines
    for (SKNode *node in nodes){
        
        CAShapeLayer *lineLayer = [CAShapeLayer layer];
        lineLayer.name = @"line";
        
        Tile *tileNode = (Tile*)node;
        
        if (tileNode.isScheduled){
            lineLayer.strokeColor = [UIColor colorWithRed:0.195009 green:0.0 blue:0.495298 alpha:1.0].CGColor;
        }
        else {
            lineLayer.strokeColor = [UIColor colorWithRed:0.481071 green:0.0310057 blue:0.182903 alpha:1.0].CGColor;
        }
        lineLayer.lineWidth = 6;
        lineLayer.fillColor = nil;
        
        CGPathRef path = [tileNode createPathToMove];
        lineLayer.path = path;
        [self.scene.view.layer addSublayer:lineLayer];
        
        // path = nil;
        //CGPathRelease(path); // causes a SA warning, RAY
    }
}

#pragma mark User Interaction And Physics

- (void) touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    
    // use for selection Animations
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInNode:self];
    
    // enumerate through all nodes (nodes are tiles only)
    for (SKSpriteNode *node in nodes){
        
        for (SKSpriteNode *nodeAtPoint in [self nodesAtPoint:location]){
 
            // test node, right here against the nodes in the nodes array
            if ([nodeAtPoint isEqual:node]){
                
                selectedNode = nodeAtPoint;
                
                // Cast this as a tile to get to tile properties
                Tile *tile = (Tile*)selectedNode;
                [tile speak:[self alternateGender]];
                [tile tileWasSelected];
                
                NSMutableArray *delayAction = [NSMutableArray array];
                SKAction *durationAction = [SKAction waitForDuration:1];
                [delayAction addObject:durationAction];
                SKAction *action1 = [SKAction runBlock:^{
                    [tile expireSelected];
                }];
                [delayAction addObject:action1];
                SKAction* sequenceAction = [SKAction sequence:delayAction];
                [self runAction:sequenceAction];
                
                // flight control
                [tile addPointToMove:location];
                [tile clearWayPoints];
            }
        }
    }
    
    // Whack a tile splash screen interaction
    if (!selectedNode){
        for (SKSpriteNode *node in uiNodes){
            for (SKSpriteNode *nodeAtPoint in [self nodesAtPoint:location]){
                if ([nodeAtPoint isEqual:node]){
                    selectedNode = nodeAtPoint;
                }
            }
        }
    }
    if (!selectedNode){
        for (SKSpriteNode *nodeAtPoint in [self nodesAtPoint:location]){
            
            // test node, right here against the nodes in the nodes array
            if ([nodeAtPoint.name isEqual:@"uiButtons"]){
                NSString *btn = [uiButtons buttonAtLocation:location];
                if ([btn isEqualToString:@"gaoBtn"]){
                    [uiButtons userPressedGao];
                    [self reloadAtlases];
                    
                }
                else if ([btn isEqualToString:@"khomutBtn"]){
                    [uiButtons userPressedKhomut];
                    
                    [scoreBoard setScore:[NSNumber numberWithInt:initialScore]];
                    [scoreBoard setLives:[NSNumber numberWithInt:initialLives]];
                    
                    [self endGameAndReturnPass:NO];
                    
                    //seeya
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"loadMainMenu" object:nil];
                    
                }
            }
        }
    }
}

- (void) touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInNode:self];
    

    if ([selectedNode.name isEqualToString:@"closeIntro"]){
        // exclude non-tile objects before assuming object contains addPointToMove:
    }
    else if([selectedNode.name isEqualToString:@"whackATile"]){
        // exclude non-tile objects before assuming object contains addPointToMove:
    }
    else {
        
        if ([nodes count] > 0){
            Tile *tile = (Tile*)selectedNode;
            [tile addPointToMove:location];
        }
    }
    if (!selectedNode){
        
    }
}

- (void) touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    
    // use for selection Animations
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInNode:self];
    
    if (selectedNode){
        Box *box;
        Tile *tile = (Tile*)selectedNode; // handle on tile
        
        // unschedule if scheduled.
        tile.isScheduled = NO;
        
        // enumerate through box nodes to determine if line is drawn at box.
        for (SKSpriteNode *node in boxNodes){
            
            for (SKSpriteNode *nodeAtPoint in [self nodesAtPoint:location]){
                
                // test 2 is dicey but appears to work. probably a future bug.
                // I suspect this is because the box textures are curerently scaled
                if ([nodeAtPoint.name isEqual:node.name] && nodeAtPoint.texture.size.width > 0){
                    
                    box = (Box*)[self childNodeWithName:nodeAtPoint.name]; // handle on box
                    
                    
                    tile.isScheduled = YES;
                    
                    // here we know that the user messed up but we wont tell them
                    if ([tile.consonantClass isEqualToString:box.name]){
                        // could use this spot for a heavenly reverse synth swell
                    }
                    else {
                        // could use this spot for an ominous reverse synth build
                    }
                }
            }
        }
    }
    if (!selectedNode){
        // looks a little dicey under the hood but is working...
        // NSLog(@"NodesAt Point: %@", [self nodesAtPoint:location]);
        for (SKSpriteNode *nodeAtPoint in [self nodesAtPoint:location]){
            if ([nodeAtPoint.name isEqualToString:@"closeIntro"]){
                if ([self setLockTimerObject:[nodeAtPoint.name copy]]){
                    [self introWasDismissed];
                }
            }
            else if ([nodeAtPoint.name isEqualToString:@"whackATile"]){
            }
            else if ([nodeAtPoint.name isEqualToString:@"newGame"]){
                if ([self setLockTimerObject:[nodeAtPoint.name copy]]){
                    [self newGame];
                }
            }
            else if ([nodeAtPoint.name isEqualToString:@"closeIntermediateMessage"]){
                if ([self setLockTimerObject:[nodeAtPoint.name copy]]){
                    [self continueGameAfterMessage];
                }
            }
        }
    }
    
    selectedNode = nil;
}

- (void) physicsContact:(SKPhysicsContact*) contact {
    
    SKSpriteNode *firstNode, *secondNode;
    
    // Note to Self: bodyA bodyB is LAME
    firstNode = (SKSpriteNode *)contact.bodyA.node;
    secondNode = (SKSpriteNode*)contact.bodyB.node;
    
    debug += 1;
    
    // What box did it hit?
    // box is an object but this is a link to the sprite within the box object.
    
    NSArray *consonantClasses = [NSArray arrayWithObjects:@"High Class", @"Middle Class", @"Low Class", nil];
    
    Tile *tile;
    Box *box;
    
    // NSLog(@"Nodes: %@ %@, %i", firstNode.name, secondNode.name, debug);
    
    // only do this if tile and a box.
    if (firstNode.name && secondNode.name){
        for (NSString *class in consonantClasses){
            
            if ([firstNode.name isEqualToString:class]){
                
                // First Node Is a Box.
                // second Node is a tile
                
                // now to get the parent class that created the sprites
                box = (Box*)[self childNodeWithName:firstNode.name]; // both the node and the sprite are named the same
                tile = (Tile*)[self childNodeWithName:secondNode.name];
            }
            else if ([secondNode.name isEqualToString:class]){
                
                // Second Node is a box.
                // First Node is a tile
                
                box = (Box*)[self childNodeWithName:secondNode.name]; // both the node and the sprite are named the same
                tile = (Tile*)[self childNodeWithName:firstNode.name];
                
            }
        }
    }
    
    if (box && tile){

        // unsubscribe from future collisions for this round. maybe
        
        // user selected a path for box
        if (tile.isScheduled){
            
            [tile tileWasSelected];
            
            if ([box.name isEqualToString:tile.consonantClass]){
            
                // Correct. Next Challenge
                // unschedule box
                tile.isScheduled = NO;
                [self win:tile];
                
                [[SoundManager sharedManager] playMusic:@"CoinDrop1.caf" looping:NO fadeIn:NO];
            }
            else {
            
                // Incorrect. Repeat Challenge
                // unschedule box
                [box sink];
                tile.isScheduled = NO;
                [self lose:tile];
                
                [[SoundManager sharedManager] playMusic:@"incorrect.caf" looping:NO fadeIn:NO];
            }
        }
    }
}

-(void)update:(CFTimeInterval)currentTime {
    
    if (!lock){
        if (!_lastUpdateTime) _lastUpdateTime = currentTime;
        _dt = currentTime - _lastUpdateTime;
        _lastUpdateTime = currentTime;
        
        // move the tiles. individual tiles store bearing in the waypoints array
        for (Tile *tile in nodes){
            [tile move:@(_dt)];
        }
        
        // Performance tweak:
        // reduce processing power when lines are peaking.
        int slowDown;
        if ([nodes count]> 7){ slowDown = 8; }
        else slowDown = 3;
        
        // redraw lines
        if (iterate < slowDown){
            iterate += 1;
        }
        else {
            [self drawLines];
            iterate = 0;
        }
    }
}

#pragma mark Use cases / Consequences

- (void) win:(Tile*)tile {

    [scoreBoard addPointsToScore];
    lastCorrectChallenge +=1;
    
    [tile explodeOut];
    tile.zPosition -= 1;
    
    // determines endGameFlag
    [self checkGameType]; // uses last correct challenge to see if the next key is still itb
    
    // delay for good evil things
    NSMutableArray *delayAction = [NSMutableArray array];
    SKAction *durationAction = [SKAction waitForDuration:2];
    [delayAction addObject:durationAction];
    SKAction *action1 = [SKAction runBlock:^{
        
        [self removeTile:tile];
        

        if ([nodes count] == 0){
            challengesAreFinished = YES;
        }
        

        
    }];
    [delayAction addObject:action1];
    SKAction* sequenceAction = [SKAction sequence:delayAction];
    [self runAction:sequenceAction];

    // Short delay for rewards
    NSMutableArray *delayAction2 = [NSMutableArray array];
    SKAction *durationAction2 = [SKAction waitForDuration:.5];
    [delayAction2 addObject:durationAction2];
    SKAction *action2 = [SKAction runBlock:^{
    
        if (endGameFlag){
            
            // starts superSpawn
            if (tile.isLastSpawn){
                [self winGameAward];
            }
            
        }
        
    }];
    [delayAction2 addObject:action2];
    SKAction* sequenceAction2 = [SKAction sequence:delayAction2];
    [self runAction:sequenceAction2];
}

- (void) lose:(Tile*)tile {

    [scoreBoard loseLife];
    [scoreBoard clearPoints];
    if ([scoreBoard lives] == 0) {
        //[scoreBoard resetLivesAndScore];
        allLivesLost = YES;
    }
    
    currentSpawn -= [nodes count];
    if (currentSpawn < 0) currentSpawn = 0;
    
    [tile implode];
    
    Blood *blood = [[Blood alloc] initWithColor:@"red"];
    [blood runAction:[SKAction fadeOutWithDuration:1]];
    [self addChild:blood];
    
    [self removeActionForKey:@"spawnAction"];
    
    // temporarily stop further tiles from spawning this round
    // shouldSpawn = NO;
    
    // block update
    lock = YES;
    
    // make the boxes respond to physics
    for (Box *box in boxNodes){
        [box unPin];
    }
    
    // Set Gravity in the world
    NSNumber *chall = [NSNumber numberWithFloat:-10];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"setGravityY" object:chall];
    
    // kill the lines
    NSMutableArray *temp = [NSMutableArray array];
    for(CALayer *layer in self.scene.view.layer.sublayers) {
        if([layer.name isEqualToString:@"line"]) {
            [temp addObject:layer];
        }
    }
    [temp makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    
    // delay for bad evil things
    NSMutableArray *delayAction = [NSMutableArray array];
    SKAction *durationAction = [SKAction waitForDuration:2];
    [delayAction addObject:durationAction];
    SKAction *action1 = [SKAction runBlock:^{
        
        [blood removeFromParent];

        // Set Gravity in the world
        NSNumber *chall = [NSNumber numberWithFloat:.0];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"setGravityY" object:chall];
        
        for (Box *box in boxNodes){
            [box pin];
        }
        
        [self removeTile:tile];
        
        if (allLivesLost){
            [self promptRestart];
            allLivesLost = NO;
            if (accrueScore){
                [self accruePointsToGlobalScore];
            }
        }
        
        else {
            [self softRestart];
        }
 
    }];
    [delayAction addObject:action1];
    SKAction* sequenceAction = [SKAction sequence:delayAction];
    [self runAction:sequenceAction];
    
}


- (void) winGameAward {
    
    [self superSpawn];
    
}

- (void) gameAwardFinished {
    [self endGameAndReturnPass:YES];
}

#pragma mark interruption screen management

// First is a screen that is displayed when a message is provided in the data file.
// This method is called from spawn when the message is found.

- (void) waitForChallengesToFinish {

    if (challengesAreFinished){
        [self pauseGameForMessage];
        [self removeActionForKey:@"waitAction"];
        challengesAreFinished = NO;
    }
    else {
    // recursively call this method
        [self runAction: [SKAction sequence:@[[SKAction waitForDuration:.2], [SKAction performSelector:@selector(waitForChallengesToFinish) onTarget:self]]] withKey:@"waitAction"] ;
    }
}

- (void) pauseGameForMessage {
 
    // stop the game and dispose of elements except the scoreboard
    // similar behavior to lose but not the same.
    
    [self removeActionForKey:@"spawnAction"];
    
    // block update
    lock = YES;
    
    // make the boxes respond to physics
    for (Box *box in boxNodes){
        [box unPin];
    }
    
    // Set Gravity in the world
    NSNumber *chall = [NSNumber numberWithFloat:-10];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"setGravityY" object:chall];
    
    // kill the lines
    NSMutableArray *temp = [NSMutableArray array];
    for(CALayer *layer in self.scene.view.layer.sublayers) {
        if([layer.name isEqualToString:@"line"]) {
            [temp addObject:layer];
        }
    }
    [temp makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    
    // let gravity animation finish
    NSMutableArray *delayAction = [NSMutableArray array];
    SKAction *durationAction = [SKAction waitForDuration:.5];
    [delayAction addObject:durationAction];
    SKAction *action1 = [SKAction runBlock:^{
        
        // reset Gravity in the world
        NSNumber *chall = [NSNumber numberWithFloat:.0];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"setGravityY" object:chall];
        
        for (Box *box in boxNodes){
            [box pin];
        }
        [self displayIntermediateMessage];

    }];
    [delayAction addObject:action1];
    SKAction* sequenceAction = [SKAction sequence:delayAction];
    [self runAction:sequenceAction];

    [scoreBoard hideBasic];
    

}

// display intermediate game message items
- (void) displayIntermediateMessage {
    
    MessageScreen *msgScreen = [[MessageScreen alloc]init];
    msgScreen.name = @"intermediate";
    [msgScreen presentIntermediateWithUnitDescription:[challengeData[currentSpawn] objectForKey:@"unitDescription"] sectionDescription:[challengeData[currentSpawn] objectForKey:@"sectionDescription"]];
    [self addChild:msgScreen];
    
    // clear out message so it does not reappear if user gets next item wrong
    [challengeData[currentSpawn] removeObjectForKey:@"message"];
}

// dispose of any elements created during interruption and start new section
- (void) continueGameAfterMessage {
    
    [(MessageScreen*)[self childNodeWithName:@"intermediate"] intermediateWasDismissed];
    
    // Run this code after message screen fades
    NSMutableArray *delayAction = [NSMutableArray array];
    SKAction *durationAction = [SKAction waitForDuration:.5];
    [delayAction addObject:durationAction];
    SKAction *action1 = [SKAction runBlock:^{
        
        [(MessageScreen*)[self childNodeWithName:@"intermediate"] seppuku];
        [self softRestart];
    }];
    [delayAction addObject:action1];
    SKAction* sequenceAction = [SKAction sequence:delayAction];
    [self runAction:sequenceAction];
    
    [scoreBoard showBasic];

}

// Second is a screen that is displayed when the user loses three lives.
- (void) promptRestart {
    
    [scoreBoard hideBasic];
    
    MessageScreen *msgScreen = [[MessageScreen alloc]init];
    msgScreen.name = @"restartGame";
    [msgScreen presentGameOverWithUnitDescription:@"No Lives Left." sectionDescription:@"Start Over"];
    [self addChild:msgScreen];
}

// called when user dismisses promptRestart items
- (void) newGame {
    
    [(MessageScreen*)[self childNodeWithName:@"restartGame"] gameOverWasDismissed];
    
    // Run this code after message screen fades
    NSMutableArray *delayAction = [NSMutableArray array];
    SKAction *durationAction = [SKAction waitForDuration:.5];
    [delayAction addObject:durationAction];
    SKAction *action1 = [SKAction runBlock:^{
        
        [(MessageScreen*)[self childNodeWithName:@"restartGame"] seppuku];
        [scoreBoard setScore:[NSNumber numberWithInt:initialScore]];
        [scoreBoard setLives:[NSNumber numberWithInt:initialLives]];
        //[scoreBoard resetLivesAndScore];
        [self restartGame];
    }];
    
    [delayAction addObject:action1];
    SKAction* sequenceAction = [SKAction sequence:delayAction];
    [self runAction:sequenceAction];
    
    [scoreBoard showBasic];

}

// used when user runs out of men
- (void)restartGame {
    
    for (SKNode *node in nodes){
        [node removeFromParent];
    }
    
    nodes = nil;
    
    [self enumerateChildNodesWithName:@"line" usingBlock:^(SKNode *node, BOOL *stop) {
        [node removeFromParent];
    }];
    
    [self initializeNodeArrays];
    
    // _currentSpawnTime = 5.0f;
    currentSpawn = 0;
    lastCorrectChallenge = 0;
    // restart
    [self spawnTile];
}

// used when user loses a man
- (void) softRestart {
    
    for (SKNode *node in nodes){
        [node removeFromParent];
    }
    
    nodes = nil;
    
    [self enumerateChildNodesWithName:@"line" usingBlock:^(SKNode *node, BOOL *stop) {
        [node removeFromParent];
    }];
    
    endGameFlag = NO;
    currentGame = @"intoTheBox";
    currentSpawn = lastCorrectChallenge;
    [self initializeNodeArrays];
    [self spawnTile];
}

#pragma mark Texture management

- (void) loadAtlases {
    
    [[TextureManager sharedInstance] getAtlasesForScene:@"gameScene" caller:self];
    
}

- (void) atlasesWereLoaded:(NSDictionary*)atlases {
    
    smallGfxAtlas = (SKTextureAtlas*)[atlases objectForKey:@"smallGfxAtlas"];
    
    SKTextureAtlas *consonantsAtlas = (SKTextureAtlas*)[atlases objectForKey:@"consonantsAtlas"];
    SKTextureAtlas *vowelsAtlas = (SKTextureAtlas*)[atlases objectForKey:@"vowelsAtlas"];
    SKTextureAtlas *animalsAtlas = (SKTextureAtlas*)[atlases objectForKey:@"animalsAtlas"];
    SKTextureAtlas *levelsAtlas = (SKTextureAtlas*)[atlases objectForKey:@"levelsAtlas"];
    SKTextureAtlas *numbersAtlas = (SKTextureAtlas*)[atlases objectForKey:@"numbersAtlas"];
    
    gameTextures = [NSArray arrayWithObjects: consonantsAtlas, vowelsAtlas, smallGfxAtlas, levelsAtlas, animalsAtlas, numbersAtlas, nil];
    
    for (Tile *tile in nodes){
        [tile reloadTexturesWithAtlases:gameTextures];
    }
}

- (void) reloadAtlases {
    
    [self loadAtlases];

}

#pragma mark Utility

// only to be called upon a level's completion
- (void) accruePointsToGlobalScore {
    
    NSDictionary *previousState = [UserDefaults restoreStateGlobal];
    
    NSNumber *runningTotal = [previousState objectForKey:@"totalChallenges"];
    NSNumber *challenges = [NSNumber numberWithInt:[runningTotal intValue]];
    
    NSNumber *runningScore = [previousState objectForKey:@"totalScore"];
    NSNumber *newGlobalScore = [NSNumber numberWithInt:[runningScore intValue] + [scoreBoard getPoints]];
    
    NSNumber *runningLevelsCompleted = [previousState objectForKey:@"levelsCompleted"];
    NSNumber *levelsCompleted = [NSNumber numberWithInt:[runningLevelsCompleted intValue]];
    
    NSNumber *pointsThisRound = [NSNumber numberWithInt:[scoreBoard getPoints]];
    
    NSDictionary *globalState = [NSDictionary dictionaryWithObjectsAndKeys:
                                 challenges, @"totalChallenges",
                                 newGlobalScore, @"totalScore",
                                 levelsCompleted, @"levelsCompleted",
                                 pointsThisRound, @"pointsThisRound",
                                 nil];
    
    [UserDefaults saveStateGlobal:globalState];
    
//    NSLog(@"accruePointsToGlobalScore");
    
}

- (NSString*) alternateGender {
    
    if ([genderAlternator isEqualToString:@"m"]){
        genderAlternator = @"f";
    }
    else {
        genderAlternator = @"m";
    }
    return genderAlternator;
}

- (NSString*) getOppositeGender {
    
    if ([genderAlternator isEqualToString:@"m"]){
        return @"f";
    }
    else {
        return @"m";
    }
}


// locks a button for one second, then releases it.
- (BOOL) setLockTimerObject:(NSString*)key {
    
    //
    if ([[lockData objectForKey:key] intValue] == 1){
        return NO;
    }
    
    [lockData setObject:@1 forKey:key];
    
    NSMutableArray *delayAction = [NSMutableArray array];
    SKAction *durationAction = [SKAction waitForDuration:1];
    [delayAction addObject:durationAction];
    SKAction *action1 = [SKAction runBlock:^{
        [lockData setObject:@0 forKey:key];
    }];
    [delayAction addObject:action1];
    SKAction* sequenceAction = [SKAction sequence:delayAction];
    [self runAction:sequenceAction];
    
    return YES;
}

// check to see if game is ready to switch back to thailes.
- (void) checkGameType {
    
    if ([challengeData[lastCorrectChallenge] objectForKey:@"gameType"]){
        currentGame = [challengeData[lastCorrectChallenge] objectForKey:@"gameType"];
    }
    
    if (!currentGame) {
        
        // we do not know what game type it is, need to figure this out by
        // accessing the last time it was set in the data stack
        for (int i = 0; i < lastCorrectChallenge; i++) {
            if ([challengeData[i] objectForKey:@"gameType"])
                currentGame = [challengeData[i] objectForKey:@"gameType"];
        }
        // if it was not defined in the plist at all, default to thailes
        if (!currentGame){
            currentGame = @"intoTheBox";
        }
    }
    
    // need to set the current game.
    if (![currentGame isEqualToString:@"intoTheBox"]){
    
        // we have exceeded the threshhold of game data. return
        endGameFlag = YES;
    }
}


- (BOOL) checkForEndOfGame {
    
    // in order to determine that the current tile being spawned is valid, we really need to check the previous entry
    
    //note to keny: tried this once. but may have to try it again. the issue is that when spawning a new tile and end of game is contained in the key that says i am at the end. One thought is to just invalidate that as acceptable data and use the previous tile as the end of game, another thought is to forge forward and use this data that contains the transition information.
    
    if ([challengeData[currentSpawn] objectForKey:@"gameType"]){
        currentGame = [challengeData[currentSpawn] objectForKey:@"gameType"];
    }
    
    if (!currentGame) {
        
        // we do not know what game type it is, need to figure this out by
        // accessing the last time it was set in the data stack
        for (int i = 0; i < currentSpawn; i++) {
            if ([challengeData[i] objectForKey:@"gameType"])
                currentGame = [challengeData[i] objectForKey:@"gameType"];
        }
        // if it was not defined in the plist at all, default to thailes
        if (!currentGame){
            currentGame = @"intoTheBox";
        }
    }
    
    if([currentGame isEqualToString:@"intoTheBox"]){
            return NO;
    }
    
    return YES;
}

// final code before leaving to clean up things.
- (void) endGameAndReturnPass:(BOOL)pass {
 
    // careful now, fast enumeration is our frienemy
    NSMutableArray *objectsToDelete = [NSMutableArray array];
    for(CALayer *layer in self.scene.view.layer.sublayers) {
        if([layer.name isEqualToString:@"line"]) {
            [objectsToDelete addObject:layer];
        }
    }
    for (CALayer *obj in objectsToDelete){
        [obj removeFromSuperlayer];
    }
    objectsToDelete = nil;
    
    for (Tile *node in nodes){
        [node seppuku];
    }

    for (Box *box in boxNodes){
        [box seppuku];
    }
    
    NSString *edge = @"on";
    [[NSNotificationCenter defaultCenter] postNotificationName:@"edgeLoop" object:edge];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"unregisterForUpdates" object:self];
    
    for (id ob in observers){
        [[NSNotificationCenter defaultCenter] removeObserver:ob];
    }
    
    [self removeFromParent];
    [self removeAllActions]; // crucial
    
    NSNumber *passFail = [NSNumber numberWithBool:pass];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"updateTileGroupAndCloseGame" object:passFail];
    
}

#pragma Utility

// remove a single tile. Called when tile hits a box via physicsContact
- (void) removeTile:(Tile*)tile {

    Tile *objectToRemove;
    
    for (Tile *tileReference in nodes){
        if ([tileReference isEqual:tile]){
            objectToRemove = tileReference;
        }
    }
    [nodes removeObject:objectToRemove]; // im being nice...
    
    // remove the box
    [tile removeFromParent];
}

-(void) registerObservers
{
    
    self ->observers = [NSMutableSet set];
    
    __weak __typeof(self) weaklyNotifiedSelf = self;
    
    id ob1 = [[NSNotificationCenter defaultCenter] addObserverForName:@"physicsContact" object:nil queue:nil usingBlock:^(NSNotification *n) {
        
        SKPhysicsContact *contact = [n object];
        [weaklyNotifiedSelf physicsContact:contact]; // is nil
        
    }];
    
    [observers addObject:ob1];
    
    id ob2 = [[NSNotificationCenter defaultCenter] addObserverForName:@"khomutButtonPressed" object:nil queue:nil usingBlock:^(NSNotification *n) {

        [weaklyNotifiedSelf endGameAndReturnPass:NO]; // is nil
        
    }];
    
    [observers addObject:ob2];
    
}

- (void) createIntensityArray {
    
    @autoreleasepool {
        
        // what needs to happen at the beginning of a section - the app needs
        // to analyze the data for start / end intensities, and determine transition
        // points. Then it can populate an array with spawn times that are
        // proportionate to the settings. Further a given spawn will access
        // the array at the currentSpawn
        NSMutableArray *startIndexes = [NSMutableArray array];
        NSMutableArray *endIndexes = [NSMutableArray array];
        
        for (int i = 0; i < [challengeData count]; i++){
            if ([challengeData[i] objectForKey:@"startIntensity"]){
                [startIndexes addObject:[NSNumber numberWithInt:i]];
            }
            else if ([challengeData[i] objectForKey:@"endIntensity"]){
                [endIndexes addObject:[NSNumber numberWithInt:i]];
            }
        }
        
        NSMutableArray *tempArray = [NSMutableArray array];
        
        // iterate through found start/end indexes
        for (int i = 0; i < [startIndexes count]; i++){
            
            int sIndex = [startIndexes[i] intValue];
            int eIndex = [endIndexes[i] intValue];
            
            int span = eIndex - sIndex;
            float sIntensity = [[challengeData[sIndex] objectForKey:@"startIntensity"] intValue];
            float eIntensity = [[challengeData[eIndex] objectForKey:@"endIntensity"] intValue];
            
            float range = eIntensity - sIntensity;
            float increment = range / span;
            
            float intensity = sIntensity;
            
            [tempArray addObject:[NSNumber numberWithInt:intensity]];
            
            for (int i = 0; i < span; i++){
                intensity += increment;
                [tempArray addObject:[NSNumber numberWithInt:intensity]];
            }
        }
        
        // now temp array is in percentages correct, in that 0% is equal to the least intense and 100 % is the most intense. Now we have to convert it to a useable format for the game so we need to make the range numbers that relate to _currentSpawnTime, a range or 2 (most intense) to 5 (least intense)
        
        //  so the first thing to do is to make the array linearly accurate to the desired output by flipping the percentages
        
        for (int i = 0; i < [tempArray count]; i++){
            float temp = [tempArray[i] floatValue];
            float newValue = 100 - temp;
            tempArray[i] = [NSNumber numberWithFloat:newValue];
        }
        
        // now that the intensity array is reversed, we need to
        // make it match the appropriate range, 100% = 2 0% = 5
        
        // to keep things simple we will caluclate only for the range, then add the minimum back in as an offset
        float range = spawnRangeMax - spawnRangeMin; // if 2 - 5, the range is 3
        
        for (int i = 0; i < [tempArray count]; i++){
            
            // Here we take the inverted percentage (tempArray[i]) and multiply it by the range. then divide by a hundred to get a decimal equivalent that is relative to the range. then add back in the offset.
            float adjustedValue = ([tempArray[i] floatValue] * range) / 100 + spawnRangeMin;
            
            tempArray[i] = [NSNumber numberWithFloat:adjustedValue];
        }
        
        // and set an iVar so OC can dump all the intermediates
        intensityArray = tempArray;
    }
}

// Once we have the plist file into memory, we need to analyze it to
// determine if it requests repeats of the data or if the data should
// be shuffled, we do that here.
- (NSArray*) analyzeDataFromPlistDict:(NSArray*)dict {
    
    @autoreleasepool {
        
        // The data is set up so that there are transitions as indicated by
        // start and end indexes. We use these to traverse the sections independently
        NSMutableArray *startIndexes = [NSMutableArray array];
        NSMutableArray *endIndexes = [NSMutableArray array];
        
        // here the sections are identified.
        for (int i = 0; i < [dict count]; i++){
            
            if ([dict[i] objectForKey:@"startIntensity"]){
                [startIndexes addObject:[NSNumber numberWithInt:i]];
            }
            else if ([dict[i] objectForKey:@"endIntensity"]){
                [endIndexes addObject:[NSNumber numberWithInt:i]];
            }
        }
        
        if ([startIndexes count] != [endIndexes count]){
            NSLog(@"Check Your intensity settings.");
        }
        
        NSMutableArray *tempArrayB = [NSMutableArray array];
        
        // And now to traverse the sections to determine what needs to be done
        // this loop goes through each section of the file
        for (int i = 0; i < [startIndexes count]; i++){
            
            int sIndex = [startIndexes[i] intValue];
            int eIndex = [endIndexes[i] intValue];
            
            int repeat = 0;
            if ([dict[sIndex] objectForKey:@"repeatSection"]){
                repeat = [[dict[sIndex] objectForKey:@"repeatSection"] intValue];
            }
            
            BOOL shuffle = NO;
            if ([[dict[sIndex] objectForKey:@"allowsShuffle"] boolValue]){
                shuffle = YES;
            }
            
            NSMutableArray *tempArrayA = [NSMutableArray array];
            
            // Here we load the file info into arrayA repeat each section as needed.
            // note the mutableCopy was necessary here in order to mutate the data later
            if (repeat == 0 || repeat == 1){
                for (int j = sIndex; j <= eIndex; j++) {
                    [tempArrayA addObject:[dict[j] mutableCopy]];
                }
            }
            else {
                for (int k = 0; k < repeat; k++) {
                    for (int l = sIndex; l <= eIndex; l++) {
                        [tempArrayA addObject:[dict[l] mutableCopy]];
                    }
                }
            }
            
            // as we go through the section
            // we extract the thai key into its own array and shuffle it.
            // This way we can preserve the transitions of the data without disturbing it too much.
            if (shuffle){
                
                NSMutableArray *keysToShuffle = [NSMutableArray array];
                for (NSMutableDictionary *item in tempArrayA){
                    [keysToShuffle addObject:[item objectForKey:@"thai"]];
                }
                
                [keysToShuffle shuffle];
                [keysToShuffle shuffle];
                
                int y = 0;
                for (NSMutableDictionary *item in tempArrayA){
                    
                    [item setObject:keysToShuffle[y] forKey:@"thai"];
                    y +=1;
                }
            }
            
            // But repeating entries cause some keys to be doubled. In order to keep the
            // intensity index proper for the entire segment, we remove secondary
            // references to start and endIntensity
            for (int s = 1; s < [tempArrayA count] -1; s += 1){
                [tempArrayA[s] removeObjectForKey:@"startIntensity"];
                [tempArrayA[s] removeObjectForKey:@"endIntensity"];
                [tempArrayA[s] removeObjectForKey:@"message"];
            }
            
            // make any last minute data modifications here, e.g. random key etc...
            for (NSDictionary *item in tempArrayA){
                
                if ([item objectForKey:@"maskOptions"]){
                    
                      CharacterLookup *lookup = [[CharacterLookup alloc]init];
                      NSString *replace = [lookup generateRandomNoiseCharacters:(int)[[item objectForKey:@"thai"] length] usingMask:[item objectForKey:@"maskOptions"]];
                    
                    [item setValue:replace forKey:@"thai"];
                }
            }
            
            
            // then we pass all this into the secondary temp array, in order to
            // proceed with parsing the next section:
            for (NSDictionary *item in tempArrayA){
                [tempArrayB addObject:item];
            }
        }
        
        // finally the final key in the dict is added, it is a dummy key, designed to keep things happy
        [tempArrayB addObject:[dict[[dict count] -1] mutableCopy]];
        
        return [NSArray arrayWithArray:tempArrayB];
    }
}

- (NSArray*) loadDataPlist:(NSString*)plist withLevel:(int)level {
    
    NSString *path = [[NSBundle mainBundle] bundlePath];
    
    NSString *finalPath;
    switch (level) {
        case 1: finalPath = [path stringByAppendingPathComponent:plist]; break;
        default: finalPath = [path stringByAppendingPathComponent:plist]; break;
    }
    
    NSArray* data = [NSArray arrayWithContentsOfFile:finalPath];
    
    return data;
}

- (void)dealloc
{
    if (kDEALLOC) NSLog(@"IntoTheBox: Dealloc");
}
@end

//  Copyright (c) 2012 BA3, LLC. All rights reserved.
#import "MEAnimatedSlippyMapTest.h"
#import "../TileProviderTests/MEInternetTileProvider.h"
#import "../METestCategory.h"
#import "../METestConsts.h"

@implementation MEStaticAsyncTileProviderBatch
{
    dispatch_queue_t serialQueue;
}

static int earlyExitCount;


- (id) init
{
	if(self=[super init])
	{
		self.isAsynchronous = YES;
		earlyExitCount=0;
        serialQueue = dispatch_queue_create("serialME", 0);
		self.sleepTime = 0.0;
		self.failWithUIImage = NO;
		self.useNSData = YES;
	}
	return self;
}

- (void) dealloc
{
    dispatch_release(serialQueue);
	[super dealloc];
}

- (void) nextTileSet
{
	self.currentTileSet++;
	if(self.currentTileSet>1)
		self.currentTileSet=0;
}

- (void) loadTile:(METileInfo*) tileInfo simulateFailure:(BOOL) simulateFailure
{
	NSLog(@"Level %d", tileInfo.slippyZ);
	
    //Early exit if tile is no longer needed.
    if(![super isNeededAnimated:tileInfo])
    {
        [super tileLoadComplete:tileInfo];
        @synchronized(self)
        {
            earlyExitCount++;
        }
        return;
    }
    
	[NSThread sleepForTimeInterval:0.2];
	
    //Determine which tile to show
	if(simulateFailure)
	{
		if(self.failWithUIImage)
		{
			tileInfo.uiImage = [UIImage imageNamed:@"pinRed"];
			tileInfo.tileProviderResponse = kTileResponseRenderUIImage;
		}
		else
		{
			tileInfo.cachedImageName=@"noData";
			tileInfo.tileProviderResponse = kTileResponseRenderNamedCachedImage;
		}
		tileInfo.isDirty = YES;
	}
	else
	{
		NSString* tileName;
		tileName = [NSString stringWithFormat:@"tile_%d.%d",
					tileInfo.frame,
					self.currentTileSet];
		
		if(self.useNSData)
		{
			NSString* imagePath = [[NSBundle mainBundle] pathForResource:tileName ofType:@"png"];
			NSLog(imagePath);
			tileInfo.nsImageData = [NSData dataWithContentsOfFile:imagePath];
			tileInfo.tileProviderResponse = kTileResponseRenderNSData;
			tileInfo.imageDataType = kImageDataTypePNG;
		}
		else
		{
			tileInfo.uiImage = [UIImage imageNamed:tileName];
			tileInfo.tileProviderResponse = kTileResponseRenderUIImage;
		}
		tileInfo.isDirty = NO;
	}
    
    //Notify engine tile is loaded
    [super tileLoadComplete:tileInfo];
}

- (void) requestTileAsync:(METileInfo *)tileInfo
{
	NSArray* tiles = [NSArray arrayWithObject:tileInfo];
	[self requestTilesAsync:tiles];
}

- (void) requestTilesAsync:(NSArray *)tileInfos
{
	if(tileInfos.count==0)
		return;
	
    METileInfo *firstTile = [tileInfos lastObject];
    //NSLog(@"Queueing %i tiles for level %i", tileInfos.count, firstTile.slippyZ);
    
    __block NSArray *batchOfTiles = [[NSArray arrayWithArray:tileInfos] retain];
    dispatch_async(serialQueue, ^{
		int currentExitCount = 0;
		@synchronized(self)
		{
			currentExitCount = earlyExitCount;
		}
        [NSThread sleepForTimeInterval:self.sleepTime];
		int zoomLevel = -1;
        METileInfo *firstTile = [tileInfos lastObject];
		zoomLevel = firstTile.slippyZ;
        
        for(METileInfo* tileInfo in batchOfTiles)
		{
			//Randomly fail the download?
			if(self.failRandomly && (arc4random_uniform(4)==2))
				[self loadTile:tileInfo simulateFailure:YES];
			else
				[self loadTile:tileInfo simulateFailure:NO];
		}
		
		@synchronized(self)
		{
			if (currentExitCount != earlyExitCount)
			{
				//NSLog(@"Cancelled %i tiles for zoom: %i", earlyExitCount-currentExitCount, zoomLevel);
			}
		}
		
        [batchOfTiles release];
    });
}

@end


/////////////////////////////////////////////////////
@implementation MEAnimatedMapTest
- (id) init
{
	if(self=[super init])
	{
		self.name=@"Animated Test 1";
		self.currentLocation = -1;
		self.currentState = -1;
		self.automaticTileRequestMode = YES;
	}
	return self;
}

- (void) addNonAnimatedMap
{
	//Add single frame non-animated map
	MEVirtualMapInfo* vmapInfo = [[[MEVirtualMapInfo alloc]init]autorelease];
	vmapInfo.name = self.name;
	vmapInfo.meTileProvider = self.tileProvider;
	vmapInfo.zOrder = 5;
	vmapInfo.maxLevel = 18;
    vmapInfo.loadingStrategy = kHighestDetailOnly;
	vmapInfo.defaultTileName = @"grayGrid";
	vmapInfo.compressTextures = YES;
	vmapInfo.zOrder = 5;
	
	[self.meMapViewController addMapUsingMapInfo:vmapInfo];
	[self.meMapViewController setMapAlpha:self.name alpha:1.0];
}

- (void) addAnimatedMap
{
	//Add 5 frame virtual map
	MEAnimatedVirtualMapInfo* mapInfo = [[[MEAnimatedVirtualMapInfo alloc]init]autorelease];
	
	mapInfo.name = self.name;
	mapInfo.meTileProvider = self.tileProvider;
	mapInfo.zOrder = 5;
	mapInfo.frameCount = 5;
	mapInfo.frameRate = 1.0;
	mapInfo.repeatDelay = 1.0;
	mapInfo.maxLevel = 18;
    mapInfo.loadingStrategy = kHighestDetailOnly;
	mapInfo.defaultTileName = @"grayGrid";
	mapInfo.compressTextures = YES;
	mapInfo.zOrder = 5;
	mapInfo.automaticTileRequestMode = self.automaticTileRequestMode;
	
	[self.meMapViewController addMapUsingMapInfo:mapInfo];
	[self.meMapViewController setMapAlpha:self.name alpha:1.0];
}

- (void) addMap
{
	//Create tile provider if needed
	if(self.tileProvider==nil)
	{
		self.tileProvider = [[[MEStaticAsyncTileProviderBatch alloc]init]autorelease];
		self.tileProvider.meMapViewController = self.meMapViewController;
	}
	
	//Create map
	[self addAnimatedMap];
}

- (void) start
{
	if(self.isRunning)
		return;
	
	[self.meTestCategory stopAllTests];
	
	[self addMap];
	[self pauseMap];
	
	
	self.isRunning=YES;
	
	self.interval = 2.0;
	[super start];
}


- (void) pauseMap
{
	[self.meMapViewController pauseAnimatedVirtualMap:self.name];
	[self.meMapViewController setAnimatedVirtualMapFrame:self.name frame:4];
	
}

- (void) unpauseMap
{
	[self.meMapViewController playAnimatedVirtualMap:self.name];
}

- (NSString*) label
{
	switch(self.currentState)
	{
		case 0:
			return @"Paused";
			break;
			
		case 1:
			return @"Play / Zoom";
			break;
			
		case 2:
			return @"Paused";
			break;
			
		case 3:
			return @"Randomly unavailable";
			
			break;
			
		default:
			
			return @"";
			break;
	}
}

- (void) userTapped
{
	self.currentState++;
	
	switch(self.currentState)
	{
		case 0:
			[self start];
			break;
			
		case 1:
			[self unpauseMap];
			[self startTimer];
			break;
			
		case 2:
			[self pauseMap];
			break;
			
		case 3:
			self.tileProvider.failRandomly = YES;
			break;
			
		case 4:
			[self stop];
			self.currentState = -1;
			self.tileProvider.failRandomly = NO;
			break;
			
		default:
			break;
	}
}

- (void) timerTick
{
	if(self.currentState!=1)
		return;
	
	self.currentLocation++;
	
	MELocation location = self.meMapViewController.meMapView.location;
	uint minalt=4000;
	uint maxalt=100000000;
	
	switch(self.currentLocation)
	{
		case 0:
			location.center.longitude = RDU_COORD.longitude;
			location.center.latitude = RDU_COORD.latitude;
			location.altitude = minalt;
			break;
			
		case 1:
			location.center.longitude = HOU_COORD.longitude;
			location.center.latitude = HOU_COORD.latitude;
			location.altitude = maxalt/2;
			[self.meMapViewController refreshMap:self.name];
			break;
			
		case 2:
			location.center.longitude = MIA_COORD.longitude;
			location.center.latitude = MIA_COORD.latitude;
			location.altitude = minalt;
			break;
			
		case 3:
			location.center.longitude = SFO_COORD.longitude;
			location.center.latitude = SFO_COORD.latitude;
			location.altitude = maxalt;
			break;
			
		case 4:
			location.center.longitude = JFK_COORD.longitude;
			location.center.latitude = JFK_COORD.latitude;
			location.altitude = maxalt/5;
			break;
			
		default:
			self.currentLocation=-1;
			break;
	}
	
	
	
	[self.meMapViewController.meMapView setLocation:location animationDuration:0.5];
	
}

- (void) stop
{
	if(!self.isRunning)
		return;
	
	[super stop];
	[self.meMapViewController removeMap:self.name clearCache:NO];
	
	self.isRunning = NO;
}

@end


/////////////////////////////////////////////////////
@implementation MEAnimatedMapTest2

- (id) init
{
	if(self=[super init])
	{
		self.name=@"Animated Test 2";
		self.automaticTileRequestMode = YES;
	}
	return self;
}

- (NSString*) label
{
	return @"";
}

- (void) userTapped
{
	if(self.isRunning)
		[self stop];
	else
		[self start];
}


- (void) togglePlay
{
	NSLog(@"Toggle play");
	self.currentState++;
	
	switch(self.currentState)
	{
			
			//Pause
		case 0:
			[self.btnPlayPause setTitle:@"Play" forState:UIControlStateNormal];
			[self pauseMap];
			break;
			
			//Play
		case 1:
			[self.btnPlayPause setTitle:@"Pause" forState:UIControlStateNormal];
			[self unpauseMap];
			self.currentState = -1;
			break;
			
	}
	
}

- (void) start
{
	if(self.isRunning)
		return;
	
	self.interval = 2.0;
	
	self.currentState = 0;
	
	//self.meMapViewController.maxVirtualMapParentSearchDepth=0;
	[self addMap];
	[self pauseMap];
	
	self.oldDelegate = self.meMapViewController.meMapView.meMapViewDelegate;
	self.meMapViewController.meMapView.meMapViewDelegate = self;
	[self.meMapViewController setAnimatedMapStartFrame:self.name frameNumber:4];
	
	//Add pause / play button.
	self.btnPlayPause = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	[self.btnPlayPause addTarget:self
						  action:@selector(togglePlay)
				forControlEvents:UIControlEventTouchDown];
	[self.btnPlayPause setTitle:@"Play" forState:UIControlStateNormal];
	self.btnPlayPause.frame = CGRectMake(10.0, 250.0, 160.0, 40.0);
	[self.meMapViewController.meMapView addSubview:self.btnPlayPause];
	[self.meMapViewController.meMapView bringSubviewToFront:self.btnPlayPause];
	self.isRunning = YES;
}

- (void) stop
{
	if(!self.isRunning)
		return;
	
	//Remove map
	[self.meMapViewController removeMap:self.name clearCache:YES];
	
	//Remove button
	[self.btnPlayPause removeFromSuperview];
	self.btnPlayPause = nil;
	
	//restore delegate chain
	self.meMapViewController.meMapView.meMapViewDelegate = self.oldDelegate;
	self.oldDelegate = nil;
	
	self.isRunning = NO;
	[self stopTimer];
}


- (void) timerTick
{
}

- (void) mapView:(MEMapView *)mapView animationPausedOnMap:(NSString *)mapName
{
	NSLog(@"animationPausedOnMap: %@", mapName);
	[self stopTimer];
}


- (void) mapView:(MEMapView *)mapView animationWaitingOnMap:(NSString *)mapName
{
	NSLog(@"animationWaitngOnMap: %@", mapName);
	[self stopTimer];
}

- (void) mapView:(MEMapView *)mapView animationFrameChangedOnMap:(NSString *)mapName withFrame:(int)frame
{
	NSLog(@"animationFrameChanged on map %@ frame %d", mapName, frame);
}

@end

/////////////////////////////////////////////////////
@implementation MEAnimatedMapTest3

- (id) init
{
	if(self=[super init])
	{
		self.name=@"Animated Test 3";
		self.automaticTileRequestMode = NO;
	}
	return self;
}

- (void) timerTick
{
	
}

- (void) start
{
	[super start];
	
	//Add politely refresh button
	self.btnRefreshDirtyTiles = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	[self.btnRefreshDirtyTiles addTarget:self
						  action:@selector(triggerTileRequest)
				forControlEvents:UIControlEventTouchDown];
	[self.btnRefreshDirtyTiles setTitle:@"refreshDirtyTiles" forState:UIControlStateNormal];
	self.btnRefreshDirtyTiles.frame = CGRectMake(10.0, 300.0, 160.0, 40.0);
	[self.meMapViewController.meMapView addSubview:self.btnRefreshDirtyTiles];
	[self.meMapViewController.meMapView bringSubviewToFront:self.btnRefreshDirtyTiles];
	self.isRunning = YES;
}

- (void) triggerTileRequest
{
	[self.meMapViewController refreshDirtyTiles:self.name];
}


- (void) stop
{
	if(!self.isRunning)
		return;
	
	//Remove button
	[self.btnRefreshDirtyTiles removeFromSuperview];
	self.btnRefreshDirtyTiles = nil;
	
	[super stop];
}

- (void) pauseMap
{
	[self.meMapViewController pauseAnimatedVirtualMap:self.name];
	[self.meMapViewController setAnimatedVirtualMapFrame:self.name frame:4];
	
}

- (void) unpauseMap
{
	[self.meMapViewController setAutomaticTileRequestModeForAnimatedVirtualMap:self.name enabled:YES];
	[self.meMapViewController playAnimatedVirtualMap:self.name];
}

- (void) mapView:(MEMapView *)mapView animationPlayingOnMap:(NSString *)mapName
{
	NSLog(@"animationPlayingOnMap: %@", mapName);
	[self.meMapViewController setAutomaticTileRequestModeForAnimatedVirtualMap:self.name enabled:NO];
	
}

- (void) mapView:(MEMapView *)mapView animationWaitingOnMap:(NSString *)mapName
{
	NSLog(@"animationWaitngOnMap: %@", mapName);
}

@end


/////////////////////////////////////////////////////
@implementation MEAnimatedMapTest4

- (id) init
{
	if(self=[super init])
	{
		self.name=@"Animated Test 4";
		self.automaticTileRequestMode = NO;
		self.interval =0.4;
	}
	return self;
}

- (void) toggleFailRandomly
{
	self.tileProvider.failRandomly = !self.tileProvider.failRandomly;
	
	if(self.tileProvider.failRandomly)
		[self.btnFailRandomly setTitle:@"Disable Random Fail" forState:UIControlStateNormal];
	else
		[self.btnFailRandomly setTitle:@"Enabled Random Fail" forState:UIControlStateNormal];
			
}

- (void) toggleFailType
{
	self.tileProvider.failWithUIImage = !self.tileProvider.failWithUIImage;
	
	if(self.tileProvider.failWithUIImage)
		[self.btnFailType setTitle:@"Fail w/cachedImage" forState:UIControlStateNormal];
	else
		[self.btnFailType setTitle:@"Fail w/UIImage" forState:UIControlStateNormal];
}

- (void) timerTick
{
	[self.meMapViewController refreshDirtyTiles:self.name];
}

- (void) start
{
	[super start];
	
	[self.meMapViewController addCachedImage:[UIImage imageNamed:@"noData"]
									withName:@"noData"
							 compressTexture:YES];
	
	//Add politely refresh button
	self.btnFailRandomly = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	[self.btnFailRandomly addTarget:self
								action:@selector(toggleFailRandomly)
					  forControlEvents:UIControlEventTouchDown];
	[self.btnFailRandomly setTitle:@"Enabled Random Fail" forState:UIControlStateNormal];
	self.btnFailRandomly.frame = CGRectMake(10.0, 350.0, 160.0, 40.0);
	[self.meMapViewController.meMapView addSubview:self.btnFailRandomly];
	[self.meMapViewController.meMapView bringSubviewToFront:self.btnFailRandomly];
	
	self.btnFailType = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	[self.btnFailType addTarget:self
							 action:@selector(toggleFailType)
				   forControlEvents:UIControlEventTouchDown];
	[self.btnFailType setTitle:@"Fail w/UIImage" forState:UIControlStateNormal];
	self.btnFailType.frame = CGRectMake(10.0, 400.0, 160.0, 40.0);
	[self.meMapViewController.meMapView addSubview:self.btnFailType];
	[self.meMapViewController.meMapView bringSubviewToFront:self.btnFailType];
	
	self.isRunning = YES;
}

- (void) mapView:(MEMapView *)mapView animationPausedOnMap:(NSString *)mapName
{
	NSLog(@"animationPausedOnMap: %@", mapName);
	[self stopTimer];
}


- (void) mapView:(MEMapView *)mapView animationPlayingOnMap:(NSString *)mapName
{
	NSLog(@"animationPlayingOnMap: %@", mapName);
	[self startTimer];
}

- (void) stop
{
	if(!self.isRunning)
		return;
	
	//Remove buttons
	[self.btnFailRandomly removeFromSuperview];
	self.btnFailRandomly = nil;
	
	[self.btnFailType removeFromSuperview];
	self.btnFailType = nil;
	
	[super stop];
}


@end

/////////////////////////////////////////////////////
@implementation MEAnimatedMapTest5

- (id) init
{
	if(self=[super init])
	{
		self.name=@"Animated Test 5";
	}
	return self;
}


- (void) addRegionBounds:(CLLocationCoordinate2D) lowerLeft
			  upperRight:(CLLocationCoordinate2D) upperRight
{
	MEVectorMapInfo* vectorMapInfo = [[[MEVectorMapInfo alloc]init]autorelease];
	vectorMapInfo.name = @"regionBounds";
	vectorMapInfo.zOrder = 999;
	[self.meMapViewController addMapUsingMapInfo:vectorMapInfo];
	
	//Point camera at US
	[self lookAtUnitedStates];
    
    //Create a new polygon style
    MEPolygonStyle* polygonStyle=[[[MEPolygonStyle alloc]init]autorelease];
    polygonStyle.strokeColor = [UIColor greenColor];
    polygonStyle.fillColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.0];
    polygonStyle.strokeWidth = 4;
	
    //Create an array of points for the region
    NSMutableArray* polygonPoints=[[[NSMutableArray alloc]init]autorelease];
    [polygonPoints addObject:[NSValue valueWithCGPoint:CGPointMake(lowerLeft.longitude, lowerLeft.latitude)]];
    [polygonPoints addObject:[NSValue valueWithCGPoint:CGPointMake(upperRight.longitude, lowerLeft.latitude)]];
	[polygonPoints addObject:[NSValue valueWithCGPoint:CGPointMake(upperRight.longitude, upperRight.latitude)]];
    [polygonPoints addObject:[NSValue valueWithCGPoint:CGPointMake(lowerLeft.longitude, upperRight.latitude)]];
    [polygonPoints addObject:[NSValue valueWithCGPoint:CGPointMake(lowerLeft.longitude, lowerLeft.latitude)]];
    
    //Add the polygon to the map
    [self.meMapViewController addPolygonToVectorMap:@"regionBounds"
											 points:polygonPoints
											  style:polygonStyle];
}

- (void) removeRegionBounds
{
	[self.meMapViewController removeMap:@"regionBounds" clearCache:YES];
}


- (void) refreshRegion
{
	[self.tileProvider nextTileSet];
	[self.meMapViewController refreshMapRegion:self.name lowerLeft:US_MIN upperRight:US_MAX];
}

- (void) start
{
	if(self.isRunning)
		return;
	
	[super start];
	
	[self addRegionBounds:US_MIN upperRight:US_MAX];
	
		
	//Add refresh region button
	self.btnRefreshRegion = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	[self.btnRefreshRegion addTarget:self
							 action:@selector(refreshRegion)
				   forControlEvents:UIControlEventTouchDown];
	[self.btnRefreshRegion setTitle:@"Refresh Region" forState:UIControlStateNormal];
	self.btnRefreshRegion.frame = CGRectMake(10.0, 450.0, 160.0, 40.0);
	[self.meMapViewController.meMapView addSubview:self.btnRefreshRegion];
	[self.meMapViewController.meMapView bringSubviewToFront:self.btnRefreshRegion];
	
	
	self.isRunning = YES;
}


- (void) stop
{
	if(!self.isRunning)
		return;
	
	[self removeRegionBounds];
	
	//Remove buttons
	[self.btnRefreshRegion removeFromSuperview];
	self.btnRefreshRegion = nil;
	
	[super stop];
}


@end






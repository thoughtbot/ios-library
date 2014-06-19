//
//  KCSAppDelegate.m
//  KitTest
//
//  Created by Brian Wilson on 11/14/11.
//  Copyright (c) 2011-2013 Kinvey. All rights reserved.
//

#import "KCSAppDelegate.h"

#import "KCSViewController.h"
#import "ImageViewController.h"
#import "CachingViewController.h"
#import "RootViewController.h"
#import "LinkedResourceViewController.h"
#import "UserDiscoveryViewController.h"
#import "KinveyRefViewController.h"

#import <KinveyKit/KinveyKit.h>

@implementation KCSAppDelegate

- (void)dealloc
{
    [_window release];
    [_viewController release];
    [_imageViewController release];
    [_rootViewController release];
    [_kinvey release];
    [super dealloc];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    // Override point for customization after application launch.
    self.viewController = [[[KCSViewController alloc] initWithNibName:@"KCSViewController" bundle:nil] autorelease];
    self.imageViewController = [[[ImageViewController alloc] initWithNibName:@"ImageView" bundle:nil] autorelease];
    self.rootViewController = [[[RootViewController alloc] initWithNibName:@"RootViewController" bundle:nil] autorelease];
    
    self.rootViewController.viewControllers = [NSArray arrayWithObjects:self.viewController, nil];
    
    CachingViewController* cachingView = [[[CachingViewController alloc] initWithNibName:@"CachingViewController" bundle:nil] autorelease];
    LinkedResourceViewController* linkedView = [[[LinkedResourceViewController alloc] initWithNibName:@"LinkedResourceViewController" bundle:nil] autorelease];
    
    UserDiscoveryViewController* userDiscView = [[[UserDiscoveryViewController alloc] initWithNibName:@"UserDiscoveryViewController" bundle:nil] autorelease];

    KinveyRefViewController* refView = [[[KinveyRefViewController alloc] initWithNibName:@"KinveyRefViewController" bundle:nil] autorelease];
    
    UITabBarController* tabBarController = [[[UITabBarController alloc] init] autorelease];
    tabBarController.viewControllers = @[self.viewController, self.imageViewController, cachingView, linkedView, userDiscView, refView];

    self.window.rootViewController = tabBarController;
    
    // Add our primary as a subview of the rootViewController.
   // [self.rootViewController.view insertSubview:self.viewController.view atIndex:0];
    
    ///////////////////////////
    // START OF KINVEY CODE
    //////////////////////////

/* PRODUCTION
    (void) [[KCSClient sharedClient] initializeKinveyServiceForAppKey:@"kid_TTO8REn0-M"
                                                        withAppSecret:@"a52ba04eb3dc4aa9b344790082ea6e01"
                                                         usingOptions:nil];
*/
/* DEVELOPMENT */
//    (void) [[KCSClient sharedClient] initializeKinveyServiceForAppKey:@"kid_eTqjiEjZ-f"
//                                                        withAppSecret:@"63e0ec61b05e44489685f1e696a90233"
//                                                         usingOptions:nil];
    (void) [[KCSClient sharedClient] initializeKinveyServiceForAppKey:@"kid_eeDgeL5lAJ"
                                                        withAppSecret:@"ad6e3a563f394d3ea56672764b0be936"
                                                         usingOptions:nil];
    [KCSClient sharedClient].configuration.serviceHostname = @"v3yk1n";
/**/
    
    
    self.viewController.rootViewController = _rootViewController;
    self.imageViewController.rootViewController = _rootViewController;

    self.rootViewController.imageViewController = _imageViewController;
    self.rootViewController.viewController = _viewController;
    
    [KCSClient configureLoggingWithNetworkEnabled:YES
                                     debugEnabled:YES
                                     traceEnabled:YES 
                                   warningEnabled:YES
                                     errorEnabled:YES];

    [self.viewController prepareDataForView];
    ///////////////////////////
    // END OF KINVEY CODE
    //////////////////////////
    
    [self.window makeKeyAndVisible];
    
    
    [KCSPing pingKinveyWithBlock:^(KCSPingResult *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *title;
            if (result.pingWasSuccessful){
                title = @"Kinvey Ping Success :)";
            } else {
                title = @"Kinvey Ping Failed :(";
            }
            
            NSLog(@"%@", result.description);
            
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle: title
                                                            message: [result description]
                                                           delegate: nil
                                                  cancelButtonTitle: @"OK"
                                                  otherButtonTitles: nil];
            [alert show];
            [alert release];
        });
    }];
    /*
    if ([KCSUser activeUser] == nil) {
        [KCSUser createAutogeneratedUser:^(KCSUser *user, NSError *errorOrNil, KCSUserActionResult result) {
            [KCSPush registerForPush];
        }];
    } else {
        [KCSPush registerForPush];
    }*/
    
    [KCSUser loginWithSocialIdentity:KCSSocialIDKinvey accessDictionary:@{@"access_token":@"6c9e779f371d0cc18926aee2151eea818196d46a"} withCompletionBlock:^(KCSUser *user, NSError *errorOrNil, KCSUserActionResult result) {
        NSLog(@"error: %@", errorOrNil);
    }];
    
    return YES;

}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    [[KCSPush sharedPush] application:application didReceiveRemoteNotification:userInfo];
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    NSLog(@"Device Token: %@", deviceToken);
    [[KCSPush sharedPush] application:application didRegisterForRemoteNotificationsWithDeviceToken:deviceToken completionBlock:^(BOOL success, NSError *error) {
        
    }];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    NSLog(@"Error: %@", error);
}


- (void)applicationWillResignActive:(UIApplication *)application
{
    /*
     Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
     Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
     */
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    /*
     Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
     If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
     */
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    /*
     Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
     */
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    /*
     Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
     */
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    [[KCSPush sharedPush] onUnloadHelper];
    /*
     Called when the application is about to terminate.
     Save data if appropriate.
     See also applicationDidEnterBackground:.
     */
}


- (void)entity:(id)entity operationDidCompleteWithResult:(NSObject *)result
{
    NSLog(@"result %@", result);
}

- (void)entity:(id)entity operationDidFailWithError:(NSError *)error
{
    NSLog(@"%@",error);
}
@end

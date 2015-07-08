//
//  KCSMICViewController.h
//  KinveyKit
//
//  Created by Victor Barros on 2015-06-16.
//  Copyright (c) 2015 Kinvey. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "KinveyUser.h"

@interface KCSMICLoginViewController : UIViewController

-(instancetype)initWithRedirectURI:(NSString*)redirectURI
               withCompletionBlock:(KCSUserCompletionBlock)completionBlock;

-(instancetype)initWithRedirectURI:(NSString*)redirectURI
                           timeout:(NSTimeInterval)timeout
               withCompletionBlock:(KCSUserCompletionBlock)completionBlock;

@end
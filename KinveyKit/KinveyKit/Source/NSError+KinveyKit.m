//
//  NSError+KinveyKit.m
//  KinveyKit
//
//  Created by Michael Katz on 8/23/13.
//  Copyright (c) 2013 Kinvey. All rights reserved.
//
// This software is licensed to you under the Kinvey terms of service located at
// http://www.kinvey.com/terms-of-use. By downloading, accessing and/or using this
// software, you hereby accept such terms of service  (and any agreement referenced
// therein) and agree that you have read, understand and agree to be bound by such
// terms of service and are of legal age to agree to such terms with Kinvey.
//
// This software contains valuable confidential and proprietary information of
// KINVEY, INC and is subject to applicable licensing agreements.
// Unauthorized reproduction, transmission or distribution of this file and its
// contents is a violation of applicable laws.
//

#import "NSError+KinveyKit.h"

#import "KinveyCoreInternal.h"

@implementation NSError (KinveyKit)

+ (NSMutableDictionary*) commonErrorInfo
{
    return [@{@"KinveyKit.Version"        : __KINVEYKIT_VERSION__,
              @"KinveyKit.Platform"       : [KCSPlatformUtils platformString],
              @"KinveyKit.SupportMessage" : @"Copy and paste this whole error info along with other pertinent information when contacting support@kinvey.com"
            } mutableCopy];
}

+ (instancetype) createKCSError:(NSString*)domain code:(NSInteger)code userInfo:(NSDictionary*)userInfo;
{
    NSMutableDictionary* updatedInfo = [self commonErrorInfo];
    if (userInfo) {
        [updatedInfo addEntriesFromDictionary:userInfo];
    }
    
    return [NSError errorWithDomain:domain code:code userInfo:userInfo];
}

@end
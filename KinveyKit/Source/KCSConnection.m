//
//  KCSConnection.m
//  KinveyKit
//
//  Created by Brian Wilson on 11/23/11.
//  Copyright (c) 2011 Kinvey. All rights reserved.
//

#import "KCSConnection.h"

@implementation KCSConnection

- (id)initWithCredentials:(NSURLCredential *)credentials
{
    return nil; // Unsupported base-class constructor
}

- (id)initWithUsername:(NSString *)username password:(NSString *)password
{
    return nil; // Unsupported base-class constructor
}

- (id)initWithConnection:(NSURLConnection *)theConnection
{
    return nil; // Unsupported base-class constructor
}

- (void)performRequest:(NSURLRequest *)theRequest
         progressBlock:(KCSConnectionProgressBlock)onProgress
       completionBlock:(KCSConnectionCompletionBlock)onCompletion
          failureBlock:(KCSConnectionFailureBlock)onFailure
      usingCredentials:(NSURLCredential *)credentials
{
    NSException* myException = [NSException
                                exceptionWithName:@"UnsupportedAbstractBaseClassUse"
                                reason:@"This method is only implemented in subclasses..."
                                userInfo:nil];
    
    @throw myException;

}


@end
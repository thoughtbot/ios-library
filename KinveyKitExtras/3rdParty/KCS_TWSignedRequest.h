//
//    KCS_TWSignedRequest.h
//
//    Copyright (c) 2012 Sean Cook
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to
//    deal in the Software without restriction, including without limitation the
//    rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//    sell copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in
//    all copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//    IN THE SOFTWARE.
//

//  Modified 2012, Kinvey Inc

#import <Foundation/Foundation.h>
#import "KCSGenericRestRequest.h"

typedef void(^KCS_TWSignedRequestHandler)(NSData *data, NSURLResponse *response, NSError *error);

@interface KCS_TWSignedRequest : NSObject

@property (nonatomic, copy) NSString *authToken;
@property (nonatomic, copy) NSString *authTokenSecret;

// Creates a new request 
- (id)initWithURL:(NSURL *)url parameters:(NSDictionary *)parameters requestMethod:(KCSRESTMethod)requestMethod;

// Perform the request, and notify handler of results
- (void)performRequestWithHandler:(KCS_TWSignedRequestHandler)handler;

@end

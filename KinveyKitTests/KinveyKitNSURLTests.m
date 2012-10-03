//
//  KinveyKitNSURLTests.m
//  KinveyKit
//
//  Created by Brian Wilson on 1/5/12.
//  Copyright (c) 2012 Kinvey. All rights reserved.
//

#import "KinveyKitNSURLTests.h"
#import "NSURL+KinveyAdditions.h"

@implementation KinveyKitNSURLTests

- (void)testURLByAppendingQueryString
{
    // Test empty String + empty string
    NSURL *emptyURL = [NSURL URLWithString:@""];
    STAssertEqualObjects([emptyURL URLByAppendingQueryString:@""], emptyURL, @"");
    
    
    // Test empty string + value
    NSURL *testURL = [NSURL URLWithString:@"?value"];
    STAssertEqualObjects([emptyURL URLByAppendingQueryString:@"value"], testURL, @"");
    
    // Test Value + empty string
    testURL = [NSURL URLWithString:@"http://www.kinvey.com/"];
    STAssertEqualObjects([testURL URLByAppendingQueryString:@""], testURL, @"");

    // Test nil
    STAssertEqualObjects([testURL URLByAppendingQueryString:nil], testURL, @"");

    // Test simple query
    NSURL *rootURL = [NSURL URLWithString:@"http://www.kinvey.com/"];
    testURL = [NSURL URLWithString:@"http://www.kinvey.com/?test"];
    STAssertEqualObjects([rootURL URLByAppendingQueryString:@"test"], testURL, @"");
    
    // Test double append
    testURL = [NSURL URLWithString:@"http://www.kinvey.com/?one=1&two=2"];    
    STAssertEqualObjects([[rootURL URLByAppendingQueryString:@"one=1"] URLByAppendingQueryString:@"two=2"], testURL, @"");
}

- (void)testURLWithUnencodedString
{
    NSString *unEncoded = @"!#$&'()*+,/:;=?@[]{} %";
    NSString *encoded = @"%21%23%24%26%27%28%29%2A%2B%2C%2F%3A%3B%3D%3F%40%5B%5D%7B%7D%20%25";

    NSURL *one = [NSURL URLWithString:encoded];
    NSURL *two = [NSURL URLWithUnencodedString:unEncoded];
    
    STAssertEqualObjects(two, one, @"");
}
@end

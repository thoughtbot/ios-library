//
//  KCSLoadObjectTest.m
//  KinveyKit
//
//  Created by Victor Barros on 2015-10-28.
//  Copyright © 2015 Kinvey. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "Event.h"
#import "KCSTestCase.h"

@interface KCSLoadObjectTest : KCSTestCase

@end

@implementation KCSLoadObjectTest

- (void)setUp {
    [super setUp];
    
    [self setupKCS];
    [self createAutogeneratedUser];
}

- (void)tearDown {
    [self removeAndLogoutActiveUser:30];
    
    [super tearDown];
}

- (void)testSaveLoad
{
    __block NSString* objectId = nil;
    
    {
        __weak __block XCTestExpectation* expectationSave = [self expectationWithDescription:@"save"];
        
        KCSCollection* collection = [KCSCollection collectionFromString:@"Event" ofClass:[Event class]];
        KCSBackgroundAppdataStore* store = [KCSBackgroundAppdataStore storeWithCollection:collection options:nil];
        
        Event* event = [[Event alloc] init];
        event.name = @"Event 1";
        
        [store saveObject:event
      withCompletionBlock:^(NSArray<Event*> *objectsOrNil, NSError *errorOrNil)
        {
            XCTAssertNotNil(objectsOrNil);
            XCTAssertNil(errorOrNil);
            XCTAssertEqual(objectsOrNil.firstObject, event);
            XCTAssertNotNil(event.entityId);
            
            objectId = event.entityId;
            
            [expectationSave fulfill];
        }
        withProgressBlock:nil];
        
        [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
            expectationSave = nil;
        }];
    }
    
    {
        __weak __block XCTestExpectation* expectationLoad = [self expectationWithDescription:@"load"];
        
        KCSCollection* collection = [KCSCollection collectionFromString:@"Event" ofClass:[Event class]];
        KCSBackgroundAppdataStore* store = [KCSBackgroundAppdataStore storeWithCollection:collection options:nil];
        
        Event* event = [[Event alloc] init];
        event.entityId = objectId;
        
        [store loadObjectWithID:event
            withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil)
        {
            XCTAssertNotNil(objectsOrNil);
            XCTAssertNil(errorOrNil);
            XCTAssertEqual(objectsOrNil.firstObject, event);
            XCTAssertNotNil(event.name);
            XCTAssertEqualObjects(event.name, @"Event 1");
            
            [expectationLoad fulfill];
        } withProgressBlock:nil];
        
        [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
            expectationLoad = nil;
        }];
    }
}

@end

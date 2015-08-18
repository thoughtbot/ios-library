//
//  KCSCachedStoreSwiftTests.swift
//  KinveyKit
//
//  Created by Victor Barros on 2015-08-10.
//  Copyright (c) 2015 Kinvey. All rights reserved.
//

import UIKit
import XCTest

class KCSCachedStoreSwiftTests: KCSTestCase {

    var LogbookStore: KCSCachedStore!
    
    override func setUp() {
        super.setUp()
        
        KCSUser.activeUser()?.logout()
        
        KCSClient.sharedClient().initializeKinveyServiceForAppKey(
            "kid_-1WAs8Rh2",
            withAppSecret: "2f355bfaa8cb4f7299e914e8e85d8c98",
            usingOptions: nil
        )
        
        LogbookStore = KCSCachedStore.storeWithOptions([
            KCSStoreKeyCollectionName : "entries",
            KCSStoreKeyCollectionTemplateClass : NSMutableDictionary.self,
            //            KCSStoreKeyCollectionTemplateClass : Entry.self,
            KCSStoreKeyCachePolicy : KCSCachePolicy.NetworkFirst.rawValue,
            KCSStoreKeyOfflineUpdateEnabled : true
        ])
        
        weak var expectationLogin = expectationWithDescription("login")
        
        KCSUser.createAutogeneratedUser(
            nil,
            completion: { (user: KCSUser!, error: NSError!, actionResult: KCSUserActionResult) -> Void in
                XCTAssertNotNil(user)
                XCTAssertNil(error)
                
                expectationLogin?.fulfill()
            }
        )
        
        waitForExpectationsWithTimeout(30, handler: { (error: NSError!) -> Void in
            expectationLogin = nil
        })
    }
    
    override func tearDown() {
        KCSUser.activeUser()?.logout()
        
        super.tearDown()
    }
    
    func save(identifier: String) {
        weak var expectationSave = expectationWithDescription("save")
        
        var dispatched = false
        
        LogbookStore.saveObject(
            [ "identifier" : identifier ],
            withCompletionBlock: { (results: [AnyObject]!, error: NSError!) -> Void in
                XCTAssertNotNil(results)
                XCTAssertNil(error)
                
                XCTAssertTrue(dispatched)
                
                XCTAssertTrue(NSThread.isMainThread())
                
                expectationSave?.fulfill()
            },
            withProgressBlock: nil
        )
        
        dispatched = true
        
        waitForExpectationsWithTimeout(30, handler: nil)
    }
    
    func testSave() {
        save(NSUUID().UUIDString)
    }
    
    func testQuery() {
        weak var expectationQuery = expectationWithDescription("query")
        
        LogbookStore.queryWithQuery(
            KCSQuery(),
            withCompletionBlock: { (results: [AnyObject]!, error: NSError!) -> Void in
                XCTAssertNotNil(results)
                XCTAssertNil(error)
                
                XCTAssertTrue(NSThread.isMainThread())
                
                expectationQuery?.fulfill()
            },
            withProgressBlock: nil,
            cachePolicy: KCSCachePolicy.LocalFirst
        )
        
        waitForExpectationsWithTimeout(30, handler: nil)
    }
    
    func testRemove() {
        let identifier = NSUUID().UUIDString
        
        save(identifier)
        
        weak var expectationRemove = expectationWithDescription("remove")
        
        var dispatched = false
        
        LogbookStore.removeObject(
            KCSQuery(onField: "identifier", withExactMatchForValue: identifier),
            withCompletionBlock: { (count: UInt, error: NSError!) -> Void in
                XCTAssertNil(error)
                
                XCTAssertTrue(dispatched)
                
                XCTAssertTrue(NSThread.isMainThread())
                
                expectationRemove?.fulfill()
            },
            withProgressBlock: nil
        )
        
        dispatched = true
        
        waitForExpectationsWithTimeout(30, handler: nil)
    }
    
    func testCount() {
        weak var expectationCount = expectationWithDescription("count")
        
        LogbookStore.countWithBlock { (count: UInt, error: NSError!) -> Void in
            XCTAssertNil(error)
            
            XCTAssertTrue(NSThread.isMainThread())
            
            expectationCount?.fulfill()
        }
        
        waitForExpectationsWithTimeout(30, handler: nil)
    }
    
    func testCountWithQuery() {
        weak var expectationCount = expectationWithDescription("count")
        
        var dispatched = false
        
        LogbookStore.countWithQuery(
            KCSQuery(),
            completion: { (count: UInt, error: NSError!) -> Void in
                XCTAssertNil(error)
                
                XCTAssertTrue(dispatched)
                
                XCTAssertTrue(NSThread.isMainThread())
                
                expectationCount?.fulfill()
            }
        )
        
        dispatched = true
        
        waitForExpectationsWithTimeout(30, handler: nil)
    }

}

//
//  MLIBZ_290_Tests.swift
//  KinveyKit
//
//  Created by Victor Barros on 2015-05-08.
//  Copyright (c) 2015 Kinvey. All rights reserved.
//

import XCTest

class MLIBZ_290_Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        
        KCSClient.sharedClient().initializeKinveyServiceForAppKey(
            "kid_-1WAs8Rh2",
            withAppSecret: "2f355bfaa8cb4f7299e914e8e85d8c98",
            usingOptions: nil
        )
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func test() {
        let expectationLogin = expectationWithDescription("login")
        
        KCSUser.createAutogeneratedUser(
            nil,
            completion: { (user: KCSUser!, error: NSError!, actionResult: KCSUserActionResult) -> Void in
                expectationLogin.fulfill()
            }
        )
        
        waitForExpectationsWithTimeout(30, handler: nil)
        
        class OfflineUpdateDelegate : NSObject, KCSOfflineUpdateDelegate {
            
            func shouldDeleteObject(objectId: String!, inCollection collectionName: String!, lastAttemptedDeleteTime time: NSDate!) -> Bool {
                return true
            }
            
            func shouldEnqueueObject(objectId: String!, inCollection collectionName: String!, onError error: NSError!) -> Bool {
                return true
            }
            
            func shouldSaveObject(objectId: String!, inCollection collectionName: String!, lastAttemptedSaveTime saveTime: NSDate!) -> Bool {
                return true
            }
            
            func didSaveObject(objectId: String!, inCollection collectionName: String!) {
                expectationLogin.fulfill()
            }
            
        }
        
        let delegate = OfflineUpdateDelegate()
        KCSClient.sharedClient().setOfflineDelegate(delegate)
        
        let store = KCSCachedStore.storeWithOptions([
            KCSStoreKeyCollectionName : "city",
            KCSStoreKeyCollectionTemplateClass : City.self,
            KCSStoreKeyCachePolicy : KCSCachePolicy.None.rawValue,
            KCSStoreKeyOfflineUpdateEnabled : true
        ])
        
        class MockURLProtocol : NSURLProtocol {
            
            static var putRequests: [NSURLRequest] = []
            static var postRequests: [NSURLRequest] = []
            
            override class func canInitWithRequest(request: NSURLRequest) -> Bool {
                NSLog("%@ %@", request.HTTPMethod!, request.URL!)
                if request.HTTPMethod == "PUT" {
                    putRequests.append(request)
                } else if request.HTTPMethod == "POST" {
                    postRequests.append(request)
                }
                return request.HTTPMethod == "POST"
            }
            
            override class func canonicalRequestForRequest(request: NSURLRequest) -> NSURLRequest {
                if (request.URL!.lastPathComponent!.hasPrefix("temp_")) {
                    let mutableRequest = request.mutableCopy() as! NSMutableURLRequest
                    if let stream = request.HTTPBodyStream {
                        stream.open()
                        
                        let data = NSMutableData()
                        var buffer = [UInt8](count: 4096, repeatedValue: 0)
                        var read = 0
                        while (stream.hasBytesAvailable) {
                            read = stream.read(&buffer, maxLength: 4096)
                            data.appendBytes(buffer, length: read)
                        }
                        
                        stream.close()
                        
                        mutableRequest.HTTPBodyStream = nil
                        mutableRequest.HTTPBody = data
                        
                        let object = NSJSONSerialization.JSONObjectWithData(
                            data,
                            options: NSJSONReadingOptions.allZeros,
                            error: nil
                        ) as! NSDictionary
                        
                        XCTAssertNil(object[KCSEntityKeyId])
                    }
                    return mutableRequest
                }
                return request
            }
            
            private override func startLoading() {
                let error = NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorNotConnectedToInternet,
                    userInfo: [
                        NSLocalizedDescriptionKey : "The connection failed because the device is not connected to the internet."
                    ]
                )
                client!.URLProtocol(self, didFailWithError: error)
            }
            
        }
        
        KCSURLProtocol.registerClass(MockURLProtocol.self)
        
        let expectationSave = expectationWithDescription("save")
        
        store.saveObject(
            City(name: "Boston"),
            withCompletionBlock: { (results: [AnyObject]!, error: NSError!) -> Void in
                dispatch_after(
                    dispatch_time(DISPATCH_TIME_NOW, Int64(60 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(),
                    { () -> Void in
                        expectationSave.fulfill()
                    }
                )
            },
            withProgressBlock: nil
        )
        
        waitForExpectationsWithTimeout(3600, handler: { (error: NSError!) -> Void in
            KCSURLProtocol.unregisterClass(MockURLProtocol.self)
        })
        
        XCTAssertEqual(MockURLProtocol.putRequests.count, 0)
        XCTAssertGreaterThan(MockURLProtocol.postRequests.count, 10)
    }

}
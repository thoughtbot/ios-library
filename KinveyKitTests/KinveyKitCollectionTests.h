//
//  KinveyKitCollectionTests.h
//  KinveyKit
//
//  Created by Brian Wilson on 12/19/11.
//  Copyright (c) 2011 Kinvey. All rights reserved.
//

//  Logic unit tests contain unit test code that is designed to be linked into an independent test executable.
//  See Also: http://developer.apple.com/iphone/library/documentation/Xcode/Conceptual/iphone_development/135-Unit_Testing_Applications/unit_testing_applications.html

#import <SenTestingKit/SenTestingKit.h>
#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>
#import "KinveyCollection.h"

@interface KinveyKitCollectionTests : SenTestCase <KCSCollectionDelegate, KCSInformationDelegate>


@end
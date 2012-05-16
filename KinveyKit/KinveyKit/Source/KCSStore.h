//
//  KCSStore.h
//  KinveyKit
//
//  Created by Brian Wilson on 4/30/12.
//  Copyright (c) 2012 Kinvey. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KCSBlockDefs.h"

// Forward decl
@class KCSAuthHandler;


@interface KCSAllObjects : NSObject
@end

/**
 KCSStore options dictionary key for the backing resource
 */
#define kKCSStoreKeyResource @"resource"


/*! Kinvey Store Protocol
 
 A Kinvey Store is a representation of a group of backend items,
 stores have several operations in common to all stores:
 
 - Add an object/s (save* methods)
 - Update an object/s (save* methods)
 - Get an object/s (query* methods)
 - Remove an object/s (remove* methods)
 - Configure the store (configure* methods)
 
 Additionally, stores may have store specific methods that are documented
 in the Store itself.  You should be able to use the documentation in
 KCSStore to understand how to accomplish all basic tasks in Stores without
 needing to refer to the specific stores implementation, but you should
 refer to that implementation to maximize performance or to configure
 store specific items prior to your app's release.
 
 */
@protocol KCSStore <NSObject>

#pragma mark -
#pragma mark Initialization
///---------------------------------------------------------------------------------------
/// @name Initialization
///---------------------------------------------------------------------------------------
/*! Initialize an empty Kinvey Store with the default options
 
 This routine is called to return an empty store with default options and default authentication.
 
 @return An autoreleased empty store with default options and default authentication.
 
 */
+ (id)store;

/*! Initialize an empty store with the given options and the default authentication
 
 This will initialize an empty store with the given options and default authentication,
 the given options dictionary should be defined by the Kinvey Store that's implementing
 the protocol.
 
 @param options A dictionary of options to configure the store.
 
 @return An autoreleased empty store with configured options and default authentication.
 
 */
+ (id)storeWithOptions: (NSDictionary *)options;

/*! Initialize an empty store with the given options and the given authentication
 
 This will initialize an empty store with the given options and given authentication,
 the options dictionary should be defined by the Kinvey Store that's implementing
 the protocol.  Authentication is Kinvey Store specific, refer to specific store's
 documentation for details.
 
 @param options A dictionary of options to configure the store.
 @param authHandler The Kinvey Authentication Handler used to authenticate backend requests.
 
 @return An autoreleased empty store with configured options and given authentication.
 
 */
+ (id)storeWithAuthHandler: (KCSAuthHandler *)authHandler withOptions: (NSDictionary *)options;

#pragma mark -
#pragma mark Adding/Updating
///---------------------------------------------------------------------------------------
/// @name Adding/Updating
///---------------------------------------------------------------------------------------
/*! Add or update an object (or objects) in the store.
 
 This is the basic method to add or update objects in a Kinvey Store.  Specific stores may
 have specific requirements on objects that are added to the store.  This will result in the
 completion callback being called informing you of an error.
 
 @param object An object to add/update in the store (if the object is an NSArray, all objects will be added/updated)
 @param completionBlock A block that gets invoked when the addition/update is "complete" (as defined by the store)
 @param progressBlock A block that is invoked whenever the store can offer an update on the progress of the operation.
 
 */
- (void)saveObject: (id)object withCompletionBlock: (KCSCompletionBlock)completionBlock withProgressBlock: (KCSProgressBlock)progressBlock;

#pragma mark -
#pragma mark Querying/Fetching
///---------------------------------------------------------------------------------------
/// @name Querying/Fetching
///---------------------------------------------------------------------------------------
/*! Query or fetch an object (or objects) in the store.
 
 This method takes a query object and calls the 
 
 @param query A query to act on a store.  The store defines the type of queries it accepts, an object of type "KCSAllObjects" causes all objects to be returned.
 @param completionBlock A block that gets invoked when the query/fetch is "complete" (as defined by the store)
 @param progressBlock A block that is invoked whenever the store can offer an update on the progress of the operation.
 
 */

- (void)queryWithQuery: (id)query withCompletionBlock: (KCSCompletionBlock)completionBlock withProgressBlock: (KCSProgressBlock)progressBlock;

#pragma mark -
#pragma mark Removing
///---------------------------------------------------------------------------------------
/// @name Removing
///---------------------------------------------------------------------------------------
/*! Add or update an object (or objects) in the store.
 
 <#Discussion#>
 
 @param object An object (or query) to remove from the store (if the object is an NSArray or query, matching objects will be removed)
 @param completionBlock A block that gets invoked when the remove is "complete" (as defined by the store)
 @param progressBlock A block that is invoked whenever the store can offer an update on the progress of the operation.
 
 */

- (void)removeObject: (id)object withCompletionBlock: (KCSCompletionBlock)completionBlock withProgressBlock: (KCSProgressBlock)progressBlock;

#pragma mark -
#pragma mark Information
- (void)countWithBlock: (KCSCountBlock)countBlock;


#pragma mark -
#pragma mark Configuring
///---------------------------------------------------------------------------------------
/// @name Configuring
///---------------------------------------------------------------------------------------
/*! This is the general configuration routine for a Kinvey Store
 
 This routine is used to pass a Store specific options dictionary to the store
 allow the user to configure store specific items in a way that's compatible with multiple
 stores.
 
 All stores are expected to handle the following options (however they're allowed to interpret
 the values in a store specific manner):
 
 - backend -- The backend represented by this store
 - debug   -- Should debugging be enabled for this store
 
 @param options A dictionary containing store specific options, see store documentation for details
 
 @return A BOOL value indicating whether the options were accepted by the store.
 
 */
- (BOOL)configureWithOptions: (NSDictionary *)options;

#pragma mark -
#pragma mark Authentication
///---------------------------------------------------------------------------------------
/// @name Authentication
///---------------------------------------------------------------------------------------


/*! Set the Kinvey Auth Handler for this store
 
 This method is used to control how the store authenticates with the backend.
 
 @param handler The Kinvey Auth Handler to be used during requests.
 
 */
- (void)setAuthHandler: (KCSAuthHandler *)handler;

/*! Get the currently set Kinvey Auth Handler for this Store
 
 This method is used to find the currently set Kinvey Auth Handler for this Store.
 
 @return The currently set Kinvey Auth Handler.
 
 */
- (KCSAuthHandler *)authHandler;


@end

//
//  KCSBackgroundAppdataStore.m
//  KinveyKit
//
//  Created by Michael Katz on 1/9/14.
//  Copyright (c) 2014 Kinvey. All rights reserved.
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


#import "KCSBackgroundAppdataStore.h"

#import "KCSAppdataStore.h"

#import "KCS_SBJson.h"
#import "KCSLogManager.h"
#import "KinveyErrorCodes.h"
#import "KCSErrorUtilities.h"
#import "NSArray+KinveyAdditions.h"
#import "KCSObjectMapper.h"
#import "KCSHiddenMethods.h"
#import "KCSSaveGraph.h"
#import "KCSObjectCache.h"
#import "KCSRequest2.h"
#import "NSError+KinveyKit.h"
#import "KCSClient+KinveyDataStore.h"
#import "KinveyDataStore.h"
#import "KCSNetworkResponse.h"
#import "KCSNetworkOperation.h"

#import "KCSCachedStore.h"
#import "KCSAppdataStore.h"
#import "KCSDataModel.h"

#define KCSSTORE_VALIDATE_PRECONDITION BOOL okayToProceed = [self validatePreconditionsAndSendErrorTo:completionBlock]; \
if (okayToProceed == NO) { \
return; \
}

#define KCS_OBJECT_LIMIT 10000

@interface KCSBackgroundAppdataStore () {
    KCSSaveGraph* _previousProgress;
    NSString* _title;
}

@property (nonatomic) BOOL treatSingleFailureAsGroupFailure;
@property (nonatomic) BOOL offlineUpdateEnabled;
@property (nonatomic, readwrite) KCSCachePolicy cachePolicy;
@property (nonatomic, strong) KCSCollection *backingCollection;

- (id) manufactureNewObject:(NSDictionary*)jsonDict resourcesOrNil:(NSMutableDictionary*)resources;

@end

@interface KCSPartialDataParser : NSObject <KCS_SBJsonStreamParserAdapterDelegate>
@property (nonatomic, strong) KCS_SBJsonStreamParser* parser;
@property (nonatomic, strong) KCS_SBJsonStreamParserAdapter* adapter;
@property (nonatomic, strong) NSMutableArray* items;
@property (nonatomic, strong) id objectMaker;
@end

@implementation KCSPartialDataParser

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.parser = [[KCS_SBJsonStreamParser alloc] init];
        self.adapter = [[KCS_SBJsonStreamParserAdapter alloc] init];
        _adapter.delegate = self;
        _adapter.levelsToSkip = 2;
        _parser.delegate = _adapter;
        
        self.items = [NSMutableArray array];
    }
    return self;
}

- (NSArray*) parseData:(NSData*)data hasArray:(BOOL)hasArray
{
    _adapter.levelsToSkip = hasArray ? 2 : 1;
    KCS_SBJsonStreamParserStatus status = [_parser parse:data];
    if (status == SBJsonStreamParserError) {
        KCSLogError(@"Error parsing partial progress reults: %@", _parser.error);
	} else if (status == SBJsonStreamParserWaitingForData) {
        KCSLogTrace(@"Parsed partial progress results. Item count %d", _items.count);
	} else if (status == SBJsonStreamParserComplete) {
        KCSLogTrace(@"complete");
    }
    return [_items copy];
}

- (void)parser:(KCS_SBJsonStreamParser *)parser foundArray:(NSArray *)array
{
    DBAssert(true, @"not expecting an array here");
}

- (void)parser:(KCS_SBJsonStreamParser *)parser foundObject:(NSDictionary *)dict {
    id obj = [self.objectMaker manufactureNewObject:dict resourcesOrNil:nil];
    [_items addObject:obj];
}

@end

@implementation KCSBackgroundAppdataStore

#pragma mark - Initialization

- (instancetype)init
{
    return [self initWithAuth:nil];
}

- (instancetype)initWithAuth: (KCSAuthHandler *)auth
{
    self = [super init];
    if (self) {
        _treatSingleFailureAsGroupFailure = YES;
        _cachePolicy = [KCSCachedStore defaultCachePolicy];
        _title = nil;
    }
    return self;
}

+ (instancetype)store
{
    return [self storeWithOptions:nil];
}

+ (instancetype) storeWithOptions: (NSDictionary *)options
{
    return  [self storeWithCollection:nil options:options];
}

+ (instancetype) storeWithAuthHandler: (KCSAuthHandler *)authHandler withOptions: (NSDictionary *)options
{
    return [self storeWithCollection:nil options:options];
}

+ (instancetype) storeWithCollection:(KCSCollection*)collection options:(NSDictionary*)options
{
    
    if (options == nil) {
        options = @{ KCSStoreKeyResource : collection };
    } else {
        options = [NSMutableDictionary dictionaryWithDictionary:options];
        if (collection) {
            [options setValue:collection forKey:KCSStoreKeyResource];
        }
    }
    KCSAppdataStore* store = [[self alloc] init];
    [store configureWithOptions:options];
    return store;
}

+ (instancetype) storeWithCollection:(KCSCollection*)collection authHandler:(KCSAuthHandler *)authHandler withOptions: (NSDictionary *)options
{
    return [self storeWithCollection:collection options:options];
}

- (BOOL)configureWithOptions: (NSDictionary *)options
{
    ifNil(options, @{});
    // Configure
    KCSCollection* collection = [options objectForKey:KCSStoreKeyResource];
    if (collection == nil) {
        NSString* collectionName = [options objectForKey:KCSStoreKeyCollectionName];
        if (collectionName != nil) {
            Class objectClass = [options objectForKey:KCSStoreKeyCollectionTemplateClass];
            if (objectClass == nil) {
                objectClass = [NSMutableDictionary class];
            }
            collection = [KCSCollection collectionFromString:collectionName ofClass:objectClass];
        }
    }
    self.backingCollection = collection;
    //        NSString* queueId = [options valueForKey:KCSStoreKeyUniqueOfflineSaveIdentifier];
    //        if (queueId == nil)
    //            queueId = [self description];
    //        //        _saveQueue = [KCSSaveQueue saveQueueForCollection:self.backingCollection uniqueIdentifier:queueId];
    //        self.cache2 = [[KCSObjectCache alloc] init]; //TODO: use persistence key
    //
    //        _offlineSaveEnabled = [options valueForKey:KCSStoreKeyUniqueOfflineSaveIdentifier] != nil;
    //
    //        //TODO: use delegate in c2
    //        id del = [options valueForKey:KCSStoreKeyOfflineSaveDelegate];
    //#warning        _saveQueue.delegate = del;
    
    
    _previousProgress = [options objectForKey:KCSStoreKeyOngoingProgress];
    _title = [options objectForKey:KCSStoreKeyTitle];
    
    KCSCachePolicy cachePolicy = (options[KCSStoreKeyCachePolicy] == nil) ? [KCSCachedStore defaultCachePolicy] : [options[KCSStoreKeyCachePolicy] intValue];
    self.cachePolicy = cachePolicy;
    [[[KCSAppdataStore caches] dataModel] setClass:self.backingCollection.objectTemplate forCollection:self.backingCollection.collectionName];
    
    self.offlineUpdateEnabled = [options[KCSStoreKeyOfflineUpdateEnabled] boolValue];
    
    
    if (self.backingCollection == nil) {
        [[NSException exceptionWithName:NSInvalidArgumentException reason:@"Collection cannot be nil" userInfo:options] raise];
    }
    
    // Even if nothing happened we return YES (as it's not a failure)
    return YES;
}

#pragma mark - Block Making
- (NSError*) noCollectionError
{
    NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"This store is not associated with a resource."
                                                                       withFailureReason:@"Store's collection is nil"
                                                                  withRecoverySuggestion:@"Create a store with KCSCollection object for  'kKCSStoreKeyResource'."
                                                                     withRecoveryOptions:nil];
    return [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSNotFoundError userInfo:userInfo];
}

- (BOOL) validatePreconditionsAndSendErrorTo:(void(^)(id objs, NSError* error))completionBlock
{
    if (completionBlock == nil) {
        return NO;
    }
    
    BOOL okay = YES;
    KCSCollection* collection = self.backingCollection;
    if (collection == nil) {
        completionBlock(nil, [self noCollectionError]);
    }
    return okay;
}

#pragma mark - Querying/Fetching
//for overriding by subclasses (simpler than strategy, for now)
- (id) manufactureNewObject:(NSDictionary*)jsonDict resourcesOrNil:(NSMutableDictionary*)resources
{
    return [KCSObjectMapper makeObjectOfType:self.backingCollection.objectTemplate withData:jsonDict];
}

- (NSString*) getObjIdFromObject:(id)object completionBlock:(KCSCompletionBlock)completionBlock
{
    NSString* theId = nil;
    if ([object isKindOfClass:[NSString class]]) {
        theId = object;
    } else if ([object conformsToProtocol:@protocol(KCSPersistable)]) {
        theId = [object kinveyObjectId];
        if (theId == nil) {
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Invalid object ID."
                                                                               withFailureReason:@"Object id cannot be empty."
                                                                          withRecoverySuggestion:nil
                                                                             withRecoveryOptions:nil];
            NSError* error = [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSInvalidArgumentError userInfo:userInfo];
            completionBlock(nil, error);
        }
    } else {
        NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Invalid object ID."
                                                                           withFailureReason:@"Object id must be a NSString."
                                                                      withRecoverySuggestion:nil
                                                                         withRecoveryOptions:nil];
        NSError* error = [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSInvalidArgumentError userInfo:userInfo];
        completionBlock(nil, error);
    }
    return theId;
}

- (void) handleLoadResponse:(KCSNetworkResponse*)response error:(NSError*)error completionBlock:(KCSCompletionBlock)completionBlock
{
    if (error) {
        completionBlock(nil, error);
    } else {
        NSDictionary* jsonResponse = [response jsonObject];
        if (jsonResponse) {
            NSArray* jsonArray = [NSArray wrapIfNotArray:jsonResponse];
            NSUInteger itemCount = jsonArray.count;
            if (itemCount == 0) {
                completionBlock(@[], nil);
            } else if (itemCount == KCS_OBJECT_LIMIT) {
                KCSLogWarning(@"Returned exactly %i objects. This is the Kinvey limit for a query, and there may actually be more results. If this is the case use the limit & skip modifiers on `KCSQuery` to page through the results.", KCS_OBJECT_LIMIT);
            }
            __block NSUInteger completedCount = 0;
            __block NSError* resourceError = nil;
            NSMutableArray* returnObjects = [NSMutableArray arrayWithCapacity:itemCount];
            for (NSDictionary* jsonDict in jsonArray) {
                NSMutableDictionary* resources = [NSMutableDictionary dictionary];
                id newobj = [self manufactureNewObject:jsonDict resourcesOrNil:resources];
                [returnObjects addObject:newobj];
                NSUInteger resourceCount = resources.count;
                if ( resourceCount > 0 ) {
                    //need to load the resources
                    __block NSUInteger completedResourceCount = 0;
                    [resources enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                        [KCSFileStore downloadKCSFile:obj completionBlock:^(NSArray *downloadedResources, NSError *error) {
                            completedResourceCount++;
                            if (error != nil) {
                                resourceError = error;
                            }
                            if (downloadedResources != nil && downloadedResources.count > 0) {
                                KCSFile* downloadedFile = downloadedResources[0];
                                id loadedResource = [downloadedFile resolvedObject];
                                [newobj setValue:loadedResource forKey:key];
                            } else {
                                //set nil for the resource
                                [newobj setValue:nil forKey:key];
                            }
                            if (completedResourceCount == resourceCount) {
                                //all resources loaded
                                completedCount++;
                                if (completedCount == itemCount) {
                                    completionBlock(returnObjects, resourceError);
                                }
                            }
                        } progressBlock:^(NSArray *objects, double percentComplete) {
                            //TODO: sub progress
                        }];
                    }];
                } else {
                    //no linked resources
                    completedCount++;
                    if (completedCount == itemCount) {
                        completionBlock(returnObjects, resourceError);
                    }
                }
            }
        } else {
            completionBlock(nil, nil);
        }
    }
}

- (void)doLoadObjectWithID: (id)objectID
     withCompletionBlock: (KCSCompletionBlock)completionBlock
       withProgressBlock: (KCSProgressBlock)progressBlock;
{
    KCSSTORE_VALIDATE_PRECONDITION
    
    if ([objectID isKindOfClass:[NSArray class]]) {
        if ([objectID containsObject:@""]) {
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Invalid object ID."
                                                                               withFailureReason:@"Object id cannot be empty."
                                                                          withRecoverySuggestion:nil
                                                                             withRecoveryOptions:nil];
            NSError* error = [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSInvalidArgumentError userInfo:userInfo];
            completionBlock(nil, error);
            return;
        }
        
        
        KCSQuery* query = [KCSQuery queryOnField:KCSEntityKeyId usingConditional:kKCSIn forValue:objectID];
        [self doQueryWithQuery:query withCompletionBlock:completionBlock withProgressBlock:progressBlock]; //TODO pass down option with request method
    } else {
        NSString* _id = [self getObjIdFromObject:objectID completionBlock:completionBlock];
        if (_id) {
            if ([_id isEqualToString:@""]) {
                NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Invalid object ID."
                                                                                   withFailureReason:@"Object id cannot be empty."
                                                                              withRecoverySuggestion:nil
                                                                                 withRecoveryOptions:nil];
                NSError* error = [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSInvalidArgumentError userInfo:userInfo];
                completionBlock(nil, error);
                return;
            } else {
                NSString* route = [self.backingCollection route];
                
                KCSRequest2* request = [KCSRequest2 requestWithCompletion:^(KCSNetworkResponse *response, NSError *error) {
                    [self handleLoadResponse:response error:error completionBlock:completionBlock];
                }
                                                                    route:route
                                                                  options:@{KCSRequestLogMethod}
                                                              credentials:[KCSUser activeUser]];
                if (route == KCSRESTRouteAppdata) {
                    request.path = @[self.backingCollection.collectionName, _id];
                } else {
                    request.path = @[_id];
                }
                
                KCSPartialDataParser* partialParser = nil;
                if (progressBlock!= nil) {
                    partialParser = [[KCSPartialDataParser alloc] init];
                    partialParser.objectMaker = self;
                }
                request.progress = ^(id data, double progress){
                    if (progressBlock != nil) {
                        NSArray* partialResults = [partialParser parseData:data hasArray:NO];
                        progressBlock(partialResults, progress);
                    }
                };
                [request start];
            }
        } else {
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Invalid object ID."
                                                                               withFailureReason:@"Object id cannot be empty."
                                                                          withRecoverySuggestion:nil
                                                                             withRecoveryOptions:nil];
            NSError* error = [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSInvalidArgumentError userInfo:userInfo];
            completionBlock(nil, error);
            return;
        }
    }
}


- (void) loadEntityFromNetwork:(NSArray*)objectIDs withCompletionBlock:(KCSCompletionBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock policy:(KCSCachePolicy)cachePolicy
{
    [self doLoadObjectWithID:objectIDs withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        [self cacheObjects:objectIDs results:objectsOrNil error:errorOrNil policy:cachePolicy];
        completionBlock(objectsOrNil, errorOrNil);
    } withProgressBlock:progressBlock];
}

- (void) completeLoad:(id)obj withCompletionBlock:(KCSCompletionBlock)completionBlock
{
    NSError* error = (obj == nil) ? createCacheError(@"Load query not in cache" ) : nil;
    completionBlock(obj, error);
}

- (void)loadObjectWithID:(id)objectID
     withCompletionBlock:(KCSCompletionBlock)completionBlock
       withProgressBlock:(KCSProgressBlock)progressBlock
             cachePolicy:(KCSCachePolicy)cachePolicy
{
    if (objectID == nil) {
        [[NSException exceptionWithName:NSInvalidArgumentException reason:@"objectId is `nil`." userInfo:nil] raise];
    }
    
    //    NSArray* keys = [NSArray wrapIfNotArray:objectID];
    //Hold on the to the object first, in case the cache is cleared during this process
    NSArray* objs = [[KCSAppdataStore caches] pullIds:objectID route:[self.backingCollection route] collection:self.backingCollection.collectionName];
    if ([self shouldCallNetworkFirst:objs cachePolicy:cachePolicy] == YES) {
        [self loadEntityFromNetwork:objectID withCompletionBlock:completionBlock withProgressBlock:progressBlock policy:cachePolicy];
    } else {
        [self completeLoad:objs withCompletionBlock:completionBlock];
        if ([self shouldUpdateInBackground:cachePolicy] == YES) {
            [self loadEntityFromNetwork:objectID withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
                if ([self shouldIssueCallbackOnBackgroundQuery:cachePolicy] == YES) {
                    completionBlock(objectsOrNil, errorOrNil);
                }
            } withProgressBlock:nil policy:cachePolicy];
        }
    }
}

- (void)loadObjectWithID: (id)objectID
     withCompletionBlock: (KCSCompletionBlock)completionBlock
       withProgressBlock: (KCSProgressBlock)progressBlock
{
    [self loadObjectWithID:objectID withCompletionBlock:completionBlock withProgressBlock:progressBlock cachePolicy:_cachePolicy];
}

#pragma mark - Querying

- (void)doQueryWithQuery:(id)query withCompletionBlock: (KCSCompletionBlock)completionBlock withProgressBlock: (KCSProgressBlock)progressBlock
{
    KCSSTORE_VALIDATE_PRECONDITION
    KCSCollection* collection = self.backingCollection;
    NSString* route = [collection route];
    
    KCSRequest2* request = [KCSRequest2 requestWithCompletion:^(KCSNetworkResponse *response, NSError *error) {
        [self handleLoadResponse:response error:error completionBlock:completionBlock];
    }
                                                        route:route
                                                      options:@{KCSRequestLogMethod}
                                                  credentials:[KCSUser activeUser]];
    if (route == KCSRESTRouteAppdata) {
        request.path = @[collection.collectionName];
    } else {
        request.path = @[];
    }
    request.queryString = [query parameterStringRepresentation];
    KCSPartialDataParser* partialParser = nil;
    if (progressBlock!= nil) {
        partialParser = [[KCSPartialDataParser alloc] init];
        partialParser.objectMaker = self;
    }
    request.progress = ^(id data, double progress){
        if (progressBlock != nil) {
            NSArray* partialResults = [partialParser parseData:data hasArray:YES];
            progressBlock(partialResults, progress);
        }
    };
    
    [request start];
}

NSError* createCacheError(NSString* message)
{
    NSDictionary* userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:message
                                                                       withFailureReason:@"The specified query could not be found in the cache"
                                                                  withRecoverySuggestion:@"Resend query with cache policy that allows network connectivity"
                                                                     withRecoveryOptions:nil];
    return [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSNotFoundError userInfo:userInfo];
}

- (BOOL) shouldCallNetworkFirst:(id)cachedResult cachePolicy:(KCSCachePolicy)cachePolicy
{
    return cachePolicy == KCSCachePolicyNone ||
           cachePolicy == KCSCachePolicyNetworkFirst ||
           (cachePolicy != KCSCachePolicyLocalOnly && cachedResult == nil);
}

- (BOOL) shouldUpdateInBackground:(KCSCachePolicy)cachePolicy
{
    return cachePolicy == KCSCachePolicyLocalFirst || cachePolicy == KCSCachePolicyBoth;
}

- (BOOL) shouldIssueCallbackOnBackgroundQuery:(KCSCachePolicy)cachePolicy
{
    return cachePolicy == KCSCachePolicyBoth;
}

- (void) cacheQuery:(KCSQuery*)query value:(id)objectsOrNil error:(NSError*)errorOrNil policy:(KCSCachePolicy)cachePolicy
{
    DBAssert([query isKindOfClass:[KCSQuery class]], @"should be a query");
    if ((errorOrNil != nil && [[errorOrNil domain] isEqualToString:KCSNetworkErrorDomain] == NO) || (objectsOrNil == nil && errorOrNil == nil)) {
        //remove the object from the cache, if it exists if the there was an error or return nil, but not if there was a network error (keep using the cached value)
        BOOL removed = [[KCSAppdataStore caches] removeQuery:[KCSQuery2 queryWithQuery1:query] route:[self.backingCollection route] collection:self.backingCollection.collectionName];
        if (!removed) {
            KCSLogError(@"Error clearing query '%@' from cache:", query);
        }
    } else if (objectsOrNil != nil) {
        [[KCSAppdataStore caches] setObjects:objectsOrNil forQuery:[KCSQuery2 queryWithQuery1:query] route:[self.backingCollection route] collection:self.backingCollection.collectionName];
    }
}

- (void) cacheObjects:(NSArray*)ids results:(id)objectsOrNil error:(NSError*)errorOrNil policy:(KCSCachePolicy)cachePolicy
{
    if ((errorOrNil != nil && [[errorOrNil domain] isEqualToString:KCSNetworkErrorDomain] == NO) || (objectsOrNil == nil && errorOrNil == nil)) {
        //remove the object from the cache, if it exists if the there was an error or return nil, but not if there was a network error (keep using the cached value)
        [[KCSAppdataStore caches] deleteObjects:[NSArray wrapIfNotArray:ids] route:[self.backingCollection route] collection:self.backingCollection.collectionName];
    } else if (objectsOrNil != nil) {
        [[KCSAppdataStore caches] addObjects:objectsOrNil route:[self.backingCollection route] collection:self.backingCollection.collectionName];
    }
}

- (void) queryNetwork:(id)query withCompletionBlock:(KCSCompletionBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock policy:(KCSCachePolicy)cachePolicy
{
    [self doQueryWithQuery:query withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        [self cacheQuery:query value:objectsOrNil error:errorOrNil policy:cachePolicy];
        completionBlock(objectsOrNil, errorOrNil);
    } withProgressBlock:progressBlock];
}

- (void) completeQuery:(NSArray*)objs withCompletionBlock:(KCSCompletionBlock)completionBlock
{
    NSError* error = (objs == nil) ? createCacheError(@"Query not in cache") : nil;
    completionBlock(objs, error);
}

- (void)queryWithQuery:(id)query withCompletionBlock:(KCSCompletionBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock cachePolicy:(KCSCachePolicy)cachePolicy
{
    //Hold on the to the object first, in case the cache is cleared during this process
    id obj = [[KCSAppdataStore caches] pullQuery:[KCSQuery2 queryWithQuery1:query] route:[self.backingCollection route] collection:self.backingCollection.collectionName];
    if ([self shouldCallNetworkFirst:obj cachePolicy:cachePolicy] == YES) {
        [self queryNetwork:query withCompletionBlock:completionBlock withProgressBlock:progressBlock policy:cachePolicy];
    } else {
        [self completeQuery:obj withCompletionBlock:completionBlock];
        if ([self shouldUpdateInBackground:cachePolicy] == YES) {
            [self queryNetwork:query withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
                if ([self shouldIssueCallbackOnBackgroundQuery:cachePolicy] == YES) {
                    completionBlock(objectsOrNil, errorOrNil);
                }
            } withProgressBlock:nil policy:cachePolicy];
        }
    }
}

- (void)queryWithQuery:(id)query withCompletionBlock:(KCSCompletionBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    [self queryWithQuery:query withCompletionBlock:completionBlock withProgressBlock:progressBlock cachePolicy:_cachePolicy];
}

#pragma mark - grouping

- (void) handleGroupResponse:(KCSNetworkResponse*)response key:(NSString*)key fields:(NSArray*)fields buildsObjects:(BOOL)buildsObjects completionBlock:(KCSGroupCompletionBlock)completionBlock
{
    NSObject* jsonData = [response jsonObject];
    
    NSArray *jsonArray = nil;
    
    if ([jsonData isKindOfClass:[NSArray class]]){
        jsonArray = (NSArray *)jsonData;
    } else {
        if ([(NSDictionary *)jsonData count] == 0){
            jsonArray = [NSArray array];
        } else {
            jsonArray = @[jsonData];
        }
    }
    
    if (buildsObjects == YES) {
        NSMutableArray* newArray = [NSMutableArray arrayWithCapacity:jsonArray.count];
        for (NSDictionary* d in jsonArray) {
            NSMutableDictionary* newDictionary = [d mutableCopy];
            NSArray* objectDicts = [d objectForKey:key];
            NSMutableArray* returnObjects = [NSMutableArray arrayWithCapacity:objectDicts.count];
            for (NSDictionary* objDict in objectDicts) {
                NSMutableDictionary* resources = [NSMutableDictionary dictionary];
                id newobj = [self manufactureNewObject:objDict resourcesOrNil:resources];
                [returnObjects addObject:newobj];
            }
            [newDictionary setObject:returnObjects forKey:key];
            [newArray addObject:newDictionary];
        }
        jsonArray = [NSArray arrayWithArray:newArray];
    }
    
    KCSGroup* group = [[KCSGroup alloc] initWithJsonArray:jsonArray valueKey:key queriedFields:fields];
    
    completionBlock(group, nil);
}

- (void)doGroup:(id)fieldOrFields reduce:(KCSReduceFunction *)function condition:(KCSQuery *)condition completionBlock:(KCSGroupCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    BOOL okayToProceed = [self validatePreconditionsAndSendErrorTo:completionBlock];
    if (okayToProceed == NO) {
        return;
    }
    
    KCSCollection* collection = self.backingCollection;
    NSString* route = [collection route];
    
    NSArray* fields = [NSArray wrapIfNotArray:fieldOrFields];
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithCapacity:4];
    NSMutableDictionary *keys = [NSMutableDictionary dictionaryWithCapacity:[fields count]];
    for (NSString* field in fields) {
        [keys setObject:[NSNumber numberWithBool:YES] forKey:field];
    }
    [body setObject:keys forKey:@"key"];
    [body setObject:[function JSONStringRepresentationForInitialValue:fields] forKey:@"initial"];
    [body setObject:[function JSONStringRepresentationForFunction:fields] forKey:@"reduce"];
    [body setObject:[NSDictionary dictionary] forKey:@"finalize"];
    
    if (condition != nil) {
        [body setObject:[condition query] forKey:@"condition"];
    }
    
    KCSRequest2* request = [KCSRequest2 requestWithCompletion:^(KCSNetworkResponse *response, NSError *error) {
        if (error) {
            completionBlock(nil, error);
        } else {
            [self handleGroupResponse:response
                                  key:[function outputValueName:fields]
                               fields:fields
                        buildsObjects:[function buildsObjects]
                      completionBlock:completionBlock];
        }
    }
                                                        route:route
                                                      options:@{KCSRequestLogMethod}
                                                  credentials:[KCSUser activeUser]];
    if (route == KCSRESTRouteAppdata) {
        request.path = @[collection.collectionName, @"_group"];
    } else {
        request.path = @[@"_group"];
    }
    
    request.body = body;
    request.method = KCSRESTMethodPOST;
    request.progress = ^(id data, double progress){
        if (progressBlock != nil) {
            progressBlock(nil, progress);
        }
    };
    [request start];
}

- (void)group:(id)fieldOrFields reduce:(KCSReduceFunction *)function completionBlock:(KCSGroupCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    [self group:fieldOrFields reduce:function condition:[KCSQuery query] completionBlock:completionBlock progressBlock:progressBlock];
}

- (void) cacheGrouping:(NSArray*)fields reduce:(KCSReduceFunction *)function condition:(KCSQuery *)condition results:(KCSGroup*)objectsOrNil error:(NSError*)errorOrNil policy:(KCSCachePolicy)cachePolicy
{
    //TODO: reinstate GROUP caching?
    
    //    if ((errorOrNil != nil && [[errorOrNil domain] isEqualToString:KCSNetworkErrorDomain] == NO) || (objectsOrNil == nil && errorOrNil == nil)) {
    //        //remove the object from the cache, if it exists if the there was an error or return nil, but not if there was a network error (keep using the cached value)
    //        [_cache removeGroup:fields reduce:function condition:condition];
    //    } else if (objectsOrNil != nil) {
    //        [_cache setResults:objectsOrNil forGroup:fields reduce:function condition:condition];
    //    }
    //
}

- (void)groupNetwork:(NSArray *)fields reduce:(KCSReduceFunction *)function condition:(KCSQuery *)condition completionBlock:(KCSGroupCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock policy:(KCSCachePolicy)cachePolicy
{
    [self doGroup:fields reduce:function condition:condition completionBlock:^(KCSGroup *valuesOrNil, NSError *errorOrNil) {
        [self cacheGrouping:fields reduce:function condition:condition results:valuesOrNil error:errorOrNil policy:cachePolicy ];
        completionBlock(valuesOrNil, errorOrNil);
    } progressBlock:progressBlock];
}

- (void) completeGroup:(id)obj withCompletionBlock:(KCSGroupCompletionBlock)completionBlock
{
    NSError* error = (obj == nil) ? createCacheError(@"Grouping query not in cache") : nil;
    completionBlock(obj, error);
}

- (void)group:(id)fieldOrFields reduce:(KCSReduceFunction *)function condition:(KCSQuery *)condition completionBlock:(KCSGroupCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock cachePolicy:(KCSCachePolicy)cachePolicy
{
    NSArray* fields = [NSArray wrapIfNotArray:fieldOrFields];
    //TODO:
    //    KCSCacheKey* key = [[[KCSCacheKey alloc] initWithFields:fields reduce:function condition:condition] autorelease];
    id obj = nil; // [_cache objectForKey:key]; //Hold on the to the object first, in case the cache is cleared during this process
    if ([self shouldCallNetworkFirst:obj cachePolicy:cachePolicy] == YES) {
        [self groupNetwork:fields reduce:function condition:condition completionBlock:completionBlock progressBlock:progressBlock policy:cachePolicy];
    } else {
        [self completeGroup:obj withCompletionBlock:completionBlock];
        if ([self shouldUpdateInBackground:cachePolicy] == YES) {
            [self groupNetwork:fields reduce:function condition:condition completionBlock:^(KCSGroup *valuesOrNil, NSError *errorOrNil) {
                if ([self shouldIssueCallbackOnBackgroundQuery:cachePolicy] == YES) {
                    completionBlock(valuesOrNil, errorOrNil);
                }
            } progressBlock:nil policy:cachePolicy];
        }
    }
}

- (void)group:(id)fieldOrFields reduce:(KCSReduceFunction *)function condition:(KCSQuery *)condition completionBlock:(KCSGroupCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    [self group:fieldOrFields reduce:function condition:condition completionBlock:completionBlock progressBlock:progressBlock cachePolicy:_cachePolicy];
}


#pragma mark - Adding/Updating
- (BOOL) isNoNetworkError:(NSError*)error
{
    BOOL isNetworkError = NO;
    if ([[error domain] isEqualToString:KCSNetworkErrorDomain]) { //KCSNetworkErrorDomain
        NSError* underlying = [error userInfo][NSUnderlyingErrorKey];
        if (underlying) {
            //not sure what kind this is, so try again later
            //error objects should have an underlying eror when coming from KCSAsyncRequest
            return [self isNoNetworkError:underlying];
        }
    } else if ([[error domain] isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case kCFURLErrorUnknown:
            case kCFURLErrorTimedOut:
            case kCFURLErrorNotConnectedToInternet:
            case kCFURLErrorDNSLookupFailed:
                KCSLogNetwork(@"Got a network error (%d) on save, adding to queue.");
                isNetworkError = YES;
                break;
            default:
                KCSLogNetwork(@"Got a network error (%d) on save, but NOT queueing.", error.code);
        }
        //TODO: ios7 background update on timer if can't resend
    }
    return isNetworkError;
}

- (BOOL) shouldEnqueue:(NSError*)error
{
    return self.offlineUpdateEnabled && [KCSAppdataStore caches].offlineUpdateEnabled && [self isNoNetworkError:error] == YES;
}

- (void) saveMainEntity:(KCSSerializedObject*)serializedObj progress:(KCSSaveGraph*)progress withCompletionBlock:(KCSCompletionBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    BOOL isPostRequest = serializedObj.isPostRequest;
    
    //Step 3: save entity
    KCSCollection* collection = self.backingCollection;
    NSString* route = [collection route];
    KCSRequest2* request = [KCSRequest2 requestWithCompletion:^(KCSNetworkResponse *response, NSError *error) {
        if (error) {
            if ([self shouldEnqueue:error] == YES) {
                //enqueue save
                NSString* _id = [[KCSAppdataStore caches] addUnsavedObject:serializedObj.handleToOriginalObject entity:serializedObj.dataToSerialize route:[self.backingCollection route] collection:self.backingCollection.collectionName method:(isPostRequest ? KCSRESTMethodPOST : KCSRESTMethodPUT) headers:@{KCSRequestLogMethod} error:error];
                
                if (_id != nil) {
                    error = [error updateWithInfo:@{KCS_ERROR_UNSAVED_OBJECT_IDS_KEY : @[_id]}];
                }
            }
            completionBlock(nil, error);
        } else {
            NSDictionary* jsonResponse = [response jsonObject];
            NSArray* arr = nil;
            if (jsonResponse != nil && serializedObj != nil) {
                id newObj = [KCSObjectMapper populateExistingObject:serializedObj withNewData:jsonResponse];
                arr = @[newObj];
            }
            completionBlock(arr, nil);
        }
    }
                                                        route:route
                                                      options:@{KCSRequestLogMethod}
                                                  credentials:[KCSUser activeUser]];
    NSString *objectId = serializedObj.objectId;
    NSDictionary *dictionaryToMap = serializedObj.dataToSerialize;
    
    request.method = (isPostRequest) ? KCSRESTMethodPOST : KCSRESTMethodPUT;
    
    NSArray* path = (route == KCSRESTRouteAppdata) ? @[collection.collectionName] : @[];
    if (objectId) {
        path = [path arrayByAddingObject:objectId];
    }
    request.path = path;
    request.body = dictionaryToMap;
    
    id objKey = [[serializedObj userInfo] objectForKey:@"entityProgress"];
    request.progress = ^(id data, double progress){
        [objKey setPc:progress];
        if (progressBlock != nil) {
            progressBlock(@[], progress);
        }
    };
    [request start];
}

- (void) saveEntityWithResources:(KCSSerializedObject*)so progress:(KCSSaveGraph*)progress withCompletionBlock:(KCSCompletionBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    //just go right on to main entity here sine this store does not do resources
    [self saveMainEntity:so progress:progress withCompletionBlock:completionBlock withProgressBlock:progressBlock];
}

- (KCSSerializedObject*) makeSO:(id<KCSPersistable>)object error:(NSError**)error
{
    return [KCSObjectMapper makeKinveyDictionaryFromObject:object error:error];
}

- (void) saveEntity:(id<KCSPersistable>)objToSave progressGraph:(KCSSaveGraph*)progress doSaveBlock:(KCSCompletionBlock)doSaveblock alreadySavedBlock:(KCSCompletionWrapperBlock_t)alreadySavedBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    //Step 0: Serialize Object
    NSError* error = nil;
    KCSSerializedObject* so = [self makeSO:objToSave error:&error];
    if (so == nil && error) {
        doSaveblock(@[], error);
        return;
    }
    id objKey = [progress markEntity:so];
    __weak id saveGraph = objKey;
    DBAssert(objKey != nil, @"should have a valid obj key here");
    NSString* cname = self.backingCollection.collectionName;
    [objKey ifNotLoaded:^{
        [self saveEntityWithResources:so progress:progress
                  withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
                      [objKey finished:objectsOrNil error:errorOrNil];
                      [objKey doAfterWaitingResaves:^{
                          doSaveblock(objectsOrNil, errorOrNil);
                      }];
                      
                  } withProgressBlock:progressBlock];
    }
    otherwiseWhenLoaded:alreadySavedBlock
andResaveAfterReferencesSaved:^{
    KCSSerializedObject* soPrime = [KCSObjectMapper makeResourceEntityDictionaryFromObject:objToSave forCollection:cname error:NULL]; //TODO: figure out if this is needed?
    [soPrime restoreReferences:so];
    [self saveMainEntity:soPrime progress:progress withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        [saveGraph resaveComplete];
    } withProgressBlock:^(NSArray *objects, double percentComplete) {
        //TODO: as above
    }];
}];
}

- (void)saveObject:(id)object withCompletionBlock:(KCSCompletionBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    KCSSTORE_VALIDATE_PRECONDITION
    
    NSArray* objectsToSave = [NSArray wrapIfNotArray:object];
    NSUInteger totalItemCount = [objectsToSave count];
    
    if (totalItemCount == 0) {
        //TODO: does this need an error?
        completionBlock(@[], nil);
    }
    
    __block int completedItemCount = 0;
    NSMutableArray* completedObjects = [NSMutableArray arrayWithCapacity:totalItemCount];
    
    KCSSaveGraph* progress = _previousProgress == nil ? [[KCSSaveGraph alloc] initWithEntityCount:totalItemCount] : _previousProgress;
    
    __block NSError* topError = nil;
    __block BOOL done = NO;
    [objectsToSave enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        //Step 0: Serialize Object
        [self saveEntity:obj
           progressGraph:progress
             doSaveBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
                 if (done) {
                     //don't do the completion blocks for all the objects if its previously finished
                     return;
                 }
                 if (errorOrNil != nil) {
                     topError = errorOrNil;
                 }
                 if (objectsOrNil != nil) {
                     [completedObjects addObjectsFromArray:objectsOrNil];
                 }
                 completedItemCount++;
                 BOOL shouldStop = errorOrNil != nil && self.treatSingleFailureAsGroupFailure;
                 if (completedItemCount == totalItemCount || shouldStop) {
                     done = YES;
                     completionBlock(completedObjects, topError);
                 }
                 
             }
       alreadySavedBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
           if (done) {
               //don't do the completion blocks for all the objects if its previously finished
               return;
           }
           [completedObjects addObjectsFromArray:objectsOrNil];
           completedItemCount++;
           if (completedItemCount == totalItemCount) {
               done = YES;
               completionBlock(completedObjects, topError);
           }
       }
       withProgressBlock:progressBlock];
    }];
}

#pragma mark - Removing
- (void) removeObject:(id)object withCompletionBlock:(KCSCountBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    BOOL okayToProceed = [self validatePreconditionsAndSendErrorTo:^(id objs, NSError *error) {
        completionBlock(0, error);
    }];
    if (okayToProceed == NO) {
        return;
    }
    
    if ([object isKindOfClass:[NSArray class]]) {
        //input is an array
        NSArray* objects = object;
        if (objects.count == 0) {
            completionBlock(0, nil);
        }
        if ([object[0] isKindOfClass:[NSString class]]) {
            //input is _id array
            object = [KCSQuery queryOnField:KCSEntityKeyId usingConditional:kKCSIn forValue:objects];
        } else if ([object[0] conformsToProtocol:@protocol(KCSPersistable)] == YES) {
            //input is object array?
            NSMutableArray* ids = [NSMutableArray arrayWithCapacity:objects.count];
            for (NSObject<KCSPersistable>* obj in objects) {
                [ids addObject:[obj kinveyObjectId]];
            }
            object = [KCSQuery queryOnField:KCSEntityKeyId usingConditional:kKCSIn forValue:ids];
        } else {
            [[NSException exceptionWithName:NSInvalidArgumentException reason:@"input is not a homogenous array of id strings or objects" userInfo:nil] raise];
        }
    } else if ([object conformsToProtocol:@protocol(KCSPersistable)]) {
        //if its just a single object get the _id
        object = [object kinveyObjectId];
    }
    
    KCSDataStore* store2 = [[KCSDataStore alloc] initWithCollection:self.backingCollection.collectionName];
    
    id<KCSNetworkOperation> op = nil;
    if ([object isKindOfClass:[KCSQuery class]]) {
        op = [store2 deleteByQuery:[KCSQuery2 queryWithQuery1:object] completion:^(NSUInteger count, NSError *error) {
            if (error) {
                if ([self shouldEnqueue:error]) {
                    //enqueue save
                    id errorValue = [[KCSAppdataStore caches] addUnsavedDeleteQuery:[KCSQuery2 queryWithQuery1:object] route:[self.backingCollection route] collection:self.backingCollection.collectionName method:KCSRESTMethodDELETE headers:@{KCSRequestLogMethod} error:error];
                    
                    if (errorValue != nil) {
                        error = [error updateWithInfo:@{KCS_ERROR_UNSAVED_OBJECT_IDS_KEY : @[errorValue]}];
                    }
                }
                completionBlock(0, error);
            } else {
                completionBlock(count, nil);
            }
        }];
    } else {
        op = [store2 deleteEntity:object completion:^(NSUInteger count, NSError *error) {
            if (error) {
                if ([self shouldEnqueue:error]) {
                    //enqueue save
                    id errorValue = [[KCSAppdataStore caches] addUnsavedDelete:object route:[self.backingCollection route] collection:self.backingCollection.collectionName method:KCSRESTMethodDELETE headers:@{KCSRequestLogMethod} error:error];
                    if (errorValue != nil) {
                        error = [error updateWithInfo:@{KCS_ERROR_UNSAVED_OBJECT_IDS_KEY : @[errorValue]}];
                    }
                }
                completionBlock(0, error);
            } else {
                completionBlock(count, nil);
            }
            
        }];
    }
    if (progressBlock) {
        op.progressBlock = ^(id data, double progress) {
            progressBlock(nil, progress);
        };
    }
    
}

#pragma mark - Information
- (void)countWithBlock:(KCSCountBlock)countBlock
{
    [self countWithQuery:nil completion:countBlock];
}

- (void)countWithQuery:(KCSQuery*)query completion:(KCSCountBlock)countBlock
{
    if (countBlock == nil) {
        return;
    } else if (self.backingCollection == nil) {
        countBlock(0, [self noCollectionError]);
        return;
    }
    
    KCSCollection* collection = self.backingCollection;
    NSString* route = [collection route];
    KCSRequest2* request = [KCSRequest2 requestWithCompletion:^(KCSNetworkResponse *response, NSError *error) {
        if (error) {
            countBlock(0, error);
        } else {
            NSDictionary *jsonResponse = [response jsonObject];
            NSNumber* val = jsonResponse[@"count"];
            countBlock([val unsignedLongValue], nil);
        }
    }
                                                        route:route
                                                      options:@{KCSRequestLogMethod}
                                                  credentials:[KCSUser activeUser]];
    
    NSString* queryString = query != nil ? [query parameterStringRepresentation] : @"";
    request.queryString = queryString;
    if (route == KCSRESTRouteAppdata) {
        request.path = @[collection.collectionName, @"_count"];
    } else {
        request.path = @[@"_count"];
    }
    [request start];
}

@end
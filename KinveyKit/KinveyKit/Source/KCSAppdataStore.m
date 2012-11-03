
//
//  KCSAppdataStore.m
//  KinveyKit
//
//  Created by Brian Wilson on 5/1/12.
//  Copyright (c) 2012 Kinvey. All rights reserved.
//

//TODO: check headers


#import "KCSAppdataStore.h"

#import "KCSGroup.h"
#import "KCSReduceFunction.h"
#import "KCS_SBJson.h"
#import "KCSRESTRequest.h"
#import "KCSConnectionResponse.h"
#import "KCSLogManager.h"
#import "KinveyHTTPStatusCodes.h"
#import "KinveyErrorCodes.h"
#import "KCSErrorUtilities.h"
#import "KCSConnectionProgress.h"
#import "KCSQuery.h"
#import "KinveyEntity.h"
#import "NSArray+KinveyAdditions.h"
#import "NSString+KinveyAdditions.h"
#import "KCSObjectMapper.h"
#import "KCSHiddenMethods.h"
#import "KCSReachability.h"
#import "KCSSaveQueue.h"
#import "KCSSaveGraph.h"
#import "KCSResourceStore.h"
#import "KCSResource.h"

#define KCSSTORE_VALIDATE_PRECONDITION BOOL okayToProceed = [self validatePreconditionsAndSendErrorTo:completionBlock]; \
if (okayToProceed == NO) { \
return; \
}

typedef KCSRESTRequest* (^RestRequestForObjBlock_t)(id obj);
typedef void (^ProcessDataBlock_t)(KCSConnectionResponse* response, KCSCompletionBlock completion);

@interface KCSAppdataStore () {
    KCSSaveGraph* _previousProgress;
    KCSSaveQueue* _saveQueue;
    BOOL _offlineSaveEnabled;
    NSString* _title;
}

@property (nonatomic) BOOL treatSingleFailureAsGroupFailure;
@property (nonatomic, retain) KCSCollection *backingCollection;

@end


@implementation KCSAppdataStore

@synthesize authHandler = _authHandler;
@synthesize treatSingleFailureAsGroupFailure = _treatSingleFailureAsGroupFailure;
@synthesize backingCollection = _backingCollection;


#pragma mark -
#pragma mark Initialization

- (id)init
{
    return [self initWithAuth:nil];
}

- (id)initWithAuth: (KCSAuthHandler *)auth
{
    self = [super init];
    if (self) {
        _authHandler = [auth retain];
        _treatSingleFailureAsGroupFailure = YES;
        _saveQueue = nil;
        _title = nil;
    }
    return self;
}

- (void) dealloc
{
    [_authHandler release];
    [_saveQueue release];
    [_previousProgress release];
    [_title release];
    [super dealloc];
}

+ (id)store
{
    return [self storeWithAuthHandler:nil withOptions:nil];
}

+ (id)storeWithOptions: (NSDictionary *)options
{
    return [self storeWithAuthHandler:nil withOptions:options];
}

+ (id)storeWithAuthHandler: (KCSAuthHandler *)authHandler withOptions: (NSDictionary *)options
{
    KCSAppdataStore *store = [[[self alloc] initWithAuth:authHandler] autorelease];
    [store configureWithOptions:options];
    return store;
}

+ (id) storeWithCollection:(KCSCollection*)collection options:(NSDictionary*)options
{
    return [self storeWithCollection:collection authHandler:nil withOptions:options];
}

+ (id)storeWithCollection:(KCSCollection*)collection authHandler:(KCSAuthHandler *)authHandler withOptions: (NSDictionary *)options {
    
    if (options == nil) {
        options = @{ KCSStoreKeyResource : collection };
    } else {
        options= [NSMutableDictionary dictionaryWithDictionary:options];
        [options setValue:collection forKey:KCSStoreKeyResource];
    }
    return [self storeWithAuthHandler:authHandler withOptions:options];
}

- (BOOL)configureWithOptions: (NSDictionary *)options
{
    
    if (options) {
        // Configure
        self.backingCollection = [options objectForKey:KCSStoreKeyResource];
        NSString* queueId = [options valueForKey:KCSStoreKeyUniqueOfflineSaveIdentifier];
        if (queueId == nil)
            queueId = [self description];
        _saveQueue = [[KCSSaveQueue saveQueueForCollection:self.backingCollection uniqueIdentifier:queueId] retain];
        _offlineSaveEnabled = [options valueForKey:KCSStoreKeyUniqueOfflineSaveIdentifier] != nil;
        id del = [options valueForKey:KCSStoreKeyOfflineSaveDelegate];
        _saveQueue.delegate = del;
        
        _previousProgress = [[options objectForKey:KCSStoreKeyOngoingProgress] retain];
        _title = [[options objectForKey:KCSStoreKeyTitle] retain];
    }
    
    // Even if nothing happened we return YES (as it's not a failure)
    return YES;
}

#pragma mark - Block Making
// Avoid compiler warning by prototyping here...
KCSConnectionCompletionBlock makeGroupCompletionBlock(KCSGroupCompletionBlock onComplete, NSString* key, NSArray* fields);
KCSConnectionFailureBlock    makeGroupFailureBlock(KCSGroupCompletionBlock onComplete);
KCSConnectionProgressBlock   makeProgressBlock(KCSProgressBlock onProgress);

KCSConnectionCompletionBlock makeGroupCompletionBlock(KCSGroupCompletionBlock onComplete, NSString* key, NSArray* fields)
{
    return [[^(KCSConnectionResponse *response){
        
        KCSLogTrace(@"In collection callback with response: %@", response);
        NSMutableArray *processedData = [[NSMutableArray alloc] init];
        NSObject* jsonData = [response jsonResponseValue];
        
        NSArray *jsonArray = nil;
        if (response.responseCode != KCS_HTTP_STATUS_OK){
            NSError* error = [KCSErrorUtilities createError:(NSDictionary*)jsonData description:@"Collection grouping was unsuccessful." errorCode:response.responseCode domain:KCSAppDataErrorDomain];
            onComplete(nil, error);
            
            [processedData release];
            return;
        }
        
        if ([jsonData isKindOfClass:[NSArray class]]){
            jsonArray = (NSArray *)jsonData;
        } else {
            if ([(NSDictionary *)jsonData count] == 0){
                jsonArray = [NSArray array];
            } else {
                jsonArray = @[jsonData];
            }
        }
        
        KCSGroup* group = [[[KCSGroup alloc] initWithJsonArray:jsonArray valueKey:key queriedFields:fields] autorelease];
        
        onComplete(group, nil);
        [processedData release];
    } copy] autorelease];
}

KCSConnectionFailureBlock makeGroupFailureBlock(KCSGroupCompletionBlock onComplete)
{
    return [[^(NSError *error){
        onComplete(nil, error);
    } copy] autorelease];
}

KCSConnectionProgressBlock makeProgressBlock(KCSProgressBlock onProgress)
{
    return onProgress == nil ? nil : [[^(KCSConnectionProgress *connectionProgress) {
        onProgress(connectionProgress.objects, connectionProgress.percentComplete);
    } copy] autorelease];
}

- (BOOL) validatePreconditionsAndSendErrorTo:(void(^)(id objs, NSError* error))completionBlock
{
    if (completionBlock == nil) {
        return NO;
    }
    
    BOOL okay = YES;
    KCSCollection* collection = self.backingCollection;
    if (collection == nil) {
        collection = NO;
        dispatch_async(dispatch_get_current_queue(), ^{
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"This store is not associated with a resource."
                                                                               withFailureReason:@"Store's collection is nil"
                                                                          withRecoverySuggestion:@"Create a store with KCSCollection object for  'kKCSStoreKeyResource'."
                                                                             withRecoveryOptions:nil];
            NSError* error = [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSNotFoundError userInfo:userInfo];
            
            completionBlock(nil, error);
        });
    }
    return okay;
}

#pragma mark - Querying/Fetching
//for overriding by subclasses (simpler than strategy, for now)
- (id) manufactureNewObject:(NSDictionary*)jsonDict resourcesOrNil:(NSMutableDictionary*)resources
{
    return [KCSObjectMapper makeObjectOfType:self.backingCollection.objectTemplate withData:jsonDict];
}

- (ProcessDataBlock_t) makeProcessDictBlockForNewObject
{
    ProcessDataBlock_t processBlock = ^(KCSConnectionResponse *response, KCSCompletionBlock completionBlock) {
        NSDictionary* jsonResponse = (NSDictionary*) [response jsonResponseValue];
        
        if (response.responseCode != KCS_HTTP_STATUS_CREATED && response.responseCode != KCS_HTTP_STATUS_OK){
            NSError* error = [KCSErrorUtilities createError:jsonResponse description:nil errorCode:response.responseCode domain:KCSAppDataErrorDomain];
            completionBlock(nil, error);
        } else {
            if (jsonResponse) {
                NSArray* jsonArray = [NSArray wrapIfNotArray:jsonResponse];
                NSUInteger itemCount = jsonArray.count;
                if (itemCount == 0) {
                    completionBlock(@[], nil);
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
                            KCSResourceStore* resourceStore = [KCSResourceStore store];
                            [resourceStore loadObjectWithID:[obj objectForKey:@"_loc"] withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
                                completedResourceCount++;
                                if (errorOrNil != nil) {
                                    resourceError = errorOrNil;
                                }
                                if (objectsOrNil != nil && objectsOrNil.count > 0) {
                                    NSData* resourceData = [objectsOrNil objectAtIndex:0];
                                    id loadedResource = [KCSResource resourceObjectFromData:resourceData type:[obj objectForKey:@"_mime-type"]];
                                    [newobj setValue:loadedResource forKey:key];
                                }
                                if (completedResourceCount == resourceCount) {
                                    //all resources loaded
                                    completedCount++;
                                    if (completedCount == itemCount) {
                                        completionBlock(returnObjects, resourceError);
                                    }
                                }
                            } withProgressBlock:^(NSArray *objects, double percentComplete) {
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
    };
    return [[processBlock copy] autorelease];
}

- (void) loadObjectsWithRESTRequest:(KCSRESTRequest*)request dataHandler:(ProcessDataBlock_t)processBlock completionBlock:(KCSCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    KCSConnectionCompletionBlock completionAction = ^(KCSConnectionResponse* response) {
        KCSLogTrace(@"In collection callback with response: %@", [response jsonResponseValue]);
        processBlock(response, ^(NSArray* objectsOrNil, NSError* error) {
            completionBlock(objectsOrNil, error);
        });
    };
    
    KCSConnectionFailureBlock failureAction = ^(NSError* error) {
        completionBlock(nil, error);
    };
    [[request withCompletionAction:completionAction failureAction:failureAction progressAction:^(KCSConnectionProgress* progress) {
        if (progressBlock != nil) {
            progressBlock(progress.objects, progress.percentComplete);
        }
    }] start];
}

- (NSString*) getObjIdFromObject:(id)object completionBlock:(KCSCompletionBlock)completionBlock
{
    NSString* theId = nil;
    if ([object isKindOfClass:[NSString class]]) {
        theId = object;
    } else if ([object conformsToProtocol:@protocol(KCSPersistable)]) {
        theId = [object kinveyObjectId];
        if (theId == nil) {
            dispatch_async(dispatch_get_current_queue(), ^{
                NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Invalid object ID."
                                                                                   withFailureReason:@"Object id cannot be empty."
                                                                              withRecoverySuggestion:nil
                                                                                 withRecoveryOptions:nil];
                NSError* error = [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSInvalidArgumentError userInfo:userInfo];
                completionBlock(nil, error);
            });
        }
    } else {
        dispatch_async(dispatch_get_current_queue(), ^{
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Invalid object ID."
                                                                               withFailureReason:@"Object id must be a NSString."
                                                                          withRecoverySuggestion:nil
                                                                             withRecoveryOptions:nil];
            NSError* error = [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSInvalidArgumentError userInfo:userInfo];
            completionBlock(nil, error);
        });
    }
    return theId;
}

//for overriding by subclasses (simpler than strategy, for now)
- (NSString*) modifyLoadQuery:(NSString*)query ids:(NSArray*)array
{
    return query;
}

- (void)loadObjectWithID: (id)objectID
     withCompletionBlock: (KCSCompletionBlock)completionBlock
       withProgressBlock: (KCSProgressBlock)progressBlock;
{
    KCSSTORE_VALIDATE_PRECONDITION
    
    KCSCollection* collection = self.backingCollection;
    NSArray* array = [NSArray wrapIfNotArray:objectID];
    if ([array containsObject:@""]) {
        dispatch_async(dispatch_get_current_queue(), ^{
            NSDictionary *userInfo = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Invalid object ID."
                                                                               withFailureReason:@"Object id cannot be empty."
                                                                          withRecoverySuggestion:nil
                                                                             withRecoveryOptions:nil];
            NSError* error = [NSError errorWithDomain:KCSAppDataErrorDomain code:KCSInvalidArgumentError userInfo:userInfo];
            completionBlock(nil, error);
        });
        return;
    }
    
    NSString* query = @"";
    if (array.count == 1) {
        query = [self getObjIdFromObject:[array objectAtIndex:0] completionBlock:completionBlock];
        if (query == nil) {
            //already sent an error;
            return;
        }
    } else {
        NSMutableArray* objIds = [NSMutableArray arrayWithCapacity:array.count];
        for (id object in array) {
            NSString* anId = [self getObjIdFromObject:object completionBlock:completionBlock];
            if (anId == nil) {
                //already sent an error;
                return;
            } else {
                [objIds addObject:[NSString stringWithFormat:@"\"%@\"", anId]];
            }
        }
        query = [NSString stringWithFormat:@"{\"_id\" : { \"$in\" : [%@]}}", [objIds join:@","]];
        query = [NSString stringWithFormat:@"?query=%@",[query stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }
    
    query = [self modifyLoadQuery:query ids:array];
    
    KCSRESTRequest* request = [collection restRequestForMethod:kGetRESTMethod apiEndpoint:query];
    ProcessDataBlock_t processBlock = [self makeProcessDictBlockForNewObject];
    
    [self loadObjectsWithRESTRequest:request dataHandler:processBlock completionBlock:completionBlock progressBlock:progressBlock];
}

- (void)queryWithQuery: (id)query withCompletionBlock: (KCSCompletionBlock)completionBlock withProgressBlock: (KCSProgressBlock)progressBlock
{
    KCSSTORE_VALIDATE_PRECONDITION
    KCSCollection* collection = self.backingCollection;
    
    NSString *resource = nil;
    NSString *format = nil;
    
    if ([collection.collectionName isEqualToString:@""]){
        format = @"%@";
    } else {
        format = @"%@/";
    }
    
    KCSQuery* kcsQuery = (KCSQuery*)query;
    
    // Here we know that we're working with a query, so now we just check each of the params...
    if (kcsQuery != nil){
        resource = [collection.baseURL stringByAppendingFormat:format, collection.collectionName];
        resource = [resource stringByAppendingString:[query parameterStringRepresentation]];
    }
    
    KCSRESTRequest *request = [KCSRESTRequest requestForResource:resource usingMethod:kGetRESTMethod];
    ProcessDataBlock_t processBlock = [self makeProcessDictBlockForNewObject];
    
    KCSConnectionCompletionBlock completionAction = ^(KCSConnectionResponse* response) {
        KCSLogTrace(@"In collection callback with response: %@", response);
        processBlock(response, ^(NSArray* objectsOrNil, NSError* error) {
            completionBlock(objectsOrNil, error);
        });
    };
    
    KCSConnectionFailureBlock failureAction = ^(NSError* error) {
        completionBlock(nil, error);
    };
    
    [[request withCompletionAction:completionAction failureAction:failureAction progressAction:^(KCSConnectionProgress* progress) {
        if (progressBlock != nil) {
            progressBlock(progress.objects, progress.percentComplete);
        }
    }] start];
}

- (void)group:(id)fieldOrFields reduce:(KCSReduceFunction *)function condition:(KCSQuery *)condition completionBlock:(KCSGroupCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    KCSCollection* collection = self.backingCollection;
    BOOL okayToProceed = [self validatePreconditionsAndSendErrorTo:completionBlock];
    if (okayToProceed == NO) {
        return;
    }
    
    NSString* collectionName = collection.collectionName;
    NSString *format = nil;
    
    if ([collectionName isEqualToString:@""]){
        format = @"%@_group";
    } else {
        format = @"%@/_group";
    }
    
    NSArray* fields = [NSArray wrapIfNotArray:fieldOrFields];
    
    NSString *resource = [collection.baseURL stringByAppendingFormat:format, collectionName];
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
    
    KCSRESTRequest *request = [KCSRESTRequest requestForResource:resource usingMethod:kPostRESTMethod];
    KCS_SBJsonWriter *writer = [[[KCS_SBJsonWriter alloc] init] autorelease];
    [request addBody:[writer dataWithObject:body]];
    [request setContentType:@"application/json"];
    
    KCSConnectionCompletionBlock cBlock = makeGroupCompletionBlock(completionBlock, [function outputValueName:fields], fields);
    KCSConnectionFailureBlock fBlock = makeGroupFailureBlock(completionBlock);
    KCSConnectionProgressBlock pBlock = makeProgressBlock(progressBlock);
    
    // Make the request happen
    [[request withCompletionAction:cBlock failureAction:fBlock progressAction:pBlock] start];
}

- (void)group:(id)fieldOrFields reduce:(KCSReduceFunction *)function completionBlock:(KCSGroupCompletionBlock)completionBlock progressBlock:(KCSProgressBlock)progressBlock
{
    [self group:fieldOrFields reduce:function condition:[KCSQuery query] completionBlock:completionBlock progressBlock:progressBlock];
}

#pragma mark - Reachability
#if BUILD_FOR_UNIT_TEST
int reachable = -1;
- (void) setReachable:(BOOL)reachOverwrite
{
    reachable = reachOverwrite;
    SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithName(NULL, [(reachable ? @"127.0.0.1" : @"nevernever") UTF8String]); //TODO: based on ref
    KCSReachability* testReachability = [[KCSReachability alloc] initWithReachabilityRef:ref];
    [[NSNotificationCenter defaultCenter] postNotificationName: kKCSReachabilityChangedNotification object:testReachability];
}
#endif

- (BOOL) isKinveyReachable
{
#if BUILD_FOR_UNIT_TEST
    return reachable == -1 ? [[KCSClient sharedClient] kinveyReachability].isReachable : reachable;
#else
    return [[KCSClient sharedClient] kinveyReachability].isReachable;
#endif
}

#pragma mark - Adding/Updating
- (BOOL) offlineSaveEnabled
{
    return _offlineSaveEnabled;
}

- (NSUInteger) numberOfPendingSaves
{
    return [_saveQueue count];
}

- (ProcessDataBlock_t) makeProcessDictBlock:(KCSSerializedObject*)serializedObject
{
    ProcessDataBlock_t processBlock = ^(KCSConnectionResponse *response, KCSCompletionBlock completionBlock) {
        NSDictionary* jsonResponse = (NSDictionary*) [response jsonResponseValue];
        
        if (response.responseCode != KCS_HTTP_STATUS_CREATED && response.responseCode != KCS_HTTP_STATUS_OK){
            NSError* error = [KCSErrorUtilities createError:jsonResponse description:nil errorCode:response.responseCode domain:KCSAppDataErrorDomain];
            completionBlock(nil, error);
        } else {
            if (jsonResponse != nil && serializedObject != nil) {
                id newObj = [KCSObjectMapper populateExistingObject:serializedObject withNewData:jsonResponse];
                completionBlock(@[newObj], nil);
            } else {
                completionBlock(nil, nil);
            }
        }
    };
    return [[processBlock copy] autorelease];
}

- (void) saveMainEntity:(KCSSerializedObject*)serializedObj progress:(KCSSaveGraph*)progress withCompletionBlock:(KCSCompletionBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    //Step 3: save entity
    RestRequestForObjBlock_t requestBlock = ^KCSRESTRequest *(id obj) {
        BOOL isPostRequest = serializedObj.isPostRequest;
        NSString *objectId = serializedObj.objectId;
        NSDictionary *dictionaryToMap = [serializedObj.dataToSerialize retain];
        
        KCSCollection* collection = self.backingCollection;
        NSString *resource = nil;
        if ([collection.collectionName isEqualToString:@""]){
            resource = [collection.baseURL stringByAppendingFormat:@"%@", objectId];
        } else {
            resource = [collection.baseURL stringByAppendingFormat:@"%@/%@", collection.collectionName, objectId];
        }
        
        // If we need to post this, then do so
        NSInteger HTTPMethod = (isPostRequest) ? kPostRESTMethod : kPutRESTMethod;
        
        // Prepare our request
        KCSRESTRequest *request = [KCSRESTRequest requestForResource:resource usingMethod:HTTPMethod];
        
        // This is a JSON request
        [request setContentType:KCS_JSON_TYPE];
        
        // Make sure to include the UTF-8 encoded JSONData...
        KCS_SBJsonWriter *writer = [[[KCS_SBJsonWriter alloc] init] autorelease];
        NSData* bodyData = [writer dataWithObject:dictionaryToMap];
        if (!bodyData && [writer error]) {
            request = (id) [writer error];
        } else {
            [request addBody:[writer dataWithObject:dictionaryToMap]];
        }
        [dictionaryToMap release];
        return request;
    };
    
    
    ProcessDataBlock_t processBlock = [self makeProcessDictBlock:serializedObj];
    
    KCSConnectionCompletionBlock completionAction = ^(KCSConnectionResponse* response) {
        KCSLogTrace(@"In collection callback with response: %@", [response jsonResponseValue]);
        processBlock(response, completionBlock);
    };
    
    KCSConnectionFailureBlock failureAction = ^(NSError* error) {
        completionBlock(nil, error);
    };
    
    KCSRESTRequest* request = requestBlock(nil);
    if ([request isKindOfClass:[NSString class]]) {
        NSError* error = [KCSErrorUtilities createError:nil description:(NSString*)request errorCode:KCSBadRequestError domain:KCSAppDataErrorDomain];
        completionBlock(nil, error);
    } else {
        id objKey = [[serializedObj userInfo] objectForKey:@"entityProgress"];
        
        [[request withCompletionAction:completionAction failureAction:failureAction progressAction:^(KCSConnectionProgress* cxnProgress) {
            [objKey setPc:cxnProgress.percentComplete];
            if (progressBlock != nil) {
                progressBlock(cxnProgress.objects, progress.percentDone);
            }
        }] start];
    }
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
    DBAssert(objKey != nil, @"should have a valid obj key here");
    [objKey ifNotLoaded:^{
        [self saveEntityWithResources:so progress:progress withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
            [objKey finished];
            [objKey doAfterWaitingResaves:^{
                doSaveblock(objectsOrNil, errorOrNil);
            }];
            
        } withProgressBlock:progressBlock];
        
    } otherwiseWhenLoaded:alreadySavedBlock andResaveAfterReferencesSaved:^{
        KCSSerializedObject* soPrime = [KCSObjectMapper makeResourceEntityDictionaryFromObject:objToSave forCollection:self.backingCollection.collectionName error:NULL]; //TODO: figure out if this is needed?
        [soPrime restoreReferences:so];
        [self saveMainEntity:soPrime progress:progress withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
            [objKey resaveComplete];
        } withProgressBlock:^(NSArray *objects, double percentComplete) {
            //TODO: as above
        }];
    }];
}

- (void) enqueSave:(id<KCSPersistable>)obj
{
    [_saveQueue addObject:obj];
}

- (void) drainQueueWithProgressGraph:(KCSSaveGraph*)progress doSaveBlock:(KCSCompletionBlock)doSaveblock alreadySavedBlock:(KCSCompletionBlock)alreadySavedBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    if ([self offlineSaveEnabled] && [self isKinveyReachable] == NO) {
        NSDictionary* info = [KCSErrorUtilities createErrorUserDictionaryWithDescription:@"Could not reach Kinvey" withFailureReason:@"Application is offline" withRecoverySuggestion:@"Try again when app is online" withRecoveryOptions:nil];
        NSMutableDictionary* offlineErrorInfo = [NSMutableDictionary dictionaryWithDictionary:info];
        [offlineErrorInfo setObject:[_saveQueue ids] forKey:KCS_ERROR_UNSAVED_OBJECT_IDS_KEY];
        NSError* error = [NSError errorWithDomain:KCSNetworkErrorDomain code:KCSKinveyUnreachableError userInfo:offlineErrorInfo];
        doSaveblock(nil,error);
    } else {
        for (KCSSaveQueueItem* item in [_saveQueue array]) {
            id<KCSPersistable> obj = item.object;
            [_saveQueue removeItem:item];
            //Step 0: Serialize Object
            [self saveEntity:obj progressGraph:progress doSaveBlock:doSaveblock
           alreadySavedBlock:^{
               alreadySavedBlock(@[obj], nil);
           } withProgressBlock:progressBlock];
        }
    }
}

- (void)saveObject:(id)object withCompletionBlock:(KCSCompletionBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    KCSSTORE_VALIDATE_PRECONDITION
    
    NSArray* objectsToSave = [NSArray wrapIfNotArray:object];
    int totalItemCount = [objectsToSave count];
    
    if (totalItemCount == 0) {
        //TODO: does this need an error?
        completionBlock(nil, nil);
    }
    
    __block int completedItemCount = 0;
    NSMutableArray* completedObjects = [NSMutableArray arrayWithCapacity:totalItemCount];
    
    KCSSaveGraph* progress = _previousProgress == nil ? [[[KCSSaveGraph alloc] initWithEntityCount:totalItemCount] autorelease] : _previousProgress;
    
    __block NSError* topError = nil;
    __block BOOL done = NO;
    for (id <KCSPersistable> singleEntity in objectsToSave) {
        [self enqueSave:singleEntity];
    }
    //TODO: compress queue=
    [self drainQueueWithProgressGraph:progress doSaveBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
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
        
    } alreadySavedBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
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
    } withProgressBlock:progressBlock];
}

#pragma mark - Removing
- (void) removeObject:(id)object withCompletionBlock:(KCSCompletionBlock)completionBlock withProgressBlock:(KCSProgressBlock)progressBlock
{
    BOOL okayToProceed = [self validatePreconditionsAndSendErrorTo:completionBlock];
    if (okayToProceed == NO) {
        return;
    }
    
    KCSQuery* deleteQuery = nil;
    if ([object isKindOfClass:[KCSQuery class]]) {
        deleteQuery = object;
    } else {
        
        NSArray *objectsToProcess = [NSArray wrapIfNotArray:object];
        if (objectsToProcess.count == 0) {
            completionBlock(nil, nil);
            return;
        }
        
        NSMutableArray* ids = [NSMutableArray arrayWithCapacity:objectsToProcess.count];
        [objectsToProcess enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSString* _id = [obj kinveyObjectId];
            if (_id != nil) {
                [ids addObject:_id];
            }
        }];
        
        deleteQuery = [KCSQuery queryOnField:@"_id" usingConditional:kKCSIn forValue:ids];
    }
    NSString *resource = nil;
    NSString *format = nil;
    
    KCSCollection* collection = self.backingCollection;
    if ([collection.collectionName isEqualToString:@""]){
        format = @"%@";
    } else {
        format = @"%@/";
    }
    
    resource = [collection.baseURL stringByAppendingFormat:format, collection.collectionName];
    
    // Add the Query portion of the request
    if (deleteQuery.query != nil && deleteQuery.query.count > 0){
        resource = [resource stringByAppendingQueryString:[deleteQuery parameterStringRepresentation]];
    }
    
    
    KCSRESTRequest *request = [KCSRESTRequest requestForResource:resource usingMethod:kDeleteRESTMethod];
    
    
    KCSConnectionCompletionBlock cBlock = ^(KCSConnectionResponse *response){
        
        KCSLogTrace(@"In collection callback with response: %@", response);
        NSObject* jsonData = [response jsonResponseValue];
        
        if (response.responseCode != KCS_HTTP_STATUS_NO_CONTENT && response.responseCode != KCS_HTTP_STATUS_OK){
            NSError* error = [KCSErrorUtilities createError:(NSDictionary*)jsonData description:@"Deletion was unsuccessful." errorCode:response.responseCode domain:KCSAppDataErrorDomain];
            completionBlock(nil, error);
            return;
        }
        NSArray* jsonArray = nil;
        if ([jsonData isKindOfClass:[NSArray class]]){
            jsonArray = (NSArray *)jsonData;
        } else {
            if ([(NSDictionary *)jsonData count] == 0){
                jsonArray = @[];
            } else {
                jsonArray = @[jsonData];
            }
        }
        
        completionBlock(jsonArray, nil);
    };
    KCSConnectionFailureBlock fBlock = ^(NSError *error){
        completionBlock(nil, error);
    };
    KCSConnectionProgressBlock pBlock = makeProgressBlock(progressBlock);
    
    // Make the request happen
    [[request withCompletionAction:cBlock failureAction:fBlock progressAction:pBlock] start];
}

#pragma mark - Information
- (void)countWithBlock:(KCSCountBlock)countBlock
{
    [self.backingCollection entityCountWithBlock:countBlock];
}


@end
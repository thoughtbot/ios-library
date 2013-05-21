//
//  KCSEntityCache2.m
//  KinveyKit
//
//  Created by Michael Katz on 5/14/13.
//  Copyright (c) 2013 Kinvey. All rights reserved.
//

#import "KCSEntityCache2.h"
#import "KCSEntityCache.h"

#import "KinveyEntity.h"
#import "KCSObjectMapper.h"
#import "KCSReduceFunction.h"
#import "KCSHiddenMethods.h"
#import "KCSGroup.h"

#import "KCSLogManager.h"
#import "KCS_SBJson.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"

#define KCS_CACHE_VERSION @"0.1"

NSString* cacheKeyForGroup2(NSArray* fields, KCSReduceFunction* function, KCSQuery* condition)
{
    NSMutableString* representation = [NSMutableString string];
    for (NSString* field in fields) {
        [representation appendString:field];
    }
    [representation appendString:[function JSONStringRepresentationForFunction:fields]];
    if (condition != nil) {
        [representation appendString:[condition JSONStringRepresentation]];
    }
    return representation;
}

@interface KCSEntityCache2 ()
@property (nonatomic, strong) FMDatabase* db;
@end

@interface KCSCacheValueDB : NSObject
@property (nonatomic) NSUInteger count;
@property (retain, nonatomic) NSDictionary* object;
@property (nonatomic) BOOL unsaved;
@property (nonatomic, strong) NSDate* lastReadTime;
@property (nonatomic, strong) NSString* objId;
@property (nonatomic, strong) NSString* classname;
@end
@implementation KCSCacheValueDB

- (instancetype) init
{
    self = [super init];
    if (self) {
        _count = 1;
        _lastReadTime = [NSDate date];
    }
    return self;
}

- (NSDictionary*) parameterDict
{
    KCS_SBJsonWriter* writer = [[KCS_SBJsonWriter alloc] init];
    NSError* error = nil;
    NSString* object = [writer stringWithObject:_object error:&error];
    KCSLogNSError(@"Error serialializing dictionary object", error);
    return @{@"id": _objId, @"obj" : object, @"time" : _lastReadTime, @"dirty" : @(_unsaved), @"count" : @(_count), @"classname" : _classname};
}
//TODO: #27 lmt,

@end

@implementation KCSEntityCache2


- (NSString*) dbPath
{
    return [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:[NSString stringWithFormat:@"com.kinvey.%@_cache.sqllite", _persistenceId]];
}

- (instancetype) initWithPersistenceId:(NSString*)key
{
    self = [super init];
    if (self) {
        _persistenceId = key;
        
        [self initDB];
    }
    return self;
}

- (instancetype) init
{
    DBAssert(YES, @"should always init cache v2 with a name");
    return [self initWithPersistenceId:@"null"];
}

- (void) initDB
{
    NSString* path = [self dbPath];
    _db = [FMDatabase databaseWithPath:path];
    if (![_db open]) return;
    
    BOOL e = NO;
    if (![_db tableExists:@"metadata"]) {
        KCSLogCache(@"Creating New Cache %@", path);
        e = [_db executeUpdate:@"CREATE TABLE metadata (id VARCHAR(255) PRIMARY KEY, version VARCHAR(255), time TEXT, data)"];
        if ([_db hadError]) { KCSLogError(@"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);}
        e = [_db executeUpdate:@"INSERT INTO metadata VALUES (:id, :version, :time)" withArgumentsInArray:@[@"1", KCS_CACHE_VERSION, @"2"]];
        if ([_db hadError]) { KCSLogError(@"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);}
    } else {
        FMResultSet *rs = [_db executeQuery:@"SELECT version FROM metadata"];
        if ([_db hadError]) { KCSLogError(@"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);}
        NSString* version = nil;
        if ([rs next]) {
            NSDictionary* d = [rs resultDictionary];
            version = d[@"version"];
        }
        
        if ([version isEqualToString:KCS_CACHE_VERSION] == NO) {
            //TODO: #20 deal with old db        }
        }
    }

    if (![_db tableExists:@"objs"]) {
        e = [_db executeUpdate:@"CREATE TABLE objs (id VARCHAR(255) PRIMARY KEY, obj TEXT, time VARCHAR(255), saved BOOL, count INT, classname TEXT)"];
        if (e == NO) {
            KCSLogError(@"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
    }
    if (![_db tableExists:@"queries"]) {
        e = [_db executeUpdate:@"CREATE TABLE queries (id VARCHAR(255) PRIMARY KEY, ids TEXT)"];
        if (e == NO) {
            KCSLogError(@"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
    }
    if (![_db tableExists:@"groups"]) {
        e = [_db executeUpdate:@"CREATE TABLE groups (key TEXT PRIMARY KEY, results TEXT)"];
        if (e == NO) {
            KCSLogError(@"Err %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
    }
}

- (void)dealloc
{
    [_db close];
}

#pragma mark - objects

- (KCSCacheValueDB*) dbObjectForId:(NSString*) objId
{
    NSString* q = [NSString stringWithFormat:@"SELECT * FROM objs WHERE id='%@'", objId];
    KCSLogCache(@"fetching %@", objId);
    FMResultSet* rs = [_db executeQuery:q];
    if ([_db hadError]) {
        KCSLogError(@"Cache error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }

    KCSCacheValueDB* val = nil;
    if ([rs next]) {
        NSDictionary* d = [rs resultDictionary];
        if (d) {
            val = [[KCSCacheValueDB alloc] init];
            val.object = [d[@"obj"] JSONValue];
            val.objId = d[@"id"];
            val.lastReadTime = d[@"time"];
            val.unsaved = [d[@"dirty"] boolValue];
            val.count = [d[@"count"] integerValue];
            val.classname = d[@"classname"];
        }

    }
    return val;
}

- (id<KCSPersistable>) objectForId:(NSString *)objId
{
    KCSCacheValueDB* dbObj = [self dbObjectForId:objId];
    NSDictionary* objDict = dbObj.object;
    NSString* classname = dbObj.classname;
    id<KCSPersistable> obj = [KCSObjectMapper makeObjectOfType:NSClassFromString(classname) withData:objDict];
    return obj;
}

- (NSArray*) dbObjectsForIds:(NSArray*) objIds
{
    if (objIds.count == 0) return @[];
    
    NSString* q = [NSString stringWithFormat:@"SELECT * FROM objs WHERE id IN ('%@')", [objIds componentsJoinedByString:@"','"]];
    KCSLogCache(@"Retreiving from cache: %@", objIds);
    FMResultSet* rs = [_db executeQuery:q];
    if ([_db hadError]) {
        KCSLogError(@"Cache error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    
    NSMutableArray* objs = [NSMutableArray arrayWithCapacity:objIds.count];
    while ([rs next]) {
        NSDictionary* d = [rs resultDictionary];
        if (d) {
            //TODO #20 combine with above
            KCSCacheValueDB* val = [[KCSCacheValueDB alloc] init];
            val.object = [d[@"obj"] JSONValue];
            val.objId = d[@"id"];
            val.lastReadTime = d[@"time"];
            val.unsaved = [d[@"dirty"] boolValue];
            val.count = [d[@"count"] integerValue];
            val.classname = d[@"classname"];
            [objs addObject:val];
        }
        
    }
    return objs;
}

- (void) insertDbObj:(KCSCacheValueDB*)val
{
    if (val == nil) return;

    KCSLogCache(@"Insert/update %@/%@", _persistenceId, val.objId);

    BOOL upated = [_db executeUpdate:@"REPLACE INTO objs VALUES (:id, :obj, :time, :dirty, :count, :classname)"
             withParameterDictionary:[val parameterDict]];
    if (upated == NO) {
        KCSLogCache(@"Error insert/updating %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
}

- (KCSCacheValueDB*) insertObj:(id<KCSPersistable>)obj
{
    NSError* error = nil;
    KCSSerializedObject* o = [KCSObjectMapper makeKinveyDictionaryFromObject:obj error:&error];
    if (error != nil) {
        KCSLogNSError(@"Error serializing object for cache.", error);
        return nil;
    }
    //TODO #2 - handle references
    //TODO #3 - pass in json directly
    
    KCSCacheValueDB* val = [self dbObjectForId:[o objectId]];
    if (val) {
        val.count++;
        val.object = [o dataToSerialize];
    } else {
        val = [[KCSCacheValueDB alloc] init];
        val.object = [o dataToSerialize];
        val.objId = [o objectId];
        val.classname = NSStringFromClass([obj class]);
    }
    val.lastReadTime = [NSDate date];
    //TODO #25 save lmt - need raw JSON with meta
    
    return val;
}

- (void) removeObj:(NSString*)objId
{
    KCSCacheValueDB* val = [self dbObjectForId:objId];
    val.count--;
    if (val.count == 0) {
        KCSLogCache(@"Deleting obj %@", objId);
        BOOL updated = [_db executeUpdateWithFormat:@"DELETE FROM objs WHERE id='%@'", objId];
        if (updated == NO) {
            KCSLogError(@"Cache error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
    }
}

- (void) addResult:(id<KCSPersistable>)obj
{
    NSString* objId = [(NSObject*)obj kinveyObjectId];
    //TODO #6 do less cross-serialzation, eg parse object fewer times
    if (objId != nil) {
        KCSCacheValueDB* db = [self insertObj:obj];
        db.unsaved = NO;
        [self insertDbObj:db];
    } else {
        KCSLogDebug(@"attempting to cache an object without a set ID");
    }
}

- (void)addResults:(NSArray *)objects
{
    for (id n in objects) {
        [self addResult:n];
    }
}

- (void) removeIds:(NSArray*)keys
{
    for (NSString* key in keys) {
        [self removeObj:key];
    }
}

#pragma mark - Queries
- (NSArray*) idsForQuery:(NSString*) queryKey
{
    NSString* q = [NSString stringWithFormat:@"SELECT ids FROM queries WHERE id='%@'", queryKey];
    NSString* result = [_db stringForQuery:q];
    if ([_db hadError]) {
        KCSLogError(@"Cache error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        return @[];
    } else {
        NSError* error = nil;
        NSArray* ids = [[[KCS_SBJsonParser alloc] init] objectWithString:result error:&error];
        KCSLogNSError(@"Error converting id array string into array", error);
        return ids;
    }
    
}


- (void) removeQuery:(KCSQuery*) query
{
    NSString* queryKey = [query parameterStringRepresentation];
    NSArray* keys = [self idsForQuery:queryKey];
    [self removeIds:keys];
    KCSLogCache(@"Removing stored query: '%@'", queryKey);
    BOOL updated = [_db executeUpdateWithFormat:@"DELETE FROM queries WHERE id='%@'", queryKey];
    if (updated == NO) {
        KCSLogError(@"Cache error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
}

- (void)setResults:(NSArray *)results forQuery:(KCSQuery *)query
{
    NSString* queryKey = [query parameterStringRepresentation];

    NSMutableArray* theseIds = [NSMutableArray arrayWithCapacity:results.count];
    for (id n in results) {
        NSString* objId = [n kinveyObjectId];
        if (objId != nil) {
            [theseIds addObject:objId];
            [self addResult:n];
        }
    }

    NSArray* oldIds = [self idsForQuery:queryKey];
    if (oldIds) {
        NSMutableArray* removedIds = [theseIds mutableCopy];
        [removedIds removeObjectsInArray:oldIds];
        [self removeIds:removedIds];
    }
    
    NSString* jsonStr = [theseIds JSONRepresentation];
    KCSLogCache(@"update query: '%@'", queryKey);
    BOOL updated = [_db executeUpdate:@"REPLACE INTO queries VALUES (:id, :ids)" withArgumentsInArray:@[queryKey, jsonStr]];
    if (updated == NO) {
        KCSLogError(@"Cache error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }

}

//TODO #5 empty results vs not cached
- (NSArray*) resultsForQuery:(KCSQuery*)query
{
    NSString* queryKey = [query parameterStringRepresentation];
    NSArray* ids = [self idsForQuery:queryKey];
    return ids == nil ? nil : [self resultsForIds:ids];
}

- (NSArray*) resultsForIds:(NSArray*)keys
{
    NSMutableArray* vals = [NSMutableArray arrayWithCapacity:keys.count];
    for (KCSCacheValueDB* val in [self dbObjectsForIds:keys]) {
        NSDictionary* objDict = val.object;
        NSString* classname = val.classname;
        id<KCSPersistable> obj = [KCSObjectMapper makeObjectOfType:NSClassFromString(classname) withData:objDict];
        [vals addObject:obj];
    }
    return vals;
}

//TODO #4 - force delete for when items are DELETED from the store

#pragma mark - Grouping
- (void)setResults:(KCSGroup *)results forGroup:(NSArray *)fields reduce:(KCSReduceFunction *)function condition:(KCSQuery *)condition
{
    NSString* key = cacheKeyForGroup2(fields, function, condition);
    NSDictionary* jdict = [results dictionaryValue];
    NSString* jsonStr = [jdict JSONRepresentation];
    KCSLogCache(@"checking cache for group");
    BOOL updated = [_db executeUpdate:@"REPLACE INTO groups VALUES (:key, :results)" withArgumentsInArray:@[key, jsonStr]];
    if (updated == NO) {
        KCSLogError(@"Cache error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
}

- (void)removeGroup:(NSArray *)fields reduce:(KCSReduceFunction *)function condition:(KCSQuery *)condition
{
    NSString* key = cacheKeyForGroup2(fields, function, condition);
    KCSLogCache(@"Remove group from cache");
    NSString* q = [NSString stringWithFormat:@"DELETE FROM groups WHERE key='%@'", key];
    BOOL updated = [_db executeUpdate:q];
    if (updated == NO) {
        KCSLogError(@"Cache error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
}

#pragma mark - Saving
- (void) addUnsavedObject:(id)obj
{
    NSString* objId = [obj kinveyObjectId];
    if (objId == nil) {
        objId = KCSMongoObjectId();
        KCSLogDebug(@"attempting to save a new object to the backend - assigning '%@' as _id", objId);
        [obj setKinveyObjectId:objId];
    }
    if (objId != nil) {
        //TODO #22 combine with add query result
        KCSCacheValueDB* val = [self insertObj:obj];
        val.unsaved = YES;
        val.lastReadTime = [NSDate date];
        //TODO #21 [_unsavedObjs addObject:objId];
        [self insertDbObj:val];
    } else {
        KCSLogDebug(@"attempting to cache an object without a set ID");
    }
    
}


#pragma mark - Management
- (void) clearCaches
{
    KCSLogCache(@"Clearing Caches");
    [_db close];
    
    NSError* error = nil;
    
    NSURL* url = [NSURL fileURLWithPath:[self dbPath]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[url path]]) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:&error];
    }
    DBAssert(!error, @"error clearing cache: %@", error);
    
    [self initDB];
}
@end

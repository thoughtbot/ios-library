//
//  Migration.swift
//  Kinvey
//
//  Created by Victor Barros on 2016-03-22.
//  Copyright © 2016 Kinvey. All rights reserved.
//

import Foundation
import RealmSwift

/// Class used to perform migrations in your local cache.
@objc(KNVMigration)
public class Migration: NSObject {
    
    public typealias MigrationHandler = (migration: Migration, schemaVersion: CUnsignedLongLong) -> Void
    public typealias MigrationObjectHandler = (oldEntity: JsonDictionary) -> JsonDictionary?
    
    let realmMigration: RealmSwift.Migration
    
    init(realmMigration: RealmSwift.Migration) {
        self.realmMigration = realmMigration
    }
    
    /// Method that performs a migration in a specific collection.
    public func execute(persistableClass: AnyClass, migrationObjectHandler: MigrationObjectHandler? = nil) {
//        let realmClassName = RealmEntitySchema.realmClassNameForClass(persistableClass)
//        let oldObjectSchema = realmMigration.oldSchema[realmClassName]
//        if let oldObjectSchema = oldObjectSchema {
//            let oldProperties = oldObjectSchema.properties.map { $0.name }
//            
//            realmMigration.enumerate(realmClassName) { (oldObject, newObject) in
//                if let oldObject = oldObject {
//                    let oldDictionary = oldObject.dictionaryWithValuesForKeys(oldProperties)
//                    
//                    let newDictionary = migrationObjectHandler?(oldEntity: oldDictionary)
//                    if let newObject = newObject {
//                        self.realmMigration.delete(newObject)
//                    }
//                    if let newDictionary = newDictionary {
//                        self.realmMigration.create(realmClassName, value: newDictionary)
//                    }
//                }
//            }
//        }
    }
    
}

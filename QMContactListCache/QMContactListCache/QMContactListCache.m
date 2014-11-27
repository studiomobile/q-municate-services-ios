//
//  QMContactListCache.m
//  QMContactListCache
//
//  Created by Andrey on 06.11.14.
//
//

#import "QMContactListCache.h"
#import "ModelIncludes.h"

@implementation QMContactListCache

static QMContactListCache *_chatCacheInstance = nil;

#pragma mark - Singleton

+ (QMContactListCache *)instance {
    
    NSAssert(_chatCacheInstance, @"You must first perform @selector(setupDBWithStoreNamed:)");
    return _chatCacheInstance;
}

#pragma mark - Configure store

+ (void)setupDBWithStoreNamed:(NSString *)storeName {
    
    NSManagedObjectModel *model =
    [NSManagedObjectModel QM_newModelNamed:@"QMContactListModel.momd"
                             inBundleNamed:@"QMContactListCacheModel.bundle"];
    
    _chatCacheInstance =
    [[QMContactListCache alloc] initWithStoreNamed:storeName
                                             model:model
                                        queueLabel:"com.qmunicate.QMContactListCacheBackgroundQueue"];
}

+ (void)cleanDBWithStoreName:(NSString *)name {
    
    if (_chatCacheInstance) {
        _chatCacheInstance = nil;
    }
    
    [super cleanDBWithStoreName:name];
}

#pragma mark -
#pragma mark Dialogs
#pragma mark -
#pragma mark Insert / Update / Delete contact items

- (void)insertOrUpdateContactListItem:(QBContactListItem *)contactListItem
                           completion:(void(^)(void))completion {
    
    __weak __typeof(self)weakSelf = self;
    [self async:^(NSManagedObjectContext *context) {
        
        CDContactListItem *cachedContactListItem =
        [CDContactListItem QM_findFirstWithPredicate:IS(@"userID", @(contactListItem.userID))
                                           inContext:context];
        if (cachedContactListItem) {
            //Update if needed
            if (![cachedContactListItem isEqual:contactListItem]) {
                
                [cachedContactListItem updateWithQBContactListItem:contactListItem];
                NSLog(@"Update contactListItem (userID - %ul)", contactListItem.userID);
            }
        }
        else {
            //Insert new contact list item
            CDContactListItem *contactListItemToInsert =
            [CDContactListItem QM_createEntityInContext:context];
            
            [contactListItemToInsert updateWithQBContactListItem:contactListItem];
            NSLog(@"Insert New contactListItem (userID - %ul)", contactListItem.userID);
        }
        
        [weakSelf save:completion];
    }];
}

- (void)insertOrUpdateContactListWithItems:(NSArray *)contactListItems
                                completion:(void(^)(void))completion {
    
    __weak __typeof(self)weakSelf = self;
    [self async:^(NSManagedObjectContext *context) {
        
        NSMutableArray *toInsert = [NSMutableArray array];
        NSMutableArray *toUpdate = [NSMutableArray array];
        
        //To Insert / Update
        for (QBContactListItem *contactListItem in contactListItems) {
            
            CDContactListItem *cachedContactListItem =
            [CDContactListItem QM_findFirstWithPredicate:IS(@"userID", @(contactListItem.userID))
                                               inContext:context];
            if (cachedContactListItem) {
                [toUpdate addObject:contactListItem];
            }
            else {
                
                [toInsert addObject:contactListItem];
            }
        }
        
        if (toUpdate.count > 0) {
            
            [weakSelf updateContactListItems:toUpdate
                                   inContext:context];
        }
        
        if (toInsert.count > 0) {
            
            [weakSelf insertContactListItems:toInsert
                                   inContext:context];
        }
        
        if (toInsert.count + toUpdate.count > 0) {
            [weakSelf save:completion];
        }
        
        NSLog(@"ContactListItems to insert %lu", (unsigned long)toInsert.count);
        NSLog(@"ContactListItems to update %lu", (unsigned long)toUpdate.count);
    }];
}

- (void)insertOrUpdateContactListItemsWithContactList:(QBContactList *)contactList
                                           completion:(void(^)(void))completion {
    NSMutableArray *items =
    [NSMutableArray arrayWithCapacity:contactList.contacts.count + contactList.pendingApproval.count];
    
    [items addObjectsFromArray:contactList.contacts];
    [items addObjectsFromArray:contactList.pendingApproval];
    
    [self insertOrUpdateContactListWithItems:items
                                  completion:completion];
}

- (void)insertContactListItems:(NSArray *)contactListItems
                     inContext:(NSManagedObjectContext *)context {
    
    for (QBContactListItem *contactListItem in contactListItems) {
        
        CDContactListItem *cdContactListItem =
        [CDContactListItem QM_createEntityInContext:context];
        
        [cdContactListItem updateWithQBContactListItem:contactListItem];
    }
}

- (void)updateContactListItems:(NSArray *)contactListItems
                     inContext:(NSManagedObjectContext *)context {
    
    for (QBContactListItem *contactListItem in contactListItems) {
        
        CDContactListItem *cachedContactListItem =
        [CDContactListItem QM_findFirstWithPredicate:IS(@"userID", @(contactListItem.userID))
                                           inContext:context];
        
        [cachedContactListItem updateWithQBContactListItem:contactListItem];
    }
}

- (void)deleteContactListItem:(QBContactListItem *)contactListItem
                   completion:(void(^)(void))completion {
    
    __weak __typeof(self)weakSelf = self;
    
    [self async:^(NSManagedObjectContext *context) {
        
        CDContactListItem *cdContactListItem =
        [CDContactListItem QM_findFirstWithPredicate:IS(@"userID", @(contactListItem.userID))
                                           inContext:context];
        
        [cdContactListItem QM_deleteEntityInContext:context];
        
        [weakSelf save:^{
            
            if (completion) {
                completion();
            }
        }];
    }];
}

- (void)deleteContactList:(void(^)(void))completion {
    
    __weak __typeof(self)weakSelf = self;
    [self async:^(NSManagedObjectContext *context) {
        
        [CDContactListItem QM_truncateAllInContext:context];
        
        [weakSelf save:^{
            
            if (completion) {
                completion();
            }
        }];
    }];
}

#pragma mark Fetch ContactList operations

- (NSArray *)convertCDContactListItemsToQBContactListItems:(NSArray *)cdContactListItems {
    
    NSMutableArray *contactListItems =
    [NSMutableArray arrayWithCapacity:cdContactListItems.count];
    
    for (CDContactListItem *cachedContactListItem in cdContactListItems) {
        
        QBContactListItem *contactListItem =
        [cachedContactListItem toQBContactListItem];
        
        [contactListItems addObject:contactListItem];
    }
    
    return contactListItems;
}

- (void)contactListItems:(void(^)(NSArray *contactListItems))completion{
    
    __weak __typeof(self)weakSelf = self;
    [self async:^(NSManagedObjectContext *context) {
        
        NSArray *cachedContactListItems =
        [CDContactListItem QM_findAllInContext:context];
        
        NSArray *contactListItems =
        [weakSelf convertCDContactListItemsToQBContactListItems:cachedContactListItems];
        
        DO_AT_MAIN(completion(contactListItems));
    }];
}

- (void)contactListItemsWithUserID:(NSUInteger)userID
                        completion:(void(^)(QBContactListItem *))completion {
    
    [self async:^(NSManagedObjectContext *context) {
        
        CDContactListItem *cachedContactListItem =
        [CDContactListItem QM_findFirstWithPredicate:IS(@"userID", @(userID))
                                           inContext:context];
        
        QBContactListItem *item = [cachedContactListItem toQBContactListItem];
        
        completion(item);
    }];
}

#pragma mark -
#pragma mark  Users
#pragma mark -
#pragma mark Insert / Update / Delete users

- (void)insertOrUpdateUser:(QBUUser *)user
                completion:(void(^)(void))completion {
    
    __weak __typeof(self)weakSelf = self;
    
    [self async:^(NSManagedObjectContext *context) {
        
        CDUser *cachedUser =
        [CDUser QM_findFirstWithPredicate:IS(@"id", @(user.ID))
                                inContext:context];
        if (cachedUser) {
            //Update if needed
            QBUUser *qbUser = [cachedUser toQBUUser];
            
            if (![user isEqual:qbUser]) {
                
                [cachedUser updateWithQBUser:qbUser];
                NSLog(@"Update user in cache (user id - %ul)", user.ID);
            }
        }
        else {
            //Insert new user
            CDUser *userToUpdate =
            [CDUser QM_createEntityInContext:context];
            
            [userToUpdate updateWithQBUser:user];
            NSLog(@"Insert new user in cache (user id - %ul)", user.ID);
        }
        
        [weakSelf save:completion];
    }];
}

- (void)insertOrUpdateUsers:(NSArray *)users
                 completion:(void(^)(void))completion {
    
    __weak __typeof(self)weakSelf = self;
    
    [self async:^(NSManagedObjectContext *context) {
        
        NSMutableArray *toInsert = [NSMutableArray array];
        NSMutableArray *toUpdate = [NSMutableArray array];
        
        //To Insert / Update
        for (QBUUser *user in users) {
            
            CDUser *cachedUser =
            [CDUser QM_findFirstWithPredicate:IS(@"id", user.ID)
                                    inContext:context];
            if (cachedUser) {
                
                [toUpdate addObject:user];
            }
            else {
                
                [toInsert addObject:user];
            }
        }
        
        if (toUpdate.count > 0) {
            
            [weakSelf updateUsers:toUpdate
                        inContext:context];
        }
        
        if (toInsert.count > 0) {
            
            [weakSelf insertUsers:toInsert
                        inContext:context];
        }
        
        if (toInsert.count + toUpdate.count > 0) {
            [weakSelf save:completion];
        }
        
        NSLog(@"Users to insert %lu", (unsigned long)toInsert.count);
        NSLog(@"Users to update %lu", (unsigned long)toUpdate.count);
        
    }];
}

- (void)insertUsers:(NSArray *)users
          inContext:(NSManagedObjectContext *)context {
    
    for (QBUUser *user in users) {
        
        CDUser *newUser = [CDUser QM_createEntityInContext:context];
        [newUser updateWithQBUser:user];
    }
}

- (void)updateUsers:(NSArray *)qbUsers
          inContext:(NSManagedObjectContext *)context {
    
    for (QBUUser *qbUser in qbUsers) {
        
        CDUser *userToUpdate =
        [CDUser QM_findFirstWithPredicate:IS(@"id", @(qbUser.ID))
                                inContext:context];
        
        [userToUpdate updateWithQBUser:qbUser];
    }
}

- (NSArray *)convertCDUsertsToQBUsers:(NSArray *)cdUsers {
    
    NSMutableArray *users =
    [NSMutableArray arrayWithCapacity:cdUsers.count];
    
    for (CDUser *user in cdUsers) {
        
        QBUUser *qbUser = [user toQBUUser];
        [users addObject:qbUser];
    }
    
    return users;
}

- (void)deleteUser:(QBUUser *)user
        completion:(void(^)(void))completion {
    
    __weak __typeof(self)weakSelf = self;
    
    [self async:^(NSManagedObjectContext *context) {
        
        CDUser *cachedUser =
        [CDUser QM_findFirstWithPredicate:IS(@"id", @(user.ID))
                                inContext:context];
        
        [cachedUser QM_deleteEntityInContext:context];
        
        [weakSelf save:^{
            
            if (completion) {
                completion();
            }
        }];
    }];
}

- (void)deleteAllUsers:(void(^)(void))completion {
    
    __weak __typeof(self)weakSelf = self;
    [self async:^(NSManagedObjectContext *context) {
        
        [CDUser QM_truncateAllInContext:context];
        
        [weakSelf save:^{
            
            if (completion) {
                completion();
            }
        }];
    }];
}

#pragma mark Fetch users operations

- (void)userWithPredicate:(NSPredicate *)predicate
               completion:(void(^)(QBUUser *user))completion {
    
    [self async:^(NSManagedObjectContext *context) {
        
        CDUser *user = [CDUser QM_findFirstWithPredicate:predicate];
        QBUUser *result = [user toQBUUser];
        
        DO_AT_MAIN(completion(result));
    }];
}

- (void)usersSortedBy:(NSString *)sortTerm
            ascending:(BOOL)ascending
           completion:(void(^)(NSArray *users))completion {
    
    [self usersWithPredicate:nil
                    sortedBy:sortTerm
                   ascending:ascending
                  completion:completion];
}

- (void)usersWithPredicate:(NSPredicate *)predicate
                  sortedBy:(NSString *)sortTerm
                 ascending:(BOOL)ascending
                completion:(void(^)(NSArray *users))completion {
    
    __weak __typeof(self)weakSelf = self;
    [self async:^(NSManagedObjectContext *context) {
        
        NSArray *users = [CDUser QM_findAllSortedBy:sortTerm
                                          ascending:ascending
                                      withPredicate:predicate
                                          inContext:context];
        
        NSArray *result = [weakSelf convertCDUsertsToQBUsers:users];
        
        DO_AT_MAIN(completion(result));
    }];
}

@end
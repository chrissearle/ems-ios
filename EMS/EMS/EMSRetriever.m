//
//  EMSRetriever.m
//

#import "EMSRetriever.h"

#import "EMSConferencesRetriever.h"
#import "EMSSlotsRetriever.h"
#import "EMSSessionsRetriever.h"
#import "EMSRoomsRetriever.h"
#import "EMSSpeakersRetriever.h"
#import "EMSConfig.h"

#import "EMSAppDelegate.h"

#import "EMSModel.h"
#import "EMSConference.h"

@interface EMSRetriever () <EMSRetrieverDelegate>

@property(readwrite) BOOL refreshingConferences;
@property(readwrite) BOOL refreshingSessions;

@end



@implementation EMSRetriever

+ (instancetype)sharedInstance {
    static EMSRetriever *instance = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[EMSRetriever alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _refreshingConferences = NO;
        _refreshingSessions = NO;
        
        _refreshingSlots = NO;
        _refreshingRooms = NO;
        
    }
    return self;
}


- (Conference *)conferenceForHref:(NSString *)href {
    CLS_LOG(@"Getting conference for %@", href);
    
    return [[[EMSAppDelegate sharedAppDelegate] model] conferenceForHref:href];
}

- (Conference *)activeConference {
    CLS_LOG(@"Getting current conference");
    
    NSString *activeConference = [[EMSAppDelegate currentConference] absoluteString];
    
    if (activeConference != nil) {
        return [self conferenceForHref:activeConference];
    }
    
    return nil;
}


- (void)refreshConferences {
    NSAssert([NSThread isMainThread], @"Should be called on main thread.");
    
    self.refreshingConferences = YES;
    
    EMSConferencesRetriever *retriever = [[EMSConferencesRetriever alloc] init];

    retriever.delegate = self;
    
    [retriever fetch:[EMSConfig emsRootUrl]];

}

- (void)finishedConferences:(NSArray *)conferences forHref:(NSURL *)href {
    
    NSError *error = nil;
    
    EMSModel *backgroundModel = [[EMSAppDelegate sharedAppDelegate] modelForBackground];
    
    if (![backgroundModel storeConferences:conferences error:&error]) {
        CLS_LOG(@"Failed to store conferences %@ - %@", error, [error userInfo]);
    }
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        [[EMSAppDelegate sharedAppDelegate] syncManagedObjectContext];
        
        self.refreshingConferences = NO;
    
        NSArray *filteredConferences = [conferences filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            EMSConference *emsConference = evaluatedObject;
            return  [emsConference.hintCount longValue] > 0;
        }]];
        
        NSArray *sortedConferences = [filteredConferences sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(id obj1, id obj2) {
            EMSConference *emsConference1 = obj1;
            EMSConference *emsConference2 = obj2;
            
            return [emsConference1.start compare:emsConference2.start];
        }];
        EMSConference *latestConference = sortedConferences.lastObject;
        
        
        [EMSAppDelegate storeCurrentConference:latestConference.href];
        
    });
    
    
    
    
}

#pragma mark - retrieval

- (void)refreshActiveConference {
    
    self.refreshingSessions = YES;
    
    Conference *activeConference = [self activeConference];
    
    CLS_LOG(@"Starting retrieval");
    
    if (activeConference != nil) {
        CLS_LOG(@"Starting retrieval - saw conf");
        
        if (activeConference.slotCollection != nil) {
            CLS_LOG(@"Starting retrieval - saw slot collection");
            _refreshingSlots = YES;
            [self refreshSlots:[NSURL URLWithString:activeConference.slotCollection]];
        }
        if (activeConference.roomCollection != nil) {
            CLS_LOG(@"Starting retrieval - saw room collection");
            _refreshingRooms = YES;
            [self refreshRooms:[NSURL URLWithString:activeConference.roomCollection]];
        }
    }
}

- (void)retrieveSessions {
    CLS_LOG(@"Starting retrieval of sessions");
    // Fetch sessions once rooms and slots are done. Don't want to get into a state when trying to persist sessions that it refers to non-existing room or slot
    if (!_refreshingRooms && !_refreshingSlots) {
        CLS_LOG(@"Starting retrieval of sessions - clear to go");
        Conference *activeConference = [self activeConference];
        [self refreshSessions:[NSURL URLWithString:activeConference.sessionCollection]];
    }
}

- (void)finishedSlots:(NSArray *)slots forHref:(NSURL *)href {
    CLS_LOG(@"Storing slots %lu", (unsigned long) [slots count]);
    
    NSError *error = nil;
    
    EMSModel *backgroundModel = [[EMSAppDelegate sharedAppDelegate] modelForBackground];
    
    if (![backgroundModel storeSlots:slots forHref:[href absoluteString] error:&error]) {
        CLS_LOG(@"Failed to store slots %@ - %@", error, [error userInfo]);
    }
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        _refreshingSlots = NO;
        
        [self retrieveSessions];
    });
}

- (void)finishedSessions:(NSArray *)sessions forHref:(NSURL *)href {
    CLS_LOG(@"Storing sessions %lu", (unsigned long) [sessions count]);
    
    NSError *error = nil;
    
    EMSModel *backgroundModel = [[EMSAppDelegate sharedAppDelegate] modelForBackground];
    
    if (![backgroundModel storeSessions:sessions forHref:[href absoluteString] error:&error]) {
        CLS_LOG(@"Failed to store sessions %@ - %@", error, [error userInfo]);
    }
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        [[EMSAppDelegate sharedAppDelegate] syncManagedObjectContext];
        
        self.refreshingSessions = NO;
    });
}

- (void)finishedRooms:(NSArray *)rooms forHref:(NSURL *)href {
    CLS_LOG(@"Storing rooms %lu", (unsigned long) [rooms count]);
    
    NSError *error = nil;
    
    EMSModel *backgroundModel = [[EMSAppDelegate sharedAppDelegate] modelForBackground];
    
    if (![backgroundModel storeRooms:rooms forHref:[href absoluteString] error:&error]) {
        CLS_LOG(@"Failed to store rooms %@ - %@", error, [error userInfo]);
    }
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        _refreshingRooms = NO;
        
        [self retrieveSessions];
    });
}




- (void)refreshSlots:(NSURL *)slotCollection {
    EMSSlotsRetriever *retriever = [[EMSSlotsRetriever alloc] init];

    retriever.delegate = self;

    [retriever fetch:slotCollection];
}

- (void)refreshSessions:(NSURL *)sessionCollection {
    EMSSessionsRetriever *retriever = [[EMSSessionsRetriever alloc] init];

    retriever.delegate = self;

    [retriever fetch:sessionCollection];
}

- (void)refreshRooms:(NSURL *)roomCollection {
    EMSRoomsRetriever *retriever = [[EMSRoomsRetriever alloc] init];

    retriever.delegate = self;

    [retriever fetch:roomCollection];
}

- (void)refreshSpeakers:(NSURL *)speakerCollection {
    EMSSpeakersRetriever *retriever = [[EMSSpeakersRetriever alloc] init];

    retriever.delegate = self.delegate;

    [retriever fetch:speakerCollection];
}

@end

//
//  EMSNotificationManager.m
//  EMS
//
//  Created by Jobb on 22.08.14.
//  Copyright (c) 2014 Chris Searle. All rights reserved.
//

#import "EMSLocalNotificationManager.h"
#import "EMSAppDelegate.h"
#import "EMSMainViewController.h"
#import "EMSDetailViewController.h"
#import "EMSTracking.h"
#import "Session.h"
#import "Room.h"

// This class is not Thread safe. Call all methods on main Thread.

NSString *const EMSUserRequestedSessionNotification = @"EMSUserRequestedSessionNotification";
NSString *const EMSUserRequestedSessionNotificationSessionKey = @"EMSUserRequestedSessionNotificationSessionKey";


@interface EMSLocalNotificationManager ()<UIAlertViewDelegate, NSFetchedResultsControllerDelegate>
@property(nonatomic) NSFetchedResultsController *fetchedResultsController;
@end

@implementation EMSLocalNotificationManager {
    @private
    
    NSMutableDictionary *_notificationDictionary;

    NSInteger _nextAlertViewTag;
    
}

- (id)init {
    self = [super init];
    if (self) {
        _notificationDictionary = [NSMutableDictionary dictionary];
        _nextAlertViewTag = 0;
    }
    return self;
}


+ (EMSLocalNotificationManager *) sharedInstance {
    
    static EMSLocalNotificationManager *sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[EMSLocalNotificationManager alloc] init];
    });
    
    return sharedInstance;
}

- (void)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    if ([EMSFeatureConfig isFeatureEnabled:fLocalNotifications]) {
        [EMSTracking trackEventWithCategory:@"system" action:@"notification" label:@"initialize"];
        
        [self initializeFetchedResultsController];
        
        UILocalNotification *notification = launchOptions[UIApplicationLaunchOptionsLocalNotificationKey];
        if (notification) {
            [self activateWithNotification:notification];
        }
    }
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    if ([EMSFeatureConfig isFeatureEnabled:fLocalNotifications]) {
        
        [EMSTracking trackEventWithCategory:@"system" action:@"notification" label:@"receive"];
        
        NSString *sessionUrl = [notification userInfo][@"sessionhref"];
        
        Session *session = [[[EMSAppDelegate sharedAppDelegate] model] sessionForHref:sessionUrl];
        
        if (!session) {
            //If we don´t find a session we assume database have been deleted together with favorites, so no need to continue.
            return;
        }
        
        UIApplicationState state = [[UIApplication sharedApplication] applicationState];
        if (state == UIApplicationStateActive) {
            [self presentLocalNotificationAlert:notification];
        } else {
            //Notification received when running in background, the system already showed an alert.
            [self activateWithNotification:notification];
        }
        
    }
}

#pragma mark - Present Session

- (void)activateWithNotification:(UILocalNotification *)notification {
    
    if (![EMSFeatureConfig isFeatureEnabled:fLocalNotifications]) {
        return;
    }
    
    
    NSDictionary *userInfo = @{EMSUserRequestedSessionNotificationSessionKey: notification.userInfo[@"sessionhref"]};
    [[NSNotificationCenter defaultCenter] postNotificationName:EMSUserRequestedSessionNotification object:self userInfo:userInfo];
    
    }



#pragma mark - Present Notification

- (void)presentLocalNotificationAlert:(UILocalNotification *)notification {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Reminder", @"Title for local notification about upcoming session.")
                                                    message:notification.alertBody
                                                   delegate:self cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                          otherButtonTitles:notification.alertAction, nil];
    
    alert.delegate = self;
    alert.tag = _nextAlertViewTag++;
    
    _notificationDictionary[@(alert.tag)] = notification;
    
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.firstOtherButtonIndex) {
        
        UILocalNotification *notification = _notificationDictionary[@(alertView.tag)];
        
        if (notification) {
            [_notificationDictionary removeObjectForKey:@(alertView.tag)];
            
            
           
            [self activateWithNotification:notification];
        }
    }
    
}

#pragma mark - Favorite session tracking

- (void)initializeFetchedResultsController {
    NSError *error;
    
    if (![[self fetchedResultsController] performFetch:&error]) {
        EMS_LOG(@"Unresolved error when trying to find favorite sessions. (%@, %@)", error, [error userInfo]);
    }
    
    [self updateAllNotifications];

}

- (NSFetchedResultsController *)fetchedResultsController {
    if (_fetchedResultsController != nil) {
        return _fetchedResultsController;
    }
    
    NSManagedObjectContext *managedObjectContext = [[EMSAppDelegate sharedAppDelegate] uiManagedObjectContext];
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription
                                   entityForName:@"Session" inManagedObjectContext:managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSSortDescriptor *sortTime = [[NSSortDescriptor alloc]
                                  initWithKey:@"slot.start" ascending:YES];
    
    [fetchRequest setSortDescriptors:@[sortTime]];
    [fetchRequest setFetchBatchSize:20];
    
    NSArray *predicates = @[[NSPredicate predicateWithFormat:@"(state == %@)", @"approved"],
                            [NSPredicate predicateWithFormat:@"favourite = %@", @YES]];
    
    [fetchRequest setPredicate:[NSCompoundPredicate andPredicateWithSubpredicates:predicates]];
    
    
    NSFetchedResultsController *theFetchedResultsController =
    [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                        managedObjectContext:managedObjectContext sectionNameKeyPath:@"sectionTitle"
                                                   cacheName:nil];
    
    theFetchedResultsController.delegate = self;
    
    
    self.fetchedResultsController = theFetchedResultsController;
    
    return _fetchedResultsController;
}


- (void)updateAllNotifications {
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
    NSArray *sessions = self.fetchedResultsController.fetchedObjects;
    for (Session *session in sessions) {
        [self addNotification:session];
    }
}

- (void)addNotification:(Session *)session {
    UILocalNotification *notification = [[UILocalNotification alloc] init];
    
    NSDate *sessionStart = [self fiveMinutesBefore:[self dateForSession:session]];
    
    NSComparisonResult result = [[[NSDate alloc] init] compare:sessionStart];
    
    if (result == NSOrderedAscending) {
        NSDateFormatter *startTimeFormatter = [[NSDateFormatter alloc] init];
        startTimeFormatter.dateStyle = NSDateFormatterNoStyle;
        startTimeFormatter.timeStyle = NSDateFormatterShortStyle;
        
        NSString *formattedStartTime = [startTimeFormatter stringFromDate:session.slot.start];
        NSString *alertMessage = [NSString stringWithFormat:NSLocalizedString(@"\"%@\" in %@ at %@.", @"{Session title} in {Room name} at {time}. (Local notification)"),
                                  session.title,
                                  session.room.name, formattedStartTime];
        
        notification.fireDate = sessionStart;
        notification.alertBody = alertMessage;
        notification.alertAction = NSLocalizedString(@"Open", @"Open session Local Notification action.");
        notification.soundName = UILocalNotificationDefaultSoundName;
        notification.userInfo = @{@"sessionhref" : session.href};
        
        EMS_LOG(@"Adding notification %@ for session %@ to notifications", notification, session);
        
        [[UIApplication sharedApplication] scheduleLocalNotification:notification];
    }
}

- (void)removeNotification:(Session *)session {
    EMS_LOG(@"Trying to remove notification for session %@ with ID %@", session, session.href);
    
    NSArray *notifications = [[UIApplication sharedApplication] scheduledLocalNotifications];
    
    for (UILocalNotification *notification in notifications) {
        if ([notification.userInfo[@"sessionhref"] isEqualToString:session.href]) {
            EMS_LOG(@"Removing notification at %@ from notifications", notification);
            [[UIApplication sharedApplication] cancelLocalNotification:notification];
        }
    }
}

- (NSDate *)fiveMinutesBefore:(NSDate *)date {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *offsetComponents = [[NSDateComponents alloc] init];
    [offsetComponents setMinute:-5];
    return [calendar dateByAddingComponents:offsetComponents toDate:date options:0];
}

- (NSDate *)dateForSession:(Session *)session {
#ifdef USE_TEST_DATE
    EMS_LOG(@"WARNING - RUNNING IN USE_TEST_DATE mode");
    
    // In debug mode we will use the current day but always the start time of the slot. Otherwise we couldn't test until JZ started ;)
    
    NSDate *sessionDate = session.slot.start;
    
    EMS_LOG(@"Saw session date of %@", sessionDate);
    
    NSCalendar *calendar = [NSCalendar currentCalendar];
    
    NSDateComponents *timeComp = [calendar components:NSHourCalendarUnit | NSMinuteCalendarUnit fromDate:sessionDate];
    NSDateComponents *dateComp = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:[[NSDate alloc] init]];
    
    NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
    [inputFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss ZZ"];
    [inputFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    
    return [inputFormatter dateFromString:[NSString stringWithFormat:@"%04ld-%02ld-%02ld %02ld:%02ld:00 +0200", (long) [dateComp year], (long) [dateComp month], (long) [dateComp day], (long) [timeComp hour], (long) [timeComp minute]]];
#else
    return session.slot.start;
#endif
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type newIndexPath:(NSIndexPath *)newIndexPath {
    
    Session *session = anObject;
    
    switch (type) {
        case NSFetchedResultsChangeDelete:
            [self removeNotification:session];
            break;
        case NSFetchedResultsChangeInsert:
            [self addNotification:session];
            break;
        case NSFetchedResultsChangeMove:
            //Change in slot. 
            [self removeNotification:session];
            [self addNotification:session];
            break;
        case NSFetchedResultsChangeUpdate:
            //I´m not sure this matter, as an change to favorite status
            //would result in either delete or insert and change to slot would
            //result in a move.
            [self removeNotification:session];
            [self addNotification:session];
            break;
        default:
            break;
    }
}

@end

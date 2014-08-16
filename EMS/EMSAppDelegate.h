//
//  EMSAppDelegate.h
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>
#import "EMSModel.h"

#ifndef DO_NOT_USE_CRASHLYTICS
@interface EMSAppDelegate : UIResponder <UIApplicationDelegate, CrashlyticsDelegate>
#else
@interface EMSAppDelegate : UIResponder <UIApplicationDelegate>
#endif

@property(strong, nonatomic) UIWindow *window;

@property(nonatomic, strong) NSManagedObjectContext *managedObjectContext;
@property(nonatomic, strong) NSManagedObjectContext *uiManagedObjectContext;
@property(nonatomic, strong) NSManagedObjectModel *managedObjectModel;
@property(nonatomic, strong) NSPersistentStoreCoordinator *persistentStoreCoordinator;

@property(nonatomic, strong) EMSModel *model;

- (NSURL *)applicationDocumentsDirectory;

- (NSURL *)applicationCacheDirectory;

+ (EMSAppDelegate *)sharedAppDelegate;

- (void)startNetwork;

- (void)stopNetwork;

+ (void)storeCurrentConference:(NSURL *)href;

+ (NSURL *)currentConference;

- (EMSModel *)modelForBackground;

- (void)syncManagedObjectContext;

#ifndef DO_NOT_USE_CRASHLYTICS
- (void)crashlyticsDidDetectCrashDuringPreviousExecution:(Crashlytics *)crashlytics;
#endif

@end

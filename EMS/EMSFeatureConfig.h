//
//  EMSFeatureConfig.h
//

#import <Foundation/Foundation.h>

@interface EMSFeatureConfig : NSObject

typedef enum EMSFeature : NSUInteger {
    fLocalNotifications, fBioPics, fLinks, fRemoteNotifications
} EMSFeature;

+ (BOOL)isFeatureEnabled:(EMSFeature)feature;

+ (BOOL)isCrashlyticsEnabled;
+ (BOOL)isGoogleAnalyticsEnabled;
+ (BOOL)isParseEnabled;

+ (NSDictionary *)getKeys;

- (void)refreshConfigFile;

@end

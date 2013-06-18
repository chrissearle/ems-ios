//
//  EMSRetrieverDelegate.h
//

#import <Foundation/Foundation.h>

@protocol EMSRetrieverDelegate <NSObject>

@optional

- (void) finishedConferences:(NSArray *)conferences forHref:(NSURL *)href;
- (void) finishedSlots:(NSArray *)slots forHref:(NSURL *)href;
- (void) finishedRooms:(NSArray *)rooms forHref:(NSURL *)href;
- (void) finishedSessions:(NSArray *)sessions forHref:(NSURL *)href;
- (void) finishedSpeakers:(NSArray *)speakers forHref:(NSURL *)href;

@end

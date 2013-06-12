//
//  EMSConference.h
//  TestRig
//
//  Created by Chris Searle on 07.06.13.
//
//

#import <Foundation/Foundation.h>

@interface EMSConference : NSObject

@property (strong, nonatomic) NSString *name;
@property (strong, nonatomic) NSString *slug;

@property (strong, nonatomic) NSDate   *start;
@property (strong, nonatomic) NSDate   *end;

@property (strong, nonatomic) NSURL *href;

@property (strong, nonatomic) NSURL *slotCollection;
@property (strong, nonatomic) NSURL *roomCollection;
@property (strong, nonatomic) NSURL *sessionCollection;


@end

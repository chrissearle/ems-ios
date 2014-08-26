//
// EMSRootParser.h
//

#import <Foundation/Foundation.h>
#import "EMSRetrieverDelegate.h"


@interface EMSRootParser : NSObject

@property(nonatomic, weak) id <EMSRetrieverDelegate> delegate;

- (void)parseData:(NSData *)data forHref:(NSURL *)url;

@end
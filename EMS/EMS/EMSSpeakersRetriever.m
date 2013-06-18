//
//  EMSSpeakersRetriever.m
//

#import "EMSSpeakersRetriever.h"
#import "EMSSpeaker.h"

#import "CJCollection.h"
#import "CJItem.h"

@implementation EMSSpeakersRetriever

- (void)fetchedSpeakers:(NSData *)responseData forHref:(NSURL *)href {
    CJCollection *collection = [CJCollection collectionForNSData:responseData];
    
    NSMutableArray *temp = [[NSMutableArray alloc] init];
    
    [collection.items enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        CJItem *item = (CJItem *)obj;
        
        EMSSpeaker *speaker = [[EMSSpeaker alloc] init];
        
        speaker.href = item.href;
        
        [item.data enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSDictionary *dict = (NSDictionary *)obj;
            
            NSString *field = [dict objectForKey:@"name"];
            NSString *value = [dict objectForKey:@"value"];
            
            if ([@"name" isEqualToString:field]) {
                speaker.name = value;
            }
            if ([@"bio" isEqualToString:field]) {
                speaker.bio = value;
            }
        }];
        
        // TODO links - add biopic
        
        [temp addObject:speaker];
    }];
    
    [self.delegate finishedSpeakers:[NSArray arrayWithArray:temp] forHref:href];
}

- (void) fetch:(NSURL *)url {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    dispatch_async(queue, ^{
        NSData* root = [NSData dataWithContentsOfURL:url];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self fetchedSpeakers:root forHref:url];
        });
    });
}



@end

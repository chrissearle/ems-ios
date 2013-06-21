//
//  EMSDetailViewController.m
//

#import <CommonCrypto/CommonDigest.h>
#import <EventKit/EventKit.h>
#import <Crashlytics/Crashlytics.h>

#import "EMSDetailViewController.h"

#import "EMSAppDelegate.h"

#import "EMSRetriever.h"

#import "Session.h"
#import "Speaker.h"
#import "Keyword.h"
#import "Room.h"

#import "NHCalendarActivity.h"
#import "NHCalendarEvent.h"

@interface EMSDetailViewController ()

@end

@implementation EMSDetailViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    NSDateFormatter *dateFormatterTime = [[NSDateFormatter alloc] init];
    
    [dateFormatterTime setDateFormat:@"HH:mm"];
    
    NSMutableString *title = [[NSMutableString alloc] init];
    [title appendString:[NSString stringWithFormat:@"%@ - %@",
                         [dateFormatterTime stringFromDate:self.session.slot.start],
                         [dateFormatterTime stringFromDate:self.session.slot.end]]];

    if (self.session.roomName != nil) {
        [title appendString:[NSString stringWithFormat:@" : %@", self.session.roomName]];
    }
    
    self.title = [NSString stringWithString:title];
    
    UIImage *normalImage = [UIImage imageNamed:@"28-star-grey"];
    UIImage *selectedImage = [UIImage imageNamed:@"28-star-yellow"];
    UIImage *highlightedImage = [UIImage imageNamed:@"28-star"];
    
    if ([self.session.format isEqualToString:@"lightning-talk"]) {
        normalImage = [UIImage imageNamed:@"64-zap-grey"];
        selectedImage = [UIImage imageNamed:@"64-zap-yellow"];
        highlightedImage = [UIImage imageNamed:@"64-zap"];
    }
    
    [self.button setImage:normalImage forState:UIControlStateNormal];
    [self.button setImage:selectedImage forState:UIControlStateSelected];
    [self.button setImage:highlightedImage forState:UIControlStateHighlighted];
    
    [self.button setSelected:[self.session.favourite boolValue]];
    
    self.titleLabel.text = self.session.title;
    
    [self buildPage];
    
    [self retrieve];
}

- (void) viewDidAppear:(BOOL)animated {
    id<GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
    [tracker sendView:@"Detail Screen"];
}


- (IBAction)toggleFavourite:(id)sender {
    self.session = [[[EMSAppDelegate sharedAppDelegate] model] toggleFavourite:self.session];
    
    [self.button setSelected:[self.session.favourite boolValue]];
}

- (void) buildPage {
    NSString *path = [[NSBundle mainBundle] bundlePath];
	NSURL *baseURL = [NSURL fileURLWithPath:path];
    [self.webView loadHTMLString:[self buildPage:self.session] baseURL:baseURL];
}

- (void) retrieve {
    EMSRetriever *retriever = [[EMSRetriever alloc] init];
    
    retriever.delegate = self;
    
    CLS_LOG(@"Retrieving speakers");
    
    [retriever refreshSpeakers:[NSURL URLWithString:self.session.speakerCollection]];
}

- (void) finishedSpeakers:(NSArray *)speakers forHref:(NSURL *)href {
    CLS_LOG(@"Storing speakers %d", [speakers count]);
    
    NSError *error = nil;
    
    if (![[[EMSAppDelegate sharedAppDelegate] model] storeSpeakers:speakers forHref:[href absoluteString] error:&error]) {
        CLS_LOG(@"Failed to store speakers %@ - %@", error, [error userInfo]);
    }

    [self buildPage];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (NSString *)cleanString:(NSString *)value {
    if (value == nil) {
        return @"";
    }
    return [[value capitalizedString] stringByReplacingOccurrencesOfString:@"-" withString:@" "];
}

- (NSString *)buildCalendarNotes {
    NSMutableString *result = [[NSMutableString alloc] init];
    
    [result appendString:@"Details\n\n"];
    [result appendString:self.session.body];
    
    [result appendString:@"\n\nInformation\n\n"];
    [result appendFormat:@"* %@\n\n", [[@[[self cleanString:self.session.level]] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"\n* "]];
    
    if (self.session.keywords != nil && [self.session.keywords count] > 0) {
        [result appendString:@"\n\nKeywords\n\n"];
        
        NSMutableArray *listItems = [[NSMutableArray alloc] init];
            
        [self.session.keywords enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            Keyword *keyword = (Keyword *)obj;
                
            [listItems addObject:keyword.name];
        }];
            
        [result appendFormat:@"* %@\n\n", [[listItems sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"\n* "]];
    }
    
    if ([self.session.speakers count] > 0) {
        [result appendString:@"\n\nSpeakers\n\n"];
        
        [self.session.speakers enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            Speaker *speaker = (Speaker *)obj;
            
            [result appendString:speaker.name];
            if (speaker.bio != nil) {
                [result appendString:@"\n\n"];
                [result appendString:speaker.bio];
            }
            [result appendString:@"\n\n"];
        }];
    }
    
    return [NSString stringWithString:result];
}

- (NHCalendarEvent *)createCalendarEvent
{
    NHCalendarEvent *calendarEvent = [[NHCalendarEvent alloc] init];
    
    calendarEvent.title = [NSString stringWithFormat:@"%@ - %@", self.session.conference.name, self.session.title];
    calendarEvent.location = self.session.room.name;
    calendarEvent.notes = [self buildCalendarNotes];
    calendarEvent.startDate = [self dateForDate:self.session.slot.start];
    calendarEvent.endDate = [self dateForDate:self.session.slot.end];
    calendarEvent.allDay = NO;
    
    // Add alarm
    NSArray *alarms = @[[EKAlarm alarmWithRelativeOffset:- 60.0f * 5.0f]];
    
    calendarEvent.alarms = alarms;
    
    CLS_LOG(@"Created calendar event %@", calendarEvent);
    
    return calendarEvent;
}

- (void)share:(id)sender {
    [Crashlytics setObjectValue:self.session.href forKey:@"lastSharedSession"];
    
    // More info - http://blogs.captechconsulting.com/blog/steven-beyers/cocoaconf-dc-recap-sharing-uiactivityviewcontroller

    NSString *shareString = [NSString stringWithFormat:@"%@ - %@", self.session.conference.name, self.session.title];
    
    CLS_LOG(@"About to share for %@", shareString);
    
    // TODO - web URL?
    // NSURL *shareUrl = [NSURL URLWithString:@"http://www.java.no"];
    
    NSArray *activityItems = [NSArray arrayWithObjects:shareString, /*shareUrl, */ [self createCalendarEvent], nil];
    
    NSArray *activities = @[[[NHCalendarActivity alloc] init]];

    __block UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:activityItems
                                                                                         applicationActivities:activities];
    
    activityViewController.excludedActivityTypes = @[UIActivityTypePrint,
                                                     UIActivityTypeCopyToPasteboard,
                                                     UIActivityTypeAssignToContact,
                                                     UIActivityTypeSaveToCameraRoll];
    
    [activityViewController setCompletionHandler:^(NSString *activityType, BOOL completed) {
        CLS_LOG(@"Sharing of %@ via %@ - completed %d", shareString, activityType, completed);

        if (completed) {
            id<GAITracker> tracker = [[GAI sharedInstance] defaultTracker];

            [tracker sendSocial:activityType
                     withAction:@"Share"
                     withTarget:[NSURL URLWithString:self.session.href]];
        }
    }];
    
    activityViewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    [self presentViewController:activityViewController animated:YES completion:^{ activityViewController.excludedActivityTypes = nil; activityViewController = nil; }];
}

- (NSString *)buildPage:(Session *)session {
    
	NSString *page = [NSString stringWithFormat:@""
					  "<html>"
					  "<head>"
					  "<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/>"
                      "<meta name='viewport' content='width=device-width; initial-scale=1.0; maximum-scale=1.0;'>"
					  "</head>"
					  "<body>"
					  "%@"
                      "%@"
					  "%@"
					  "%@"
					  "</body>"
					  "</html>",
					  [self paraContent:session.body],
                      [self dataContent:@[[self cleanString:self.session.level]]],
					  [self keywordContent:session.keywords],
					  [self speakerContent:session.speakers]];
	
	return page;
}

- (NSString *)paraContent:(NSString *)text {
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    
    return [NSString stringWithFormat:@"<p>%@</p>", [lines componentsJoinedByString:@"</p><p>"]];
}

- (NSString *)dataContent:(NSArray *)data {
	NSMutableString *result = [[NSMutableString alloc] init];
    
    if (data != nil && [data count] > 0) {
        [result appendString:@"<h2>Information</h2>"];
        
        [result appendString:@"<ul>"];
        
        [result appendFormat:@"<li>%@</li>", [[data sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"</li><li>"]];
        
        [result appendString:@"</ul>"];
    }
    
    return [NSString stringWithString:result];
}

- (NSString *)keywordContent:(NSSet *)keywords {
	NSMutableString *result = [[NSMutableString alloc] init];

    if (keywords != nil && [keywords count] > 0) {
        [result appendString:@"<h2>Keywords</h2>"];

        [result appendString:@"<ul>"];

        NSMutableArray *listItems = [[NSMutableArray alloc] init];

        [keywords enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            Keyword *keyword = (Keyword *)obj;

            [listItems addObject:keyword.name];
        }];

        [result appendFormat:@"<li>%@</li>", [[listItems sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"</li><li>"]];

        [result appendString:@"</ul>"];
    }

    return [NSString stringWithString:result];
}

- (NSString *)speakerContent:(NSSet *)speakers {
	NSMutableString *result = [[NSMutableString alloc] init];

    if (speakers != nil && [speakers count] > 0) {
        [result appendString:@"<h2>Speakers</h2>"];
    
        [speakers enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            Speaker *speaker = (Speaker *)obj;
            
            if (speaker.name != nil) {
                [result appendString:[NSString stringWithFormat:@"<h3>%@</h3>", speaker.name]];
            }

            if (speaker.thumbnailUrl != nil) {
                CLS_LOG(@"Speaker has available thumbnail %@", speaker.thumbnailUrl);

                NSString *safeFilename = [self md5:speaker.thumbnailUrl];

                NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];

                NSString *pngFilePath = [NSString stringWithFormat:@"%@/%@.png",cacheDir,safeFilename];

                NSFileManager *fileManager = [NSFileManager defaultManager];

                if ([fileManager fileExistsAtPath:pngFilePath]) {
                    CLS_LOG(@"Speaker has cached thumbnail %@", speaker.thumbnailUrl);

                    NSError *fileError = nil;
                
                    NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:pngFilePath error:&fileError];
                
                    if (fileError != nil) {
                        CLS_LOG(@"Got a file error reading file attributes for file %@", pngFilePath);
                    } else {
                        if ([fileAttributes fileSize] > 0) {
                            [result appendString:[NSString stringWithFormat:@"<img src='file://%@' width='50px' style='float: left; margin-right: 3px; margin-bottom: 3px'/>", pngFilePath]];
                        } else {
                            CLS_LOG(@"Empty bioPic %@", pngFilePath);
                        }
                    }
                } else {
                    CLS_LOG(@"Speaker needs to fetch thumbnail %@", speaker.thumbnailUrl);

                    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

                    [[EMSAppDelegate sharedAppDelegate] startNetwork];

                    dispatch_async(queue, ^{
                        NSError *thumbnailError = nil;
                        
                        NSURL *url = [NSURL URLWithString:speaker.thumbnailUrl];
                        
                        NSData* data = [NSData dataWithContentsOfURL:url
                                        options:NSDataReadingMappedIfSafe
                                        error:&thumbnailError];

                        if (data == nil) {
                            CLS_LOG(@"Failed to retrieve thumbnail %@ - %@ - %@", url, thumbnailError, [thumbnailError userInfo]);

                            [[EMSAppDelegate sharedAppDelegate] stopNetwork];
                        } else {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                UIImage *image = [UIImage imageWithData:data];

                                CLS_LOG(@"Saving image file");

                                [[NSData dataWithData:UIImagePNGRepresentation(image)] writeToFile:pngFilePath atomically:YES];

                                [[EMSAppDelegate sharedAppDelegate] stopNetwork];

                                [self buildPage];
                            });
                        }
                    });

                    
               }
            }

            NSString *bio = speaker.bio;
            if (bio != nil) {
                [result appendString:[self paraContent:bio]];
            }
        }];
        
	}
    
	return [NSString stringWithString:result];
}

- (NSString *) md5:(NSString *) input
{
    const char *cStr = [input UTF8String];
    unsigned char digest[16];
    CC_MD5( cStr, strlen(cStr), digest ); // This is the md5 call

    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];

    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];
    
    return  output;
}

- (NSDate *)dateForDate:(NSDate *)date {
#ifdef USE_TEST_DATE
    CLS_LOG(@"WARNING - RUNNING IN USE_TEST_DATE mode");
    
	// In debug mode we will use the current day but always the start time of the slot. Otherwise we couldn't test until JZ started ;)
	NSCalendar *calendar = [NSCalendar currentCalendar];
    
	NSDateComponents *timeComp = [calendar components:NSHourCalendarUnit|NSMinuteCalendarUnit fromDate:date];
	NSDateComponents *dateComp = [calendar components:NSYearCalendarUnit|NSMonthCalendarUnit|NSDayCalendarUnit fromDate:[[NSDate alloc] init]];
    
    NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
    [inputFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss ZZ"];
    [inputFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    
	return [inputFormatter dateFromString:[NSString stringWithFormat:@"%04d-%02d-%02d %02d:%02d:00 +0200", [dateComp year], [dateComp month], [dateComp day], [timeComp hour], [timeComp minute]]];
#else
    return date;
#endif
}

@end

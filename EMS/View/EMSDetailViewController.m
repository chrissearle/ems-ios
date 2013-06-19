//
//  EMSDetailViewController.m
//

#import <CommonCrypto/CommonDigest.h>

#import "EMSDetailViewController.h"

#import "EMSAppDelegate.h"

#import "EMSRetriever.h"

#import "Session.h"
#import "Speaker.h"
#import "Keyword.h"

@interface EMSDetailViewController ()

@end

@implementation EMSDetailViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = self.session.title;
    
    self.room.text = self.session.roomName;
    self.level.text = [self.session.level capitalizedString];

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
    
    NSDateFormatter *dateFormatterTime = [[NSDateFormatter alloc] init];
    
    [dateFormatterTime setDateFormat:@"HH:mm"];

    self.time.text = [NSString stringWithFormat:@"%@ - %@",
                      [dateFormatterTime stringFromDate:self.session.slot.start],
                      [dateFormatterTime stringFromDate:self.session.slot.end]];
    
    [self buildPage];
    
    [self retrieve];
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
    
    [[[EMSAppDelegate sharedAppDelegate] model] storeSpeakers:speakers forHref:[href absoluteString] error:nil];

    [self buildPage];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)share:(id)sender {
    // More info - http://blogs.captechconsulting.com/blog/steven-beyers/cocoaconf-dc-recap-sharing-uiactivityviewcontroller

    NSString *shareString = [NSString stringWithFormat:@"%@ - %@", self.session.conference.name, self.session.title];
    
    CLS_LOG(@"About to share for %@", shareString);
    
//TODO - image?    UIImage *shareImage = [UIImage imageNamed:@"captech-logo.jpg"];
    // TODO - web URL?
    NSURL *shareUrl = [NSURL URLWithString:@"http://www.java.no"];
    NSArray *activityItems = [NSArray arrayWithObjects:shareString, /*shareImage, */shareUrl, nil];
    
    __block UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:activityItems
                                                                                         applicationActivities:nil];
    
    activityViewController.excludedActivityTypes = @[UIActivityTypePrint,
                                                     UIActivityTypeCopyToPasteboard,
                                                     UIActivityTypeAssignToContact,
                                                     UIActivityTypeSaveToCameraRoll];
    
    [activityViewController setCompletionHandler:^(NSString *activityType, BOOL completed) {
        CLS_LOG(@"Sharing of %@ via %@ - completed %d", shareString, activityType, completed);
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
					  "<h1>%@</h1>"
					  "%@"
					  "%@"
					  "%@"
					  "</body>"
					  "</html>",
					  [session valueForKey:@"title"],
					  [self paraContent:session.body],
					  [self keywordContent:session.keywords],
					  [self speakerContent:session.speakers]];
	
	return page;
}

- (NSString *)paraContent:(NSString *)text {
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    
    return [NSString stringWithFormat:@"<p>%@</p>", [lines componentsJoinedByString:@"</p><p>"]];
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
                        NSData* data = [NSData dataWithContentsOfURL:[NSURL URLWithString:speaker.thumbnailUrl]];

                        dispatch_async(dispatch_get_main_queue(), ^{
                            UIImage *image = [UIImage imageWithData:data];

                            CLS_LOG(@"Saving image file");

                            [[NSData dataWithData:UIImagePNGRepresentation(image)] writeToFile:pngFilePath atomically:YES];

                            [[EMSAppDelegate sharedAppDelegate] stopNetwork];

                            [self buildPage];
                        });
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

@end

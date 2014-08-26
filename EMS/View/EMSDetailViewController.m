//
//  EMSDetailViewController.m
//

#import <CommonCrypto/CommonDigest.h>
#import <EventKit/EventKit.h>

#import "EMSDetailViewController.h"

#import "EMSAppDelegate.h"

#import "EMSRetriever.h"

#import "Speaker.h"
#import "Keyword.h"
#import "Room.h"

#import "EMSDetailViewRow.h"

#import "NHCalendarActivity.h"

#import "EMSTopAlignCellTableViewCell.h"

#import "EMSDefaultTableViewCell.h"
#import "EMSTracking.h"

#import "EMSSessionTitleTableViewCell.h"

@interface EMSDetailViewController () <UIPopoverControllerDelegate, EMSSpeakersRetrieverDelegate, UITableViewDataSource, UITableViewDelegate>

@property(nonatomic) UIPopoverController *sharePopoverController;

@property(nonatomic) NSArray *parts;

@property(nonatomic, strong) NSDictionary *cachedSpeakerBios;

@property(nonatomic, weak) IBOutlet UIBarButtonItem *shareButton;

@property(nonatomic, strong) EMSRetriever *speakerRetriever;

@property(nonatomic) BOOL observersInstalled;

@property(nonatomic, strong) EMSSessionTitleTableViewCell *titleSizingCell;

@property(nonatomic, strong) EMSTopAlignCellTableViewCell *topAlignSizingCell;

@property(nonatomic, strong) EMSDefaultTableViewCell *defaultSizingCell;

- (IBAction)share:(id)sender;

@end

typedef NS_ENUM(NSUInteger, EMSDetailViewControllerSection) {
    EMSDetailViewControllerSectionInfo,
    EMSDetailViewControllerSectionLegacy,

};

@implementation EMSDetailViewController

#pragma mark - Initialization Convenience

- (void)setupWithSession:(Session *)session {
    if (session) {

        if (self.observersInstalled) {
            [self.session removeObserver:self forKeyPath:@"favourite"];
        }

        self.session = session;

        if (self.observersInstalled) {
            [self.session addObserver:self forKeyPath:@"favourite" options:0 context:nil];
        }

        [self initSpeakerCache:session];

        [self setupPartsWithThumbnailRefresh:YES];

        [self retrieve];

        self.shareButton.enabled = YES;

    }
}

+ (NSString *)createControllerTitle:(Session *)session {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterNoStyle];


    NSDateFormatter *timeFormatter = [[NSDateFormatter alloc] init];

    [timeFormatter setDateStyle:NSDateFormatterNoStyle];
    [timeFormatter setTimeStyle:NSDateFormatterShortStyle];

    NSMutableString *title = [[NSMutableString alloc] init];

    if (session.slot) {
        [title appendString:[NSString stringWithFormat:@"%@ %@ - %@",
                                                       [dateFormatter stringFromDate:session.slot.start],
                                                       [timeFormatter stringFromDate:session.slot.start],
                                                       [timeFormatter stringFromDate:session.slot.end]]];
    } else {
        if (session.slotName != nil) {
            [title appendString:session.slotName];
        }
    }

    if (session.roomName != nil) {
        [title appendString:[NSString stringWithFormat:@" : %@", session.roomName]];
    }
    return [title copy];
}

+ (NSString *)createControllerAccessibilityTitle:(Session *)session {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterNoStyle];


    NSDateFormatter *timeFormatter = [[NSDateFormatter alloc] init];

    [timeFormatter setDateStyle:NSDateFormatterNoStyle];
    [timeFormatter setTimeStyle:NSDateFormatterShortStyle];

    NSMutableString *title = [[NSMutableString alloc] init];

    if (session.slot) {
        [title appendString:[NSString stringWithFormat:NSLocalizedString(@"%@ at %@ to %@", @"{Session date} at {Session start time} to {Session end time}"),
                                                       [dateFormatter stringFromDate:session.slot.start],
                                                       [timeFormatter stringFromDate:session.slot.start],
                                                       [timeFormatter stringFromDate:session.slot.end]]];
    } else {
        if (session.slotName != nil) {
            [title appendString:session.slotName];
        }
    }

    if (session.roomName != nil) {
        [title appendString:[NSString stringWithFormat:NSLocalizedString(@" in %@", @" in {Room name}"), session.roomName]];
    }
    return [title copy];
}

- (void)initSpeakerCache:(Session *)session {
    NSMutableDictionary *speakerBios = [[NSMutableDictionary alloc] init];

    for (Speaker *speaker in session.speakers) {
        if (speaker.bio != nil) {
            speakerBios[speaker.name] = speaker.bio;
        } else {
            speakerBios[speaker.name] = @"";
        }
    }

    self.cachedSpeakerBios = [NSDictionary dictionaryWithDictionary:speakerBios];
}

- (void)setupPartsWithThumbnailRefresh:(BOOL) thumbnailRefresh {
    NSMutableArray *p = [[NSMutableArray alloc] init];

    if ([EMSFeatureConfig isFeatureEnabled:fLinks]) {
        if (self.session.videoLink) {
            [p addObject:[[EMSDetailViewRow alloc] initWithContent:NSLocalizedString(@"Video", @"Title for video button in detail view") image:[UIImage imageNamed:@"70-tv"] link:[NSURL URLWithString:self.session.videoLink]]];
        }
    }

    if (self.session.summary != nil) {
        [p addObject:[[EMSDetailViewRow alloc] initWithContent:self.session.summary emphasized:YES]];
    }
    if (self.session.body != nil) {
        [p addObject:[[EMSDetailViewRow alloc] initWithContent:self.session.body]];
    }
    if (self.session.audience != nil) {
        [p addObject:[[EMSDetailViewRow alloc] initWithContent:NSLocalizedString(@"Intended Audience", @"Subtitle for detail view for audience") emphasized:YES]];
        [p addObject:[[EMSDetailViewRow alloc] initWithContent:self.session.audience title:NSLocalizedString(@"Intended Audience", @"Subtitle for detail view for audience")]];
    }

    if (self.session.level != nil) {

        UIImage *img = [UIImage imageNamed:self.session.level];

        [p addObject:[[EMSDetailViewRow alloc] initWithContent:[self cleanString:self.session.level] image:img]];
    }

    NSArray *sortedKeywords = [self.session.keywords.allObjects sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        NSString *first = [(Keyword *) a name];
        NSString *second = [(Keyword *) b name];

        return [first compare:second];
    }];

    [sortedKeywords enumerateObjectsUsingBlock:^(id obj, NSUInteger x, BOOL *stop) {
        Keyword *keyword = (Keyword *) obj;

        [p addObject:[[EMSDetailViewRow alloc] initWithContent:keyword.name image:[UIImage imageNamed:@"14-tag"]]];
    }];

    [self.session.speakers enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
        Speaker *speaker = (Speaker *) obj;

        EMSDetailViewRow *row = [[EMSDetailViewRow alloc] initWithContent:speaker.name];

        if ([EMSFeatureConfig isFeatureEnabled:fBioPics]) {
            if (speaker.thumbnailUrl != nil) {
                EMS_LOG(@"Speaker has available thumbnail %@", speaker.thumbnailUrl);

                NSString *pngFilePath = [self pathForCachedThumbnail:speaker];

                UIImage *img = [UIImage imageWithContentsOfFile:pngFilePath];

                row.image = img;

                if (thumbnailRefresh) {
                    [self checkForNewThumbnailForSpeaker:speaker withFilename:pngFilePath forSessionHref:self.session.href];
                }
            }
        }

        NSString *bio = self.cachedSpeakerBios[speaker.name];

        //if (bio && ![bio isEqualToString:@""]) {
            row.body = bio;
        //}

        [p addObject:row];
    }];

    self.parts = [NSArray arrayWithArray:p];

    [self.tableView reloadData];
}

#pragma mark - Lifecycle

- (void)updateTableViewRowHeightReload {
    [self.tableView reloadData];
}

- (void)addObservers {
    if (!self.observersInstalled) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTableViewRowHeightReload) name:UIContentSizeCategoryDidChangeNotification object:nil];

        [self.session addObserver:self forKeyPath:@"favourite" options:0 context:NULL];

        self.observersInstalled = YES;

    }
}

- (void)removeObservers {
    if (self.observersInstalled) {

        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIContentSizeCategoryDidChangeNotification object:nil];

        [self.session removeObserver:self forKeyPath:@"favourite"];

        self.observersInstalled = NO;
    }

}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([object isEqual:self.session] && [keyPath isEqual:@"favourite"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
    }
}


- (void)viewDidLoad {
    [super viewDidLoad];

    //We do not do fullscreen layout on iOS 7+ right now.
    if ([self respondsToSelector:@selector(setAutomaticallyAdjustsScrollViewInsets:)]) {
        self.automaticallyAdjustsScrollViewInsets = YES;
    }

    self.tableView.dataSource = self;
    self.tableView.delegate = self;

    self.observersInstalled = NO;

    [self setupWithSession:self.session];

}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self addObservers];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [EMSTracking trackScreen:@"Detail Screen"];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self removeObservers];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - UIPopoverControllerDelegate

- (BOOL)popoverControllerShouldDismissPopover:(UIPopoverController *)popoverController {
    return YES;
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController {
    if (popoverController == self.sharePopoverController) {
        self.sharePopoverController = nil;
    }

    self.shareButton.enabled = YES;
}


#pragma mark - Calendar

- (NHCalendarEvent *)createCalendarEvent {
    NHCalendarEvent *calendarEvent = [[NHCalendarEvent alloc] init];

    calendarEvent.title = [NSString stringWithFormat:@"%@ - %@", self.session.conference.name, self.session.title];
    calendarEvent.location = self.session.room.name;
    calendarEvent.notes = [self buildCalendarNotes];
    calendarEvent.startDate = [self dateForDate:self.session.slot.start];
    calendarEvent.endDate = [self dateForDate:self.session.slot.end];
    calendarEvent.allDay = NO;

    // Add alarm
    NSArray *alarms = @[[EKAlarm alarmWithRelativeOffset:-60.0f * 5.0f]];

    calendarEvent.alarms = alarms;

    EMS_LOG(@"Created calendar event %@", calendarEvent);

    return calendarEvent;
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
            Keyword *keyword = (Keyword *) obj;

            [listItems addObject:keyword.name];
        }];

        [result appendFormat:@"* %@\n\n", [[listItems sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"\n* "]];
    }

    if ([self.session.speakers count] > 0) {
        [result appendString:@"\n\nSpeakers\n\n"];

        [self.session.speakers enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            Speaker *speaker = (Speaker *) obj;

            if (speaker.name != nil) {
                [result appendString:speaker.name];
            }

            NSString *bio = self.cachedSpeakerBios[speaker.name];
            if (bio && ![bio isEqualToString:@""]) {
                [result appendString:@"\n\n"];
                [result appendString:bio];
            }
            [result appendString:@"\n\n"];
        }];
    }

    return [NSString stringWithString:result];
}


#pragma mark - Convenience

- (NSString *)md5:(NSString *)input {
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG) strlen(cStr), digest); // This is the md5 call

    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];

    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];

    return output;
}

- (NSString *)cleanString:(NSString *)value {
    if (value == nil) {
        return @"";
    }
    return [[value capitalizedString] stringByReplacingOccurrencesOfString:@"-" withString:@" "];
}

- (NSDate *)dateForDate:(NSDate *)date {
#ifdef USE_TEST_DATE
    EMS_LOG(@"WARNING - RUNNING IN USE_TEST_DATE mode");

    // In debug mode we will use the current day but always the start time of the slot. Otherwise we couldn't test until JZ started ;)
    NSCalendar *calendar = [NSCalendar currentCalendar];

    NSDateComponents *timeComp = [calendar components:NSHourCalendarUnit | NSMinuteCalendarUnit fromDate:date];
    NSDateComponents *dateComp = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:[[NSDate alloc] init]];

    NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
    [inputFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss ZZ"];
    [inputFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

    return [inputFormatter dateFromString:[NSString stringWithFormat:@"%04ld-%02ld-%02ld %02ld:%02ld:00 +0200", (long) [dateComp year], (long) [dateComp month], (long) [dateComp day], (long) [timeComp hour], (long) [timeComp minute]]];
#else
    return date;
#endif
}

#pragma mark - Actions

- (IBAction)toggleFavourite:(id)sender {
    [[[EMSAppDelegate sharedAppDelegate] model] toggleFavourite:self.session];
}

- (void)share:(id)sender {
    self.shareButton.enabled = NO;

    if ([EMSFeatureConfig isCrashlyticsEnabled]) {
        [Crashlytics setObjectValue:self.session.href forKey:@"lastSharedSession"];
    }

    NSString *shareString = [NSString stringWithFormat:@"%@ - %@", self.session.conference.name, self.session.title];
    EMS_LOG(@"About to share for %@", shareString);

    // TODO - web URL?
    // NSURL *shareUrl = [NSURL URLWithString:@"http://www.java.no"];

    NSMutableArray *shareItems = [[NSMutableArray alloc] init];
    NSMutableArray *shareActivities = [[NSMutableArray alloc] init];

    [shareItems addObject:shareString];

    if (self.session.slot) {
        [shareItems addObject:[self createCalendarEvent]];
        [shareActivities addObject:[[NHCalendarActivity alloc] init]];
    }

    if (self.session.videoLink) {
        [shareItems addObject:self.session.videoLink];
    }

    NSArray *activityItems = [NSArray arrayWithArray:shareItems];
    NSArray *activities = [NSArray arrayWithArray:shareActivities];

    __block UIActivityViewController *activityViewController = [[UIActivityViewController alloc]
            initWithActivityItems:activityItems
            applicationActivities:activities];

    activityViewController.excludedActivityTypes = @[UIActivityTypePrint,
            UIActivityTypeCopyToPasteboard,
            UIActivityTypeAssignToContact,
            UIActivityTypeSaveToCameraRoll];

    [activityViewController setCompletionHandler:^(NSString *activityType, BOOL completed) {
        EMS_LOG(@"Sharing of %@ via %@ - completed %d", shareString, activityType, completed);


        self.shareButton.enabled = YES;
        if (completed) {
            [EMSTracking trackSocialWithNetwork:activityType action:@"Share" target:self.session.href];
        }
    }];


    activityViewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;


    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        UIPopoverController *popup = [[UIPopoverController alloc] initWithContentViewController:activityViewController];

        popup.delegate = self;
        [popup presentPopoverFromBarButtonItem:sender permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];

        self.sharePopoverController = popup;
    } else {
        [self presentViewController:activityViewController animated:YES completion:^{
            activityViewController.excludedActivityTypes = nil;
            activityViewController = nil;
        }];
    }

}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger rows = 0;

    if (section == EMSDetailViewControllerSectionInfo) {
        rows = 1;
    } else if (section == EMSDetailViewControllerSectionLegacy) {
        rows = [self.parts count];
    }

    return rows;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    UITableViewCell *cell = nil;

    if (indexPath.section == EMSDetailViewControllerSectionInfo) {
        EMSSessionTitleTableViewCell *titleCell = [self.tableView dequeueReusableCellWithIdentifier:@"SessionTitleTableViewCell" forIndexPath:indexPath];
        cell = [self configureTitleCell:titleCell forIndexPath:indexPath];
    } else if (indexPath.section == EMSDetailViewControllerSectionLegacy) {
        EMSDetailViewRow *row = self.parts[(NSUInteger) indexPath.row];
        if (row.body) {
            EMSTopAlignCellTableViewCell *speakerCell = [self.tableView dequeueReusableCellWithIdentifier:@"SpeakerCell" forIndexPath:indexPath];
            cell = [self configureSpeakerCell:speakerCell forRow:row forIndexPath:indexPath];
            
        } else {
            cell = [self tableView:tableView buildCellForRow:row];
        }
    }

    return cell;

}

- (EMSSessionTitleTableViewCell *) configureTitleCell:(EMSSessionTitleTableViewCell *)titleCell forIndexPath:(NSIndexPath *) indexPath {
    
    UIFont *font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    font = [font fontWithSize:(CGFloat) (font.pointSize * 1.2)];
    titleCell.titleLabel.font = font;
    
    titleCell.titleLabel.text = self.session.title;
    titleCell.titleLabel.accessibilityLanguage = self.session.language;
    
    titleCell.timeAndRoomLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];;
    titleCell.timeAndRoomLabel.text = [EMSDetailViewController createControllerTitle:self.session];
    titleCell.timeAndRoomLabel.accessibilityLabel = [EMSDetailViewController createControllerAccessibilityTitle:self.session];
    
    NSString *imageBaseName = [self.session.format isEqualToString:@"lightning-talk"] ? @"64-zap" : @"28-star";
    NSString *imageNameFormat = @"%@-%@";

    UIImage *normalImage = [UIImage imageNamed:[NSString stringWithFormat:imageNameFormat, imageBaseName, @"grey"]];
    UIImage *selectedImage = [UIImage imageNamed:[NSString stringWithFormat:imageNameFormat, imageBaseName, @"yellow"]];

    if ([UIImage instancesRespondToSelector:@selector(imageWithRenderingMode:)]) {
        normalImage = [normalImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        selectedImage = [selectedImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }

    [titleCell.favoriteButton setImage:normalImage forState:UIControlStateNormal];
    [titleCell.favoriteButton setImage:selectedImage forState:UIControlStateSelected];

    if ([self.session.favourite boolValue]) {
        titleCell.favoriteButton.tintColor = nil;
    } else {
        titleCell.favoriteButton.tintColor = [UIColor lightGrayColor];
    }
    
    return titleCell;
}

- (UITableViewCell *) configureSpeakerCell:(EMSTopAlignCellTableViewCell *) cell forRow:(EMSDetailViewRow *)row forIndexPath:(NSIndexPath *) indexPath {
    
    cell.nameLabel.text = row.content;
    cell.nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    cell.nameLabel.accessibilityLanguage = self.session.language;
    
    cell.descriptionLabel.text = row.body;
    cell.descriptionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.descriptionLabel.accessibilityLanguage = self.session.language;
    
    cell.thumbnailView.image = row.image;
    cell.thumbnailView.layer.borderWidth = 1.0f;
    cell.thumbnailView.layer.borderColor = [UIColor grayColor].CGColor;
    cell.thumbnailView.layer.masksToBounds = NO;
    cell.thumbnailView.clipsToBounds = YES;
    cell.thumbnailView.layer.cornerRadius = CGRectGetWidth(cell.thumbnailView.frame)/2;
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell;
    
    EMSDetailViewRow *row = self.parts[(NSUInteger) indexPath.row];
    if (indexPath.section == EMSDetailViewControllerSectionInfo) {
        if (!self.titleSizingCell) {
            self.titleSizingCell = [self.tableView dequeueReusableCellWithIdentifier:@"SessionTitleTableViewCell"];
        }
        
        cell = [self configureTitleCell:self.titleSizingCell forIndexPath:indexPath];
        
    } else if (row.body){
        if (!self.topAlignSizingCell) {
            self.topAlignSizingCell = [tableView dequeueReusableCellWithIdentifier:@"SpeakerCell"];
        }
        cell = [self configureSpeakerCell:self.topAlignSizingCell forRow:row forIndexPath:indexPath];
    } else {
        cell = [self tableView:tableView buildCellForRow:row];
    }
    
    if ([cell isKindOfClass:[EMSDefaultTableViewCell class]]) {
        
        cell.bounds = CGRectMake(0.0f, 0.0f, CGRectGetWidth(tableView.bounds), CGRectGetHeight(cell.bounds));
        
        
        CGFloat height = (NSInteger) [cell intrinsicContentSize].height;
        
        if (row.link && height < 48) {
            height = 48;
        }
        
        return height;
        
    } else {
        
        CGFloat prefWidth =CGRectGetWidth(tableView.bounds);
        CGFloat prefHeigth = 400;
        cell.bounds = CGRectMake(0.0f, 0.0f, prefWidth, prefHeigth);
        
        [cell setNeedsLayout];
        [cell layoutSubviews];
        
        // Get the actual height required for the cell's contentView
        CGFloat height = [cell.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;

        return height + 1;
    }

}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == EMSDetailViewControllerSectionLegacy) {
        EMSDetailViewRow *row = self.parts[(NSUInteger) indexPath.row];

        if (row.link) {
            return indexPath;
        }
    }

    return nil;

}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == EMSDetailViewControllerSectionLegacy) {
        EMSDetailViewRow *row = self.parts[(NSUInteger) indexPath.row];

        if (row.link) {
            [EMSTracking trackEventWithCategory:@"web" action:@"open link" label:[row.link absoluteString]];

            [[UIApplication sharedApplication] openURL:row.link];
        }

        [tableView deselectRowAtIndexPath:indexPath animated:false];
    }
}


- (UITableViewCell *)tableView:(UITableView *)tableView buildCellForRow:(EMSDetailViewRow *)row {

    if (row.link) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DetailLinkCell"];

        cell.accessibilityLanguage = self.session.language;

        cell.imageView.image = row.image;
        cell.textLabel.text = row.content;
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

             return cell;
    } else {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DetailBodyCell"];

        cell.accessibilityLanguage = self.session.language;

        cell.imageView.image = row.image;
        cell.textLabel.text = row.content;


        UIFont *font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

        if (row.emphasis) {
            UIFontDescriptor *fontD = [font.fontDescriptor
                    fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
            font = [UIFont fontWithDescriptor:fontD size:0];
        }

        cell.textLabel.font = font;
        return cell;
    }


}

#pragma mark - Load Speakers

- (void)retrieve {

    if (!self.speakerRetriever) {
        self.speakerRetriever = [[EMSRetriever alloc] init];

        self.speakerRetriever.delegate = self;
    }


    EMS_LOG(@"Retrieving speakers for href %@", self.session.speakerCollection);

    [self.speakerRetriever refreshSpeakers:[NSURL URLWithString:self.session.speakerCollection]];
}

- (void)finishedSpeakers:(NSArray *)speakers forHref:(NSURL *)href {
    // Check we haven't navigated to a new session
    if ([[href absoluteString] isEqualToString:self.session.speakerCollection]) {
        __block BOOL newBios = NO;
        
        NSMutableDictionary *speakerBios = [NSMutableDictionary dictionaryWithDictionary:self.cachedSpeakerBios];
        
        [self.cachedSpeakerBios enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stopCached) {
            NSString *name = (NSString *) key;
            NSString *bio = (NSString *) obj;
            
            for (Speaker *speaker in self.session.speakers) {
                if ([speaker.name isEqualToString:name]) {
                    if (![speaker.bio isEqualToString:bio]) {
                        if (speaker.bio != nil) {
                            speakerBios[speaker.name] = speaker.bio;
                            newBios = YES;
                        }
                    }
                }
            }
        }];
        
        if (newBios) {
            EMS_LOG(@"Saw updated bios - updating screen");
            self.cachedSpeakerBios = [NSDictionary dictionaryWithDictionary:speakerBios];
            [self setupPartsWithThumbnailRefresh:YES];
        }
    }
}

- (void)checkForNewThumbnailForSpeaker:(Speaker *)speaker withFilename:(NSString *)pngFilePath forSessionHref:(NSString *)href {
    EMS_LOG(@"Checking for updated thumbnail %@", speaker.thumbnailUrl);

    static NSDateFormatter *httpDateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        httpDateFormatter = [[NSDateFormatter alloc] init];
        httpDateFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        httpDateFormatter.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss 'GMT'";
    });

    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
    [sessionConfiguration setAllowsCellularAccess:YES];

    NSDate *lastModified = [[[EMSAppDelegate sharedAppDelegate] model] dateForSpeakerPic:speaker.thumbnailUrl];

    if (lastModified) {
        EMS_LOG(@"Setting last modified to %@", lastModified);

        NSString *httpFormattedDate = [httpDateFormatter stringFromDate:lastModified];
        sessionConfiguration.HTTPAdditionalHeaders = @{@"If-Modified-Since" : httpFormattedDate};
        sessionConfiguration.URLCache = nil;
    }

    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration];

    [[EMSAppDelegate sharedAppDelegate] startNetwork];

    [[session downloadTaskWithURL:[NSURL URLWithString:speaker.thumbnailUrl] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error != nil) {
            EMS_LOG(@"Failed to retrieve thumbnail %@ - %@ - %@", speaker.thumbnailUrl, error, [error userInfo]);
        } else {
            // Network is likely still up
            [EMSTracking dispatch];

            // Cast to http - safe as long as we've made a web call
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

            if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {

                NSFileManager *fileManager = [NSFileManager defaultManager];

                if ([fileManager isReadableFileAtPath:[location path]]) {
                    NSError *fileError;

                    if ([fileManager isDeletableFileAtPath:pngFilePath]) {
                        [fileManager removeItemAtPath:pngFilePath error:&fileError];

                        if (fileError != nil) {
                            EMS_LOG(@"Failed to delete old thumbnail %@ - %@ - %@", pngFilePath, fileError, [fileError userInfo]);

                            fileError = nil;
                        }
                    }

                    [fileManager moveItemAtPath:[location path] toPath:pngFilePath error:&fileError];

                    if (fileError != nil) {
                        EMS_LOG(@"Failed to copy thumbnail %@ - %@ - %@", location, fileError, [fileError userInfo]);
                    } else {
                        NSString *lastModifiedHeader = [httpResponse allHeaderFields][@"Last-Modified"];

                        if (lastModifiedHeader) {
                            __block NSDate *lastModifiedDate = [httpDateFormatter dateFromString:lastModifiedHeader];

                            dispatch_async(dispatch_get_main_queue(), ^{
                                [[[EMSAppDelegate sharedAppDelegate] model] setDate:lastModifiedDate ForSpeakerPic:speaker.thumbnailUrl];
                            });
                        }

                        dispatch_async(dispatch_get_main_queue(), ^{
                            if ([self.session.href isEqualToString:href]) {
                                [self setupPartsWithThumbnailRefresh:NO];
                            }
                        });
                    }
                }
            }
        }

        [[EMSAppDelegate sharedAppDelegate] stopNetwork];
    }] resume];
}

- (NSString *)pathForCachedThumbnail:(Speaker *)speaker {
    NSString *safeFilename = [self md5:speaker.thumbnailUrl];

    return [[[[EMSAppDelegate sharedAppDelegate] applicationCacheDirectory] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", safeFilename]] path];
}


#pragma mark - State restoration

static NSString *const EMSDetailViewControllerRestorationIdentifierSessionHref = @"EMSDetailViewControllerRestorationIdentifierSessionHref";

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder {
    [super encodeRestorableStateWithCoder:coder];

    [coder encodeObject:self.session.href forKey:EMSDetailViewControllerRestorationIdentifierSessionHref];
}

- (void)decodeRestorableStateWithCoder:(NSCoder *)coder {
    [super decodeRestorableStateWithCoder:coder];


    NSString *sessionHref = [coder decodeObjectForKey:EMSDetailViewControllerRestorationIdentifierSessionHref];

    if (sessionHref) {
        Session *session = [[[EMSAppDelegate sharedAppDelegate] model] sessionForHref:sessionHref];
        [self setupWithSession:session];
    }

}

@end

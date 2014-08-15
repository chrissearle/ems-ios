//
//  EMSMainViewController.m
//

#import "EMSMainViewController.h"

#import "EMSAppDelegate.h"

#import "EMSDetailViewController.h"
#import "EMSSearchViewController.h"

#import "EMSSessionCell.h"

#import "ConferenceKeyword.h"
#import "ConferenceLevel.h"
#import "ConferenceType.h"
#import "Speaker.h"
#import "Room.h"


@interface EMSMainViewController () <UISplitViewControllerDelegate,UITableViewDataSource, UITableViewDelegate, EMSRetrieverDelegate, NSFetchedResultsControllerDelegate, UISearchBarDelegate, EMSSearchViewDelegate>

@property(nonatomic, strong) EMSDetailViewController *detailViewController;

@property(nonatomic, strong) NSFetchedResultsController *fetchedResultsController;

@property(nonatomic, assign) BOOL filterFavourites;

@property(nonatomic, strong) EMSAdvancedSearch *advancedSearch;

@property(nonatomic, strong) IBOutlet UISearchBar *search;
@property(nonatomic, strong) IBOutlet UIBarButtonItem *advancedSearchButton;

@property(nonatomic, strong) IBOutlet UIView *footer;
@property(nonatomic, strong) IBOutlet UILabel *footerLabel;

- (IBAction)toggleFavourite:(id)sender;

- (IBAction)segmentChanged:(id)sender;

- (IBAction) scrollToNow:(id) sender;

- (IBAction)back:(UIStoryboardSegue *)segue;

@property BOOL observersInstalled;

@end

@implementation EMSMainViewController

#pragma mark - Convenience methods

- (void)setUpRefreshControl {
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];

    refreshControl.tintColor = [UIColor grayColor];
    refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:@"Refresh available sessions"];
    refreshControl.backgroundColor = self.tableView.backgroundColor;

    [refreshControl addTarget:self action:@selector(retrieve) forControlEvents:UIControlEventValueChanged];

    self.refreshControl = refreshControl;
}

- (void) updateRefreshControl {
    UIRefreshControl *refreshControl = self.refreshControl;
    if ([EMSRetriever sharedInstance].refreshingSessions) {
        if (!refreshControl.refreshing) {
            [refreshControl beginRefreshing];
        }
    } else {
        if (refreshControl.refreshing) {
            [refreshControl endRefreshing];
        }
    }

}

- (Conference *)conferenceForHref:(NSString *)href {
    CLS_LOG(@"Getting conference for %@", href);

    return [[[EMSAppDelegate sharedAppDelegate] model] conferenceForHref:href];
}

- (Conference *)activeConference {
    CLS_LOG(@"Getting current conference");

    NSString *activeConference = [[EMSAppDelegate currentConference] absoluteString];

    if (activeConference != nil) {
        return [self conferenceForHref:activeConference];
    }

    return nil;
}

- (void)initializeFooter {
    
    
    if ([[self.fetchedResultsController sections] count] == 0) {
        NSMutableString *labelText = [[NSMutableString alloc] init];
        
        
        Conference *conference = [self activeConference];
        if ([self activeConference]) {
            [labelText appendString:@"No sessions found."];
            
            if ([[[EMSAppDelegate sharedAppDelegate] model] sessionsAvailableForConference:[conference href]]) {
                [labelText appendString:@" Try"];
                
                if ([self.advancedSearch hasAdvancedSearch] || ![self.search.text isEqualToString:@""]) {
                    [labelText appendString:@" a less restrictive search,"];
                } else if (self.filterFavourites) {
                    [labelText appendString:@" switching back to the full list,"];
                }
                
                [labelText appendString:@" or you can refresh the session list with pull to refresh."];
            } else {
                [labelText appendString:@" Refreshing session list."];
            }
            
        } else {
            [labelText appendString:@"Refreshing session list."];
        }


        self.footerLabel.text = [NSString stringWithString:labelText];

        self.footer.hidden = NO;
    } else {
        self.footer.hidden = YES;
    }
}

- (void)initializeFetchedResultsController {
    [self setDefaultTypeSearch];

    [self.fetchedResultsController.fetchRequest setPredicate:[self currentConferencePredicate]];

    NSError *error;

    if (![[self fetchedResultsController] performFetch:&error]) {
        UIAlertView *errorAlert = [[UIAlertView alloc]
                initWithTitle:@"Unable to connect view to data store"
                      message:@"The data store did something unexpected and without it this application has no data to show. This is not an error we can recover from - please exit using the home button."
                     delegate:nil
            cancelButtonTitle:@"OK"
            otherButtonTitles:nil];
        [errorAlert show];

        CLS_LOG(@"Unresolved error %@, %@", error, [error userInfo]);
    }

    [self initializeFooter];

    [self.tableView reloadData];


}

- (NSPredicate *)currentConferencePredicate {
    Conference *activeConference = [self activeConference];
    
    if (activeConference != nil) {
        NSMutableArray *predicates = [[NSMutableArray alloc] init];
        
        [predicates
         addObject:[NSPredicate predicateWithFormat:@"((state == %@) AND (conference == %@))",
                    @"approved",
                    activeConference]];
        
        if (!([[self.advancedSearch search] isEqualToString:@""])) {
            [predicates
             addObject:[NSPredicate predicateWithFormat:@"(title CONTAINS[cd] %@ OR body CONTAINS[cd] %@ OR ANY speakers.name CONTAINS[cd] %@)",
                        [self.advancedSearch search],
                        [self.advancedSearch search],
                        [self.advancedSearch search]]];
        }
        
        if ([[self.advancedSearch fieldValuesForKey:emsLevel] count] > 0) {
            [predicates
             addObject:[NSPredicate predicateWithFormat:@"(level IN %@)",
                        [self.advancedSearch fieldValuesForKey:emsLevel]]];
        }

        if ([[self.advancedSearch fieldValuesForKey:emsType] count] > 0) {
            [predicates
             addObject:[NSPredicate predicateWithFormat:@"(format IN %@)",
                        [self.advancedSearch fieldValuesForKey:emsType]]];
        }

        if ([[self.advancedSearch fieldValuesForKey:emsRoom] count] > 0) {
            [predicates
             addObject:[NSPredicate predicateWithFormat:@"(room.name IN %@)",
                        [self.advancedSearch fieldValuesForKey:emsRoom]]];
        }
        
        if ([[self.advancedSearch fieldValuesForKey:emsKeyword] count] > 0) {
            NSMutableArray *keywordPredicates = [[NSMutableArray alloc] init];
            
            [[self.advancedSearch fieldValuesForKey:emsKeyword] enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
                NSString *keyword = (NSString *) obj;
                
                [keywordPredicates
                 addObject:[NSPredicate predicateWithFormat:@"(ANY keywords.name CONTAINS[cd] %@)",
                            keyword]];
            }];
            
            [predicates
             addObject:[NSCompoundPredicate orPredicateWithSubpredicates:keywordPredicates]];
        }
        
        if ([[self.advancedSearch fieldValuesForKey:emsLang] count] > 0) {
            NSSet *languages = [self.advancedSearch fieldValuesForKey:emsLang];
            
            NSMutableSet *langs = [[NSMutableSet alloc] init];
            
            [languages enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
                NSString *language = (NSString *) obj;
                
                if ([language isEqualToString:@"English"]) {
                    [langs addObject:@"en"];
                }
                
                if ([language isEqualToString:@"Norwegian"]) {
                    [langs addObject:@"no"];
                }
            }];
            
            [predicates
             addObject:[NSPredicate predicateWithFormat:@"(language IN %@)",
                        [NSSet setWithSet:langs]]];
        }
        
        if (self.filterFavourites) {
            [predicates
             addObject:[NSPredicate predicateWithFormat:@"favourite = %@", @YES]];
        }

        
        NSPredicate *resultPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:predicates];
        
#ifndef DO_NOT_USE_CRASHLYTICS
        [Crashlytics setObjectValue:resultPredicate forKey:@"activePredicate"];
#endif
        
        return resultPredicate;
    }
    
    return nil;
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
    
    NSSortDescriptor *sortSlot = [[NSSortDescriptor alloc]
                                  initWithKey:@"slotName" ascending:YES];
    NSSortDescriptor *sortRoom = [[NSSortDescriptor alloc]
                                  initWithKey:@"room.name" ascending:YES];
    NSSortDescriptor *sortTime = [[NSSortDescriptor alloc]
                                  initWithKey:@"slot.start" ascending:YES];
    NSSortDescriptor *sortTitle = [[NSSortDescriptor alloc]
                                   initWithKey:@"title" ascending:YES];
    
    [fetchRequest setSortDescriptors:@[sortSlot, sortRoom, sortTime, sortTitle]];
    [fetchRequest setFetchBatchSize:20];
    
    NSPredicate *conferencePredicate = [self currentConferencePredicate];
    
    if (conferencePredicate != nil) {
        [fetchRequest setPredicate:conferencePredicate];
    }
    
    NSFetchedResultsController *theFetchedResultsController =
    [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                        managedObjectContext:managedObjectContext sectionNameKeyPath:@"slotName"
                                                   cacheName:nil];
    
    self.fetchedResultsController = theFetchedResultsController;
    
    _fetchedResultsController.delegate = self;
    
    return _fetchedResultsController;
}

- (void)setDefaultTypeSearch {
    Conference *conference = [self activeConference];
    
    if (conference) {
        if ([[self.advancedSearch fieldValuesForKey:emsType] count] == 0) {
            NSArray *types = [self typesForConference:conference];
            
            NSMutableSet *typeNames = [[NSMutableSet alloc] init];
            
            [types enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                NSString *type = (NSString *)obj;
                
                if (![type isEqualToString:@"workshop"]) {
                    [typeNames addObject:type];
                }
            }];
            
            [self.advancedSearch setFieldValues:typeNames forKey:emsType];
        }
    }
}

#pragma  mark - Lifecycle Events

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Sessions";

    self.filterFavourites = NO;

    self.advancedSearch = [[EMSAdvancedSearch alloc] init];

    self.search.text = [self.advancedSearch search];
    
    [self setUpRefreshControl];

    // All sections start with the same year name - so the index is meaningless.
    // Can't turn it off - so let's have it only if we have at least 500 sections :)
    // This is also set in the storyboard but appears not to work.
    self.tableView.sectionIndexMinimumDisplayRowCount = 500;

    if (self.splitViewController) {
        self.splitViewController.delegate = self;
    }
    
    self.observersInstalled = NO;

}

static void  * kRefreshActiveConferenceContext = &kRefreshActiveConferenceContext;

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self addObservers];
}


- (void)viewDidAppear:(BOOL)animated {
    
    //This method should have been called in viewWillAppear, but UISplitViewController
    //does not call viewWillAppear on master view controller when app is launched in portrait mode
    //for some reason. This has been reported as a bug to Apple, the bug id 17291466.
    //As a workaround we call [self addObservers] again here. The addObservers method has
    //a guard to prevent that the observers are added twice.
    //TODO: Remove this line when Apple fixes bug 17291466.
    [self addObservers];
 
    
    [super viewDidAppear:animated];
    
#ifndef DO_NOT_USE_GA
    id <GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
    [tracker set:kGAIScreenName value:@"Main Screen"];
    [tracker send:[[GAIDictionaryBuilder createAppView] build]];
#endif
    
    Conference *conference = [self activeConference];
    
    if (conference) {
        CLS_LOG(@"Conference found - initialize");
        
        [self initializeFetchedResultsController];
    }
    
    [self updateRefreshControl];
    
    if (self.splitViewController) {
        if (self.tableView.numberOfSections > 0 && [self.tableView numberOfRowsInSection:0] > 0) {
            if ([self.tableView indexPathForSelectedRow] == nil) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
                [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionTop];
                [self performSegueWithIdentifier:@"showDetailsView" sender:self];
            }
        }
    }
    
    [self initializeFooter];
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

#pragma mark - Key Value Observing

- (void) addObservers {
    if (!self.observersInstalled) {
        [[EMSRetriever sharedInstance] addObserver:self forKeyPath:NSStringFromSelector(@selector(refreshingSessions)) options:0 context:kRefreshActiveConferenceContext];
        self.observersInstalled = YES;
    }
}

- (void) removeObservers {
    if (self.observersInstalled) {
        [[EMSRetriever sharedInstance] removeObserver:self forKeyPath:NSStringFromSelector(@selector(refreshingSessions))];
        self.observersInstalled = NO;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == kRefreshActiveConferenceContext) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateRefreshControl];
            
            if (![EMSRetriever sharedInstance].refreshingSessions) {
                if ([self activeConference]) {
                    [self initializeFetchedResultsController];
                }
            }
        });
    }
}


#pragma mark - Storyboard Segues

- (NSArray *)typesForConference:(Conference *)conference {
   NSMutableArray *types = [[NSMutableArray alloc] init];
   
   [conference.conferenceTypes enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
       ConferenceType *type = (ConferenceType *) obj;
    
       [types addObject:type.name];
   }];
   
    return [NSArray arrayWithArray:types];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    [self.search setShowsCancelButton:NO animated:YES];
    [self.search resignFirstResponder];
    
#ifndef DO_NOT_USE_GA
    id <GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
#endif
    
    if ([[segue identifier] isEqualToString:@"showDetailsView"]) {
        UIViewController *tmpDestination = [segue destinationViewController];
        if ([tmpDestination isKindOfClass:[UINavigationController class]]) {
            tmpDestination = tmpDestination.childViewControllers[0];
        }
        
        EMSDetailViewController *destination = (EMSDetailViewController *) tmpDestination;
        
        self.detailViewController = destination;
        
        if ([sender isKindOfClass:[NSString class]]) {
            Session *session = [[[EMSAppDelegate sharedAppDelegate] model] sessionForHref:(NSString *) sender];
            
            CLS_LOG(@"Preparing detail view from passed href %@", session);
            
            destination.session = session;
            
#ifndef DO_NOT_USE_CRASHLYTICS
            [Crashlytics setObjectValue:session.href forKey:@"lastDetailSessionFromNotification"];
#endif
            
#ifndef DO_NOT_USE_GA
            [tracker send:[[GAIDictionaryBuilder createEventWithCategory:@"listView"
                                                                  action:@"detailFromNotification"
                                                                   label:session.href
                                                                   value:nil] build]];
#endif
        } else {
            Session *session = [self.fetchedResultsController objectAtIndexPath:[self.tableView indexPathForSelectedRow]];
            
            CLS_LOG(@"Preparing detail view with %@", session);
            
            destination.session = session;
            
#ifndef DO_NOT_USE_CRASHLYTICS
            [Crashlytics setObjectValue:session.href forKey:@"lastDetailSession"];
#endif
            
#ifndef DO_NOT_USE_GA
            [tracker send:[[GAIDictionaryBuilder createEventWithCategory:@"listView"
                                                                  action:@"detail"
                                                                   label:session.href
                                                                   value:nil] build]];
#endif
        }
        
        destination.indexPath = [[self tableView] indexPathForSelectedRow];
    }
    
    if ([[segue identifier] isEqualToString:@"showSearchView"]) {
        UINavigationController *navigationController = [segue destinationViewController];
        EMSSearchViewController *destination = (EMSSearchViewController *) navigationController.childViewControllers[0];
        
        CLS_LOG(@"Preparing search view with %@ and conference %@", self.search.text, [self activeConference]);
        
        destination.advancedSearch = self.advancedSearch;
        
        Conference *conference = [self activeConference];
        
        NSMutableArray *levels = [[NSMutableArray alloc] init];
        
        [conference.conferenceLevels enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            ConferenceLevel *level = (ConferenceLevel *) obj;
            
            [levels addObject:level.name];
        }];
        
        NSString *filePath = [[NSBundle mainBundle] pathForResource:@"EMS-Config" ofType:@"plist"];
        NSDictionary *prefs = [[NSDictionary alloc] initWithContentsOfFile:filePath];
        NSDictionary *sort = prefs[@"level-sort"];
        
        destination.levels = [levels sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            NSNumber *firstKey = [sort valueForKey:obj1];
            NSNumber *secondKey = [sort valueForKey:obj2];
            
            if ([firstKey integerValue] > [secondKey integerValue]) {
                return (NSComparisonResult) NSOrderedDescending;
            }
            
            if ([firstKey integerValue] < [secondKey integerValue]) {
                return (NSComparisonResult) NSOrderedAscending;
            }
            return (NSComparisonResult) NSOrderedSame;
        }];
        
        NSMutableArray *keywords = [[NSMutableArray alloc] init];
        
        [conference.conferenceKeywords enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            ConferenceKeyword *keyword = (ConferenceKeyword *) obj;
            
            [keywords addObject:keyword.name];
        }];
        
        destination.keywords = [keywords sortedArrayUsingSelector:@selector(compare:)];
        
        NSMutableArray *rooms = [[NSMutableArray alloc] init];
        
        [conference.rooms enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            Room *room = (Room *) obj;
            
            [rooms addObject:room.name];
        }];
        
        destination.rooms = [rooms sortedArrayUsingSelector:@selector(compare:)];
        
        NSArray *types = [self typesForConference:conference];
        
        destination.types = [types sortedArrayUsingSelector:@selector(compare:)];
        
        destination.delegate = self;
        
#ifndef DO_NOT_USE_GA
        [tracker send:[[GAIDictionaryBuilder createEventWithCategory:@"listView"
                                                              action:@"search"
                                                               label:nil
                                                               value:nil] build]];
#endif
    }
}


- (IBAction)back:(UIStoryboardSegue *)segue {
    if ([[self.fetchedResultsController sections] count] > 0) {
        if ([segue.identifier isEqualToString:@"popDetailSegue"]) {
            EMSDetailViewController *detail = (EMSDetailViewController *) segue.sourceViewController;
            [self.tableView scrollToRowAtIndexPath:detail.indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
        }
    }
    
    if ([segue.identifier isEqualToString:@"unwindSettingsSegue"]) {
        self.advancedSearch = [[EMSAdvancedSearch alloc] init];
        
        self.search.text = [self.advancedSearch search];

        [self initializeFetchedResultsController];
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}



#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSUInteger count = [[_fetchedResultsController sections] count];

    CLS_LOG(@"numberOfSectionsInTableView: Found %lu sections", (unsigned long) count);

    return count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    id sectionInfo = [_fetchedResultsController sections][(NSUInteger) section];

    NSUInteger count = [sectionInfo numberOfObjects];

    CLS_LOG(@"tableView:numberOfRowsInSection: %ld: Found %lu rows", (long) section, (unsigned long) count);

    return count;
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    CLS_LOG(@"configureCell:atIndexPath: asking for section %ld and row %ld", (long) indexPath.section, (long) indexPath.row);

    Session *session = [_fetchedResultsController objectAtIndexPath:indexPath];

    EMSSessionCell *sessionCell = (EMSSessionCell *) cell;

    UIButton *icon = sessionCell.icon;

    [icon setSelected:[session.favourite boolValue]];

    NSString *imageBaseName = [session.format isEqualToString:@"lightning-talk"] ? @"64-zap" : @"28-star";
    NSString *imageNameFormat = @"%@-%@";

    UIImage *normalImage = [UIImage imageNamed:[NSString stringWithFormat:imageNameFormat, imageBaseName, @"grey"]];
    UIImage *selectedImage = [UIImage imageNamed:[NSString stringWithFormat:imageNameFormat, imageBaseName, @"yellow"]];

    if ([UIImage instancesRespondToSelector:@selector(imageWithRenderingMode:)]) {
        normalImage = [normalImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        selectedImage = [selectedImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        if (icon.selected) {
            icon.tintColor = nil;
        } else {
            icon.tintColor = [UIColor lightGrayColor];
        }
    }

    [icon setImage:normalImage forState:UIControlStateNormal];
    [icon setImage:selectedImage forState:UIControlStateSelected];

    [sessionCell.icon addTarget:self action:@selector(toggleFavourite:) forControlEvents:UIControlEventTouchUpInside];

    UIImageView *level = sessionCell.level;

    [level setImage:[UIImage imageNamed:session.level]];

    UIImageView *video = sessionCell.video;

    if (session.videoLink) {
        [video setImage:[UIImage imageNamed:@"70-tv"]];
    } else {
        [video setImage:nil];
    }

    sessionCell.title.text = session.title;
    if (session.room) {
        sessionCell.room.text = session.room.name;
    } else {
        sessionCell.room.text = @"";
    }

    NSMutableArray *speakerNames = [[NSMutableArray alloc] init];

    [session.speakers enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
        Speaker *speaker = (Speaker *) obj;

        [speakerNames addObject:speaker.name];
    }];

    sessionCell.speaker.text = [speakerNames componentsJoinedByString:@", "];

    sessionCell.session = session;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CLS_LOG(@"tableView:cellForRowAtIndexPath: asking for section %ld and row %ld", (long) indexPath.section, (long) indexPath.row);

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SessionCell"];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SessionCell"];
    }

    [self configureCell:cell atIndexPath:indexPath];

    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    id <NSFetchedResultsSectionInfo> sectionInfo = [_fetchedResultsController sections][(NSUInteger) section];
    return [sectionInfo name];
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return [_fetchedResultsController sectionIndexTitles];
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    return [_fetchedResultsController sectionForSectionIndexTitle:title atIndex:index];
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView beginUpdates];
}


- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type newIndexPath:(NSIndexPath *)newIndexPath {

    UITableView *tableView = self.tableView;

    switch (type) {

        case NSFetchedResultsChangeInsert:
            [tableView insertRowsAtIndexPaths:@[newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;

        case NSFetchedResultsChangeDelete:
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;

        case NSFetchedResultsChangeUpdate:
            [self configureCell:[tableView cellForRowAtIndexPath:indexPath] atIndexPath:indexPath];
            break;

        case NSFetchedResultsChangeMove:
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
            [tableView insertRowsAtIndexPaths:@[newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}


- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id)sectionInfo atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type {

    switch (type) {
        case NSFetchedResultsChangeInsert:
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;

        case NSFetchedResultsChangeDelete:
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;
        case NSFetchedResultsChangeMove:
            break;
        case NSFetchedResultsChangeUpdate:
            break;
    }
}


- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView endUpdates];
}


#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if ([searchText length] == 0) {
        [self performSelector:@selector(hideKeyboardWithSearchBar:) withObject:searchBar afterDelay:0];
    }

    [self storeSearchPrefs];

    [self initializeFetchedResultsController];
}

- (void)hideKeyboardWithSearchBar:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:NO animated:YES];
    [searchBar resignFirstResponder];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";

    [self storeSearchPrefs];

    [self initializeFetchedResultsController];

    [searchBar setShowsCancelButton:NO animated:YES];
    [searchBar resignFirstResponder];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [self storeSearchPrefs];

    [self initializeFetchedResultsController];

    [searchBar setShowsCancelButton:NO animated:YES];
    [searchBar resignFirstResponder];
}


#pragma mark - EMSSearchViewDelegate

- (void)advancedSearchUpdated {
    // Need to reload
    self.advancedSearch = [[EMSAdvancedSearch alloc] init];

    self.search.text = [self.advancedSearch search];

    [self initializeFetchedResultsController];

    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Actions

- (void)storeSearchPrefs {
    [self.advancedSearch setSearch:self.search.text];
}

- (void)retrieve {
    [[EMSRetriever sharedInstance] refreshActiveConference];
}

- (void)pushDetailViewForHref:(NSString *)href {
    [self performSegueWithIdentifier:@"showDetailsView" sender:href];
}

- (void)toggleFavourite:(id)sender {
    UIButton *button = (UIButton *) sender;
    
    UIView *view = [button superview];
    
    while (view != nil) {
        if ([view isKindOfClass:[EMSSessionCell class]]) {
            EMSSessionCell *cell = (EMSSessionCell *) view;
            
            Session *session = cell.session;
            
            [[[EMSAppDelegate sharedAppDelegate] model] toggleFavourite:session];
            
            break;
        }
        
        view = [view superview];
    }
    
    if (self.detailViewController != nil) {
        [self.detailViewController refreshFavourite];
    }
    
    [self.tableView reloadData];
}

- (void)segmentChanged:(id)sender {
    self.filterFavourites = NO;

#ifndef DO_NOT_USE_GA
    UISegmentedControl *segment = (UISegmentedControl *) sender;

    id <GAITracker> tracker = [[GAI sharedInstance] defaultTracker];

    switch ([segment selectedSegmentIndex]) {
        case 0: {
            // All
            [tracker send:[[GAIDictionaryBuilder createEventWithCategory:@"listView"
                                                                  action:@"all"
                                                                   label:nil
                                                                   value:nil] build]];
            break;
        }
        case 1: {
            // My
            [tracker send:[[GAIDictionaryBuilder createEventWithCategory:@"listView"
                                                                  action:@"favourites"
                                                                   label:nil
                                                                   value:nil] build]];
            self.filterFavourites = YES;
            break;
        }

        default:
            break;
    }
#endif

    [self initializeFetchedResultsController];
}

- (IBAction) scrollToNow:(id) sender {
    
    Conference *conference = [self activeConference];
    if (!conference) {
        return;
    }
    
    NSArray *sections = [self.fetchedResultsController sections];
    
    if ([sections count] == 0) {
        return;
    }
    
    NSMutableArray *mappedObjects = [NSMutableArray array];
    
    for (id <NSFetchedResultsSectionInfo> sectionInfo in sections) {
        if ([sectionInfo numberOfObjects] > 0) {
            Session *session = [sectionInfo objects].firstObject;
            [mappedObjects addObject:session.slot.end];
        }
    }
    
    NSRange range = NSMakeRange(0, [sections count]);

    NSArray *sortedDates = [mappedObjects sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [obj1 compare:obj2];
    }];
    
    
    NSDate *now = [[[EMSAppDelegate sharedAppDelegate] model] dateForConference:conference andDate:[NSDate date]];
   
    NSInteger index = [sortedDates indexOfObject:now inSortedRange:range options:NSBinarySearchingInsertionIndex usingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [obj1 compare:obj2];
    }];
    
    if (index != NSNotFound) {
        if (index >= [sections count]) {//scroll to end
            index = [sections count] - 1;
        }
        
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:index];
            
        [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionTop animated:YES];
        
    }
}


#pragma mark - UISplitViewControllerDelegate

- (BOOL)splitViewController:(UISplitViewController *)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)orientation {
    return NO;
}

@end

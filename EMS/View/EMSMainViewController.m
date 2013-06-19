//
//  EMSMainViewController.m
//

#import "EMSMainViewController.h"
#import "EMSModel.h"

#import "EMSSlot.h"

#import "EMSRetriever.h"

#import "EMSAppDelegate.h"

#import "EMSSettingsViewController.h"
#import "EMSDetailViewController.h"
#import "EMSSearchViewController.h"

#import "EMSSessionCell.h"

@interface EMSMainViewController ()

@end

@implementation EMSMainViewController

- (void) setUpRefreshControl {
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    
    refreshControl.tintColor = [UIColor grayColor];
    refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:@"Refresh available sessions"];
    
    [refreshControl addTarget:self action:@selector(retrieve) forControlEvents:UIControlEventValueChanged];
    
    self.refreshControl = refreshControl;
}

- (NSManagedObject *)conferenceForHref:(NSString *)href {
    CLS_LOG(@"Getting conference for %@", href);
    
    return [[[EMSAppDelegate sharedAppDelegate] model] conferenceForHref:href];
}

- (NSManagedObject *)activeConference {
    CLS_LOG(@"Getting current conference");
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *activeConference = [[defaults URLForKey:@"activeConference"] absoluteString];
    
    if (activeConference != nil) {
        return [self conferenceForHref:activeConference];
    }
    
    return nil;
}

- (void)initializeFetchedResultsController {
    [self.fetchedResultsController.fetchRequest setPredicate:[self currentConferencePredicate]];

    NSError *error;
    
    if (![[self fetchedResultsController] performFetch:&error]) {
        UIAlertView *errorAlert = [[UIAlertView alloc]
                                   initWithTitle: @"Unable to connect view to data store"
                                   message: @"The data store did something unexpected and without it this application has no data to show. This is not an error we can recover from - please exit using the home button."
                                   delegate:nil
                                   cancelButtonTitle:@"OK"
                                   otherButtonTitles:nil];
        [errorAlert show];
        
        CLS_LOG(@"Unresolved error %@, %@", error, [error userInfo]);
    }
    
    [self.tableView reloadData];

    if (![[[EMSAppDelegate sharedAppDelegate] model] sessionsAvailableForConference:[[self activeConference] valueForKey:@"href"]]) {
        CLS_LOG(@"Checking for existing data found no data - forced refresh");
        
        [self.refreshControl beginRefreshing];
        [self retrieve];
    }
}

- (void) conferenceChanged:(id)sender {
    CLS_LOG(@"Conference changed");
    
    [self initializeFetchedResultsController];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.retrievingSlots = NO;
    self.retrievingRooms = NO;

    self.filterFavourites = NO;
    self.filterTime = NO;

    self.search.text = @"";
    
    self.retriever = [[EMSRetriever alloc] init];
    self.retriever.delegate = self;

    [self setUpRefreshControl];

    // All sections start with the same year name - so the index is meaningless.
    // Can't turn it off - so let's have it only if we have at least 500 sections :)
    // This is also set in the storyboard but appears not to work.
    self.tableView.sectionIndexMinimumDisplayRowCount = 500;
    
    NSManagedObject *conference = [self activeConference];
    
    if (conference == nil) {
        CLS_LOG(@"No conference - push to settings view");

        [self performSegueWithIdentifier:@"showSettingsView" sender:self];
    } else {
        CLS_LOG(@"Conference found - initialize");

        [self initializeFetchedResultsController];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    [self.search resignFirstResponder];
    
    if ([[segue identifier] isEqualToString:@"showSettingsView"]) {
        EMSSettingsViewController *destination = (EMSSettingsViewController *)[segue destinationViewController];

        CLS_LOG(@"Preparing settings view");
        
        destination.delegate = self;
    }
    if ([[segue identifier] isEqualToString:@"showDetailsView"]) {
        EMSDetailViewController *destination = (EMSDetailViewController *)[segue destinationViewController];

        NSManagedObject *session = [self.fetchedResultsController objectAtIndexPath:[self.tableView indexPathForSelectedRow]];

        CLS_LOG(@"Preparing detail view with %@", session);

        destination.session = session;
    }
    if ([[segue identifier] isEqualToString:@"showSearchView"]) {
        EMSSearchViewController *destination = (EMSSearchViewController *)[segue destinationViewController];

        CLS_LOG(@"Preparing search view with %@ and conference %@", self.search.text, [self activeConference]);

        destination.currentSearch = self.search.text;
        destination.currentLevels = [NSSet setWithSet:self.currentLevels];
        destination.currentKeywords = [NSSet setWithSet:self.currentKeywords];

        NSMutableArray *levels = [[NSMutableArray alloc] init];
        [[[self activeConference] valueForKey:@"conferenceLevels"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSManagedObject *level = (NSManagedObject *)obj;

            [levels addObject:[level valueForKey:@"name"]];
        }];
        destination.levels = [levels sortedArrayUsingSelector: @selector(compare:)];

        NSMutableArray *keywords = [[NSMutableArray alloc] init];
        [[[self activeConference] valueForKey:@"conferenceKeywords"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSManagedObject *keyword = (NSManagedObject *)obj;

            [keywords addObject:[keyword valueForKey:@"name"]];
        }];
        destination.keywords = [keywords sortedArrayUsingSelector: @selector(compare:)];

        destination.delegate = self;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (NSPredicate *)currentConferencePredicate {
    NSManagedObject *activeConference = [self activeConference];
    
    if (activeConference != nil) {
        NSMutableArray *predicates = [[NSMutableArray alloc] init];
        
        [predicates
         addObject:[NSPredicate predicateWithFormat: @"((state == %@) AND (conference == %@))", @"approved",
                    activeConference]];

        if (!([self.search.text isEqualToString:@""])) {
            [predicates
             addObject:[NSPredicate predicateWithFormat:@"(title CONTAINS[cd] %@ OR ANY speakers.name CONTAINS[cd] %@)",
                        self.search.text,
                        self.search.text]];
        }

        if ([self.currentLevels count] > 0) {
            [predicates
             addObject:[NSPredicate predicateWithFormat:@"(level IN %@)",
                        self.currentLevels]];
        }


        if ([self.currentKeywords count] > 0) {
            NSMutableArray *keywordPredicates = [[NSMutableArray alloc] init];

            [self.currentKeywords enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
                NSString *keyword = (NSString *)obj;

                [keywordPredicates
                 addObject:[NSPredicate predicateWithFormat:@"(ANY keywords.name CONTAINS[cd] %@)",
                            keyword]];
            }];

            [predicates
             addObject:[NSCompoundPredicate orPredicateWithSubpredicates:keywordPredicates]];
        }

        if (self.filterFavourites == YES) {
            [predicates
             addObject:[NSPredicate predicateWithFormat:@"favourite = %@", [NSNumber numberWithBool:YES]]];
        }

        if (self.filterTime == YES) {
            NSSet *slots = [[[EMSAppDelegate sharedAppDelegate] model] activeSlotNamesForConference:activeConference];

            [predicates
             addObject:[NSPredicate predicateWithFormat:@"slot IN %@", slots]];
        }

        return [NSCompoundPredicate andPredicateWithSubpredicates:predicates];
    }

    return nil;
}

- (NSFetchedResultsController *)fetchedResultsController {
    if (_fetchedResultsController != nil) {
        return _fetchedResultsController;
    }

    NSManagedObjectContext *managedObjectContext = [[EMSAppDelegate sharedAppDelegate] managedObjectContext];
    
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

    [fetchRequest setSortDescriptors:[NSArray arrayWithObjects:sortSlot, sortRoom, sortTime, nil]];
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

- (void)toggleFavourite:(id)sender {
    UIButton *button = (UIButton *)sender;
    
	UIView *view = [button superview];
	
	while (view != nil) {
		if ([view isKindOfClass:[EMSSessionCell class]]) {
			EMSSessionCell *cell = (EMSSessionCell *)view;
			
            NSManagedObject *session = cell.session;
    
            CLS_LOG(@"Trying to toggle favourite for %@", session);
            
            BOOL isFavourite = [[session valueForKey:@"favourite"] boolValue];
    
            if (isFavourite == YES) {
                [session setValue:[NSNumber numberWithBool:NO] forKey:@"favourite"];
            } else {
                [session setValue:[NSNumber numberWithBool:YES] forKey:@"favourite"];
            }
    
            NSError *error;
            if (![[session managedObjectContext] save:&error]) {
                CLS_LOG(@"Failed to toggle favourite for %@, %@, %@", session, error, [error userInfo]);
        
                // TODO - die?
            }
			
			break;
		}
        
		view = [view superview];
    }
    
    [self.tableView reloadData];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [[_fetchedResultsController sections] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    id sectionInfo = [[_fetchedResultsController sections] objectAtIndex:section];
    
    return [sectionInfo numberOfObjects];
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    NSManagedObject *session = [_fetchedResultsController objectAtIndexPath:indexPath];

    EMSSessionCell *sessionCell = (EMSSessionCell *)cell;
    
    UIButton *icon = sessionCell.icon;
    
    UIImage *normalImage = [UIImage imageNamed:@"28-star-grey"];
    UIImage *selectedImage = [UIImage imageNamed:@"28-star-yellow"];
    UIImage *highlightedImage = [UIImage imageNamed:@"28-star"];

    if ([[session valueForKey:@"format"] isEqualToString:@"lightning-talk"]) {
        normalImage = [UIImage imageNamed:@"64-zap-grey"];
        selectedImage = [UIImage imageNamed:@"64-zap-yellow"];
        highlightedImage = [UIImage imageNamed:@"64-zap"];
    }

    [icon setImage:normalImage forState:UIControlStateNormal];
    [icon setImage:selectedImage forState:UIControlStateSelected];
    [icon setImage:highlightedImage forState:UIControlStateHighlighted];

    [icon setSelected:[[session valueForKey:@"favourite"] boolValue]];
    
    [sessionCell.icon addTarget:self action:@selector(toggleFavourite:) forControlEvents:UIControlEventTouchUpInside];

    sessionCell.title.text = [session valueForKey:@"title"];
    sessionCell.room.text = [[session valueForKey:@"room"] valueForKey:@"name"];
    
    NSMutableArray *speakerNames = [[NSMutableArray alloc] init];
    [[session valueForKey:@"speakers"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSManagedObject *speaker = (NSManagedObject *)obj;
        
        [speakerNames addObject:[speaker valueForKey:@"name"]];
    }];
    sessionCell.speaker.text = [speakerNames componentsJoinedByString:@", "];
    
    sessionCell.session = session;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SessionCell"];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SessionCell"];
    }
    
    [self configureCell:cell atIndexPath:indexPath];
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    id <NSFetchedResultsSectionInfo> sectionInfo = [[_fetchedResultsController sections] objectAtIndex:section];
    return [sectionInfo name];
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return [_fetchedResultsController sectionIndexTitles];
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    return [_fetchedResultsController sectionForSectionIndexTitle:title atIndex:index];
}

#pragma mark - retrieval

- (void) retrieve {
    NSManagedObject *conference = [self activeConference];

    CLS_LOG(@"Starting retrieval");

    if (conference != nil) {
        CLS_LOG(@"Starting retrieval - saw conf");

        if ([conference valueForKey:@"slotCollection"] != nil) {
            CLS_LOG(@"Starting retrieval - saw slot collection");
            self.retrievingSlots = YES;
            [self.retriever refreshSlots:[NSURL URLWithString:[conference valueForKey:@"slotCollection"]]];
        }
        if ([conference valueForKey:@"roomCollection"] != nil) {
            CLS_LOG(@"Starting retrieval - saw room collection");
            self.retrievingRooms = YES;
            [self.retriever refreshRooms:[NSURL URLWithString:[conference valueForKey:@"roomCollection"]]];
        }
    }
}

- (void) retrieveSessions {
    CLS_LOG(@"Starting retrieval of sessions");
    // Fetch sessions once rooms and slots are done. Don't want to get into a state when trying to persist sessions that it refers to non-existing room or slot
    if (self.retrievingRooms == NO && self.retrievingSlots == NO) {
        CLS_LOG(@"Starting retrieval of sessions - clear to go");
        [self.retriever refreshSessions:[NSURL URLWithString:[[self activeConference] valueForKey:@"sessionCollection"]]];
    }
}

- (void) finishedSlots:(NSArray *)slots forHref:(NSURL *)href {
    CLS_LOG(@"Storing slots %d", [slots count]);
    
    [[[EMSAppDelegate sharedAppDelegate] model] storeSlots:slots forHref:[href absoluteString] error:nil];

    self.retrievingSlots = NO;
    
    [self retrieveSessions];
}

- (void) finishedSessions:(NSArray *)sessions forHref:(NSURL *)href {
    CLS_LOG(@"Storing sessions %d", [sessions count]);

    [[[EMSAppDelegate sharedAppDelegate] model] storeSessions:sessions forHref:[href absoluteString] error:nil];
    
    [self.refreshControl endRefreshing];
}

- (void) finishedRooms:(NSArray *)rooms forHref:(NSURL *)href {
    CLS_LOG(@"Storing rooms %d", [rooms count]);

    [[[EMSAppDelegate sharedAppDelegate] model] storeRooms:rooms forHref:[href absoluteString] error:nil];
    
    self.retrievingRooms = NO;
    
    [self retrieveSessions];
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView beginUpdates];
}


- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type newIndexPath:(NSIndexPath *)newIndexPath {
    
    UITableView *tableView = self.tableView;
    
    switch(type) {
            
        case NSFetchedResultsChangeInsert:
            [tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeDelete:
            [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeUpdate:
            [self configureCell:[tableView cellForRowAtIndexPath:indexPath] atIndexPath:indexPath];
            break;
            
        case NSFetchedResultsChangeMove:
            [tableView deleteRowsAtIndexPaths:[NSArray
                                               arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
            [tableView insertRowsAtIndexPaths:[NSArray
                                               arrayWithObject:newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}


- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id )sectionInfo atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type {
    
    switch(type) {
            
        case NSFetchedResultsChangeInsert:
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeDelete:
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}


- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView endUpdates];
}


- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
	if ([searchText length] == 0) {
        [self performSelector:@selector(hideKeyboardWithSearchBar:) withObject:searchBar afterDelay:0];
	}
    
    self.search.text = [searchBar text];

    [self initializeFetchedResultsController];
}

- (void)hideKeyboardWithSearchBar:(UISearchBar *)searchBar
{
    [searchBar setShowsCancelButton:NO animated:YES];
    [searchBar resignFirstResponder];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    
    self.search.text = [searchBar text];

    [self initializeFetchedResultsController];

    [searchBar setShowsCancelButton:NO animated:YES];
    [searchBar resignFirstResponder];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    self.search.text = [searchBar text];

    [self initializeFetchedResultsController];
	
    [searchBar setShowsCancelButton:NO animated:YES];
    [searchBar resignFirstResponder];
}

- (void) setSearchText:(NSString *)searchText withKeywords:(NSSet *)keywords andLevels:(NSSet *)levels {
    self.search.text = searchText;

    self.currentLevels = [NSSet setWithSet:levels];
    self.currentKeywords = [NSSet setWithSet:keywords];

    [self initializeFetchedResultsController];
}

- (void) segmentChanged:(id)sender {
    UISegmentedControl *segment = (UISegmentedControl *)sender;

    self.filterFavourites = NO;
    self.filterTime = NO;

    switch ([segment selectedSegmentIndex]) {
        case 0:
        {
            // All
            break;
        }
        case 1:
        {
            // My
            self.filterFavourites = YES;
            break;
        }
        case 2:
        {
            // Now / Next
            self.filterTime = YES;
            break;
        }

        default:
            break;
    }

    [self initializeFetchedResultsController];
}

@end

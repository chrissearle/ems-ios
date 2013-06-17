//
//  EMSSettingsViewController.m
//

#import "EMSSettingsViewController.h"

// TODO - Temp - get conferences directly - needs to move to model
#import "EMSRetriever.h"

#import "EMSConference.h"
#import "EMSSlot.h"

#import "EMSAppDelegate.h"

#import "EMSMainViewController.h"

#import "EMSModel.h"

@interface EMSSettingsViewController ()

@end

@implementation EMSSettingsViewController

@synthesize fetchedResultsController = _fetchedResultsController;
@synthesize delegate;
@synthesize model;

- (void) setUpRefreshControl {
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    
    refreshControl.tintColor = [UIColor grayColor];
    refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:@"Refresh available conferences"];
    
    [refreshControl addTarget:self action:@selector(retrieve) forControlEvents:UIControlEventValueChanged];
    
    self.refreshControl = refreshControl;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.model = [[EMSAppDelegate sharedAppDelegate] model];
    
    [self setUpRefreshControl];
    
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
    
    id sectionInfo = [[_fetchedResultsController sections] objectAtIndex:0];
    
    if ([sectionInfo numberOfObjects] == 0) {
        [self.refreshControl beginRefreshing];
        [self retrieve];
    }
}

- (void)viewDidUnload
{
    self.model = nil;
    self.fetchedResultsController = nil;
}

- (NSFetchedResultsController *)fetchedResultsController {
    
    if (_fetchedResultsController != nil) {
        return _fetchedResultsController;
    }

    NSManagedObjectContext *managedObjectContext = [[EMSAppDelegate sharedAppDelegate] managedObjectContext];
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription
                                   entityForName:@"Conference" inManagedObjectContext:managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSSortDescriptor *sort = [[NSSortDescriptor alloc]
                              initWithKey:@"name" ascending:NO];
    [fetchRequest setSortDescriptors:[NSArray arrayWithObject:sort]];
    
    [fetchRequest setFetchBatchSize:20];
    
    NSFetchedResultsController *theFetchedResultsController =
    [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                        managedObjectContext:managedObjectContext sectionNameKeyPath:nil
                                                   cacheName:@"Conferences"];
    self.fetchedResultsController = theFetchedResultsController;

    _fetchedResultsController.delegate = self;
    
    return _fetchedResultsController;
}

- (void) retrieve {
    EMSRetriever *retriever = [[EMSRetriever alloc] init];
    
    retriever.delegate = self;
    
    CLS_LOG(@"Retrieving conferences");
    
    [retriever refreshConferences];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}



- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    id sectionInfo = [[_fetchedResultsController sections] objectAtIndex:section];

    return [sectionInfo numberOfObjects];
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    NSManagedObject *conference = [_fetchedResultsController objectAtIndexPath:indexPath];
        
    cell.textLabel.text = [NSString stringWithFormat:@"%@ - %@",
                           [conference valueForKey:@"name"],
                           [conference valueForKey:@"venue"]];
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        
    [dateFormatter setDateFormat:@"yyyy-MM-dd"];
        
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@",
                                 [dateFormatter stringFromDate:[conference valueForKey:@"start"]],
                                 [dateFormatter stringFromDate:[conference valueForKey:@"end"]]];
        
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *activeConference = [[defaults URLForKey:@"activeConference"] absoluteString];
    NSString *cellConference   = [conference valueForKey:@"href"];
        
    if ([cellConference isEqualToString:activeConference]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ConferenceCell"];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ConferenceCell"];
    }

    [self configureCell:cell atIndexPath:indexPath];
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Available Conferences";
}


- (void)finishedConferences:(NSArray *)conferenceList forHref:(NSURL *)href {
    [self.model storeConferences:conferenceList error:nil];

    [self.refreshControl endRefreshing];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *currentConference = [[defaults URLForKey:@"activeConference"] absoluteString];
    
    NSManagedObject *conference = [_fetchedResultsController objectAtIndexPath:indexPath];
    
    [defaults setURL:[NSURL URLWithString:[conference valueForKey:@"href"]] forKey:@"activeConference"];

    [self.tableView reloadData];
    

    if (!([[conference valueForKey:@"href"] isEqualToString:currentConference])) {
        [delegate conferenceChanged:self];
    }
    
    [self.navigationController popViewControllerAnimated:YES];
}


#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    // The fetch controller is about to start sending change notifications, so prepare the table view for updates.
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
    // The fetch controller has sent all current change notifications, so tell the table view to process all updates.
    [self.tableView endUpdates];
}

@end
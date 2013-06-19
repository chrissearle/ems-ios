//
//  EMSMainViewController.h
//

#import <UIKit/UIKit.h>

#import "EMSRetrieverDelegate.h"
#import "EMSConferenceChangedDelegate.h"
#import "EMSSearchViewDelegate.h"
#import "EMSRetriever.h"

#import "EMSModel.h"

@interface EMSMainViewController : UITableViewController <UITableViewDataSource, UITableViewDelegate, EMSRetrieverDelegate, EMSConferenceChangedDelegate, NSFetchedResultsControllerDelegate, UISearchBarDelegate, EMSSearchViewDelegate>

@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;
@property (nonatomic, strong) EMSRetriever *retriever;

@property (nonatomic, assign) BOOL retrievingSlots;
@property (nonatomic, assign) BOOL retrievingRooms;

@property (nonatomic, assign) BOOL filterFavourites;
@property (nonatomic, assign) BOOL filterTime;

@property (nonatomic, strong) NSSet *currentLevels;
@property (nonatomic, strong) NSSet *currentKeywords;

@property (nonatomic, strong) IBOutlet UISearchBar *search;

- (IBAction)toggleFavourite:(id)sender;
- (IBAction)segmentChanged:(id)sender;

- (void)pushDetailViewForHref:(NSString *)href;

@end

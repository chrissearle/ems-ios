//
//  EMSDetailViewController.h
//

#import <UIKit/UIKit.h>
#import "EMSRetrieverDelegate.h"

#import "Session.h"

@interface EMSDetailViewController : UITableViewController

@property(nonatomic, strong) Session *session;

@end

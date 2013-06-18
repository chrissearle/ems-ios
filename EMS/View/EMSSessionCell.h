//
//  EMSSessionCell.h
//

#import <UIKit/UIKit.h>

@interface EMSSessionCell : UITableViewCell

@property (nonatomic, strong) IBOutlet UILabel *title;
@property (nonatomic, strong) IBOutlet UILabel *room;
@property (nonatomic, strong) IBOutlet UILabel *speaker;
@property (nonatomic, strong) IBOutlet UIButton *icon;
@property (nonatomic, strong) NSManagedObject *session;

@end
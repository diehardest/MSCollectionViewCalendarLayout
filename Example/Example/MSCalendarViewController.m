//
//  MSCalendarViewController.m
//  Example
//
//  Created by Eric Horacek on 2/26/13.
//  Copyright (c) 2013 Monospace Ltd. All rights reserved.
//

#import "MSCalendarViewController.h"
#import "MSCollectionViewCalendarLayout.h"
#import "MSEvent.h"
// Collection View Reusable Views
#import "MSGridline.h"
#import "MSTimeRowHeaderBackground.h"
#import "MSDayColumnHeaderBackground.h"
#import "MSEventCell.h"
#import "MSDayColumnHeader.h"
#import "MSTimeRowHeader.h"
#import "MSCurrentTimeIndicator.h"
#import "MSCurrentTimeGridline.h"

NSString * const MSEventCellReuseIdentifier = @"MSEventCellReuseIdentifier";
NSString * const MSDayColumnHeaderReuseIdentifier = @"MSDayColumnHeaderReuseIdentifier";
NSString * const MSTimeRowHeaderReuseIdentifier = @"MSTimeRowHeaderReuseIdentifier";

@interface MSCalendarViewController () <MSCollectionViewDelegateCalendarLayout, NSFetchedResultsControllerDelegate, UICollectionViewDelegate>

@property (nonatomic, strong) MSCollectionViewCalendarLayout *collectionViewCalendarLayout;
@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;

@property (nonatomic, strong) NSCalendar *calendar;
@property (nonatomic, strong) NSDate *fromDate;
@property (nonatomic, strong) NSDate *toDate;

@end

@implementation MSCalendarViewController

- (id)init
{
    self.collectionViewCalendarLayout = [[MSCollectionViewCalendarLayout alloc] init];
    self.collectionViewCalendarLayout.delegate = self;
    self = [super initWithCollectionViewLayout:self.collectionViewCalendarLayout];
    
    return self;
}

- (void)fixUIForiOS7
{
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [self setEdgesForExtendedLayout:UIRectEdgeNone];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.collectionView.backgroundColor = [UIColor whiteColor];
    
    [self.collectionView registerClass:MSEventCell.class forCellWithReuseIdentifier:MSEventCellReuseIdentifier];
    [self.collectionView registerClass:MSDayColumnHeader.class forSupplementaryViewOfKind:MSCollectionElementKindDayColumnHeader withReuseIdentifier:MSDayColumnHeaderReuseIdentifier];
    [self.collectionView registerClass:MSTimeRowHeader.class forSupplementaryViewOfKind:MSCollectionElementKindTimeRowHeader withReuseIdentifier:MSTimeRowHeaderReuseIdentifier];
    
    // These are optional. If you don't want any of the decoration views, just don't register a class for them.
    [self.collectionViewCalendarLayout registerClass:MSCurrentTimeIndicator.class forDecorationViewOfKind:MSCollectionElementKindCurrentTimeIndicator];
    [self.collectionViewCalendarLayout registerClass:MSCurrentTimeGridline.class forDecorationViewOfKind:MSCollectionElementKindCurrentTimeHorizontalGridline];
    [self.collectionViewCalendarLayout registerClass:MSGridline.class forDecorationViewOfKind:MSCollectionElementKindVerticalGridline];
    [self.collectionViewCalendarLayout registerClass:MSGridline.class forDecorationViewOfKind:MSCollectionElementKindHorizontalGridline];
    [self.collectionViewCalendarLayout registerClass:MSTimeRowHeaderBackground.class forDecorationViewOfKind:MSCollectionElementKindTimeRowHeaderBackground];
    [self.collectionViewCalendarLayout registerClass:MSDayColumnHeaderBackground.class forDecorationViewOfKind:MSCollectionElementKindDayColumnHeaderBackground];
    
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Event"];
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"start" ascending:YES]];
    // No events with undecided times or dates
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"(dateToBeDecided == NO) AND (timeToBeDecided == NO)"];
    // Divide into sections by the "day" key path
    self.fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:[RKManagedObjectStore defaultStore].mainQueueManagedObjectContext sectionNameKeyPath:@"day" cacheName:nil];
    self.fetchedResultsController.delegate = self;
    [self.fetchedResultsController performFetch:nil];
    
    
    //Setting up calendar and days
    _calendar = [NSCalendar currentCalendar];
    NSDate *now = [_calendar dateFromComponents:[_calendar components:NSYearCalendarUnit|NSMonthCalendarUnit fromDate:[NSDate date]]];
    
    _fromDate = [_calendar dateByAddingComponents:((^{
        NSDateComponents *components = [NSDateComponents new];
        components.month = -1;
        return components;
    })()) toDate:now options:0];
    
    _toDate = [_calendar dateByAddingComponents:((^{
        NSDateComponents *components = [NSDateComponents new];
        components.month = 1;
        return components;
    })()) toDate:now options:0];
    
    
    //Style the NavigationController
    self.title = @"June";
    UIBarButtonItem *todayButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Today", @"Today") style:UIBarButtonItemStyleBordered target:self action:@selector(todayButtonTapped:)];
    [self setToolbarItems:@[todayButton]];
    [self.navigationController setToolbarHidden:NO];
    
    //iOS7 UI
    [self fixUIForiOS7];
    
    //Load the data
    [self loadData];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.collectionViewCalendarLayout scrollCollectionViewToClosetSectionToCurrentTimeAnimated:NO];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    // On iPhone, adjust width of sections on interface rotation. No necessary in horizontal layout (iPad)
    if (self.collectionViewCalendarLayout.sectionLayoutType == MSSectionLayoutTypeVerticalTile) {
        [self.collectionViewCalendarLayout invalidateLayoutCache];
        // These are the only widths that are defined by default. There are more that factor into the overall width.
        self.collectionViewCalendarLayout.sectionWidth = (CGRectGetWidth(self.collectionView.frame) - self.collectionViewCalendarLayout.timeRowHeaderWidth - self.collectionViewCalendarLayout.contentMargin.right);
        [self.collectionView reloadData];
    }
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

#pragma mark - MSCalendarViewController

- (void)loadData
{
    [[RKObjectManager sharedManager] getObjectsAtPath:@"events" parameters:@{
        @"lat" : @(39.750),             // Denver latitude
        @"lon" : @(-104.984),           // Denver longitude
        @"range" : @"10mi",             // 10mi search radius
        @"taxonomies.name" : @"sports", // Only "sports" taxonomies
        @"per_page" : @500              // Up to 500 results
    } success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        NSLog(@"Successfully loaded %@ events", @(mappingResult.count));
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        [[[UIAlertView alloc] initWithTitle:@"Unable to Load Events" message:[error localizedDescription] delegate:nil cancelButtonTitle:@"Continue" otherButtonTitles:nil] show];
    }];
}





#pragma mark - UIScrollViewDelegate

//Used to create infinite scrolling

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    float rightEdge = scrollView.contentOffset.x + scrollView.frame.size.width;
    float leftEdge = scrollView.contentOffset.x - scrollView.frame.size.width;
    if (rightEdge >= scrollView.contentSize.width) {
        // we are at the end
        NSLog(@"SCROLLED TO RIGHT");
		[self appendFutureDates];
    }
    if (leftEdge <= 0) {
        NSLog(@"SCROLLED TO LEFT");
        [self appendPastDates];
    }
}

- (void) appendPastDates {
    
	[self shiftDatesByComponents:((^{
		NSDateComponents *dateComponents = [NSDateComponents new];
		dateComponents.month = -1;
		return dateComponents;
	})())];
    
}

- (void) appendFutureDates {
	
	[self shiftDatesByComponents:((^{
		NSDateComponents *dateComponents = [NSDateComponents new];
		dateComponents.month = 1;
		return dateComponents;
	})())];
	
}

- (void) shiftDatesByComponents:(NSDateComponents *)components {
	
	UICollectionView *cv = self.collectionView;

	MSCollectionViewCalendarLayout *cvLayout = (MSCollectionViewCalendarLayout *)self.collectionView.collectionViewLayout;

	NSArray *visibleCells = [self.collectionView visibleCells];
	if (![visibleCells count])
		return;

	NSIndexPath *fromIndexPath = [cv indexPathForCell:((UICollectionViewCell *)visibleCells[0]) ];
	NSInteger fromSection = fromIndexPath.section;
	NSDate *fromSectionOfDate = [self dateForFirstDayInSection:fromSection];
    UICollectionViewLayoutAttributes *fromAttrs = [cvLayout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:fromSection]];
	CGPoint fromSectionOrigin = [self.collectionView convertPoint:fromAttrs.frame.origin fromView:cv];
//
	_fromDate = [self.calendar dateByAddingComponents:components toDate:self.fromDate options:0];
	_toDate = [self.calendar dateByAddingComponents:components toDate:self.toDate options:0];
    
    

#if 0
	
	//	This solution trips up the collection view a bit
	//	because our reload is reactionary, and happens before a relayout
	//	since we must do it to avoid flickering and to heckle the CA transaction (?)
	//	that could be a small red flag too
	
	[cv performBatchUpdates:^{
		
		if (components.month < 0) {
			
			[cv deleteSections:[NSIndexSet indexSetWithIndexesInRange:(NSRange){
				cv.numberOfSections - abs(components.month),
				abs(components.month)
			}]];
			
			[cv insertSections:[NSIndexSet indexSetWithIndexesInRange:(NSRange){
				0,
				abs(components.month)
			}]];
			
		} else {
			
			[cv insertSections:[NSIndexSet indexSetWithIndexesInRange:(NSRange){
				cv.numberOfSections,
				abs(components.month)
			}]];
			
			[cv deleteSections:[NSIndexSet indexSetWithIndexesInRange:(NSRange){
				0,
				abs(components.month)
			}]];
			
		}
		
	} completion:^(BOOL finished) {
		
		NSLog(@"%s %x", __PRETTY_FUNCTION__, finished);
		
	}];
	
	for (UIView *view in cv.subviews)
		[view.layer removeAllAnimations];
	
#else
	
	[cv reloadData];
	[cvLayout invalidateLayout];
	[cvLayout prepareLayout];
    
#endif
	
	NSInteger toSection = [self.calendar components:NSMonthCalendarUnit fromDate:[self dateForFirstDayInSection:0] toDate:fromSectionOfDate options:0].month;
	UICollectionViewLayoutAttributes *toAttrs = [cvLayout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:toSection]];
	CGPoint toSectionOrigin = [self.collectionView convertPoint:toAttrs.frame.origin fromView:cv];
	
	[cv setContentOffset:(CGPoint) {
		cv.contentOffset.x,
		cv.contentOffset.y + (toSectionOrigin.y - fromSectionOrigin.y)
	}];
	
}

- (NSDate *) dateForFirstDayInSection:(NSInteger)section {
    
	return [self.calendar dateByAddingComponents:((^{
		NSDateComponents *dateComponents = [NSDateComponents new];
		dateComponents.month = section;
		return dateComponents;
	})()) toDate:self.fromDate options:0];
    
}

- (NSUInteger) numberOfWeeksForMonthOfDate:(NSDate *)date {
    
	NSDate *firstDayInMonth = [self.calendar dateFromComponents:[self.calendar components:NSYearCalendarUnit|NSMonthCalendarUnit fromDate:date]];
	
	NSDate *lastDayInMonth = [self.calendar dateByAddingComponents:((^{
		NSDateComponents *dateComponents = [NSDateComponents new];
		dateComponents.month = 1;
		dateComponents.day = -1;
		return dateComponents;
	})()) toDate:firstDayInMonth options:0];
	
	NSDate *fromSunday = [self.calendar dateFromComponents:((^{
		NSDateComponents *dateComponents = [self.calendar components:NSWeekOfYearCalendarUnit|NSYearForWeekOfYearCalendarUnit fromDate:firstDayInMonth];
		dateComponents.weekday = 1;
		return dateComponents;
	})())];
	
	NSDate *toSunday = [self.calendar dateFromComponents:((^{
		NSDateComponents *dateComponents = [self.calendar components:NSWeekOfYearCalendarUnit|NSYearForWeekOfYearCalendarUnit fromDate:lastDayInMonth];
		dateComponents.weekday = 1;
		return dateComponents;
	})())];
	
	return 1 + [self.calendar components:NSWeekCalendarUnit fromDate:fromSunday toDate:toSunday options:0].week;
	
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    [self.collectionViewCalendarLayout invalidateLayoutCache];
    [self.collectionView reloadData];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    NSInteger sections = [self.calendar components:NSDayCalendarUnit fromDate:self.fromDate toDate:self.toDate options:0].day;
    NSLog(@"sections: %d", sections);
	return sections;
}

- (NSDate*)dateForSection:(NSInteger)section
{
    NSDate *newDate = [self.calendar dateByAddingComponents:((^{
        NSDateComponents *components = [NSDateComponents new];
        components.day = section;
        return components;
    })()) toDate:self.fromDate options:0];
    return newDate;
}

- (NSInteger)sectionForDate:(NSDate*)day
{

    return [[self.fetchedResultsController.sections valueForKey:@"name"] indexOfObject:[NSString stringWithFormat:@"%@", day]];

// Another way
//    NSInteger index = [self.fetchedResultsController.sections indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
//        NSString *sectionName = [[self.fetchedResultsController.sections objectAtIndex:idx] name];
//        return [sectionName isEqualToString:[NSString stringWithFormat:@"%@",day]];
//    }];
//    return index;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    NSDate *date = [self dateForSection:section];
    NSInteger index = [self sectionForDate:date];
    if (index == NSNotFound) {
        return 0;
    }
    return [(id <NSFetchedResultsSectionInfo>)self.fetchedResultsController.sections[index] numberOfObjects];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    MSEventCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:MSEventCellReuseIdentifier forIndexPath:indexPath];
    
    NSDate *date = [self dateForSection:indexPath.section];
    NSInteger index = [self sectionForDate:date];
    MSEvent *event = [self.fetchedResultsController objectAtIndexPath:[NSIndexPath indexPathForRow:indexPath.row inSection:index]];
    cell.event = event;
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    UICollectionReusableView *view;
    if (kind == MSCollectionElementKindDayColumnHeader) {
        MSDayColumnHeader *dayColumnHeader = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:MSDayColumnHeaderReuseIdentifier forIndexPath:indexPath];
//        NSDate *day = [self.collectionViewCalendarLayout dateForDayColumnHeaderAtIndexPath:indexPath];
        NSDate *day = [self dateForSection:indexPath.section];
        NSDate *currentDay = [self currentTimeComponentsForCollectionView:self.collectionView layout:self.collectionViewCalendarLayout];
        dayColumnHeader.day = day;
        dayColumnHeader.currentDay = [[day beginningOfDay] isEqualToDate:[currentDay beginningOfDay]];
        view = dayColumnHeader;
        
        //Also set the title!
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"MMM yyyy"];
        self.title = [df stringFromDate:day];
        
    } else if (kind == MSCollectionElementKindTimeRowHeader) {
        MSTimeRowHeader *timeRowHeader = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:MSTimeRowHeaderReuseIdentifier forIndexPath:indexPath];
        timeRowHeader.time = [self.collectionViewCalendarLayout dateForTimeRowHeaderAtIndexPath:indexPath];
        view = timeRowHeader;
    }
    return view;
}

#pragma mark - MSCollectionViewCalendarLayout

- (NSDate *)collectionView:(UICollectionView *)collectionView layout:(MSCollectionViewCalendarLayout *)collectionViewCalendarLayout dayForSection:(NSInteger)section
{
    //The CollectionView is not driven by the NSFetchedResultsController sections anymore
//    id <NSFetchedResultsSectionInfo> sectionInfo = [self.fetchedResultsController.sections objectAtIndex:section];
//    MSEvent *event = [sectionInfo.objects firstObject];
//    return event.day;
    
    NSDate *day = [self dateForSection:section];
    return day;

}

- (NSDate *)collectionView:(UICollectionView *)collectionView layout:(MSCollectionViewCalendarLayout *)collectionViewCalendarLayout startTimeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSIndexPath *eventIndexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:[self sectionForDate:[self dateForSection:indexPath.section]]];
    MSEvent *event = [self.fetchedResultsController objectAtIndexPath:eventIndexPath];
    return event.start;
}

- (NSDate *)collectionView:(UICollectionView *)collectionView layout:(MSCollectionViewCalendarLayout *)collectionViewCalendarLayout endTimeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSIndexPath *eventIndexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:[self sectionForDate:[self dateForSection:indexPath.section]]];
    MSEvent *event = [self.fetchedResultsController objectAtIndexPath:eventIndexPath];
    // Most sports last ~3 hours, and SeatGeek doesn't provide an end time
    return [event.start dateByAddingTimeInterval:(60 * 60 * 3)];
}

- (NSDate *)currentTimeComponentsForCollectionView:(UICollectionView *)collectionView layout:(MSCollectionViewCalendarLayout *)collectionViewCalendarLayout
{
    return [NSDate date];
}

#pragma mark - Actions

- (void)todayButtonTapped:(id)sender
{
    [self.collectionViewCalendarLayout scrollCollectionViewToClosetSectionToCurrentTimeAnimated:YES];
}

@end

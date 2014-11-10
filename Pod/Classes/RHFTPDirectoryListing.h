//
//  RHFTPDirectoryListing.h
//  iCED
//
//  Created by Ryan on 2010-08-16.
//  Copyright 2010 Murage Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@protocol RHFTPDirectoryListingDelegate;

@interface RHFTPDirectoryListing : NSObject<NSStreamDelegate> {
    UITextField *_urlText;
    UIActivityIndicatorView *_activityIndicator;
    UITableView *_tableView;
    UIBarButtonItem *_listOrCancelButton;
    
    NSInputStream *_networkStream;
    NSMutableData *_listData;
    NSMutableDictionary *_listEntries;           // of NSDictionary as returned by CFFTPCreateParsedResourceListing
    NSString *_status;
	
	NSURL *url;
	id<RHFTPDirectoryListingDelegate> delegate;
}

@property(nonatomic,assign) id<RHFTPDirectoryListingDelegate> delegate;
@property(nonatomic,retain) NSMutableDictionary *listEntries;

- (id)initWithFtpUrl:(NSURL *)theUrl;
- (void)startReceive;

@end


@protocol RHFTPDirectoryListingDelegate<NSObject>
@optional
- (void)directoryListingAvailable:(RHFTPDirectoryListing *)directoryListing;
- (void)directoryListingDidFailToEstablishConnection:(RHFTPDirectoryListing *)directoryListing withError:(NSError *)error;
@end

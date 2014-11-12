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
@class RHDownloadItem;

@interface RHFTPDirectoryListing : NSObject<NSStreamDelegate> {
    NSInputStream *_networkStream;
    NSMutableData *_listData;
    NSMutableDictionary *_listEntries;           // of NSDictionary as returned by CFFTPCreateParsedResourceListing
    NSString *_status;
	
	RHDownloadItem *_downloadItem;
	id<RHFTPDirectoryListingDelegate> delegate;
}

@property(nonatomic,assign) id<RHFTPDirectoryListingDelegate> delegate;
@property(nonatomic,retain) NSMutableDictionary *listEntries;

- (id)initWithDownloadItem:(RHDownloadItem *)theDownloadItem;
- (void)startReceive;

@end


@protocol RHFTPDirectoryListingDelegate<NSObject>
@optional
- (void)directoryListingAvailable:(RHFTPDirectoryListing *)directoryListing;
- (void)directoryListingDidFailToEstablishConnection:(RHFTPDirectoryListing *)directoryListing withError:(NSError *)error;
@end

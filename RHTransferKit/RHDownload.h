//
//  RHDownload.h
//  RHUtil
//
//  Created by Ryan Homer on 2010-02-17.
//  Copyright 2010 Murage Inc.. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WTClient.h"
#import "RHDownloadTableViewCellDelegate.h"
#import "RHDownloadItem.h"
#import "RHFTPDownloadClient.h"
#import "RHFTPDirectoryListing.h"

enum {
	// Queued (download will start automatically when possible)
	RHDownloadStatusNew							=   0x01,	// 1 New download that has never been started (queued)
	RHDownloadStatusPausedForAutoResume 		=   0x02,	// 2 Download paused due to application shutdown (queued)
	RHDownloadStatusQueued						=   0x04,	// 4 Download is queued and will start when current download has been completed (queued)
	RHDownloadCombinedStatusQueued				=   0x0F,
	
	// Stopped (download must be restarted manually)
	RHDownloadStatusWaiting						=   0x10,	//   16 Download has been paused by user (stopped)
	RHDownloadStatusTransferCompleted			=   0x20,	//   32 Download has been completed (stopped)
	RHDownloadStatusDownloadSkipped				=   0x40,	//   64 Download terminated because file date not newer than given date (stopped)
	RHDownloadStatusInvalidUrl					=   0x80,	//  128 File not found on server for the given URL (stopped)
	//RHDownloadStatusInvalidFile				=  0x100,
	RHDownloadStatusAllProcessesCompleted		=  0x200,	//  512 Finished downloading, decompressing, etc. (stopped)
	RHDownloadStatusUnknownResponse				=  0x400,	// 1024 Unhandled status code in iCED (stopped).
	RHDownloadStatusFailedAuthentication		=  0x800,	// 2048 Incorrect username/password.
	RHDownloadCombinedStatusStopped				=  0xFF0,
	
	// Processing
	RHDownloadStatusWaitingForDownload			= 0x1000,	//  4096 Download was initiated; waiting for it to start
	RHDownloadStatusDownloading					= 0x2000,	//  8192 Download in progress (downloading)	
	RHDownloadStatusWaitingForPostProcessing	= 0x4000,	// 16384 Download has completed and is waiting to be decompressed (processing, can't be interrupted)
	RHDownloadStatusDecompressingFile			= 0x8000,	// 32768 Download has completed and is being decompressed (processing, can't be interrupted)
	RHDownloadCombinedStatusProcessing			= 0xF000
};
typedef NSUInteger RHDownloadStatus;

@protocol RHDownloadViewDelegate, RHDownloadDelegate;

@interface RHDownload : NSObject <WTClientDelegate, RHFTPDownloadClientDelegate, RHFTPDirectoryListingDelegate, RHDownloadTableViewCellDelegate, NSCoding, NSCopying> {
@public
	NSString *uuid;
	RHDownloadItem *downloadItem;
	id<RHDownloadViewDelegate> viewDelegate;
	id<RHDownloadDelegate> delegate;
	RHDownloadStatus downloadStatus;
	NSUInteger lastStatusCode; // Status codes: http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
	
	unsigned long long contentLength;	// bytes
	NSTimeInterval timeLeft;			// seconds
	float avgTransferRate;				// bytes/sec
	NSTimeInterval lastTimeLeft;
	
@protected
	WTClient *wtClient;
	RHFTPDownloadClient *ftpClient;
	id transferClient;
	
	BOOL shouldResume;
	BOOL allowSimultaneousTransfer;
	NSDate *oldDate;
	
	// used for calculating avg. rate
	unsigned long long lastTotalBytesReceived;	
	NSTimeInterval lastTimeInterval;
	NSMutableArray *dlRates;
	double totalAccumulatedRates;
	
	NSError *error; // last error
	
@private
	// iOS4
	BOOL backgroundSupported;
	BOOL applicationIsInBackground;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 40000
	UIBackgroundTaskIdentifier bgTask;
#endif
}

@property(retain,readonly) NSString *uuid;
@property(retain) RHDownloadItem *downloadItem;
@property(nonatomic,assign) id<RHDownloadViewDelegate> viewDelegate;
@property(assign) id<RHDownloadDelegate> delegate;
@property RHDownloadStatus downloadStatus;
@property(readonly) unsigned long long contentLength;
@property(readonly) NSTimeInterval timeLeft;
@property(readonly) float avgTransferRate;
@property(readonly) unsigned long long lastTotalBytesReceived;
@property(readonly) NSUInteger lastStatusCode;
@property BOOL allowSimultaneousTransfer;
@property(retain) NSError *error;

// convenience class method for initialization
+ (RHDownload *)downloadWithDownloadItem:(RHDownloadItem *)downloadItem;

// designated initializer
- (id)initWithDownloadItem:(RHDownloadItem *)downloadItem;

- (NSString *)description;
- (void)downloadFile;
- (void)downloadFileIfNewerThan:(NSDate *)date;
- (void)downloadFileWithResume;
- (void)stopTransfer;

//- (void)setDecompressionObject:(id)object selector:(SEL)selector;
@end


@protocol RHDownloadViewDelegate <NSObject>

@required
- (void)downloadClientDidFailToEstablishConnection:(RHDownload *)client;
- (void)downloadClientDidLoseConnectionWithError:(RHDownload *)client; // error is stored in client.error
- (void)downloadClientDidFailToPassAuthenticationChallenge:(RHDownload *)client;
- (void)downloadClientDidAbortTransfer:(RHDownload *)client;
- (void)downloadClientDidFinishTransfer:(RHDownload *)client;

@optional
- (void)downloadClientRequestQueued:(RHDownload *)client;
- (void)downloadClientDidBeginConnecting:(RHDownload *)client;
- (void)downloadClientDidEstablishConnection:(RHDownload *)client;
- (void)downloadClientDidBeginTransfer:(RHDownload *)client;
- (void)downloadClientDidCloseConnection:(RHDownload *)client;
- (void)downloadClient:(RHDownload *)client didReceiveBytes:(unsigned long long)bytesWritten;
- (void)downloadClientInitiatedResumeRequest:(RHDownload *)download;
//- (void)setTotalSizeAndSizeUnitsForBytes:(unsigned long long)totalSizeInBytes;
@end


@protocol RHDownloadDelegate <NSObject>

@optional
- (void)downloadClientDidBeginTransfer:(RHDownload *)client;
- (void)downloadClientDidAbortTransfer:(RHDownload *)client;
- (void)downloadClientDidSkipTransfer:(RHDownload *)client;

/**
 Auto redirects if not implemented.
 */
- (void)downloadClient:(RHDownload *)client didReceiveRedirectURL:(NSURL *)url;

@required
- (void)downloadClientDidFinishTransfer:(RHDownload *)client;

@end
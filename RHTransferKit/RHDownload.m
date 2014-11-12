//
//  RHDownload.m
//  RHUtil
//
//  Created by Ryan Homer on 2010-02-17.
//  Copyright 2010 Murage Inc.. All rights reserved.
//

#include <unistd.h>
#import <uuid/uuid.h>
#import "RHDownload.h"

#define MAX_DL_RATES_TO_COMPUTE_AVERAGE 10

@interface RHDownload()
@property(retain) NSDate *oldDate;
@property(retain) WTClient *wtClient;
@property(retain) RHFTPDownloadClient *ftpClient;
@property(retain) RHFTPDirectoryListing *ftpDL;
- (void)pauseTransferForApplicationShutdown;
- (void)transferClientDidSkipTransfer:(id)client;
@end

@implementation RHDownload

@synthesize delegate, viewDelegate;
@synthesize uuid, downloadItem, downloadStatus, oldDate;
@synthesize contentLength, timeLeft, avgTransferRate, lastTotalBytesReceived, lastStatusCode;
@synthesize wtClient, ftpClient;
@synthesize ftpDL = ftpDL_;
@synthesize allowSimultaneousTransfer;
@synthesize error;

+ (RHDownload *)downloadWithDownloadItem:(RHDownloadItem *)theDownloadItem {
	return [[[RHDownload alloc] initWithDownloadItem:theDownloadItem] autorelease];
}

- (id)initWithDownloadItem:(RHDownloadItem *)theDownloadItem {
	if ( (self = [super init]) ) {
		self.downloadItem = [[theDownloadItem copy] autorelease];
		
		uuid_t aUUID;
		uuid_generate(aUUID);
		uuid = [[NSString alloc] initWithFormat:@"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
				aUUID[0],
				aUUID[1],
				aUUID[2],
				aUUID[3],
				aUUID[4],
				aUUID[5],
				aUUID[6],
				aUUID[7],
				aUUID[8],
				aUUID[9],
				aUUID[10],
				aUUID[11],
				aUUID[12],
				aUUID[13],
				aUUID[14],
				aUUID[15]];
		
		dlRates = [[NSMutableArray alloc] initWithCapacity:MAX_DL_RATES_TO_COMPUTE_AVERAGE];
		downloadStatus = RHDownloadStatusNew;
		
		UIDevice* device = [UIDevice currentDevice];
		if ([device respondsToSelector:@selector(isMultitaskingSupported)])
			backgroundSupported = device.multitaskingSupported;
		
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 40000
		// iOS4 - Background task handling
		if (backgroundSupported) {
			bgTask = UIBackgroundTaskInvalid;
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name: UIApplicationDidEnterBackgroundNotification object:nil];
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground:) name: UIApplicationWillEnterForegroundNotification object:nil];
		}
#endif
	}
	return self;
}

- (void)dealloc {
	NSLog(@"RHDownload dealloc: %@", self);
	self.delegate = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	if (self.downloadStatus & (RHDownloadStatusDownloading | RHDownloadStatusWaitingForDownload)) {
		[self pauseTransferForApplicationShutdown];
	}
	
	[wtClient release];
	[ftpClient release];
	transferClient = nil;
	
	[uuid release];
	[dlRates release];
	[downloadItem release];
	[error release];
	
	[ftpDL_ release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark Private

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 40000
- (void)endBackgroundTask {
	if (backgroundSupported && bgTask != UIBackgroundTaskInvalid) {
		NSLog(@"Ending background download task #%lu...", (unsigned long)bgTask);

		// Synchronize the cleanup call on the main thread in case
		// the expiration handler is fired at the same time.
		dispatch_async(dispatch_get_main_queue(), ^{
			if (bgTask != UIBackgroundTaskInvalid)
			{
				[[UIApplication sharedApplication] endBackgroundTask:bgTask];
				bgTask = UIBackgroundTaskInvalid;
			}
		});
	}	
}
#endif

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 40000
	#define END_BACKGROUND_TASK() [self endBackgroundTask]
#else
	#define END_BACKGROUND_TASK()
#endif


- (void)startTransfer {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	if ([[self.downloadItem.remoteURL scheme] hasPrefix:@"http"]) {
		self.wtClient = nil;
		wtClient = [[WTClient alloc] initWithLocalURL:self.downloadItem.localURL
											remoteURL:self.downloadItem.remoteURL
											 username:self.downloadItem.username
											 password:self.downloadItem.password];
		wtClient.delegate = self;
		transferClient = wtClient;
	}
	else if ([[self.downloadItem.remoteURL scheme] isEqualToString:@"ftp"]) {	
		self.ftpClient = nil;
		ftpClient = [[RHFTPDownloadClient alloc] initWithLocalURL:self.downloadItem.localURL
														remoteURL:self.downloadItem.remoteURL
														 username:self.downloadItem.username
														 password:self.downloadItem.password];
		self.ftpClient.delegate = self;
		transferClient = ftpClient;
	}
	else {
		assert(NO);
		return;
	}
	
	lastTimeInterval = 0;
	
	if (transferClient == wtClient) {
		[wtClient requestProperties];
	}
	else if (transferClient == ftpClient) {
		if (self.contentLength == 0) {
			// Get file size and last modification date using file's parent directory for URL
			self.ftpDL = [[RHFTPDirectoryListing alloc] initWithDownloadItem:self.downloadItem];
			self.ftpDL.delegate = self;
			[self.ftpDL startReceive];
		}
		else
			[transferClient downloadFileWithResume:shouldResume];
	}
	else {
		assert(NO);
	}
	
	[pool release];
}

#pragma mark -
#pragma mark Public super overridden methods

- (NSString *)description {
	return self.uuid;
}

#pragma mark -
#pragma mark Public methods

- (void)downloadFile {	
	// iOS4: Let OS know this task should continue in background if necessary
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 40000
	if (backgroundSupported) {
		bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
			// Synchronize the cleanup call on the main thread in case
			// the task actually finishes at around the same time.
			dispatch_async(dispatch_get_main_queue(), ^{
				if (bgTask != UIBackgroundTaskInvalid)
				{
					[self pauseTransferForApplicationShutdown];
					[[UIApplication sharedApplication] endBackgroundTask:bgTask];
					bgTask = UIBackgroundTaskInvalid;
				}
			});
		}];
		
		NSLog(@"Starting background download task #%lu...", (unsigned long)bgTask);
		
		// Start the long-running task and return immediately.
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			
			// Do the work associated with the task.
			[self startTransfer];
			
			// Wait for status to transition from RHDownloadStatusWaiting
			while (self.downloadStatus == RHDownloadStatusWaiting)
				usleep(6000000); // block thread for 6 seconds; no rush to check more frequently
			
			// Then wait until download is no longer downloading (completed or otherwise stopped)
			while (self.downloadStatus == RHDownloadStatusDownloading) {
				usleep(6000000);
				
				// If we only have 2 seconds or less left, pause download and set for auto resume
				if ([[UIApplication sharedApplication] backgroundTimeRemaining] <= 2.0) {
					[self pauseTransferForApplicationShutdown];
					break;
				}
			}
			
			// Wait until download status is "stopped".
			while (!(self.downloadStatus & RHDownloadCombinedStatusStopped)) {
				usleep(2000000);
			}
			
			//[self endBackgroundTask];			
		});
	}
	
	else
#endif
		[self performSelectorInBackground:@selector(startTransfer) withObject:nil];
	
}

- (void)downloadFileIfNewerThan:(NSDate *)theDate {
	self.oldDate = theDate;
	[self downloadFile];
}

- (void)downloadFileWithResume {
	shouldResume = YES;
	if (!applicationIsInBackground && [viewDelegate respondsToSelector:@selector(downloadClientInitiatedResumeRequest:)]) {
		[(NSObject *)viewDelegate performSelectorOnMainThread:@selector(downloadClientInitiatedResumeRequest:) withObject:self waitUntilDone:NO];
	}
	[self downloadFile];
}

/*!
 @method pauseTransferForApplicationShutdown
 @brief If download in progress, gracefully stop download and set appropriate status for auto-resume.
 */
- (void)pauseTransferForApplicationShutdown {
	if (self.downloadStatus == RHDownloadStatusDownloading) {
		self.downloadStatus = RHDownloadStatusPausedForAutoResume;
		[transferClient stopTransfer];
	}
}

- (void)stopTransfer {		
	if (transferClient) {
		// stop transfer
		[transferClient stopTransfer];
		transferClient = nil; // don't release; this is an assign pointer
		self.downloadStatus = RHDownloadStatusWaiting;
	}
	else {
		// This doesn't make sense since we have no transferClient
		[self transferClientDidAbortTransfer:(id)(wtClient ? wtClient : (ftpClient ? ftpClient : nil))];
	}	
}

//- (void)setDecompressionObject:(id)object selector:(SEL)selector {
//	decompressionObject = object;
//	decompressionSelector = selector;
//}

#pragma mark -
#pragma mark RHFTPDownloadClientDelegate

- (void)directoryListingAvailable:(RHFTPDirectoryListing *)directoryListing {
	//NSLog(@"FTP directory listing: %@", directoryListing.listEntries);
	NSDictionary *listingDict = [directoryListing.listEntries objectForKey:[[self.downloadItem.remoteURL absoluteString] lastPathComponent]];
	
	if (!listingDict) {
		// Invalid URL
		[self transferClientDidFailToEstablishConnection:transferClient];
		return;
	}
	
	NSNumber *contentLengthNumber = (NSNumber *)[listingDict objectForKey:(id)kCFFTPResourceSize];
	#ifdef DEBUG
	assert(contentLengthNumber);
	#endif
	
	if (contentLengthNumber) {
		contentLength = [contentLengthNumber unsignedLongLongValue];
		/*
		if ([viewDelegate respondsToSelector:@selector(setTotalSizeAndSizeUnitsForBytes:)]) {
			[viewDelegate setTotalSizeAndSizeUnitsForBytes:contentLength];
		}
		 */
	}
	
	if (self.oldDate) {
		NSDate *lastModifiedDate = [listingDict objectForKey:(id)kCFFTPResourceModDate];
		
		// if lastModifiedDate is earlier in time than oldDate
		if ([lastModifiedDate compare:self.oldDate] != NSOrderedDescending) {
			// don't download, just signal finished
			self.downloadStatus = RHDownloadStatusDownloadSkipped;
			[self transferClientDidSkipTransfer:transferClient];
			//[directoryListing release];
			return;
		}
	}
	
	//[directoryListing release];
	[transferClient downloadFileWithResume:shouldResume];
}

- (void)directoryListingDidFailToEstablishConnection:(RHFTPDirectoryListing *)directoryListing withError:(NSError *)theError {
	[self transferClientDidLoseConnection:transferClient withError:theError];
}

#pragma mark RHFTPDownloadClientDelegate / WTHTTPConnectionDelegate

- (void)transferClientDidBeginConnecting:(WTClient *)client {
	if (!applicationIsInBackground && [viewDelegate respondsToSelector:@selector(downloadClientDidBeginConnecting:)]) {
		[(NSObject *)viewDelegate performSelectorOnMainThread:@selector(downloadClientDidBeginConnecting:) withObject:self waitUntilDone:NO];
	}
}

- (void)transferClientDidEstablishConnection:(id)client {
	//NSLog(@"transferClientDidEstablishConnection:");
	
	if (!applicationIsInBackground && [viewDelegate respondsToSelector:@selector(downloadClientDidEstablishConnection:)]) {
		[(NSObject *)viewDelegate performSelectorOnMainThread:@selector(downloadClientDidEstablishConnection:) withObject:self waitUntilDone:NO];
	}
}

- (void)transferClientDidFailToEstablishConnection:(id)client {
	//NSLog(@"transferClientDidFailToEstablishConnection:");
	
	self.downloadStatus = RHDownloadStatusInvalidUrl;
	if (/*!applicationIsInBackground &&*/ [viewDelegate respondsToSelector:@selector(downloadClientDidFailToEstablishConnection:)]) {
		[(NSObject *)viewDelegate performSelectorOnMainThread:@selector(downloadClientDidFailToEstablishConnection:)
												   withObject:self
												waitUntilDone:NO];
	}
}

- (void)transferClientDidCloseConnection:(WTClient *)client {
	if ([viewDelegate respondsToSelector:@selector(downloadClientDidCloseConnection:)]) {
		[viewDelegate downloadClientDidCloseConnection:self];
		[(NSObject *)viewDelegate performSelectorOnMainThread:@selector(downloadClientDidCloseConnection:)
												   withObject:self
												waitUntilDone:NO];
	}
	//NSLog(@"transferClientDidCloseConnection:");
	//self.downloadStatus = RHDownloadStatusWaiting;
}

- (void)transferClientDidLoseConnection:(id)client withError:(NSError *)theError {
	//[[iCEDAppDelegate appDelegate] didStopNetworkingConnection];
	// In the event there was an open connection, this class instance would have already
	// received the transferClientDidCloseConnection: message before getting to this point.
	
	NSLog(@"Download URL: %@", [client remoteURL]);
	NSLog(@"Download client lost connection. Error: %@", [error localizedDescription]);
	self.error = theError;
	
	if (applicationIsInBackground) {
		self.downloadStatus = RHDownloadStatusQueued;
		self.error = nil;
	}
	else if ([[error domain] isEqualToString:(NSString *)kCFErrorDomainCFNetwork]) {
		switch ([error code]) {
			case kCFHostErrorHostNotFound:
			case kCFHostErrorUnknown:
				self.downloadStatus = RHDownloadStatusInvalidUrl;
				break;
			default:
				self.downloadStatus = RHDownloadStatusUnknownResponse;
				break;
		}
	}
	else {
		self.downloadStatus = RHDownloadStatusUnknownResponse;
	}
	
	if (/*!applicationIsInBackground &&*/ [viewDelegate respondsToSelector:@selector(downloadClientDidLoseConnectionWithError:)]) {
		[(NSObject *)viewDelegate performSelectorOnMainThread:@selector(downloadClientDidLoseConnectionWithError:) withObject:self waitUntilDone:NO];
	}
	if ([delegate respondsToSelector:@selector(downloadClientDidLoseConnectionWithError:)]) {
		[(NSObject *)delegate performSelectorOnMainThread:@selector(downloadClientDidLoseConnectionWithError:) withObject:self waitUntilDone:NO];
	}
	//[transferClient release], transferClient = nil;
}

- (void)transferClientDidFailToPassAuthenticationChallenge:(WTClient *)client {
	NSLog(@"transferClientDidFailToPassAuthenticationChallenge:");
	self.downloadStatus = RHDownloadStatusFailedAuthentication;
	if (/*!applicationIsInBackground &&*/ [viewDelegate respondsToSelector:@selector(downloadClientDidFailToPassAuthenticationChallenge:)]) {
		[(NSObject *)viewDelegate performSelectorOnMainThread:@selector(downloadClientDidFailToPassAuthenticationChallenge:) withObject:self waitUntilDone:NO];
	}	
}

/*!
 * @method dateFromString:
 * @brief Convert a string in RFC1123, RFC1036 or ANSI C format to an NSDate object.
 * @param dateString The string to be converted
 * @return an NSDate object
 * @updated 2010-04-10
 */
- (NSDate *)dateFromString:(NSString *)dateString {
	static NSArray *months = nil;
	
	if (!dateString || [dateString length] == 0) {
		return nil;
	}
	
	if (months == nil) {
		months = [[NSArray alloc] initWithObjects:@"", @"Jan", @"Feb", @"Mar", @"Apr", @"May", @"Jun", @"Jul", @"Aug", @"Sep", @"Oct", @"Nov", @"Dec", nil];
	}
	
	NSArray *stringComponents = [dateString componentsSeparatedByString:@" "];
	NSDateComponents *dateTimeComponents = [[NSDateComponents alloc] init];
	NSString *tzAbbr = nil;
	NSDate *dateTime = nil;
	
	// Date formats: http://tools.ietf.org/html/rfc2616#section-3.3.1
	switch ([stringComponents count]) {
		case 4: {
			// Sunday, 06-Nov-94 08:49:37 GMT (RFC 850, obsoleted by RFC 1036)
			NSArray *dateComponents = [[stringComponents objectAtIndex:1] componentsSeparatedByString:@"-"];
			[dateTimeComponents setDay:[[dateComponents objectAtIndex:0] intValue]];
			[dateTimeComponents setMonth:[months indexOfObject:[dateComponents objectAtIndex:1]]];
			NSInteger year = [[dateComponents objectAtIndex:2] intValue];
			year += (year > 40) ? 1900 : 2000;
			[dateTimeComponents setYear:year];
			
			NSArray *timeComponents = [[stringComponents objectAtIndex:2] componentsSeparatedByString:@":"];
			[dateTimeComponents setHour:[[timeComponents objectAtIndex:0] intValue]];
			[dateTimeComponents setMinute:[[timeComponents objectAtIndex:1] intValue]];
			[dateTimeComponents setSecond:[[timeComponents objectAtIndex:2] intValue]];
			
			tzAbbr = [stringComponents objectAtIndex:3];
			break;
		}
		case 5:
			// Sun Nov  6 08:49:37 1994 (ANSI C's asctime() format)
			break;
		case 6:
			// Sun, 06 Nov 1994 08:49:37 GMT (RFC 822, updated by RFC 1123)
			[dateTimeComponents setDay:[[stringComponents objectAtIndex:1] intValue]];
			[dateTimeComponents setMonth:[months indexOfObject:[stringComponents objectAtIndex:2]]];
			[dateTimeComponents setYear:[[stringComponents objectAtIndex:3] intValue]];
			
			NSArray *timeComponents = [[stringComponents objectAtIndex:4] componentsSeparatedByString:@":"];
			[dateTimeComponents setHour:[[timeComponents objectAtIndex:0] intValue]];
			[dateTimeComponents setMinute:[[timeComponents objectAtIndex:1] intValue]];
			[dateTimeComponents setSecond:[[timeComponents objectAtIndex:2] intValue]];
			
			tzAbbr = [stringComponents objectAtIndex:5];
	}
	
	if (tzAbbr) {
		NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
		[calendar setTimeZone:[NSTimeZone timeZoneWithAbbreviation:tzAbbr]];
		dateTime = [calendar dateFromComponents:dateTimeComponents];
		[calendar release];
	}
	[dateTimeComponents release];
	
	return dateTime;
}

- (void)transferClientDidReceivePropertiesResponse:(WTClient *)client {
	//NSLog(@"transferClientDidReceivePropertiesResponse:");
	//NSLog(@"Authentication passed");
	//NSLog(@"properites:%@", client.properties);
	
    NSUInteger statusCode = [[client.currentResponse valueForKey:@"statusCode"] intValue];
	lastStatusCode = statusCode;
    //NSLog(@"transferClientDidReceivePropertiesResponse: statusCode=%u", statusCode);
	
	// Status codes: http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
	// and: http://en.wikipedia.org/wiki/List_of_HTTP_status_codes
	if (statusCode >= 200 && statusCode <= 299)			// OK
	{
		if ([[[client properties] valueForKey:@"status"] isEqualToString:@"HTTP/1.1 200 OK"]) {
			contentLength = (unsigned long long)[(NSString *)[[client properties] valueForKey:@"getcontentlength"] longLongValue];
			/*
			if ([viewDelegate respondsToSelector:@selector(setTotalSizeAndSizeUnitsForBytes:)]) {
				[viewDelegate setTotalSizeAndSizeUnitsForBytes:contentLength];
			}			
			*/
			
			if (self.oldDate) {
				NSString *getlastmodified = [[client properties] valueForKey:@"getlastmodified"];
				NSDate *lastModifiedDate = [self dateFromString:getlastmodified];
				
				// if lastModifiedDate is earlier in time than oldDate
				if ([lastModifiedDate compare:self.oldDate] != NSOrderedDescending) {
					// don't download, just signal finished
					self.downloadStatus = RHDownloadStatusDownloadSkipped;
					[self transferClientDidSkipTransfer:client];
					return;
				}
			}
			
			[client downloadFileWithResume:shouldResume];
			return;
		}
		else {
			NSLog(@"Error. Status is: %@", [[client properties] valueForKey:@"status"]);
			//NSLog(@"Requested file cannot be accessed");
			self.downloadStatus = RHDownloadStatusInvalidUrl;
			[self transferClientDidAbortTransfer:client];
		}
    }
	else if (statusCode >= 300 && statusCode <= 399) {		// Redirect
		NSString *newUrlString = [client.currentResponse objectForKey:@"Location"];
		if ([delegate respondsToSelector:@selector(downloadClient:didReceiveRedirectURL:)]) {
			NSURL *url = [NSURL URLWithString:newUrlString];
			[delegate downloadClient:self didReceiveRedirectURL:url];
		}
		else {
			NSLog(@"Received HTTP redirect URL");
			NSLog(@"Old URL: %@", [wtClient.remoteURL absoluteString]);
			NSLog(@"New URL: %@", [client.currentResponse objectForKey:@"Location"]);
			
			// Remove trailing slash if there is one, then create NSURL
			newUrlString = [newUrlString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
			NSURL *newURL = [NSURL URLWithString:newUrlString];
			
			self.downloadItem.remoteURL = newURL;
			[self downloadFile];
		}
	}
    else if (statusCode == 404) {
		self.downloadStatus = RHDownloadStatusInvalidUrl;
		NSLog(@"Requested file \"%@\" not found on server", self.downloadItem.remoteURL);
    }
    else {
		NSLog(@"Error. Unexpected response from server. (Status code = %lu)", (unsigned long)statusCode);
		self.downloadStatus = RHDownloadStatusUnknownResponse;
		[self transferClientDidAbortTransfer:client];
    }
}

- (void)transferClientDidBeginTransfer:(id)client {
	self.downloadStatus = RHDownloadStatusDownloading;
	
	if (!applicationIsInBackground
		&& (id)delegate != (id)viewDelegate
		&& [viewDelegate respondsToSelector:@selector(downloadClientDidBeginTransfer:)])
	{
		[(NSObject *)viewDelegate performSelectorOnMainThread:@selector(downloadClientDidBeginTransfer:) withObject:self waitUntilDone:NO];
	}
	
	if ([delegate respondsToSelector:@selector(downloadClientDidBeginTransfer:)]) {
		[delegate downloadClientDidBeginTransfer:self];
	}
}

- (void)transferClientDidFinishTransfer:(id)client {
	self.downloadStatus = RHDownloadStatusTransferCompleted;
	
	if (/*!applicationIsInBackground &&*/
		(id)delegate != (id)viewDelegate
		&& [viewDelegate respondsToSelector:@selector(downloadClientDidFinishTransfer:)])
	{
		[(NSObject *)viewDelegate performSelectorOnMainThread:@selector(downloadClientDidFinishTransfer:) withObject:self waitUntilDone:YES];
	}
	
	if (delegate && [delegate respondsToSelector:@selector(downloadClientDidFinishTransfer:)]) {
		[delegate downloadClientDidFinishTransfer:self];
	}
	
	//[transferClient release], transferClient = nil;
	
	END_BACKGROUND_TASK();
}

- (void)transferClientDidSkipTransfer:(id)client {
	self.downloadStatus = RHDownloadStatusDownloadSkipped;
	END_BACKGROUND_TASK();
	
	if (/*!applicationIsInBackground &&*/ [viewDelegate respondsToSelector:@selector(downloadClientDidSkipTransfer:)]) {
		[(NSObject *)viewDelegate performSelectorOnMainThread:@selector(downloadClientDidSkipTransfer:) withObject:self waitUntilDone:NO];
	}
	
	if (delegate && [delegate respondsToSelector:@selector(downloadClientDidSkipTransfer:)]) {
		[delegate downloadClientDidSkipTransfer:self];
	}	
}

- (void)transferClientDidAbortTransfer:(id)client {
	//self.transferClient = nil;
	END_BACKGROUND_TASK();
	
	// If abort is due to application shutdown, downlStatus will already be set to RHDownloadStatusPausedForAutoResume
	if (self.downloadStatus != RHDownloadStatusPausedForAutoResume) {
		self.downloadStatus = RHDownloadStatusWaiting;
	}
	
	if (/*!applicationIsInBackground &&*/
		(id)delegate != (id)viewDelegate
		&& [viewDelegate respondsToSelector:@selector(downloadClientDidAbortTransfer:)]) {
		[(NSObject *)viewDelegate performSelectorOnMainThread:@selector(downloadClientDidAbortTransfer:) withObject:self waitUntilDone:NO];
	}
	
	if ([delegate respondsToSelector:@selector(downloadClientDidAbortTransfer:)]) {
		[delegate downloadClientDidAbortTransfer:self];
	}
	
	//[transferClient release], transferClient = nil;
}

//- (void)transferClient:(WTClient *)client didSendBytes:(unsigned long long)bytesWritten {
//}

- (void)transferClient:(id)client didReceiveBytes:(unsigned long long)totalBytesReceived {
	if (lastTimeInterval == 0) {
		lastTimeInterval = [NSDate timeIntervalSinceReferenceDate];
		lastTotalBytesReceived = totalBytesReceived;
		lastTimeLeft = 0;		
	}
	else {
		// calcualte rate
		NSTimeInterval ti = [NSDate timeIntervalSinceReferenceDate];
		NSTimeInterval tiDelta = ti - lastTimeInterval;
		
		// Don't sample too often; using 4 sec. intervals.
		if (tiDelta < 3)
			goto bail;
		
		lastTimeInterval = ti;
		float rateThisTime = (double) (totalBytesReceived - lastTotalBytesReceived) / tiDelta;
		lastTotalBytesReceived = totalBytesReceived;
		
		// save rates and get average
		[dlRates addObject:[NSNumber numberWithFloat:rateThisTime]];
		totalAccumulatedRates += rateThisTime;
		// prune
		if (dlRates.count > MAX_DL_RATES_TO_COMPUTE_AVERAGE) {
			NSNumber *rateToRemove = [dlRates objectAtIndex:0];
			totalAccumulatedRates -= [rateToRemove floatValue];
			[dlRates removeObject:rateToRemove];
		}
		avgTransferRate = totalAccumulatedRates / dlRates.count;
		
		// now calculate time left
		unsigned long long bytesLeft = MAX(0, (contentLength - totalBytesReceived));
		timeLeft = (avgTransferRate == 0) ? 0 : (bytesLeft / avgTransferRate);
	}
	
bail:
	if (!applicationIsInBackground && [viewDelegate respondsToSelector:@selector(downloadClient:didReceiveBytes:)]) {
		[viewDelegate downloadClient:self didReceiveBytes:totalBytesReceived];
	}
}

#pragma mark -
#pragma mark NSCoding protocol methods

- (void)encodeWithCoder:(NSCoder *)encoder {
	[encoder encodeObject:self.uuid forKey:@"uuid"];
	self.downloadItem.shouldArchivePassword = YES;
	[encoder encodeObject:self.downloadItem forKey:@"downloadItem"];
	[encoder encodeObject:[NSNumber numberWithUnsignedInteger:self.downloadStatus] forKey:@"downloadStatus"];
	
	// Save this info to restore progress indication
	[encoder encodeObject:[NSNumber numberWithUnsignedLongLong:lastTotalBytesReceived] forKey:@"lastTotalBytesReceived"];
	[encoder encodeObject:[NSNumber numberWithUnsignedLongLong:contentLength] forKey:@"contentLength"];
}

- (id)initWithCoder:(NSCoder *)decoder {
	self.downloadItem = [decoder decodeObjectForKey:@"downloadItem"];
	if ( (self = [self initWithDownloadItem:self.downloadItem]) ) {
		uuid = [[decoder decodeObjectForKey:@"uuid"] retain];
		self.downloadStatus = [(NSNumber *)[decoder decodeObjectForKey:@"downloadStatus"] unsignedIntegerValue];
		lastTotalBytesReceived = [(NSNumber *)[decoder decodeObjectForKey:@"lastTotalBytesReceived"] unsignedLongLongValue];
		contentLength = [(NSNumber *)[decoder decodeObjectForKey:@"contentLength"] unsignedLongLongValue];
	}
	return self;
}

#pragma mark -
#pragma mark NSCopying protocol methods

- (id)copyWithZone:(NSZone *)zone {
	RHDownload *copy = [[[self class] allocWithZone:zone] initWithDownloadItem:self.downloadItem];
	//copy.uuid = self.uuid;
	//copy.downloadItem = self.downloadItem;
	return copy;
}

#pragma mark -
#pragma mark Notifications

- (void)applicationDidEnterBackground:(NSNotification *)notification {
	applicationIsInBackground = YES;
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
	applicationIsInBackground = NO;
}

@end

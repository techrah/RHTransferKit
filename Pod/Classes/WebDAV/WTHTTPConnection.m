//
//  WTHTTPConnection.m
//
//  $Revision: 4 $
//  $LastChangedDate: 2009-02-07 12:28:17 -0500 (Sat, 07 Feb 2009) $
//  $LastChangedBy: alex.chugunov $
//
//  This part of source code is distributed under MIT Licence
//  Copyright (c) 2009 Alex Chugunov
//  http://code.google.com/p/wtclient/
//
//  Parts of this code may have been changed since the original version on Google Code.
//  None of these changes have been added to that respsitory.

#import "WTHTTPConnection.h"
#define BUFSIZE 32768
#define POLL_INTERVAL 1.0

void connectionMaster (CFReadStreamRef stream, CFStreamEventType event, void *myPtr) {
    if (event == kCFStreamEventHasBytesAvailable) {
		UInt8 buffer[BUFSIZE];
		CFIndex bytesRead = CFReadStreamRead(stream, buffer, BUFSIZE);
		if (bytesRead > 0) {
			[(WTHTTPConnection *)myPtr handleBytes:buffer length:bytesRead];
		}
    }
    else if (event == kCFStreamEventErrorOccurred) {
		CFErrorRef cfError = CFReadStreamCopyError(stream);
		NSError *nsError = [[(NSError *)cfError retain] autorelease];
		CFRelease(cfError);
		[(WTHTTPConnection *)myPtr handleError:nsError];
    }
    else if (event == kCFStreamEventEndEncountered) {
		[(WTHTTPConnection *)myPtr handleEnd];
    }
}

@interface WTHTTPConnection()
@property (nonatomic, retain) NSOutputStream *responseStream;
@property (nonatomic, retain) NSMutableData *responseData;
@end


@implementation WTHTTPConnection

@synthesize connectionError, request, requestStream, localURL, connectionTimeout;
@synthesize delegate, connectionTimer, lastActivity;
@synthesize responseStream, responseData;

- (id)initWithDestination:(NSURL *)destination protocol:(NSString *)protocol {
    if ( (self = [self init]) != nil) {
		bytesBeforeResume = 0;
		connectionTimeout = 60;
		destinationURL = [destination retain];
		authenticationRequired = NO;
		request = CFHTTPMessageCreateRequest(kCFAllocatorDefault,
											 (CFStringRef)protocol,
											 (CFURLRef)destinationURL,
											 kCFHTTPVersion1_1);
		if (request == NULL) {
			[self release];
			self = nil;
		}
    }
    return self;
}

- (void)setRequestBodyWithData:(NSData *)data {
    CFHTTPMessageSetBody(request, (CFDataRef)data);
}


- (BOOL)setRequestBodyWithTargetURL:(NSURL *)targetURL offset:(unsigned long long)offset  {
    //
    // We don't want to load files into memory (probably large, especially in iPhone).
    // And we would like to get some sort of uploading progress.
    // That's why we open here new stream instead of using setRequestBodyWithData
    //
    
    bytesBeforeResume = 0;
    unsigned long long contentLength = 0;
    NSNumber *fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:[targetURL path] error:nil] valueForKey:NSFileSize];
    contentLength = [fileSize unsignedLongLongValue];
    if (!contentLength) {
		self.connectionError = [NSError errorWithDomain:@"HTTPConnection" code:4242 userInfo:nil];
		return NO;
    }
    
    bodyStream = CFReadStreamCreateWithFile(kCFAllocatorDefault, (CFURLRef)targetURL);
    if (bodyStream == NULL) {
		self.connectionError = [NSError errorWithDomain:@"HTTPConnection" code:4202 userInfo:nil];
		return NO;
    }    
    
    // We are using Content-Range header in case we want to resume uploading.
    if (offset && offset != contentLength  ) {
		CFReadStreamSetProperty(bodyStream, kCFStreamPropertyFileCurrentOffset, (CFNumberRef)[NSNumber numberWithUnsignedLongLong:offset]);
		NSString *contentRangeValue = [NSString stringWithFormat:@"bytes %qi-%qi/%qi", offset, contentLength - 1, contentLength];
		CFHTTPMessageSetHeaderFieldValue(self.request, CFSTR("Content-Range"), (CFStringRef)contentRangeValue);
		contentLength = contentLength - offset;
		bytesBeforeResume = offset;
    }
    
    NSString *contentLengthValue = [NSString stringWithFormat:@"%qi", contentLength];    
    CFHTTPMessageSetHeaderFieldValue(self.request, CFSTR("Content-Length"), (CFStringRef)contentLengthValue);
    
    return YES;
}

- (BOOL)setResumeRequestBodyForLocalURL {
	NSAssert(self.localURL, @"localURL must not be nil");
	
    unsigned long long contentLength = 0;
	NSError *error = nil;
	
    NSNumber *fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:[self.localURL path] error:&error] valueForKey:NSFileSize];
	if (error)
		return NO;
	
    contentLength = [fileSize unsignedLongLongValue];
    if (!contentLength) {
		self.connectionError = [NSError errorWithDomain:@"HTTPConnection" code:4242 userInfo:nil];
		return NO;
    }
	
	self.responseStream = [[[NSOutputStream alloc] initToFileAtPath:[self.localURL path] append:YES] autorelease];
	[self.responseStream open];
	bytesBeforeResume = contentLength;
	
	// We are using Range header to resume downloading.
	// http://books.google.com/books?id=oxg8_i9dVakC&lpg=PA172&ots=b6bTo4RN-1&dq=content-range%20example&pg=PA172#v=onepage&q=content-range%20example&f=false
	NSString *rangeValue = [NSString stringWithFormat:@"bytes=%qu-", contentLength];
    CFHTTPMessageSetHeaderFieldValue(self.request, CFSTR("Range"), (CFStringRef)rangeValue);
	
	return YES;
}

- (BOOL)setAuthentication:(CFHTTPAuthenticationRef)authentication credentials:(NSDictionary *)credentials {
    if (!CFHTTPMessageApplyCredentialDictionary(request,
												authentication,
												(CFDictionaryRef)credentials,
												NULL))
    {
		self.connectionError = [NSError errorWithDomain:@"HTTPConnection" code:4203 userInfo:nil];
		return NO;
    }
    authenticationRequired = YES;
    return YES;
}

- (BOOL)openStream {
	NSAssert(requestStream == nil, @"requestStream not nil. Perhaps last used stream was not closed.");
	
	bytesForDownload = 0;
	bytesReceived = 0;
	if ([self.delegate respondsToSelector:@selector(HTTPConnectionDidBeginEstablishingConnection:)]) {
		[self.delegate HTTPConnectionDidBeginEstablishingConnection:self];
	}
	self.responseData = [NSMutableData dataWithLength:0];
	if (bodyStream) {
		requestStream = CFReadStreamCreateForStreamedHTTPRequest(kCFAllocatorDefault,
																 request,
																 bodyStream);
	}
	else {
		if (!self.responseStream) {
			// If we are resuming a download, response stream should not be nil
			// and we'll need the bytesBeforeResume, so don't reset.
			bytesBeforeResume = 0;
		}
		requestStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, request);
	}
	
	if (!requestStream) {
		self.connectionError = [NSError errorWithDomain:@"HTTPConnection" code:4204 userInfo:nil];
		if ([self.delegate respondsToSelector:@selector(HTTPConnectionDidFailToEstablish:)]) {
			[self.delegate HTTPConnectionDidFailToEstablish:self];
		}
		
		return NO;
	}
	
	CFReadStreamSetProperty(requestStream, kCFStreamPropertyHTTPAttemptPersistentConnection, kCFBooleanTrue);
	
	
	// Set client and schedule with run loop BEFORE opening stream
	
	CFStreamClientContext myContext = {0, self, NULL, NULL, NULL};
	
	CFOptionFlags registeredEvents = kCFStreamEventHasBytesAvailable
	| kCFStreamEventOpenCompleted
	| kCFStreamEventCanAcceptBytes
	| kCFStreamEventErrorOccurred
	| kCFStreamEventNone
	| kCFStreamEventEndEncountered;
	
	if (CFReadStreamSetClient(requestStream, registeredEvents, connectionMaster, &myContext)) {
		CFReadStreamScheduleWithRunLoop(requestStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
		
		// Open stream and finish setup
		if (CFReadStreamOpen(requestStream)) {
			self.lastActivity = [NSDate date];
			if ([self.delegate respondsToSelector:@selector(HTTPConnectionDidEstablish:)]) {
				[self.delegate HTTPConnectionDidEstablish:self];
			}
			//The timer is used only to poll connection about the transfer progress. Event handling is scheduled in run loop.
			self.connectionTimer = [NSTimer scheduledTimerWithTimeInterval:POLL_INTERVAL
																	target:self
																  selector:@selector(pollConnection:)
																  userInfo:nil
																   repeats:YES];
			isOpen = YES;		
			CFRunLoopRun();
			return YES;
		}
		else {
			CFReadStreamUnscheduleFromRunLoop(requestStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
			CFReadStreamSetClient(requestStream, kCFStreamEventNone, connectionMaster, NULL);
			CFRelease(requestStream);
			requestStream = nil;
			
			self.connectionError = [NSError errorWithDomain:@"HTTPConnection" code:4205 userInfo:nil];
			if ([self.delegate respondsToSelector:@selector(HTTPConnectionDidFailToEstablish:)]) {
				[self.delegate HTTPConnectionDidFailToEstablish:self];
			}
			
			return NO;
		}
	}
	
	return NO;
}

- (void)closeStream {
	if (isOpen) {
		[self pollConnection:nil];
		isOpen = NO;
		
		if (requestStream) {
			CFReadStreamClose(requestStream);
			CFReadStreamUnscheduleFromRunLoop(requestStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
			CFReadStreamSetClient(requestStream, kCFStreamEventNone, connectionMaster, NULL);
			CFRelease(requestStream);
			requestStream = nil;
			CFRunLoopStop(CFRunLoopGetCurrent());
		}
		
		if (connectionTimer) {
			if ([connectionTimer isValid])
				[connectionTimer invalidate];
			[connectionTimer release];
			connectionTimer = nil;
		}
		
		if (responseStream) {
			[responseStream close];
			[responseStream release];
			responseStream = nil;
		}		
	}
}

- (void)handleError:(NSError *)error {
    [self closeStream];
	if ([self.delegate respondsToSelector:@selector(interruptedHTTPConnection:withError:)]) {
		[self.delegate interruptedHTTPConnection:self withError:error];
    }	
}

- (void)pollConnection:(NSTimer *)aTimer {
    if (isOpen) {
		long long bytesWritten = 0;
		CFNumberRef cfSize = CFReadStreamCopyProperty(requestStream, kCFStreamPropertyHTTPRequestBytesWrittenCount);
		CFNumberGetValue(cfSize, kCFNumberLongLongType, &bytesWritten);
		CFRelease(cfSize);
		cfSize = NULL;
		if (bytesWritten > 0) {
			self.lastActivity = [NSDate date];
			if ([self.delegate respondsToSelector:@selector(HTTPConnection:didSendBytes:)]) {
				[self.delegate HTTPConnection:self didSendBytes:((unsigned)bytesWritten + bytesBeforeResume)];
			}
		}
		if ([self.delegate respondsToSelector:@selector(HTTPConnection:didReceiveBytes:)]) {
			[self.delegate HTTPConnection:self didReceiveBytes:bytesReceived + bytesBeforeResume];
		}
    }
    //TODO: implement timeout checking here (use lastActivity and connectionTimeout)
}

- (void)handleBytes:(UInt8 *)buffer length:(CFIndex)bytesRead {
	if (bytesReceived == 0) {
		CFHTTPMessageRef responseHeader = (CFHTTPMessageRef)CFReadStreamCopyProperty(requestStream, kCFStreamPropertyHTTPResponseHeader);
		NSInteger statusCode = CFHTTPMessageGetResponseStatusCode(responseHeader);
		//NSLog(@"%@ handleBytes:length: rec'd status code: %lu", self, statusCode);
		if (statusCode == 200 || statusCode == 416) {
			// Either there was no resume request, WebDAV server does not support it, or range was not valid.
			[responseStream close];
			self.responseStream = nil;
			bytesBeforeResume = 0;			
		}
		CFRelease(responseHeader);
	}
    
	self.lastActivity = [NSDate date];
    bytesReceived += bytesRead;
    if (self.localURL) {
		// This is a case when we don't want to store downloaded data into memory
		// We are using stream and writing received bytes into the file if it's determined
		if (!self.responseStream) {
			self.responseStream = [[[NSOutputStream alloc] initToFileAtPath:[self.localURL path] append:NO] autorelease];
			[self.responseStream open];
		}
		[self.responseStream write:buffer maxLength:bytesRead];
    }
    else {
		[self.responseData appendBytes:buffer length:bytesRead];
    }
}

- (void)handleEnd {
    CFHTTPMessageRef responseHeader = (CFHTTPMessageRef)CFReadStreamCopyProperty(requestStream, kCFStreamPropertyHTTPResponseHeader);
    [self closeStream];
    
    CFStringRef statusString = CFHTTPMessageCopyResponseStatusLine(responseHeader);
    NSInteger statusCode = CFHTTPMessageGetResponseStatusCode(responseHeader);
	//NSLog(@"%@ rec'd status code: %lu", self, statusCode);
    
    if (statusCode == 401 /* unauthorized */ || statusCode == 407 /* proxy authentication required */ ) {
		CFHTTPAuthenticationRef authentication = CFHTTPAuthenticationCreateFromResponse(kCFAllocatorDefault, responseHeader);
		if (authenticationRequired) {
			if ([self.delegate respondsToSelector:@selector(HTTPConnection:didFailToPassAuthenticationChallenge:)]) {
				[self.delegate HTTPConnection:self didFailToPassAuthenticationChallenge:authentication];
			}
		}
		else {
			if ([self.delegate respondsToSelector:@selector(HTTPConnection:didReceiveAuthenticationChallenge:)]) {
				[self.delegate HTTPConnection:self didReceiveAuthenticationChallenge:authentication];
			}
		}
		CFRelease(authentication);
		authentication = NULL;
    }
    else {
		NSMutableDictionary *responseDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
											 [NSNumber numberWithInteger:statusCode], @"statusCode",
											 statusString, @"statusString",
											 self.responseData, @"responseBody",
											 nil];
				
		CFDictionaryRef allHeaderFields = CFHTTPMessageCopyAllHeaderFields(responseHeader);
		[responseDict addEntriesFromDictionary:(NSDictionary *)allHeaderFields];
		CFRelease(allHeaderFields);
		
		if ([self.delegate respondsToSelector:@selector(HTTPConnection:didReceiveResponse:)]) {
			[self.delegate HTTPConnection:self didReceiveResponse:responseDict];
		}
    }
    
    CFRelease(statusString);
    statusString = NULL;
    CFRelease(responseHeader);
    responseHeader = NULL;
}

- (void)dealloc {
	delegate = nil;
	
    if (isOpen)
		[self closeStream];
    
	if (connectionTimer) {
		if ([connectionTimer isValid])
			[connectionTimer invalidate];
		[connectionTimer release];
		connectionTimer = nil;
	}
	
	if (responseStream) {
		[responseStream release];
		responseStream = nil;
	}
	
    [connectionError release];
	
	if (responseData) {
		[responseData release];
		responseData = nil;
	}
    
	[destinationURL release];
    [localURL release];
    [lastActivity release];
    
    
    if (request) {
		CFRelease(request);
		request = NULL;
    }
    
    if (bodyStream) {
		CFRelease(bodyStream);
		bodyStream = NULL;
    }
    
    if (requestStream) {
		CFRelease(requestStream);
		requestStream = NULL;
    }    
    [super dealloc];
}


@end

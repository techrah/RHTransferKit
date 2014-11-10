//
//  RHFTPDownloadClient.m
//  iCED
//
//  Created by Ryan on 2010-08-16.
//  Copyright 2010 Murage Inc. All rights reserved.
//

#import "RHFTPDownloadClient.h"

@interface RHFTPDownloadClient()
@property(nonatomic,retain) NSInputStream *networkStream;
@property(nonatomic,retain) NSOutputStream *fileStream;
- (void)closeConnections;
@end

@implementation RHFTPDownloadClient

@synthesize remoteURL, localURL;
@synthesize username, password;
@synthesize networkStream, fileStream, delegate;

#pragma mark -
#pragma mark Life Cycle

- (id)initWithLocalURL:(NSURL *)aLocalURL remoteURL:(NSURL *)aRemoteURL username:(NSString *)username password:(NSString *)password {
	if ((self = [self init])) {
		self.localURL = aLocalURL;
		self.remoteURL = aRemoteURL;
	}
	return self;
}

- (void)dealloc {
	NSLog(@"dealloc: %@", self);
	//self.delegate = nil;
	[self closeConnections];
	[remoteURL release];
	[localURL release];
	[username release];
	[password release];
	
	// Released in closeConnections
	//self.networkStream = nil;
	//self.fileStream = nil;
	
	[super dealloc];
}

#pragma mark -
#pragma mark Private

- (void)closeConnections {
	if (self.networkStream != nil) {        
		self.networkStream.delegate = nil;
		[self.networkStream close];
		
		[self.networkStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
		
		if (streamOpen) {
			if ([self.delegate respondsToSelector:@selector(transferClientDidCloseConnection:)])
				[self.delegate transferClientDidCloseConnection:self];
			
			streamOpen = NO;
		}
		
        self.networkStream = nil;
		
		/*
		 Moved CFRunLoopStop to after all other runloop operations in an attempt to stop intermittent crashing of the runloop.
		 It's possible that the runloop needs to be running during the unscheduling of the runloop, for example, though it is not certain that this is the case.
		 
		 Also, using getCFRunLoop instead of CFRunLoopGetCurrent(). Don't know if it makes a difference.
		 
		 Apple Reference: Although they are not toll-free bridged types, you can get a CFRunLoopRef opaque type from an NSRunLoop object when needed.
		 The NSRunLoop class defines a getCFRunLoop method that returns a CFRunLoopRef type that you can pass to Core Foundation routines.
		 Because both objects refer to the same run loop, you can intermix calls to the NSRunLoop object and CFRunLoopRef opaque type as needed.
		 */
		CFRunLoopStop([[NSRunLoop currentRunLoop] getCFRunLoop]);
	}
    if (self.fileStream != nil) {
        [self.fileStream close];
        self.fileStream = nil;
    }
}

#pragma mark -
#pragma mark Public Methods

- (void)stopTransfer {
	[self closeConnections];
	
	if ([delegate respondsToSelector:@selector(transferClientDidAbortTransfer:)]) {
		[delegate transferClientDidAbortTransfer:self];
	}
	
	// We do not need to contact the delegate anymore so setting to nil in case there is a connection
	// response before it completely shuts down to ensure no more UI changes or other side effects from here on.
	self.delegate = nil;
}

- (void)downloadFile {
    assert(self.networkStream == nil);
    assert(self.fileStream == nil);	
	assert(self.localURL != nil);
	assert([NSRunLoop currentRunLoop] != [NSRunLoop mainRunLoop]);
	
	self.fileStream = [NSOutputStream outputStreamWithURL:self.localURL append:(totalBytesTransferred > 0)];
	
	assert(self.fileStream != nil);	
	[self.fileStream open];
	
	// Open an FTP stream for the URL.
	CFReadStreamRef ftpStream = CFReadStreamCreateWithFTPURL(NULL, (CFURLRef)self.remoteURL);
	if (!ftpStream) {
		if ([delegate respondsToSelector:@selector(transferClientDidFailToEstablishConnection:)])
			[delegate transferClientDidFailToEstablishConnection:self];
		return;
	}
	
	self.networkStream = (NSInputStream *)ftpStream;
	self.networkStream.delegate = self;
	CFRelease(ftpStream);
	
	[self.networkStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	
	CFReadStreamSetProperty(ftpStream, kCFStreamPropertyFTPFetchResourceInfo, kCFBooleanFalse);
	CFReadStreamSetProperty(ftpStream, kCFStreamPropertyFTPAttemptPersistentConnection, kCFBooleanFalse);
	CFReadStreamSetProperty(ftpStream, kCFStreamPropertyFTPUsePassiveMode, kCFBooleanTrue);
	CFReadStreamSetProperty(ftpStream, kCFStreamPropertyFTPFileTransferOffset, (CFNumberRef)[NSNumber numberWithUnsignedLongLong:totalBytesTransferred]);
	
	[self.networkStream open];
	
	if ([delegate respondsToSelector:@selector(transferClientDidBeginConnecting:)])
		[delegate transferClientDidBeginConnecting:self];
	
	/*
	// Too CPU intensive; using CFRunLoopRun() instead!
	NSRunLoop *theRL = [NSRunLoop currentRunLoop];
	BOOL result;
	if (theRL != [NSRunLoop mainRunLoop]) {
		runLoopShouldKeepRunning = YES;
		while (runLoopShouldKeepRunning && (result = [theRL runMode:NSDefaultRunLoopMode beforeDate:[NSDate date]]));
	}*/	
	CFRunLoopRun();
}

- (void)downloadFileWithResume:(BOOL)resume {
	if (resume) {
		NSError *error = nil;
		NSNumber *fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:[self.localURL path] error:&error] valueForKey:NSFileSize];
		if (!error)		
			totalBytesTransferred = [fileSize unsignedLongLongValue];
	}
	else
		totalBytesTransferred = 0;
	
	[self downloadFile];
}

#pragma mark -
#pragma mark NSStreamDelegate

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)streamEvent {
    assert(stream == self.networkStream);
	
    switch (streamEvent) {
        case NSStreamEventOpenCompleted: {
			streamOpen = YES;
			if ([delegate respondsToSelector:@selector(transferClientDidEstablishConnection:)])
				[delegate transferClientDidEstablishConnection:self];
			break;
        }
        case NSStreamEventHasBytesAvailable: {
            NSInteger       bytesRead;
            uint8_t         buffer[32768];
			
			if (!transferClientDidBeginTransfer) {
				if ([delegate respondsToSelector:@selector(transferClientDidBeginTransfer:)])
					[delegate transferClientDidBeginTransfer:self];
				transferClientDidBeginTransfer = YES;
			}
			
            // Pull some data off the network.
            bytesRead = [self.networkStream read:buffer maxLength:sizeof(buffer)];
            if (bytesRead == -1) {
                //[self _stopReceiveWithStatus:@"Network read error"];
            } else if (bytesRead == 0) {
                //[self _stopReceiveWithStatus:nil];
				NSLog(@"Transfer completed, closing connections.");
				[self closeConnections];
				if ([delegate respondsToSelector:@selector(transferClientDidFinishTransfer:)])
					[delegate transferClientDidFinishTransfer:self];
            } else {
                NSInteger bytesWritten;
                NSInteger bytesWrittenSoFar;
                
                // Write to the file.
                bytesWrittenSoFar = 0;
                do {
                    bytesWritten = [self.fileStream write:&buffer[bytesWrittenSoFar] maxLength:bytesRead - bytesWrittenSoFar];
                    assert(bytesWritten != 0);
                    if (bytesWritten == -1) {
                        //[self _stopReceiveWithStatus:@"File write error"];
						NSLog(@"Unable to write to file: %@", self.localURL);
						[self closeConnections];
                        break;
                    } else {
                        bytesWrittenSoFar += bytesWritten;
                    }
                } while (bytesWrittenSoFar != bytesRead);
				totalBytesTransferred += bytesWrittenSoFar;
				if ([delegate respondsToSelector:@selector(transferClient:didReceiveBytes:)])
					[delegate transferClient:self didReceiveBytes:totalBytesTransferred];
            }
			break;
        }
        case NSStreamEventHasSpaceAvailable: {
            assert(NO);     // should never happen for the output stream
			break;
        }
        case NSStreamEventErrorOccurred: {
			NSError *error = [stream streamError];
			NSLog(@"NSStreamEventErrorOccurred: %@", [error localizedDescription]);
            
			// Since we can't tell if this error has occurred before or after a connection was made,
			// we'll attempt to close the connections. If the connection was opened, it'll be closed
			// and the delegate will receive the transferClientDidCloseConnection: message.
			[self closeConnections];
			
			if ([delegate respondsToSelector:@selector(transferClientDidLoseConnection:withError:)])
				[delegate transferClientDidLoseConnection:self withError:error];
			break;
        }
        case NSStreamEventEndEncountered: {
            // ignore
			break;
        }
        default: {
            assert(NO);
			break;
        }
    }	
}

@end

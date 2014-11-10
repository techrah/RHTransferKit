//
//  RHUpload.m
//  RHUtil
//
//  Created by Ryan Homer on 2011-07-31.
//  Copyright 2011 Murage Inc. All rights reserved.
//

#import "RHUpload.h"

@interface RHUpload()
@property(retain) WTClient *wtClient;
@property(retain) NSString *username;
@property(retain) NSString *password;
@end

@implementation RHUpload

@synthesize delegate;
@synthesize viewDelegate;
@synthesize wtClient;
@synthesize username;
@synthesize password;
@synthesize contentLength;

- (id)initWithLocalURL:(NSURL *)localURL
			 remoteURL:(NSURL *)remoteURL
			  username:(NSString *)theUsername
			  password:(NSString *)thePassword
{
	if ((self = [super init])) {
		self.username = theUsername;
		self.password = thePassword;
		
		wtClient = [[WTClient alloc] initWithLocalURL:localURL
											remoteURL:remoteURL
											 username:username
											 password:password];
		
		if (!wtClient) {
			//[self release];
			return nil;
		}
		
		wtClient.delegate = self;
		NSString *path = [[localURL filePathURL] absoluteString];
		contentLength = [[[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] valueForKey:NSFileSize] unsignedLongLongValue];
	}
	return self;
}

#pragma mark - WTCientDelegate

- (void)transferClientDidReceivePropertiesResponse:(WTClient *)client {
    NSUInteger statusCode = [[client.currentResponse objectForKey:@"statusCode"] intValue];
#if TARGET_IPHONE_SIMULATOR
    NSLog(@"Response to properties request: %lu", (unsigned long)statusCode);
#endif
	//http://en.wikipedia.org/wiki/List_of_HTTP_status_codes
	// OK
    if (statusCode >= 200 && statusCode <= 299) {
		[wtClient uploadFile];
    }
	
	// Redirect
	//else if (statusCode == 301) {
	//}
	else if (statusCode >= 300 && statusCode <= 399) {
		NSString *newUrlString = [client.currentResponse objectForKey:@"Location"];
		
		if ([delegate respondsToSelector:@selector(uploadClient:didReceiveRedirectURL:)]) {
			NSURL *url = [NSURL URLWithString:newUrlString];
			[delegate uploadClient:self didReceiveRedirectURL:url];
			return;
		}
		else {
			NSLog(@"Received HTTP redirect URL");
			NSLog(@"Old URL: %@", [wtClient.remoteURL absoluteString]);
			NSLog(@"New URL: %@", [client.currentResponse objectForKey:@"Location"]);
			
			// Remove trailing slash if there is one, then create NSURL
			newUrlString = [newUrlString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
			NSURL *newURL = [NSURL URLWithString:newUrlString];
			
			wtClient.delegate = nil;
			//[wtClient stopTransfer]; // don't stop; prevent delegate messages.
			self.wtClient = [[[WTClient alloc] initWithLocalURL:wtClient.localURL
													  remoteURL:newURL
													   username:username
													   password:password] autorelease];
			wtClient.delegate = self;
			[self startTransfer];
			return;
		}
	}	
    else if (statusCode == 404) {
		// File not found; ok for upload.
		[wtClient uploadFile];
    }
    else {		
		NSLog(@"Error. Unexpected response from server. (Status code = %lu)", (unsigned long)statusCode);
		NSLog(@"%@", client.currentResponse);
		goto abort;
    }
	
	return;
	
abort:
	[self transferClientDidAbortTransfer:wtClient];
}

- (void)transferClientDidBeginConnecting:(WTClient *)client {
	[viewDelegate uploadClientDidBeginConnecting:self];
}

- (void)transferClientDidEstablishConnection:(WTClient *)client {
	[viewDelegate uploadClientDidEstablishConnection:self];
}

// Don't handle this case because if the file is not already on the server, which is OK, we'll end up with an error.
- (void)transferClientDidFailToEstablishConnection:(WTClient *)client {
	//[viewDelegate uploadClientDidFailToEstablishConnection:self];
}

- (void)transferClientDidCloseConnection:(WTClient *)client {
	[viewDelegate uploadClientDidCloseConnection:self];
}

- (void)transferClientDidLoseConnection:(WTClient *)client withError:(NSError *)error {
	[viewDelegate uploadClientDidLoseConnectionWithError:self];
}

- (void)transferClientDidFailToPassAuthenticationChallenge:(WTClient *)client {
	[viewDelegate uploadClientDidFailToPassAuthenticationChallenge:self];
}

- (void)transferClientDidBeginTransfer:(WTClient *)client {
	if ((id)viewDelegate == (id)delegate) {
		[delegate uploadClientDidBeginTransfer:self];
	}
	else {
		[viewDelegate uploadClientDidBeginTransfer:self];
		[delegate uploadClientDidBeginTransfer:self];
	}
}

- (void)transferClientDidFinishTransfer:(WTClient *)client {
	if ((id)viewDelegate == (id)delegate) {
		[delegate uploadClientDidFinishTransfer:self];
	}
	else {
		[viewDelegate uploadClientDidFinishTransfer:self];
		[delegate uploadClientDidFinishTransfer:self];
	}	
}

- (void)transferClientDidAbortTransfer:(WTClient *)client {
	if ((id)viewDelegate == (id)delegate) {
		[delegate uploadClientDidAbortTransfer:self];
	}
	else {
		[viewDelegate uploadClientDidAbortTransfer:self];
		[delegate uploadClientDidAbortTransfer:self];
	}
}

- (void)transferClient:(WTClient *)client didSendBytes:(unsigned long long)bytesWritten {
	[viewDelegate uploadClient:self didSendBytes:bytesWritten];
}

#pragma mark - Public

- (void)startTransfer {
	[wtClient requestProperties];
}

- (void)stopTransfer {
	[wtClient stopTransfer];
}

@end

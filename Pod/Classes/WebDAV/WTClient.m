//
//  WTClient.m
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


#import "WTClient.h"

@implementation WTClient
@synthesize remoteURL, credentials, properties, currentResponse, currentPropertyValue, delegate, propertiesConnection, authentication;
@synthesize downloadConnection, uploadConnection, localURL;

- (id)initWithLocalURL:(NSURL *)aLocalURL remoteURL:(NSURL *)aRemoteURL username:(NSString *)username password:(NSString *)password {
    if ((self = [super init])) {
		remoteURL = [aRemoteURL retain];
		localURL = [aLocalURL retain];
		credentials = [[NSDictionary alloc] initWithObjectsAndKeys:
					   username, kCFHTTPAuthenticationUsername,
					   password, kCFHTTPAuthenticationPassword,
					   nil];
    }
    return self;
}

- (BOOL)preparePropertiesConnection {
    WTHTTPConnection *connection = [[WTHTTPConnection alloc] initWithDestination:remoteURL
																		protocol:@"PROPFIND"];
    self.propertiesConnection = connection;
    [connection release];
    if (!self.propertiesConnection) {
		if ([self.delegate respondsToSelector:@selector(transferClientDidFailToEstablishConnection:)]) {
			[self.delegate transferClientDidFailToEstablishConnection:self];
		}
		return NO;
    }
    
    //TODO: request all properties here
	static NSString * const propFindString = @"<?xml version=\"1.0\" encoding=\"utf-8\" ?><D:propfind xmlns:D=\"DAV:\"><D:prop><D:getcontentlength/><D:getlastmodified/></D:prop></D:propfind>";
    [self.propertiesConnection setRequestBodyWithData:[propFindString dataUsingEncoding:NSUTF8StringEncoding]];
    [self.propertiesConnection setDelegate:self];
    return YES;
}

- (void)requestProperties {
    if ([self preparePropertiesConnection]) {
		self.properties = [NSMutableDictionary dictionary];
		[self.propertiesConnection openStream];
    }
}

- (void)uploadFile {
    if (self.uploadConnection == nil) {
		WTHTTPConnection *connection = [[WTHTTPConnection alloc] initWithDestination:remoteURL
																			protocol:@"PUT"];
		self.uploadConnection = connection;
		[connection release];
    }
    if (!self.uploadConnection) {
		if ([self.delegate respondsToSelector:@selector(transferClientDidFailToEstablishConnection:)]) {
			[self.delegate transferClientDidFailToEstablishConnection:self];
		}
		return;
    }
    
    if (self.authentication) {
		if (![self.uploadConnection setAuthentication:self.authentication credentials:self.credentials]) {
			if ([self.delegate respondsToSelector:@selector(transferClientDidFailToEstablishConnection:)]) {
				[self.delegate transferClientDidFailToEstablishConnection:self];
			}
			return;
		}
    }
    
    if (![self.uploadConnection setRequestBodyWithTargetURL:self.localURL offset:0]) {
		if ([self.delegate respondsToSelector:@selector(transferClientDidFailToEstablishConnection:)]) {
			[self.delegate transferClientDidFailToEstablishConnection:self];
		}
		return;
    }
    
    [self.uploadConnection setDelegate:self];
    [self.uploadConnection openStream];
    
}

- (void)downloadFileWithResume:(BOOL)resume {
	WTHTTPConnection *connection = [[WTHTTPConnection alloc] initWithDestination:remoteURL
																		protocol:@"GET"];
	self.downloadConnection = connection;
	[connection release];
	
    if (!self.downloadConnection) {
		if ([self.delegate respondsToSelector:@selector(transferClientDidFailToEstablishConnection:)]) {
			[self.delegate transferClientDidFailToEstablishConnection:self];
		}
		return;
    }
    
    if (self.authentication) {
		if (![self.downloadConnection setAuthentication:self.authentication credentials:self.credentials]) {
			if ([self.delegate respondsToSelector:@selector(transferClientDidFailToEstablishConnection:)]) {
				[self.delegate transferClientDidFailToEstablishConnection:self];
			}
			return;
		}
    }
	
    [self.downloadConnection setDelegate:self];
    [self.downloadConnection setLocalURL:self.localURL]; //to enable downloading into file instead of keeping data in memory
	
	if(resume)
		[self.downloadConnection setResumeRequestBodyForLocalURL];
	
    [self.downloadConnection openStream];
}

- (void)downloadFile {
	[self downloadFileWithResume:NO];
}

/*!
 * @method closeAllConnections
 * Closes all connections, but does not release them because the connections may still receive
 * responses from any communications that were still in progress and cause a crash.
 * They will be release when this object is deallocated.
 */
- (void)closeAllConnections {
    if (self.propertiesConnection) {
		[self.propertiesConnection closeStream];
		//self.propertiesConnection = nil;
		/*
		if ([self.delegate respondsToSelector:@selector(transferClientDidCloseConnection:)]) {
			[self.delegate transferClientDidCloseConnection:self];
		}
		*/
    }
    if (self.uploadConnection) {
		[self.uploadConnection closeStream];
		//self.uploadConnection = nil;
		if (streamOpen) {
			if ([self.delegate respondsToSelector:@selector(transferClientDidCloseConnection:)]) {
				[self.delegate transferClientDidCloseConnection:self];
			}
			streamOpen = NO;
		}
    }
    if (self.downloadConnection) {
		[self.downloadConnection closeStream];
		//self.downloadConnection = nil;
		if (streamOpen) {
			if ([self.delegate respondsToSelector:@selector(transferClientDidCloseConnection:)]) {
				[self.delegate transferClientDidCloseConnection:self];
			}
			streamOpen = NO;
		}
    }
}

- (void)stopTransfer {
	[self closeAllConnections];
	if ([self.delegate respondsToSelector:@selector(transferClientDidAbortTransfer:)]) {
		[self.delegate transferClientDidAbortTransfer:self];
    }	
}

- (void)HTTPConnection:(WTHTTPConnection *)connection didSendBytes:(unsigned long long)amountOfBytes {
    if (connection == self.uploadConnection) {
		//If we are uploading a file then report about uploading progress to delegate
		if (self.delegate && [self.delegate respondsToSelector:@selector(transferClient:didSendBytes:)]) {
			[self.delegate transferClient:self didSendBytes:amountOfBytes];
		}
    }
}

- (void)HTTPConnection:(WTHTTPConnection *)connection didReceiveBytes:(unsigned long long)amountOfBytes {
    if (connection == self.downloadConnection) {
		//If we are downloading a file then report about downloading progress to delegate
		if (self.delegate && [self.delegate respondsToSelector:@selector(transferClient:didReceiveBytes:)]) {
			[self.delegate transferClient:self didReceiveBytes:amountOfBytes];
		}
    }
}

- (void)HTTPConnection:(WTHTTPConnection *)connection didReceiveResponse:(NSDictionary *)response {
    self.currentResponse = response;
    if (connection == self.propertiesConnection) {
		
		/*
		NSData *responseBody = [NSData dataWithData:(NSData *)[response valueForKey:@"responseBody"]];
		//BOOL success = [responseBody writeToURL:[NSURL fileURLWithPath:[@"~/Desktop/resp.bin" stringByExpandingTildeInPath] isDirectory:NO] atomically:NO];
		BOOL success = [responseBody writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"resp.bin"] atomically:NO];
		NSLog(@"data dump successful: %@", success ? @"YES" : @"NO");
		*/
		
		//get properties from response body and report about to delegate when finished
		NSXMLParser *xmlParser = [[[NSXMLParser alloc] initWithData:[response valueForKey:@"responseBody"]] autorelease];
		[xmlParser setDelegate:self];
		[xmlParser parse];
    }
    else if (connection == self.uploadConnection || connection == self.downloadConnection) {
		[self closeAllConnections];
		if ([self.delegate respondsToSelector:@selector(transferClientDidFinishTransfer:)]) {
			[self.delegate transferClientDidFinishTransfer:self];
		}
    }
}

- (void)HTTPConnection:(WTHTTPConnection *)connection didReceiveAuthenticationChallenge:(CFHTTPAuthenticationRef)authenticationRef {
	CFRetain(authenticationRef);
    self.authentication = authenticationRef;
    if (![connection setAuthentication:self.authentication credentials:credentials]) {
		NSLog(@"Cannot provide authentication credentials for connection");
		if ([self.delegate respondsToSelector:@selector(transferClientDidFailToEstablishConnection:)]) {
			[self.delegate transferClientDidFailToEstablishConnection:self];
		}
		return;
    }
    
    if (![connection openStream]) {
		if ([self.delegate respondsToSelector:@selector(transferClientDidFailToEstablishConnection:)]) {
			[self.delegate transferClientDidFailToEstablishConnection:self];
		}
    }
}

- (void)HTTPConnection:(WTHTTPConnection *)connection didFailToPassAuthenticationChallenge:(CFHTTPAuthenticationRef)authentication {
    if ([self.delegate respondsToSelector:@selector(transferClientDidFailToPassAuthenticationChallenge:)]) {
		[self.delegate transferClientDidFailToPassAuthenticationChallenge:self];
    }
}


- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary *)attributeDict {
	//NSLog(@"elementName: %@", elementName);
    //get rid of namespaces
    NSString *key = nil;
    NSArray *parts = [[elementName lowercaseString] componentsSeparatedByString:@":"];
    if ([parts count] > 1) {
		key = [parts lastObject];
    }
    else {
		key = [parts objectAtIndex:0];
    }
    
    //if ([key isEqualToString:@"getcontentlength"] || [key isEqualToString:@"status"]) {
		[self.properties setObject:[NSMutableString string] forKey:key];
		self.currentPropertyValue = [self.properties objectForKey:key];
    //}
    //TODO: here should be proper properties parser
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    self.currentPropertyValue = nil;
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
	//NSLog(@"foundCharacters: %@", string);
    if (self.currentPropertyValue) {
		[self.currentPropertyValue appendString:string];
    }
}

- (void)parserDidEndDocument:(NSXMLParser *)parser {
    if ([self.delegate respondsToSelector:@selector(transferClientDidReceivePropertiesResponse:)]) {
		[self.delegate transferClientDidReceivePropertiesResponse:self];
    }
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
	NSLog(@"WebDAV PROPFIND Parse Error: %@", [parseError localizedDescription]);
	[self parserDidEndDocument:parser];
}

- (void)interruptedHTTPConnection:(WTHTTPConnection *)connection withError:(NSError *)error {
	[self closeAllConnections];
    if ([self.delegate respondsToSelector:@selector(transferClientDidLoseConnection:withError:)]) {
		[self.delegate transferClientDidLoseConnection:self withError:error];
    }
}

- (void)HTTPConnectionDidBeginEstablishingConnection:(WTHTTPConnection *)connection {
    if ([self.delegate respondsToSelector:@selector(transferClientDidBeginConnecting:)]) {
		[self.delegate transferClientDidBeginConnecting:self];
    }
}    

- (void)HTTPConnectionDidEstablish:(WTHTTPConnection *)connection {
    if (connection == self.downloadConnection || connection == self.uploadConnection) {
		streamOpen = YES;
		if ([self.delegate respondsToSelector:@selector(transferClientDidEstablishConnection:)]) {
			[self.delegate transferClientDidEstablishConnection:self];
		}
		if ([self.delegate respondsToSelector:@selector(transferClientDidBeginTransfer:)]) {
			[self.delegate transferClientDidBeginTransfer:self];
		}
    }
}

- (void)HTTPConnectionDidFailToEstablish:(WTHTTPConnection *)connection {
    if ([self.delegate respondsToSelector:@selector(transferClientDidFailToEstablishConnection:)]) {
		[self.delegate transferClientDidFailToEstablishConnection:self];
    }    
}


- (void)dealloc {
	#if TARGET_IPHONE_SIMULATOR
    NSLog(@"WTClient object will be deallocated");
	#endif
	
	self.delegate = nil;
	
	// Reminder: releasing each connection here instead of via closeAllConnections
	// because at this point we do not want to change the network indicator status.
	// Since a dealloc might not happen right away, it's possible that another connection has
	// already set the indicator status to show so we don't want to hide it now.
	//[self closeAllConnections];
	self.propertiesConnection = nil;
    self.downloadConnection = nil;
    self.uploadConnection = nil;
    
	if (authentication) {
		CFRelease(authentication);
		authentication = NULL;
    }
    self.localURL = nil;
    self.remoteURL = nil;
    self.currentResponse = nil;
    self.credentials = nil;
    self.properties = nil;
    self.currentPropertyValue = nil;
    [super dealloc];
}

@end

//
//  WTHTTPConnection.h
//
//  $Revision: 12 $
//  $LastChangedDate: 2009-02-07 14:35:24 -0500 (Sat, 07 Feb 2009) $
//  $LastChangedBy: alex.chugunov $
//
//  This part of source code is distributed under MIT Licence
//  Copyright (c) 2009 Alex Chugunov
//  http://code.google.com/p/wtclient/
//
//  Parts of this code may have been changed since the original version on Google Code.
//  None of these changes have been added to that respsitory.

#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>

@protocol WTHTTPConnectionDelegate;

@interface WTHTTPConnection : NSObject {
    BOOL isOpen;
    BOOL authenticationRequired;
    NSError *connectionError;
    NSURL *destinationURL;
    NSURL *localURL;
	
    NSMutableData *responseData;
    NSOutputStream *responseStream;
    NSDate *lastActivity;
    
    CFHTTPMessageRef request;
    CFReadStreamRef bodyStream;
    CFReadStreamRef requestStream;
	
    unsigned long long bytesBeforeResume;	
    unsigned long long bytesForDownload;
    unsigned long long bytesReceived;
    NSTimer *connectionTimer;
    NSTimeInterval connectionTimeout;
	
    id<WTHTTPConnectionDelegate> delegate;
}

- (id)initWithDestination:(NSURL *)destination protocol:(NSString *)protocol;
- (void)handleEnd;
- (void)handleError:(NSError *)error;
- (void)handleBytes:(UInt8 *)buffer length:(CFIndex)bytesRead;
- (void)pollConnection:(NSTimer *)aTimer;
- (void)setRequestBodyWithData:(NSData *)data;
- (BOOL)setRequestBodyWithTargetURL:(NSURL *)targetURL offset:(unsigned long long)offset;
- (BOOL)setResumeRequestBodyForLocalURL;
- (BOOL)setAuthentication:(CFHTTPAuthenticationRef)authentication credentials:(NSDictionary *)credentials;
- (BOOL)openStream;
- (void)closeStream;

@property (nonatomic, retain) NSError *connectionError;
@property (nonatomic, retain) NSURL *localURL;
@property (nonatomic, readonly) CFHTTPMessageRef request;
@property (nonatomic, readonly) CFReadStreamRef requestStream;
@property (nonatomic, assign) id<WTHTTPConnectionDelegate> delegate;
@property (nonatomic, retain) NSTimer *connectionTimer;
@property (nonatomic, retain) NSDate *lastActivity;
@property (nonatomic, readwrite) NSTimeInterval connectionTimeout;

@end

@protocol WTHTTPConnectionDelegate <NSObject>

@optional

- (void)HTTPConnection:(WTHTTPConnection *)connection didSendBytes:(unsigned long long)amountOfBytes;
- (void)HTTPConnection:(WTHTTPConnection *)connection didReceiveBytes:(unsigned long long)amountOfBytes;

- (void)HTTPConnectionDidBeginEstablishingConnection:(WTHTTPConnection *)connection;
- (void)HTTPConnectionDidEstablish:(WTHTTPConnection *)connection;
- (void)HTTPConnectionDidFailToEstablish:(WTHTTPConnection *)connection;

- (void)HTTPConnection:(WTHTTPConnection *)connection didReceiveResponse:(NSDictionary *)response;
- (void)HTTPConnection:(WTHTTPConnection *)connection didReceiveAuthenticationChallenge:(CFHTTPAuthenticationRef)authentication; 
- (void)HTTPConnection:(WTHTTPConnection *)connection didFailToPassAuthenticationChallenge:(CFHTTPAuthenticationRef)authentication;
- (void)interruptedHTTPConnection:(WTHTTPConnection *)connection withError:(NSError *)error;

@end

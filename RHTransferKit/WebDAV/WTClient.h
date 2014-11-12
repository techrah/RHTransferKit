//
//  WTClient.h
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

#import <Foundation/Foundation.h>
#import "WTHTTPConnection.h"

@protocol WTClientDelegate;

@interface WTClient : NSObject <WTHTTPConnectionDelegate
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 40000
,NSXMLParserDelegate
#endif
> {
    BOOL authorized;
    
    NSURL *remoteURL;
    NSURL *localURL;
    NSDictionary *credentials;
    NSDictionary *currentResponse;
    
    NSMutableDictionary *properties;
    NSMutableString *currentPropertyValue;
    
    WTHTTPConnection *propertiesConnection;
    WTHTTPConnection *uploadConnection;
    WTHTTPConnection *downloadConnection;
    
    CFHTTPAuthenticationRef authentication;
    
    id<WTClientDelegate> delegate;
	BOOL streamOpen;
}

@property (nonatomic, retain) NSURL *remoteURL;
@property (nonatomic, retain) NSURL *localURL;
@property (nonatomic, retain) NSMutableDictionary *properties;
@property (nonatomic, retain) NSMutableString *currentPropertyValue;
@property (nonatomic, retain) WTHTTPConnection *propertiesConnection;
@property (nonatomic, retain) WTHTTPConnection *uploadConnection;
@property (nonatomic, retain) WTHTTPConnection *downloadConnection;
@property (nonatomic, assign) id<WTClientDelegate> delegate;
@property (nonatomic, retain) NSDictionary *currentResponse;
@property (nonatomic, retain) NSDictionary *credentials;
@property (nonatomic) CFHTTPAuthenticationRef authentication;

- (id)initWithLocalURL:(NSURL *)aLocalURL remoteURL:(NSURL *)aRemoteURL username:(NSString *)username password:(NSString *)password;
- (BOOL)preparePropertiesConnection;
- (void)requestProperties;
- (void)stopTransfer;
- (void)uploadFile;
- (void)downloadFile;
- (void)downloadFileWithResume:(BOOL)resume;

@end

@protocol WTClientDelegate <NSObject>

@optional
- (void)transferClientDidBeginConnecting:(WTClient *)client;
- (void)transferClientDidEstablishConnection:(WTClient *)client;
- (void)transferClientDidFailToEstablishConnection:(WTClient *)client;
- (void)transferClientDidCloseConnection:(WTClient *)client;
- (void)transferClientDidLoseConnection:(WTClient *)client withError:(NSError *)error;
- (void)transferClientDidFailToPassAuthenticationChallenge:(WTClient *)client;
- (void)transferClientDidReceivePropertiesResponse:(WTClient *)client;

- (void)transferClientDidBeginTransfer:(WTClient *)client;
- (void)transferClientDidFinishTransfer:(WTClient *)client;
- (void)transferClientDidAbortTransfer:(WTClient *)client;
- (void)transferClient:(WTClient *)client didSendBytes:(unsigned long long)bytesWritten;
- (void)transferClient:(WTClient *)client didReceiveBytes:(unsigned long long)bytesWritten;

@end

//
//  RHUpload.h
//  RHUtil
//
//  Created by Ryan Homer on 2011-07-31.
//  Copyright 2011 Murage Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WTClient.h"

@protocol RHUploadDelegate;
@protocol RHUploadViewDelegate;

@interface RHUpload : NSObject <WTClientDelegate> {
	id<RHUploadDelegate> delegate;
	id<RHUploadViewDelegate> viewDelegate;
	WTClient *wtClient;
	NSString *username;
	NSString *password;
	unsigned long long contentLength;	// bytes
}

- (id)initWithLocalURL:(NSURL *)localURL
			 remoteURL:(NSURL *)remoteURL
			  username:(NSString *)username
			  password:(NSString *)password;

- (void)startTransfer;
- (void)stopTransfer;

@property(nonatomic,assign) id<RHUploadDelegate> delegate;
@property(nonatomic,assign) id<RHUploadViewDelegate> viewDelegate;
@property(readonly) unsigned long long contentLength;

@end


@protocol RHUploadViewDelegate <NSObject>

@required
- (void)uploadClientDidFailToEstablishConnection:(RHUpload *)client;
- (void)uploadClientDidLoseConnectionWithError:(RHUpload *)client;
- (void)uploadClientDidFailToPassAuthenticationChallenge:(RHUpload *)client;
- (void)uploadClientDidAbortTransfer:(RHUpload *)client;
- (void)uploadClientDidFinishTransfer:(RHUpload *)client;

@optional
- (void)uploadClientRequestQueued:(RHUpload *)client;
- (void)uploadClientDidBeginConnecting:(RHUpload *)client;
- (void)uploadClientDidEstablishConnection:(RHUpload *)client;
- (void)uploadClientDidBeginTransfer:(RHUpload *)client;
- (void)uploadClientDidCloseConnection:(RHUpload *)client;
- (void)uploadClient:(RHUpload *)client didSendBytes:(unsigned long long)bytesWritten;
//- (void)uploadClientInitiatedResumeRequest:(RHUpload *)client;
//- (void)setTotalSizeAndSizeUnitsForBytes:(unsigned long long)totalSizeInBytes;
@end


@protocol RHUploadDelegate <NSObject>

@optional
- (void)uploadClientDidBeginTransfer:(RHUpload *)client;
- (void)uploadClientDidAbortTransfer:(RHUpload *)client;

/**
 Auto redirects if not implemented.
 */
- (void)uploadClient:(RHUpload *)client didReceiveRedirectURL:(NSURL *)url;

@required
- (void)uploadClientDidFinishTransfer:(RHUpload *)client;

@end
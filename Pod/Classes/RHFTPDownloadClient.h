//
//  RHFTPDownloadClient.h
//  iCED
//
//  Created by Ryan on 2010-08-16.
//  Copyright 2010 Murage Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol RHFTPDownloadClientDelegate;

@interface RHFTPDownloadClient : NSObject<NSStreamDelegate> {
	NSInputStream *networkStream;
    NSOutputStream *fileStream;
    NSURL *remoteURL;
    NSURL *localURL;
	NSString *username;
	NSString *password;
	id<RHFTPDownloadClientDelegate> delegate;
	unsigned long long totalBytesTransferred;
	BOOL streamOpen;
	BOOL transferClientDidBeginTransfer;
	//CFRunLoopRef currentRunLoop;
}

@property(nonatomic,retain) NSURL *remoteURL;
@property(nonatomic,retain) NSURL *localURL;
@property(nonatomic,retain) NSString *username;
@property(nonatomic,retain) NSString *password;
@property(nonatomic,assign) id<RHFTPDownloadClientDelegate> delegate;

- (id)initWithLocalURL:(NSURL *)aLocalURL remoteURL:(NSURL *)aRemoteURL username:(NSString *)username password:(NSString *)password;
- (void)stopTransfer;
- (void)downloadFile;
- (void)downloadFileWithResume:(BOOL)resume;

@end


@protocol RHFTPDownloadClientDelegate<NSObject>
@optional
- (void)transferClientDidBeginConnecting:(RHFTPDownloadClient *)client;
- (void)transferClientDidEstablishConnection:(RHFTPDownloadClient *)client;
- (void)transferClientDidFailToEstablishConnection:(RHFTPDownloadClient *)client;
- (void)transferClientDidCloseConnection:(RHFTPDownloadClient *)client;
- (void)transferClientDidLoseConnection:(RHFTPDownloadClient *)client withError:(NSError *)error;

- (void)transferClientDidBeginTransfer:(RHFTPDownloadClient *)client;
- (void)transferClientDidFinishTransfer:(RHFTPDownloadClient *)client;
- (void)transferClientDidAbortTransfer:(RHFTPDownloadClient *)client;

- (void)transferClient:(RHFTPDownloadClient *)client didSendBytes:(unsigned long long)bytesWritten;
- (void)transferClient:(RHFTPDownloadClient *)client didReceiveBytes:(unsigned long long)bytesWritten;

@end

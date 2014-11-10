//
//  RHDownloadItem.h
//  RHUtil
//
//  Created by Ryan Homer on 2010-02-20.
//  Copyright 2010 Murage Inc.. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface RHDownloadItem : NSObject <NSCoding,NSCopying> {
	NSString *itemId;
	NSString *title;
	NSURL *localURL, *remoteURL;
	NSString *username, *password;
	BOOL shouldArchivePassword; // Default is YES when designated initializer is used, otherwise NO.
}

@property(nonatomic,retain) NSString *itemId;
@property(nonatomic,retain) NSString *title;
@property(nonatomic,retain) NSURL *localURL;
@property(nonatomic,retain) NSURL *remoteURL;
@property(nonatomic,retain) NSString *username;
@property(nonatomic,retain) NSString *password;
@property(nonatomic) BOOL shouldArchivePassword;

// Uses designated initializer to return an autoreleased CEDownloadItem *
+ (RHDownloadItem *)downloadItemWithId:(NSString *)itemId title:(NSString *)theTitle localURL:(NSURL *)theLocalURL remoteURL:(NSURL *)theRemoteURL username:(NSString *)theUsername password:(NSString *)thePassword;

// The designated initializer
- (id)initWithId:(NSString *)itemId title:(NSString *)title localURL:(NSURL *)localURL remoteURL:(NSURL *)remoteURL username:(NSString *)username password:(NSString *)password;

@end

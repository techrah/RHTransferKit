//
//  RHDownloadItem.m
//  RHUtil
//
//  Created by Ryan Homer on 2010-02-20.
//  Copyright 2010 Murage Inc.. All rights reserved.
//

#import "RHDownloadItem.h"


@implementation RHDownloadItem

@synthesize itemId, title, localURL, remoteURL, username, password, shouldArchivePassword;

+ (RHDownloadItem *)downloadItemWithId:(NSString *)theItemId
								 title:(NSString *)theTitle 
							  localURL:(NSURL *)theLocalURL 
							 remoteURL:(NSURL *)theRemoteURL 
							  username:(NSString *)theUsername 
							  password:(NSString *)thePassword
{
	return [[[RHDownloadItem alloc] initWithId:theItemId
										 title:theTitle
									  localURL:theLocalURL
									 remoteURL:theRemoteURL
									  username:theUsername
									  password:thePassword] autorelease];
}

- (id)initWithId:(NSString *)theItemId
		   title:(NSString *)theTitle 
		localURL:(NSURL *)theLocalURL 
	   remoteURL:(NSURL *)theRemoteURL 
		username:(NSString *)theUsername 
		password:(NSString *)thePassword
{
	if ( (self = [super init]) ) {
		self.itemId = theItemId;
		self.title = theTitle;
		self.localURL = theLocalURL;
		self.remoteURL = theRemoteURL;
		self.username = theUsername;
		self.password = thePassword;
		self.shouldArchivePassword = YES;
	}
	
	return self;
}

- (void) dealloc {
	[itemId release];
	[title release];
	[localURL release];
	[remoteURL release];
	[username release];
	[password release];
	[super dealloc];
}


#pragma mark NSCoding protocol methods

- (void)encodeWithCoder:(NSCoder *)encoder {
	[encoder encodeObject:self.itemId forKey:@"itemId"];
	[encoder encodeObject:self.title forKey:@"title"];
	[encoder encodeObject:self.localURL forKey:@"localURL"];
	[encoder encodeObject:self.remoteURL forKey:@"remoteURL"];
	[encoder encodeObject:self.username forKey:@"username"];
	[encoder encodeObject:[NSNumber numberWithBool:self.shouldArchivePassword] forKey:@"shouldArchivePassword"];
	if (self.shouldArchivePassword)
		[encoder encodeObject:self.password forKey:@"password"];
}

- (id)initWithCoder:(NSCoder *)decoder {
	self = [super init];
	self.itemId = [decoder decodeObjectForKey:@"itemId"];
	if (!self.itemId) self.itemId = [decoder decodeObjectForKey:@"pid"]; // backward compatibility
	self.title = [decoder decodeObjectForKey:@"title"];
	self.localURL = [decoder decodeObjectForKey:@"localURL"];
	
	//#if TARGET_IPHONE_SIMULATOR
	// Fix URL since simulator always (iPhone sometimes) uses a different path for each new install
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *downloadsDirectory = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"Downloads"];
	NSString *localPath = [downloadsDirectory stringByAppendingPathComponent:[self.localURL lastPathComponent]];
	
	self.localURL = [NSURL fileURLWithPath:localPath];
	//#endif
	
	self.remoteURL = [decoder decodeObjectForKey:@"remoteURL"];
	self.username = [decoder decodeObjectForKey:@"username"];
	self.shouldArchivePassword = [(NSNumber *)[decoder decodeObjectForKey:@"shouldArchivePassword"] boolValue];
	self.password = [decoder decodeObjectForKey:@"password"];
	return self;
}

#pragma mark NSCopying protocol methods

- (id)copyWithZone:(NSZone *)zone {
	RHDownloadItem *copy = [[[self class] allocWithZone:zone] init];
	copy.itemId = self.itemId;
	copy.title = self.title;
	copy.localURL = self.localURL;
	copy.remoteURL = self.remoteURL;
	copy.username = self.username;
	copy.password = self.password;
	return copy;
}

@end

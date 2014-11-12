//
//  ViewController.m
//  RHTransferKitSample
//
//  Created by Ryan Homer on 11/11/2014.
//  Copyright (c) 2014 Murage Inc. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()
@end

@implementation ViewController

@synthesize download = _download;

- (void)viewDidLoad {
	[super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}

- (IBAction)downloadAction:(UIButton *)sender {
	self.downloadProgress.progress = 0.0;
	
	NSURL *localURL = [NSURL fileURLWithPath:[[NSString stringWithFormat:@"~/Documents/%@", self.urlTextField.text.lastPathComponent] stringByExpandingTildeInPath]];
	
	RHDownloadItem * downloadItem = [RHDownloadItem downloadItemWithId:@"com.example.product1" // e.g.: App Store Product ID
																 title:@"My Product" // e.g.: App Store Product Title
															  localURL:localURL
															 remoteURL:[NSURL URLWithString:self.urlTextField.text]
															  username:self.user.text
															  password:self.password.text];
	
	self.download = [RHDownload downloadWithDownloadItem:downloadItem];
	self.download.delegate = self;
	self.download.viewDelegate = self;
	[self.download downloadFile];
}

#pragma mark RHDownloadDelegate

- (void)downloadClientDidFinishTransfer:(RHDownload *)client {
	self.downloadStatus.text = @"Transfer Complete";
}

#pragma mark RHDownloadViewDelegate

- (void)downloadClient:(RHDownload *)client didReceiveBytes:(unsigned long long)bytesWritten {
	self.downloadProgress.progress = (float)((double)bytesWritten/(double)client.contentLength);
	self.downloadStatus.text = [NSString stringWithFormat:@"%llu bytes downloaded.", bytesWritten];
}

- (void)downloadClientDidFailToEstablishConnection:(RHDownload *)client {
	self.downloadStatus.text = @"Error establishing connection!";
}

- (void)downloadClientDidLoseConnectionWithError:(RHDownload *)client {
	// error is stored in client.error
	self.downloadStatus.text = [NSString stringWithFormat:@"Error: %@", client.error.description];
}

- (void)downloadClientDidFailToPassAuthenticationChallenge:(RHDownload *)client {
	self.downloadStatus.text = @"Authentication Error.";	
}

- (void)downloadClientDidAbortTransfer:(RHDownload *)client {
	
}

@end

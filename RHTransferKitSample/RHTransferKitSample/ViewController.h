//
//  ViewController.h
//  RHTransferKitSample
//
//  Created by Ryan Homer on 11/11/2014.
//  Copyright (c) 2014 Murage Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "RHDownload.h"

@interface ViewController : UIViewController <RHDownloadDelegate, RHDownloadViewDelegate> {
	RHDownload * _download;
}

@property (weak, nonatomic) IBOutlet UITextField *urlTextField;
@property (weak, nonatomic) IBOutlet UITextField *user;
@property (weak, nonatomic) IBOutlet UITextField *password;
@property (weak, nonatomic) IBOutlet UIProgressView *downloadProgress;
@property (weak, nonatomic) IBOutlet UILabel *downloadStatus;

@property (strong, nonatomic) RHDownload * download;

- (IBAction)downloadAction:(UIButton *)sender;

@end


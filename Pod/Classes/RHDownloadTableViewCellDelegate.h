//
//  RHDownloadTableViewCellDelegate.h
//  RHUtil
//
//  Created by Ryan Homer on 2010-02-18.
//  Copyright 2010 Murage Inc.. All rights reserved.
//


@protocol RHDownloadTableViewCellDelegate <NSObject>

@optional
- (void)stopTransfer;
- (void)downloadFileWithResume;

@end
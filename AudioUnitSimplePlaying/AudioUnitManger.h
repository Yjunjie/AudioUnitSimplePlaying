//
//  AudioUnitManger.h
//  AudioUnitSimplePlaying
//
//  Created by Double-J🍎 on 2019/3/14.
//  Copyright © 2019年 Double-J🍎. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioUnitManger : NSObject
-(instancetype)initWithURL:(NSURL*)url;
- (BOOL)play;
- (BOOL)stop;
@end

NS_ASSUME_NONNULL_END

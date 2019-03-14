//
//  ViewController.m
//  AudioUnitSimplePlaying
//
//  Created by Double-J🍎 on 2019/3/14.
//  Copyright © 2019年 Double-J🍎. All rights reserved.
//

#import "ViewController.h"
#import "AudioUnitManger.h"
@interface ViewController ()

@end
//http://www.ytmp3.cn/down/58627.mp3
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    AudioUnitManger *player = [[AudioUnitManger alloc] initWithURL:[NSURL URLWithString:@"http://www.ytmp3.cn/down/58627.mp3"]];
    [player play];
}


@end

//
//  ViewController.m
//  SRSocketDemo
//
//  Created by apple on 2019/2/21.
//  Copyright © 2019 Crystal. All rights reserved.
//

#import "ViewController.h"
#import "SocketRocketUtility.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [[SocketRocketUtility instance] SRWebSocketOpenWithURLString:@"wss://openservice.dev.jsjinfo.cn/notification-gateway/v1/ws/300/20613282"];
}


@end

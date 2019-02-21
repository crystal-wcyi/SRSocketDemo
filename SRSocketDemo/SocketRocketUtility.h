//
//  SocketRocketUtility.h
//  SRSocketDemo
//
//  Created by apple on 2019/2/21.
//  Copyright © 2019 Crystal. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SocketRocketUtility : NSObject

+ (SocketRocketUtility *)instance;

/**
 开启连接
 
 @param urlString websocket的地址，写入自己后台的地址
 */
- (void)SRWebSocketOpenWithURLString:(NSString *)urlString;

/**
 断开连接
 */
- (void)SRWebSocketClose;

@end

NS_ASSUME_NONNULL_END

//
//  SocketRocketUtility.m
//  SRSocketDemo
//
//  Created by apple on 2019/2/21.
//  Copyright © 2019 Crystal. All rights reserved.
//

#import "SocketRocketUtility.h"
#import <SocketRocket.h>

#ifndef dispatch_main_async_safe
#define dispatch_main_async_safe(block)\
if (strcmp(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL), dispatch_queue_get_label(dispatch_get_main_queue())) == 0) {\
block();\
} else {\
dispatch_async(dispatch_get_main_queue(), block);\
}
#endif

NSString *const kNeedPayOrderNote = @"kNeedPayOrderNote";//发送的通知名称

@interface SocketRocketUtility () <SRWebSocketDelegate>
{
    NSTimer *heartBeat;
    NSTimeInterval reConnectTime;
}

@property (nonatomic, strong) SRWebSocket *socket;

@end

@implementation SocketRocketUtility

+ (SocketRocketUtility *)instance {
    static SocketRocketUtility *instance = nil;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        instance = [[SocketRocketUtility alloc] init];
    });
    return instance;
}

/**
 开启连接

 @param urlString websocket的地址，写入自己后台的地址
 */
- (void)SRWebSocketOpenWithURLString:(NSString *)urlString {
    if (self.socket) {
        return;
    }
    if (!urlString) {
        return;
    }
    
    //SRWebSocketUrlString 就是websocket的地址，写入自己后台的地址
    self.socket = [[SRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlString]]];
    self.socket.delegate = self;
    [self.socket open];//开始连接
}

/**
 断开连接
 */
- (void)SRWebSocketClose {
    if (self.socket) {
        [self.socket close];
        self.socket = nil;
        //断开连接时销毁心跳
        [self destoryHeartBeat];
    }
}

- (void)destoryHeartBeat {
    dispatch_main_async_safe(^{
        if (self->heartBeat) {
            [self->heartBeat invalidate];
            self->heartBeat = nil;
        }
    });
}

//初始化心跳
- (void)initHeartBeat {
    dispatch_main_async_safe(^{
        [self destoryHeartBeat];
        self->heartBeat = [NSTimer scheduledTimerWithTimeInterval:20 target:self selector:@selector(heartTimeAction) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:self->heartBeat forMode:NSRunLoopCommonModes];
    });
}

- (void)heartTimeAction {
    NSLog(@"heart");
    //和服务器约定好发送什么作为心跳标识，尽可能的减少心跳包大小
    [self sendData:@"+"];
}

//重连机制
- (void)reConnect {
    [self SRWebSocketClose];
    //超过一分钟就不再重连
    if (reConnectTime > 64) {
        return;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(reConnectTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.socket = nil;
        [self SRWebSocketOpenWithURLString:@"wss://openservice.dev.jsjinfo.cn/notification-gateway/v1/ws/300/20613282"];
        NSLog(@"重连");
    });
    
    //重连时间2的指数级增长
    if (reConnectTime == 0) {
        reConnectTime = 2;
    } else {
        reConnectTime *= 2;
    }
}

- (void)sendData:(NSString *)data {
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t queue = dispatch_queue_create("zy", NULL);
    dispatch_async(queue, ^{
        if (weakSelf.socket != nil) {
            //只有 SR_OPEN 开启状态才能调 send 方法，不然崩溃
            if (weakSelf.socket.readyState == SR_OPEN) {
                [weakSelf.socket send:data];
            } else if (weakSelf.socket.readyState == SR_CONNECTING) {
                NSLog(@"正在连接中，重连后其他方法会去自动同步数据");
                // 每隔2秒检测一次 socket.readyState 状态，检测 10 次左右
                // 只要有一次状态是 SR_OPEN 的就调用 [ws.socket send:data] 发送数据
                // 如果 10 次都还是没连上的，那这个发送请求就丢失了，这种情况是服务器的问题了，小概率的
                [self reConnect];
            } else if (weakSelf.socket.readyState == SR_CLOSED || weakSelf.socket.readyState == SR_CLOSING) {
                //websocket 断开了，调用reconnect 方法重连
                [self reConnect];
            }
        } else {
            NSLog(@"没网络，发送失败，一旦断网 socket 会被我设置为nil 的");
        }
    });
}

//pingpong机制
- (void)ping {
    [self.socket sendPing:nil];
}

#pragma mark - SRWebsocketDelegate

- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
    NSLog(@"连接成功，可以与服务器交流了，同时需要开启心跳");
    //每次正常连接的时候清零重连时间
    reConnectTime = 0;
    //开启心跳，心跳是发送pong的消息，这里根据后台的要求发送“+”给后台
    [self initHeartBeat];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"kWebSocketDidOpenNote" object:nil];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    NSLog(@"连接失败，这里可以实现掉线自动重连，要注意以下几点");
    NSLog(@"1.判断当前网络环境，如果断网了就不要重连了，等待网络到来，在发起重连");
    NSLog(@"2.判断调用层是否需要连接，例如用户都没在聊天界面，连接上浪费流量");
    NSLog(@"3.连接次数限制，如果连接失败了，重连10次左右就可以了，不然就死循环了。");
    _socket = nil;
    [self reConnect];
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
    NSLog(@"被关闭连接，code:%ld, reason:%@, wasClean:%d", code, reason, wasClean);
    //断开连接，同事销毁心跳
//    [self SRWebSocketClose];
    [self reConnect];
}

/**
 该方法是接收服务器发送的pong消息，其中最后一个是接受pong消息的，
 在这里就要提一下心跳包，一般情况下建立长连接都会建立一个心跳包，
 用于每个一段时间通知一次服务器，客户端还是在线，这个心跳包其实就是一个ping消息
 建立一个定时器，每个十秒或者十五秒向服务器发送一个ping消息，这个消息可以是空的

 @param webSocket <#webSocket description#>
 @param pongPayload <#pongPayload description#>
 */
- (void)webSocket:(SRWebSocket *)webSocket didReceivePong:(NSData *)pongPayload {
    NSString *reply = [[NSString alloc] initWithData:pongPayload encoding:NSUTF8StringEncoding];
    NSLog(@"reply===%@", reply);
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message {
    //收到服务器发过来的数据，这里的数据可以和后台约定一个格式
    NSLog(@"message==%@", message);
    [[NSNotificationCenter defaultCenter] postNotificationName:kNeedPayOrderNote object:message];
}

@end

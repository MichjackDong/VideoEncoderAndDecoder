//
//  HDVideoEncoder.h
//  iOSVideoEncoder
//
//  Created by TianGe on 2020/4/1.
//  Copyright © 2020 hedong. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <VideoToolbox/VideoToolbox.h>

typedef NS_ENUM(NSInteger,EncoderType){
    EncoderTypeH264,
    EncoderTypeH265
};

struct VideoEncoderData {
    BOOL isKeyFrame;
    BOOL isExtraData;
    uint8_t *data;
    size_t size;
    int64_t timestamp;
};

typedef struct VideoEncoderData *EncoderDataRef;


@protocol HDVideoEncoderDelegate <NSObject>

- (void)receiveEncoderData:(EncoderDataRef)data;

@end

@interface HDVideoEncoder : NSObject

@property(nonatomic,assign) EncoderType encoderType;
@property(nonatomic,weak)   id<HDVideoEncoderDelegate> delegate;


/// 初始化
/// @param videoSize 视频size
/// @param fps 帧率,帧率以每秒钟接收的视频帧数量来衡量
/// @param bitRate 码率
/// @param isRealTimeEncode 是否实时执行压缩
/// @param encoderType 编码格式
- (instancetype)initWithVideoSize:(CGSize)videoSize fps:(int)fps bitRate:(int)bitRate isRealTimeEncode:(BOOL)isRealTimeEncode encoderType:(EncoderType)encoderType;


- (void)configureEncoderWithWidth:(int)width height:(int)height;

- (void)startEncoderWithDataBuffer:(CMSampleBufferRef)sampleBuffer isNeedFreeBuffer:(BOOL)isFreeBuffer;

//释放资源
- (void)releaseEncoder;

- (void)forceInsertKeyFrame;

@end




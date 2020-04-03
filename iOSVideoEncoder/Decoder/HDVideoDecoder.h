//
//  HDVideoDecoder.h
//  iOSVideoEncoder
//
//  Created by TianGe on 2020/4/2.
//  Copyright © 2020 hedong. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

//视频显示数据格式
typedef enum: NSUInteger {
   VideoDataType_Image = 0,
   VideoDataType_Pixel,
   VideoDataType_Layer,
}DisplayVideoDataType;


@class HDVideoDecoder;

@protocol VideoDecoderDelegate <NSObject>

- (void)decoder:(HDVideoDecoder *) decoder didDecodingFrame:(CVPixelBufferRef) imageBuffer;

@end

@interface HDVideoDecoder : NSObject

@property(nonatomic,weak) id<VideoDecoderDelegate> delegate;
@property(nonatomic,assign)DisplayVideoDataType showType;
@property (nonatomic,strong) UIImage *image;            //解码成RGB数据时的IMG
@property (nonatomic,assign) CVPixelBufferRef pixelBuffer;    //解码成YUV数据时的解码BUF
@property (nonatomic,strong) AVSampleBufferDisplayLayer *displayLayer;  //显示图层

@property (nonatomic,assign) BOOL isNeedPerfectImg;    //是否读取完整UIImage图形(showType为0时才有效)

/**
 H264视频流解码
 @param videoData 视频帧数据
 @param videoSize 视频帧大小
 @return 视图的宽高(width, height)，当为接收为AVSampleBufferDisplayLayer时返回接口是无效的
 */
- (CGSize)decodeH264VideoData:(uint8_t *)videoData videoSize:(NSInteger)videoSize;
 
/**
 释放解码器
 */
- (void)releaseH264HwDecoder;
 
/**
 视频截图
 @return IMG
 */
- (UIImage *)snapshot;
 
@end



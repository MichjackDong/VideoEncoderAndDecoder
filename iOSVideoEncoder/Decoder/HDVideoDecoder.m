//
//  HDVideoDecoder.m
//  iOSVideoEncoder
//
//  Created by TianGe on 2020/4/2.
//  Copyright © 2020 hedong. All rights reserved.
//

#import "HDVideoDecoder.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

#ifndef DeleteCharP
#define DeleteCharP(p) if (p) {free(p); p = NULL;}
#endif


typedef enum : NSUInteger {
    HDVideoFrameType_UNKNOWN = 0,
    HDVideoFrameType_I,
    HDVideoFrameType_P,
    HDVideoFrameType_B,
    HDVideoFrameType_SPS,
    HDVideoFrameType_PPS,
    HDVideoFrameType_SEI,
} HDVideoFrameType;

@interface HDVideoDecoder ()
{
    
    VTDecompressionSessionRef _deocderSession;
    CMVideoFormatDescriptionRef _decoderFormatDescription;   //  解码 format 封装了sps和pps
    //sps & pps
    uint8_t *_sps;
    NSInteger _spsSize;
    uint8_t *_pps;
    NSInteger _ppsSize;
    
    uint8_t *_pSEI;
    NSInteger _seiSize;
    
    NSInteger _mINalCount;        //I帧起始码个数
    NSInteger _mPBNalCount;       //P、B帧起始码个数
    NSInteger _mINalIndex;       //I帧起始码开始位
    
    BOOL _mIsNeedReinit;         //需要重置解码器
    
}

@end

@implementation HDVideoDecoder

/*
 typedef void (*VTDecompressionOutputCallback)(
 void * CM_NULLABLE decompressionOutputRefCon,
 void * CM_NULLABLE sourceFrameRefCon,
 OSStatus status,
 VTDecodeInfoFlags infoFlags,
 CM_NULLABLE CVImageBufferRef imageBuffer,
 CMTime presentationTimeStamp,
 CMTime presentationDuration );
 */
//解码回调函数
static void didDecompress(void *decompressionOutputRefCon, void*sourceFrameRefCon, OSStatus status,VTDecodeInfoFlags infoFlags,CVImageBufferRef imageBuffer,CMTime presentationTimeStamp, CMTime presentationDuration){
    
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef*)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(imageBuffer);
    
    NSLog(@"-----解码------");
    
    HDVideoDecoder *decoder = (__bridge HDVideoDecoder*)decompressionOutputRefCon;
    
    if ([decoder.delegate respondsToSelector:@selector(decoder:didDecodingFrame:)]) {
        [decoder.delegate decoder:decoder didDecodingFrame:*outputPixelBuffer];
    }
}
- (instancetype)init {
    if (self = [super init]) {
        _sps = _pps = _pSEI = NULL;
        _spsSize = _ppsSize = _seiSize = 0;
        _mINalCount = _mPBNalCount = _mINalIndex = 0;
        _mIsNeedReinit = NO;
        
        _showType = VideoDataType_Image;
        
        _isNeedPerfectImg = NO;
        _pixelBuffer = NULL;
    }
    return self;
}
- (BOOL)initH264Decoder {
    if(_deocderSession) {
        return YES;
    }
    const uint8_t* const parameterSetPointers[2] = { _sps, _pps };
    const size_t parameterSetSizes[2] = { _spsSize, _ppsSize };
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          2, //param count
                                                                          parameterSetPointers,
                                                                          parameterSetSizes,
                                                                          4, //nal start code size
                                                                          &_decoderFormatDescription);
    
    if(status == noErr) {
        /*
         //      kCVPixelFormatType_420YpCbCr8Planar is YUV420
        //      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange is NV12
        //      kCVPixelFormatType_24RGB    //使用24位bitsPerPixel
        //      kCVPixelFormatType_32BGRA   //使用32位bitsPerPixel，kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
         */
        uint32_t pixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;  //NV12
        if (self.showType == VideoDataType_Pixel) {
            pixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
        }
        NSDictionary* destinationPixelBufferAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:pixelFormatType],
                                                           //这里宽高和编码反的
                                                           (id)kCVPixelBufferOpenGLCompatibilityKey : [NSNumber numberWithBool:YES]
                                                           };
        
        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompress;
        callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              _decoderFormatDescription,
                                              NULL,
                                              (__bridge CFDictionaryRef)destinationPixelBufferAttributes,
                                              &callBackRecord,
                                              &_deocderSession);
        VTSessionSetProperty(_deocderSession, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
        VTSessionSetProperty(_deocderSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    } else {
        NSLog(@"IOS8VT: reset decoder session failed status=%d", (int)status);
    }
    
    return YES;
}
- (void)removeH264HwDecoder
{
    if(_deocderSession) {
        VTDecompressionSessionInvalidate(_deocderSession);
        CFRelease(_deocderSession);
        _deocderSession = NULL;
    }
    
    if(_decoderFormatDescription) {
        CFRelease(_decoderFormatDescription);
        _decoderFormatDescription = NULL;
    }
}

- (void)releaseH264HwDecoder
{
    [self removeH264HwDecoder];
    
    DeleteCharP(_sps);
    DeleteCharP(_pps);
    DeleteCharP(_pSEI);
    _spsSize = 0;
    _ppsSize = 0;
    _seiSize = 0;
    
    if (_pixelBuffer) {
        CVPixelBufferRelease(_pixelBuffer);
        _pixelBuffer = NULL;
    }
}
 


- (CVPixelBufferRef)decode:(uint8_t *)frame withSize:(NSInteger)frameSize{
    
    __weak typeof(self)weakSelf = self;
    CVPixelBufferRef outputPixelBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status  = CMBlockBufferCreateWithMemoryBlock(NULL,
                                                          (void *)frame,
                                                          frameSize,
                                                          kCFAllocatorNull,
                                                          NULL,
                                                          0,
                                                          frameSize,
                                                          FALSE,
                                                          &blockBuffer);
    if(status == kCMBlockBufferNoErr) {
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = {frameSize};
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           _decoderFormatDescription ,
                                           1, 0, NULL, 1, sampleSizeArray,
                                           &sampleBuffer);
        if (status == kCMBlockBufferNoErr && sampleBuffer) {
            if (self.showType == VideoDataType_Layer && _displayLayer) {
                CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
                CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
                CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
                if ([self.displayLayer isReadyForMoreMediaData]) {
                    dispatch_sync(dispatch_get_main_queue(),^{
                        [weakSelf.displayLayer enqueueSampleBuffer:sampleBuffer];
                    });
                }
                
                CFRelease(sampleBuffer);
            }else{
            
                VTDecodeFrameFlags flags = 0;
                VTDecodeInfoFlags flagOut = 0;
                OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(_deocderSession,
                                                                          sampleBuffer,
                                                                          flags,
                                                                          &outputPixelBuffer,
                                                                          &flagOut);
                
                if(decodeStatus == kVTInvalidSessionErr) {
                    [self removeH264HwDecoder];
                    NSLog(@"IOS8VT: Invalid session, reset decoder session");
                } else if(decodeStatus == kVTVideoDecoderBadDataErr) {
                    NSLog(@"IOS8VT: decode failed status=%d(Bad data)", (int)decodeStatus);
                    CVPixelBufferRelease(outputPixelBuffer);
                    outputPixelBuffer = NULL;
                } else if(decodeStatus != noErr) {
                    NSLog(@"IOS8VT: decode failed status=%d", (int)decodeStatus);
                }
                CFRelease(sampleBuffer);
            }
        }
        CFRelease(blockBuffer);
    }
    return outputPixelBuffer;
}

- (CGSize)decodeH264VideoData:(uint8_t *)videoData videoSize:(NSInteger)videoSize
{
    CGSize imageSize = CGSizeMake(0, 0);
    if (videoData && videoSize > 0) {
        HDVideoFrameType frameFlag = [self analyticalData:videoData size:videoSize];
        if (_mIsNeedReinit) {
            _mIsNeedReinit = NO;
            [self removeH264HwDecoder];
        }
        
        if (_sps && _pps && (frameFlag == HDVideoFrameType_I || frameFlag == HDVideoFrameType_P || frameFlag == HDVideoFrameType_B)) {
            uint8_t *buffer = NULL;
            if (frameFlag == HDVideoFrameType_I) {
                int nalExtra = (_mINalCount==3?1:0);      //如果是3位的起始码，转为大端时需要增加1位
                videoSize -= _mINalIndex;
                buffer = (uint8_t *)malloc(videoSize + nalExtra);
                memcpy(buffer + nalExtra, videoData + _mINalIndex, videoSize);
                videoSize += nalExtra;
            } else {
                int nalExtra = (_mPBNalCount==3?1:0);
                buffer = (uint8_t *)malloc(videoSize + nalExtra);
                memcpy(buffer + nalExtra, videoData, videoSize);
                videoSize += nalExtra;
            }
            
            uint32_t nalSize = (uint32_t)(videoSize - 4);
            uint32_t *pNalSize = (uint32_t *)buffer;
            *pNalSize = CFSwapInt32HostToBig(nalSize);
            
            CVPixelBufferRef pixelBuffer = NULL;
            if ([self initH264Decoder]) {
                pixelBuffer = [self decode:buffer withSize:videoSize];
                
                if(pixelBuffer) {
                    NSInteger width = CVPixelBufferGetWidth(pixelBuffer);
                    NSInteger height = CVPixelBufferGetHeight(pixelBuffer);
                    imageSize = CGSizeMake(width, height);
                    
                    if (self.showType == VideoDataType_Pixel) {
                        if (_pixelBuffer) {
                            CVPixelBufferRelease(_pixelBuffer);
                        }
                        self.pixelBuffer = CVPixelBufferRetain(pixelBuffer);
                    } else {
                        if (frameFlag == HDVideoFrameType_B) {  //若B帧未进行乱序解码，顺序播放，则在此需要去除，否则解码图形则是灰色。
                            size_t planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
                            if (planeCount >= 2 && planeCount <= 3) {
                                CVPixelBufferLockBaseAddress(pixelBuffer, 0);
                                u_char *yDestPlane = (u_char *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
                                if (planeCount == 2) {
                                    u_char *uvDestPlane = (u_char *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
                                    if (yDestPlane[0] == 0x80 && uvDestPlane[0] == 0x80 && uvDestPlane[1] == 0x80) {
                                        frameFlag = HDVideoFrameType_UNKNOWN;
                                        NSLog(@"Video YUV data parse error: Y=%02x U=%02x V=%02x", yDestPlane[0], uvDestPlane[0], uvDestPlane[1]);
                                    }
                                } else if (planeCount == 3) {
                                    u_char *uDestPlane = (u_char *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
                                    u_char *vDestPlane = (u_char *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 2);
                                    if (yDestPlane[0] == 0x80 && uDestPlane[0] == 0x80 && vDestPlane[0] == 0x80) {
                                        frameFlag = HDVideoFrameType_UNKNOWN;
                                        NSLog(@"Video YUV data parse error: Y=%02x U=%02x V=%02x", yDestPlane[0], uDestPlane[0], vDestPlane[0]);
                                    }
                                }
                                CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
                            }
                        }
                        
                        if (frameFlag != HDVideoFrameType_UNKNOWN) {
                            self.image = [self pixelBufferToImage:pixelBuffer];
                        }
                    }
                    
                    CVPixelBufferRelease(pixelBuffer);
                }
            }
            
            DeleteCharP(buffer);
        }
    }
    
    return imageSize;
}
 
- (UIImage *)pixelBufferToImage:(CVPixelBufferRef)pixelBuffer
{
    UIImage *image = nil;
    if (!self.isNeedPerfectImg) {
        //第1种绘制（可直接显示，不可保存为文件(无效缺少图像描述参数)）
        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
        image = [UIImage imageWithCIImage:ciImage];
    } else {
        //第2种绘制（可直接显示，可直接保存为文件，相对第一种性能消耗略大）
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    CIContext *temporaryContext = [CIContext contextWithOptions:nil];
    CGImageRef videoImage = [temporaryContext createCGImage:ciImage fromRect:CGRectMake(0, 0, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer))];
    image = [[UIImage alloc] initWithCGImage:videoImage];
    CGImageRelease(videoImage);
    }
    
    return image;
}
 
- (UIImage *)snapshot
{
    UIImage *img = nil;
    if (self.displayLayer) {
        UIGraphicsBeginImageContext(self.displayLayer.bounds.size);
        [self.displayLayer renderInContext:UIGraphicsGetCurrentContext()];
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    } else {
        if (self.showType == VideoDataType_Pixel) {
            if (self.pixelBuffer) {
                img = [self pixelBufferToImage:self.pixelBuffer];
            }
        } else {
            img = self.image;
        }
        
        if (!self.isNeedPerfectImg) {
            UIGraphicsBeginImageContext(CGSizeMake(img.size.width, img.size.height));
            [img drawInRect:CGRectMake(0, 0, img.size.width, img.size.height)];
            img = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
    }
    
    return img;
}
 
 
//从起始位开始查询SPS、PPS、SEI、I、B、P帧起始码，遇到I、P、B帧则退出
//存在多种情况：
//1、起始码是0x0 0x0 0x0 0x01 或 0x0 0x0 0x1
//2、每个SPS、PPS、SEI、I、B、P帧为单独的Slice
//3、I帧中包含SPS、PPS、I数据Slice
//4、I帧中包含第3点的数据之外还包含SEI，顺序：SPS、PPS、SEI、I
//5、起始位是AVCC协议格式的大端数据(不支持多Slice的视频帧)
- (HDVideoFrameType)analyticalData:(const uint8_t *)buffer size:(NSInteger)size
{
    NSInteger preIndex = 0;
    HDVideoFrameType preFrameType = HDVideoFrameType_UNKNOWN;
    HDVideoFrameType curFrameType = HDVideoFrameType_UNKNOWN;
    for (int i=0; i<size && i<300; i++) {       //一般第四种情况下的帧起始信息不会超过(32+256+12)位，可适当增大，为了不循环整个帧片数据
        int nalSize = [self getNALHeaderLen:(buffer + i) size:size-i];
        if (nalSize == 0 && i == 0) {   //当每个Slice起始位开始若使用AVCC协议则判断帧大小是否一致
            uint32_t *pNalSize = (uint32_t *)(buffer);
            uint32_t videoSize = CFSwapInt32BigToHost(*pNalSize);    //大端模式转为系统端模式
            if (videoSize == size - 4) {     //是大端模式(AVCC)
                nalSize = 4;
            }
        }
        
        if (nalSize && i + nalSize + 1 < size) {
            int sliceType = buffer[i + nalSize] & 0x1F;
            
            if (sliceType == 0x1) {
                _mPBNalCount = nalSize;
                if (buffer[i + nalSize] == 0x1) {   //B帧
                    curFrameType = HDVideoFrameType_B;
                } else {    //P帧
                    curFrameType = HDVideoFrameType_P;
                }
                break;
            } else if (sliceType == 0x5) {     //IDR(I帧)
                if (preFrameType == HDVideoFrameType_PPS) {
                    _mIsNeedReinit = [self getSliceInfo:buffer slice:&_pps size:&_ppsSize start:preIndex end:i];
                } else if (preFrameType == HDVideoFrameType_SEI)  {
                    [self getSliceInfo:buffer slice:&_pSEI size:&_seiSize start:preIndex end:i];
                }
                
                _mINalCount = nalSize;
                _mINalIndex = i;
                curFrameType = HDVideoFrameType_I;
                goto Goto_Exit;
            } else if (sliceType == 0x7) {      //SPS
                preFrameType = HDVideoFrameType_SPS;
                preIndex = i + nalSize;
                i += nalSize;
            } else if (sliceType == 0x8) {      //PPS
                if (preFrameType == HDVideoFrameType_SPS) {
                    _mIsNeedReinit = [self getSliceInfo:buffer slice:&_sps size:&_spsSize start:preIndex end:i];
                }
                
                preFrameType = HDVideoFrameType_PPS;
                preIndex = i + nalSize;
                i += nalSize;
            } else if (sliceType == 0x6) {      //SEI
                if (preFrameType == HDVideoFrameType_PPS) {
                    _mIsNeedReinit = [self getSliceInfo:buffer slice:&_pps size:&_ppsSize start:preIndex end:i];
                }
                
                preFrameType = HDVideoFrameType_SEI;
                preIndex = i + nalSize;
                i += nalSize;
            }
        }
    }
    
    //SPS、PPS、SEI为单独的Slice帧片
    if (curFrameType == HDVideoFrameType_UNKNOWN && preIndex != 0) {
        if (preFrameType == HDVideoFrameType_SPS) {
            _mIsNeedReinit = [self getSliceInfo:buffer slice:&_sps size:&_spsSize start:preIndex end:size];
            curFrameType = HDVideoFrameType_SPS;
        } else if (preFrameType == HDVideoFrameType_PPS) {
             _mIsNeedReinit = [self getSliceInfo:buffer slice:&_pps size:&_ppsSize start:preIndex end:size];
            curFrameType = HDVideoFrameType_PPS;
        } else if (preFrameType == HDVideoFrameType_SEI)  {
            [self getSliceInfo:buffer slice:&_pSEI size:&_seiSize start:preIndex end:size];
            curFrameType = HDVideoFrameType_SEI;
        }
    }
    
Goto_Exit:
    return curFrameType;
}
 
//获取NAL的起始码长度是3还4
- (int)getNALHeaderLen:(const uint8_t *)buffer size:(NSInteger)size
{
    if (size >= 4 && buffer[0] == 0x0 && buffer[1] == 0x0 && buffer[2] == 0x0 && buffer[3] == 0x1) {
        return 4;
    } else if (size >= 3 && buffer[0] == 0x0 && buffer[1] == 0x0 && buffer[2] == 0x1) {
        return 3;
    }
    
    return 0;
}
 
//给SPS、PPS、SEI的Buf赋值，返回YES表示不同于之前的值
- (BOOL)getSliceInfo:(const uint8_t *)videoBuf slice:(uint8_t **)sliceBuf size:(NSInteger *)size start:(NSInteger)start end:(NSInteger)end
{
    BOOL isDif = NO;
    NSInteger len = end - start;
    uint8_t *tempBuf = (uint8_t *)(*sliceBuf);
    if (tempBuf) {
        if (len != *size || memcmp(tempBuf, videoBuf + start, len) != 0) {
            free(tempBuf);
            tempBuf = (uint8_t *)malloc(len);
            memcpy(tempBuf, videoBuf + start, len);
            
            *sliceBuf = tempBuf;
            *size = len;
            
            isDif = YES;
        }
    } else {
        tempBuf = (uint8_t *)malloc(len);
        memcpy(tempBuf, videoBuf + start, len);
        
        *sliceBuf = tempBuf;
        *size = len;
    }
    
    return isDif;
}
@end

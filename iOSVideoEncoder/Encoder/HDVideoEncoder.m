//
//  HDVideoEncoder.m
//  iOSVideoEncoder
//
//  Created by TianGe on 2020/4/1.
//  Copyright © 2020 hedong. All rights reserved.
//

#import "HDVideoEncoder.h"
#import <AVFoundation/AVFoundation.h>


uint32_t g_capture_base_time = 0;

static const size_t kStartCodeLength = 4;
//每个nalu单元开始码
static const uint8_t kStartCode[] = {0x00, 0x00, 0x00, 0x01};

@interface HDVideoEncoder ()
{
    VTCompressionSessionRef   sessionRef;//编码器
}

// encoder property
@property (assign, nonatomic) BOOL isSupportEncoder;
@property (assign, nonatomic) BOOL isRealTimeEncode;
@property (assign, nonatomic) BOOL needForceInsertKeyFrame;
@property (assign, nonatomic) int  width;
@property (assign, nonatomic) int  height;
@property (assign, nonatomic) int  fps;
@property (assign, nonatomic) int  bitRate;
@property (assign, nonatomic) int  errorCount;

@property (assign, nonatomic) BOOL                   needResetKeyParamSetBuffer;
@property (strong, nonatomic) NSLock                 *lock;
@property (strong, nonatomic) NSMutableArray         *averageBitratesArray;

@end


static HDVideoEncoder *encoder = NULL;

void   printfBuffer(uint8_t* buf, int size, char* name);

void   writeFile(uint8_t *buf, int size, FILE *videoFile, int frameCount);

@implementation HDVideoEncoder


#pragma mark - 编码回调

/*
 typedef void (*VTCompressionOutputCallback)(
 void * CM_NULLABLE outputCallbackRefCon,
 void * CM_NULLABLE sourceFrameRefCon,
 OSStatus status,
 VTEncodeInfoFlags infoFlags,
 CM_NULLABLE CMSampleBufferRef sampleBuffer );
 */

//编码格式为AVCC 大端字节序  iOS使用的是小端模式 需要转化 CFSwapInt32BigToHost
void OutputCallback(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags,CMSampleBufferRef sampleBuffer){
    
    HDVideoEncoder *encoder = (__bridge HDVideoEncoder*)outputCallbackRefCon;
    
    if (status != noErr) {
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        NSLog(@"H264: vtCallBack failed with %@", error);
        NSLog(@"encode frame failured! %s" ,error.debugDescription.UTF8String);
        return;
    }
    if (!encoder.isSupportEncoder) {
        return;
    }
    
    CMBlockBufferRef bufferRef = CMSampleBufferGetDataBuffer(sampleBuffer);
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);//视频帧的pts
    CMTime dts = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
    
    
    // Use our define time. (the time is used to sync audio and video)
    
    int64_t ptsAfter = (int64_t)((CMTimeGetSeconds(pts) - g_capture_base_time)*1000);
    int64_t dtsAfter = (int64_t)((CMTimeGetSeconds(dts) - g_capture_base_time)*1000);
    
    dtsAfter = ptsAfter;
    
    /*sometimes relative dts is zero, provide a workground to restore dts*/
    static int64_t last_dts = 0;
    if(dtsAfter == 0){
       dtsAfter = last_dts + 33;
    }else if (dtsAfter == last_dts){
       dtsAfter = dtsAfter + 1;
    }
    BOOL isKeyFrame = NO;
    CFArrayRef bufferArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    if (bufferArray != NULL) {
        CFDictionaryRef attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(bufferArray, 0);
        CFBooleanRef dependsOnOthers = (CFBooleanRef)CFDictionaryGetValue(attachment, kCMSampleAttachmentKey_DependsOnOthers);
        isKeyFrame = (dependsOnOthers == kCFBooleanFalse);
    }
    
    if (isKeyFrame) {
         static uint8_t *keyParameterSetBuffer = NULL;
         static size_t  keyParameterSetBufferSize = 0;
         // Note: the NALU header will not change if video resolution not change.
        if (keyParameterSetBufferSize == 0 || encoder.needResetKeyParamSetBuffer == YES) {
            const uint8_t *vps, *sps, *pps;
            size_t  vpsSize, spsSize, ppsSize = 0;
            int   NALUnitHeaderLengthOut;
            size_t         parmCount;
            
            if (keyParameterSetBuffer != NULL) {
                free(keyParameterSetBuffer);
            }
            
            CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
            if (encoder.encoderType == EncoderTypeH264) {
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format,
                                                                   0,
                                                                   &sps,
                                                                   &spsSize,
                                                                   &parmCount,
                                                                   &NALUnitHeaderLengthOut);
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format,
                                                                   1,
                                                                   &pps,
                                                                   &ppsSize,
                                                                   &parmCount,
                                                                   &NALUnitHeaderLengthOut);
                keyParameterSetBufferSize = spsSize + 4 + ppsSize + 4;
                keyParameterSetBuffer = (uint8_t*)malloc(keyParameterSetBufferSize);
                memcpy(keyParameterSetBuffer, "\x00\x00\x00\x01", 4);
                memcpy(&keyParameterSetBuffer[4], sps, spsSize);
                memcpy(&keyParameterSetBuffer[4 + spsSize], "\x00\x00\x00\x01", 4);
                memcpy(&keyParameterSetBuffer[4+spsSize+4], pps, ppsSize);
                NSLog(@"Video Encoder: H264 find IDR frame， spsSize : %zu, ppsSize : %zu",spsSize, ppsSize);
            }else{
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format,
                                                                   0,
                                                                   &vps,
                                                                   &vpsSize,
                                                                   &parmCount,
                                                                   &NALUnitHeaderLengthOut);
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format,
                                                                   1,
                                                                   &sps,
                                                                   &spsSize,
                                                                   &parmCount,
                                                                   &NALUnitHeaderLengthOut);
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format,
                                                                   2,
                                                                   &pps,
                                                                   &ppsSize,
                                                                   &parmCount,
                                                                   &NALUnitHeaderLengthOut);
                keyParameterSetBufferSize = vpsSize + 4 + spsSize + 4 + ppsSize +4;
                keyParameterSetBuffer = (uint8_t*)malloc(keyParameterSetBufferSize);
                memcpy(keyParameterSetBuffer, "\x00\x00\x00\x01", 4);
                memcpy(&keyParameterSetBuffer[4], vps, vpsSize);
                memcpy(&keyParameterSetBuffer[4+vpsSize], "\x00\x00\x00\x01", 4);
                memcpy(&keyParameterSetBuffer[4+vpsSize+4], sps, spsSize);
                memcpy(&keyParameterSetBuffer[4+vpsSize+4+spsSize], "\x00\x00\x00\x01", 4);
                memcpy(&keyParameterSetBuffer[4+vpsSize+4+spsSize+4], pps, ppsSize);
                
                NSLog(@"Video Encoder: H265 find IDR frame, vpsSize : %zu, spsSize : %zu, ppsSize : %zu",vpsSize,spsSize, ppsSize);
            }
            encoder.needResetKeyParamSetBuffer = NO;
        }
        
        struct VideoEncoderData encoderData = {
            .isKeyFrame = NO,
            .isExtraData = YES,
            .data = keyParameterSetBuffer,
            .size = keyParameterSetBufferSize,
            .timestamp = dtsAfter,
        };
        
        if ([encoder.delegate respondsToSelector:@selector(receiveEncoderData:)]) {
            [encoder.delegate receiveEncoderData:&encoderData];
        }
        NSLog(@"load a I frame");
    }
    size_t blockBufferLength;
    uint8_t *bufferDataPointer = NULL;
    CMBlockBufferGetDataPointer(bufferRef, 0, NULL, &blockBufferLength,(char **)&bufferDataPointer);
    size_t bufferOffset = 0;
    while (bufferOffset < blockBufferLength - kStartCodeLength) {
       uint32_t NALUnitLength = 0;
       memcpy(&NALUnitLength, bufferDataPointer+bufferOffset, kStartCodeLength);
       NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
       memcpy(bufferDataPointer+bufferOffset, kStartCode, kStartCodeLength);
       bufferOffset += kStartCodeLength + NALUnitLength;
    }
    struct VideoEncoderData encoderData = {
        .isKeyFrame  = isKeyFrame,
        .isExtraData = NO,
        .data        = bufferDataPointer,
        .size        = blockBufferLength,
        .timestamp   = dtsAfter,
    };
    
    if ([encoder.delegate respondsToSelector:@selector(receiveEncoderData:)]) {
        [encoder.delegate receiveEncoderData:&encoderData];
    }
    
    last_dts = dtsAfter;
    
}


- (instancetype)initWithVideoSize:(CGSize)videoSize fps:(int)fps bitRate:(int)bitRate isRealTimeEncode:(BOOL)isRealTimeEncode encoderType:(EncoderType)encoderType {
    if (self = [super init]) {
        sessionRef = NULL;
        _width  = videoSize.width;
        _height = videoSize.height;
        _fps    = fps;
        _bitRate = bitRate << 10; //转化为 bps
        _errorCount = 0;
        _isSupportEncoder = NO;
        _encoderType = encoderType;
        _lock = [[NSLock alloc] init];
        _isRealTimeEncode = isRealTimeEncode;
        _needResetKeyParamSetBuffer = YES;
        if (encoderType == EncoderTypeH265) {
            if (@available(iOS 11.0,*)) {
                if ([[AVAssetExportSession allExportPresets] containsObject:AVAssetExportPresetHEVCHighestQuality]) {
                    _isSupportEncoder = YES;
                }
            }
        }else if(encoderType == EncoderTypeH264){
            _isSupportEncoder = YES;
        }
        NSLog(@"Video Encoder Init encoder width:%d, height:%d, fps:%d, bitrate:%d, is support encoder:%d, encoder type:H%ld", _width, _height, fps, bitRate, isRealTimeEncode,(long)encoderType);
    }
    return self;
}


- (void)configureEncoderWithWidth:(int)width height:(int)height {
    if (width == 0 || height == 0) {
        NSLog(@"encoder width or height can't is null");
        return;
    }
    
    self.width = width;
    self.height = height;
    sessionRef = [self configureEncoderWithEncoderType:self.encoderType
                                              callback:OutputCallback
                                                 width:self.width
                                                height:self.height
                                                   fps:self.fps
                                               bitrate:self.bitRate
                               isSupportRealtimeEncode:self.isRealTimeEncode
                                        iFrameDuration:30
                                                  lock:self.lock];
}
#pragma mark - 创建编码器
- (VTCompressionSessionRef)configureEncoderWithEncoderType:(EncoderType)encoderType callback:(VTCompressionOutputCallback)callback width:(int)width height:(int)height fps:(int)fps bitrate:(int)bitrate isSupportRealtimeEncode:(BOOL)isSupportRealtimeEncode iFrameDuration:(int)iFrameDuration lock:(NSLock *)lock  {
    [lock lock];
    
    //创建VTCompressionSessionRef
    VTCompressionSessionRef session = [self createCompressionSessionWithEncoderType:encoderType
                                                                              width:width
                                                                             height:height callback:callback];
    //设置编码器参数
    int maxCount = 3;
/*
 kVTCompressionPropertyKey_MaxFrameDelayCount:
 编码器在输出压缩帧前允许保留的最大帧数默认为kVTUnlimitedFrameDelayCount,即不限制保留帧数.比如当前要编码10帧数据,最大延迟帧数为3(M),那么在编码10(N)帧视频数据时,10-3(N-M)帧数据必须已经发送给编码回调.即已经编好了N-M帧数据,还保留M帧未编码的数据.
     */
    
    if (!isSupportRealtimeEncode) {
        if ([self isSupportPropertyWithSession:session key:kVTCompressionPropertyKey_MaxFrameDelayCount]) {
            CFNumberRef ref = CFNumberCreate(NULL, kCFNumberSInt32Type, &maxCount);
            [self setSessionProperty:session key:kVTCompressionPropertyKey_MaxFrameDelayCount value:ref];
            CFRelease(ref);
        }
    }
    
    /*
     kVTCompressionPropertyKey_ExpectedFrameRate
     期望帧率，帧率以每秒钟接收视频帧数量来衡量 此属性无法控制帧率而仅仅作为编码器n编码的指示 以便在编码前设置内部参数配置 实际取决于视频帧的duration并且可能是不同的  默认0 表示未知
     */
    if (fps) {
        if ([self isSupportPropertyWithSession:session key:kVTCompressionPropertyKey_ExpectedFrameRate]) {
            CFNumberRef ref = CFNumberCreate(NULL, kCFNumberSInt32Type, &fps);
            [self setSessionProperty:session key:kVTCompressionPropertyKey_ExpectedFrameRate value:ref];
            CFRelease(ref);
        }
    }else{
        NSLog(@"Video Encoder: Current fps is 0");
        return nil;
    }
    /*
     kVTCompressionPropertyKey_AverageBitRate
     长期编码的平均码率 此属性不是一个绝对设置 实际产生的码率可能高于此值默认0 表示编码器自行决定编码的大小 注意码率设置仅在为原始帧提供信息时有效 并且某些编码器不支持限制指定的码率
     */
    if (bitrate) {
        if ([self isSupportPropertyWithSession:session key:kVTCompressionPropertyKey_AverageBitRate]) {
            CFNumberRef ref = CFNumberCreate(NULL, kCFNumberSInt32Type, &bitrate);
            [self setSessionProperty:session key:kVTCompressionPropertyKey_AverageBitRate value:ref];
            CFRelease(ref);
        }
    }else{
        NSLog(@"Video Encoder: Current bitrate is 0");
        return nil;
    }
    
    /*
     kVTCompressionPropertyKey_RealTime
     是否实时执行压缩false:表示视频编码器可以比实时更慢地工作 以产生更好的效果 设置true可以更加即时的编码 默认NULL 表示未知
     */
    if ([self isSupportPropertyWithSession:session key:kVTCompressionPropertyKey_RealTime]) {
         NSLog(@"Video Encoder: use realTimeEncoder");
        [self setSessionProperty:session key:kVTCompressionPropertyKey_RealTime value:isSupportRealtimeEncode ? kCFBooleanTrue : kCFBooleanFalse];
    }
    /*
     kVTCompressionPropertyKey_ProfileLevel
     指定编码比特流的配置文件和级别。可用的配置文件和级别因格式和视频编码器而异。 视频编码器应该在可用的地方使用标准密匙 而不是标准模式
     kVTCompressionPropertyKey_H264EntropyMode
      H.264压缩的熵编码模式 如果H.264编码器支持，则此属性控制编码器是使用基于上下文的自适应可变长度编码CAVLC 还是基于上下文的自适应二进制算术编码(CABAC)。CABAC通常以更高的计算开销为代价提供更好的压缩。 默认值是编码器特定的
     可能会根据其他编码器设置而改变 使用此属性应小心更改可能会导致配置与请求的配置文件和级别 不兼容。 这种情况下的结果是未定义的
     可能包括编码错误或不符合要求的输出流
     
     */
    if (encoderType == EncoderTypeH264) {
        if (isSupportRealtimeEncode) {
            if ([self isSupportPropertyWithSession:session key:kVTCompressionPropertyKey_ProfileLevel]) {
                [self setSessionProperty:session key:kVTCompressionPropertyKey_ProfileLevel value:kVTProfileLevel_H264_Main_AutoLevel];
            }
        }else{
            if ([self isSupportPropertyWithSession:session key:kVTCompressionPropertyKey_ProfileLevel]) {
                [self setSessionProperty:session key:kVTCompressionPropertyKey_ProfileLevel value:kVTProfileLevel_H264_Baseline_AutoLevel];
            }
            if([self isSupportPropertyWithSession:session key:kVTCompressionPropertyKey_H264EntropyMode]) {
                [self setSessionProperty:session key:kVTCompressionPropertyKey_H264EntropyMode value:kVTH264EntropyMode_CAVLC];
            }
        }
    }else{
        
        if ([self isSupportPropertyWithSession:session key:kVTCompressionPropertyKey_ProfileLevel]) {
            [self setSessionProperty:session key:kVTCompressionPropertyKey_ProfileLevel value:kVTProfileLevel_HEVC_Main_AutoLevel];
        }
        
    }
    /*
     kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration
     从一个关键帧到下一个关键帧的最长s持续时间（秒）。默认为0 没有限制。当帧速率可变时，此属性特别有用。 此键可以与
     kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration 一起设置，并且将强制执行这两个限制- 每X帧或每Y秒
     需要一个关键帧 以先到者为准
     
     kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration
     关键帧之间的最大间隔 以帧的数量为单位。 关键帧 也成为i帧 重置帧间依赖关系；解码关键帧足以准备解码器以正确解码随后的差异帧。允许视频编码器更频繁的生成关键帧。如果这将导致更有效的压缩。 默认关键帧间隔为0  表示视频编码器应选则放置所有关键帧的位置。 关键帧间隔为1表示每帧必须是关键帧 2表示至少每隔一帧必须是关键帧等此键可以与kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration一起设置，并且将强制执行这两个限制 - 每X帧或每Y秒需要一个关键帧，以先到者为准。
     */
    if ([self isSupportPropertyWithSession:session key:kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration]) {
        int value  = iFrameDuration;
        CFNumberRef ref     = CFNumberCreate(NULL, kCFNumberSInt32Type, &value);
        [self setSessionProperty:session key:kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration value:ref];
        CFRelease(ref);
    }
    
     NSLog(@"Video Encoder: The compression session max frame delay count = %d, expected frame rate = %d, average bitrate = %d, is support realtime encode = %d, I frame duration = %d",maxCount, fps, bitrate, isSupportRealtimeEncode,iFrameDuration);
    
    // Prepare to encode
    OSStatus status = VTCompressionSessionPrepareToEncodeFrames(session);
    [lock unlock];
    if(status != noErr) {
        if (session) {
            [self destroySession:session lock:lock];
        }
        NSLog(@"Video Encoder: create encoder failed, status: %d",(int)status);
        return NULL;
    }else {
        NSLog(@"Video Encoder: create encoder success");
        return session;
    }
    
    return session;
}
- (VTCompressionSessionRef)createCompressionSessionWithEncoderType:(EncoderType)encoderType width:(int)width height:(int)height callback:(VTCompressionOutputCallback)callback {
    
    CMVideoCodecType codecType;
    if (encoderType == EncoderTypeH264) {
        codecType = kCMVideoCodecType_H264;
    }else {
        codecType = kCMVideoCodecType_HEVC;
    }
    
    VTCompressionSessionRef session;
    OSStatus status = VTCompressionSessionCreate(NULL,
                                                 width,
                                                 height,
                                                 codecType,
                                                 NULL,
                                                 NULL,
                                                 NULL,
                                                 callback,
                                                 (__bridge void *)self,
                                                 &session);
    
    if (status != noErr) {
        NSLog(@"Video Encoder %s: Create session failed:%d",__func__,(int)status);
        return nil;
    }else {
        return session;
    }
}

//编码器是否支持参数设置
- (BOOL)isSupportPropertyWithSession:(VTCompressionSessionRef)session key:(CFStringRef)key {
    OSStatus status;
    static CFDictionaryRef supportedPropertyDictionary;
    if (!supportedPropertyDictionary) {
        status = VTSessionCopySupportedPropertyDictionary(session, &supportedPropertyDictionary);
        if (status != noErr) {
            return NO;
        }
    }
    
    BOOL isSupport = [NSNumber numberWithBool:CFDictionaryContainsKey(supportedPropertyDictionary, key)].intValue;
    return isSupport;
}
//设置编码器参数
- (OSStatus)setSessionProperty:(VTCompressionSessionRef)session key:(CFStringRef)key value:(CFTypeRef)value {
    if (value == nil || value == NULL || value == 0x0) {
        return noErr;
    }
    OSStatus status = VTSessionSetProperty(session, key, value);
    if (status != noErr) {
        NSLog(@"Set session of %s Failed, status = %d",CFStringGetCStringPtr(key, kCFStringEncodingUTF8),status);
    }
    return status;
}

- (void)startEncoderWithDataBuffer:(CMSampleBufferRef)sampleBuffer isNeedFreeBuffer:(BOOL)isFreeBuffer {
    [self startEncodeWithBuffer:sampleBuffer
                            session:sessionRef
                   isNeedFreeBuffer:isFreeBuffer
                             isDrop:NO
            needForceInsertKeyFrame:self.needForceInsertKeyFrame
                               lock:self.lock];
        
        if (self.needForceInsertKeyFrame) {
            self.needForceInsertKeyFrame = NO;
        }
}
-(void)startEncodeWithBuffer:(CMSampleBufferRef)sampleBuffer session:(VTCompressionSessionRef)session isNeedFreeBuffer:(BOOL)isNeedFreeBuffer isDrop:(BOOL)isDrop  needForceInsertKeyFrame:(BOOL)needForceInsertKeyFrame lock:(NSLock *)lock {
    [lock lock];
    
    if (session == NULL) {
        NSLog(@"session is NULL");
        [self handleEncodeFailedWithFreeBuffer:isNeedFreeBuffer sampleBuffer:sampleBuffer];
        return;
    }
    
    //the first frame must be iframe then create the reference timeStamp;
    static BOOL isKeyFrame = YES;
    if (isKeyFrame && g_capture_base_time == 0) {
        CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        // system absolutly time(s)
        g_capture_base_time = CMTimeGetSeconds(pts);
        isKeyFrame = NO;
        NSLog(@"start capture time = %u",g_capture_base_time);
    }
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CMTime pTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
     // Switch different source data will show mosaic because timestamp not sync.
    static int64_t lastPts = 0;
    int64_t currentPts = (int64_t)CMTimeGetSeconds(pTimeStamp)*1000;
    if (currentPts - lastPts < 0) {
        NSLog(@"Video Encoder: Switch different source data the timestamp < last timestamp, currentPts = %lld, lastPts = %lld, duration = %lld",currentPts, lastPts, currentPts - lastPts);
        [self handleEncodeFailedWithFreeBuffer:isNeedFreeBuffer sampleBuffer:sampleBuffer];
        return;
    }
    lastPts = currentPts;
    OSStatus status = noErr;
    NSDictionary *properties = @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame:@(needForceInsertKeyFrame)};
    status = VTCompressionSessionEncodeFrame(session,
                                             imageBuffer,
                                             pTimeStamp,
                                             kCMTimeInvalid,
                                             (__bridge CFDictionaryRef)properties,
                                             NULL,
                                             NULL);
    if(status != noErr) {
        NSLog(@"Video Encoder: encode frame failed");
        [self handleEncodeFailedWithFreeBuffer:isNeedFreeBuffer sampleBuffer:sampleBuffer];
    }
    [lock unlock];
    if (isNeedFreeBuffer) {
        if (sampleBuffer != NULL) {
            CFRelease(sampleBuffer);
            NSLog(@"release the sample buffer");
        }
    }
    
}
- (void)handleEncodeFailedWithFreeBuffer:(BOOL)isNeedFreeBuffer sampleBuffer:(CMSampleBufferRef)sampleBuffer {
    // if sample buffer are from system needn't to release, if sample buffer are from we create need to release.
    [self.lock unlock];
    if (isNeedFreeBuffer) {
        if (sampleBuffer != NULL) {
            CFRelease(sampleBuffer);
            NSLog(@"Video Encoder: release the sample buffer");
        }
    }
}
#pragma mark - Other
-(BOOL)needAdjustBitrateWithBitrate:(int)bitrate averageBitratesArray:(NSMutableArray *)averageBitratesArray {
    CMClockRef   hostClockRef = CMClockGetHostTimeClock();
    CMTime       hostTime     = CMClockGetTime(hostClockRef);
    static float lastTime     = 0;
    float now = CMTimeGetSeconds(hostTime);
    if(now - lastTime < 0.5) {
        [averageBitratesArray addObject:[NSNumber numberWithInt:bitrate]];
        return NO;
    }else {
        NSUInteger count = [averageBitratesArray count];
        if(count == 0) return YES;
        
        int sum = 0;
        for (NSNumber *num in averageBitratesArray) {
            sum += num.intValue;
        }
        
        int average  = sum/count;
        self.bitRate = average;
        
        [averageBitratesArray removeAllObjects];
        lastTime = now;
        return YES;
    }
}

-(void)doSetBitrateWithSession:(VTCompressionSessionRef)session isSupportRealtimeEncode:(BOOL)isSupportRealtimeEncode bitrate:(int)bitrate averageBitratesArray:(NSMutableArray *)averageBitratesArray {
    if(!isSupportRealtimeEncode) {
        return;
    }
    
    if(![self needAdjustBitrateWithBitrate:bitrate averageBitratesArray:averageBitratesArray]) {
        return;
    }
    
    int tmp         = bitrate;
    int bytesTmp    = tmp >> 3;
    int durationTmp = 1;
    
    CFNumberRef bitrateRef   = CFNumberCreate(NULL, kCFNumberSInt32Type, &tmp);
    CFNumberRef bytes        = CFNumberCreate(NULL, kCFNumberSInt32Type, &bytesTmp);
    CFNumberRef duration     = CFNumberCreate(NULL, kCFNumberSInt32Type, &durationTmp);
    
    
    if (session) {
        if ([self isSupportPropertyWithSession:session key:kVTCompressionPropertyKey_AverageBitRate]) {
            [self setSessionProperty:session key:kVTCompressionPropertyKey_AverageBitRate value:bitrateRef];
        }else {
            NSLog(@"Video Encoder: set average bitRate error");
        }
        
        NSLog(@"Video Encoder: set bitrate bytes = %d, _bitrate = %d",bytesTmp, bitrate);
        
        CFMutableArrayRef limit = CFArrayCreateMutable(NULL, 2, &kCFTypeArrayCallBacks);
        CFArrayAppendValue(limit, bytes);
        CFArrayAppendValue(limit, duration);
        if([self isSupportPropertyWithSession:session key:kVTCompressionPropertyKey_DataRateLimits]) {
            OSStatus ret = VTSessionSetProperty(session, kVTCompressionPropertyKey_DataRateLimits, limit);
            if(ret != noErr){
                NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:ret userInfo:nil];
                NSLog(@"Video Encoder: set DataRateLimits failed with %s",error.description.UTF8String);
            }
        }else {
            NSLog(@"Video Encoder: set data rate limits error");
        }
        CFRelease(limit);
    }
    
    CFRelease(bytes);
    CFRelease(duration);
}


#pragma mark - dealloc
- (void)destroySession:(VTCompressionSessionRef)session lock:(NSLock*)lock{
    NSLog(@"release session");
    [lock lock];
    if (session == NULL) {
        NSLog(@"%s current compression is NULL",__func__);
        [lock unlock];
    }else{
        VTCompressionSessionCompleteFrames(session, kCMTimeInvalid);
        VTCompressionSessionInvalidate(session);
        CFRelease(session);
        session = NULL;
    }
    
}
- (void)releaseEncoder {
    [self destroySession:sessionRef lock:self.lock];
}

- (void)forceInsertKeyFrame {
   self.needForceInsertKeyFrame = YES;
}

- (void)dealloc {
    [self releaseEncoder];
    NSLog(@"HDVideoEncoder dealloc -----");
}
@end

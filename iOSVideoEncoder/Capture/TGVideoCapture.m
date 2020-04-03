//
//  TGVideoCapture.m
//  TGVideoCapture
//
//  Created by TianGe on 2019/12/11.
//  Copyright © 2019 hedong. All rights reserved.
//

#import "TGVideoCapture.h"
#import <UIKit/UIKit.h>

@interface TGVideoCapture ()<AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate>

// 视频输入对象
@property(nonatomic, strong) AVCaptureDeviceInput *videoInput;
// 视频设备对象
@property(nonatomic, strong) AVCaptureDevice *videoDevice;
// 音频输入对象
@property (nonatomic, strong) AVCaptureDeviceInput *audioInput;
// 音频设备对象
@property (nonatomic, strong) AVCaptureDevice *audioDevice;

@property (nonatomic, strong) AVCaptureSession *session;

@property (nonatomic, strong) dispatch_queue_t bufferQueue;

@property (nonatomic, assign) BOOL isPaused;

@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

@end


@implementation TGVideoCapture

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.isPaused = YES;
        [self setupCaptureSession];
    }
    return self;
}

- (void)setupCaptureSession{
    [self requestCameraAuthorization:^(BOOL granted) {
        if (granted) {
            [self _setupCaptureSession];
        }else{
            [self throwError:VideoCaptureErrorAuthNotGranted];
        }
    }];
    
}
- (void)_setupCaptureSession {
    //初始化session
    self.session = [[AVCaptureSession alloc] init];
    [self.session beginConfiguration];
    if ([self.session canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        [_session setSessionPreset:AVCaptureSessionPreset1280x720];
        self.sessionPreset = AVCaptureSessionPreset1280x720;
    }else{
        [self.session setSessionPreset:AVCaptureSessionPresetHigh];
        self.sessionPreset = AVCaptureSessionPresetHigh;
    }
    [self.session commitConfiguration];
    
    self.videoDevice = [self cameraDeviceWithPosition:AVCaptureDevicePositionFront];
    self.devicePosition = AVCaptureDevicePositionFront;
    self.bufferQueue = dispatch_queue_create("TGBufferQueue", NULL);
    
    //videoInput
    NSError *error = nil;
    self.videoInput = [AVCaptureDeviceInput deviceInputWithDevice:self.videoDevice error:&error];
    if (!_videoInput) {
        [self.delegate videoCapture:self didFailedToStartWithError:VideoCaptureErrorFailedCreateInput];
        return;
    }
    
    //videoOutput
    int iCVPixelFormatType = self.isOutputWithYUV ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_32BGRA;
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.videoOutput setAlwaysDiscardsLateVideoFrames:YES];
    [_videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:iCVPixelFormatType] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    [_videoOutput setSampleBufferDelegate:self queue:_bufferQueue];
    
    [_session beginConfiguration];
    if ([_session canAddOutput:_videoOutput]) {
        [_session addOutput:_videoOutput];
    }else{
        [self throwError:VideoCaptureErrorFailedAddDataOutput];
        NSLog( @"Could not add video data output to the session" );
    }
    if ([_session canAddInput:_videoInput]) {
        [_session addInput:_videoInput];
    }else{
        [self throwError:VideoCaptureErrorFailedAddDeviceInput];
        NSLog( @"Could not add device input to the session" );
    }
    [_session commitConfiguration];
    
    //添加音频输入输出
    [self audioInputAndOutput];
    
    AVCaptureConnection *videoConnection =  [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if ([videoConnection isVideoOrientationSupported]) {
        [videoConnection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    }
    if ([videoConnection isVideoMirroringSupported]) {
        [videoConnection setVideoMirrored:YES];
    }
//    [self registerNotification];
//    [self startRunning];
    
    
}
- (void)registerNotification {
    __weak typeof(self) weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf startRunning];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf stopRunning];
    }];
    
}
// 设置音频I/O 对象
- (void)audioInputAndOutput {
    __weak typeof(self) weakSelf = self;
    [self requestAudioAuthorization:^(BOOL granted) {
        if (granted) {
            NSError *error;
            weakSelf.audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
            weakSelf.audioInput = [[AVCaptureDeviceInput alloc] initWithDevice:weakSelf.audioDevice error:&error];
            if (error) {
                NSLog(@"== 录音设备出错");
            }
            [weakSelf.session beginConfiguration];
            if ([weakSelf.session canAddInput:weakSelf.audioInput]) {
                [weakSelf.session addInput:weakSelf.audioInput];
            }
            weakSelf.audioOutput = [[AVCaptureAudioDataOutput alloc] init];
            if ([weakSelf.session canAddOutput:weakSelf.audioOutput]) {
                [weakSelf.session addOutput:weakSelf.audioOutput];
            }
            [self.session commitConfiguration];
            // 创建设置音频输出代理所需要的线程队列
            dispatch_queue_t audioQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
            [weakSelf.audioOutput setSampleBufferDelegate:self queue:audioQueue];
        }
    }];
}

#pragma mark - Private

-(AVCaptureDevice*)cameraDeviceWithPosition:(AVCaptureDevicePosition)position {
    AVCaptureDevice *deviceRet = nil;
    if (position != AVCaptureDevicePositionUnspecified) {
        NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        for (AVCaptureDevice *device in devices) {
            if ([device position] == position) {
                deviceRet = device;
            }
        }
    }
    return deviceRet;
}

- (void)requestCameraAuthorization:(void (^)(BOOL granted))handler {
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (authStatus == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            handler(granted);
        }];
    } else if (authStatus == AVAuthorizationStatusAuthorized) {
        handler(true);
    } else {
        handler(false);
    }
}
- (void)requestAudioAuthorization:(void (^)(BOOL granted))handler {
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (authStatus == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            handler(granted);
        }];
    } else if (authStatus == AVAuthorizationStatusAuthorized) {
        handler(true);
    } else {
        handler(false);
    }
}

- (void)throwError:(VideoCaptureError)error {
    if (_delegate && [_delegate respondsToSelector:@selector(videoCapture:didFailedToStartWithError:)]) {
        [_delegate videoCapture:self didFailedToStartWithError:error];
    }
}

#pragma mark - public

- (void)startRunning {
    if (!(_videoOutput || _audioOutput)) {
        return;
    }
    if (_session && ![_session isRunning]) {
        [_session startRunning];
        _isPaused = NO;
    }
}
- (void)stopRunning {
    if (_session && [_session isRunning]) {
        [_session stopRunning];
        _isPaused = YES;
    }
}

- (void)pause {
    _isPaused = true;
}

- (void)resume {
    _isPaused = false;
}

//切换摄像头
- (void)switchCamera {
    if (_session == nil) {
        return;
    }
    AVCaptureDevicePosition targetPosition = _devicePosition == AVCaptureDevicePositionFront ? AVCaptureDevicePositionBack: AVCaptureDevicePositionFront;
    AVCaptureDevice *targetDevice = [self cameraDeviceWithPosition:targetPosition];
    if (targetDevice == nil) {
        return;
    }
    NSError *error = nil;
    AVCaptureDeviceInput *deviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:targetDevice error:&error];
    if(!deviceInput || error) {
        [self throwError:VideoCaptureErrorFailedCreateInput];
        NSLog(@"Error creating capture device input: %@", error.localizedDescription);
        return;
    }
    [self pause];
    [_session beginConfiguration];
    [_session removeInput:_videoInput];
    if ([_session canAddInput:deviceInput]) {
        [_session addInput:deviceInput];
        _videoInput = deviceInput;
        _videoDevice = targetDevice;
        _devicePosition = targetPosition;
        AVCaptureConnection * videoConnection =  [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
        if ([videoConnection isVideoOrientationSupported]) {
            [videoConnection setVideoOrientation:AVCaptureVideoOrientationPortrait];
        }
        
        AVCaptureDevicePosition currentPosition=[[self.videoInput device] position];
        if (currentPosition == AVCaptureDevicePositionUnspecified || currentPosition == AVCaptureDevicePositionFront) {
            if ([videoConnection isVideoMirroringSupported]) {
                [videoConnection setVideoMirrored:YES];
            }
        }
        else {
            [videoConnection setVideoMirrored:NO];
        }
    }
    [_session commitConfiguration];
    [self resume];
}

#pragma mark - Util
- (CGSize)videoSize {
    if (_videoOutput.videoSettings) {
        CGFloat width = [[_videoOutput.videoSettings objectForKey:@"Width"] floatValue];
        CGFloat height = [[_videoOutput.videoSettings objectForKey:@"Height"] floatValue];
        return CGSizeMake(width, height);
    }
    return CGSizeZero;
}

#pragma mark - getter && setter
- (void)setSessionPreset:(NSString *)sessionPreset {
    if ([sessionPreset isEqualToString:_sessionPreset]) {
        return;
    }
    if (!_session) {
        return;
    }
    [self pause];
    [_session beginConfiguration];
    if ([_session canSetSessionPreset:sessionPreset]) {
        [_session setSessionPreset:sessionPreset];
        _sessionPreset = sessionPreset;
    }
    [self.session commitConfiguration];
    [self resume];
}
- (void)setIsOutputWithYUV:(BOOL)isOutputWithYUV {
    if (_isOutputWithYUV == isOutputWithYUV) {
        return;
    }
    _isOutputWithYUV = isOutputWithYUV;
    int iCVPixelFormatType = _isOutputWithYUV ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_32BGRA;
    AVCaptureVideoDataOutput *dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    [dataOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:iCVPixelFormatType] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    [dataOutput setSampleBufferDelegate:self queue:_bufferQueue];
    [self pause];
    [_session beginConfiguration];
    [_session removeOutput:_videoOutput];
    if ([_session canAddOutput:dataOutput]) {
        [_session addOutput:dataOutput];
        _videoOutput = dataOutput;
    }else{
        [self throwError:VideoCaptureErrorFailedAddDataOutput];
        NSLog(@"session add data output failed when change output buffer pixel format.");
    }
    [_session commitConfiguration];
    [self resume];
    /// make the buffer portrait
    AVCaptureConnection * videoConnection =  [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if ([videoConnection isVideoOrientationSupported]) {
        [videoConnection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    }
    if ([videoConnection isVideoMirroringSupported]) {
        [videoConnection setVideoMirrored:YES];
    }
}
#pragma mark - gettre
- (AVCaptureVideoPreviewLayer* )previewLayer{
    if (!_previewLayer){
        _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
        _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        _previewLayer.frame = [UIScreen mainScreen].bounds;
        _previewLayer.backgroundColor = [UIColor grayColor].CGColor;
    }
    return _previewLayer;
}

- (void)insertAVView:(UIView *)avview {
    self.previewLayer.frame = avview.bounds;
    [avview.layer addSublayer:self.previewLayer];
}
//开启关闭闪光灯
-(void)toggleFlash{
    self.videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [self.videoDevice lockForConfiguration:nil];
    //防止意外发生 前置直接返回
    if (self.devicePosition == AVCaptureDevicePositionFront) {
        return;
    }
    if ([self.videoDevice hasTorch] && [self.videoDevice hasFlash]){
        if (self.videoDevice.torchMode == AVCaptureTorchModeOff)
        {
            [self.videoDevice setTorchMode:AVCaptureTorchModeOn];
            [self.videoDevice setFlashMode:AVCaptureFlashModeOn];
            
        }
        else
        {
            [self.videoDevice setTorchMode:AVCaptureTorchModeOff];
            [self.videoDevice setFlashMode:AVCaptureFlashModeOff];
            
        }
        
    }
    [self.videoDevice unlockForConfiguration];
}


#pragma mark - AVCaptureAudioDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (!_isPaused) {
        if (_delegate && [_delegate respondsToSelector:@selector(videoCapture:didOutputSampleBuffer:)]) {
            [_delegate videoCapture:captureOutput didOutputSampleBuffer:sampleBuffer];
        }
    }
}
- (void)dealloc {
    if (!_session) {
        return;
    }
    _isPaused = YES;
    [_session beginConfiguration];
    [_session removeOutput:_videoOutput];
    [_session removeInput:_videoInput];
    [_session removeOutput:_audioOutput];
    [_session removeInput:_audioInput];
    [_session commitConfiguration];
    if ([_session isRunning]) {
        [_session stopRunning];
    }
    _session = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
}
- (void)setOrientation:(AVCaptureVideoOrientation)orientation {
    if (_session == nil || _videoOutput == nil) {
        return;
    }
    AVCaptureConnection *videoConnection = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (videoConnection) {
        if ([videoConnection isVideoOrientationSupported]) {
            [videoConnection setVideoOrientation:orientation];
        }
    }
}
- (void)setVideoMirrored:(BOOL)isMirrored {
    AVCaptureConnection *videoConnection =  [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (self.devicePosition == AVCaptureDevicePositionFront && [videoConnection isVideoMirroringSupported]) {
        [videoConnection setVideoMirrored:isMirrored];
    }

}
@end

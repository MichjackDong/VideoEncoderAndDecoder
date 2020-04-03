//
//  TGVideoCapture.h
//  TGVideoCapture
//
//  Created by TianGe on 2019/12/11.
//  Copyright © 2019 hedong. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

@class TGVideoCapture;

typedef NS_ENUM(NSInteger, VideoCaptureError) {
    VideoCaptureErrorAuthNotGranted = 0,
    VideoCaptureErrorFailedCreateInput = 1,
    VideoCaptureErrorFailedAddDataOutput = 2,
    VideoCaptureErrorFailedAddDeviceInput = 3,
};

@protocol TGVideoCaptureDelegate <NSObject>
- (void)videoCapture:(AVCaptureOutput *)captureType didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer;

- (void)videoCapture:(TGVideoCapture *)videoCapture didFailedToStartWithError:(VideoCaptureError)error;
@end

@interface TGVideoCapture : NSObject
// 音频输出对象
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioOutput;
// 视频输出对象
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
// default AVCaptureDevicePositionFront
@property (nonatomic, assign) AVCaptureDevicePosition devicePosition;

@property (nonatomic, weak) id <TGVideoCaptureDelegate> delegate;

@property (nonatomic, copy) AVCaptureSessionPreset sessionPreset;// default 1280x720
@property (nonatomic, assign) BOOL isOutputWithYUV; // default NO

//add avview
-(void)insertAVView:(UIView *)avview;

- (void)startRunning;

- (void)stopRunning;
//切换闪光灯
- (void)toggleFlash;

- (void)pause;
- (void)resume;

- (void)switchCamera;

- (CGSize)videoSize;

- (void)setOrientation:(AVCaptureVideoOrientation)orientation;
- (void)setVideoMirrored:(BOOL)isMirrored;
@end



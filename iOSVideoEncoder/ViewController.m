//
//  ViewController.m
//  iOSVideoEncoder
//
//  Created by TianGe on 2020/4/1.
//  Copyright © 2020 hedong. All rights reserved.
//

#import "ViewController.h"
#import "TGVideoCapture.h"
#import "HDVideoEncoder.h"
#import "HDVideoDecoder.h"
#import "TGOpenGLView.h"


@interface ViewController ()<TGVideoCaptureDelegate,HDVideoEncoderDelegate,VideoDecoderDelegate>
{
    
    FILE *videoFile;
    
}

@property (weak, nonatomic) IBOutlet UIView *originalVideoView;
@property (weak, nonatomic) IBOutlet UIView *encoderVideoView;

@property(nonatomic,strong) TGVideoCapture *capture;
@property(nonatomic,strong) HDVideoEncoder *videoEncoder;
@property(nonatomic,strong) HDVideoDecoder *videoDecoder;
@property(nonatomic,strong) TGOpenGLView *glView;




@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view addSubview:self.glView];
}
- (TGVideoCapture *)capture {
    if (!_capture) {
        _capture = [[TGVideoCapture alloc] init];
        _capture.delegate = self;
        _capture.isOutputWithYUV = YES;
        UIView *videoView = [[UIView alloc] initWithFrame:CGRectMake(20, 200, [UIScreen mainScreen].bounds.size.width-40, 200)];
        videoView.backgroundColor = [UIColor greenColor];
        [self.view addSubview:videoView];
        [_capture insertAVView:videoView];
    }
    return _capture;
}
- (TGOpenGLView *)glView {
    if (!_glView) {
        _glView = [[TGOpenGLView alloc] initWithFrame:CGRectMake(20, 480, [UIScreen mainScreen].bounds.size.width-40, 200)];
        _glView.backgroundColor = [UIColor redColor];
    }
    return _glView;
}
- (HDVideoEncoder *)videoEncoder {
    if (!_videoEncoder) {
        
        _videoEncoder = [[HDVideoEncoder alloc] initWithVideoSize:CGSizeMake(1280, 720) fps:30 bitRate:2048 isRealTimeEncode:NO encoderType:EncoderTypeH264];
        _videoEncoder.delegate = self;
        [_videoEncoder configureEncoderWithWidth:1280 height:720];
    }
    return _videoEncoder;
}
- (HDVideoDecoder *)videoDecoder {
    if (!_videoDecoder) {
        _videoDecoder = [[HDVideoDecoder alloc] init];
        _videoDecoder.delegate = self;
        _videoDecoder.showType = VideoDataType_Pixel;
    }
    return _videoDecoder;
}

- (void)videoCapture:(AVCaptureOutput *)captureType didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    //采集视频数据
    if (captureType == self.capture.videoOutput) {
        [self.videoEncoder startEncoderWithDataBuffer:sampleBuffer isNeedFreeBuffer:NO];
    }
}

- (void)videoCapture:(TGVideoCapture *)videoCapture didFailedToStartWithError:(VideoCaptureError)error {
    
    
}

- (void)receiveEncoderData:(EncoderDataRef)data {
    if (data->isKeyFrame) {
        [self.videoDecoder decodeH264VideoData:data->data videoSize:data->size];
    }else{
        [self.videoDecoder decodeH264VideoData:data->data videoSize:data->size];
    }
    
    
}
- (IBAction)startEncoder:(id)sender {
    
    [self .capture startRunning];
    
    
}
- (IBAction)stopEncoder:(id)sender {
    
    [self .capture stopRunning];
}


#pragma mark - 解码
- (void)decoder:(HDVideoDecoder *)decoder didDecodingFrame:(CVPixelBufferRef)imageBuffer {
    if (imageBuffer) {
        [self.glView displayPixelBuffer:imageBuffer];
    }
    
}
@end

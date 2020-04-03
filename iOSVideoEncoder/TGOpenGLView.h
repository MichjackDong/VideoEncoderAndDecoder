//
//  TGOpenGLView.h
//  videochatdemo
//
//  Created by sc on 2018/5/30.
//  Copyright © 2018年 sc. All rights reserved.
//

#ifndef TGOpenGLView_h
#define TGOpenGLView_h

#import <GLKit/GLKit.h>
//#import "WLLocalRenderView.h"

@interface TGOpenGLView : UIView

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer;

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer withLandmarks:(float *)landmarks count:(int)count;

@end

#endif /* TGOpenGLView_h */

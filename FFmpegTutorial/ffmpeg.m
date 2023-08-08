//
//  ffmpeg.m
//  FFmpegTutorial
//
//  Created by 201510003 on 2023/08/07.
//
// Reference:
// https://github.com/oozoofrog/ffmpeg-swift-tutorial/blob/master/tutorial/tutorial/FFmpeg.m

#import "ffmpeg.h"
#import <libavutil/error.h>

int AVERROR_CONVERT(int e) {
    return AVERROR(e);
}

bool IS_AVERROR_EOF(int e) {
    return e == AVERROR_EOF;
}

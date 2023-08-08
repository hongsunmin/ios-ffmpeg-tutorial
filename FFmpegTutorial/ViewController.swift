//
//  ViewController.swift
//  FFmpegTutorial
//
//  Created by 201510003 on 2023/08/04.
//
// Reference:
// http://soen.kr/lecture/library/FFmpeg/2-8.htm
// https://longxuan.ren/2019/07/03/ffmpeg-get-raw-h264
// https://blog.csdn.net/qq_42024397/article/details/115101448
// https://github.com/oozoofrog/ffmpeg-swift-tutorial/blob/master/tutorial/tutorial/tutorial.swift

import UIKit
import ffmpeg

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        runTutorial(forResource: "sample", ofType: "mp4")
    }
}



extension ViewController {
    func runTutorial(forResource: String, ofType: String) -> Int {
        var formatCtx: UnsafeMutablePointer<AVFormatContext>?
        guard let samplePath = Bundle.main.path(forResource: forResource, ofType: ofType) else {
            return -1
        }
        
        let url = samplePath.utf8CString.withUnsafeBufferPointer({ p in
            let url: UnsafePointer<CChar> = p.cast()
            return url
        })
        
        avformat_network_init()
        
        // Open video file
        guard avformat_open_input(&formatCtx, url, nil, nil) == 0,
              let formatCtx = formatCtx else {
            return -1 // Couldn't open file
        }
        
        defer {
            avformat_free_context(formatCtx)
        }
        
        // Retrieve stream information
        if avformat_find_stream_info(formatCtx, nil) < 0 {
            return -1 // Couldn't find stream information
        }
        
        // Dump information about file onto standard error
        av_dump_format(formatCtx, 0, url, 0)
        
        // Find the first video stream
        var videoSteram = -1
        let lengthOfStream = Int(formatCtx.pointee.nb_streams)
        for i in 0..<lengthOfStream {
            let stream = formatCtx.pointee.streams[i]
            let codecParameters = stream?.pointee.codecpar
            if codecParameters?.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoSteram = i
                break
            }
        }
        
        if videoSteram == -1 {
            return -1 // Didn't find a video stream
        }
        
        guard let codecParameters = formatCtx.pointee.streams[videoSteram]?.pointee.codecpar else {
            return -1
        }
        
        let codec = avcodec_find_decoder(codecParameters.pointee.codec_id)
        if codec == nil {
            print("Unsupported codec\n")
            return -1 // Codec not found
        }
        
        let codecCtx = avcodec_alloc_context3(codec)
        defer {
            avcodec_close(codecCtx)
        }
        
        // Open codec
        if avcodec_open2(codecCtx, codec, nil) < 0 {
            return -1 // Could not open codec
        }
        
        avcodec_parameters_to_context(codecCtx, codecParameters)
        
        // Allocate video frame
        var frame = av_frame_alloc()
        // Allocate an AVFrame structure
        var frameRGB = av_frame_alloc()
        if frameRGB == nil {
            return -1
        }
        
        let pixelFormat = AVPixelFormat(rawValue: codecParameters.pointee.format)
        let width = codecParameters.pointee.width
        let height = codecParameters.pointee.height
        // Determine required buffer size and allocate buffer
        let numBytes = av_image_get_buffer_size(AV_PIX_FMT_RGB24, width, height, 1)
        
        let buffer = av_malloc(Int(numBytes) * MemoryLayout<UInt8>.stride).assumingMemoryBound(to: UInt8.self)
        let dstData = withUnsafeMutablePointer(to: &frameRGB!.pointee.data.0) { $0 }
        let dstLinesize = withUnsafeMutablePointer(to: &frameRGB!.pointee.linesize.0) { $0 }
        // Assign appropriate parts of buffer to image planes in frameRGB
        // Note that frameRGB is an AVFrame, but AVFrame is a superest
        // of AVPicture
        av_image_fill_arrays(
            dstData, dstLinesize,
            buffer,
            AV_PIX_FMT_RGB24,
            width,
            height,
            1
        )
        
        var packet = AVPacket()
        defer {
            av_free(buffer)
            av_frame_free(&frameRGB)
            av_frame_free(&frame)
        }
        // initialize SWS context for software scaling
        let swsCtx = sws_getContext(
            width, height, pixelFormat,
            width, height, AV_PIX_FMT_RGB24, SWS_BILINEAR, nil, nil, nil
        )
        
        var bsfCtx: UnsafeMutablePointer<AVBSFContext>?
        let bsFilter = av_bsf_get_by_name("h264_mp4toannexb")
        if av_bsf_alloc(bsFilter, &bsfCtx) != 0 {
            return -1
        }
        
        if avcodec_parameters_from_context(bsfCtx?.pointee.par_in, codecCtx) < 0 {
            return -1
        }
        
        av_bsf_init(bsfCtx)
        defer {
            av_bsf_free(&bsfCtx)
        }
        
        var i = 0
        while av_read_frame(formatCtx, &packet) >= 0 {
            if packet.stream_index == videoSteram {
                // Decode video frame
                var result: Int32
                result = av_bsf_send_packet(bsfCtx, &packet)
                if result < 0 {
                    print("av_bsf_send_packet error occurs.")
                    printAVError(err: result)
                    break
                }
                
                while true {
                    result = av_bsf_receive_packet(bsfCtx, &packet)
                    if result == AVERROR_CONVERT(EAGAIN) {
                        break
                    } else if result == 0 {
                        let decodeResult = decode(codecCtx!, avpkt: &packet, frame: frame!) { frame in
                            // Did we get a video frame?
                            // Convert the image from its native format to RGB
                            let data = withUnsafeBytes(of: &frame.pointee.data.0) { $0 }
                            let srcSlice: UnsafePointer<UnsafePointer<UInt8>?> = data.cast()
                            let srcStride = withUnsafePointer(to: &frame.pointee.linesize.0) { $0 }
                            sws_scale(swsCtx, srcSlice.cast(), srcStride, 0, height, dstData, dstLinesize)
                            
                            // Save th frame to disk
                            i += 1
                            if i <= 5 {
                                saveFrame(frame: frameRGB!, width: width, height: height, iFrame: i)
                            }
                        }
                        
                        if decodeResult != 0 {
                            print("decode error occures")
                            printAVError(err: decodeResult)
                        }
                    } else {
                        print("av_bsf_receive_packet error occurs.")
                        printAVError(err: result)
                        break
                    }
                }
                
                av_packet_unref(&packet)
            }
        }
        return 0
    }
    
    func decode(_ codecCtx: UnsafeMutablePointer<AVCodecContext>,
                avpkt: UnsafePointer<AVPacket>,
                frame: UnsafeMutablePointer<AVFrame>,
                closure: (UnsafeMutablePointer<AVFrame>) -> Void) -> Int32
    {
        var result = avcodec_send_packet(codecCtx, avpkt)
        if result != 0 && result != AVERROR_CONVERT(EAGAIN) {
            return result
        }
        
        repeat {
            result = avcodec_receive_frame(codecCtx, frame)
            if result == AVERROR_CONVERT(EAGAIN) {
                break
            }
            
            closure(frame)
        } while result == 0
        return 0
    }
    
    func saveFrame(frame: UnsafeMutablePointer<AVFrame>, width: Int32, height: Int32, iFrame: Int) {
        let fileManager = FileManager.default
        let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directoryPath = documentPath.appendingPathComponent("images", isDirectory: true)
        let imagePath = directoryPath.appendingPathComponent("frame\(iFrame).ppm")
        do {
            try fileManager.createDirectory(at: directoryPath, withIntermediateDirectories: true)
            try Data().write(to: imagePath)
            
            let fileHandle = try FileHandle(forWritingTo: imagePath)
            defer {
                do {
                    if #available(iOS 13.0, *) {
                        try fileHandle.synchronize()
                    } else {
                        fileHandle.synchronizeFile()
                    }
                    
                    if #available(iOS 13.0, *) {
                        try fileHandle.close()
                    } else {
                        fileHandle.closeFile()
                    }
                } catch let e {
                    print(e.localizedDescription)
                }
            }
            
            guard let header = "P6\n\(width) \(height)\n255\n".data(using: .utf8) else {
                return
            }
            
            fileHandle.write(header)
            
            for y in 0..<height {
                let bytes = frame.pointee.data.0?.advanced(by: Int(y) * Int(frame.pointee.linesize.0))
                fileHandle.write(Data(bytes: UnsafePointer<UInt8>(bytes!), count: Int(frame.pointee.linesize.0)))
            }
            print("Done!!!")
        } catch let e {
            print(e.localizedDescription)
        }
    }
    
    func printAVError(err: Int32) {
        var errbuf = [CChar](repeating: 0, count: 1024)
        av_strerror(err, &errbuf, 1024)
        print("reason: \(errbuf)")
    }
}

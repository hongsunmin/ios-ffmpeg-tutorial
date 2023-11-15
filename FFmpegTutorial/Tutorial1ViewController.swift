//
//  Tutorial1ViewController.swift
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

struct FFmpegTutorialEnv {
    static var local = true
}

func printAVError(err: Int32) {
    var errbuf = [CChar](repeating: 0, count: 1024)
    av_strerror(err, &errbuf, 1024)
    print("reason: \(String(cString: errbuf))")
}

public func av_check<T: Equatable>(_ label: String,
                                   _ expression: @autoclosure () -> T,
                                   comparison: (T, T) -> Bool,
                                   comparisonValues: T) -> Bool
{
    let result = expression()
    guard comparison(result, comparisonValues) else {
        print("Comparing \(label) to \(comparisonValues) fails")
        printAVError(err: result as! Int32)
        return false
    }
    return true
}

class Tutorial1ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        if FFmpegTutorialEnv.local {
            runTutorial(forResource: "sample", ofType: "mp4")
        } else {
            // You can stream it at https://rtsp.stream
            runTutorial(forResource: "")
        }
    }
}



private extension Tutorial1ViewController {
    
    func runTutorial(forResource name: String, ofType: String) -> Int {
        guard let samplePath = Bundle.main.path(forResource: name, ofType: ofType) else {
            return -1
        }
        
        return runTutorial(forResource: samplePath)
    }
    
    func runTutorial(forResource name: String) -> Int {
        av_log_set_level(AV_LOG_DEBUG)
        
        var formatCtx: UnsafeMutablePointer<AVFormatContext>?
        let nameBytes = name.utf8CString
        let url = nameBytes.withUnsafeBufferPointer({ p in
            let url: UnsafePointer<CChar> = p.cast()
            return url
        })
        
        avformat_network_init()
        
        // Open video file
        guard av_check("avformat_open_input",
                       avformat_open_input(&formatCtx, url, nil, nil),
                       comparison: ==,
                       comparisonValues: 0) else {
            return -1 // Couldn't open file
        }
        
        defer {
            avformat_close_input(&formatCtx)
        }
        
        guard let formatCtx = formatCtx else {
            return -1 // Couldn't open file
        }
        
        // Retrieve stream information
        if av_check("avformat_find_stream_info",
                    avformat_find_stream_info(formatCtx, nil),
                    comparison: <,
                    comparisonValues: 0) {
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
        
        // Get a pointer to the codec parameters for the video stream
        guard let codecParameters = formatCtx.pointee.streams[videoSteram]?.pointee.codecpar else {
            return -1
        }
        
        // Find the decoder for the video stream
        let codec = avcodec_find_decoder(codecParameters.pointee.codec_id)
        if codec == nil {
            print("Unsupported codec\n")
            return -1 // Codec not found
        }
        
        // Copy context
        var codecCtx = avcodec_alloc_context3(codec)
        defer {
            avcodec_free_context(&codecCtx)
        }
        
        // Open codec
        if av_check("avcodec_open2",
                    avcodec_open2(codecCtx, codec, nil),
                    comparison: <,
                    comparisonValues: 0) {
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
        defer {
            sws_freeContext(swsCtx)
        }
        
        var bsfCtx: UnsafeMutablePointer<AVBSFContext>?
        if FFmpegTutorialEnv.local {
            let bsFilter = av_bsf_get_by_name("h264_mp4toannexb")
            if av_check("av_bsf_alloc",
                        av_bsf_alloc(bsFilter, &bsfCtx),
                        comparison: !=,
                        comparisonValues: 0) {
                return -1
            }
            
            if av_check("avcodec_parameters_from_context",
                        avcodec_parameters_from_context(bsfCtx?.pointee.par_in, codecCtx),
                        comparison: <,
                        comparisonValues: 0) {
                return -1
            }
            
            av_bsf_init(bsfCtx)
        }
        
        defer {
            av_bsf_free(&bsfCtx)
        }
        
        // Read frames and save first five frames to disk
        var i = 0
        let decoder = { (codecCtx, packet, frame) -> Int32 in
            self.decode(codecCtx!, avpkt: &packet, frame: frame!) { frame in
                // Did we get a video frame?
                // Convert the image from its native format to RGB
                let data = withUnsafeBytes(of: &frame.pointee.data.0) { $0 }
                let srcSlice: UnsafePointer<UnsafePointer<UInt8>?> = data.cast()
                let srcStride = withUnsafePointer(to: &frame.pointee.linesize.0) { $0 }
                sws_scale(swsCtx, srcSlice.cast(), srcStride, 0, height, dstData, dstLinesize)
                
                // Save th frame to disk
                i += 1
                if i <= 5 {
                    self.saveFrame(frame: frameRGB!, width: width, height: height, iFrame: i)
                }
            }
        }
        
        while av_read_frame(formatCtx, &packet) >= 0 {
            // Is this a packet from the video stream?
            if packet.stream_index == videoSteram {
                // Decode video frame
                if FFmpegTutorialEnv.local {
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
                            let decodeResult = decoder(codecCtx!, &packet, frame!)
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
                } else {
                    let decodeResult = decoder(codecCtx!, &packet, frame!)
                    if decodeResult != 0 {
                        print("decode error occures")
                        printAVError(err: decodeResult)
                    }
                }
                
                // Free the packet that was allocated by av_read_frame
                av_packet_unref(&packet)
            }
            
            // Free the packet that was allocated by av_read_frame < 0
            av_packet_unref(&packet)
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
        print("app document path: \(documentPath)")
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
}

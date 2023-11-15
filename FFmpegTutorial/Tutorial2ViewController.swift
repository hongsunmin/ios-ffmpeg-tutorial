//
//  Tutorial2ViewController.swift
//  FFmpegTutorial
//
//  Created by 201510003 on 10/6/23.
//

import UIKit

import GLKit
import ffmpeg

class Tutorial2ViewController: UIViewController {

    @IBOutlet
    weak var glkView: GLKView!
    
    private var context: EAGLContext?
    
    private var vertexArrayID: GLuint = 0
    private var textures = [GLuint](repeating: 0, count: 3)
    private var vertexbuffer: GLuint = 0
    private var uvbuffer: GLuint = 0
    private var indexbuffer: GLuint = 0
    private var programID: GLuint = 0
    
    private var textureIDs = [Int32](repeating: 0, count: 3)
    
    private let indices: [GLubyte] = [
        0, 1, 2,
        0, 2, 3
    ]
    
    private var effect = GLKBaseEffect()
    
    deinit {
        tearDownGL()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onOrientationChange(notification:)),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        setupOpenGL()
        
        DispatchQueue.global(qos: .background).async {
            if FFmpegTutorialEnv.local {
                self.runTutorial(forResource: "sample", ofType: "mp4")
            } else {
                // You can stream it at https://rtsp.stream
                self.runTutorial(forResource: "")
            }
        }
    }
    
    @objc
    func onOrientationChange(notification: Notification) {
        DispatchQueue.main.async {
            self.glkView.display()
        }
    }
}



private extension Tutorial2ViewController {
    
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
        
        let pixelFormat = AVPixelFormat(rawValue: codecParameters.pointee.format)
        let width = codecParameters.pointee.width
        let height = codecParameters.pointee.height
        
        var packet = AVPacket()
        defer {
            av_frame_free(&frame)
        }
        // initialize SWS context for software scaling
        let swsCtx = sws_getContext(
            width, height, pixelFormat,
            width, height, AV_PIX_FMT_YUV420P, SWS_BILINEAR, nil, nil, nil
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
        
        let decoder = { (codecCtx, packet, frame) -> Int32 in
            self.decode(codecCtx!, avpkt: &packet, frame: frame!) { frame in
                // Did we get a video frame?
                var pictData = [UnsafeMutablePointer<UInt8>?](repeating: nil, count: 8)
                var pictLinesize = [Int32](repeating: 0, count: 8)
                var _ = av_image_alloc(&pictData, &pictLinesize, width, height, AV_PIX_FMT_YUV420P, 1)
                // Convert the image into YUV format that OpenGL uses
                let data = withUnsafeBytes(of: &frame.pointee.data.0) { $0 }
                let srcSlice: UnsafePointer<UnsafePointer<UInt8>?> = data.cast()
                let srcStride = withUnsafePointer(to: &frame.pointee.linesize.0) { $0 }
                var _ = sws_scale(swsCtx, srcSlice.cast(), srcStride, 0, height, pictData, pictLinesize)
                
                // Save th frame to disk
                self.drawFrame(frame: pictData, linesize: pictLinesize, width: width, height: height)
                av_freep(&pictData)
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
        
        while av_read_frame(formatCtx, &packet) >= 0 {
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
    
    func drawFrame(frame: UnsafePointer<UnsafeMutablePointer<UInt8>?>, linesize: [Int32], width: Int32, height: Int32) {
        let imageSize = (GLsizei(width), GLsizei(height))
        let widths = [GLsizei](arrayLiteral: imageSize.0, imageSize.0 / 2, imageSize.0 / 2)
        let heights = [GLsizei](arrayLiteral: imageSize.1, imageSize.1 / 2, imageSize.1 / 2)
        let yuv = [frame.advanced(by: 0).pointee, frame.advanced(by: 1).pointee, frame.advanced(by: 2).pointee]
        for (i, p) in yuv.enumerated() {
            // "Bind" the newly created texture : all future texture functions will modify this texture
            glBindTexture(GLenum(GL_TEXTURE_2D), textures[i])
            
            // Give the image to OpenGL
            glTexImage2D(
                GLenum(GL_TEXTURE_2D),
                0,
                GL_LUMINANCE,
                GLsizei(widths[i]),
                GLsizei(heights[i]),
                0,
                GLenum(GL_LUMINANCE),
                GLenum(GL_UNSIGNED_BYTE),
                p
            )
            
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        }
        
        glkView.display()
    }
    
    func setupOpenGL() {
        context = EAGLContext(api: .openGLES3)
        EAGLContext.setCurrent(context)
        if let context = context {
            glkView.context = context
            glkView.delegate = self
            
            // Dark blue background
            glClearColor(0.0, 0.0, 0.4, 0.0)
            
            glEnable(GLenum(GL_DEPTH_TEST))
            glDepthFunc(GLenum(GL_LESS))
            
            glGenVertexArraysOES(1, &vertexArrayID)
            glBindVertexArrayOES(vertexArrayID)
            
            // Create and compile our GLSL program from the shaders
            programID = loadShaders(
                vertexFilePath: "tutorial.vert",
                fragmentFilePath: "tutorial.frag"
            )
            
            glGenTextures(3, &textures)
            
            // Get a handle for our "image" uniform
            textureIDs[0] = glGetUniformLocation(programID, "image_y")
            textureIDs[1] = glGetUniformLocation(programID, "image_u")
            textureIDs[2] = glGetUniformLocation(programID, "image_v")
            
            // Our vertices. Three consecutive floats give a 3D vertex; Three consecutive vertices give a triangle.
            let vertexBufferData: [GLfloat] = [
                -1.0,  1.0, 0.0, // upper-left
                -1.0, -1.0, 0.0, // lower-left
                 1.0, -1.0, 0.0, // lower-right
                 1.0,  1.0, 0.0  // upper-right
            ]
            
            // Two UV coordinatesfor each vertex. They were created with Blender.
            let uvBufferData: [GLfloat] = [
                0.0, 0.0, // upper-left
                0.0, 1.0, // lower-left
                1.0, 1.0, // lower-right
                1.0, 0.0  // upper-right
            ]
            
            glGenBuffers(1, &vertexbuffer)
            glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexbuffer)
            glBufferData(GLenum(GL_ARRAY_BUFFER),
                         vertexBufferData.size(),
                         vertexBufferData,
                         GLenum(GL_STATIC_DRAW))
            
            glGenBuffers(1, &uvbuffer)
            glBindBuffer(GLenum(GL_ARRAY_BUFFER), uvbuffer)
            glBufferData(GLenum(GL_ARRAY_BUFFER),
                         uvBufferData.size(),
                         uvBufferData,
                         GLenum(GL_STATIC_DRAW))
            
            glGenBuffers(1, &indexbuffer)
            glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), indexbuffer)
            glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER),
                         indices.size(),
                         indices,
                         GLenum(GL_STATIC_DRAW))
        }
    }
    
    func tearDownGL() {
        EAGLContext.setCurrent(context)
        
        glDeleteVertexArraysOES(1, &vertexArrayID)
        glDeleteBuffers(1, &vertexbuffer)
        glDeleteBuffers(1, &uvbuffer)
        glDeleteBuffers(1, &indexbuffer)
        glDeleteProgram(programID)
        glDeleteTextures(3, &textures)
        
        EAGLContext.setCurrent(nil)
        
        context = nil
    }
}



extension Tutorial2ViewController: GLKViewDelegate {
    
    func glkView(_ view: GLKView, drawIn rect: CGRect) {
        effect.prepareToDraw()
        // Clear the screen
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT) | GLbitfield(GL_DEPTH_BUFFER_BIT))
        
        // Use our shader
        glUseProgram(programID)
        
        for (i, texture) in textures.enumerated() {
            // Bind our texture in Texture Unit 0~2
            glActiveTexture(GLenum(GL_TEXTURE0 + Int32(i)))
            glBindTexture(GLenum(GL_TEXTURE_2D), texture)
            // Set our "image_y, image_u, image_v" sampler to use Texture Unit 0~2
            glUniform1i(textureIDs[i], GLint(i))
        }
        
        // 1rst attribute buffer : vertices
        let vertexAttribPosition = GLuint(GLKVertexAttrib.position.rawValue)
        glEnableVertexAttribArray(vertexAttribPosition)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexbuffer)
        glVertexAttribPointer(
            vertexAttribPosition,                      // attribute. No particular reason for 0, but must match the layout in the shader.
            3,                                         // size
            GLenum(GL_FLOAT),                          // type
            GLboolean(UInt8(GL_FALSE)),                // normalized?
            GLsizei(0),                                // stride
            nil                                        // array buffer offset
        )
        
        // 2nd attribute buffer : UVs
        let vertexAttribColor = GLuint(GLKVertexAttrib.texCoord0.rawValue)
        glEnableVertexAttribArray(vertexAttribColor)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), uvbuffer)
        glVertexAttribPointer(
            vertexAttribColor,                         // attribute. No particular reason for 0, but must match the layout in the shader.
            2,                                         // size : U+V => 2
            GLenum(GL_FLOAT),                          // type
            GLboolean(UInt8(GL_FALSE)),                // normalized?
            GLsizei(0),                                // stride
            nil                                        // array buffer offset
        )
        
        glDrawElements(GLenum(GL_TRIANGLES), GLsizei(indices.count), GLenum(GL_UNSIGNED_BYTE), nil)
        
        glDisableVertexAttribArray(vertexAttribPosition)
        glDisableVertexAttribArray(vertexAttribColor)
    }
}

//
//  FFmpegDecoder.swift
//  HLS_player
//
//  Created by Maksim Ponomarev on 10/9/24.
//
// https://github.com/tanersener/ffmpeg-kit-test

import Foundation
import FFmpegKit

class FFmpegDecoder {
	private var formatContext: UnsafeMutablePointer<AVFormatContext>?
	private var codecContext: UnsafeMutablePointer<AVCodecContext>?
	
	init() {
		print("FFmpegDecoder: Initializing")
		// Initialize FFmpeg components
		avformat_network_init()
		formatContext = avformat_alloc_context()
		print("FFmpegDecoder: FFmpeg components initialized")
		// ... (additional initialization as needed)
	}
	
	deinit {
		print("FFmpegDecoder: Deinitializing")
		// Clean up FFmpeg resources
		avformat_close_input(&formatContext)
		avcodec_free_context(&codecContext)
		avformat_network_deinit()
		print("FFmpegDecoder: FFmpeg resources cleaned up")
	}
	
	func decodeSegment(data: Data, completion: @escaping (DecodedFrame) -> Void) {
		print("FFmpegDecoder: Starting to decode segment of size \(data.count) bytes")
		
		// Create an AVIOContext from the segment data
		let ioBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
		data.copyBytes(to: ioBuffer, count: data.count)
		let ioContext = avio_alloc_context(ioBuffer, Int32(data.count), 0, nil, nil, nil, nil)
		
		print("FFmpegDecoder: Created AVIOContext")
		
		// Set the custom I/O context
		formatContext?.pointee.pb = ioContext
		
		// Open the input
		guard avformat_open_input(&formatContext, nil, nil, nil) >= 0 else {
			print("FFmpegDecoder: Failed to open input")
			return
		}
		
		print("FFmpegDecoder: Opened input successfully")
		
		// Find the best video stream
		guard avformat_find_stream_info(formatContext, nil) >= 0 else {
			print("FFmpegDecoder: Failed to find stream info")
			return
		}
		
		let videoStreamIndex = av_find_best_stream(formatContext, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
		guard videoStreamIndex >= 0 else {
			print("FFmpegDecoder: Failed to find video stream")
			return
		}
		
		print("FFmpegDecoder: Found video stream at index \(videoStreamIndex)")
		
		// Set up the codec context
		let videoStream = formatContext?.pointee.streams[Int(videoStreamIndex)]
		guard let codecParameters = videoStream?.pointee.codecpar else {
			print("FFmpegDecoder: Failed to get codec parameters")
			return
		}
		
		guard let codec = avcodec_find_decoder(codecParameters.pointee.codec_id) else {
			print("FFmpegDecoder: Failed to find decoder")
			return
		}
		
		print("FFmpegDecoder: Found decoder: \(String(cString: codec.pointee.name))")
		
		codecContext = avcodec_alloc_context3(codec)
		guard avcodec_parameters_to_context(codecContext, codecParameters) >= 0 else {
			print("FFmpegDecoder: Failed to set codec parameters")
			return
		}
		
		guard avcodec_open2(codecContext, codec, nil) >= 0 else {
			print("FFmpegDecoder: Failed to open codec")
			return
		}
		
		print("FFmpegDecoder: Opened codec successfully")
		
		// Decode frames
		var packet = av_packet_alloc()
		defer { av_packet_free(&packet) }
		
		var frame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
		defer { av_frame_free(&frame) }
		
		guard frame != nil else {
			print("FFmpegDecoder: Failed to create frame")
			return
		}
		
		var frameCount = 0
		while av_read_frame(formatContext, packet) >= 0 {
			if packet?.pointee.stream_index == videoStreamIndex {
				guard avcodec_send_packet(codecContext, packet) >= 0 else {
					print("FFmpegDecoder: Error sending packet for decoding")
					continue
				}
				
				while avcodec_receive_frame(codecContext, frame) >= 0 {
					if let frame = frame, let decodedFrame = DecodedFrame(frame: frame) {
						print("FFmpegDecoder: Decoded frame \(frameCount) - Size: \(decodedFrame.width)x\(decodedFrame.height), Format: \(decodedFrame.format), PTS: \(decodedFrame.pts)")
						completion(decodedFrame)
						frameCount += 1
					} else {
						print("FFmpegDecoder: Failed to create DecodedFrame from AVFrame")
					}
				}
			}
			av_packet_unref(packet)
		}
		
		print("FFmpegDecoder: Finished decoding segment. Total frames decoded: \(frameCount)")
	}
}

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
		avformat_network_init()
		print("FFmpegDecoder: FFmpeg components initialized")
	}
	
	deinit {
		print("FFmpegDecoder: Deinitializing")
		if formatContext != nil {
			var tempFormatContext: UnsafeMutablePointer<AVFormatContext>? = formatContext
			avformat_close_input(&tempFormatContext)
			formatContext = nil
		}
		if codecContext != nil {
			var tempCodecContext: UnsafeMutablePointer<AVCodecContext>? = codecContext
			avcodec_free_context(&tempCodecContext)
			codecContext = nil
		}
		avformat_network_deinit()
		print("FFmpegDecoder: FFmpeg resources cleaned up")
	}
	
	func decodeSegment(data: Data, completion: @escaping (Result<DecodedFrame, Error>) -> Void) {
		print("FFmpegDecoder: Starting to decode segment of size \(data.count) bytes")
		
		// Create an AVIOContext from the segment data
		let ioBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
		data.copyBytes(to: ioBuffer, count: data.count)
		let ioContext = avio_alloc_context(ioBuffer, Int32(data.count), 0, nil, nil, nil, nil)
		
		guard let ioContext = ioContext else {
			print("FFmpegDecoder: Failed to create AVIOContext")
			completion(.failure(FFmpegError.failedToCreateIOContext))
			return
		}
		
		print("FFmpegDecoder: Created AVIOContext")
		
		// Ensure formatContext is allocated
		var formatContextPointer: UnsafeMutablePointer<AVFormatContext>? = avformat_alloc_context()
		guard let formatContext = formatContextPointer else {
			print("FFmpegDecoder: Failed to allocate AVFormatContext")
			completion(.failure(FFmpegError.failedToAllocateFormatContext))
			return
		}
		self.formatContext = formatContext
		
		// Set the custom I/O context
		formatContext.pointee.pb = ioContext
		
		// Open the input
		let openResult = avformat_open_input(&formatContextPointer, nil, nil, nil)
		guard openResult >= 0 else {
			print("FFmpegDecoder: Failed to open input. Error code: \(openResult)")
			completion(.failure(FFmpegError.failedToOpenInput(code: openResult)))
			return
		}
		
		print("FFmpegDecoder: Opened input successfully")
		
		// Find stream info
		let findStreamInfoResult = avformat_find_stream_info(formatContext, nil)
		guard findStreamInfoResult >= 0 else {
			print("FFmpegDecoder: Failed to find stream info. Error code: \(findStreamInfoResult)")
			completion(.failure(FFmpegError.failedToFindStreamInfo(code: findStreamInfoResult)))
			return
		}
		
		print("FFmpegDecoder: Found stream info successfully")
		
		// Find the best video stream
		let videoStreamIndex = av_find_best_stream(formatContext, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
		guard videoStreamIndex >= 0 else {
			print("FFmpegDecoder: Failed to find video stream. Result: \(videoStreamIndex)")
			completion(.failure(FFmpegError.failedToFindVideoStream(code: videoStreamIndex)))
			return
		}
		
		print("FFmpegDecoder: Found video stream at index \(videoStreamIndex)")
		
		// Set up the codec context
		guard let videoStream = formatContext.pointee.streams[Int(videoStreamIndex)] else {
			print("FFmpegDecoder: Failed to get video stream")
			completion(.failure(FFmpegError.failedToGetVideoStream))
			return
		}
		
		guard let codecParameters = videoStream.pointee.codecpar else {
			print("FFmpegDecoder: Failed to get codec parameters")
			completion(.failure(FFmpegError.failedToGetCodecParameters))
			return
		}
		
		guard let codec = avcodec_find_decoder(codecParameters.pointee.codec_id) else {
			print("FFmpegDecoder: Failed to find decoder")
			completion(.failure(FFmpegError.failedToFindDecoder))
			return
		}
		
		print("FFmpegDecoder: Found decoder: \(String(cString: codec.pointee.name))")
		
		var codecContextPointer: UnsafeMutablePointer<AVCodecContext>? = avcodec_alloc_context3(codec)
		guard let codecContext = codecContextPointer else {
			print("FFmpegDecoder: Failed to allocate codec context")
			completion(.failure(FFmpegError.failedToAllocateCodecContext))
			return
		}
		self.codecContext = codecContext
		
		guard avcodec_parameters_to_context(codecContext, codecParameters) >= 0 else {
			print("FFmpegDecoder: Failed to set codec parameters")
			completion(.failure(FFmpegError.failedToSetCodecParameters))
			return
		}
		
		guard avcodec_open2(codecContext, codec, nil) >= 0 else {
			print("FFmpegDecoder: Failed to open codec")
			completion(.failure(FFmpegError.failedToOpenCodec))
			return
		}
		
		print("FFmpegDecoder: Opened codec successfully")
		
		// Decode frames
		decodeFrames(formatContext: formatContext, codecContext: codecContext, videoStreamIndex: videoStreamIndex, completion: completion)
	}
	
	private func decodeFrames(formatContext: UnsafeMutablePointer<AVFormatContext>, codecContext: UnsafeMutablePointer<AVCodecContext>, videoStreamIndex: Int32, completion: @escaping (Result<DecodedFrame, Error>) -> Void) {
		
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			autoreleasepool {
				guard let self = self else {
					completion(.failure(FFmpegError.decoderDeallocated))
					return
				}
				
				var packet = av_packet_alloc()
				defer { av_packet_free(&packet) }
				
				var frame = av_frame_alloc()
				defer { av_frame_free(&frame) }
				
				guard let frame = frame else {
					print("FFmpegDecoder: Failed to create frame")
					completion(.failure(FFmpegError.failedToCreateFrame))
					return
				}
				
				var frameCount = 0
				while av_read_frame(formatContext, packet) >= 0 {
					if packet?.pointee.stream_index == videoStreamIndex {
						let sendPacketResult = avcodec_send_packet(codecContext, packet)
						guard sendPacketResult >= 0 else {
							print("FFmpegDecoder: Error sending packet for decoding. Error code: \(sendPacketResult)")
							continue
						}
						
						while true {
							let receiveFrameResult = avcodec_receive_frame(codecContext, frame)
							if receiveFrameResult == -11 /* EAGAIN */ || receiveFrameResult == -541478725 /* AVERROR_EOF */ {
								break
							} else if receiveFrameResult < 0 {
								print("FFmpegDecoder: Error receiving frame. Error code: \(receiveFrameResult)")
								break
							}
							
							if let decodedFrame = DecodedFrame(frame: frame) {
								print("FFmpegDecoder: Decoded frame \(frameCount) - Size: \(decodedFrame.width)x\(decodedFrame.height), Format: \(decodedFrame.format), PTS: \(decodedFrame.pts)")
								completion(.success(decodedFrame))
								frameCount += 1
							} else {
								print("FFmpegDecoder: Failed to create DecodedFrame from AVFrame")
								completion(.failure(FFmpegError.failedToCreateDecodedFrame))
							}
							
							// Clean up resources
							av_frame_unref(frame)
							av_packet_unref(packet)
						}
					}
					//					av_packet_unref(packet)
				}
				
				print("FFmpegDecoder: Finished decoding segment. Total frames decoded: \(frameCount)")
				
				
			}
		}
		
		
		
		
	}
}

enum FFmpegError: Error {
	case failedToCreateIOContext
	case failedToAllocateFormatContext
	case failedToOpenInput(code: Int32)
	case failedToFindStreamInfo(code: Int32)
	case failedToFindVideoStream(code: Int32)
	case failedToGetVideoStream
	case failedToGetCodecParameters
	case failedToFindDecoder
	case failedToAllocateCodecContext
	case failedToSetCodecParameters
	case failedToOpenCodec
	case failedToCreateFrame
	case failedToCreateDecodedFrame
	
	case decoderDeallocated
//	case failedToCreateDecodedFrame
}

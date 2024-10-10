//
//  DecodedFrame.swift
//  HLS_player
//
//  Created by Maksim Ponomarev on 10/9/24.
//

import FFmpegKit
import Foundation

struct DecodedFrame {
	let width: Int
	let height: Int
	let data: [Data]  // Expecting at least 3 elements: [Y_data, UV_data, V_data]
	let linesize: [Int]
	let pts: Int64
	let format: AVPixelFormat
	
	init?(frame: UnsafeMutablePointer<AVFrame>) {
		print("DecodedFrame: Initializing from AVFrame")
		width = Int(frame.pointee.width)
		height = Int(frame.pointee.height)
		pts = frame.pointee.pts
		format = AVPixelFormat(rawValue: frame.pointee.format)
		
		print("DecodedFrame: Frame properties - Width: \(width), Height: \(height), PTS: \(pts), Format: \(format.description)")
		
		// Safely copy data and linesize
		var tempData: [Data] = []
		var tempLinesize: [Int] = []
		
		for i in 0..<8 {  // AV_NUM_DATA_POINTERS is 8
			if let dataPointer = frame.pointee.getData(at: i),
			   frame.pointee.getLineSize(at: i) > 0 {
				let lineSize = Int(frame.pointee.getLineSize(at: i))
				let size = lineSize * height
				tempData.append(Data(bytes: dataPointer, count: size))
				tempLinesize.append(lineSize)
				print("DecodedFrame: Copied plane \(i) - Size: \(size) bytes, Linesize: \(lineSize)")
			} else {
				break  // No more valid planes
			}
		}
		
		// Ensure we have at least one valid plane
		guard !tempData.isEmpty else {
			print("DecodedFrame: Initialization failed - No valid planes found")
			return nil
		}
		
		data = tempData
		linesize = tempLinesize
		
		print("DecodedFrame: Successfully initialized with \(data.count) planes")
	}
	
	func getBuffer(plane: Int = 0) -> Data? {
		guard plane < data.count else {
			print("DecodedFrame: Attempted to access invalid plane \(plane)")
			return nil
		}
		print("DecodedFrame: Returning buffer for plane \(plane) - Size: \(data[plane].count) bytes")
		return data[plane]
	}
	
	var description: String {
		let desc = "DecodedFrame: \(width)x\(height), format: \(format.description), planes: \(data.count), pts: \(pts)"
		print(desc)
		return desc
	}
}

extension AVPixelFormat: CustomStringConvertible {
	public var description: String {
		switch self.rawValue {
		case AV_PIX_FMT_NONE.rawValue:
			return "None"
		case AV_PIX_FMT_YUV420P.rawValue:
			return "YUV420P"
		case AV_PIX_FMT_YUVJ420P.rawValue:
			return "YUVJ420P"
		case AV_PIX_FMT_RGB24.rawValue:
			return "RGB24"
		case AV_PIX_FMT_BGR24.rawValue:
			return "BGR24"
		case AV_PIX_FMT_YUV422P.rawValue:
			return "YUV422P"
		case AV_PIX_FMT_YUV444P.rawValue:
			return "YUV444P"
		case AV_PIX_FMT_NV12.rawValue:
			return "NV12"
		case AV_PIX_FMT_NV21.rawValue:
			return "NV21"
		// Add more cases as needed
		default:
			return "Unknown (\(self.rawValue))"
		}
	}
}

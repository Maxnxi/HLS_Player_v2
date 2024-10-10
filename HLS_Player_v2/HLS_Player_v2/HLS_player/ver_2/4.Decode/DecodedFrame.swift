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
	let data: [Data]
	let linesize: [Int]
	let pts: Int64
	let format: AVPixelFormat
	
	init?(frame: UnsafeMutablePointer<AVFrame>) {
		width = Int(frame.pointee.width)
		height = Int(frame.pointee.height)
		pts = frame.pointee.pts
		format = AVPixelFormat(rawValue: frame.pointee.format)
		
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
			} else {
				break  // No more valid planes
			}
		}
		
		// Ensure we have at least one valid plane
		guard !tempData.isEmpty else {
			return nil
		}
		
		data = tempData
		linesize = tempLinesize
	}
	
	func getBuffer(plane: Int = 0) -> Data? {
		guard plane < data.count else { return nil }
		return data[plane]
	}
	
	var description: String {
		return "DecodedFrame: \(width)x\(height), format: \(format), planes: \(data.count), pts: \(pts)"
	}
}

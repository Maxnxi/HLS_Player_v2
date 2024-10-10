//
//  AVFrame_extension.swift
//  HLS_player
//
//  Created by Maksim Ponomarev on 10/9/24.
//

import FFmpegKit

extension AVFrame {
	func getData(at index: Int) -> UnsafeMutablePointer<UInt8>? {
		switch index {
		case 0: return data.0
		case 1: return data.1
		case 2: return data.2
		case 3: return data.3
		case 4: return data.4
		case 5: return data.5
		case 6: return data.6
		case 7: return data.7
		default: return nil
		}
	}
	
	func getLineSize(at index: Int) -> Int32 {
		switch index {
		case 0: return linesize.0
		case 1: return linesize.1
		case 2: return linesize.2
		case 3: return linesize.3
		case 4: return linesize.4
		case 5: return linesize.5
		case 6: return linesize.6
		case 7: return linesize.7
		default: return 0
		}
	}
}

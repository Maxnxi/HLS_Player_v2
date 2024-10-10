//
//  BufferManager.swift
//  HLS_player
//
//  Created by Maksim Ponomarev on 10/8/24.
//

import Foundation

class BufferManager {
	private var buffer: [BufferedSegment] = []
	private(set) var maxBufferDuration: TimeInterval
	private(set) var minBufferDuration: TimeInterval
	
	struct BufferedSegment {
		let index: Int
		let data: Data
		let duration: TimeInterval
	}
	
	init(maxBufferDuration: TimeInterval = 30.0, minBufferDuration: TimeInterval = 10.0) {
		self.maxBufferDuration = maxBufferDuration
		self.minBufferDuration = minBufferDuration
	}
	
	func updateBufferSizes(max: TimeInterval, min: TimeInterval) {
		self.maxBufferDuration = max
		self.minBufferDuration = min
		trimBuffer()
	}
	
	func addSegment(_ segment: BufferedSegment) {
		buffer.append(segment)
		trimBuffer()
	}
	
	func getNextSegment() -> BufferedSegment? {
		guard !buffer.isEmpty else { return nil }
		return buffer.removeFirst()
	}
	
	func peekNextSegment() -> BufferedSegment? {
		return buffer.first
	}
	
	func clearBuffer() {
		buffer.removeAll()
	}
	
	func bufferDuration() -> TimeInterval {
		return buffer.reduce(0) { $0 + $1.duration }
	}
	
	func isBufferHealthy() -> Bool {
		return bufferDuration() >= minBufferDuration
	}
	
	private func trimBuffer() {
		while bufferDuration() > maxBufferDuration, buffer.count > 1 {
			_ = buffer.removeLast()
		}
	}
	
	func segmentCount() -> Int {
		return buffer.count
	}
	
}

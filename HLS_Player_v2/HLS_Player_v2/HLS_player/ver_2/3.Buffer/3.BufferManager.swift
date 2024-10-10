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
		print("BufferManager: Initializing with maxBufferDuration: \(maxBufferDuration), minBufferDuration: \(minBufferDuration)")
		self.maxBufferDuration = maxBufferDuration
		self.minBufferDuration = minBufferDuration
	}
	
	func updateBufferSizes(max: TimeInterval, min: TimeInterval) {
		print("BufferManager: Updating buffer sizes - max: \(max), min: \(min)")
		self.maxBufferDuration = max
		self.minBufferDuration = min
		trimBuffer()
	}
	
	func addSegment(_ segment: BufferedSegment) {
		print("BufferManager: Adding segment - index: \(segment.index), duration: \(segment.duration), size: \(segment.data.count) bytes")
		buffer.append(segment)
		print("BufferManager: Buffer size after adding: \(buffer.count) segments")
		trimBuffer()
	}
	
	func getNextSegment() -> BufferedSegment? {
		guard !buffer.isEmpty else {
			print("BufferManager: Attempted to get next segment, but buffer is empty")
			return nil
		}
		let segment = buffer.removeFirst()
		print("BufferManager: Removed segment from buffer - index: \(segment.index), duration: \(segment.duration)")
		print("BufferManager: Buffer size after removal: \(buffer.count) segments")
		return segment
	}
	
	func peekNextSegment() -> BufferedSegment? {
		guard let segment = buffer.first else {
			print("BufferManager: Attempted to peek next segment, but buffer is empty")
			return nil
		}
		print("BufferManager: Peeked next segment - index: \(segment.index), duration: \(segment.duration)")
		return segment
	}
	
	func clearBuffer() {
		print("BufferManager: Clearing buffer")
		let count = buffer.count
		buffer.removeAll()
		print("BufferManager: Cleared \(count) segments from buffer")
	}
	
	func bufferDuration() -> TimeInterval {
		let duration = buffer.reduce(0) { $0 + $1.duration }
		print("BufferManager: Current buffer duration: \(duration) seconds")
		return duration
	}
	
	func isBufferHealthy() -> Bool {
		let healthy = bufferDuration() >= minBufferDuration
		print("BufferManager: Buffer health check - Is healthy: \(healthy)")
		return healthy
	}
	
	private func trimBuffer() {
		print("BufferManager: Trimming buffer")
		var trimmedCount = 0
		while bufferDuration() > maxBufferDuration, buffer.count > 1 {
			_ = buffer.removeLast()
			trimmedCount += 1
		}
		print("BufferManager: Trimmed \(trimmedCount) segments from buffer")
		print("BufferManager: Buffer size after trimming: \(buffer.count) segments")
		print("BufferManager: Buffer duration after trimming: \(bufferDuration()) seconds")
	}
	
	func segmentCount() -> Int {
		print("BufferManager: Current segment count: \(buffer.count)")
		return buffer.count
	}
}

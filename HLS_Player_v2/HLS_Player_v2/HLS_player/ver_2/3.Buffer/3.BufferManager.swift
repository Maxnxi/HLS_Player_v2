//
//  BufferManager.swift
//  HLS_player
//
//  Created by Maksim Ponomarev on 10/8/24.
//

import Foundation

enum Buffer_WarningType {
	case cachedTimeLowerMinBufferDuration
	case cachedTimeHigherMaxBufferDuration
	
	case noNextSegment_Downloaded
	
	case noSegment(Quality_Key, Int)
	
	case noDataForSegment(Quality_Key, Int)
	
	case nextSegmentWasPrepared_successfully(Quality_Key, Int)
	
	case isFinal
}

enum BufferError: Error {
	case managerDeallocated
	case noSegmentsAvailable
}

class Timeline_Cache {
	
}

struct Quality_Key: Hashable {
	var index: Int
	var quality: Int
}

struct BufferedSegment {
	let index: Int
	let data: Data
	let duration: TimeInterval
}

struct Segment_Info {
	let index_in_list: Int
	let data_address: String
	let duration: TimeInterval
}

struct Times_To_Buffer {
	var time_for_saving_past_segments: TimeInterval
	var time_for_saving_future_segments: TimeInterval
}

enum KeepCacheBufferOption {
	case keepAllSegments
	case keepSegmentsWithinTimeInterval(Times_To_Buffer)
}

enum SwitchingQuality {
	// switch quality immediately - allow to save elementsInQueue
	case switchImmediately(elementsInQueue: Int)
	case switchAfterUsingSegmentsInQueue
}


class BufferManager {
	
	var completion_warningCachedTimeLowerMinBufferDuration: ((Quality_Key) -> ())?
	var completion_needToDownloadMore: ((Quality_Key) -> ())?
	var completion_isFinal: (() -> ())?
	
	
	private let addLock = NSLock()
	
	private var master_playlist: M3U8Playlist?
	private var media_playlist: M3U8Playlist?
	
	/// from here we take the buffered segments to decode and to show
	/// FIFO
	private var current_timeline_cache: [BufferedSegment] = []
	private var current_timeline: [Double] = []
	private var current_qualityKey: Quality_Key?
	private var current_segment_index: Int = 0
	
	private var isFinal: Bool = false
	
	private var past_timeline_cache: [BufferedSegment] = []
	
	/// dictionary that contains info about every quality what is contained in master m3u8 playlist
	/// dictionary organized with ascending list of movie quality
	private var dictionary_Info_about_downloaded_segments: [Quality_Key: [Int: Segment_Info]] = [:]
	
	private var dictionary_downloaded_segments: [String: Data] = [:]
	
	private var switchQualityAfterSegmentsInQueue: Int? = nil
	private var nextQuality: Quality_Key?
	private var next_timeline_cache: [BufferedSegment] = []
	private var next_media_playlist: M3U8Playlist?
	
	// MARK: - Settings
	
	private var keep_cache_bufferOption: KeepCacheBufferOption = .keepAllSegments
	private(set) var switchingQualityOption: SwitchingQuality = .switchAfterUsingSegmentsInQueue
	
	//	private var buffer: [BufferedSegment] = []
	private(set) var isCustom: Bool = false
	private(set) var maxBufferDuration: TimeInterval = 30.0
	private(set) var minBufferDuration: TimeInterval = 10.0
	
	private(set) var allowToAddLowQualitySegments: Bool = false
	
	init() {
		print("BufferManager: Initialized")
	}
	
	func setupBufferManager(
		masterPlaylist: M3U8Playlist?,
		mediaPlaylist: M3U8Playlist,
		bufferOption: KeepCacheBufferOption = .keepAllSegments
	) {
		// clean current_qualityKey - because it is set when new segment is adding
		current_qualityKey = nil
		isFinal = false
		
		self.master_playlist = masterPlaylist
		self.media_playlist = mediaPlaylist
		self.keep_cache_bufferOption = bufferOption
		
		set_recommended_settings(streamType: masterPlaylist?.streamType)
		
		set_current_timeline(segments: mediaPlaylist.segments)
		
		
	}
	
	private func set_current_timeline(segments: [M3U8Segment]) {
		current_timeline = segments.map { $0.duration }
	}
	
	public func set_custom_buffer_options(
		maxBufferDuration: TimeInterval,
		minBufferDuration: TimeInterval
	) {
		self.isCustom = true
		self.maxBufferDuration = maxBufferDuration
		self.minBufferDuration = minBufferDuration
	}
	
	public func disable_custom_buffer_options_flag() {
		self.isCustom = false
	}
	
	public func set_recommended_settings(streamType: HLSStreamType?) {
		guard !isCustom else { return }
		switch streamType {
		case .live:
			self.maxBufferDuration = 30.0
			self.minBufferDuration = 10.0
		case .vod:
			self.maxBufferDuration = 60.0
			self.minBufferDuration = 30.0
		case .event:
			self.maxBufferDuration = 60.0
			self.minBufferDuration = 30.0
		default:
			self.maxBufferDuration = 60.0
			self.minBufferDuration = 30.0
		}
	}
	
	/// isLowQuality - for saving low quality segments
	/// for case when better quality segments may not be loaded
	public func addSegment(
		quality_Key: Quality_Key,
		segment: BufferedSegment,
		isLowQuality: Bool
	) {
		if !isLowQuality {
			checkIfNeedToSetQuality(quality_Key: quality_Key)
		}
		
		addLock.lock()
		defer { addLock.unlock() }
		
		print("BufferManager: Adding segment - index: \(segment.index), duration: \(segment.duration), size: \(segment.data.count) bytes")
		
		let index = segment.index
		let address = UUID().uuidString
		
		// save loaded Data
		dictionary_downloaded_segments[address] = segment.data
		
		let segment_info = Segment_Info(
			index_in_list: index,
			data_address: address,
			duration: segment.duration
		)
		
		if var quality_line = dictionary_Info_about_downloaded_segments[quality_Key] {
			quality_line[index] = segment_info
		} else {
			dictionary_Info_about_downloaded_segments[quality_Key] = [index: segment_info]
		}
		print("BufferManager: Added segment")
		
		// if quality_Key is same - that means - we do not need to switch quality
		if current_qualityKey != quality_Key {
			addSegmentSwitchQuality(quality_Key: quality_Key)
			print("BufferManager: Need to switch quality")
		}
	}
	
	private func checkIfNeedToSetQuality(quality_Key: Quality_Key) {
		if current_qualityKey == nil {
			current_qualityKey = quality_Key
		}
	}
	
	public func getNextSegment() -> BufferedSegment? {
		checkIfNeedToSwitchQuality()
		
		addLock.lock()
		defer { addLock.unlock() }
		
		if let nextSegment = current_timeline_cache.first {
			//			current_timeline_cache.removeFirst()
			
			checkIfNeedToWarnPlayer()
			update_timeline_cache()
			
			return nextSegment
		} else {
			// no element
			
			guard allowToAddLowQualitySegments else {
				return nil
			}
			
			guard let bufferedSegment = searchForSegment() else {
				return nil
			}
			update_timeline_cache()
			
			return bufferedSegment
		}
	}
	
	private func update_timeline_cache() {
		past_timeline_cache.append(current_timeline_cache.removeFirst())
		
		guard var media_playlist else {
			return
		}
		
		if switchQualityAfterSegmentsInQueue != nil {
			guard let next_media_playlist else {
				return
			}
			media_playlist = next_media_playlist
		}
		
		guard isMoreSegmentsInPlaylist(from: current_segment_index, mediaPlayList: media_playlist) else {
			markAsFinal()
			warnPlayer(typeOfWarning: .isFinal)
			return
		}
		
		increaseCurrentSegmentIndex()
		
		fetchNextSegment()
		
	}
	
	private func markAsFinal() {
		isFinal = true
	}
	
	private func fetchNextSegment() {
		guard var current_qualityKey else {
			return
		}
		
		guard var qualityLine = dictionary_Info_about_downloaded_segments[current_qualityKey] else {
			return
		}
		
		guard var playList = media_playlist else {
			return
		}
		
		if switchQualityAfterSegmentsInQueue != nil {
			guard let nextQuality else {
				return
			}
			current_qualityKey = nextQuality
			
			guard let newQualityLine = dictionary_Info_about_downloaded_segments[nextQuality] else {
				return
			}
			qualityLine = newQualityLine
			
			guard let next_media_playlist else {
				return
			}
			playList = next_media_playlist
		}
		
		let duration_of_current_timeline_cache_segments = current_timeline_cache.reduce(0) { $0 + $1.duration }
		let duration_of_next_timeline_cache_segments = next_timeline_cache.reduce(0) { $0 + $1.duration }
		let totalDuration = duration_of_current_timeline_cache_segments + duration_of_next_timeline_cache_segments
		
		var duration_to_be_in_current_timeline_cache = maxBufferDuration - totalDuration
		var segment_index = current_segment_index + current_timeline_cache.count + next_timeline_cache.count
		var isDownloadedSegment: Bool = true
		
		var conditions = [
			isMoreSegmentsInPlaylist(from: segment_index, mediaPlayList: playList),
			duration_to_be_in_current_timeline_cache > 0,
			isDownloadedSegment
		].contains(false)
		
		while !conditions {
			guard let nextSegment = qualityLine[segment_index] else {
				isDownloadedSegment = false
				warnPlayer(typeOfWarning: .noSegment(current_qualityKey, segment_index))
				return
			}
			
			guard let data = dictionary_downloaded_segments[nextSegment.data_address] else {
				isDownloadedSegment = false
				print("Error: no data for \(nextSegment.data_address)")
				warnPlayer(typeOfWarning: .noDataForSegment(current_qualityKey, segment_index))
				return
			}
			
			let bufferSegment = BufferedSegment(
				index: nextSegment.index_in_list,
				data: data,
				duration: nextSegment.duration
			)
			
			if switchQualityAfterSegmentsInQueue != nil {
				next_timeline_cache.append(bufferSegment)
			} else {
				current_timeline_cache.append(bufferSegment)
			}
			
			duration_to_be_in_current_timeline_cache -= bufferSegment.duration
			segment_index += 1
			
			print("segment_index: \(segment_index)")
			print("duration_to_be_in_current_timeline_cache: \(duration_to_be_in_current_timeline_cache)")
			warnPlayer(typeOfWarning: .nextSegmentWasPrepared_successfully(current_qualityKey, segment_index))
		}
	}
	
	
	private func isMoreSegmentsInPlaylist(from index: Int, mediaPlayList: M3U8Playlist) -> Bool {
		let segmentsCount = mediaPlayList.segments.count
		
		if index < segmentsCount - 1 {
			return true
		}
		return false
	}
	
	private func increaseCurrentSegmentIndex() {
		current_segment_index += 1
	}
	
	private func checkIfNeedToWarnPlayer() {
		let cachedTime = current_timeline_cache.reduce(0) { $0 + $1.duration }
		if cachedTime < minBufferDuration {
			guard let current_qualityKey else {
				return
			}
			completion_warningCachedTimeLowerMinBufferDuration?(current_qualityKey)
		}
	}
	
	private func warnPlayer(typeOfWarning: Buffer_WarningType) {
		switch typeOfWarning {
		case .cachedTimeLowerMinBufferDuration:
			
			break
		case .cachedTimeHigherMaxBufferDuration:
			
			break
			
		case .noNextSegment_Downloaded:
			if let current_qualityKey {
				completion_needToDownloadMore?(current_qualityKey)
			}
			
		case .isFinal:
			
			completion_isFinal?()
			
		case .noSegment(let qualityKey, let segmentIndex):
			
			print("noSegment \(qualityKey) \(segmentIndex)")
			
		case .noDataForSegment(let qualityKey, let segmentIndex):
			print("noDataForSegment \(qualityKey) \(segmentIndex)")
			
		case .nextSegmentWasPrepared_successfully(let qualityKey, let segmentIndex):
			print("nextSegmentWasPrepared_successfully \(qualityKey) \(segmentIndex)")
			
		}
	}
	
	private func searchForSegment() -> BufferedSegment? {
		let segmentDownloaded = dictionary_Info_about_downloaded_segments
			.filter ({ streamLine in
				streamLine.value.contains { segments in
					segments.key == current_segment_index
				}
			})
			.compactMap({ $0.value.values.first })
			.sorted(by: { $0.duration < $1.duration })
			.first
		
		guard let segmentDownloaded else {
			return nil
		}
		
		let data = dictionary_downloaded_segments[segmentDownloaded.data_address]
		guard let data else {
			return nil
		}
		
		let bufferSegment = BufferedSegment(
			index: segmentDownloaded.index_in_list,
			data: data,
			duration: segmentDownloaded.duration
		)
		
		return bufferSegment
	}
	
	
	private func checkIfNeedToSwitchQuality() {
		guard let switchQualityAfterSegmentsInQueue else {
			return
		}
		guard switchQualityAfterSegmentsInQueue == 0 else {
			self.switchQualityAfterSegmentsInQueue = switchQualityAfterSegmentsInQueue - 1
			return
		}
		
		addLock.lock()
		defer { addLock.unlock() }
		
		current_qualityKey = nextQuality
		current_timeline_cache = next_timeline_cache
		
		nextQuality = nil
		self.switchQualityAfterSegmentsInQueue = nil
		next_timeline_cache = []
	}
	
	private func addSegmentSwitchQuality(quality_Key: Quality_Key) {
		addLock.lock()
		defer { addLock.unlock() }
		
		switch switchingQualityOption {
		case .switchImmediately(let elementsInQueue):
			print("BufferManager: Switching quality immediately in elementsInQueue \(elementsInQueue)")
			switchQuality(afterElementsInQueue: elementsInQueue, toQuality: quality_Key)
			
		case .switchAfterUsingSegmentsInQueue:
			let elementsInQueue = current_timeline_cache.count
			print("BufferManager: Switching quality after using segments in queue: \(elementsInQueue)")
			switchQuality(afterElementsInQueue: elementsInQueue, toQuality: quality_Key)
		}
	}
	
	private func switchQuality(afterElementsInQueue: Int, toQuality: Quality_Key) {
		switchQualityAfterSegmentsInQueue = afterElementsInQueue
		nextQuality = toQuality
	}
	
	
	
//	func getNextSegment(completion: @escaping (Result<BufferedSegment, Error>) -> Void) {
//		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//			guard let self = self else {
//				completion(.failure(BufferError.managerDeallocated))
//				return
//			}
//			
//			self.lock.lock()
//			defer { self.lock.unlock() }
//			
//			if let segment = self.buffer.first {
//				self.buffer.removeFirst()
//				completion(.success(segment))
//			} else {
//				completion(.failure(BufferError.noSegmentsAvailable))
//			}
//		}
//	}
	
//	func peekNextSegment() -> BufferedSegment? {
//		guard let segment = buffer.first else {
//			print("BufferManager: Attempted to peek next segment, but buffer is empty")
//			return nil
//		}
//		print("BufferManager: Peeked next segment - index: \(segment.index), duration: \(segment.duration)")
//		return segment
//	}
	
//	func clearBuffer() {
//		print("BufferManager: Clearing buffer")
//		let count = buffer.count
//		buffer.removeAll()
//		print("BufferManager: Cleared \(count) segments from buffer")
//	}
//	
//	func bufferDuration() -> TimeInterval {
//		let duration = buffer.reduce(0) { $0 + $1.duration }
//		print("BufferManager: Current buffer duration: \(duration) seconds")
//		return duration
//	}
//	
//	func isBufferHealthy() -> Bool {
//		lock.lock()
//		defer { lock.unlock() }
//		
//		let healthy = bufferDuration() >= minBufferDuration
//		print("BufferManager: Buffer health check - Is healthy: \(healthy)")
//		return healthy
//	}
	
//	private func trimBuffer() {
//		print("BufferManager: Trimming buffer")
//		var trimmedCount = 0
//		while bufferDuration() > maxBufferDuration, buffer.count > 1 {
//			_ = buffer.removeFirst()
//			trimmedCount += 1
//		}
//		print("BufferManager: Trimmed \(trimmedCount) segments from buffer")
//		print("BufferManager: Buffer size after trimming: \(buffer.count) segments")
//		print("BufferManager: Buffer duration after trimming: \(bufferDuration()) seconds")
//	}
//	
//	func segmentCount() -> Int {
//		print("BufferManager: Current segment count: \(buffer.count)")
//		return buffer.count
//	}
}

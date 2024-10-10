//
//  HLS_Player_ver_2.swift
//  HLS_player
//
//  Created by Maksim Ponomarev on 10/7/24.
//

// WE should not use AVPlayer !!!

import Foundation


struct HLS_Movie {
	let playlistUrlString: String
	var m3u8Playlist: M3U8Playlist?
	var cached_fragments: [Int: Data] = [:]
}

enum HLS_player_movie_quality {
	case low
	case medium
	case high
	// optional
}

struct Cached_Quality {
	
}

enum Movie_Rate_speed: Double { // Changed to Double for more precise control
	case slow_x0_5 = 0.5
	case regular_x1 = 1.0
	case fast_x1_5 = 1.5
	case fast_x2 = 2.0
}

enum HLS_Player_state {
	case inited
	case newMovieLoading
	case m3u8PlaylistLoaded
	case start_loading_movie
	case movie_is_playing_preload_available
	case movie_is_playing_preload_not_available
	case bandWidthChanged
	case need_to_change_movie_quality
	case errorDownloadM3u8
	case errorDownloadSegments
}

//
//final class HLS_Player_ver_2_Impl {
//	private var playerState: HLS_Player_state = .inited
//	private let contentLoadingService: ContentLoadingService
//	private var masterPlaylist: M3U8Playlist?
//	private var currentMediaPlaylist: M3U8Playlist?
//	private var currentVariant: M3U8Variant?
//	private var currentSegmentIndex: Int = 0
//	
//	private var bufferManager: BufferManager
//	private var isPlaying: Bool = false
//	
//	private var is_preload_available: Bool = false
//	private var minimum_preload_duration: TimeInterval = 30 // 30 seconds
//	
//	private var playlistRefreshInterval: TimeInterval = 600 // 10 minutes in seconds
//	
//	private var currentStreamType: HLSStreamType = .vod
//	
//	// Buffering strategy constants
//	private let vodBufferMax: TimeInterval = 60.0 // 1 minute
//	private let vodBufferMin: TimeInterval = 30.0 // 30 seconds
//	private let liveBufferMax: TimeInterval = 30.0 // 30 seconds
//	private let liveBufferMin: TimeInterval = 10.0 // 10 seconds
//	private let eventBufferMax: TimeInterval = 45.0 // 45 seconds
//	private let eventBufferMin: TimeInterval = 20.0 // 20 seconds
//	
//	
//	private var ffmpegDecoder: FFmpegDecoder?
//	
//	init() {
//		self.contentLoadingService = ContentLoadingService()
//		self.bufferManager = BufferManager(maxBufferDuration: vodBufferMax, minBufferDuration: vodBufferMin)
//		self.ffmpegDecoder = FFmpegDecoder()
//	}
//	
//	func load_new_movie(_ urlString: String) {
//		playerState = .newMovieLoading
//		contentLoadingService.loadPlaylist(from: urlString) { [weak self] result in
//			guard let self = self else { return }
//			switch result {
//			case .success(let playlist):
//				if playlist.type == .master {
//					self.masterPlaylist = playlist
//					self.update_player_state(.m3u8PlaylistLoaded)
//					self.selectBestVariant()
//				} else {
//					self.currentMediaPlaylist = playlist
//					self.update_player_state(.m3u8PlaylistLoaded)
//					self.startPlayback()
//				}
//			case .failure(let error):
//				print("Error: \(error)")
//				self.update_player_state(.errorDownloadM3u8)
//			}
//		}
//	}
//	
//	private func selectBestVariant() {
//		guard let masterPlaylist = masterPlaylist else { return }
//		if let bestVariant = contentLoadingService.getBestVariant(for: masterPlaylist) {
//			let isNewVariant = currentVariant?.url != bestVariant.url
//			currentVariant = bestVariant
//			
//			loadMediaPlaylist(for: bestVariant) { [weak self] in
//				guard let self = self else { return }
//				if isNewVariant {
//					self.update_player_state(.need_to_change_movie_quality)
//					self.adjustPlaybackForNewVariant()
//				} else {
//					self.update_player_state(.start_loading_movie)
//					self.ensureBufferIsFull()
//				}
//			}
//		} else {
//			print("No suitable variant found")
//			update_player_state(.errorDownloadM3u8)
//		}
//	}
//	
//	private func adjustPlaybackForNewVariant() {
//		// Find the corresponding segment in the new playlist
//		if let currentTime = getCurrentPlaybackTime() {
//			currentSegmentIndex = findSegmentIndex(for: currentTime)
//		} else {
//			currentSegmentIndex = 0
//		}
//		
//		// Clear the buffer as the segments are from a different variant
//		bufferManager.clearBuffer()
//		
//		// Start loading new segments
//		loadNextSegments()
//	}
//	
//	private func getCurrentPlaybackTime() -> TimeInterval? {
//		// Implement this to get the current playback time
//		// This could be based on the segments already played plus the current segment's progress
//		return nil // Placeholder
//	}
//	
//	private func findSegmentIndex(for time: TimeInterval) -> Int {
//		guard let playlist = currentMediaPlaylist else { return 0 }
//		var accumulatedDuration: TimeInterval = 0
//		for (index, segment) in playlist.segments.enumerated() {
//			accumulatedDuration += segment.duration
//			if accumulatedDuration > time {
//				return index
//			}
//		}
//		return playlist.segments.count - 1
//	}
//	
//	private func startPlayback() {
//		//		guard let playlist = currentMediaPlaylist else { return }
//		contentLoadingService.setPreloadSettings(isAvailable: is_preload_available, minimumDuration: minimum_preload_duration)
//		currentSegmentIndex = 0
//		loadNextSegments()
//	}
//	
//	private func ensureBufferIsFull() {
//		if bufferManager.bufferDuration() < bufferManager.minBufferDuration {
//			loadNextSegments()
//		}
//	}
//	
//	private func loadNextSegments() {
//		guard let playlist = currentMediaPlaylist,
//			  currentSegmentIndex < playlist.segments.count else {
//			update_player_state(.movie_is_playing_preload_not_available)
//			return
//		}
//		
//		while bufferManager.bufferDuration() < bufferManager.maxBufferDuration &&
//				currentSegmentIndex < playlist.segments.count {
//			let segment = playlist.segments[currentSegmentIndex]
//			loadSegment(segment)
//		}
//	}
//	
//	private func loadSegment(_ segment: M3U8Segment) {
//		contentLoadingService.loadSegment(segment) { [weak self] result in
//			guard let self = self else { return }
//			switch result {
//			case .success(let data):
//				let bufferedSegment = BufferManager.BufferedSegment(
//					index: self.currentSegmentIndex,
//					data: data,
//					duration: segment.duration
//				)
//				self.bufferManager.addSegment(bufferedSegment)
//				self.currentSegmentIndex += 1
//				self.checkForQualitySwitch()
//				self.updatePlayerState()
//				if self.isPlaying && self.bufferManager.segmentCount() == 1 {
//					self.playNextSegment()
//				}
//				self.loadNextSegments()
//			case .failure(let error):
//				print("Error loading segment: \(error)")
//				self.update_player_state(.errorDownloadSegments)
//			}
//		}
//	}
//	
//	private func playNextSegment() {
//		guard isPlaying, let segment = bufferManager.getNextSegment() else { return }
//		
//		print("Playing segment: \(segment.index), duration: \(segment.duration)")
//		
//		// Transfer data to FFmpeg decoder
//		ffmpegDecoder?.decodeSegment(data: segment.data) { [weak self] decodedFrame in
//			guard let self = self else { return }
//			
//			// Here you would typically render the decoded frame
//			self.renderFrame(decodedFrame)
//			
//			// Schedule the next segment
//			DispatchQueue.main.asyncAfter(deadline: .now() + segment.duration) {
//				self.playNextSegment()
//			}
//		}
//	}
//	
//	private func renderFrame(_ frame: DecodedFrame) {
//			// Example of how you might use the frame data
//			if let yBuffer = frame.getBuffer(plane: 0),
//			   let uBuffer = frame.getBuffer(plane: 1),
//			   let vBuffer = frame.getBuffer(plane: 2) {
//				// Now you have separate Y, U, and V buffers
//				// You would typically combine these and convert to RGB
//				// before displaying or further processing
//				// This is just a placeholder for actual rendering logic
//				print("Received YUV frame: Y(\(yBuffer.count)), U(\(uBuffer.count)), V(\(vBuffer.count))")
//			}
//		}
//
//	
//	private func updatePlayerState() {
//		if bufferManager.isBufferHealthy() {
//			if is_preload_available {
//				update_player_state(.movie_is_playing_preload_available)
//			} else {
//				update_player_state(.movie_is_playing_preload_not_available)
//			}
//		} else {
//			update_player_state(.bandWidthChanged)
//		}
//	}
//	
//	private func checkForQualitySwitch() {
//		selectBestVariant()
//	}
//	
//	func update_player_state(_ state: HLS_Player_state) {
//		playerState = state
//		// Notify observers or update UI based on new state
//	}
//	
//	func play() {
//		checkAndReloadPlaylistIfNeeded { [weak self] in
//			guard let self = self else { return }
//			self.isPlaying = true
//			if self.bufferManager.segmentCount() > 0 {
//				self.playNextSegment()
//			} else {
//				self.loadNextSegments()
//			}
//			self.startPeriodicPlaylistRefresh()
//		}
//	}
//	
//	private func checkAndReloadPlaylistIfNeeded(completion: @escaping () -> Void) {
//		guard let currentPlaylist = currentMediaPlaylist,
//			  let currentVariant = currentVariant else {
//			completion()
//			return
//		}
//		
//		let currentTime = Int(Date().timeIntervalSince1970)
//		if currentTime - currentPlaylist.time_created > Int(playlistRefreshInterval) {
//			loadMediaPlaylist(for: currentVariant) {
//				completion()
//			}
//		} else {
//			completion()
//		}
//	}
//	
//	private func loadMediaPlaylist(for variant: M3U8Variant, completion: @escaping () -> Void) {
//		contentLoadingService.loadPlaylist(from: variant.url) { [weak self] result in
//			guard let self = self else { return }
//			switch result {
//			case .success(let mediaPlaylist):
//				self.currentMediaPlaylist = mediaPlaylist
//				self.currentStreamType = mediaPlaylist.streamType
//				self.adjustPlaybackStrategyForStreamType()
//				completion()
//			case .failure(let error):
//				print("Error loading media playlist: \(error)")
//				self.update_player_state(.errorDownloadM3u8)
//			}
//		}
//	}
//	
//	private func adjustPlaybackStrategyForStreamType() {
//		switch currentStreamType {
//		case .vod:
//			playlistRefreshInterval = .infinity // Don't refresh VOD playlists
//		case .live:
//			playlistRefreshInterval = 30 // Refresh live playlists more frequently
//		case .event:
//			playlistRefreshInterval = 60 // Refresh event playlists less frequently than live, but still regularly
//		}
//	}
//	
//	// For live streams, we might want to periodically check for new segments
//	private func startPeriodicPlaylistRefresh() {
//		guard currentStreamType == .live || currentStreamType == .event else { return }
//		
//		DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + playlistRefreshInterval) { [weak self] in
//			self?.checkAndReloadPlaylistIfNeeded {
//				self?.startPeriodicPlaylistRefresh()
//			}
//		}
//	}
//	
//	func pause() {
//		isPlaying = false
//	}
//	
//	func stop() {
//		isPlaying = false
//		bufferManager.clearBuffer()
//		contentLoadingService.clearCache()
//	}
//	
//	func seek(to time: TimeInterval) {
//		currentSegmentIndex = findSegmentIndex(for: time)
//		bufferManager.clearBuffer()
//		loadNextSegments()
//		if isPlaying {
//			playNextSegment()
//		}
//	}
//	
//	func change_rate_speed(rate_speed: Movie_Rate_speed) {
//		// Implement rate change functionality
//	}
//	
//	func set_preload_settings(available: Bool, minimum_duration: TimeInterval) {
//		is_preload_available = available
//		minimum_preload_duration = minimum_duration
//		contentLoadingService.setPreloadSettings(isAvailable: available, minimumDuration: minimum_duration)
//	}
//}

import Foundation

final class HLS_Player_ver_2_Impl {
	private var playerState: HLS_Player_state = .inited
	private let contentLoadingService: ContentLoadingService
	private var masterPlaylist: M3U8Playlist?
	private var currentMediaPlaylist: M3U8Playlist?
	private var currentVariant: M3U8Variant?
	private var currentSegmentIndex: Int = 0
	
	private var bufferManager: BufferManager
	private var isPlaying: Bool = false
	
	private var is_preload_available: Bool = false
	private var minimum_preload_duration: TimeInterval = 30 // 30 seconds
	
	private var playlistRefreshInterval: TimeInterval = 600 // 10 minutes in seconds
	
	private var currentStreamType: HLSStreamType = .vod
	
	// Buffering strategy constants
	private let vodBufferMax: TimeInterval = 60.0 // 1 minute
	private let vodBufferMin: TimeInterval = 30.0 // 30 seconds
	private let liveBufferMax: TimeInterval = 30.0 // 30 seconds
	private let liveBufferMin: TimeInterval = 10.0 // 10 seconds
	private let eventBufferMax: TimeInterval = 45.0 // 45 seconds
	private let eventBufferMin: TimeInterval = 20.0 // 20 seconds
	
	private var ffmpegDecoder: FFmpegDecoder?
	
	private var currentPlaybackTime: TimeInterval = 0
	private var playbackTimer: Timer?
	private var currentPlaybackRate: Double = 1.0
	
	init() {
		self.contentLoadingService = ContentLoadingService()
		self.bufferManager = BufferManager(maxBufferDuration: vodBufferMax, minBufferDuration: vodBufferMin)
		self.ffmpegDecoder = FFmpegDecoder()
	}
	
	func load_new_movie(_ urlString: String) {
		playerState = .newMovieLoading
		contentLoadingService.loadPlaylist(from: urlString) { [weak self] result in
			guard let self = self else { return }
			switch result {
			case .success(let playlist):
				if playlist.type == .master {
					self.masterPlaylist = playlist
					self.update_player_state(.m3u8PlaylistLoaded)
					self.selectBestVariant()
				} else {
					self.currentMediaPlaylist = playlist
					self.update_player_state(.m3u8PlaylistLoaded)
					self.startPlayback()
				}
			case .failure(let error):
				print("Error: \(error)")
				self.update_player_state(.errorDownloadM3u8)
			}
		}
	}
	
	private func selectBestVariant() {
		guard let masterPlaylist = masterPlaylist else { return }
		if let bestVariant = contentLoadingService.getBestVariant(for: masterPlaylist) {
			let isNewVariant = currentVariant?.url != bestVariant.url
			currentVariant = bestVariant
			
			loadMediaPlaylist(for: bestVariant) { [weak self] in
				guard let self = self else { return }
				if isNewVariant {
					self.update_player_state(.need_to_change_movie_quality)
					self.adjustPlaybackForNewVariant()
				} else {
					self.update_player_state(.start_loading_movie)
					self.ensureBufferIsFull()
				}
			}
		} else {
			print("No suitable variant found")
			update_player_state(.errorDownloadM3u8)
		}
	}
	
	private func adjustPlaybackForNewVariant() {
		currentSegmentIndex = findSegmentIndex(for: currentPlaybackTime)
		bufferManager.clearBuffer()
		loadNextSegments()
	}
	
	private func findSegmentIndex(for time: TimeInterval) -> Int {
		guard let playlist = currentMediaPlaylist else { return 0 }
		var accumulatedDuration: TimeInterval = 0
		for (index, segment) in playlist.segments.enumerated() {
			accumulatedDuration += segment.duration
			if accumulatedDuration > time {
				return index
			}
		}
		return playlist.segments.count - 1
	}
	
	private func startPlayback() {
		contentLoadingService.setPreloadSettings(isAvailable: is_preload_available, minimumDuration: minimum_preload_duration)
		currentSegmentIndex = 0
		loadNextSegments()
	}
	
	private func ensureBufferIsFull() {
		if bufferManager.bufferDuration() < bufferManager.minBufferDuration {
			loadNextSegments()
		}
	}
	
	private func loadNextSegments() {
		guard let playlist = currentMediaPlaylist,
			  currentSegmentIndex < playlist.segments.count else {
			update_player_state(.movie_is_playing_preload_not_available)
			return
		}
		
		while bufferManager.bufferDuration() < bufferManager.maxBufferDuration &&
				currentSegmentIndex < playlist.segments.count {
			let segment = playlist.segments[currentSegmentIndex]
			loadSegment(segment)
		}
	}
	
	private func loadSegment(_ segment: M3U8Segment) {
		contentLoadingService.loadSegment(segment) { [weak self] result in
			guard let self = self else { return }
			switch result {
			case .success(let data):
				let bufferedSegment = BufferManager.BufferedSegment(
					index: self.currentSegmentIndex,
					data: data,
					duration: segment.duration
				)
				self.bufferManager.addSegment(bufferedSegment)
				self.currentSegmentIndex += 1
				self.checkForQualitySwitch()
				self.updatePlayerState()
				if self.isPlaying && self.bufferManager.segmentCount() == 1 {
					self.playNextSegment()
				}
				self.loadNextSegments()
			case .failure(let error):
				print("Error loading segment: \(error)")
				self.update_player_state(.errorDownloadSegments)
			}
		}
	}
	
	private func playNextSegment() {
		guard isPlaying, let segment = bufferManager.getNextSegment() else { return }
		
		print("Playing segment: \(segment.index), duration: \(segment.duration)")
		
		ffmpegDecoder?.decodeSegment(data: segment.data) { [weak self] decodedFrame in
			guard let self = self else { return }
			self.renderFrame(decodedFrame)
			
			// Update playback time
			self.currentPlaybackTime += segment.duration / self.currentPlaybackRate
			
			// Schedule next segment playback
			DispatchQueue.main.asyncAfter(deadline: .now() + segment.duration / self.currentPlaybackRate) {
				self.playNextSegment()
			}
		}
	}
	
	private func renderFrame(_ frame: DecodedFrame) {
		// Here you would implement the logic to display the frame
		// This could involve passing the frame data to a video renderer
		// For now, we'll just print some information about the frame
		print("Rendered frame: Width: \(frame.width), Height: \(frame.height), PTS: \(frame.pts)")
	}
	
	private func updatePlayerState() {
		if bufferManager.isBufferHealthy() {
			if is_preload_available {
				update_player_state(.movie_is_playing_preload_available)
			} else {
				update_player_state(.movie_is_playing_preload_not_available)
			}
		} else {
			update_player_state(.bandWidthChanged)
		}
	}
	
	private func checkForQualitySwitch() {
		selectBestVariant()
	}
	
	func update_player_state(_ state: HLS_Player_state) {
		playerState = state
		// Notify observers or update UI based on new state
	}
	
	func play() {
		checkAndReloadPlaylistIfNeeded { [weak self] in
			guard let self = self else { return }
			self.isPlaying = true
			if self.bufferManager.segmentCount() > 0 {
				self.playNextSegment()
			} else {
				self.loadNextSegments()
			}
			self.startPeriodicPlaylistRefresh()
		}
	}
	
	private func checkAndReloadPlaylistIfNeeded(completion: @escaping () -> Void) {
		guard let currentPlaylist = currentMediaPlaylist,
			  let currentVariant = currentVariant else {
			completion()
			return
		}
		
		let currentTime = Int(Date().timeIntervalSince1970)
		if currentTime - currentPlaylist.time_created > Int(playlistRefreshInterval) {
			loadMediaPlaylist(for: currentVariant) {
				completion()
			}
		} else {
			completion()
		}
	}
	
	private func loadMediaPlaylist(for variant: M3U8Variant, completion: @escaping () -> Void) {
		contentLoadingService.loadPlaylist(from: variant.url) { [weak self] result in
			guard let self = self else { return }
			switch result {
			case .success(let mediaPlaylist):
				self.currentMediaPlaylist = mediaPlaylist
				self.currentStreamType = mediaPlaylist.streamType
				self.adjustPlaybackStrategyForStreamType()
				completion()
			case .failure(let error):
				print("Error loading media playlist: \(error)")
				self.update_player_state(.errorDownloadM3u8)
			}
		}
	}
	
	private func adjustPlaybackStrategyForStreamType() {
		switch currentStreamType {
		case .vod:
			playlistRefreshInterval = .infinity // Don't refresh VOD playlists
			bufferManager.updateBufferSizes(max: vodBufferMax, min: vodBufferMin)
		case .live:
			playlistRefreshInterval = 30 // Refresh live playlists more frequently
			bufferManager.updateBufferSizes(max: liveBufferMax, min: liveBufferMin)
		case .event:
			playlistRefreshInterval = 60 // Refresh event playlists less frequently than live, but still regularly
			bufferManager.updateBufferSizes(max: eventBufferMax, min: eventBufferMin)
		}
	}
	
	private func startPeriodicPlaylistRefresh() {
		guard currentStreamType == .live || currentStreamType == .event else { return }
		
		DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + playlistRefreshInterval) { [weak self] in
			self?.checkAndReloadPlaylistIfNeeded {
				self?.startPeriodicPlaylistRefresh()
			}
		}
	}
	
	func pause() {
		isPlaying = false
		playbackTimer?.invalidate()
	}
	
	func stop() {
		isPlaying = false
		playbackTimer?.invalidate()
		currentPlaybackTime = 0
		bufferManager.clearBuffer()
		contentLoadingService.clearCache()
	}
	
	func seek(to time: TimeInterval) {
		currentPlaybackTime = time
		currentSegmentIndex = findSegmentIndex(for: time)
		bufferManager.clearBuffer()
		loadNextSegments()
		if isPlaying {
			playNextSegment()
		}
	}
	
	func change_rate_speed(_ rate: Movie_Rate_speed) {
		currentPlaybackRate = rate.rawValue
		if isPlaying {
			// Restart playback with new rate
			pause()
			play()
		}
	}
	
	func set_preload_settings(available: Bool, minimum_duration: TimeInterval) {
		is_preload_available = available
		minimum_preload_duration = minimum_duration
		contentLoadingService.setPreloadSettings(isAvailable: available, minimumDuration: minimum_duration)
	}
}

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

import Foundation
import QuartzCore

final class HLS_Player_ver_2_Impl: ObservableObject {
	
	@Published private(set) var playerState: HLS_Player_state = .inited
	@Published private(set) var currentPlaybackTime: TimeInterval = 0
	@Published private(set) var isPlaying: Bool = false
	
//	private var playerState: HLS_Player_state = .inited
	private let contentLoadingService: ContentLoadingService
	private var masterPlaylist: M3U8Playlist?
	private var currentMediaPlaylist: M3U8Playlist?
	private var currentVariant: M3U8Variant?
	private var currentSegmentIndex: Int = 0
	private var isDecodingSegment = false
	
	private var bufferManager: BufferManager
//	private var isPlaying: Bool = false
	
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
	
//	private var currentPlaybackTime: TimeInterval = 0
	private var playbackTimer: Timer?
	private var currentPlaybackRate: Double = 1.0
	
	private var metalVideoView: MetalVideoView?
	
	private var frameQueue: DispatchQueue
	private var frameSemaphore: DispatchSemaphore
	private var decodedFrames: [DecodedFrame]
	private var lastPresentationTime: CFTimeInterval = 0
	private let targetFrameInterval: CFTimeInterval = 1.0 / 30.0 // 30 fps
	
	private var metalTextureCache: CVMetalTextureCache?
	
	
	init() {
		print("HLS_Player_ver_2_Impl: Initializing")
		self.contentLoadingService = ContentLoadingService()
		self.bufferManager = BufferManager(maxBufferDuration: vodBufferMax, minBufferDuration: vodBufferMin)
		self.ffmpegDecoder = FFmpegDecoder()
		
		self.frameQueue = DispatchQueue(label: "com.hlsplayer.frameQueue")
		self.frameSemaphore = DispatchSemaphore(value: 5) // Allow up to 5 frames in flight
		self.decodedFrames = []
		
		if let device = MTLCreateSystemDefaultDevice() {
			CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &metalTextureCache)
		}
		
		// Set up bandwidth measurement callback
		self.contentLoadingService.setBandwidthMeasurementCallback { [weak self] bandwidthKbps in
			self?.handleBandwidthMeasurement(bandwidthKbps)
		}

		print("HLS_Player_ver_2_Impl: Initialization complete")
	}
	
	private func updateOnMainThread(_ update: @escaping () -> Void) {
			if Thread.isMainThread {
				update()
			} else {
				DispatchQueue.main.async {
					update()
				}
			}
		}
	
	func load_new_movie(_ urlString: String) {
		print("HLS_Player_ver_2_Impl: Loading new movie from URL: \(urlString)")
		playerState = .newMovieLoading
		contentLoadingService.loadPlaylist(from: urlString) { [weak self] result in
			guard let self = self else { return }
			switch result {
			case .success(let playlist):
				print("HLS_Player_ver_2_Impl: Successfully loaded playlist")
				if playlist.type == .master {
					print("HLS_Player_ver_2_Impl: Master playlist detected")
					self.masterPlaylist = playlist
					self.update_player_state(.m3u8PlaylistLoaded)
					// Note: selectBestVariant is now called in handleBandwidthMeasurement
				} else {
					print("HLS_Player_ver_2_Impl: Media playlist detected")
					self.currentMediaPlaylist = playlist
					self.update_player_state(.m3u8PlaylistLoaded)
					self.startPlayback()
				}
			case .failure(let error):
				print("HLS_Player_ver_2_Impl: Error loading playlist: \(error)")
				self.update_player_state(.errorDownloadM3u8)
			}
		}
	}
	
	private func handleBandwidthMeasurement(_ bandwidthKbps: Int) {
		print("HLS_Player_ver_2_Impl: Received bandwidth measurement: \(bandwidthKbps) Kbps")
		// You might want to implement some logic here to smooth out bandwidth measurements
		// For now, we'll just use the measurement directly
		if let masterPlaylist = masterPlaylist {
			selectBestVariant(for: masterPlaylist, withBandwidth: bandwidthKbps)
		}
	}
	
	private func checkForQualitySwitch() {
		print("HLS_Player_ver_2_Impl: Checking for quality switch")
		guard let masterPlaylist = masterPlaylist else {
			print("HLS_Player_ver_2_Impl: No master playlist available for quality switch")
			return
		}
		
		// Use the most recent bandwidth measurement
		let currentBandwidth = contentLoadingService.getCurrentBandwidth()
		print("HLS_Player_ver_2_Impl: Current bandwidth for quality switch: \(currentBandwidth) Kbps")
		
		selectBestVariant(for: masterPlaylist, withBandwidth: currentBandwidth)
	}
	
	private func handleMasterPlaylist(_ playlist: M3U8Playlist) {
		print("HLS_Player_ver_2_Impl: Handling master playlist")
		self.masterPlaylist = playlist
		self.update_player_state(.m3u8PlaylistLoaded)
		
		// Select the best variant based on current bandwidth
		let currentBandwidth = contentLoadingService.getCurrentBandwidth()
		selectBestVariant(for: playlist, withBandwidth: currentBandwidth)
	}
	
	private func selectBestVariant(for masterPlaylist: M3U8Playlist, withBandwidth bandwidth: Int) {
		print("HLS_Player_ver_2_Impl: Selecting best variant for bandwidth: \(bandwidth) Kbps")
		if let bestVariant = contentLoadingService.getBestVariant(for: masterPlaylist, withBandwidth: bandwidth) {
			currentVariant = bestVariant
			loadMediaPlaylist(for: bestVariant)
		} else {
			print("HLS_Player_ver_2_Impl: No suitable variant found for bandwidth: \(bandwidth) Kbps")
			update_player_state(.errorDownloadM3u8)
		}
	}
	
	private func loadMediaPlaylist(for variant: M3U8Variant) {
		print("HLS_Player_ver_2_Impl: Loading media playlist for variant: \(variant.url)")
		contentLoadingService.loadPlaylist(from: variant.url) { [weak self] result in
			guard let self = self else { return }
			switch result {
			case .success(let mediaPlaylist):
				self.currentMediaPlaylist = mediaPlaylist
				self.currentStreamType = mediaPlaylist.streamType
				self.adjustPlaybackStrategyForStreamType()
				self.update_player_state(.m3u8PlaylistLoaded)
				if self.playerState == .start_loading_movie {
					self.startPlayback()
				}
			case .failure(let error):
				print("HLS_Player_ver_2_Impl: Error loading media playlist: \(error)")
				self.update_player_state(.errorDownloadM3u8)
			}
		}
	}
	
	//	private func selectBestVariant(for masterPlaylist: M3U8Playlist, withBandwidth bandwidth: Int) {
	//		print("HLS_Player_ver_2_Impl: Selecting best variant for bandwidth: \(bandwidth) Kbps")
	//		if let bestVariant = contentLoadingService.getBestVariant(for: masterPlaylist, withBandwidth: bandwidth) {
	//			let isNewVariant = currentVariant?.url != bestVariant.url
	//			if isNewVariant {
	//				print("HLS_Player_ver_2_Impl: New variant selected. Current: \(currentVariant?.bandwidth ?? 0) Kbps, New: \(bestVariant.bandwidth) Kbps")
	//				currentVariant = bestVariant
	//				update_player_state(.need_to_change_movie_quality)
	//				loadMediaPlaylist(for: bestVariant) { [weak self] in
	//					self?.adjustPlaybackForNewVariant()
	//				}
	//			} else {
	//				print("HLS_Player_ver_2_Impl: Keeping current variant: \(bestVariant.bandwidth) Kbps")
	//			}
	//		} else {
	//			print("HLS_Player_ver_2_Impl: No suitable variant found for bandwidth: \(bandwidth) Kbps")
	//		}
	//	}
	
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
		print("HLS_Player_ver_2_Impl: Starting playback")
		DispatchQueue.main.async { [weak self] in
			self?.isPlaying = true
		}
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
			print("HLS_Player_ver_2_Impl: No more segments to load")
			update_player_state(.movie_is_playing_preload_not_available)
			return
		}
		
		print("HLS_Player_ver_2_Impl: Loading next segments. Current index: \(currentSegmentIndex)")
		while bufferManager.bufferDuration() < bufferManager.maxBufferDuration &&
				currentSegmentIndex < playlist.segments.count {
			let segment = playlist.segments[currentSegmentIndex]
			loadSegment(segment)
			currentSegmentIndex += 1
		}
	}
	
	private func loadSegment(_ segment: M3U8Segment) {
		print("HLS_Player_ver_2_Impl: Loading segment at index \(currentSegmentIndex)")
		contentLoadingService.loadSegment(segment) { [weak self] result in
			guard let self = self else { return }
			switch result {
			case .success(let data):
				print("HLS_Player_ver_2_Impl: Successfully loaded segment. Size: \(data.count) bytes")
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
					print("HLS_Player_ver_2_Impl: First segment loaded, starting playback")
					self.playNextSegment()
				}
				self.loadNextSegments()
			case .failure(let error):
				print("HLS_Player_ver_2_Impl: Error loading segment: \(error)")
				self.update_player_state(.errorDownloadSegments)
			}
		}
	}
	
	private func playNextSegment() {
			guard isPlaying else {
				print("HLS_Player_ver_2_Impl: Playback stopped")
				return
			}
			
			bufferManager.getNextSegment { [weak self] result in
				guard let self = self else { return }
				switch result {
				case .success(let segment):
					print("HLS_Player_ver_2_Impl: Decoding segment \(segment.index)")
					self.decodeAndRenderSegment(segment)
				case .failure(let error):
					print("HLS_Player_ver_2_Impl: Failed to get next segment: \(error)")
					self.stop()
				}
			}
		}
	
	private func decodeAndRenderSegment(_ segment: BufferManager.BufferedSegment) {
		guard let ffmpegDecoder else {
			print("HLS_Player_ver_2_Impl: ffmpegDecoder failed to be initialized")
			return
		}
		ffmpegDecoder.decodeSegment(data: segment.data) { [weak self] result in
			guard let self = self else { return }
			self.updateOnMainThread {
				switch result {
				case .success(let decodedFrame):
					print("HLS_Player_ver_2_Impl: Successfully decoded frame for segment \(segment.index)")
					self.metalVideoView?.updateWithFrame(decodedFrame)
					print("HLS_Player_ver_2_Impl: Frame sent to MetalVideoView for rendering")
					self.currentPlaybackTime += segment.duration / self.currentPlaybackRate
					self.objectWillChange.send()
				
					// Schedule next segment playback
					DispatchQueue.main.asyncAfter(deadline: .now() + segment.duration / self.currentPlaybackRate) {
						self.playNextSegment()
					}

				case .failure(let error):
					print("HLS_Player_ver_2_Impl: Error decoding frame: \(error)")
					self.stop()
				}
			}
		}
	}
	
	private func renderFrame(_ frame: DecodedFrame) {
		print("HLS_Player_ver_2_Impl: Rendering frame: Width: \(frame.width), Height: \(frame.height), PTS: \(frame.pts)")
		
		DispatchQueue.main.async {
			self.metalVideoView?.updateWithFrame(frame)
		}
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
	
	
	func update_player_state(_ state: HLS_Player_state) {
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.playerState = state
			// Notify observers or update UI based on new state
		}
	}
	
	func play() {
		   updateOnMainThread {
			   print("HLS_Player_ver_2_Impl: Play requested")
			   if self.bufferManager.segmentCount() > 0 {
				   self.isPlaying = true
				   self.playNextSegment()
			   } else {
				   print("HLS_Player_ver_2_Impl: No segments available, waiting for preload")
				   self.update_player_state(.start_loading_movie)
			   }
		   }
	   
//		if let currentMediaPlaylist = currentMediaPlaylist {
//			if currentMediaPlaylist.segments.isEmpty {
//				print("HLS_Player_ver_2_Impl: Current media playlist has no segments")
//				update_player_state(.errorDownloadM3u8)
//				return
//			}
//			update_player_state(.start_loading_movie)
//			startPlayback()
//		} else if let masterPlaylist = masterPlaylist {
//			print("HLS_Player_ver_2_Impl: No media playlist loaded, selecting from master playlist")
//			selectBestVariant(for: masterPlaylist, withBandwidth: contentLoadingService.getCurrentBandwidth())
//		} else {
//			print("HLS_Player_ver_2_Impl: No playlists available")
//			update_player_state(.errorDownloadM3u8)
//		}
	}
	
	private func checkAndReloadPlaylistIfNeeded(completion: @escaping () -> Void) {
		guard let currentPlaylist = currentMediaPlaylist,
			  let currentVariant = currentVariant else {
			completion()
			return
		}
		
		let currentTime = Date().timeIntervalSince1970
		let playlistAge = currentTime - TimeInterval(currentPlaylist.time_created)
		
		if playlistRefreshInterval.isFinite && playlistAge > playlistRefreshInterval {
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
		
		guard playlistRefreshInterval.isFinite else {
			print("HLS_Player_ver_2_Impl: Playlist refresh interval is infinite, skipping periodic refresh")
			return
		}
		
		DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + playlistRefreshInterval) { [weak self] in
			self?.checkAndReloadPlaylistIfNeeded {
				self?.startPeriodicPlaylistRefresh()
			}
		}
	}
	
	func pause() {
		updateOnMainThread {
			print("HLS_Player_ver_2_Impl: Pause requested")
			self.isPlaying = false
			self.playbackTimer?.invalidate()
		}
	}
	
	func stop() {
		updateOnMainThread {
			print("HLS_Player_ver_2_Impl: Stop requested")
			self.isPlaying = false
			self.playbackTimer?.invalidate()
			self.currentPlaybackTime = 0
			self.bufferManager.clearBuffer()
			self.contentLoadingService.clearCache()
		}
	}
	
	func seek(to time: TimeInterval) {
		updateOnMainThread {
			self.currentPlaybackTime = time
			self.currentSegmentIndex = self.findSegmentIndex(for: time)
			self.bufferManager.clearBuffer()
			self.loadNextSegments()
			if self.isPlaying {
				self.playNextSegment()
			}
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

extension HLS_Player_ver_2_Impl {
	func getPlayerLayer() -> CALayer {
		print("HLS_Player_ver_2_Impl: Getting player layer")
		if let existingLayer = metalVideoView?.layer.sublayers?.first as? HLSPlayerLayer {
			print("HLS_Player_ver_2_Impl: Returning existing player layer")
			return existingLayer
		}
		
		print("HLS_Player_ver_2_Impl: Creating new MetalVideoView")
		let metal_view = MetalVideoView(frame: .zero, device: MTLCreateSystemDefaultDevice())
		self.metalVideoView = metal_view
		
		guard let playerLayer = metal_view.layer.sublayers?.first as? HLSPlayerLayer else {
			fatalError("Failed to create HLSPlayerLayer")
		}
		
		print("HLS_Player_ver_2_Impl: Returning new player layer")
		return playerLayer
	}
}


extension HLS_Player_ver_2_Impl {
	///Call this cleanup method when you're done with the player, such as in your view's onDisappear or when
	func cleanup() {
		stop()
		ffmpegDecoder = nil
		metalVideoView = nil
		bufferManager.clearBuffer()
		contentLoadingService.clearCache()
	}
}


extension HLS_Player_ver_2_Impl {
	private func preloadSegments() {
		guard let playlist = currentMediaPlaylist else { return }
		var segmentsLoaded = 0
		for (index, segment) in playlist.segments.prefix(6).enumerated() {
			contentLoadingService.loadSegment(segment) { [weak self] result in
				guard let self = self else { return }
				self.updateOnMainThread {
					switch result {
					case .success(let data):
						let bufferedSegment = BufferManager.BufferedSegment(
							index: index,
							data: data,
							duration: segment.duration
						)
						self.bufferManager.addSegment(bufferedSegment)
						segmentsLoaded += 1
						if segmentsLoaded == 6 {
							print("HLS_Player_ver_2_Impl: Preloaded 6 segments, starting playback")
							self.play()
						}
					case .failure(let error):
						print("HLS_Player_ver_2_Impl: Error preloading segment: \(error)")
					}
				}
			}
		}
	}
}


extension HLS_Player_ver_2_Impl {
	
}

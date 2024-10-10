

import Foundation

enum HLSError: Error {
	case invalidURL
	case networkError(Error)
	case parsingError
	case noDataReceived
}

class ContentLoadingService {
	private var urlSession: URLSession
	private let parser_M3U8_Service: Parser_M3U8_Service
	private var currentBandwidth: Int = 0
	private var cachedSegments: [String: Data] = [:]
	private var isPreloadAvailable: Bool = false
	private var minimumPreloadDuration: TimeInterval = 30 // 30 seconds
	
	private var bandwidthMeasurementCallback: ((Int) -> Void)?

	init() {
			print("ContentLoadingService: Initializing")
			self.urlSession = URLSession.shared
			self.parser_M3U8_Service = Parser_M3U8_Service()
			print("ContentLoadingService: Initialization complete")
		}

	func loadPlaylist(from urlString: String, completion: @escaping (Result<M3U8Playlist, HLSError>) -> Void) {
			print("ContentLoadingService: Loading playlist from URL: \(urlString)")
			guard let url = URL(string: urlString) else {
				print("ContentLoadingService: Invalid URL")
				completion(.failure(.invalidURL))
				return
			}
			
			let startTime = Date()
			
			let task = urlSession.dataTask(with: url) { [weak self] data, response, error in
				let endTime = Date()
				let duration = endTime.timeIntervalSince(startTime)
				
				if let error = error {
					print("ContentLoadingService: Network error: \(error.localizedDescription)")
					completion(.failure(.networkError(error)))
					return
				}
				
				guard let data = data else {
					print("ContentLoadingService: No data received")
					completion(.failure(.noDataReceived))
					return
				}
				
				// Calculate bandwidth
				let bandwidthBps = Int(Double(data.count * 8) / duration)
				let bandwidthKbps = bandwidthBps / 1000
				print("ContentLoadingService: Estimated bandwidth: \(bandwidthKbps) Kbps")
				
				// Update the current bandwidth
				self?.currentBandwidth = bandwidthKbps
				
				// Notify about the bandwidth measurement
				self?.bandwidthMeasurementCallback?(bandwidthKbps)
				
				print("ContentLoadingService: Received \(data.count) bytes of playlist data")
				self?.parseM3U8(data: data, completion: completion)
			}
			
			task.resume()
			print("ContentLoadingService: Playlist request started")
		}
	
	func setBandwidthMeasurementCallback(_ callback: @escaping (Int) -> Void) {
			bandwidthMeasurementCallback = callback
		}
	
	private func parseM3U8(data: Data, completion: @escaping (Result<M3U8Playlist, HLSError>) -> Void) {
			print("ContentLoadingService: Parsing M3U8 data")
			guard let content = String(data: data, encoding: .utf8) else {
				print("ContentLoadingService: Failed to decode M3U8 data as UTF-8")
				completion(.failure(.parsingError))
				return
			}
			
			if let playlist = parser_M3U8_Service.parseM3U8(content: content) {
				print("ContentLoadingService: Successfully parsed M3U8 playlist")
				print("ContentLoadingService: Playlist type: \(playlist.type == .master ? "Master" : "Media")")
				print("ContentLoadingService: Number of variants: \(playlist.variants.count)")
				print("ContentLoadingService: Number of segments: \(playlist.segments.count)")
				completion(.success(playlist))
			} else {
				print("ContentLoadingService: Failed to parse M3U8 playlist")
				completion(.failure(.parsingError))
			}
		}

	func loadSegment(_ segment: M3U8Segment, completion: @escaping (Result<Data, HLSError>) -> Void) {
			print("ContentLoadingService: Loading segment from URL: \(segment.url)")
			guard let url = URL(string: segment.url) else {
				print("ContentLoadingService: Invalid segment URL")
				completion(.failure(.invalidURL))
				return
			}

			if let cachedData = cachedSegments[segment.url] {
				print("ContentLoadingService: Returning cached segment data (\(cachedData.count) bytes)")
				completion(.success(cachedData))
				return
			}

			let startTime = Date()
			let task = urlSession.dataTask(with: url) { [weak self] data, response, error in
				guard let self = self else { return }

				if let error = error {
					print("ContentLoadingService: Network error loading segment: \(error.localizedDescription)")
					completion(.failure(.networkError(error)))
					return
				}

				guard let data = data else {
					print("ContentLoadingService: No data received for segment")
					completion(.failure(.noDataReceived))
					return
				}

				let endTime = Date()
				let downloadDuration = endTime.timeIntervalSince(startTime)
				let downloadSpeed = Double(data.count) / downloadDuration / 1024 // Speed in KB/s

				self.updateBandwidth(Int(downloadSpeed * 8)) // Convert to Kbps
				print("ContentLoadingService: Segment downloaded. Size: \(data.count) bytes, Duration: \(downloadDuration) seconds, Speed: \(downloadSpeed) KB/s")

				if self.isPreloadAvailable {
					self.cachedSegments[segment.url] = data
					print("ContentLoadingService: Segment cached")
				}

				completion(.success(data))
			}

			task.resume()
			print("ContentLoadingService: Segment download request started")
		}

	private func updateBandwidth(_ newBandwidth: Int) {
			// Simple moving average
			currentBandwidth = (currentBandwidth + newBandwidth) / 2
			print("ContentLoadingService: Updated bandwidth: \(currentBandwidth) Kbps")
		}

	func getCurrentBandwidth() -> Int {
		return currentBandwidth
	}
	
	func getBestVariant(for playlist: M3U8Playlist, withBandwidth bandwidth: Int) -> M3U8Variant? {
		print("ContentLoadingService: Selecting best variant for bandwidth: \(bandwidth) Kbps")
		
		let suitableVariants = playlist.variants.filter { $0.bandwidth <= bandwidth }
		let bestVariant = suitableVariants.max(by: { $0.bandwidth < $1.bandwidth })
		
		if let variant = bestVariant {
			print("ContentLoadingService: Selected variant with bandwidth: \(variant.bandwidth) Kbps")
		} else {
			print("ContentLoadingService: No suitable variant found, selecting lowest bandwidth")
			return playlist.variants.min(by: { $0.bandwidth < $1.bandwidth })
		}
		
		return bestVariant
	}

	func setPreloadSettings(isAvailable: Bool, minimumDuration: TimeInterval) {
			isPreloadAvailable = isAvailable
			minimumPreloadDuration = minimumDuration
			print("ContentLoadingService: Preload settings updated - Available: \(isAvailable), Minimum Duration: \(minimumDuration) seconds")
		}

	func preloadSegments(for playlist: M3U8Playlist) {
			guard isPreloadAvailable else {
				print("ContentLoadingService: Preloading is not available")
				return
			}

			print("ContentLoadingService: Starting segment preload")
			var totalDuration: TimeInterval = 0
			for segment in playlist.segments {
				guard totalDuration < minimumPreloadDuration else {
					print("ContentLoadingService: Preload complete. Total duration: \(totalDuration) seconds")
					break
				}
				loadSegment(segment) { _ in }
				totalDuration += segment.duration
				print("ContentLoadingService: Preloaded segment. Cumulative duration: \(totalDuration) seconds")
			}
		}

	func clearCache() {
			let count = cachedSegments.count
			cachedSegments.removeAll()
			print("ContentLoadingService: Cache cleared. Removed \(count) cached segments")
		}
}

// Usage example:
// let service = ContentLoadingService()
// service.loadPlaylist(from: "https://example.com/playlist.m3u8") { result in
//     switch result {
//     case .success(let playlist):
//         print("Loaded playlist: \(playlist)")
//         if let firstSegment = playlist.segments.first {
//             service.loadSegment(firstSegment) { result in
//                 switch result {
//                 case .success(let data):
//                     print("Loaded segment data: \(data.count) bytes")
//                     // Here you would typically pass this data to your video player
//                 case .failure(let error):
//                     print("Error loading segment: \(error)")
//                 }
//             }
//         }
//     case .failure(let error):
//         print("Error loading playlist: \(error)")
//     }
// }

// Usage example:
// let service = ContentLoadingService()
// https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.mp4/.m3u8
//
// service.loadPlaylist(from: "https://example.com/playlist.m3u8") { result in
//     switch result {
//     case .success(let segments):
//         print("Loaded \(segments.count) segments")
//         if let firstSegment = segments.first {
//             service.loadSegment(firstSegment) { result in
//                 switch result {
//                 case .success(let data):
//                     print("Loaded segment data: \(data.count) bytes")
//                     // Here you would typically pass this data to your video player
//                 case .failure(let error):
//                     print("Error loading segment: \(error)")
//                 }
//             }
//         }
//     case .failure(let error):
//         print("Error loading playlist: \(error)")
//     }
// }

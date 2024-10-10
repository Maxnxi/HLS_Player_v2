

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

	init() {
		self.urlSession = URLSession.shared
		self.parser_M3U8_Service = Parser_M3U8_Service()
	}

	func loadPlaylist(from urlString: String, completion: @escaping (Result<M3U8Playlist, HLSError>) -> Void) {
		guard let url = URL(string: urlString) else {
			completion(.failure(.invalidURL))
			return
		}
		
		let task = urlSession.dataTask(with: url) { [weak self] data, response, error in
			if let error = error {
				completion(.failure(.networkError(error)))
				return
			}
			
			guard let data = data else {
				completion(.failure(.noDataReceived))
				return
			}
			
			self?.parseM3U8(data: data, completion: completion)
		}
		
		task.resume()
	}
	
	private func parseM3U8(data: Data, completion: @escaping (Result<M3U8Playlist, HLSError>) -> Void) {
		guard let content = String(data: data, encoding: .utf8) else {
			completion(.failure(.parsingError))
			return
		}
		
		if let playlist = parser_M3U8_Service.parseM3U8(content: content) {
			completion(.success(playlist))
		} else {
			completion(.failure(.parsingError))
		}
	}

	func loadSegment(_ segment: M3U8Segment, completion: @escaping (Result<Data, HLSError>) -> Void) {
		guard let url = URL(string: segment.url) else {
			completion(.failure(.invalidURL))
			return
		}

		if let cachedData = cachedSegments[segment.url] {
			completion(.success(cachedData))
			return
		}

		let startTime = Date()
		let task = urlSession.dataTask(with: url) { [weak self] data, response, error in
			guard let self = self else { return }

			if let error = error {
				completion(.failure(.networkError(error)))
				return
			}

			guard let data = data else {
				completion(.failure(.noDataReceived))
				return
			}

			let endTime = Date()
			let downloadDuration = endTime.timeIntervalSince(startTime)
			let downloadSpeed = Double(data.count) / downloadDuration / 1024 // Speed in KB/s

			self.updateBandwidth(Int(downloadSpeed * 8)) // Convert to Kbps

			if self.isPreloadAvailable {
				self.cachedSegments[segment.url] = data
			}

			completion(.success(data))
		}

		task.resume()
	}

	private func updateBandwidth(_ newBandwidth: Int) {
		// Simple moving average
		currentBandwidth = (currentBandwidth + newBandwidth) / 2
	}

	func getBestVariant(for playlist: M3U8Playlist) -> M3U8Variant? {
		return playlist.variants.filter { $0.bandwidth <= currentBandwidth }
								.max(by: { $0.bandwidth < $1.bandwidth })
	}

	func setPreloadSettings(isAvailable: Bool, minimumDuration: TimeInterval) {
		isPreloadAvailable = isAvailable
		minimumPreloadDuration = minimumDuration
	}

	func preloadSegments(for playlist: M3U8Playlist) {
		guard isPreloadAvailable else { return }

		var totalDuration: TimeInterval = 0
		for segment in playlist.segments {
			guard totalDuration < minimumPreloadDuration else { break }
			loadSegment(segment) { _ in }
			totalDuration += segment.duration
		}
	}

	func clearCache() {
		cachedSegments.removeAll()
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

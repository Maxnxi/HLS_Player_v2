//
//  2.Parse_M3U8_service.swift
//  HLS_player
//
//  Created by Maksim Ponomarev on 10/8/24.
//
import Foundation

enum M3U8PlaylistType {
	case master
	case media
}

enum HLSStreamType {
	case vod
	case live
	case event
}

struct M3U8Playlist {
	var time_created: Int // seconds
	var type: M3U8PlaylistType = .media
	var version: Int = 0
	var independentSegments: Bool = false
	var streamType: HLSStreamType = .vod // Default to VOD

	// Master playlist specific
	var variants: [M3U8Variant] = []
	
	// Media playlist specific
	var targetDuration: Int = 0
	var mediaSequence: Int = 0
	var segments: [M3U8Segment] = []
	//var playlistType: String?
	var discontinuitySequence: Int?
	var endList: Bool = false
	var iFramesOnly: Bool = false
	
	// Common
	var startTimeOffset: Double?
	var mediaGroups: [String: [M3U8MediaGroup]] = [:]
	var sessionData: [String: String] = [:]
	var sessionKey: String?
	
	init() {
		self.time_created = Int(Date().timeIntervalSince1970)
	}
}

struct M3U8Variant {
	var url: String
	var bandwidth: Int
	var averageBandwidth: Int?
	var codecs: String?
	var resolution: (width: Int, height: Int)?
	var frameRate: Double?
	var hdcpLevel: String?
	var audioGroup: String?
	var videoGroup: String?
	var subtitlesGroup: String?
	var closedCaptionsGroup: String?
}

struct M3U8MediaGroup {
	var type: String
	var url: String?
	var groupId: String
	var language: String?
	var name: String
	var isDefault: Bool
	var autoSelect: Bool
	var forced: Bool?
	var characteristics: String?
	var channels: String?
}

struct M3U8Segment {
	var url: String
	var duration: Double
	var title: String?
	var byteRange: M3U8ByteRange?
	var discontinuity: Bool = false
	var key: M3U8Key?
	var map: M3U8Map?
	var programDateTime: Date?
	var dateRange: [String: String]?
}

struct M3U8ByteRange {
	var length: Int
	var offset: Int?
}

struct M3U8Key {
	var method: String
	var url: String?
	var iv: String?
	var keyFormat: String?
	var keyFormatVersions: String?
}

struct M3U8Map {
	var url: String
	var byteRange: M3U8ByteRange?
}

final class Parser_M3U8_Service {
	func parseM3U8(content: String) -> M3U8Playlist? {
		var lines = content.components(separatedBy: .newlines)
		
		guard lines.first == "#EXTM3U" else {
			print("Invalid M3U8 file: Missing #EXTM3U header")
			return nil
		}
		
		lines.removeFirst()
		
		var playlist = M3U8Playlist()
		var currentSegment: M3U8Segment?
		var currentVariant: M3U8Variant?
		
		for line in lines {
			if line.hasPrefix("#EXT-X-VERSION:") {
				playlist.version = Int(line.split(separator: ":")[1]) ?? 0
			} else if line == "#EXT-X-INDEPENDENT-SEGMENTS" {
				playlist.independentSegments = true
			} else if line.hasPrefix("#EXT-X-START:") {
				let params = parseParameters(line)
				playlist.startTimeOffset = Double(params["TIME-OFFSET"] ?? "")
			} else if line.hasPrefix("#EXT-X-STREAM-INF:") {
				playlist.type = .master
				let params = parseParameters(line)
				currentVariant = M3U8Variant(
					url: "",
					bandwidth: Int(params["BANDWIDTH"] ?? "") ?? 0,
					averageBandwidth: Int(params["AVERAGE-BANDWIDTH"] ?? ""),
					codecs: params["CODECS"],
					resolution: parseResolution(params["RESOLUTION"]),
					frameRate: Double(params["FRAME-RATE"] ?? ""),
					hdcpLevel: params["HDCP-LEVEL"],
					audioGroup: params["AUDIO"],
					videoGroup: params["VIDEO"],
					subtitlesGroup: params["SUBTITLES"],
					closedCaptionsGroup: params["CLOSED-CAPTIONS"]
				)
			} else if line.hasPrefix("#EXT-X-MEDIA:") {
				let params = parseParameters(line)
				if let type = params["TYPE"], let groupId = params["GROUP-ID"] {
					let mediaGroup = M3U8MediaGroup(
						type: type,
						url: params["URL"],
						groupId: groupId,
						language: params["LANGUAGE"],
						name: params["NAME"] ?? "",
						isDefault: params["DEFAULT"]?.lowercased() == "yes",
						autoSelect: params["AUTOSELECT"]?.lowercased() == "yes",
						forced: params["FORCED"].map { $0.lowercased() == "yes" },
						characteristics: params["CHARACTERISTICS"],
						channels: params["CHANNELS"]
					)
					playlist.mediaGroups[type, default: []].append(mediaGroup)
				}
			} else if playlist.type == .media {
				// Media playlist specific parsing
				if line.hasPrefix("#EXT-X-TARGETDURATION:") {
					playlist.targetDuration = Int(line.split(separator: ":")[1]) ?? 0
				} else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
					playlist.mediaSequence = Int(line.split(separator: ":")[1]) ?? 0
				} else if line.hasPrefix("#EXT-X-PLAYLIST-TYPE:") {
					
					let typeString = line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)
					switch typeString.lowercased() {
					case "vod":
						playlist.streamType = .vod
					case "event":
						playlist.streamType = .event
					default:
						break
					}
					
				} else if line.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE:") {
					playlist.discontinuitySequence = Int(line.split(separator: ":")[1]) ?? 0
				} else if line == "#EXT-X-ENDLIST" {
					playlist.endList = true
					playlist.streamType = .vod
				} else if line == "#EXT-X-I-FRAMES-ONLY" {
					playlist.iFramesOnly = true
				} else if line.hasPrefix("#EXTINF:") {
					let parts = line.split(separator: ":", maxSplits: 1)
					let infoParts = parts[1].split(separator: ",", maxSplits: 1)
					let duration = Double(infoParts[0]) ?? 0
					let title = infoParts.count > 1 ? String(infoParts[1]) : nil
					currentSegment = M3U8Segment(url: "", duration: duration, title: title)
				} else if line.hasPrefix("#EXT-X-BYTERANGE:") {
					let parts = line.split(separator: ":")[1].split(separator: "@")
					let length = Int(parts[0]) ?? 0
					let offset = parts.count > 1 ? Int(parts[1]) : nil
					currentSegment?.byteRange = M3U8ByteRange(length: length, offset: offset)
				} else if line == "#EXT-X-DISCONTINUITY" {
					currentSegment?.discontinuity = true
				} else if line.hasPrefix("#EXT-X-KEY:") {
					let params = parseParameters(line)
					currentSegment?.key = M3U8Key(
						method: params["METHOD"] ?? "",
						url: params["URL"],
						iv: params["IV"],
						keyFormat: params["KEYFORMAT"],
						keyFormatVersions: params["KEYFORMATVERSIONS"]
					)
				} else if line.hasPrefix("#EXT-X-MAP:") {
					let params = parseParameters(line)
					currentSegment?.map = M3U8Map(url: params["URL"] ?? "")
				} else if line.hasPrefix("#EXT-X-PROGRAM-DATE-TIME:") {
					let dateString = line.split(separator: ":").dropFirst().joined(separator: ":")
					let formatter = ISO8601DateFormatter()
					currentSegment?.programDateTime = formatter.date(from: dateString)
				} else if line.hasPrefix("#EXT-X-DATERANGE:") {
					currentSegment?.dateRange = parseParameters(line)
				}
			}
			
			// Handle URLs for both master and media playlists
			if !line.hasPrefix("#") && !line.isEmpty {
				if playlist.type == .master, var variant = currentVariant {
					variant.url = line
					playlist.variants.append(variant)
					currentVariant = nil
				} else if playlist.type == .media, var segment = currentSegment {
					segment.url = line
					playlist.segments.append(segment)
					currentSegment = nil
				}
			}
		}
		
		// If no PLAYLIST-TYPE or ENDLIST tag was found, assume it's a live stream
		if !lines.contains(where: { $0.hasPrefix("#EXT-X-PLAYLIST-TYPE:") || $0 == "#EXT-X-ENDLIST" }) {
			playlist.streamType = .live
		}
		
		return playlist
	}
	
	func parseParameters(_ line: String) -> [String: String] {
		let paramString = line.split(separator: ":").dropFirst().joined(separator: ":")
		let pairs = paramString.components(separatedBy: ",")
		var params: [String: String] = [:]
		
		for pair in pairs {
			let keyValue = pair.split(separator: "=", maxSplits: 1)
			if keyValue.count == 2 {
				let key = String(keyValue[0]).trimmingCharacters(in: .whitespaces)
				let value = String(keyValue[1]).trimmingCharacters(in: .whitespacesAndNewlines)
					.replacingOccurrences(of: "\"", with: "")
				params[key] = value
			}
		}
		
		return params
	}
	
	func parseResolution(_ resolution: String?) -> (width: Int, height: Int)? {
		guard let resolution = resolution else { return nil }
		let parts = resolution.split(separator: "x")
		guard parts.count == 2,
			  let width = Int(parts[0]),
			  let height = Int(parts[1]) else {
			return nil
		}
		return (width, height)
	}
}


/*
// Example usage:
let masterPlaylistContent = """
#EXTM3U
#EXT-X-VERSION:4
#EXT-X-INDEPENDENT-SEGMENTS

#EXT-X-STREAM-INF:BANDWIDTH=1280000,AVERAGE-BANDWIDTH=1000000,CODECS="avc1.64001f,mp4a.40.2",RESOLUTION=1280x720,FRAME-RATE=30,AUDIO="audio-group"
http://example.com/video_720p.m3u8

#EXT-X-STREAM-INF:BANDWIDTH=2560000,AVERAGE-BANDWIDTH=2000000,CODECS="avc1.640028,mp4a.40.2",RESOLUTION=1920x1080,FRAME-RATE=30,AUDIO="audio-group"
http://example.com/video_1080p.m3u8

#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-group",NAME="English",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="en",URL="http://example.com/audio_en.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-group",NAME="Spanish",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE="es",URL="http://example.com/audio_es.m3u8"
"""

if let playlist = parseM3U8(content: masterPlaylistContent) {
	print("Playlist Type: \(playlist.type)")
	print("Version: \(playlist.version)")
	print("Independent Segments: \(playlist.independentSegments)")
	print("Variants: \(playlist.variants.count)")
	for (index, variant) in playlist.variants.enumerated() {
		print("  Variant \(index + 1):")
		print("    URL: \(variant.url)")
		print("    Bandwidth: \(variant.bandwidth)")
		print("    Resolution: \(variant.resolution?.width ?? 0)x\(variant.resolution?.height ?? 0)")
	}
	print("Media Groups:")
	for (type, groups) in playlist.mediaGroups {
		print("  \(type): \(groups.count)")
		for group in groups {
			print("    Name: \(group.name), Language: \(group.language ?? "N/A"), URL: \(group.url ?? "N/A")")
		}
	}
} else {
	print("Failed to parse M3U8 playlist")
}
"""
*/

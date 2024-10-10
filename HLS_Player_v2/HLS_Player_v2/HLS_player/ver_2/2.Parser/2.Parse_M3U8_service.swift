//
//  2.Parse_M3U8_service.swift
//  HLS_player
//
//  Created by Maksim Ponomarev on 10/8/24.
//

import Foundation


final class Parser_M3U8_Service {
	func parseM3U8(content: String) -> M3U8Playlist? {
		print("Parser_M3U8_Service: Starting to parse M3U8 content")
		let lines = content.components(separatedBy: .newlines)
		
		guard lines.first == "#EXTM3U" else {
			print("Parser_M3U8_Service: Error - Invalid M3U8 file: Missing #EXTM3U header")
			return nil
		}
		
		var playlist = M3U8Playlist()
		var currentSegment: M3U8Segment?
		var currentVariant: M3U8Variant?
		
		for (index, line) in lines.dropFirst().enumerated() {
			autoreleasepool {
				parseLine(line, index: index, playlist: &playlist, currentSegment: &currentSegment, currentVariant: &currentVariant)
			}
		}
		
		// If no PLAYLIST-TYPE or ENDLIST tag was found, assume it's a live stream
		if !lines.contains(where: { $0.hasPrefix("#EXT-X-PLAYLIST-TYPE:") || $0 == "#EXT-X-ENDLIST" }) {
			playlist.streamType = .live
			print("Parser_M3U8_Service: No PLAYLIST-TYPE or ENDLIST found, assuming live stream")
		}
		
		print("Parser_M3U8_Service: Finished parsing M3U8 content")
		print("Parser_M3U8_Service: Playlist type: \(playlist.type)")
		print("Parser_M3U8_Service: Number of variants: \(playlist.variants.count)")
		print("Parser_M3U8_Service: Number of segments: \(playlist.segments.count)")
		
		return playlist
	}
	
	private func parseLine(_ line: String, index: Int, playlist: inout M3U8Playlist, currentSegment: inout M3U8Segment?, currentVariant: inout M3U8Variant?) {
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
			parseMediaGroup(line, playlist: &playlist)
		} else if playlist.type == .media {
			parseMediaPlaylistLine(line, playlist: &playlist, currentSegment: &currentSegment)
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
	
	func parseParameters(_ line: String) -> [String: String] {
		print("Parser_M3U8_Service: Parsing parameters from line: \(line)")
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
				print("Parser_M3U8_Service: Parsed parameter: \(key) = \(value)")
			}
		}
		
		return params
	}
	
	func parseResolution(_ resolution: String?) -> (width: Int, height: Int)? {
		guard let resolution = resolution else {
			print("Parser_M3U8_Service: No resolution to parse")
			return nil
		}
		let parts = resolution.split(separator: "x")
		guard parts.count == 2,
			  let width = Int(parts[0]),
			  let height = Int(parts[1]) else {
			print("Parser_M3U8_Service: Failed to parse resolution: \(resolution)")
			return nil
		}
		print("Parser_M3U8_Service: Parsed resolution: \(width)x\(height)")
		return (width, height)
	}
	
	private func parseMediaGroup(_ line: String, playlist: inout M3U8Playlist) {
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
	}
	
	private func parseMediaPlaylistLine(_ line: String, playlist: inout M3U8Playlist, currentSegment: inout M3U8Segment?) {
		if line.hasPrefix("#EXT-X-TARGETDURATION:") {
			playlist.targetDuration = Int(line.split(separator: ":")[1]) ?? 0
		} else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
			playlist.mediaSequence = Int(line.split(separator: ":")[1]) ?? 0
		} else if line.hasPrefix("#EXT-X-PLAYLIST-TYPE:") {
			let typeString = line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)
			playlist.streamType = typeString.lowercased() == "vod" ? .vod : .event
		} else if line.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE:") {
			playlist.discontinuitySequence = Int(line.split(separator: ":")[1]) ?? 0
		} else if line == "#EXT-X-ENDLIST" {
			playlist.endList = true
			playlist.streamType = .vod
		} else if line == "#EXT-X-I-FRAMES-ONLY" {
			playlist.iFramesOnly = true
		} else if line.hasPrefix("#EXTINF:") {
			parseInfLine(line, currentSegment: &currentSegment)
		} else if line.hasPrefix("#EXT-X-BYTERANGE:") {
			parseByteRange(line, currentSegment: &currentSegment)
		} else if line == "#EXT-X-DISCONTINUITY" {
			currentSegment?.discontinuity = true
		} else if line.hasPrefix("#EXT-X-KEY:") {
			parseKey(line, currentSegment: &currentSegment)
		} else if line.hasPrefix("#EXT-X-MAP:") {
			parseMap(line, currentSegment: &currentSegment)
		} else if line.hasPrefix("#EXT-X-PROGRAM-DATE-TIME:") {
			parseProgramDateTime(line, currentSegment: &currentSegment)
		} else if line.hasPrefix("#EXT-X-DATERANGE:") {
			currentSegment?.dateRange = parseParameters(line)
		}
	}
	
	private func parseInfLine(_ line: String, currentSegment: inout M3U8Segment?) {
		let parts = line.split(separator: ":", maxSplits: 1)
		let infoParts = parts[1].split(separator: ",", maxSplits: 1)
		let duration = Double(infoParts[0]) ?? 0
		let title = infoParts.count > 1 ? String(infoParts[1]) : nil
		currentSegment = M3U8Segment(url: "", duration: duration, title: title)
	}
	
	private func parseByteRange(_ line: String, currentSegment: inout M3U8Segment?) {
		let parts = line.split(separator: ":")[1].split(separator: "@")
		let length = Int(parts[0]) ?? 0
		let offset = parts.count > 1 ? Int(parts[1]) : nil
		currentSegment?.byteRange = M3U8ByteRange(length: length, offset: offset)
	}
	
	private func parseKey(_ line: String, currentSegment: inout M3U8Segment?) {
		let params = parseParameters(line)
		currentSegment?.key = M3U8Key(
			method: params["METHOD"] ?? "",
			url: params["URI"],
			iv: params["IV"],
			keyFormat: params["KEYFORMAT"],
			keyFormatVersions: params["KEYFORMATVERSIONS"]
		)
	}
	
	private func parseMap(_ line: String, currentSegment: inout M3U8Segment?) {
		let params = parseParameters(line)
		currentSegment?.map = M3U8Map(url: params["URI"] ?? "")
		if let byteRange = params["BYTERANGE"] {
			let parts = byteRange.split(separator: "@")
			let length = Int(parts[0]) ?? 0
			let offset = parts.count > 1 ? Int(parts[1]) : nil
			currentSegment?.map?.byteRange = M3U8ByteRange(length: length, offset: offset)
		}
	}
	
	private func parseProgramDateTime(_ line: String, currentSegment: inout M3U8Segment?) {
		let dateString = line.split(separator: ":").dropFirst().joined(separator: ":")
		let formatter = ISO8601DateFormatter()
		currentSegment?.programDateTime = formatter.date(from: dateString)
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

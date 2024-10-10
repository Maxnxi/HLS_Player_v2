//
//  Parser_Structs.swift
//  HLS_Player_v2
//
//  Created by Maksim Ponomarev on 10/10/24.
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

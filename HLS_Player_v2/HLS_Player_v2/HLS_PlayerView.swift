//
//  HLS_PlayerView.swift
//  HLS_Player_v2
//
//  Created by Maksim Ponomarev on 10/10/24.
//

import SwiftUI

//struct HLS_PlayerView: View {
//    var body: some View {
//        Text("Hello, World!")
//    }
//}
//
//#Preview {
//    HLS_PlayerView()
//}

import SwiftUI

struct HLSPlayerView: UIViewRepresentable {
	@ObservedObject var player: HLS_Player_ver_2_Impl
	
	func makeUIView(context: Context) -> UIView {
		print("HLSPlayerView: Creating UIView")
		let view = UIView(frame: .zero)
		let playerLayer = player.getPlayerLayer()
		playerLayer.frame = view.bounds
		view.layer.addSublayer(playerLayer)
		return view
	}
	
	func updateUIView(_ uiView: UIView, context: Context) {
		DispatchQueue.main.async {
			print("HLSPlayerView: Updating UIView")
			if let playerLayer = uiView.layer.sublayers?.first as? CAMetalLayer {
				CATransaction.begin()
				CATransaction.setDisableActions(true)
				playerLayer.frame = uiView.bounds
				CATransaction.commit()
				print("HLSPlayerView: Updated player layer frame to \(uiView.bounds)")
			} else {
				print("HLSPlayerView: Player layer not found or not a CAMetalLayer")
			}
		}
	}
	
	static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
		print("HLSPlayerView: Dismantling UIView")
		// Clean up any resources if needed
		if let playerLayer = uiView.layer.sublayers?.first as? CAMetalLayer {
			playerLayer.removeFromSuperlayer()
		}
	}
}

import SwiftUI

struct HLSPlayer_ContentView: View {
	@StateObject private var player = HLS_Player_ver_2_Impl()
	
	var body: some View {
		VStack {
			HLSPlayerView(player: player)
				.aspectRatio(16/9, contentMode: .fit)
				.background(Color.yellow)
//				.onAppear {
//					print("ContentView: HLSPlayerView appeared")
//					player.play()
//				}
//				.onDisappear {
//					print("HLSPlayer_ContentView: HLSPlayerView disappeared")
//					player.stop()
//				}
			
			HStack {
				Button(player.isPlaying ? "Pause" : "Play") {
					if player.isPlaying {
						player.pause()
					} else {
						player.play()
					}
				}
				Button("Stop") {
					player.stop()
				}
			}
			.padding()
			
			Text("Playback Time: \(formatTime(player.currentPlaybackTime))")
			Text("Player State: \(player.playerState)")
		}
		.onAppear {
			print("HLSPlayer_ContentView: View appeared")
			// Load and prepare your HLS stream
			player.load_new_movie("http://qthttp.apple.com.edgesuite.net/1010qwoeiuryfg/0440_vod.m3u8")
		}
	}
	
	private func formatTime(_ time: TimeInterval) -> String {
		let minutes = Int(time) / 60
		let seconds = Int(time) % 60
		return String(format: "%02d:%02d", minutes, seconds)
	}
}

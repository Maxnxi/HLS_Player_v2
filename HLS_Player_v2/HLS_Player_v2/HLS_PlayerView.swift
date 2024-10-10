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
	let player: HLS_Player_ver_2_Impl
	
	func makeUIView(context: Context) -> UIView {
		let view = UIView(frame: .zero)
		let playerLayer = player.getPlayerLayer()
		playerLayer.frame = view.bounds
		view.layer.addSublayer(playerLayer)
		
		// Set up constraints to keep the playerLayer sized to its superview
		playerLayer.anchorPoint = .zero
		playerLayer.position = .zero
		
		return view
	}
	
	func updateUIView(_ uiView: UIView, context: Context) {
		// Ensure the player layer is always the size of the view
		if let playerLayer = uiView.layer.sublayers?.first {
			playerLayer.frame = uiView.bounds
		}
	}
	
	static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
		// Clean up any resources if needed
	}
}

struct HLSPlayer_ContentView: View {
	var player = HLS_Player_ver_2_Impl()
	
	var body: some View {
		VStack {
			HLSPlayerView(player: player)
				.aspectRatio(16/9, contentMode: .fit)
				.border(Color.black, width: 5)
			
			HStack {
				Button("Play") {
					player.play()
				}
				Button("Pause") {
					player.pause()
				}
				Button("Stop") {
					player.stop()
				}
			}
		}
		.task {
			// Load and prepare your HLS stream
			player.load_new_movie("http://content.jwplatform.com/manifests/vM7nH0Kl.m3u8")
		}
	}
}

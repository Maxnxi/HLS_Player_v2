//
//  0.HLSPlayerLayer.swift
//  HLS_Player_v2
//
//  Created by Maksim Ponomarev on 10/10/24.
//

import MetalKit
import QuartzCore

class HLSPlayerLayer: CAMetalLayer {
	weak var metalVideoView: MetalVideoView?
	
	override init() {
		super.init()
		framebufferOnly = false
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	override func display() {
		metalVideoView?.drawVideo()
	}
}

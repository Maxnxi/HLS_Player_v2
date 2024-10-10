//
//  MetalVideoView.swift
//  HLS_Player_v2
//
//  Created by Maksim Ponomarev on 10/10/24.
//

import MetalKit
import CoreVideo
import simd


class MetalVideoView: MTKView {
	private var commandQueue: MTLCommandQueue?
	private var pipelineState: MTLRenderPipelineState?
	private var yTexture: MTLTexture?
	private var cbcrTexture: MTLTexture?
	private var vertices: MTLBuffer?
	private var textureCoordinates: MTLBuffer?
	private var playerLayer: HLSPlayerLayer?
	
	private let textureCache: CVMetalTextureCache
	
	// Vertex data for a quad that fills the entire view
	private let quadVertices: [SIMD3<Float>] = [
		SIMD3<Float>(-1, -1, 0), // Bottom left
		SIMD3<Float>( 1, -1, 0), // Bottom right
		SIMD3<Float>(-1,  1, 0), // Top left
		SIMD3<Float>( 1,  1, 0)  // Top right
	]
	
	// Texture coordinates for the quad
	private let quadTextureCoordinates: [SIMD2<Float>] = [
		SIMD2<Float>(0, 1), // Bottom left
		SIMD2<Float>(1, 1), // Bottom right
		SIMD2<Float>(0, 0), // Top left
		SIMD2<Float>(1, 0)  // Top right
	]
	
	override init(frame frameRect: CGRect, device: MTLDevice?) {
		print("MetalVideoView: Initializing")
		var textureCache: CVMetalTextureCache?
		guard let device = device else {
			fatalError("Metal device not created")
		}
		CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
		guard let unwrappedTextureCache = textureCache else {
			fatalError("Unable to allocate texture cache")
		}
		self.textureCache = unwrappedTextureCache
		
		super.init(frame: frameRect, device: device)
		
		self.device = device
		self.backgroundColor = .black
		self.framebufferOnly = false
		self.setupMetal()
		self.setupPlayerLayer()
		print("MetalVideoView: Initialization complete")
	}
	
	required init(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	private func setupMetal() {
		print("MetalVideoView: Setting up Metal")
		guard let device = self.device else { return }
		
		commandQueue = device.makeCommandQueue()
		
		// Load Metal shader file
		guard let library = device.makeDefaultLibrary() else {
			fatalError("Unable to create default Metal library")
		}
		
		let vertexFunction = library.makeFunction(name: "vertexShader")
		let fragmentFunction = library.makeFunction(name: "fragmentShader")
		
		// Create render pipeline state
		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		pipelineDescriptor.vertexFunction = vertexFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction
		pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
		
		do {
			pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
			print("MetalVideoView: Render pipeline state created successfully")
		} catch {
			fatalError("Failed to create pipeline state: \(error)")
		}
		
		// Create vertex and texture coordinate buffers
		vertices = device.makeBuffer(bytes: quadVertices,
									 length: quadVertices.count * MemoryLayout<SIMD3<Float>>.stride,
									 options: [])
		textureCoordinates = device.makeBuffer(bytes: quadTextureCoordinates,
											   length: quadTextureCoordinates.count * MemoryLayout<SIMD2<Float>>.stride,
											   options: [])
		print("MetalVideoView: Vertex and texture coordinate buffers created")
	}
	
	private func setupPlayerLayer() {
		print("MetalVideoView: Setting up player layer")
		playerLayer = HLSPlayerLayer()
		playerLayer?.metalVideoView = self
		playerLayer?.device = device
		playerLayer?.pixelFormat = .bgra8Unorm
		playerLayer?.framebufferOnly = false
		layer.addSublayer(playerLayer!)
		print("MetalVideoView: Player layer setup complete")
	}
	
	override func layoutSubviews() {
		super.layoutSubviews()
		print("MetalVideoView: Laying out subviews")
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		playerLayer?.frame = bounds
		CATransaction.commit()
		print("MetalVideoView: Player layer frame updated to \(bounds)")
	}
	
	func updateWithFrame(_ frame: DecodedFrame) {
		print("MetalVideoView: Updating with new frame - Size: \(frame.width)x\(frame.height), Format: \(frame.format)")
		guard frame.data.count >= 2 else {
			print("MetalVideoView: Invalid frame data. Expected at least 2 planes for YUV420P.")
			return
		}
		
		let width = frame.width
		let height = frame.height
		
		// Create Y texture
		yTexture = createTexture(from: frame.data[0], width: width, height: height, format: .r8Unorm)
		
		// Create CbCr texture
		cbcrTexture = createTexture(from: frame.data[1], width: width / 2, height: height / 2, format: .rg8Unorm)
		
		if yTexture != nil && cbcrTexture != nil {
			print("MetalVideoView: Y and CbCr textures created successfully")
		} else {
			print("MetalVideoView: Failed to create Y and/or CbCr textures")
		}
		
		// Trigger a redraw
		playerLayer?.setNeedsDisplay()
		print("MetalVideoView: Requested redraw")
	}
	
	private func createTexture(from data: Data, width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture? {
		print("MetalVideoView: Creating texture - Size: \(width)x\(height), Format: \(format)")
		guard let device = self.device else { return nil }
		
		let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
																		 width: width,
																		 height: height,
																		 mipmapped: false)
		textureDescriptor.usage = [.shaderRead]
		
		guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
			print("MetalVideoView: Failed to create texture")
			return nil
		}
		
		let region = MTLRegionMake2D(0, 0, width, height)
		data.withUnsafeBytes { rawBufferPointer in
			texture.replace(region: region,
							mipmapLevel: 0,
							withBytes: rawBufferPointer.baseAddress!,
							bytesPerRow: width * format.bytesPerPixel)
		}
		
		print("MetalVideoView: Texture created successfully")
		return texture
	}
	
	func drawVideo() {
		print("MetalVideoView: Drawing video frame")
		guard let drawable = playerLayer?.nextDrawable(),
			  let pipelineState = pipelineState,
			  let commandBuffer = commandQueue?.makeCommandBuffer(),
			  let renderPassDescriptor = currentRenderPassDescriptor,
			  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
			  let yTexture = yTexture,
			  let cbcrTexture = cbcrTexture else {
			print("MetalVideoView: Failed to get required objects for drawing")
			return
		}
		
		renderEncoder.setRenderPipelineState(pipelineState)
		renderEncoder.setVertexBuffer(vertices, offset: 0, index: 0)
		renderEncoder.setVertexBuffer(textureCoordinates, offset: 0, index: 1)
		renderEncoder.setFragmentTexture(yTexture, index: 0)
		renderEncoder.setFragmentTexture(cbcrTexture, index: 1)
		renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
		renderEncoder.endEncoding()
		
		commandBuffer.present(drawable)
		commandBuffer.commit()
		
		print("MetalVideoView: Video frame drawn and presented")
	}
}

extension MTLPixelFormat {
	var bytesPerPixel: Int {
		switch self {
		case .r8Unorm:
			return 1
		case .rg8Unorm:
			return 2
		default:
			fatalError("Unsupported pixel format")
		}
	}
}

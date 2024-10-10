//
//  MetalVideoView.swift
//  HLS_Player_v2
//
//  Created by Maksim Ponomarev on 10/10/24.
//

import MetalKit
import CoreVideo
import simd


enum TextureError: Error {
	case invalidDataSize
	case failedToCreateTexture
}


class MetalVideoView: MTKView {
	private var commandQueue: MTLCommandQueue?
	private var pipelineState: MTLRenderPipelineState?
	
	private var cbcrTexture: MTLTexture?
	private var vertices: MTLBuffer?
	private var textureCoordinates: MTLBuffer?
	private var playerLayer: HLSPlayerLayer?
	
	private let textureCache: CVMetalTextureCache
	
	private var yTextureDescriptor: MTLTextureDescriptor?
		private var cbcrTextureDescriptor: MTLTextureDescriptor?
	
	private var yTexture: MTLTexture?
		private var uTexture: MTLTexture?
		private var vTexture: MTLTexture?
	
	private var currentFrame: DecodedFrame?
	
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
		self.delegate = self
		
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
			print("MetalVideoView: Received frame for rendering - Size: \(frame.width)x\(frame.height), PTS: \(frame.pts)")
			currentFrame = frame
			DispatchQueue.main.async {
				self.setNeedsDisplay()
			}
		}
	
//	func updateWithFrame(_ frame: DecodedFrame) {
//			print("MetalVideoView: Updating with new frame - Size: \(frame.width)x\(frame.height), Format: \(frame.format)")
//			guard frame.data.count >= 3 else {
//				print("MetalVideoView: Invalid frame data. Expected 3 planes for YUV420P.")
//				return
//			}
//
//			let width = frame.width
//			let height = frame.height
//
//			yTexture = createOrUpdateTexture(yTexture, with: frame.data[0], width: width, height: height, bytesPerRow: frame.linesize[0], format: .r8Unorm)
//			uTexture = createOrUpdateTexture(uTexture, with: frame.data[1], width: width/2, height: height/2, bytesPerRow: frame.linesize[1], format: .r8Unorm)
//			vTexture = createOrUpdateTexture(vTexture, with: frame.data[2], width: width/2, height: height/2, bytesPerRow: frame.linesize[2], format: .r8Unorm)
//
//			if yTexture != nil && uTexture != nil && vTexture != nil {
//				DispatchQueue.main.async {
//					self.setNeedsDisplay()
//				}
//				print("MetalVideoView: Requested redraw")
//			} else {
//				print("MetalVideoView: Failed to create or update textures")
//			}
//		}
	
	private func createOrUpdateTexture(_ texture: MTLTexture?, with data: Data, width: Int, height: Int, bytesPerRow: Int, format: MTLPixelFormat) -> MTLTexture? {
			if let existingTexture = texture, existingTexture.width == width, existingTexture.height == height {
				updateTexture(existingTexture, with: data, bytesPerRow: bytesPerRow)
				return existingTexture
			} else {
				return createTexture(from: data, width: width, height: height, bytesPerRow: bytesPerRow, format: format)
			}
		}

	private func updateTexture(_ texture: MTLTexture, with data: Data, bytesPerRow: Int) {
		   let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
		   data.withUnsafeBytes { rawBufferPointer in
			   texture.replace(region: region,
							   mipmapLevel: 0,
							   withBytes: rawBufferPointer.baseAddress!,
							   bytesPerRow: bytesPerRow)
		   }
	   }

	private func createTexture(from data: Data, width: Int, height: Int, bytesPerRow: Int, format: MTLPixelFormat) -> MTLTexture? {
			let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
																			 width: width,
																			 height: height,
																			 mipmapped: false)
			textureDescriptor.usage = [.shaderRead]
			
			guard let texture = device?.makeTexture(descriptor: textureDescriptor) else {
				print("MetalVideoView: Failed to create texture")
				return nil
			}
			
			updateTexture(texture, with: data, bytesPerRow: bytesPerRow)
			
			return texture
		}
	
	func drawVideo() {
		print("MetalVideoView: Drawing video frame")
		autoreleasepool {
			guard let drawable = playerLayer?.nextDrawable() else {
				print("MetalVideoView: Failed to get nextDrawable")
				return
			}
			guard let pipelineState = pipelineState else {
				print("MetalVideoView: pipelineState is nil")
				return
			}
			guard let commandBuffer = commandQueue?.makeCommandBuffer() else {
				print("MetalVideoView: Failed to create command buffer")
				return
			}
			guard let renderPassDescriptor = currentRenderPassDescriptor else {
				print("MetalVideoView: renderPassDescriptor is nil")
				return
			}
			guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
				print("MetalVideoView: Failed to create render encoder")
				return
			}
			guard let yTexture = yTexture else {
				print("MetalVideoView: yTexture is nil")
				return
			}
			guard let cbcrTexture = cbcrTexture else {
				print("MetalVideoView: cbcrTexture is nil")
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
			commandBuffer.waitUntilCompleted()
			
			print("MetalVideoView: Video frame drawn and presented")
		}
	}
	
	override func draw(_ rect: CGRect) {
			autoreleasepool {
				guard let currentFrame = currentFrame else {
					print("MetalVideoView: No current frame to render")
					return
				}
				
				print("MetalVideoView: Drawing frame - Size: \(currentFrame.width)x\(currentFrame.height), PTS: \(currentFrame.pts)")
				
				// Create textures and render the frame
				let yTexture = createOrUpdateTexture(yTexture, with: currentFrame.data[0], width: currentFrame.width, height: currentFrame.height, bytesPerRow: currentFrame.linesize[0], format: .r8Unorm)
				let uTexture = createOrUpdateTexture(uTexture, with: currentFrame.data[1], width: currentFrame.width/2, height: currentFrame.height/2, bytesPerRow: currentFrame.linesize[1], format: .r8Unorm)
				let vTexture = createOrUpdateTexture(vTexture, with: currentFrame.data[2], width: currentFrame.width/2, height: currentFrame.height/2, bytesPerRow: currentFrame.linesize[2], format: .r8Unorm)
				
				guard let yTex = yTexture, let uTex = uTexture, let vTex = vTexture else {
					print("MetalVideoView: Failed to create or update textures")
					return
				}
				
				render(yTexture: yTex, uTexture: uTex, vTexture: vTex)
				
				print("MetalVideoView: Frame rendered and presented")
			}
		}
//	override func draw(_ rect: CGRect) {
//			autoreleasepool {
//				guard let currentFrame = currentFrame else {
//					print("MetalVideoView: Missing textures for rendering")
//					return
//				}
//				print("MetalVideoView: Drawing frame - Size: \(currentFrame.width)x\(currentFrame.height), PTS: \(currentFrame.pts)")
//
//				
//				let yTexture = createOrUpdateTexture(yTexture, with: currentFrame.data[0], width: currentFrame.width, height: currentFrame.height, bytesPerRow: currentFrame.linesize[0], format: .r8Unorm)
//				let uTexture = createOrUpdateTexture(uTexture, with: currentFrame.data[1], width: currentFrame.width/2, height: currentFrame.height/2, bytesPerRow: currentFrame.linesize[1], format: .r8Unorm)
//				let vTexture = createOrUpdateTexture(vTexture, with: currentFrame.data[2], width: currentFrame.width/2, height: currentFrame.height/2, bytesPerRow: currentFrame.linesize[2], format: .r8Unorm)
//				
//				guard let yTex = yTexture, let uTex = uTexture, let vTex = vTexture else {
//					print("MetalVideoView: Failed to create or update textures")
//					return
//				}
//				
//				render(yTexture: yTex, uTexture: uTex, vTexture: vTex)
//				print("MetalVideoView: Frame rendered and presented")
//			}
//		}
	
	private func render(yTexture: MTLTexture, uTexture: MTLTexture, vTexture: MTLTexture) {
		   guard let pipelineState,
				 let commandBuffer = commandQueue?.makeCommandBuffer(),
				 let renderPassDescriptor = currentRenderPassDescriptor,
				 let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
			   return
		   }

		   renderEncoder.setRenderPipelineState(pipelineState)
		   renderEncoder.setVertexBuffer(vertices, offset: 0, index: 0)
		   renderEncoder.setVertexBuffer(textureCoordinates, offset: 0, index: 1)
		   renderEncoder.setFragmentTexture(yTexture, index: 0)
		   renderEncoder.setFragmentTexture(uTexture, index: 1)
		   renderEncoder.setFragmentTexture(vTexture, index: 2)
		   renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
		   renderEncoder.endEncoding()

		   if let drawable = currentDrawable {
			   commandBuffer.present(drawable)
			   print("MetalVideoView: currentDrawable")
		   }
		   commandBuffer.commit()
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

extension MetalVideoView: MTKViewDelegate {
	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
		print("MetalVideoView: Drawable size will change to \(size)")
	}
	
	func draw(in view: MTKView) {
		drawVideo()
	}
}

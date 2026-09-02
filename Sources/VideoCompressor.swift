import Foundation
import AVFoundation
import CoreMedia
import CoreImage

final class VideoCompressor: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage = "Siap memproses"
    
    func compressVideo(inputURL: URL, fitWhatsAppScreen: Bool = true) async throws -> URL {
        await MainActor.run {
            self.isProcessing = true
            self.statusMessage = "Menganalisis frame 60 FPS..."
        }
        
        let asset = AVURLAsset(url: inputURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Compressor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Track video tidak ditemukan."])
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        
        let isPortrait = (transform.a == 0 && abs(transform.b) == 1.0) || (transform.d == 0 && abs(transform.c) == 1.0)
        
        // Atur resolusi kanvas: 1080x2340 (Anti-Zoom WA iPhone) atau 1080x1920 (Original 9:16)
        let targetWidth: Int
        let targetHeight: Int
        if isPortrait {
            targetWidth = 1080
            targetHeight = fitWhatsAppScreen ? 2340 : 1920
        } else {
            targetWidth = 1920
            targetHeight = 1080
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WA_HD_60FPS_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        // 1. SETUP READER
        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.alwaysCopiesSampleData = false
        if reader.canAdd(videoOutput) {
            reader.add(videoOutput)
        }
        
        var audioOutput: AVAssetReaderTrackOutput? = nil
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
            let aOut = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM]
            )
            aOut.alwaysCopiesSampleData = false
            if reader.canAdd(aOut) {
                reader.add(aOut)
                audioOutput = aOut
            }
        }
        
        // 2. SETUP WRITER
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetWidth,
            AVVideoHeightKey: targetHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_500_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoExpectedSourceFrameRateKey: 60
            ]
        ]
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.mediaTimeScale = 60000
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: targetWidth,
            kCVPixelBufferHeightKey as String: targetHeight,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        
        var audioInput: AVAssetWriterInput? = nil
        if audioOutput != nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 128_000
            ]
            let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aIn.expectsMediaDataInRealTime = false
            if writer.canAdd(aIn) {
                writer.add(aIn)
                audioInput = aIn
            }
        }
        
        // 3. PROSES RENDERING METAL DENGAN SKALA PRESISI
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        await MainActor.run {
            self.statusMessage = "Merender 1080p 60 FPS Anti-Crop..."
        }
        
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let videoQueue = DispatchQueue(label: "videoCompressQueue")
        let audioQueue = DispatchQueue(label: "audioCompressQueue")
        let group = DispatchGroup()
        
        var isVideoDone = false
        var pendingVideoBuffer: CMSampleBuffer? = nil
        
        group.enter()
        videoInput.requestMediaDataWhenReady(on: videoQueue) {
            if isVideoDone { return }
            
            while videoInput.isReadyForMoreMediaData {
                if pendingVideoBuffer == nil {
                    pendingVideoBuffer = videoOutput.copyNextSampleBuffer()
                }
                
                guard let sampleBuffer = pendingVideoBuffer else {
                    if !isVideoDone {
                        isVideoDone = true
                        videoInput.markAsFinished()
                        group.leave()
                    }
                    break
                }
                
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                var appendSuccess = false
                
                autoreleasepool {
                    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        pendingVideoBuffer = nil
                        return
                    }
                    
                    var ciImage = CIImage(cvPixelBuffer: imageBuffer)
                    ciImage = ciImage.transformed(by: transform)
                    ciImage = ciImage.transformed(by: CGAffineTransform(
                        translationX: -ciImage.extent.origin.x,
                        y: -ciImage.extent.origin.y
                    ))
                    
                    // Skala video agar muat pas di kanvas tanpa melar (Aspect Fit)
                    let scale = min(CGFloat(targetWidth) / ciImage.extent.width, CGFloat(targetHeight) / ciImage.extent.height)
                    let scaledWidth = ciImage.extent.width * scale
                    let scaledHeight = ciImage.extent.height * scale
                    
                    let offsetX = (CGFloat(targetWidth) - scaledWidth) / 2.0
                    let offsetY = (CGFloat(targetHeight) - scaledHeight) / 2.0
                    
                    ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    ciImage = ciImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
                    
                    var pixelBufferOut: CVPixelBuffer?
                    if let pool = adaptor.pixelBufferPool {
                        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut)
                    } else {
                        CVPixelBufferCreate(
                            kCFAllocatorDefault,
                            targetWidth,
                            targetHeight,
                            kCVPixelFormatType_32BGRA,
                            pixelBufferAttributes as CFDictionary,
                            &pixelBufferOut
                        )
                    }
                    
                    if let destBuffer = pixelBufferOut {
                        ciContext.render(ciImage, to: destBuffer)
                        appendSuccess = adaptor.append(destBuffer, withPresentationTime: pts)
                    }
                }
                
                if appendSuccess {
                    pendingVideoBuffer = nil
                } else {
                    break
                }
            }
        }
        
        var isAudioDone = false
        var pendingAudioBuffer: CMSampleBuffer? = nil
        
        if let aIn = audioInput, let aOut = audioOutput {
            group.enter()
            aIn.requestMediaDataWhenReady(on: audioQueue) {
                if isAudioDone { return }
                
                while aIn.isReadyForMoreMediaData {
                    if pendingAudioBuffer == nil {
                        pendingAudioBuffer = aOut.copyNextSampleBuffer()
                    }
                    
                    guard let buffer = pendingAudioBuffer else {
                        if !isAudioDone {
                            isAudioDone = true
                            aIn.markAsFinished()
                            group.leave()
                        }
                        break
                    }
                    
                    if aIn.append(buffer) {
                        pendingAudioBuffer = nil
                    } else {
                        break
                    }
                }
            }
        }
        
        await withCheckedContinuation { continuation in
            group.notify(queue: .main) {
                continuation.resume()
            }
        }
        
        await writer.finishWriting()
        
        await MainActor.run {
            self.isProcessing = false
        }
        
        if writer.status == .completed {
            return outputURL
        } else {
            throw writer.error ?? NSError(domain: "Compressor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Gagal encoding."])
        }
    }
}

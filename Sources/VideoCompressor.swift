import Foundation
import AVFoundation
import CoreMedia
import CoreImage

final class VideoCompressor: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage = "Siap memproses"
    
    func compressVideo(inputURL: URL) async throws -> URL {
        await MainActor.run {
            self.isProcessing = true
            self.statusMessage = "Membaca 60 FPS murni via GPU..."
        }
        
        let asset = AVURLAsset(url: inputURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Compressor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Track video tidak ditemukan."])
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        
        // Deteksi Portrait vs Landscape
        let isPortrait = (transform.a == 0 && abs(transform.b) == 1.0) || (transform.d == 0 && abs(transform.c) == 1.0)
        let targetWidth: Int = isPortrait ? 1080 : 1920
        let targetHeight: Int = isPortrait ? 1920 : 1080
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WA_HD_60FPS_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        // 1. READER MURNI (Direct Track Output: Tidak akan pernah drop ke 30 FPS!)
        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.alwaysCopiesSampleData = false
        if reader.canAdd(videoOutput) {
            reader.add(videoOutput)
        }
        
        // Audio Track
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
        
        // 2. WRITER ANTI-BEGAL WHATSAPP
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
        
        // 3. HARDWARE ACCELERATED RENDERING VIA METAL
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        await MainActor.run {
            self.statusMessage = "Merender 1080p 60 FPS..."
        }
        
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let videoQueue = DispatchQueue(label: "videoCompressQueue")
        let audioQueue = DispatchQueue(label: "audioCompressQueue")
        let group = DispatchGroup()
        
        var isVideoDone = false
        group.enter()
        videoInput.requestMediaDataWhenReady(on: videoQueue) {
            if isVideoDone { return }
            while videoInput.isReadyForMoreMediaData {
                guard let sampleBuffer = videoOutput.copyNextSampleBuffer() else {
                    if !isVideoDone {
                        isVideoDone = true
                        videoInput.markAsFinished()
                        group.leave()
                    }
                    break
                }
                
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                
                // Rotasi dan scaling presisi menggunakan Metal GPU
                var ciImage = CIImage(cvPixelBuffer: imageBuffer)
                ciImage = ciImage.transformed(by: transform)
                
                // Normalisasi origin
                ciImage = ciImage.transformed(by: CGAffineTransform(
                    translationX: -ciImage.extent.origin.x,
                    y: -ciImage.extent.origin.y
                ))
                
                let scaleX = CGFloat(targetWidth) / ciImage.extent.width
                let scaleY = CGFloat(targetHeight) / ciImage.extent.height
                ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                
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
                    adaptor.append(destBuffer, withPresentationTime: pts)
                }
            }
        }
        
        var isAudioDone = false
        if let aIn = audioInput, let aOut = audioOutput {
            group.enter()
            aIn.requestMediaDataWhenReady(on: audioQueue) {
                if isAudioDone { return }
                while aIn.isReadyForMoreMediaData {
                    if let buffer = aOut.copyNextSampleBuffer() {
                        aIn.append(buffer)
                    } else {
                        if !isAudioDone {
                            isAudioDone = true
                            aIn.markAsFinished()
                            group.leave()
                        }
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

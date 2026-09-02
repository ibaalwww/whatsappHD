import Foundation
import AVFoundation
import CoreMedia
import CoreImage

final class VideoCompressor: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage = "Siap memproses"
    
    func compressVideo(inputURL: URL, musicURL: URL? = nil) async throws -> URL {
        await MainActor.run {
            self.isProcessing = true
            self.statusMessage = "Membaca orientasi dan frame 60 FPS..."
        }
        
        let videoAsset = AVURLAsset(url: inputURL)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Compressor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Track video tidak ditemukan."])
        }
        
        let transform = try await videoTrack.load(.preferredTransform)
        let orientation = getOrientation(from: transform)
        
        // Cek apakah video portrait atau landscape berdasarkan EXIF orientation
        let isPortrait = (orientation == .right || orientation == .left || orientation == .rightMirrored || orientation == .leftMirrored)
        let targetWidth: Int = isPortrait ? 1080 : 1920
        let targetHeight: Int = isPortrait ? 1920 : 1080
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WA_HD_STATUS_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        // 1. SETUP READER VIDEO
        let reader = try AVAssetReader(asset: videoAsset)
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.alwaysCopiesSampleData = false
        if reader.canAdd(videoOutput) {
            reader.add(videoOutput)
        }
        
        // 2. SETUP AUDIO (Gunakan Musik Tambahan Jika Ada, Atau Suara Asli)
        var audioAsset = videoAsset
        if let customMusic = musicURL {
            audioAsset = AVURLAsset(url: customMusic)
        }
        
        var audioOutput: AVAssetReaderTrackOutput? = nil
        var audioReader: AVAssetReader? = nil
        
        if let audioTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first {
            let aReader = try AVAssetReader(asset: audioAsset)
            let aOut = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM]
            )
            aOut.alwaysCopiesSampleData = false
            if aReader.canAdd(aOut) {
                aReader.add(aOut)
                audioOutput = aOut
                audioReader = aReader
            }
        }
        
        // 3. SETUP WRITER ANTI-BEGAL WHATSAPP
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetWidth,
            AVVideoHeightKey: targetHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 3_000_000, // 3.0 Mbps: Ambang batas aman WhatsApp
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60,   // Keyframe tepat tiap 1 detik
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
        
        // 4. MULAI PROSES ENCODING
        reader.startReading()
        audioReader?.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        await MainActor.run {
            self.statusMessage = musicURL != nil ? "Memadukan musik & merender 60 FPS..." : "Merender 1080p 60 FPS murni..."
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
                    
                    // KUNCI ANTI-TERBALIK: Gunakan CGImagePropertyOrientation
                    var ciImage = CIImage(cvPixelBuffer: imageBuffer).oriented(orientation)
                    
                    // Penskalaan Aspect-Fit ke 1080x1920
                    let extent = ciImage.extent
                    let scaleX = CGFloat(targetWidth) / extent.width
                    let scaleY = CGFloat(targetHeight) / extent.height
                    let scale = max(scaleX, scaleY)
                    
                    ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    ciImage = ciImage.transformed(by: CGAffineTransform(
                        translationX: -ciImage.extent.origin.x + (CGFloat(targetWidth) - ciImage.extent.width) / 2.0,
                        y: -ciImage.extent.origin.y + (CGFloat(targetHeight) - ciImage.extent.height) / 2.0
                    ))
                    
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
        
        // AUDIO THREAD
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
    
    // Mapping transform rotasi kamera iPhone ke EXIF orientation
    private func getOrientation(from transform: CGAffineTransform) -> CGImagePropertyOrientation {
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            return .right
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            return .left
        } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
            return .up
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            return .down
        }
        return .up
    }
}

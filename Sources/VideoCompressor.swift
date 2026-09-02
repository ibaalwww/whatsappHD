import Foundation
import AVFoundation
import CoreMedia
import CoreImage
import ImageIO

final class VideoCompressor: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var statusMessage = "Siap memproses"
    
    func compressVideo(inputURL: URL, musicURL: URL? = nil) async throws -> URL {
        await MainActor.run {
            self.isProcessing = true
            self.progress = 0.0
            self.statusMessage = "Membaca struktur video 4K..."
        }
        
        let videoAsset = AVURLAsset(url: inputURL)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Compressor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Track video tidak ditemukan."])
        }
        
        let videoDuration = try await videoAsset.load(.duration)
        let totalDurationSeconds = CMTimeGetSeconds(videoDuration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        
        // 1. DETEKSI ORIENTASI (ANTI SALAH LANDSCAPE)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let isPortrait = abs(transformedRect.height) >= abs(transformedRect.width)
        
        let targetWidth: Int = isPortrait ? 1080 : 1920
        let targetHeight: Int = isPortrait ? 1920 : 1080
        
        // Hitung sudut rotasi EXIF
        let angle = atan2(transform.b, transform.a)
        let degrees = Int(round(angle * 180 / .pi))
        let orientation: CGImagePropertyOrientation
        switch degrees {
        case 90:
            orientation = .right
        case -90, 270:
            orientation = .left
        case 180, -180:
            orientation = .down
        default:
            orientation = .up
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PURE_60FPS_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        // 2. SETUP READER
        let reader = try AVAssetReader(asset: videoAsset)
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.alwaysCopiesSampleData = false
        if reader.canAdd(videoOutput) {
            reader.add(videoOutput)
        }
        
        // 3. SETUP AUDIO (Potong sinkron dengan durasi video)
        var audioAsset = videoAsset
        if let customMusic = musicURL {
            audioAsset = AVURLAsset(url: customMusic)
        }
        
        var audioOutput: AVAssetReaderTrackOutput? = nil
        var audioReader: AVAssetReader? = nil
        
        if let audioTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first {
            let aReader = try AVAssetReader(asset: audioAsset)
            aReader.timeRange = CMTimeRange(start: .zero, duration: videoDuration)
            
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
        
        // 4. SETUP WRITER (FORMULA PURESTATUS WA: LEVEL 4.1 & 2.8 MBPS)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetWidth,
            AVVideoHeightKey: targetHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_800_000, // 2.8 Mbps: Batas aman anti-begal WA
                AVVideoProfileLevelKey: AVVideoProfileLevelH264High41, // KUNCI UTAMA: Wajib Level 4.1
                AVVideoMaxKeyFrameIntervalKey: 60, // GOP 1 detik
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
        
        // 5. RENDERING PIPELINE
        reader.startReading()
        audioReader?.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        await MainActor.run {
            self.statusMessage = "Mengunci 60.0 FPS murni..."
        }
        
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let videoQueue = DispatchQueue(label: "videoCompressQueue")
        let audioQueue = DispatchQueue(label: "audioCompressQueue")
        let group = DispatchGroup()
        
        var isVideoDone = false
        var pendingVideoBuffer: CMSampleBuffer? = nil
        var frameIndex: Int64 = 0
        
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
                
                let forcedPTS = CMTime(value: frameIndex * 1000, timescale: 60000)
                var appendSuccess = false
                
                autoreleasepool {
                    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        pendingVideoBuffer = nil
                        return
                    }
                    
                    var ciImage = CIImage(cvPixelBuffer: imageBuffer).oriented(orientation)
                    let extent = ciImage.extent
                    let scale = max(CGFloat(targetWidth) / extent.width, CGFloat(targetHeight) / extent.height)
                    
                    ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    let offsetX = (CGFloat(targetWidth) - ciImage.extent.width) / 2.0
                    let offsetY = (CGFloat(targetHeight) - ciImage.extent.height) / 2.0
                    ciImage = ciImage.transformed(by: CGAffineTransform(
                        translationX: offsetX - ciImage.extent.origin.x,
                        y: offsetY - ciImage.extent.origin.y
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
                        appendSuccess = adaptor.append(destBuffer, withPresentationTime: forcedPTS)
                    }
                }
                
                if appendSuccess {
                    pendingVideoBuffer = nil
                    frameIndex += 1
                    
                    // Update progress bar
                    if totalDurationSeconds > 0 {
                        let currentSec = Double(frameIndex) / 60.0
                        let p = min(currentSec / totalDurationSeconds, 1.0)
                        DispatchQueue.main.async {
                            self.progress = p
                        }
                    }
                } else {
                    break
                }
            }
        }
        
        // Audio Loop
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
                    
                    let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
                    if pts >= videoDuration {
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
        
        writer.endSession(atSourceTime: videoDuration)
        await writer.finishWriting()
        
        await MainActor.run {
            self.progress = 1.0
            self.isProcessing = false
        }
        
        if writer.status == .completed {
            return outputURL
        } else {
            throw writer.error ?? NSError(domain: "Compressor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Gagal encoding video."])
        }
    }
}

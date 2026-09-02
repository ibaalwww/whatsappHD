import Foundation
import AVFoundation
import CoreMedia

final class VideoCompressor: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage = "Siap memproses"
    
    func compressVideo(inputURL: URL) async throws -> URL {
        await MainActor.run {
            self.isProcessing = true
            self.statusMessage = "Menganalisis metadata 60 FPS..."
        }
        
        let asset = AVURLAsset(url: inputURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Compressor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Track video tidak ditemukan."])
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        
        // Deteksi apakah video portrait (vertikal) atau landscape
        let isPortrait = abs(transform.b) == 1.0 && abs(transform.c) == 1.0
        let targetWidth: Int = isPortrait ? 1080 : 1920
        let targetHeight: Int = isPortrait ? 1920 : 1080
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WA_HD_60FPS_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        // 1. Setup Reader dengan Video Composition (Kunci 60 FPS murni)
        let reader = try AVAssetReader(asset: asset)
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: targetWidth, height: targetHeight)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60) // LOCK 60 FPS
        
        let instruction = AVMutableVideoCompositionInstruction()
        let duration = try await asset.load(.duration)
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        
        // Hitung scaling agar video 4K pas ke 1080p tanpa distorsi
        let sourceWidth = isPortrait ? naturalSize.height : naturalSize.width
        let sourceHeight = isPortrait ? naturalSize.width : naturalSize.height
        let scale = max(CGFloat(targetWidth) / sourceWidth, CGFloat(targetHeight) / sourceHeight)
        
        var finalTransform = transform
        if transform.b == 1.0 { // Portrait standard iPhone
            finalTransform = CGAffineTransform(rotationAngle: .pi / 2)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: CGFloat(targetWidth), y: 0))
        } else if transform.c == -1.0 { // Portrait terbalik
            finalTransform = CGAffineTransform(rotationAngle: -.pi / 2)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: 0, y: CGFloat(targetHeight)))
        } else if transform.a == -1.0 { // Landscape terbalik
            finalTransform = CGAffineTransform(rotationAngle: .pi)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: CGFloat(targetWidth), y: CGFloat(targetHeight)))
        } else { // Landscape normal
            finalTransform = CGAffineTransform(scaleX: scale, y: scale)
        }
        
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        
        if reader.canAdd(videoOutput) {
            reader.add(videoOutput)
        }
        
        // Audio Track Reader
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
        
        // 2. Setup Writer dengan Rumus Anti-Begal
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true // Faststart: Moov atom di awal file
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetWidth,
            AVVideoHeightKey: targetHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_500_000, // 4.5 Mbps (Ambang aman HD WhatsApp)
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60,   // Keyframe tiap 60 frame = Tepat 1 detik!
                AVVideoExpectedSourceFrameRateKey: 60
            ]
        ]
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        
        // Audio Writer (AAC-LC 128 kbps)
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
        
        // 3. Eksekusi Encoding Hardware-Accelerated
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        await MainActor.run {
            self.statusMessage = "Merender 1080p 60 FPS Anti-Begal..."
        }
        
        let videoQueue = DispatchQueue(label: "videoCompressQueue")
        let audioQueue = DispatchQueue(label: "audioCompressQueue")
        let group = DispatchGroup()
        
        var isVideoDone = false
        group.enter()
        videoInput.requestMediaDataWhenReady(on: videoQueue) {
            if isVideoDone { return }
            while videoInput.isReadyForMoreMediaData {
                if let buffer = videoOutput.copyNextSampleBuffer() {
                    videoInput.append(buffer)
                } else {
                    if !isVideoDone {
                        isVideoDone = true
                        videoInput.markAsFinished()
                        group.leave()
                    }
                    break
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
            throw writer.error ?? NSError(domain: "Compressor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Gagal encoding video 60 FPS."])
        }
    }
}

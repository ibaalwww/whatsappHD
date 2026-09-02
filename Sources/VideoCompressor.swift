import Foundation
import AVFoundation
import CoreMedia

final class VideoCompressor: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage = "Siap memproses"
    
    func compressVideo(inputURL: URL) async throws -> URL {
        await MainActor.run {
            self.isProcessing = true
            self.statusMessage = "Menganalisis stream video murni..."
        }
        
        let asset = AVURLAsset(url: inputURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Compressor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Track video tidak ditemukan."])
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        
        let isPortrait = abs(transform.b) == 1.0 && abs(transform.c) == 1.0
        let targetWidth: Int = isPortrait ? 1080 : 1920
        let targetHeight: Int = isPortrait ? 1920 : 1080
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WA_HD_60FPS_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        // 1. Setup Reader dengan Clock 60 Hz Mandiri
        let reader = try AVAssetReader(asset: asset)
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: targetWidth, height: targetHeight)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)
        
        let instruction = AVMutableVideoCompositionInstruction()
        let duration = try await asset.load(.duration)
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        let sourceWidth = isPortrait ? naturalSize.height : naturalSize.width
        let sourceHeight = isPortrait ? naturalSize.width : naturalSize.height
        let scale = max(CGFloat(targetWidth) / sourceWidth, CGFloat(targetHeight) / sourceHeight)
        
        var finalTransform = transform
        if transform.b == 1.0 {
            finalTransform = CGAffineTransform(rotationAngle: .pi / 2)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: CGFloat(targetWidth), y: 0))
        } else if transform.c == -1.0 {
            finalTransform = CGAffineTransform(rotationAngle: -.pi / 2)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: 0, y: CGFloat(targetHeight)))
        } else if transform.a == -1.0 {
            finalTransform = CGAffineTransform(rotationAngle: .pi)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: CGFloat(targetWidth), y: CGFloat(targetHeight)))
        } else {
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
        
        // Audio Track
        var audioOutput: AVAssetReaderTrackOutput? = nil
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
            let aOut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            aOut.alwaysCopiesSampleData = false
            if reader.canAdd(aOut) {
                reader.add(aOut)
                audioOutput = aOut
            }
        }
        
        // 2. Setup Writer dengan Konfigurasi Level H.264 Tinggi (High 5.1)
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
        
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        await MainActor.run {
            self.statusMessage = "Mengunci 60 frame per detik..."
        }
        
        let videoQueue = DispatchQueue(label: "videoCompressQueue")
        let audioQueue = DispatchQueue(label: "audioCompressQueue")
        let group = DispatchGroup()
        
        var isVideoDone = false
        var frameIndex: Int64 = 0
        
        group.enter()
        videoInput.requestMediaDataWhenReady(on: videoQueue) {
            if isVideoDone { return }
            while videoInput.isReadyForMoreMediaData {
                if let buffer = videoOutput.copyNextSampleBuffer() {
                    // Paksa setiap frame memiliki durasi tepat 1/60 detik
                    var timingInfo = CMSampleTimingInfo(
                        duration: CMTime(value: 1000, timescale: 60000),
                        presentationTimeStamp: CMTime(value: frameIndex * 1000, timescale: 60000),
                        decodeTimeStamp: .invalid
                    )
                    var retimedBuffer: CMSampleBuffer?
                    CMSampleBufferCreateCopyWithNewTiming(
                        allocator: kCFAllocatorDefault,
                        sampleBuffer: buffer,
                        numSampleTimingEntries: 1,
                        sampleTimingArray: &timingInfo,
                        sampleBufferOut: &retimedBuffer
                    )
                    
                    if let validBuffer = retimedBuffer {
                        videoInput.append(validBuffer)
                    } else {
                        videoInput.append(buffer)
                    }
                    frameIndex += 1
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
            throw writer.error ?? NSError(domain: "Compressor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Gagal encoding 60 FPS."])
        }
    }
}

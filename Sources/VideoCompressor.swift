import Foundation
import AVFoundation
import CoreMedia

final class VideoCompressor: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var statusMessage = "Siap memproses"
    
    func compressVideo(inputURL: URL, musicURL: URL? = nil) async throws -> URL {
        await MainActor.run {
            self.isProcessing = true
            self.progress = 0.0
            self.statusMessage = "Mengaktifkan Engine 720p 60 FPS..."
        }
        
        let videoAsset = AVURLAsset(url: inputURL)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Compressor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Track video tidak ditemukan."])
        }
        
        let videoDuration = try await videoAsset.load(.duration)
        let totalDurationSeconds = CMTimeGetSeconds(videoDuration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        
        // Deteksi Orientasi & Paksa ke 720p (720x1280 untuk Portrait agar lolos sensor WA)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let isPortrait = abs(transformedRect.height) >= abs(transformedRect.width)
        let targetWidth: Int = isPortrait ? 720 : 1280
        let targetHeight: Int = isPortrait ? 1280 : 720
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iBaal_720p60_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        // 1. SETUP READER
        let reader = try AVAssetReader(asset: videoAsset)
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)
        videoComposition.renderSize = CGSize(width: targetWidth, height: targetHeight)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: videoDuration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        let scale = max(CGFloat(targetWidth) / abs(transformedRect.width), CGFloat(targetHeight) / abs(transformedRect.height))
        var finalTransform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        
        let postWidth = abs(transformedRect.width) * scale
        let postHeight = abs(transformedRect.height) * scale
        let offsetX = (CGFloat(targetWidth) - postWidth) / 2.0
        let offsetY = (CGFloat(targetHeight) - postHeight) / 2.0
        finalTransform = finalTransform.concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
        
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
        
        // Audio Reader Setup
        var audioAsset = videoAsset
        if let customMusic = musicURL {
            audioAsset = AVURLAsset(url: customMusic)
        }
        
        var audioOutput: AVAssetReaderTrackOutput? = nil
        var audioReader: AVAssetReader? = nil
        
        if let audioTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first {
            let aReader = try AVAssetReader(asset: audioAsset)
            aReader.timeRange = CMTimeRange(start: .zero, duration: videoDuration)
            let aOut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            aOut.alwaysCopiesSampleData = false
            if aReader.canAdd(aOut) {
                aReader.add(aOut)
                audioOutput = aOut
                audioReader = aReader
            }
        }
        
        // 2. SETUP WRITER (Bitrate diturunkan ke 1.8 Mbps agar ramah server WhatsApp)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetWidth,
            AVVideoHeightKey: targetHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_800_000, // 1.8 Mbps untuk 720p 60 FPS
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
                AVEncoderBitRateKey: 96_000
            ]
            let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aIn.expectsMediaDataInRealTime = false
            if writer.canAdd(aIn) {
                writer.add(aIn)
                audioInput = aIn
            }
        }
        
        // 3. EKSEKUSI RENDER
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "Compressor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Gagal memulai reader."])
        }
        audioReader?.startReading()
        
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "Compressor", code: -3, userInfo: [NSLocalizedDescriptionKey: "Gagal memulai writer."])
        }
        writer.startSession(atSourceTime: .zero)
        
        let videoQueue = DispatchQueue(label: "iBaalVideoQueue720", qos: .userInitiated)
        let audioQueue = DispatchQueue(label: "iBaalAudioQueue720", qos: .userInitiated)
        let group = DispatchGroup()
        
        var frameIndex: Int64 = 0
        var isVideoFinished = false
        
        group.enter()
        videoInput.requestMediaDataWhenReady(on: videoQueue) {
            while videoInput.isReadyForMoreMediaData {
                if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                    var timingInfo = CMSampleTimingInfo(
                        duration: CMTime(value: 1000, timescale: 60000),
                        presentationTimeStamp: CMTime(value: frameIndex * 1000, timescale: 60000),
                        decodeTimeStamp: .invalid
                    )
                    
                    var modifiedBuffer: CMSampleBuffer?
                    CMSampleBufferCreateCopyWithNewTiming(
                        allocator: kCFAllocatorDefault,
                        sampleBuffer: sampleBuffer,
                        numSampleTimingEntries: 1,
                        sampleTimingArray: &timingInfo,
                        sampleBufferOut: &modifiedBuffer
                    )
                    
                    if let validBuffer = modifiedBuffer {
                        videoInput.append(validBuffer)
                    } else {
                        videoInput.append(sampleBuffer)
                    }
                    
                    frameIndex += 1
                    
                    if totalDurationSeconds > 0 && frameIndex % 10 == 0 {
                        let currentSec = Double(frameIndex) / 60.0
                        let p = min(currentSec / totalDurationSeconds, 0.99)
                        DispatchQueue.main.async {
                            self.progress = p
                        }
                    }
                } else {
                    if !isVideoFinished {
                        isVideoFinished = true
                        videoInput.markAsFinished()
                        group.leave()
                    }
                    break
                }
            }
        }
        
        var isAudioFinished = false
        if let aIn = audioInput, let aOut = audioOutput {
            group.enter()
            aIn.requestMediaDataWhenReady(on: audioQueue) {
                while aIn.isReadyForMoreMediaData {
                    if let audioBuffer = aOut.copyNextSampleBuffer() {
                        let pts = CMSampleBufferGetPresentationTimeStamp(audioBuffer)
                        if pts >= videoDuration {
                            if !isAudioFinished {
                                isAudioFinished = true
                                aIn.markAsFinished()
                                group.leave()
                            }
                            break
                        }
                        aIn.append(audioBuffer)
                    } else {
                        if !isAudioFinished {
                            isAudioFinished = true
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
        
        writer.endSession(atSourceTime: videoDuration)
        await writer.finishWriting()
        
        await MainActor.run {
            self.progress = 1.0
            self.isProcessing = false
        }
        
        if writer.status == .completed {
            return outputURL
        } else {
            throw writer.error ?? NSError(domain: "Compressor", code: -4, userInfo: [NSLocalizedDescriptionKey: "Gagal encoding 720p: \(writer.error?.localizedDescription ?? "Unknown")"])
        }
    }
}

import Foundation
import AVFoundation
import CoreMedia

final class VideoCompressor: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var statusMessage = "Siap memproses"
    
    private var exportSession: AVAssetExportSession?
    private var timer: Timer?
    
    func compressVideo(inputURL: URL, musicURL: URL? = nil) async throws -> URL {
        await MainActor.run {
            self.isProcessing = true
            self.progress = 0.0
            self.statusMessage = "Menyiapkan engine iBaal 60 FPS..."
        }
        
        let videoAsset = AVURLAsset(url: inputURL)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Compressor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Track video tidak ditemukan."])
        }
        
        let composition = AVMutableComposition()
        let videoDuration = try await videoAsset.load(.duration)
        
        // Injeksi Track Video
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "Compressor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Gagal membuat track video."])
        }
        try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
        
        // Injeksi Audio (Musik Kustom atau Suara Asli)
        var audioSourceAsset = videoAsset
        if let customMusic = musicURL {
            audioSourceAsset = AVURLAsset(url: customMusic)
        }
        
        if let audioTrack = try? await audioSourceAsset.loadTracks(withMediaType: .audio).first {
            if let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let audioDuration = min(videoDuration, try await audioSourceAsset.load(.duration))
                try? compAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: audioDuration), of: audioTrack, at: .zero)
            }
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let isPortrait = abs(transformedRect.height) >= abs(transformedRect.width)
        
        let renderWidth: CGFloat = isPortrait ? 1080 : 1920
        let renderHeight: CGFloat = isPortrait ? 1920 : 1080
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60) // Kunci 60 FPS
        videoComposition.renderSize = CGSize(width: renderWidth, height: renderHeight)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: videoDuration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
        
        let scale = max(renderWidth / abs(transformedRect.width), renderHeight / abs(transformedRect.height))
        var finalTransform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        
        let postWidth = abs(transformedRect.width) * scale
        let postHeight = abs(transformedRect.height) * scale
        let offsetX = (renderWidth - postWidth) / 2.0
        let offsetY = (renderHeight - postHeight) / 2.0
        finalTransform = finalTransform.concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
        
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iBaal_60FPS_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "Compressor", code: -3, userInfo: [NSLocalizedDescriptionKey: "Gagal membuat sesi ekspor."])
        }
        
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = videoComposition
        
        self.exportSession = session
        
        await MainActor.run {
            self.statusMessage = "Merender video 60 FPS..."
            self.startProgressTracking()
        }
        
        await session.export()
        
        await MainActor.run {
            self.stopProgressTracking()
            self.isProcessing = false
            self.progress = 1.0
        }
        
        if session.status == .completed {
            return outputURL
        } else {
            throw session.error ?? NSError(domain: "Compressor", code: -4, userInfo: [NSLocalizedDescriptionKey: "Gagal ekspor: \(session.error?.localizedDescription ?? "Batal")"])
        }
    }
    
    private func startProgressTracking() {
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let session = self.exportSession else { return }
            DispatchQueue.main.async {
                self.progress = Double(session.progress)
            }
        }
    }
    
    private func stopProgressTracking() {
        self.timer?.invalidate()
        self.timer = nil
    }
}

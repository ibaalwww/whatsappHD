import Foundation
import AVFoundation

final class VideoCompressor: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage = "Siap memproses"
    
    func compressVideo(inputURL: URL) async throws -> URL {
        await MainActor.run {
            self.isProcessing = true
            self.statusMessage = "Menganalisis resolusi 4K..."
        }
        
        let asset = AVURLAsset(url: inputURL)
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPreset1920x1080
        ) else {
            throw NSError(domain: "Compressor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Gagal inisialisasi engine."])
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WA_HD_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        await MainActor.run {
            self.statusMessage = "Mengompresi ke 1080p Anti-Begal..."
        }
        
        await exportSession.export()
        
        await MainActor.run {
            self.isProcessing = false
        }
        
        if exportSession.status == .completed {
            return outputURL
        } else {
            throw exportSession.error ?? NSError(domain: "Compressor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Gagal ekspor video."])
        }
    }
}

import SwiftUI
import UIKit
import Photos
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var compressor = VideoCompressor()
    @State private var showVideoPicker = false
    @State private var showMusicPicker = false
    
    @State private var selectedVideoURL: URL? = nil
    @State private var selectedMusicURL: URL? = nil
    @State private var processedVideoURL: URL? = nil
    @State private var showShareSheet = false
    @State private var videoInfoText: String? = nil
    @State private var saveMessage: String? = nil
    
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 4) {
                    Text("STATUS PURIFIER")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.white)
                    Text("TRUE 1080P 60 FPS ENGINE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                }
                .padding(.top, 24)
                
                // Status Box
                VStack(spacing: 12) {
                    if compressor.isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.83, green: 0.68, blue: 0.21)))
                            .scaleEffect(1.4)
                        Text(compressor.statusMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else if processedVideoURL != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 42))
                            .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                        Text("RENDER 60 FPS SUKSES")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("1080x1920 • 60.0 FPS • 3.0 Mbps")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray)
                    } else {
                        Image(systemName: "video.badge.waveform")
                            .font(.system(size: 42))
                            .foregroundColor(.gray)
                        Text(videoInfoText ?? "PILIH MASTER VIDEO 4K")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(Color(red: 0.08, green: 0.09, blue: 0.11))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 20)
                
                // Panel Musik
                HStack {
                    Image(systemName: "music.note")
                        .foregroundColor(selectedMusicURL != nil ? Color(red: 0.83, green: 0.68, blue: 0.21) : .gray)
                    if let music = selectedMusicURL {
                        Text(music.lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Button(action: { selectedMusicURL = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    } else {
                        Text("Tambahkan Musik (Opsional)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Button("Pilih") {
                            showMusicPicker = true
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Color(red: 0.08, green: 0.09, blue: 0.11))
                .cornerRadius(12)
                .padding(.horizontal, 20)
                
                // Panduan Trik Status WA
                VStack(alignment: .leading, spacing: 4) {
                    Text("💡 TIPS AGAR TIDAK DI-COMPRESS WA:")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                    Text("1. Simpan video ke Galeri.\n2. Kirim ke Chat Sendiri (You) dengan tombol [HD] aktif.\n3. Teruskan (Forward) ke Status Saya.")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.03))
                .cornerRadius(10)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Tombol Aksi
                VStack(spacing: 12) {
                    if let outputURL = processedVideoURL {
                        Button(action: { requestSaveToGallery(url: outputURL) }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text(saveMessage ?? "SIMPAN KE GALERI (60 FPS)")
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(red: 0.83, green: 0.68, blue: 0.21))
                            .cornerRadius(12)
                        }
                        
                        Button(action: { showShareSheet = true }) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("BAGIKAN VIA SHARE SHEET")
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(red: 0.13, green: 0.15, blue: 0.18))
                            .cornerRadius(12)
                        }
                    }
                    
                    Button(action: { showVideoPicker = true }) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(selectedVideoURL == nil ? "IMPORT VIDEO 4K" : "GANTI VIDEO MASTER")
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(red: 0.16, green: 0.18, blue: 0.22))
                        .cornerRadius(12)
                    }
                    .disabled(compressor.isProcessing)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showVideoPicker) {
            NativeVideoPicker { url in
                selectedVideoURL = url
                saveMessage = nil
                Task {
                    let asset = AVURLAsset(url: url)
                    if let track = try? await asset.loadTracks(withMediaType: .video).first,
                       let size = try? await track.load(.naturalSize),
                       let fps = try? await track.load(.nominalFrameRate) {
                        await MainActor.run {
                            self.videoInfoText = "\(Int(size.width))x\(Int(size.height)) • \(Int(round(fps))) FPS"
                        }
                    }
                    startProcessing()
                }
            }
        }
        .sheet(isPresented: $showMusicPicker) {
            AudioPicker { url in
                selectedMusicURL = url
                saveMessage = nil
                if selectedVideoURL != nil {
                    startProcessing()
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = processedVideoURL {
                ShareSheet(activityItems: [url])
            }
        }
    }
    
    private func startProcessing() {
        guard let videoURL = selectedVideoURL else { return }
        Task {
            do {
                let result = try await compressor.compressVideo(
                    inputURL: videoURL,
                    musicURL: selectedMusicURL
                )
                await MainActor.run {
                    self.processedVideoURL = result
                }
            } catch {
                await MainActor.run {
                    self.compressor.statusMessage = "Gagal: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func requestSaveToGallery(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                if status == .authorized || status == .limited {
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    }) { success, error in
                        DispatchQueue.main.async {
                            if success {
                                self.saveMessage = "BERHASIL DISIMPAN KE GALERI! ✓"
                            } else {
                                self.saveMessage = "GAGAL SIMPAN: \(error?.localizedDescription ?? "")"
                            }
                        }
                    }
                } else {
                    self.saveMessage = "IZIN GALERI DITOLAK!"
                }
            }
        }
    }
}

struct NativeVideoPicker: UIViewControllerRepresentable {
    var onVideoPicked: (URL) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: NativeVideoPicker

        init(_ parent: NativeVideoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()
            guard let provider = results.first?.itemProvider else { return }

            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let sourceURL = url else { return }
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("RAW_\(UUID().uuidString)_\(sourceURL.lastPathComponent)")
                try? FileManager.default.copyItem(at: sourceURL, to: temp)
                DispatchQueue.main.async {
                    self.parent.onVideoPicked(temp)
                }
            }
        }
    }
}

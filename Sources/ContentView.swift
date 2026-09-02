import SwiftUI
import UIKit
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
    @State private var saveStatusAlert = false
    @State private var saveStatusMessage = ""
    
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.08).ignoresSafeArea()
            
            VStack(spacing: 14) {
                // Header Bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PURESTATUS 60 FPS")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("ANTI-COMPRESSION BYPASS ENGINE")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                    }
                    Spacer()
                    Image(systemName: "bolt.badge.checkmark.fill")
                        .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                        .font(.system(size: 20))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                // Box Pratinjau & Status
                VStack(spacing: 12) {
                    if compressor.isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.83, green: 0.68, blue: 0.21)))
                            .scaleEffect(1.3)
                        
                        Text(compressor.statusMessage)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white)
                        
                        // Progress Bar Dinamis
                        ProgressView(value: compressor.progress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 0.83, green: 0.68, blue: 0.21)))
                            .frame(height: 6)
                            .padding(.horizontal, 30)
                        
                        Text("\(Int(compressor.progress * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                    } else if processedVideoURL != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                        Text("READY UNTUK STATUS WA")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("1080x1920 • 60 FPS Murni • H.264 Level 4.1")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray)
                    } else {
                        Image(systemName: "video.badge.waveform")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.8))
                        Text(videoInfoText ?? "PILIH MASTER VIDEO 4K")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(Color(red: 0.09, green: 0.10, blue: 0.13))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 20)
                
                // Pilihan Musik
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
                        Text("Tambahkan Musik Latar (Opsional)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Button("Pilih File") {
                            showMusicPicker = true
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color(red: 0.09, green: 0.10, blue: 0.13))
                .cornerRadius(10)
                .padding(.horizontal, 20)
                
                // Panduan Trik PureStatus
                VStack(alignment: .leading, spacing: 4) {
                    Text("💡 RAHASIA STATUS 60 FPS MULUS:")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                    Text("1. Simpan video ke Galeri.\n2. Buka WA, kirim ke chat sendiri (You) dengan tombol [HD].\n3. Tahan video di chat > Teruskan (Forward) ke Status Saya.")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.03))
                .cornerRadius(10)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Tombol Aksi Bawah
                VStack(spacing: 10) {
                    if let outputURL = processedVideoURL {
                        Button(action: { saveVideoSafely(url: outputURL) }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text("SIMPAN KE GALERI (FOTO)")
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(red: 0.83, green: 0.68, blue: 0.21))
                            .cornerRadius(10)
                        }
                        
                        Button(action: { showShareSheet = true }) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("BAGIKAN LANGSUNG")
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(red: 0.13, green: 0.15, blue: 0.18))
                            .cornerRadius(10)
                        }
                    }
                    
                    Button(action: { showVideoPicker = true }) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(selectedVideoURL == nil ? "IMPORT VIDEO MASTER 4K" : "GANTI VIDEO")
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 0.18, green: 0.20, blue: 0.24))
                        .cornerRadius(10)
                    }
                    .disabled(compressor.isProcessing)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .alert(isPresented: $saveStatusAlert) {
            Alert(title: Text("Galeri"), message: Text(saveStatusMessage), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showVideoPicker) {
            NativeVideoPicker { url in
                selectedVideoURL = url
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
    
    // Simpan native anti-crash (kebal crash SIGABRT)
    private func saveVideoSafely(url: URL) {
        let saver = VideoSaver()
        saver.onSuccess = {
            self.saveStatusMessage = "Berhasil disimpan ke Galeri! ✓ (Tersimpan murni 60 FPS)"
            self.saveStatusAlert = true
        }
        saver.onError = { error in
            self.saveStatusMessage = "Gagal simpan: \(error.localizedDescription)"
            self.saveStatusAlert = true
        }
        saver.save(url: url)
    }
}

// Helper penyimpanan UIKit
class VideoSaver: NSObject {
    var onSuccess: (() -> Void)?
    var onError: ((Error) -> Void)?

    func save(url: URL) {
        UISaveVideoAtPathToSavedPhotosAlbum(url.path, self, #selector(video(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc func video(_ videoPath: String, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        DispatchQueue.main.async {
            if let err = error {
                self.onError?(err)
            } else {
                self.onSuccess?()
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

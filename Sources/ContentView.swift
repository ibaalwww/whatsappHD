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
    @State private var videoDetails: String? = nil
    @State private var alertMessage: String? = nil
    @State private var showAlert = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background hitam pekat AMOLED
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 1. TOP BAR
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("STATUS PURIFIER")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("60 FPS ULTRA COMPRESSOR")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.18, green: 0.80, blue: 0.44)) // WhatsApp Green
                        }
                        Spacer()
                        
                        // Badge HD
                        HStack(spacing: 4) {
                            Circle()
                                .fill(processedVideoURL != nil ? Color.green : Color.gray)
                                .frame(width: 7, height: 7)
                            Text("HD 60")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(20)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    Spacer()
                    
                    // 2. MAIN PREVIEW CARD (CENTER)
                    VStack(spacing: 16) {
                        if compressor.isProcessing {
                            // Tampilan Processing
                            VStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.1), lineWidth: 6)
                                        .frame(width: 80, height: 80)
                                    Circle()
                                        .trim(from: 0, to: compressor.progress)
                                        .stroke(Color(red: 0.18, green: 0.80, blue: 0.44), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                        .frame(width: 80, height: 80)
                                        .rotationEffect(.degrees(-90))
                                        .animation(.linear, value: compressor.progress)
                                    
                                    Text("\(Int(compressor.progress * 100))%")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                
                                Text(compressor.statusMessage)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                        } else if processedVideoURL != nil {
                            // Tampilan Video Sukses Siap Kirim
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 54))
                                    .foregroundColor(Color(red: 0.18, green: 0.80, blue: 0.44))
                                
                                Text("VIDEO SIAP DIPASANG")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("1080x1920 • 60 FPS • High Profile 4.1")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                        } else {
                            // Tampilan Idle (Belum pilih video)
                            Button(action: { showVideoPicker = true }) {
                                VStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.06))
                                            .frame(width: 74, height: 74)
                                        Image(systemName: "video.badge.plus")
                                            .font(.system(size: 32))
                                            .foregroundColor(.white)
                                    }
                                    
                                    Text("PILIH VIDEO MASTER 4K")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                    
                                    Text(videoDetails ?? "Mendukung 4K 60 FPS Camera")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: geo.size.height * 0.38)
                    .background(Color(red: 0.09, green: 0.10, blue: 0.12))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    
                    // 3. OPTIONAL MUSIC BAR
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundColor(selectedMusicURL != nil ? Color.green : .gray)
                        
                        if let music = selectedMusicURL {
                            Text(music.lastPathComponent)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            Button(action: { selectedMusicURL = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        } else {
                            Text("Ganti Musik Latar (Opsional)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.gray)
                            Spacer()
                            Button("Pilih") {
                                showMusicPicker = true
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.18, green: 0.80, blue: 0.44))
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Color(red: 0.09, green: 0.10, blue: 0.12))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    
                    Spacer()
                    
                    // 4. ACTION BUTTONS (BOTTOM)
                    VStack(spacing: 10) {
                        if let outputURL = processedVideoURL {
                            // Tombol Simpan ke Galeri (Native Anti-Crash)
                            Button(action: { saveVideoSafely(url: outputURL) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.down.fill")
                                    Text("SIMPAN KE GALERI FOTO")
                                }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color(red: 0.18, green: 0.80, blue: 0.44))
                                .cornerRadius(14)
                            }
                            
                            // Tombol Share Sheet Langsung
                            Button(action: { showShareSheet = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "paperplane.fill")
                                    Text("BAGIKAN KE CHAT / STATUS")
                                }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(14)
                            }
                        }
                        
                        // Tombol Ganti / Pilih Video
                        Button(action: { showVideoPicker = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle")
                                Text(processedVideoURL == nil ? "IMPORT DARI GALERI" : "PILIH VIDEO LAIN")
                            }
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(red: 0.14, green: 0.16, blue: 0.20))
                            .cornerRadius(14)
                        }
                        .disabled(compressor.isProcessing)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom : 20)
                }
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Info"), message: Text(alertMessage ?? ""), dismissButton: .default(Text("OK")))
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
                            self.videoDetails = "\(Int(size.width))x\(Int(size.height)) @ \(Int(round(fps))) FPS"
                        }
                    }
                    startCompression()
                }
            }
        }
        .sheet(isPresented: $showMusicPicker) {
            AudioPicker { url in
                selectedMusicURL = url
                if selectedVideoURL != nil {
                    startCompression()
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = processedVideoURL {
                ShareSheet(activityItems: [url])
            }
        }
    }
    
    private func startCompression() {
        guard let url = selectedVideoURL else { return }
        Task {
            do {
                let result = try await compressor.compressVideo(inputURL: url, musicURL: selectedMusicURL)
                await MainActor.run {
                    self.processedVideoURL = result
                }
            } catch {
                await MainActor.run {
                    self.alertMessage = "Gagal memproses: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }
    
    private func saveVideoSafely(url: URL) {
        let saver = VideoSaver()
        saver.onSuccess = {
            self.alertMessage = "Video 60 FPS berhasil disimpan ke Galeri! ✓"
            self.showAlert = true
        }
        saver.onError = { error in
            self.alertMessage = "Gagal simpan: \(error.localizedDescription)"
            self.showAlert = true
        }
        saver.save(url: url)
    }
}

// UIKit Safe Video Saver (Anti Crash)
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

// Native Video Picker (Force Raw Original)
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

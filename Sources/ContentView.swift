import SwiftUI
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
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header Ringkas
                VStack(spacing: 4) {
                    Text("STATUS PURIFIER")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(2)
                    Text("ANTI-BEGAL 1080P 60 FPS")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 16)
                
                // Card Pratinjau & Status
                VStack(spacing: 12) {
                    if compressor.isProcessing {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(compressor.statusMessage)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else if processedVideoURL != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("VIDEO SIAP UNGGAH")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                        Text("1080x1920 • 60 FPS • 3.0 Mbps")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "video.badge.waveform")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text(videoInfoText ?? "Pilih Master Video 4K")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal, 20)
                
                // Panel Musik Tambahan (Opsional)
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundColor(.secondary)
                        if let music = selectedMusicURL {
                            Text(music.lastPathComponent)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Button(action: { selectedMusicURL = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Musik Latar (Opsional)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Pilih") {
                                showMusicPicker = true
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Tombol Aksi
                VStack(spacing: 10) {
                    if processedVideoURL != nil {
                        Button(action: { showShareSheet = true }) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("BAGIKAN KE WHATSAPP")
                            }
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.green)
                            .cornerRadius(10)
                        }
                    }
                    
                    if selectedVideoURL != nil && !compressor.isProcessing {
                        Button(action: { startProcessing() }) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                Text("PROSES ULANG SEKARANG")
                            }
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                    }
                    
                    Button(action: { showVideoPicker = true }) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(selectedVideoURL == nil ? "IMPORT VIDEO 4K" : "GANTI VIDEO")
                        }
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                    .disabled(compressor.isProcessing)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
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
                    self.showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    self.compressor.statusMessage = "Gagal: \(error.localizedDescription)"
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

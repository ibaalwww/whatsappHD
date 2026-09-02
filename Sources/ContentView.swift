import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var compressor = VideoCompressor()
    @State private var showPicker = false
    @State private var processedVideoURL: URL? = nil
    @State private var showShareSheet = false
    @State private var sourceVideoInfo: String? = nil
    
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea()
            
            VStack(spacing: 28) {
                // Header
                VStack(spacing: 6) {
                    Text("STATUS // PURIFIER")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.white)
                    
                    Text("LOCK 60 FPS PURIFIER ENGINE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Status Viewer Box
                VStack(spacing: 16) {
                    if compressor.isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.83, green: 0.68, blue: 0.21)))
                            .scaleEffect(1.5)
                        
                        Text(compressor.statusMessage)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else if processedVideoURL != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48))
                            .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                        
                        Text("1080P 60 FPS SIAP DIUNGGAH")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        
                        if let info = sourceVideoInfo {
                            Text("SUMBER: \(info)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    } else {
                        Image(systemName: "video.badge.waveform")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("PILIH MASTER 4K 60 FPS")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .background(Color(red: 0.08, green: 0.09, blue: 0.11))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    if processedVideoURL != nil {
                        Button(action: { showShareSheet = true }) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("BAGIKAN KE WHATSAPP")
                            }
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(red: 0.83, green: 0.68, blue: 0.21))
                            .cornerRadius(12)
                        }
                    }
                    
                    Button(action: { showPicker = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text(processedVideoURL == nil ? "IMPORT VIDEO DARI FOTO" : "GANTI VIDEO LAIN")
                        }
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(red: 0.12, green: 0.14, blue: 0.17))
                        .cornerRadius(12)
                    }
                    .disabled(compressor.isProcessing)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showPicker) {
            NativeVideoPicker { rawVideoURL in
                Task {
                    do {
                        let asset = AVURLAsset(url: rawVideoURL)
                        if let track = try? await asset.loadTracks(withMediaType: .video).first,
                           let size = try? await track.load(.naturalSize),
                           let fps = try? await track.load(.nominalFrameRate) {
                            await MainActor.run {
                                self.sourceVideoInfo = "\(Int(size.width))x\(Int(size.height)) @ \(Int(round(fps))) FPS"
                            }
                        }
                        
                        let resultURL = try await compressor.compressVideo(inputURL: rawVideoURL)
                        await MainActor.run {
                            self.processedVideoURL = resultURL
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
        .sheet(isPresented: $showShareSheet) {
            if let url = processedVideoURL {
                ShareSheet(activityItems: [url])
            }
        }
    }
}

// Native Picker yang memaksa iOS memberikan berkas asli (tanpa downscale ke 30 FPS)
struct NativeVideoPicker: UIViewControllerRepresentable {
    var onVideoPicked: (URL) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        // KUNCI EMAS: Menolak transcode otomatis Apple!
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

            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                guard let sourceURL = url else { return }
                let tempDir = FileManager.default.temporaryDirectory
                let targetURL = tempDir.appendingPathComponent("RAW_\(UUID().uuidString)_\(sourceURL.lastPathComponent)")
                try? FileManager.default.copyItem(at: sourceURL, to: targetURL)
                
                DispatchQueue.main.async {
                    self.parent.onVideoPicked(targetURL)
                }
            }
        }
    }
}

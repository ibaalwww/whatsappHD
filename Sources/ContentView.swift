import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var compressor = VideoCompressor()
    @State private var showPicker = false
    @State private var processedVideoURL: URL? = nil
    @State private var showShareSheet = false
    @State private var sourceVideoInfo: String? = nil
    @State private var fitToWhatsAppScreen = true // Mode Anti-Zoom WA bawaan aktif
    
    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.08).ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header Minimalis
                VStack(spacing: 4) {
                    Text("STATUS PURIFIER")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2.5)
                        .foregroundColor(.white)
                    
                    Text("60 FPS • 1080P MASTER ENGINE")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                }
                .padding(.top, 24)
                
                Spacer()
                
                // Status Box Ramping
                VStack(spacing: 12) {
                    if compressor.isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.83, green: 0.68, blue: 0.21)))
                            .scaleEffect(1.2)
                        
                        Text(compressor.statusMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    } else if processedVideoURL != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 36))
                            .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                        
                        Text("1080P 60 FPS SIAP STATUS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        
                        if let info = sourceVideoInfo {
                            Text(info)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    } else {
                        Image(systemName: "video.badge.waveform")
                            .font(.system(size: 36))
                            .foregroundColor(.gray.opacity(0.8))
                        
                        Text("PILIH VIDEO DARI GALERI")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(Color(red: 0.10, green: 0.11, blue: 0.13))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                
                // Switch Anti-Zoom WhatsApp
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $fitToWhatsAppScreen) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MODE ANTI-ZOOM WHATSAPP")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text("Cegah video terpotong/di-crop oleh status WA")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.83, green: 0.68, blue: 0.21)))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 10) {
                    if processedVideoURL != nil {
                        Button(action: { showShareSheet = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "paperplane.fill")
                                Text("BAGIKAN KE WHATSAPP")
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(red: 0.83, green: 0.68, blue: 0.21))
                            .cornerRadius(10)
                        }
                    }
                    
                    Button(action: { showPicker = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                            Text(processedVideoURL == nil ? "IMPORT VIDEO DARI FOTO" : "GANTI VIDEO LAIN")
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 0.14, green: 0.16, blue: 0.19))
                        .cornerRadius(10)
                    }
                    .disabled(compressor.isProcessing)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
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
                                self.sourceVideoInfo = "\(Int(size.width))x\(Int(size.height)) • \(Int(round(fps))) FPS"
                            }
                        }
                        
                        let resultURL = try await compressor.compressVideo(
                            inputURL: rawVideoURL,
                            fitWhatsAppScreen: fitToWhatsAppScreen
                        )
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

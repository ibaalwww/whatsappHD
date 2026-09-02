import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var compressor = VideoCompressor()
    @State private var selectedPickerItem: PhotosPickerItem? = nil
    @State private var processedVideoURL: URL? = nil
    @State private var showShareSheet = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea()
            
            VStack(spacing: 32) {
                VStack(spacing: 6) {
                    Text("STATUS // PURIFIER")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.white)
                    
                    Text("ALGORITMA ANTI-KOMPRESI WHATSAPP")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                }
                .padding(.top, 40)
                
                Spacer()
                
                VStack(spacing: 16) {
                    if compressor.isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.83, green: 0.68, blue: 0.21)))
                            .scaleEffect(1.5)
                        Text(compressor.statusMessage)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                    } else if processedVideoURL != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48))
                            .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                        Text("VIDEO SIAP DIJADIKAN STATUS")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "video.badge.waveform")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("PILIH VIDEO 4K DARI GALERI")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .background(Color(red: 0.08, green: 0.09, blue: 0.11))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 24)
                
                Spacer()
                
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
                    
                    PhotosPicker(selection: $selectedPickerItem, matching: .videos) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text(processedVideoURL == nil ? "IMPORT VIDEO 4K" : "GANTI VIDEO LAIN")
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
        .onChange(of: selectedPickerItem) { newItem in
            guard let item = newItem else { return }
            Task {
                do {
                    if let movie = try await item.loadTransferable(type: MovieTransfer.self) {
                        let resultURL = try await compressor.compressVideo(inputURL: movie.url)
                        await MainActor.run {
                            self.processedVideoURL = resultURL
                            self.showShareSheet = true
                        }
                    }
                } catch {
                    self.errorMessage = error.localizedDescription
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

struct MovieTransfer: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}
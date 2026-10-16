import SwiftUI
import Vision
import VisionKit
import PDFKit
import ImageIO

enum VisionTools {
    static func recognize(_ image: UIImage) async throws -> String {
        guard let cg = image.cgImage else { return "" }
        let orientation:CGImagePropertyOrientation
        switch image.imageOrientation {
        case .up: orientation = .up
        case .down: orientation = .down
        case .left: orientation = .left
        case .right: orientation = .right
        case .upMirrored: orientation = .upMirrored
        case .downMirrored: orientation = .downMirrored
        case .leftMirrored: orientation = .leftMirrored
        case .rightMirrored: orientation = .rightMirrored
        @unknown default: orientation = .up
        }
        return try await Task.detached(priority:.userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["it-IT","en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage:cg,orientation:orientation,options:[:]).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator:"\n")
        }.value
    }
    static func pdfPageText(_ page: PDFPage) async throws -> String {
        if let text = page.string, text.trimmingCharacters(in:.whitespacesAndNewlines).count > 10 { return text }
        let image = page.thumbnail(of:CGSize(width:1400,height:1900),for:.mediaBox)
        return try await recognize(image)
    }
}

@MainActor struct BoardScanner: UIViewControllerRepresentable {
    var onImages: ([UIImage]) -> Void
    var onError: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context:Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ controller:VNDocumentCameraViewController,context:Context) {}
    @MainActor final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: BoardScanner
        init(_ parent:BoardScanner) { self.parent = parent }
        nonisolated func documentCameraViewController(_ controller:VNDocumentCameraViewController,didFinishWith scan:VNDocumentCameraScan) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let images = (0..<scan.pageCount).map { scan.imageOfPage(at:$0) }
                self.parent.onImages(images)
                self.parent.dismiss()
            }
        }
        nonisolated func documentCameraViewControllerDidCancel(_ controller:VNDocumentCameraViewController) {
            Task { @MainActor [weak self] in self?.parent.dismiss() }
        }
        nonisolated func documentCameraViewController(_ controller:VNDocumentCameraViewController,didFailWithError error:Error) {
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.parent.onError(message)
                self.parent.dismiss()
            }
        }
    }
}

import SwiftUI
import PhotosUI
import UIKit

/// 系统相册选择器封装（文档 F-12/F-15）：多选图片，绝不涉及相机
struct PhotoLibraryPicker: UIViewControllerRepresentable {

    var maxCount: Int = 5
    var onPicked: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = maxCount
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // 用 picker 自身 dismiss（Environment dismiss 在 Coordinator 持有的拷贝上会静默失效）
            picker.dismiss(animated: true)
            guard !results.isEmpty else {
                parent.onPicked([])
                return
            }
            let providers = results.map(\.itemProvider)

            Task { @MainActor in
                var images: [UIImage] = []
                for provider in providers {
                    if let image = await Self.loadImage(from: provider) {
                        images.append(image)
                    }
                }
                // 无论识别结果如何都回调，避免流程卡死
                parent.onPicked(images)
            }
        }

        private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
            await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
        }
    }
}

import SwiftUI
import PhotosUI
import UIKit

/// 系统相册选择器封装（文档 F-12/F-15）：多选图片，绝不涉及相机
///
/// 重要：delegate 里不要调用任何 dismiss——
/// PHPickerViewController 嵌在 SwiftUI sheet 的层级里，
/// 调用 dismiss 会向上传播关闭整个 sheet。
/// 正确做法：选完后通过 onPicked 通知父级，由父级通过状态移除本视图。
struct PhotoLibraryPicker: UIViewControllerRepresentable {

    var maxCount: Int = 5
    var onPicked: ([UIImage]) -> Void

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
            // 不调用任何 dismiss——SwiftUI 会在父级移除本视图时自动清理
            let providers = results.map(\.itemProvider)

            Task { @MainActor in
                var images: [UIImage] = []
                for provider in providers {
                    if let image = await Self.loadImage(from: provider) {
                        images.append(image)
                    }
                }
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

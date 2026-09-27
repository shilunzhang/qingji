import SwiftUI
import UIKit

/// 系统相机封装（文档 F-15 拍照记账）。仅在真机可用（模拟器无摄像头）。
///
/// 重要：delegate 里不要调用任何 dismiss——
/// UIImagePickerController 嵌在 SwiftUI sheet 的层级里，
/// dismiss 会向上传播关闭整个 sheet。
/// 由父级通过状态控制移除（stage 切换或 showCamera = false）。
struct CameraPicker: UIViewControllerRepresentable {

    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

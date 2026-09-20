import AVFoundation
import SwiftUI
import UIKit

enum CameraAccessState: Equatable {
    case needsAuthorization
    case authorized
    case denied

    init(authorizationStatus: AVAuthorizationStatus) {
        switch authorizationStatus {
        case .notDetermined: self = .needsAuthorization
        case .authorized: self = .authorized
        case .denied, .restricted: self = .denied
        @unknown default: self = .denied
        }
    }
}

struct CameraPicker: View {
    @Binding var isPresented: Bool
    let onImageCaptured: (UIImage) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var accessState = CameraAccessState(
        authorizationStatus: AVCaptureDevice.authorizationStatus(for: .video)
    )

    var body: some View {
        Group {
            switch accessState {
            case .authorized:
                SystemCameraPicker(isPresented: $isPresented, onImageCaptured: onImageCaptured)
                    .ignoresSafeArea()
            case .needsAuthorization:
                permissionView(
                    title: L10n.text("カメラへのアクセスを許可"),
                    message: L10n.text("写真を撮影してチャットに添付するには、カメラへのアクセスを許可してください。"),
                    buttonTitle: L10n.text("アクセスを許可"),
                    action: requestAuthorization
                )
            case .denied:
                permissionView(
                    title: L10n.text("カメラへのアクセスが許可されていません"),
                    message: L10n.text("「設定」アプリからYamabikoChatのカメラアクセスを許可してください。"),
                    buttonTitle: L10n.text("設定を開く"),
                    action: openSettings
                )
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshAuthorizationState()
        }
    }

    private func permissionView(
        title: String,
        message: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color.chatScreenBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.chatAccent)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.chatComposerText)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 6)
                Button(L10n.text("キャンセル")) { isPresented = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func requestAuthorization() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                accessState = granted ? .authorized : .denied
                DiagnosticsLogger.log(
                    granted ? "Camera permission granted" : "Camera permission denied",
                    category: .chat
                )
            }
        }
    }

    private func refreshAuthorizationState() {
        accessState = CameraAccessState(
            authorizationStatus: AVCaptureDevice.authorizationStatus(for: .video)
        )
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct SystemCameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImageCaptured: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        precondition(
            AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
            "Camera picker must only be created after camera access is authorized"
        )
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: SystemCameraPicker

        init(_ parent: SystemCameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { parent.onImageCaptured(image) }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

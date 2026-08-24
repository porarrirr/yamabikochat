import SwiftUI
import UIKit

@MainActor
final class ShareImportModel: ObservableObject {
    @Published var importedText = ""
    @Published var noteText = ""
    @Published var isLoading = true
    @Published var importError: String?

    var mergedText: String {
        [importedText, noteText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    var canImport: Bool {
        !isLoading && !mergedText.isEmpty
    }

    var previewText: String {
        if isLoading {
            return ShareExtensionStrings.loading
        }
        let trimmed = importedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ShareExtensionStrings.emptyPreview
        }
        return trimmed
    }
}

final class ShareImportViewController: UIViewController {
    private let model = ShareImportModel()
    private var hostingController: UIHostingController<ShareImportRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let rootView = ShareImportRootView(
            model: model,
            onCancel: { [weak self] in self?.cancelImport() },
            onImport: { [weak self] in self?.confirmImport() }
        )
        let hosting = UIHostingController(rootView: rootView)
        hostingController = hosting

        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)

        Task { await loadSharedContent() }
    }

    private func loadSharedContent() async {
        let loaded = await ShareExtensionItemLoader.loadIncomingText(from: extensionContext)
        model.importedText = loaded
        model.isLoading = false
    }

    private func cancelImport() {
        let error = NSError(domain: "YamabikoShareExtension", code: 0)
        extensionContext?.cancelRequest(withError: error)
    }

    private func confirmImport() {
        let merged = model.mergedText
        guard !merged.isEmpty else { return }

        do {
            try SharePayloadPersister.save(text: merged, sourceApp: nil)
        } catch {
            model.importError = error.localizedDescription
            return
        }

        extensionContext?.open(AppConstants.importShareURL) { [weak self] opened in
            guard let self else { return }
            if opened {
                self.extensionContext?.completeRequest(returningItems: nil)
            } else {
                Task { @MainActor in
                    self.model.importError = ShareExtensionStrings.openFailed
                }
            }
        }
    }
}

private struct ShareImportRootView: View {
    @ObservedObject var model: ShareImportModel
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(ShareExtensionStrings.previewHeading) {
                    Text(model.previewText)
                        .font(.body)
                        .foregroundStyle(model.isLoading || model.importedText.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                }

                Section {
                    TextField(ShareExtensionStrings.notePlaceholder, text: $model.noteText, axis: .vertical)
                        .lineLimit(3...8)
                }
                if let importError = model.importError {
                    Section {
                        Text(importError)
                            .foregroundStyle(.red)
                            .accessibilityLabel(ShareExtensionStrings.importFailed)
                    }
                }
            }
            .navigationTitle(ShareExtensionStrings.screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ShareExtensionStrings.cancelButton, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ShareExtensionStrings.primaryButton, action: onImport)
                        .disabled(!model.canImport)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

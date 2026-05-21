import Foundation
import Photos
import UniformTypeIdentifiers

struct RecentPhotoItem: Identifiable {
    let asset: PHAsset

    var id: String {
        asset.localIdentifier
    }
}

@MainActor
final class RecentPhotoLibrary: ObservableObject {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var items: [RecentPhotoItem] = []
    @Published private(set) var isLoading = false

    var canShowRecentPhotos: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    var needsAuthorizationPrompt: Bool {
        authorizationStatus == .notDetermined
    }

    var isAccessDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus()
    }

    func refresh() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus()
        guard canShowRecentPhotos else {
            isLoading = false
            items = []
            return
        }
        loadRecentPhotos()
    }

    func requestAuthorization() {
        let currentStatus = PHPhotoLibrary.authorizationStatus()
        authorizationStatus = currentStatus
        guard currentStatus == .notDetermined else {
            refresh()
            return
        }

        PHPhotoLibrary.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
                self?.refresh()
            }
        }
    }

    func exportFileURL(for asset: PHAsset) async throws -> URL {
        guard let resource = preferredResource(for: asset) else {
            throw CocoaError(.fileReadUnknown)
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + sanitizedFilename(for: resource))
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: temporaryURL, options: options) { error in
                if let error {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        return temporaryURL
    }

    func suggestedFilename(for asset: PHAsset) -> String {
        guard let resource = preferredResource(for: asset) else {
            return "photo.jpg"
        }
        return sanitizedFilename(for: resource)
    }

    private func loadRecentPhotos(limit: Int = 12) {
        isLoading = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = limit

            let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            var assets: [RecentPhotoItem] = []
            result.enumerateObjects { asset, _, _ in
                assets.append(RecentPhotoItem(asset: asset))
            }

            await MainActor.run {
                guard let self else { return }
                self.items = assets
                self.isLoading = false
            }
        }
    }

    private func preferredResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first(where: {
            $0.type == .photo || $0.type == .fullSizePhoto || $0.type == .alternatePhoto
        }) ?? resources.first
    }

    private func sanitizedFilename(for resource: PHAssetResource) -> String {
        let original = resource.originalFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if !original.isEmpty {
            return original
        }

        let ext = UTType(resource.uniformTypeIdentifier)?.preferredFilenameExtension ?? "jpg"
        return "photo.\(ext)"
    }
}

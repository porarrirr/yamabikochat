import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

struct RecentPhotoItem: Identifiable, Equatable {
    let asset: PHAsset

    var id: String {
        asset.localIdentifier
    }

    var aspectRatio: CGFloat {
        let width = CGFloat(max(asset.pixelWidth, 1))
        let height = CGFloat(max(asset.pixelHeight, 1))
        return width / height
    }

    static func == (lhs: RecentPhotoItem, rhs: RecentPhotoItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct RecentPhotoSelection: Equatable {
    let limit: Int
    private(set) var orderedIDs: [String] = []

    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    var count: Int {
        orderedIDs.count
    }

    var isEmpty: Bool {
        orderedIDs.isEmpty
    }

    var isAtLimit: Bool {
        orderedIDs.count >= limit
    }

    func selectionIndex(for id: String) -> Int? {
        orderedIDs.firstIndex(of: id).map { $0 + 1 }
    }

    @discardableResult
    mutating func toggle(_ id: String) -> Bool {
        if let index = orderedIDs.firstIndex(of: id) {
            orderedIDs.remove(at: index)
            return true
        }

        guard !isAtLimit else { return false }
        orderedIDs.append(id)
        return true
    }

    mutating func removeAll() {
        orderedIDs.removeAll()
    }
}

@MainActor
final class RecentPhotoThumbnailCache {
    static let shared = RecentPhotoThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()
    private let imageManager = PHCachingImageManager()

    init() {
        cache.countLimit = 400
    }

    func cachedThumbnail(for localIdentifier: String, targetSize: CGSize) -> UIImage? {
        let key = "\(localIdentifier)_\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
        return cache.object(forKey: key)
    }

    func thumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        let key = "\(asset.localIdentifier)_\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            var didResume = false
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { [weak self] image, info in
                let isCancelled = (info?[PHImageCancelledKey] as? NSNumber)?.boolValue ?? false
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
                if isCancelled {
                    if !didResume {
                        didResume = true
                        continuation.resume(returning: nil)
                    }
                    return
                }

                if let image {
                    if !isDegraded {
                        self?.cache.setObject(image, forKey: key)
                    }
                    if !didResume {
                        didResume = true
                        continuation.resume(returning: image)
                    }
                } else if !didResume {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
        }
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
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func refresh() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard canShowRecentPhotos else {
            isLoading = false
            items = []
            return
        }
        loadRecentPhotos()
    }

    func requestAuthorization() {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = currentStatus
        guard currentStatus == .notDetermined else {
            refresh()
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
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

    private func loadRecentPhotos(limit: Int = 120) {
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

            Task { @MainActor [weak self] in
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

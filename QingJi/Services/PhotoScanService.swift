import Foundation
import Photos
import UIKit

/// 相册扫描相关设置（文档 F-17）
enum AlbumScanSettings {
    private static let autoDeleteKey = "qingji.album.autoDelete"

    /// 入账后自动删除已处理的截图（默认关；删除时系统会弹确认框）
    static var autoDeleteProcessedScreenshots: Bool {
        get { UserDefaults.standard.bool(forKey: autoDeleteKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoDeleteKey) }
    }
}

/// 相册截图扫描（文档 F-13，Tier 2）：增量读取「屏幕快照」，全本机处理
enum PhotoScanService {

    struct ScannedScreenshot {
        let assetID: String
        let image: UIImage
        let creationDate: Date
    }

    /// 请求权限；返回是否可读（完整或有限访问）
    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status == .authorized || status == .limited)
            }
        }
    }

    /// 当前权限是否已授权（不弹窗）
    static var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// 增量取新增截图（新→旧，最多 limit 张）
    static func fetchNewScreenshots(after date: Date?, limit: Int = 10) -> [ScannedScreenshot] {
        let subtype = Int(PHAssetMediaSubtype.photoScreenshot.rawValue)
        let imageType = PHAssetMediaType.image.rawValue

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let date {
            options.predicate = NSPredicate(
                format: "mediaType == %d AND (mediaSubtypes & %d) != 0 AND creationDate > %@",
                imageType, subtype, date as NSDate)
        } else {
            options.predicate = NSPredicate(
                format: "mediaType == %d AND (mediaSubtypes & %d) != 0",
                imageType, subtype)
        }

        let fetch = PHAsset.fetchAssets(with: .image, options: options)
        var result: [ScannedScreenshot] = []
        fetch.enumerateObjects { asset, _, stop in
            if result.count >= limit {
                stop.pointee = true
                return
            }
            if let image = Self.loadImage(for: asset) {
                result.append(ScannedScreenshot(assetID: asset.localIdentifier,
                                                image: image,
                                                creationDate: asset.creationDate ?? .now))
            }
        }
        return result
    }

    private static func loadImage(for asset: PHAsset) -> UIImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true // iCloud 优化的照片允许联网取回
        var image: UIImage?
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            guard let data else { return }
            image = UIImage(data: data)
        }
        return image
    }
}

/// 已处理截图登记（asset id）+ 上次扫描时间（文档 F-13 AC1：已处理不重弹）
struct AlbumScanStore {

    private static let processedKey = "qingji.album.processedIDs"
    private static let lastScanKey = "qingji.album.lastScanDate"
    private static let capacity = 500

    static func processedIDs(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: processedKey) ?? [])
    }

    static func markProcessed(_ assetID: String, defaults: UserDefaults = .standard) {
        var ids = defaults.stringArray(forKey: processedKey) ?? []
        if ids.contains(assetID) { return }
        ids.insert(assetID, at: 0)
        if ids.count > capacity {
            ids = Array(ids.prefix(capacity))
        }
        defaults.set(ids, forKey: processedKey)
    }

    static func lastScanDate(defaults: UserDefaults = .standard) -> Date? {
        let timestamp = defaults.double(forKey: lastScanKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    static func setLastScanDate(_ date: Date?, defaults: UserDefaults = .standard) {
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: lastScanKey)
        } else {
            defaults.removeObject(forKey: lastScanKey)
        }
    }
}

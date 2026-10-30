import Foundation

/// Measures how much disk space files actually take.
public enum DiskUsage {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey
    ]

    /// Allocated size of a file or folder in bytes. Symlinks are never
    /// followed, so a link to a huge folder counts as zero.
    public static func size(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true { return allocatedSize(values) }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            guard let itemValues = try? item.resourceValues(forKeys: Set(keys)),
                  itemValues.isDirectory != true,
                  itemValues.isSymbolicLink != true else { continue }
            total += allocatedSize(itemValues)
        }
        return total
    }

    private static func allocatedSize(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }
}

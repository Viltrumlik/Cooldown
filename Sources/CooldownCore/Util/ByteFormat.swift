import Foundation

public enum ByteFormat {
    /// "12.4 GB", using the same decimal units as Finder.
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

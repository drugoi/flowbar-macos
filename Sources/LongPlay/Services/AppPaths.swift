import Foundation

enum AppPaths {
    static let appName = "LongPlay"
    static var overrideApplicationSupportDirectory: URL?
    static var overrideCachesDirectory: URL?

    static func applicationSupportDirectory() throws -> URL {
        let fm = FileManager.default
        if let overrideApplicationSupportDirectory {
            try fm.createDirectory(at: overrideApplicationSupportDirectory, withIntermediateDirectories: true)
            return overrideApplicationSupportDirectory
        }
        let base = try fm.url(for: .applicationSupportDirectory,
                              in: .userDomainMask,
                              appropriateFor: nil,
                              create: true)
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cachesDirectory() throws -> URL {
        let fm = FileManager.default
        if let overrideCachesDirectory {
            try fm.createDirectory(at: overrideCachesDirectory, withIntermediateDirectories: true)
            return overrideCachesDirectory
        }
        let base = try fm.url(for: .cachesDirectory,
                              in: .userDomainMask,
                              appropriateFor: nil,
                              create: true)
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func libraryFileURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent("library.json")
    }
}

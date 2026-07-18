import Darwin
import Foundation

enum HostProfile: String {
    case defaultProfile = "default"
    case busy
}

struct BusyAppsSnapshot {
    typealias FileReader = (URL) throws -> String

    static let empty = BusyAppsSnapshot(
        configurationFileURL: configurationFileURL(),
        bundleIdentifiers: [],
        loadErrorDescription: nil
    )

    let configurationFileURL: URL
    let bundleIdentifiers: Set<String>
    let loadErrorDescription: String?

    func contains(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else {
            return false
        }

        return bundleIdentifiers.contains(bundleIdentifier)
    }

    func profile(for bundleIdentifier: String?) -> HostProfile {
        contains(bundleIdentifier: bundleIdentifier) ? .busy : .defaultProfile
    }

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fallbackHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        reader: FileReader = { try String(contentsOf: $0, encoding: .utf8) }
    ) -> BusyAppsSnapshot {
        let configurationFileURL = configurationFileURL(
            environment: environment,
            fallbackHomeDirectory: fallbackHomeDirectory
        )

        do {
            let contents = try reader(configurationFileURL)
            return BusyAppsSnapshot(
                configurationFileURL: configurationFileURL,
                bundleIdentifiers: parse(contents),
                loadErrorDescription: nil
            )
        } catch {
            let error = error as NSError
            let errorDescription = "\(error.domain)(\(error.code)): \(error.localizedDescription)"
            return BusyAppsSnapshot(
                configurationFileURL: configurationFileURL,
                bundleIdentifiers: [],
                loadErrorDescription: errorDescription
            )
        }
    }

    static func configurationFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fallbackHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let configurationDirectory: URL
        if let xdgConfigurationHome = environment["XDG_CONFIG_HOME"], !xdgConfigurationHome.isEmpty {
            configurationDirectory = URL(fileURLWithPath: xdgConfigurationHome, isDirectory: true)
        } else {
            let homeDirectory: URL
            if let home = environment["HOME"], !home.isEmpty {
                homeDirectory = URL(fileURLWithPath: home, isDirectory: true)
            } else {
                homeDirectory = fallbackHomeDirectory
            }
            configurationDirectory = homeDirectory.appendingPathComponent(".config", isDirectory: true)
        }

        return configurationDirectory
            .appendingPathComponent("hisle", isDirectory: true)
            .appendingPathComponent("busy-apps.txt", isDirectory: false)
    }

    static func initializeConfigurationFile(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fallbackHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> (configurationFileURL: URL, created: Bool) {
        let configurationFileURL = configurationFileURL(
            environment: environment,
            fallbackHomeDirectory: fallbackHomeDirectory
        )
        try fileManager.createDirectory(
            at: configurationFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let descriptor = configurationFileURL.path.withCString { path in
            Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o666))
        }
        if descriptor >= 0 {
            guard Darwin.close(descriptor) == 0 else {
                throw posixError(code: errno, path: configurationFileURL.path)
            }
            return (configurationFileURL, true)
        }

        let creationError = errno
        if creationError == EEXIST {
            var fileStatus = stat()
            // Follow symbolic links intentionally: managed configuration links
            // are supported when their resolved destination is a regular file.
            guard fstatat(AT_FDCWD, configurationFileURL.path, &fileStatus, 0) == 0 else {
                throw posixError(code: errno, path: configurationFileURL.path)
            }
            let fileType = fileStatus.st_mode & S_IFMT
            guard fileType == S_IFREG else {
                let errorCode = fileType == S_IFDIR ? EISDIR : EFTYPE
                throw posixError(code: errorCode, path: configurationFileURL.path)
            }
            return (configurationFileURL, false)
        }

        throw posixError(code: creationError, path: configurationFileURL.path)
    }

    private static func parse(_ contents: String) -> Set<String> {
        Set(contents.components(separatedBy: .newlines).compactMap { line in
            let identifier = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty, !identifier.hasPrefix("#") else {
                return nil
            }
            return identifier
        })
    }

    private static func posixError(code: Int32, path: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSFilePathErrorKey: path]
        )
    }
}

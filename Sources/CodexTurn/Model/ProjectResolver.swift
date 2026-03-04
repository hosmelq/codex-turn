import Foundation

struct ProjectResolver {
    static func normalizeProjectPath(from cwd: String, useRepoRoot: Bool) -> String {
        let expanded = (cwd as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardized

        guard useRepoRoot else {
            return url.path
        }

        return findRepoRoot(for: url)
    }

    static func displayName(
        for projectPath: String,
        allProjectPaths: [String] = [],
        namingHints: [String: String] = [:]
    ) -> String {
        let path = URL(fileURLWithPath: projectPath)
        let base = displayBase(for: projectPath, namingHints: namingHints)

        let sameBasePaths = allProjectPaths.filter {
            displayBase(for: $0, namingHints: namingHints) == base
        }
        if sameBasePaths.count <= 1 {
            return base
        }

        let disambiguationByPath: [String: String] = Dictionary(
            uniqueKeysWithValues: sameBasePaths.compactMap { candidatePath in
                let candidateURL = URL(fileURLWithPath: candidatePath)
                guard let label = disambiguationLabel(for: candidateURL) else {
                    return nil
                }
                return (candidatePath, label)
            }
        )

        if let suffix = disambiguationByPath[projectPath] {
            return "\(base) (\(suffix))"
        }

        let hasWorktreeSibling = sameBasePaths.contains { candidatePath in
            candidatePath != projectPath && disambiguationByPath[candidatePath] != nil
        }
        if hasWorktreeSibling {
            return base
        }

        let parent = path.deletingLastPathComponent().lastPathComponent
        if parent.isEmpty || parent == "/" {
            return base
        }
        return "\(base) (\(parent))"
    }

    static func repositoryName(from remoteURL: String?) -> String? {
        guard
            let rawRemoteURL = remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawRemoteURL.isEmpty
        else {
            return nil
        }

        if let scpPath = scpRemotePath(from: rawRemoteURL) {
            return repositoryName(fromPath: "/\(scpPath)")
        }

        if let remoteAsURL = URL(string: rawRemoteURL),
            let candidate = repositoryName(fromPath: remoteAsURL.path)
        {
            return candidate
        }

        return repositoryName(fromPath: rawRemoteURL)
    }

    private static func displayBase(for projectPath: String, namingHints: [String: String]) -> String {
        if let namingHint = namingHints[projectPath]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !namingHint.isEmpty
        {
            return namingHint
        }

        let path = URL(fileURLWithPath: projectPath)
        return path.lastPathComponent.isEmpty ? projectPath : path.lastPathComponent
    }

    private static func repositoryName(fromPath path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let withoutFragment = String(trimmed.split(separator: "#", maxSplits: 1).first ?? "")
        let withoutQuery = String(withoutFragment.split(separator: "?", maxSplits: 1).first ?? "")
        let normalized = withoutQuery.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let lastComponent = normalized.split(separator: "/").last else {
            return nil
        }

        var name = String(lastComponent)
        if name.hasSuffix(".git") {
            name.removeLast(4)
        }

        return name.isEmpty ? nil : name
    }

    private static func scpRemotePath(from remoteURL: String) -> String? {
        guard !remoteURL.contains("://"),
            let atIndex = remoteURL.firstIndex(of: "@"),
            let separatorIndex = remoteURL[atIndex...].firstIndex(of: ":"),
            separatorIndex < remoteURL.index(before: remoteURL.endIndex)
        else {
            return nil
        }

        let pathPart = remoteURL[remoteURL.index(after: separatorIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return pathPart.isEmpty ? nil : pathPart
    }

    private static func findRepoRoot(for url: URL) -> String {
        let fm = FileManager.default
        var current = url

        while current.path != "/" && current.path != current.deletingLastPathComponent().path {
            let gitEntryURL = current.appendingPathComponent(".git")
            var isDirectory = ObjCBool(false)
            if fm.fileExists(atPath: gitEntryURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return current.path
                }

                if let gitDirURL = readGitDirURL(for: current),
                    let linkedRoot = resolveRepoRoot(fromGitDir: gitDirURL)
                {
                    return linkedRoot
                }

                return current.path
            }

            let parent = current.deletingLastPathComponent()
            if parent == current {
                break
            }
            current = parent
        }

        return url.path
    }

    private static func disambiguationLabel(for projectURL: URL) -> String? {
        detectWorktreeIDFromPathPattern(for: projectURL) ?? detectGitWorktreeName(for: projectURL)
    }

    private static func detectWorktreeIDFromPathPattern(for projectURL: URL) -> String? {
        let components = projectURL.standardizedFileURL.pathComponents
        guard let worktreesIndex = components.lastIndex(of: "worktrees"),
            worktreesIndex + 2 < components.count
        else {
            return nil
        }

        let worktreeID = components[worktreesIndex + 1]
        let repoName = components[worktreesIndex + 2]
        guard !worktreeID.isEmpty, !repoName.isEmpty else {
            return nil
        }

        return worktreeID
    }

    private static func detectGitWorktreeName(for projectURL: URL) -> String? {
        guard let gitDirURL = readGitDirURL(for: projectURL) else {
            return nil
        }

        let components = gitDirURL.pathComponents

        guard let worktreesIndex = components.lastIndex(of: "worktrees"),
            worktreesIndex + 1 < components.count
        else {
            return nil
        }

        return components[worktreesIndex + 1]
    }

    private static func readGitDirURL(for projectURL: URL) -> URL? {
        let gitPath = projectURL.appendingPathComponent(".git").path
        var isDirectory = ObjCBool(false)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: gitPath, isDirectory: &isDirectory), !isDirectory.boolValue
        else {
            return nil
        }

        guard let gitFileContents = try? String(contentsOfFile: gitPath, encoding: .utf8),
            let line = gitFileContents.split(whereSeparator: \.isNewline).first
        else {
            return nil
        }

        let prefix = "gitdir:"
        guard line.hasPrefix(prefix) else {
            return nil
        }

        let rawGitDir = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawGitDir.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: String(rawGitDir), relativeTo: projectURL).standardizedFileURL
    }

    private static func resolveRepoRoot(fromGitDir gitDirURL: URL) -> String? {
        if gitDirURL.lastPathComponent == ".git" {
            return gitDirURL.deletingLastPathComponent().path
        }

        let worktreesContainer = gitDirURL.deletingLastPathComponent()
        guard worktreesContainer.lastPathComponent == "worktrees" else {
            return nil
        }

        let dotGitDirectory = worktreesContainer.deletingLastPathComponent()
        guard dotGitDirectory.lastPathComponent == ".git" else {
            return nil
        }

        return dotGitDirectory.deletingLastPathComponent().path
    }
}

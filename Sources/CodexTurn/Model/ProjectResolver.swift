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

    static func displayName(for projectPath: String, allProjectPaths: [String] = []) -> String {
        let path = URL(fileURLWithPath: projectPath)
        let base = path.lastPathComponent.isEmpty ? projectPath : path.lastPathComponent

        let sameBasePaths = allProjectPaths.filter { URL(fileURLWithPath: $0).lastPathComponent == base }
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
        detectCodexWorktreeID(for: projectURL) ?? detectGitWorktreeName(for: projectURL)
    }

    private static func detectCodexWorktreeID(for projectURL: URL) -> String? {
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

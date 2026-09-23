import Foundation
import Darwin

public protocol UsageProviding: Sendable {
    func fetch() async throws -> UsageLimits
}

public enum UsageClientError: Error, LocalizedError, Equatable, Sendable {
    case executableNotFound, launchFailed, serverExited, timedOut, invalidResponse
    case authenticationRequired, unsupportedAccount, requestFailed

    public var errorDescription: String? {
        switch self {
        case .executableNotFound: "Codex が見つかりません。接続設定で Codex の実行ファイルを選択してください。"
        case .launchFailed: "Codex を起動できませんでした。接続設定の実行ファイルを確認してください。"
        case .serverExited: "Codex との接続が終了しました。Codex が起動できることを確認して再試行してください。"
        case .timedOut: "取得がタイムアウトしました。ネットワーク接続を確認して再試行してください。"
        case .invalidResponse: "利用状況を読み取れませんでした。Codex を更新して再試行してください。"
        case .authenticationRequired: "Codex へのログインが必要です。ターミナルで codex login を実行し、ChatGPT アカウントでログインしてください。"
        case .unsupportedAccount: "この認証方式では利用枠を取得できません。Codex に ChatGPT アカウントでログインしてください。"
        case .requestFailed: "利用状況を取得できませんでした。ネットワークと Codex のログイン状態を確認してください。"
        }
    }
}

public struct CodexUsageClient: UsageProviding {
    public let executablePath: String
    public let timeout: TimeInterval

    public init(executablePath: String, timeout: TimeInterval = 20) {
        self.executablePath = executablePath
        self.timeout = timeout
    }

    public func fetch() async throws -> UsageLimits {
        let cancellation = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                try readLimits(cancellation: cancellation)
            }.value
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func readLimits(cancellation: CancellationFlag) throws -> UsageLimits {
        try cancellation.check()
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw UsageClientError.executableNotFound
        }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        // Server diagnostics may contain private data; do not persist or display them.
        process.standardError = FileHandle.nullDevice
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try process.run() } catch { throw UsageClientError.launchFailed }

        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            let deadline = ProcessInfo.processInfo.systemUptime + 0.3
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }

        let stream = RPCStream(
            input: input.fileHandleForWriting,
            output: output.fileHandleForReading,
            deadline: ProcessInfo.processInfo.systemUptime + timeout,
            cancellation: cancellation
        )
        try stream.send([
            "id": 1, "method": "initialize",
            "params": ["clientInfo": ["name": "usage_board", "title": "Usage Board", "version": "0.1.0"]]
        ])
        _ = try stream.response(id: 1)
        try stream.send(["method": "initialized"])
        try stream.send(["id": 2, "method": "account/rateLimits/read"])
        let data = try stream.response(id: 2)
        do { return try JSONDecoder().decode(UsageLimits.self, from: data) }
        catch { throw UsageClientError.invalidResponse }
    }
}

// The lock protects the only state shared with the background process worker.
private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    func check() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }
}

// Used only on the background worker. Partial JSONL messages are buffered between reads.
private final class RPCStream {
    let input: FileHandle
    let output: FileHandle
    let deadline: TimeInterval
    let cancellation: CancellationFlag
    var buffer = Data()

    init(input: FileHandle, output: FileHandle, deadline: TimeInterval, cancellation: CancellationFlag) {
        self.input = input
        self.output = output
        self.deadline = deadline
        self.cancellation = cancellation
    }

    func send(_ object: [String: Any]) throws {
        try cancellation.check()
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        do { try input.write(contentsOf: data) }
        catch { throw UsageClientError.serverExited }
    }

    func response(id: Int) throws -> Data {
        while true {
            try cancellation.check()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw UsageClientError.timedOut }
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if line.isEmpty { continue }
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw UsageClientError.invalidResponse
                }
                // No server-initiated actions are supported by this read-only client.
                if message["method"] != nil {
                    if let requestID = message["id"] {
                        try send(["id": requestID, "error": ["code": -32601, "message": "Method not supported"]])
                    }
                    continue
                }
                guard (message["id"] as? Int) == id else { continue }
                if let error = message["error"] as? [String: Any] {
                    let text = (error["message"] as? String ?? "").lowercased()
                    if text.contains("not authenticated") || text.contains("unauthorized") || text.contains("log in") || text.contains("login") || text.contains("401") {
                        throw UsageClientError.authenticationRequired
                    }
                    if text.contains("chatgpt") || text.contains("api key") || text.contains("api_key") {
                        throw UsageClientError.unsupportedAccount
                    }
                    throw UsageClientError.requestFailed
                }
                guard let result = message["result"] as? [String: Any] else { throw UsageClientError.invalidResponse }
                return try JSONSerialization.data(withJSONObject: result)
            }
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let status = poll(&descriptor, 1, 100)
            if status < 0 {
                if errno == EINTR { continue }
                throw UsageClientError.serverExited
            }
            if status == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw UsageClientError.serverExited }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 4_194_304 else { throw UsageClientError.invalidResponse }
        }
    }
}

public enum CodexLocator {
    public static func locate(customPath: String = "") -> String? {
        let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return (trimmed as NSString).expandingTildeInPath }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "\(home)/.codex/packages/standalone/current/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex"
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

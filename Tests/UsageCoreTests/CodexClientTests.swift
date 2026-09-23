import Foundation
import Testing
@testable import UsageCore

struct CodexClientTests {
    @Test func performsHandshakeAndIgnoresNotificationsAndPartialLines() async throws {
        let fixture = try MockServer("""
        read -r init
        case "$init" in *'"method":"initialize"'*) ;; *) exit 1;; esac
        printf '%s\\n' '{"method":"notice","params":{}}' '{"id":1,"result":{}}'
        read -r ready
        case "$ready" in *'"method":"initialized"'*) ;; *) exit 2;; esac
        read -r request
        case "$request" in *'"method":"account/rateLimits/read"'*) ;; *) exit 3;; esac
        printf '%s' '{"id":2,"result":{"rateLimits":{"primary":'
        sleep 0.05
        printf '%s\\n' '{"usedPercent":21}}}}'
        """)
        defer { fixture.remove() }
        let limits = try await fixture.client.fetch()
        #expect(limits.buckets.first?.primary?.remainingPercent == 79)
    }

    @Test func propagatesRPCErrorWithoutExposingServerText() async throws {
        let fixture = try MockServer("""
        read -r init
        printf '%s\\n' '{"id":1,"result":{}}'
        read -r ready
        read -r request
        printf '%s\\n' '{"id":2,"error":{"code":-32000,"message":"not authenticated secret-value"}}'
        """)
        defer { fixture.remove() }
        await #expect(throws: UsageClientError.authenticationRequired) { try await fixture.client.fetch() }
    }

    @Test func timesOutAnUnresponsiveProcess() async throws {
        let fixture = try MockServer("sleep 3", timeout: 0.15)
        defer { fixture.remove() }
        await #expect(throws: UsageClientError.timedOut) { try await fixture.client.fetch() }
    }

    @Test func reportsEarlyExitAndMalformedJSON() async throws {
        let exited = try MockServer("exit 1")
        defer { exited.remove() }
        await #expect(throws: UsageClientError.serverExited) { try await exited.client.fetch() }
        let malformed = try MockServer("read -r init\nprintf '%s\\n' 'invalid-json'")
        defer { malformed.remove() }
        await #expect(throws: UsageClientError.invalidResponse) { try await malformed.client.fetch() }
    }

    @Test func cancellationStopsWaitingPromptly() async throws {
        let fixture = try MockServer("sleep 3", timeout: 10)
        defer { fixture.remove() }
        let task = Task { try await fixture.client.fetch() }
        try await Task.sleep(for: .milliseconds(80))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func missingExecutableIsActionable() async {
        let client = CodexUsageClient(executablePath: "/nonexistent/usage-board-codex")
        await #expect(throws: UsageClientError.executableNotFound) { try await client.fetch() }
    }
}

struct MockServer {
    let directory: URL
    let client: CodexUsageClient

    init(_ body: String, timeout: TimeInterval = 2) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("codex")
        try ("#!/bin/sh\n" + body + "\n").write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        client = CodexUsageClient(executablePath: script.path, timeout: timeout)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

import AppKit
import Foundation

enum CodexLoginState: Equatable {
  case notInstalled
  case loggedOut
  case chatGPT
  case apiKey
  case unknown(String)

  var isConnected: Bool {
    switch self {
    case .chatGPT, .apiKey:
      return true
    case .notInstalled, .loggedOut, .unknown:
      return false
    }
  }

  var usesChatGPTQuota: Bool {
    if case .chatGPT = self { return true }
    return false
  }

  var statusText: String {
    switch self {
    case .notInstalled:
      return "Codex CLI is not installed"
    case .loggedOut:
      return "Not signed in to Codex"
    case .chatGPT:
      return "Connected with ChatGPT"
    case .apiKey:
      return "Connected with API key"
    case .unknown(let message):
      return message
    }
  }
}

enum CodexCLI {
  static let installGuideURL = URL(string: "https://help.openai.com/en/articles/11369540")!

  struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
  }

  static func findBinary() -> String? {
    let candidates = [
      "/opt/homebrew/bin/codex",
      "/usr/local/bin/codex",
      "/usr/bin/codex",
    ]

    for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
      return path
    }

    let whichProcess = Process()
    whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    whichProcess.arguments = ["codex"]

    let stdout = Pipe()
    let stderr = Pipe()
    whichProcess.standardOutput = stdout
    whichProcess.standardError = stderr

    do {
      try whichProcess.run()
      whichProcess.waitUntilExit()
      let data = stdout.fileHandleForReading.readDataToEndOfFile()
      if let path = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !path.isEmpty,
        FileManager.default.isExecutableFile(atPath: path)
      {
        return path
      }
    } catch {
      log("CodexCLI: failed to locate codex binary — \(error.localizedDescription)")
    }

    return nil
  }

  static func loginStatus() -> CodexLoginState {
    guard let binary = findBinary() else { return .notInstalled }
    let result = run(binary: binary, arguments: ["login", "status"])
    return parseLoginStatus(
      output: [result.stdout, result.stderr].joined(separator: "\n"),
      exitCode: result.exitCode,
      binaryFound: true
    )
  }

  static func parseLoginStatus(
    output: String,
    exitCode: Int32,
    binaryFound: Bool
  ) -> CodexLoginState {
    guard binaryFound else { return .notInstalled }

    let trimmed = output
      .split(separator: "\n")
      .map(String.init)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && !$0.hasPrefix("WARNING:") }
      .joined(separator: "\n")

    let lower = trimmed.lowercased()

    if lower.contains("logged in using chatgpt") {
      return .chatGPT
    }
    if lower.contains("logged in using api key") {
      return .apiKey
    }
    if lower.contains("not logged in") {
      return .loggedOut
    }
    if exitCode == 0 && !trimmed.isEmpty {
      return .unknown(trimmed)
    }
    return .loggedOut
  }

  static func openInstallGuide() {
    NSWorkspace.shared.open(installGuideURL)
  }

  static func openLoginInTerminal() {
    let shellCommand = [
      "source ~/.zprofile 2>/dev/null",
      "source ~/.zshrc 2>/dev/null",
      "codex logout >/dev/null 2>&1 || true",
      "codex login --device-auth",
      "echo ''",
      "echo 'Return to Omi and click Refresh after sign-in completes.'",
      "exec $SHELL -l",
    ].joined(separator: "; ")

    let escapedCommand = shellCommand
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")

    let script = """
    tell application "Terminal"
      activate
      do script "\(escapedCommand)"
    end tell
    """

    var error: NSDictionary?
    if let appleScript = NSAppleScript(source: script) {
      appleScript.executeAndReturnError(&error)
      if let error {
        log("CodexCLI: failed to open Terminal for login — \(error)")
      }
    }
  }

  static func logout() throws {
    guard let binary = findBinary() else {
      throw CodexBridgeError.cliNotInstalled
    }

    let result = run(binary: binary, arguments: ["logout"])
    guard result.exitCode == 0 else {
      let message = [result.stdout, result.stderr]
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw CodexBridgeError.commandFailed(message.nilIfBlank ?? "Failed to log out from Codex")
    }
  }

  static func renderPrompt(
    systemPrompt: String,
    userPrompt: String,
    mode: String?,
    imageData: Data?
  ) -> String {
    var sections: [String] = [
      "You are responding inside the Omi desktop chat UI.",
      "",
      "Execution mode: \(mode == "ask" ? "ask" : "act").",
      mode == "ask"
        ? "Prefer explanation and read-only investigation unless the user explicitly asks you to make changes."
        : "You may edit files and run commands when it helps complete the user's request.",
      "",
      "<system_prompt>",
      systemPrompt,
      "</system_prompt>",
      "",
      "<user_message>",
      userPrompt,
      "</user_message>",
    ]

    if imageData != nil {
      sections.append("")
      sections.append(
        "Note: the desktop app attached an image, but the current Codex CLI bridge forwards text only."
      )
    }

    return sections.joined(separator: "\n")
  }

  private static func run(binary: String, arguments: [String]) -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return ProcessResult(exitCode: 1, stdout: "", stderr: error.localizedDescription)
    }

    let stdoutText = String(
      data: stdout.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    ) ?? ""
    let stderrText = String(
      data: stderr.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    ) ?? ""

    return ProcessResult(
      exitCode: process.terminationStatus,
      stdout: stdoutText,
      stderr: stderrText
    )
  }
}

actor CodexBridge {
  private var process: Process?
  private var stdoutPipe: Pipe?
  private var stderrPipe: Pipe?
  private var terminationContinuation: CheckedContinuation<Int32, Error>?
  private var lastStructuredError: String?
  private var stderrLines: [String] = []
  private var wasInterrupted = false

  var isAlive: Bool { process != nil }

  func query(
    prompt: String,
    systemPrompt: String,
    sessionKey _: String? = nil,
    cwd: String? = nil,
    mode: String? = nil,
    model: String? = nil,
    resume _: String? = nil,
    imageData: Data? = nil,
    onTextDelta: @escaping ACPBridge.TextDeltaHandler,
    onToolCall _: @escaping ACPBridge.ToolCallHandler,
    onToolActivity _: @escaping ACPBridge.ToolActivityHandler,
    onThinkingDelta _: @escaping ACPBridge.ThinkingDeltaHandler = { _ in },
    onToolResultDisplay _: @escaping ACPBridge.ToolResultDisplayHandler = { _, _, _ in },
    onAuthRequired _: @escaping ACPBridge.AuthRequiredHandler = { _, _ in },
    onAuthSuccess _: @escaping ACPBridge.AuthSuccessHandler = {}
  ) async throws -> ACPBridge.QueryResult {
    guard process == nil else {
      throw CodexBridgeError.commandFailed("Codex is already running a request")
    }

    guard let binary = CodexCLI.findBinary() else {
      throw CodexBridgeError.cliNotInstalled
    }

    let outputFile = FileManager.default.temporaryDirectory
      .appendingPathComponent("omi-codex-last-\(UUID().uuidString).txt")
    let resolvedCwd = cwd?.nilIfBlank ?? FileManager.default.homeDirectoryForCurrentUser.path
    let renderedPrompt = CodexCLI.renderPrompt(
      systemPrompt: systemPrompt,
      userPrompt: prompt,
      mode: mode,
      imageData: imageData
    )

    var arguments = [
      "exec",
      "--json",
      "--skip-git-repo-check",
      "-C", resolvedCwd,
      "--output-last-message", outputFile.path,
      "--sandbox", mode == "ask" ? "read-only" : "workspace-write",
    ]

    if let normalizedModel = normalizedModel(from: model) {
      arguments.append(contentsOf: ["--model", normalizedModel])
    }

    arguments.append(renderedPrompt)

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: binary)
    proc.arguments = arguments
    proc.environment = ProcessInfo.processInfo.environment

    let stdout = Pipe()
    let stderr = Pipe()
    proc.standardOutput = stdout
    proc.standardError = stderr

    self.process = proc
    self.stdoutPipe = stdout
    self.stderrPipe = stderr
    self.lastStructuredError = nil
    self.stderrLines = []
    self.wasInterrupted = false

    stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      let text = String(data: data, encoding: .utf8) ?? ""
      Task { await self?.consumeStdout(text) }
    }

    stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      let text = String(data: data, encoding: .utf8) ?? ""
      Task { await self?.consumeStderr(text) }
    }

    proc.terminationHandler = { [weak self] process in
      Task { await self?.finish(exitCode: process.terminationStatus) }
    }

    do {
      try proc.run()
    } catch {
      clearState()
      throw CodexBridgeError.commandFailed(error.localizedDescription)
    }

    let exitCode = try await withCheckedThrowingContinuation { continuation in
      self.terminationContinuation = continuation
    }

    let finalText = (try? String(contentsOf: outputFile, encoding: .utf8))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    try? FileManager.default.removeItem(at: outputFile)

    if !finalText.isEmpty {
      onTextDelta(finalText)
    }

    if exitCode == 0 || (!finalText.isEmpty && wasInterrupted) {
      return ACPBridge.QueryResult(
        text: finalText,
        costUsd: 0,
        sessionId: UUID().uuidString,
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0
      )
    }

    if wasInterrupted {
      throw BridgeError.stopped
    }

    let errorMessage = lastStructuredError?.nilIfBlank
      ?? stderrLines.joined(separator: "\n").nilIfBlank
      ?? "Codex request failed"
    throw CodexBridgeError.commandFailed(errorMessage)
  }

  func interrupt() {
    wasInterrupted = true
    process?.terminate()
  }

  private func consumeStdout(_ text: String) {
    for line in text.split(whereSeparator: \.isNewline) {
      guard let data = line.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let type = json["type"] as? String
      else {
        continue
      }

      if type == "error", let message = json["message"] as? String {
        lastStructuredError = message
      }
    }
  }

  private func consumeStderr(_ text: String) {
    let cleaned = text
      .split(whereSeparator: \.isNewline)
      .map(String.init)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    stderrLines.append(contentsOf: cleaned)
  }

  private func finish(exitCode: Int32) {
    stdoutPipe?.fileHandleForReading.readabilityHandler = nil
    stderrPipe?.fileHandleForReading.readabilityHandler = nil

    let remainingStdout = stdoutPipe?.fileHandleForReading.readDataToEndOfFile()
    if let remainingStdout,
      !remainingStdout.isEmpty,
      let text = String(data: remainingStdout, encoding: .utf8)
    {
      consumeStdout(text)
    }

    let remainingStderr = stderrPipe?.fileHandleForReading.readDataToEndOfFile()
    if let remainingStderr,
      !remainingStderr.isEmpty,
      let text = String(data: remainingStderr, encoding: .utf8)
    {
      consumeStderr(text)
    }

    clearState()
    terminationContinuation?.resume(returning: exitCode)
    terminationContinuation = nil
  }

  private func clearState() {
    stdoutPipe?.fileHandleForReading.readabilityHandler = nil
    stderrPipe?.fileHandleForReading.readabilityHandler = nil
    process = nil
    stdoutPipe = nil
    stderrPipe = nil
  }

  private func normalizedModel(from requested: String?) -> String? {
    guard let requested = requested?.trimmingCharacters(in: .whitespacesAndNewlines),
      !requested.isEmpty
    else {
      return nil
    }

    let lower = requested.lowercased()
    if lower.contains("gpt") || lower.hasPrefix("o") {
      return requested
    }
    return nil
  }
}

enum CodexBridgeError: LocalizedError {
  case cliNotInstalled
  case commandFailed(String)

  var errorDescription: String? {
    switch self {
    case .cliNotInstalled:
      return "Codex CLI is not installed. Install it and sign in with ChatGPT first."
    case .commandFailed(let message):
      let lower = message.lowercased()
      if lower.contains("not logged in") {
        return "Sign in to Codex with your ChatGPT account to use this provider."
      }
      if lower.contains("failed to lookup address information")
        || lower.contains("could not resolve host")
      {
        return "Codex could not reach OpenAI. Check your network connection and try again."
      }
      return message.nilIfBlank ?? "Codex request failed."
    }
  }
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

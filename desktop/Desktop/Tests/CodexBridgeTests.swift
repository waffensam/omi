import XCTest
@testable import Omi_Computer

final class CodexBridgeTests: XCTestCase {
  func testParseLoginStatusDetectsChatGPTAuth() {
    let state = CodexCLI.parseLoginStatus(
      output: "Logged in using ChatGPT\n",
      exitCode: 0,
      binaryFound: true
    )

    XCTAssertEqual(state, .chatGPT)
  }

  func testParseLoginStatusDetectsAPIKeyAuth() {
    let state = CodexCLI.parseLoginStatus(
      output: "Logged in using API key\n",
      exitCode: 0,
      binaryFound: true
    )

    XCTAssertEqual(state, .apiKey)
  }

  func testParseLoginStatusDetectsLoggedOutState() {
    let state = CodexCLI.parseLoginStatus(
      output: "Not logged in. Run `codex login`.\n",
      exitCode: 1,
      binaryFound: true
    )

    XCTAssertEqual(state, .loggedOut)
  }

  func testParseLoginStatusReturnsNotInstalledWhenBinaryMissing() {
    let state = CodexCLI.parseLoginStatus(
      output: "",
      exitCode: 127,
      binaryFound: false
    )

    XCTAssertEqual(state, .notInstalled)
  }

  func testParseLoginStatusPreservesUnexpectedSuccessfulOutput() throws {
    let state = CodexCLI.parseLoginStatus(
      output: "Authenticated using enterprise SSO",
      exitCode: 0,
      binaryFound: true
    )

    guard case .unknown(let message) = state else {
      return XCTFail("Expected unknown state, got \(state)")
    }

    XCTAssertEqual(message, "Authenticated using enterprise SSO")
  }
}

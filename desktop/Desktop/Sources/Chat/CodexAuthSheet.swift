import SwiftUI

/// Sheet shown when Codex CLI needs to be installed or authenticated.
struct CodexAuthSheet: View {
  let loginState: CodexLoginState
  let onOpenInstallGuide: () -> Void
  let onOpenLogin: () -> Void
  let onRefresh: () -> Void
  let onCancel: () -> Void

  @State private var isOpeningExternalAction = false

  private var titleText: String {
    switch loginState {
    case .notInstalled:
      return "Install Codex CLI"
    case .loggedOut, .unknown:
      return "Sign In with ChatGPT"
    case .chatGPT:
      return "Connected to Codex"
    case .apiKey:
      return "Codex is Using an API Key"
    }
  }

  private var descriptionText: String {
    switch loginState {
    case .notInstalled:
      return "Omi uses the official Codex CLI for this provider. Install Codex first, then sign in with ChatGPT to use your Codex allowance."
    case .loggedOut, .unknown:
      return "Open a Terminal window, finish the Codex sign-in flow with ChatGPT, then come back here and refresh the status."
    case .chatGPT:
      return "Codex is already connected with ChatGPT. Refresh if Omi has not picked that up yet."
    case .apiKey:
      return "Codex is signed in with an API key right now. To use ChatGPT-authenticated Codex quota instead, log out in Terminal and sign back in with ChatGPT."
    }
  }

  private var primaryButtonTitle: String {
    switch loginState {
    case .notInstalled:
      return "Open Install Guide"
    case .loggedOut, .unknown, .apiKey:
      return "Open Terminal"
    case .chatGPT:
      return "Refresh Status"
    }
  }

  private var iconName: String {
    switch loginState {
    case .notInstalled:
      return "terminal"
    case .loggedOut, .unknown:
      return "person.crop.circle.badge.key"
    case .chatGPT:
      return "checkmark.seal.fill"
    case .apiKey:
      return "key.fill"
    }
  }

  private var iconColor: Color {
    switch loginState {
    case .chatGPT:
      return .green
    case .apiKey, .loggedOut, .unknown:
      return OmiColors.warning
    case .notInstalled:
      return OmiColors.textSecondary
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(titleText)
          .scaledFont(size: 18, weight: .semibold)
          .foregroundColor(OmiColors.textPrimary)

        Spacer()

        Button(action: onCancel) {
          Image(systemName: "xmark")
            .scaledFont(size: 14, weight: .medium)
            .foregroundColor(OmiColors.textTertiary)
            .frame(width: 28, height: 28)
            .background(OmiColors.backgroundTertiary.opacity(0.5))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 24)
      .padding(.top, 20)
      .padding(.bottom, 16)

      Divider()
        .foregroundColor(OmiColors.border)

      VStack(spacing: 20) {
        Image(systemName: iconName)
          .scaledFont(size: 40)
          .foregroundColor(iconColor)
          .padding(.top, 8)

        VStack(spacing: 8) {
          Text(descriptionText)
            .scaledFont(size: 13)
            .foregroundColor(OmiColors.textTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

          Text("Omi never handles your ChatGPT credentials directly. Authentication stays inside the Codex CLI flow.")
            .scaledFont(size: 12)
            .foregroundColor(OmiColors.textTertiary.opacity(0.85))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)

        if isOpeningExternalAction {
          VStack(spacing: 12) {
            ProgressView()
              .controlSize(.small)

            Text("Waiting for Codex setup...")
              .scaledFont(size: 13)
              .foregroundColor(OmiColors.textTertiary)
          }
          .padding(.top, 4)
        }
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 16)

      Spacer()

      VStack(spacing: 12) {
        Button(action: primaryAction) {
          HStack(spacing: 8) {
            if isOpeningExternalAction {
              ProgressView()
                .controlSize(.mini)
            }
            Text(primaryButtonTitle)
              .scaledFont(size: 14, weight: .semibold)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(isOpeningExternalAction ? OmiColors.backgroundTertiary : Color.accentColor)
          .foregroundColor(isOpeningExternalAction ? OmiColors.textSecondary : .white)
          .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(isOpeningExternalAction && loginState != .chatGPT)

        Button("Refresh") {
          isOpeningExternalAction = false
          onRefresh()
        }
        .buttonStyle(.plain)
        .scaledFont(size: 13, weight: .medium)
        .foregroundColor(OmiColors.textSecondary)

        Button("Use omi account instead", action: onCancel)
          .buttonStyle(.plain)
          .scaledFont(size: 13)
          .foregroundColor(OmiColors.textTertiary)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 20)
    }
    .frame(width: 420, height: 400)
    .background(OmiColors.backgroundPrimary)
  }

  private func primaryAction() {
    switch loginState {
    case .notInstalled:
      isOpeningExternalAction = true
      onOpenInstallGuide()
    case .loggedOut, .unknown, .apiKey:
      isOpeningExternalAction = true
      onOpenLogin()
    case .chatGPT:
      isOpeningExternalAction = false
      onRefresh()
    }
  }
}

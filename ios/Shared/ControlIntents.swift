import AppIntents

struct TogglePlaybackIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays or pauses the video in IINA.")

    @MainActor func perform() async throws -> some IntentResult {
        try await control { .set(.pause, !$0.pause) }
    }
}

struct PauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause"
    static let description = IntentDescription("Pauses the video in IINA.")

    @MainActor func perform() async throws -> some IntentResult {
        try await control { _ in .set(.pause, true) }
    }
}

struct ResumeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume"
    static let description = IntentDescription("Resumes the video in IINA.")

    @MainActor func perform() async throws -> some IntentResult {
        try await control { _ in .set(.pause, false) }
    }
}

struct SkipForwardIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Forward"
    static let description = IntentDescription("Skips 30 seconds forward in IINA.")

    @MainActor func perform() async throws -> some IntentResult {
        try await control { _ in .seek(30, absolute: false) }
    }
}

struct SkipBackIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Back"
    static let description = IntentDescription("Goes 10 seconds back in IINA.")

    @MainActor func perform() async throws -> some IntentResult {
        try await control { _ in .seek(-10, absolute: false) }
    }
}

struct NextItemIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next Episode"
    static let description = IntentDescription("Plays the next item in IINA's playlist.")

    @MainActor func perform() async throws -> some IntentResult {
        try await control { _ in .next }
    }
}

enum ControlError: Error, CustomLocalizedStringResourceConvertible {
    case noIINA

    var localizedStringResource: LocalizedStringResource {
        "Couldn't reach IINA. Open a video in IINA on your Mac and try again."
    }
}

@MainActor
private func control(_ command: (PlayerState) -> Command) async throws -> some IntentResult {
    let remote = Remote.shared
    guard let current = await remote.connectedPlayer()?.state,
          await remote.perform(command(current)) != nil
    else { throw ControlError.noIINA }
    return .result()
}

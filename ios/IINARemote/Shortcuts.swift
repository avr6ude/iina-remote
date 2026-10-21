import AppIntents

struct RemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PauseIntent(), phrases: ["Pause \(.applicationName)"], shortTitle: "Pause", systemImageName: "pause.fill")
        AppShortcut(intent: ResumeIntent(), phrases: ["Resume \(.applicationName)", "Play \(.applicationName)"], shortTitle: "Resume", systemImageName: "play.fill")
        AppShortcut(intent: SkipForwardIntent(), phrases: ["Skip forward in \(.applicationName)"], shortTitle: "Skip Forward", systemImageName: "goforward.30")
        AppShortcut(intent: SkipBackIntent(), phrases: ["Go back in \(.applicationName)"], shortTitle: "Skip Back", systemImageName: "gobackward.10")
        AppShortcut(intent: NextItemIntent(), phrases: ["Next episode in \(.applicationName)"], shortTitle: "Next Episode", systemImageName: "forward.end.fill")
    }
}

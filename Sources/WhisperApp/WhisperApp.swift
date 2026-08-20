import SwiftUI

@main
struct WhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Whisper") {
            Color(DesignTokens.canvas)
                .frame(
                    minWidth: DesignTokens.sidebarWidth,
                    idealWidth: DesignTokens.contentMaxWidth,
                    minHeight: 560
                )
                .preferredColorScheme(.dark)
        }
    }
}

import SwiftUI

struct AppRootView: View {
    @Bindable var onboarding: OnboardingModel
    let relaunch: () -> Void
    @State private var destination = "Home"
    private let destinations = ["Home", "Modes", "Recordings", "History", "Settings"]

    var body: some View {
        Group {
            if onboarding.isPresented {
                OnboardingView(model: onboarding, relaunch: relaunch)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Whisper").font(.title2.bold()).padding(.bottom, 20)
                        ForEach(destinations, id: \.self) { item in
                            Button { destination = item } label: {
                                Text(item).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(destination == item ? DesignTokens.selected : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(destination == item ? .isSelected : [])
                        }
                        Spacer()
                    }
                    .padding(20).frame(width: DesignTokens.sidebarWidth)
                    .background(DesignTokens.sidebar)
                    Divider()
                    VStack(alignment: .leading, spacing: 24) {
                        Text(destination).font(.largeTitle.weight(.semibold))
                        if destination == "Settings" {
                            Text("Setup and permissions").font(.headline)
                            Button("Preview Setup") { onboarding.presentSetup(reset: false) }
                            Button("Reset Setup") { onboarding.presentSetup(reset: true) }
                            ForEach(PermissionKind.allCases, id: \.self) { kind in
                                HStack {
                                    Text("\(kind.settingsTitle): \(onboarding.permissions[kind].setupLabel)")
                                    Button("Open \(kind.settingsTitle) Settings") { onboarding.openSettings(for: kind) }
                                }
                            }
                        } else if destination == "Home" {
                            Text("Welcome to Whisper").font(.title2)
                            Text("Use the menu bar to dictate or change mode. Complete or revisit setup from Settings.")
                        } else {
                            Text("\(destination) is not available yet.")
                                .foregroundStyle(DesignTokens.secondaryText)
                        }
                        Spacer()
                    }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .foregroundStyle(DesignTokens.primaryText)
        .background(DesignTokens.canvas)
        .preferredColorScheme(.dark)
        .onChange(of: onboarding.completionGeneration) { destination = "Home" }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            onboarding.refreshPermissions()
        }
    }
}

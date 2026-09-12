import SwiftUI

struct AppRootView: View {
    @Bindable var onboarding: OnboardingModel
    @Bindable var home: HomeModel
    @Bindable var modes: ModesModel
    @Bindable var settings: SettingsModel
    let relaunch: () -> Void
    let startDictation: () -> Void
    let changeMode: () -> Void
    let recordMeeting: () -> Void
    @State private var destination: SidebarDestination = .home

    init(
        onboarding: OnboardingModel,
        home: HomeModel,
        modes: ModesModel,
        settings: SettingsModel,
        initialDestination: SidebarDestination = .home,
        relaunch: @escaping () -> Void,
        startDictation: @escaping () -> Void,
        changeMode: @escaping () -> Void,
        recordMeeting: @escaping () -> Void
    ) {
        self.onboarding = onboarding
        self.home = home
        self.modes = modes
        self.settings = settings
        self.relaunch = relaunch
        self.startDictation = startDictation
        self.changeMode = changeMode
        self.recordMeeting = recordMeeting
        _destination = State(initialValue: initialDestination)
    }

    var body: some View {
        Group {
            if onboarding.isPresented {
                OnboardingView(model: onboarding, relaunch: relaunch)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                NavigationSplitView {
                    VStack(alignment: .leading, spacing: 0) {
                        Label("Whisper", systemImage: "waveform")
                            .font(.system(size: 18, weight: .bold))
                            .padding(.horizontal, DesignTokens.space16)
                            .padding(.vertical, DesignTokens.space24)
                        VStack(spacing: DesignTokens.space4) {
                            ForEach(SidebarDestination.allCases) { item in
                                Button {
                                    destination = item
                                } label: {
                                    Label(item.rawValue, systemImage: item.systemImage)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, DesignTokens.space12)
                                        .frame(height: 36)
                                        .background(destination == item ? DesignTokens.selected : .clear)
                                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(item.rawValue)
                                .accessibilityAddTraits(destination == item ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, DesignTokens.space8)
                        Spacer()
                    }
                    .background(DesignTokens.sidebar)
                    .navigationSplitViewColumnWidth(
                        min: DesignTokens.sidebarWidth,
                        ideal: DesignTokens.sidebarWidth,
                        max: DesignTokens.sidebarWidth
                    )
                } detail: {
                    destinationView
                }
                .navigationSplitViewStyle(.balanced)
                .toolbar {
                    ToolbarItem {
                        HStack(spacing: DesignTokens.space4) {
                            Image(systemName: "mic")
                            Text(settings.selectedMicrophoneName)
                        }
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.secondaryText)
                            .help("Current microphone")
                    }
                }
            }
        }
        .foregroundStyle(DesignTokens.primaryText)
        .background(DesignTokens.canvas)
        .preferredColorScheme(.dark)
        .onChange(of: onboarding.completionGeneration) {
            settings.refresh()
            destination = .home
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            onboarding.refreshPermissions()
            settings.refresh()
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch destination {
        case .home:
            HomeView(
                home: home,
                modes: modes,
                settings: settings,
                startDictation: startDictation,
                changeMode: changeMode,
                recordMeeting: recordMeeting
            )
        case .modes:
            ModesListView(model: modes)
        case .recordings:
            futureDestination(
                title: "Recordings",
                symbol: "record.circle",
                message: "Durable meeting recording arrives in Milestone 4."
            )
        case .history:
            futureDestination(
                title: "History",
                symbol: "clock.arrow.circlepath",
                message: "Complete dictation and recording history arrives in Milestone 5."
            )
        case .settings:
            SettingsView(
                model: settings,
                previewSetup: { onboarding.presentSetup(reset: false) },
                resetSetup: { onboarding.presentSetup(reset: true) }
            )
        }
    }

    private func futureDestination(title: String, symbol: String, message: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: symbol,
            description: Text(message)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.canvas)
    }
}

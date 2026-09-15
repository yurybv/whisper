import SwiftUI

struct AppRootView: View {
    @Bindable var onboarding: OnboardingModel
    @Bindable var home: HomeModel
    @Bindable var modes: ModesModel
    @Bindable var settings: SettingsModel
    @Bindable var recordings: RecordingsModel
    @Bindable var history: HistorySearchModel
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
        recordings: RecordingsModel,
        history: HistorySearchModel,
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
        self.recordings = recordings
        self.history = history
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
                                        .frame(height: 44)
                                        .background(destination == item ? DesignTokens.selected : .clear)
                                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
                                        .contentShape(Rectangle())
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
                                .accessibilityHidden(true)
                            Text(settings.selectedMicrophoneName)
                                .accessibilityLabel("Current microphone")
                                .accessibilityValue(settings.selectedMicrophoneName)
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
            history.reload()
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
            RecordingsView(model: recordings)
        case .history:
            HistoryView(model: history)
        case .settings:
            SettingsView(
                model: settings,
                previewSetup: { onboarding.presentSetup(reset: false) },
                resetSetup: { onboarding.presentSetup(reset: true) }
            )
        }
    }
}

import FaceMacCore
import SwiftUI

/// Settings window, laid out 1:1 with MacBookDuo: sidebar + grouped form panes.
struct SettingsWindowView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SidebarItem? = .general
    @State private var search = ""

    private var activeItem: SidebarItem { selection ?? .general }

    private var filteredItems: [SidebarItem] {
        guard !search.isEmpty else { return SidebarItem.allCases }
        return SidebarItem.allCases.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        let _ = model.uiLanguage
        NavigationSplitView {
            List(filteredItems, selection: $selection) { item in
                SidebarRow(item: item)
                    .tag(item)
                    .id("\(item.id).\(model.uiLanguage.rawValue)")
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
                .navigationTitle(activeItem.title)
                .navigationSplitViewColumnWidth(
                    min: SettingsMetrics.detailMinWidth,
                    ideal: SettingsMetrics.detailIdealWidth
                )
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(L10n.t("settings.previewNotch")) {
                            model.previewNotch()
                        }
                    }
                }
        }
        .searchable(text: $search, placement: .sidebar, prompt: L10n.t("settings.search"))
        .background {
            SettingsWindowChrome()
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch activeItem {
        case .general: GeneralPane(model: model)
        case .recognition: RecognitionPane(model: model)
        case .unlock: UnlockPane(model: model)
        case .lockButton: LockButtonPane(model: model)
        case .about: AboutPane(model: model)
        }
    }
}

private struct SidebarRow: View {
    let item: SidebarItem

    var body: some View {
        Label {
            Text(item.title)
        } icon: {
            SettingsIconBadge(
                symbol: item.symbol,
                color: item.iconColor,
                size: SettingsMetrics.sidebarIconSize
            )
        }
    }
}

private enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case general
    case recognition
    case unlock
    case lockButton
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L10n.t("settings.tab.general")
        case .recognition: L10n.t("settings.recognition")
        case .unlock: L10n.t("settings.unlock")
        case .lockButton: L10n.t("settings.lockScreenButton")
        case .about: L10n.t("settings.tab.about")
        }
    }

    var symbol: String {
        switch self {
        case .general: "face.smiling"
        case .recognition: "eye"
        case .unlock: "lock.open"
        case .lockButton: "button.roundedtop.horizontal"
        case .about: "info.circle"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: SettingsPalette.gray
        case .recognition: SettingsPalette.green
        case .unlock: SettingsPalette.blue
        case .lockButton: SettingsPalette.indigo
        case .about: SettingsPalette.teal
        }
    }
}

// MARK: - Panes

private struct GeneralPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPane {
            Section {
                SettingsHeader(
                    title: "FaceMac",
                    subtitle: L10n.t("settings.generalSubtitle"),
                    appIcon: NSApp.applicationIconImage
                )
            }

            Section {
                NotchPreview(showsText: model.showMatchText)
                    .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
            } header: {
                Text(L10n.t("settings.previewSection"))
            }

            Section {
                Toggle(L10n.t("menu.enabled"), isOn: Binding(
                    get: { model.isEnabled },
                    set: { model.setEnabled($0) }
                ))
                SettingsActionRow(
                    title: L10n.t("settings.previewNotch"),
                    symbol: "play.fill",
                    color: SettingsPalette.green,
                    subtitle: L10n.t("settings.previewNotchHint")
                ) {
                    model.previewNotch()
                }
                SettingsActionRow(
                    title: L10n.t("menu.scanNow"),
                    symbol: "viewfinder",
                    color: SettingsPalette.blue,
                    subtitle: L10n.t("settings.scanNowHint")
                ) {
                    model.scanNow()
                }
            }

            Section {
                SettingsValueRow(
                    title: L10n.t("settings.embedder"),
                    symbol: "cpu",
                    color: SettingsPalette.purple,
                    value: model.embedderName
                )
                SettingsValueRow(
                    title: L10n.t("settings.faceEnrolled"),
                    symbol: "person.crop.circle",
                    color: SettingsPalette.green,
                    value: model.hasEnrollment ? L10n.t("settings.yes") : L10n.t("settings.no")
                )
                SettingsValueRow(
                    title: L10n.t("settings.passwordSaved"),
                    symbol: "key",
                    color: SettingsPalette.orange,
                    value: model.hasPassword ? L10n.t("settings.yes") : L10n.t("settings.no")
                )
                SettingsValueRow(
                    title: L10n.t("settings.accessibility"),
                    symbol: "hand.raised",
                    color: SettingsPalette.indigo,
                    value: model.accessibilityTrusted
                        ? L10n.t("settings.accessibilityGranted")
                        : L10n.t("settings.accessibilityNotGranted")
                )
            } header: {
                Text(L10n.t("settings.status"))
            }

            Section {
                SettingsActionRow(
                    title: L10n.t("menu.enroll"),
                    symbol: "person.badge.plus",
                    color: SettingsPalette.green
                ) {
                    model.beginEnrollment()
                }
                SettingsActionRow(
                    title: L10n.t("menu.forgetFace"),
                    symbol: "trash",
                    color: SettingsPalette.red,
                    isDestructive: true
                ) {
                    model.forgetFace()
                }
            } header: {
                Text(L10n.t("settings.faceData"))
            }
        }
        .onAppear { model.refreshPermissions() }
    }
}

private struct RecognitionPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPane {
            Section {
                HStack {
                    Text(L10n.t("settings.language"))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { model.uiLanguage },
                        set: { model.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                Toggle(L10n.t("settings.showMatchText"), isOn: Binding(
                    get: { model.showMatchText },
                    set: { model.setShowMatchText($0) }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.t("settings.notchWidth"))
                        Spacer()
                        Text(String(format: "%.0f pt", model.notchWidth))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { model.notchWidth },
                            set: { model.updateNotchWidth($0) }
                        ),
                        in: 180...420,
                        step: 4
                    )
                }
            } header: {
                Text(L10n.t("settings.recognition"))
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.t("settings.threshold"))
                        Spacer()
                        Text(String(format: "%.2f", model.threshold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(model.threshold) },
                            set: { model.updateThreshold(Float($0)) }
                        ),
                        in: 0.1...0.9,
                        step: 0.01
                    )
                    Text(L10n.t("settings.thresholdHint"))
                        .foregroundStyle(.secondary)
                }

                Picker(L10n.t("settings.liveness"), selection: Binding(
                    get: { model.livenessMode },
                    set: { model.setLivenessMode($0) }
                )) {
                    ForEach(LivenessMode.allCases, id: \.self) { mode in
                        Text(Self.label(for: mode)).tag(mode)
                    }
                }
                Text(L10n.t("settings.livenessHint"))
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.t("settings.match"))
            }
        }
    }

    private static func label(for mode: LivenessMode) -> String {
        switch mode {
        case .off: return L10n.t("liveness.off")
        case .blink: return L10n.t("liveness.blink")
        case .motion: return L10n.t("liveness.motion")
        case .blinkOrMotion: return L10n.t("liveness.blinkOrMotion")
        case .blinkAndMotion: return L10n.t("liveness.blinkAndMotion")
        }
    }
}

private struct UnlockPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPane {
            Section {
                Stepper(
                    String(format: L10n.t("settings.frames"), model.requiredFrames),
                    value: Binding(
                        get: { model.requiredFrames },
                        set: { model.updateRequiredFrames($0) }
                    ),
                    in: 1...10
                )
                Text(L10n.t("settings.framesHint"))
                    .foregroundStyle(.secondary)

                Toggle(L10n.t("settings.keepAwake"), isOn: Binding(
                    get: { model.keepDisplayAwake },
                    set: { model.setKeepDisplayAwake($0) }
                ))
            } header: {
                Text(L10n.t("settings.scanning"))
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.t("settings.cameraOnFor"))
                        Spacer()
                        Text(String(format: "%.0f s", model.scanTimeout))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { model.scanTimeout },
                            set: { model.updateScanTimeout($0) }
                        ),
                        in: 3...20,
                        step: 1
                    )
                    Text(L10n.t("settings.cameraOnHint"))
                        .foregroundStyle(.secondary)
                }

                Stepper(
                    String(format: L10n.t("settings.maxAttempts"), model.maxAttempts),
                    value: Binding(
                        get: { model.maxAttempts },
                        set: { model.updateMaxAttempts($0) }
                    ),
                    in: 1...10
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.t("settings.cooldown"))
                        Spacer()
                        Text(String(format: "%.1f s", model.unlockCooldown))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { model.unlockCooldown },
                            set: { model.updateCooldown($0) }
                        ),
                        in: 0...10,
                        step: 0.5
                    )
                }
            } header: {
                Text(L10n.t("settings.timing"))
            }

            Section {
                SettingsActionRow(
                    title: model.hasPassword ? L10n.t("menu.changePassword") : L10n.t("menu.setPassword"),
                    symbol: "key.fill",
                    color: SettingsPalette.orange
                ) {
                    model.setPassword()
                }
                SettingsActionRow(
                    title: L10n.t("menu.typePassword"),
                    symbol: "keyboard",
                    color: SettingsPalette.blue
                ) {
                    model.tryUnlockNow()
                }
                if !model.accessibilityTrusted {
                    SettingsActionRow(
                        title: L10n.t("menu.grantAccessibility"),
                        symbol: "hand.raised.fill",
                        color: SettingsPalette.indigo
                    ) {
                        model.requestAccessibility()
                    }
                }
            } header: {
                Text(L10n.t("settings.password"))
            }
        }
        .onAppear { model.refreshPermissions() }
    }
}

private struct LockButtonPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPane {
            Section {
                Toggle(L10n.t("settings.preview"), isOn: Binding(
                    get: { model.retryPreview },
                    set: { model.setRetryPreview($0) }
                ))
                Text(L10n.t("settings.previewHint"))
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.t("settings.lockScreenButton"))
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.t("settings.size"))
                        Spacer()
                        Text(String(format: "%.0f pt", model.retryButtonSize))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { model.retryButtonSize },
                            set: { model.updateRetryButtonSize($0) }
                        ),
                        in: 40...80,
                        step: 2
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.t("settings.horizontal"))
                        Spacer()
                        Text(String(format: "%.0f pt", model.retryOffsetX))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { model.retryOffsetX },
                            set: { model.updateRetryOffsetX($0) }
                        ),
                        in: -200...200,
                        step: 2
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.t("settings.vertical"))
                        Spacer()
                        Text(String(format: "%.1f%%", model.retryVerticalFraction * 100))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { model.retryVerticalFraction },
                            set: { model.updateRetryVerticalFraction($0) }
                        ),
                        in: 0.5...0.95,
                        step: 0.002
                    )
                }
            } header: {
                Text(L10n.t("settings.position"))
            }
        }
    }
}

private struct AboutPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPane {
            Section {
                SettingsHeader(
                    title: "FaceMac",
                    subtitle: L10n.t("settings.aboutBody"),
                    appIcon: NSApp.applicationIconImage
                )
            }

            Section {
                SettingsValueRow(
                    title: L10n.t("settings.license"),
                    symbol: "doc.text",
                    color: SettingsPalette.gray,
                    value: "GPL-3.0"
                )
                SettingsValueRow(
                    title: L10n.t("settings.model"),
                    symbol: "brain",
                    color: SettingsPalette.purple,
                    value: "SFace · Apache-2.0"
                )
            }

            Section {
                SettingsActionRow(
                    title: L10n.t("settings.openGitHub"),
                    symbol: "chevron.left.forwardslash.chevron.right",
                    color: SettingsPalette.gray
                ) {
                    if let url = URL(string: "https://github.com/") {
                        NSWorkspace.shared.open(url)
                    }
                }
                SettingsActionRow(
                    title: L10n.t("menu.quit"),
                    symbol: "power",
                    color: SettingsPalette.red,
                    isDestructive: true
                ) {
                    model.quit()
                }
            } footer: {
                Text(L10n.t("settings.aboutFooter"))
            }
        }
    }
}

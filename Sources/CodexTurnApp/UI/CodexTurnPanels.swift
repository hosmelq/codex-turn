import CodexTurnCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var monitor: SessionMonitor
    @Environment(\.colorScheme) private var colorScheme
    @State private var codexHomePathDraft: String = ""
    @State private var launchAtLoginEnabled: Bool = LaunchAtLoginManager.savedPreference()

    private struct StepperRowConfiguration {
        let range: ClosedRange<Int>
        let step: Int
        let subtitle: String
        let unit: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsCard(title: "Notifications") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notification permission")
                        Text("Allow CodexTurn to send local macOS notifications.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    HStack(spacing: 10) {
                        Text(monitor.hasPermission ? "Enabled" : "Disabled")
                            .foregroundStyle(monitor.hasPermission ? .green : .red)

                        if !monitor.hasPermission {
                            Button("Allow") {
                                Task {
                                    await monitor.requestNotificationPermission()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                #if DEBUG
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Test notification")
                            Text("Send a sample notification to verify alerts are working.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 16)
                        Button("Send") {
                            Task {
                                await monitor.sendTestNotification()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                #endif
            }

            settingsCard(title: "Reminders") {
                stepperRow(
                    title: "Reminder repeat interval",
                    value: reminderMinutesBinding,
                    configuration: StepperRowConfiguration(
                        range: 5...120,
                        step: 1,
                        subtitle: "If a thread is still waiting on you, send another reminder at this interval.",
                        unit: "m"
                    )
                )
                Divider()
                stepperRow(
                    title: "Waiting-on-you threshold",
                    value: idleMinutesBinding,
                    configuration: StepperRowConfiguration(
                        range: 1...120,
                        step: 1,
                        subtitle:
                            "Treat a thread as waiting on you after this many minutes since the assistant replied.",
                        unit: "m"
                    )
                )
            }

            settingsCard(title: "Sessions") {
                codexHomePathRow
                Divider()
                toggleRow(
                    title: "Group worktrees by repository",
                    subtitle: "ON combines Codex worktrees from the same repo. OFF shows each worktree separately.",
                    isOn: $monitor.useRepoRoot
                )
                Divider()
                toggleRow(
                    title: "Start CodexTurn at login",
                    subtitle: "Automatically launch CodexTurn when you sign in to macOS.",
                    isOn: launchAtLoginBinding
                )
                Divider()
                stepperRow(
                    title: "Rescan interval",
                    value: pollSecondsBinding,
                    configuration: StepperRowConfiguration(
                        range: 10...600,
                        step: 10,
                        subtitle: "How often CodexTurn checks session logs for new activity.",
                        unit: "s"
                    )
                )
                Divider()
                stepperRow(
                    title: "Recent activity window",
                    value: recencyWindowBinding,
                    configuration: StepperRowConfiguration(
                        range: 1...24,
                        step: 1,
                        subtitle: "Show only sessions with activity within this number of hours.",
                        unit: "h"
                    )
                )
            }

        }
        .padding(24)
        .frame(width: 500)
        .onAppear {
            codexHomePathDraft = monitor.codexHomePath
            launchAtLoginEnabled = LaunchAtLoginManager.savedPreference()
        }
    }

    private var codexHomePathRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex home folder")
                Text("Change this only if your Codex home is not ~/.codex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField("Use ~/.codex", text: $codexHomePathDraft)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    monitor.codexHomePath = codexHomePathDraft
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Clear") {
                    codexHomePathDraft = ""
                    monitor.codexHomePath = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(codexHomePathDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Session logs path: \(monitor.resolvedCodexSessionsPath)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private var idleMinutesBinding: Binding<Int> {
        Binding(
            get: { Int(monitor.idleMinutes) },
            set: { monitor.idleMinutes = TimeInterval($0) }
        )
    }

    private var pollSecondsBinding: Binding<Int> {
        Binding(
            get: { Int(monitor.pollSeconds) },
            set: { monitor.pollSeconds = TimeInterval($0) }
        )
    }

    private var recencyWindowBinding: Binding<Int> {
        Binding(
            get: { Int(monitor.recencyWindowHours) },
            set: { monitor.recencyWindowHours = TimeInterval($0) }
        )
    }

    private var reminderMinutesBinding: Binding<Int> {
        Binding(
            get: { Int(monitor.reminderMinutes) },
            set: { monitor.reminderMinutes = TimeInterval($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginEnabled },
            set: updateLaunchAtLogin
        )
    }

    private func settingsCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(settingsCardBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(settingsCardBorderColor, lineWidth: 1)
            )
        }
    }

    private var settingsCardBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04)
    }

    private var settingsCardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
    }

    private func stepperRow(
        title: String,
        value: Binding<Int>,
        configuration: StepperRowConfiguration
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(configuration.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            HStack(spacing: 12) {
                Text("\(value.wrappedValue)\(configuration.unit)")
                    .monospacedDigit()
                Stepper(
                    "",
                    value: value,
                    in: configuration.range,
                    step: configuration.step
                )
                .labelsHidden()
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        if LaunchAtLoginManager.setEnabled(enabled) {
            launchAtLoginEnabled = enabled
            return
        }

        let currentStatus = LaunchAtLoginManager.isEnabled()
        launchAtLoginEnabled = currentStatus
        LaunchAtLoginManager.savePreference(currentStatus)
        monitor.statusText = "Couldn't update start-at-login setting"
    }
}

struct ThreadMenuRow: View {
    let badge: String
    let iconName: String
    let isWaiting: Bool
    let message: String
    let meta: String

    private var badgeColor: Color {
        isWaiting ? .orange : .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(badgeColor)
                    .frame(width: 14, height: 14, alignment: .center)
                Text(message)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.15), in: Capsule())
            }
            HStack(spacing: 8) {
                Color.clear
                    .frame(width: 14, height: 14)
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: 320, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

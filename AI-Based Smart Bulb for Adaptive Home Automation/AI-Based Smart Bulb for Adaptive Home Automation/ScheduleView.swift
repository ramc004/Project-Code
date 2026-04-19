import SwiftUI
import HealthKit

// MARK: - Main Schedule View

struct ScheduleView: View {
    let bulbId: String
    let bulbName: String

    @StateObject private var manager = ScheduleManager.shared
    @State private var showAddSheet = false
    @State private var editingSchedule: BulbSchedule?
    @State private var showAutoToggleInfo = false
    @State private var showHealthPermission = false
    @State private var showHealthRevoke = false
    @State private var selectedTab = 0   // 0=Schedules 1=Suggestions
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.15),
                    Color(red: 0.12, green: 0.10, blue: 0.22),
                    Color(red: 0.08, green: 0.12, blue: 0.20)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ────────────────────────────────────────────────
                HStack(spacing: 14) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Schedules")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Text(bulbName)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    Spacer()

                    // Auto mode pill
                    Button(action: { showAutoToggleInfo = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: manager.autoScheduleEnabled ? "cpu.fill" : "hand.tap.fill")
                                .font(.system(size: 11))
                            Text(manager.autoScheduleEnabled ? "Auto" : "Manual")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(manager.autoScheduleEnabled ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(manager.autoScheduleEnabled ?
                                    Color(red: 0.4, green: 0.9, blue: 0.6) :
                                    Color.white.opacity(0.15))
                        .clipShape(Capsule())
                    }

                    // Add button
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color(red: 0.3, green: 0.5, blue: 1.0))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 20)

                // ── Health Banner ─────────────────────────────────────────
                if manager.healthKitAvailable && !manager.healthKitAuthorised {
                    HealthPermissionBanner { showHealthPermission = true }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                } else if manager.healthKitAvailable && manager.healthKitAuthorised {
                    if let bedtime = manager.sleepBedtime, let wake = manager.sleepWakeTime {
                        SleepSummaryBanner(bedtime: bedtime, wakeTime: wake) {
                            showHealthRevoke = true
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                    } else {
                        // Authorised but no sleep data yet
                        SleepLinkedBanner { showHealthRevoke = true }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)
                    }
                }

                // ── Segment ───────────────────────────────────────────────
                HStack(spacing: 0) {
                    ForEach(["My Schedules", "AI Suggestions"], id: \.self) { tab in
                        let idx = tab == "My Schedules" ? 0 : 1
                        Button(action: { withAnimation(.spring()) { selectedTab = idx } }) {
                            VStack(spacing: 4) {
                                Text(tab)
                                    .font(.system(size: 14, weight: selectedTab == idx ? .bold : .regular))
                                    .foregroundColor(selectedTab == idx ? .white : .white.opacity(0.4))
                                if selectedTab == idx {
                                    Capsule()
                                        .fill(Color(red: 0.4, green: 0.6, blue: 1.0))
                                        .frame(width: 30, height: 3)
                                } else {
                                    Capsule()
                                        .fill(Color.clear)
                                        .frame(width: 30, height: 3)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }

                        // Badge on suggestions
                        .overlay(alignment: .topTrailing) {
                            if idx == 1 && !manager.suggestions.isEmpty {
                                Text("\(manager.suggestions.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(minWidth: 16)
                                    .padding(.horizontal, 4)
                                    .background(Color(red: 1.0, green: 0.35, blue: 0.35))
                                    .clipShape(Capsule())
                                    .offset(x: -20, y: -2)
                            }
                        }
                    }
                }
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // ── Content ───────────────────────────────────────────────
                if selectedTab == 0 {
                    ScheduleListTab(
                        schedules: manager.schedules,
                        isLoading: manager.isLoadingSchedules,
                        onToggle: { id, enabled in manager.toggleSchedule(id, enabled: enabled) },
                        onDelete: { id in manager.deleteSchedule(id, bulbId: bulbId) },
                        onEdit: { s in editingSchedule = s },
                        onAdd: { showAddSheet = true }
                    )
                } else {
                    SuggestionsTab(
                        suggestions: manager.suggestions,
                        isLoading: manager.isLoadingSuggestions,
                        sleepBedtime: manager.sleepBedtime,
                        sleepWakeTime: manager.sleepWakeTime,
                        onAccept: { id in manager.respondToSuggestion(id: id, response: "accept", bulbId: bulbId) },
                        onDismiss: { id in manager.respondToSuggestion(id: id, response: "dismiss", bulbId: bulbId) },
                        onAutoAcceptAll: {
                            for s in manager.suggestions {
                                manager.respondToSuggestion(id: s.id, response: "auto", bulbId: bulbId)
                            }
                        },
                        onRefresh: { manager.analyseUsage(bulbId: bulbId) }
                    )
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showAddSheet) {
            AddScheduleSheet(bulbId: bulbId, bulbName: bulbName)
        }
        .sheet(item: $editingSchedule) { s in
            EditScheduleSheet(schedule: s, bulbId: bulbId)
        }
        .sheet(isPresented: $showHealthPermission) {
            HealthPermissionSheet()
        }
        .sheet(isPresented: $showHealthRevoke) {
            HealthRevokeSheet()
        }
        .alert("Scheduling Mode", isPresented: $showAutoToggleInfo) {
            Button(manager.autoScheduleEnabled ? "Switch to Manual" : "Enable Auto") {
                manager.setAutoSchedule(enabled: !manager.autoScheduleEnabled)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(manager.autoScheduleEnabled
                 ? "Auto mode fires schedules automatically. Switch to Manual to only receive suggestions."
                 : "Manual mode shows suggestions for you to approve. Enable Auto to fire schedules automatically.")
        }
        .onAppear {
            manager.loadSchedules(for: bulbId)
            manager.loadSuggestions(for: bulbId)
            manager.analyseUsage(bulbId: bulbId)
        }
    }
}

// MARK: - Schedule List Tab

struct ScheduleListTab: View {
    let schedules: [BulbSchedule]
    let isLoading: Bool
    let onToggle: (Int, Bool) -> Void
    let onDelete: (Int) -> Void
    let onEdit: (BulbSchedule) -> Void
    let onAdd: () -> Void

    var body: some View {
        if isLoading {
            Spacer()
            ProgressView().tint(.white).scaleEffect(1.3)
            Spacer()
        } else if schedules.isEmpty {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 52))
                    .foregroundColor(.white.opacity(0.25))
                Text("No Schedules Yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                Text("Add a schedule or accept an AI suggestion")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
                Button(action: onAdd) {
                    Label("Add Schedule", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.3, green: 0.5, blue: 1.0))
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 40)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(schedules) { schedule in
                        ScheduleCard(
                            schedule: schedule,
                            onToggle: { onToggle(schedule.id, $0) },
                            onDelete: { onDelete(schedule.id) },
                            onEdit: { onEdit(schedule) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }
}

// MARK: - Schedule Card

struct ScheduleCard: View {
    let schedule: BulbSchedule
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    @State private var isEnabled: Bool

    init(schedule: BulbSchedule, onToggle: @escaping (Bool) -> Void, onDelete: @escaping () -> Void, onEdit: @escaping () -> Void) {
        self.schedule = schedule
        self.onToggle = onToggle
        self.onDelete = onDelete
        self.onEdit = onEdit
        _isEnabled = State(initialValue: schedule.isEnabled)
    }

    var actionColour: Color {
        switch schedule.action {
        case .powerOn:          return Color(red: 0.3, green: 0.9, blue: 0.5)
        case .powerOff:         return Color(red: 0.9, green: 0.3, blue: 0.3)
        case .dimWarm:          return Color(red: 1.0, green: 0.65, blue: 0.2)
        case .brightenCool:     return Color(red: 0.4, green: 0.8, blue: 1.0)
        default:                return Color(red: 0.6, green: 0.6, blue: 1.0)
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Time block
            VStack(spacing: 2) {
                Text(String(format: "%02d", schedule.triggerHour))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(isEnabled ? .white : .white.opacity(0.3))
                Text(String(format: "%02d", schedule.triggerMinute))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(isEnabled ? .white.opacity(0.6) : .white.opacity(0.2))
            }
            .frame(width: 46)

            // Divider
            RoundedRectangle(cornerRadius: 2)
                .fill(actionColour.opacity(isEnabled ? 0.7 : 0.2))
                .frame(width: 3, height: 44)

            // Info
            VStack(alignment: .leading, spacing: 5) {
                Text(schedule.scheduleName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isEnabled ? .white : .white.opacity(0.4))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(schedule.action.displayName, systemImage: schedule.action.icon)
                        .font(.system(size: 11))
                        .foregroundColor(actionColour.opacity(isEnabled ? 1 : 0.4))
                    if schedule.source != "manual" {
                        Label(schedule.sourceLabel, systemImage: schedule.sourceIcon)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
            }

            Spacer()

            // Toggle + menu — larger tap targets
            HStack(spacing: 12) {
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.4, green: 0.9, blue: 0.6)))
                    .onChange(of: isEnabled) { onToggle($0) }
                    .scaleEffect(0.85)

                Menu {
                    Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(isEnabled ? 0.08 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(actionColour.opacity(isEnabled ? 0.2 : 0.05), lineWidth: 1)
                )
        )
    }
}

// MARK: - Suggestions Tab

struct SuggestionsTab: View {
    let suggestions: [ScheduleSuggestion]
    let isLoading: Bool
    let sleepBedtime: Date?
    let sleepWakeTime: Date?
    let onAccept: (Int) -> Void
    let onDismiss: (Int) -> Void
    let onAutoAcceptAll: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        if isLoading {
            Spacer()
            VStack(spacing: 12) {
                ProgressView().tint(.white).scaleEffect(1.3)
                Text("Analysing usage patterns…")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
            }
            Spacer()
        } else if suggestions.isEmpty {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 52))
                    .foregroundColor(.white.opacity(0.2))
                Text("No Suggestions Yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                Text("Keep using your light — the AI learns your patterns over time")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
                Button(action: onRefresh) {
                    Label("Analyse Now", systemImage: "cpu")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.5, green: 0.3, blue: 1.0))
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 40)
            Spacer()
        } else {
            VStack(spacing: 0) {
                // Sleep hint banner inside suggestions tab
                if let bedtime = sleepBedtime, let wake = sleepWakeTime {
                    SleepHintBanner(bedtime: bedtime, wakeTime: wake)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                // Accept all button
                if suggestions.count > 1 {
                    Button(action: onAutoAcceptAll) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                            Text("Accept All \(suggestions.count) Suggestions")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            LinearGradient(colors: [Color(red: 0.3, green: 0.6, blue: 0.4), Color(red: 0.2, green: 0.7, blue: 0.5)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                }

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(suggestions) { suggestion in
                            SuggestionCard(suggestion: suggestion,
                                           onAccept: { onAccept(suggestion.id) },
                                           onDismiss: { onDismiss(suggestion.id) })
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
        }
    }
}

// MARK: - Suggestion Card

struct SuggestionCard: View {
    let suggestion: ScheduleSuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var confidenceColour: Color {
        suggestion.confidence >= 0.8 ? Color(red: 0.2, green: 0.85, blue: 0.5) :
        suggestion.confidence >= 0.65 ? Color(red: 1.0, green: 0.65, blue: 0.2) :
        Color(red: 1.0, green: 0.85, blue: 0.2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: suggestion.isSleepBased ? "moon.zzz.fill" : "cpu.fill")
                            .font(.system(size: 11))
                            .foregroundColor(suggestion.isSleepBased ?
                                             Color(red: 0.6, green: 0.4, blue: 1.0) :
                                             Color(red: 0.4, green: 0.7, blue: 1.0))
                        Text(suggestion.isSleepBased ? "Sleep-Linked" : "AI Detected")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(suggestion.isSleepBased ?
                                             Color(red: 0.6, green: 0.4, blue: 1.0) :
                                             Color(red: 0.4, green: 0.7, blue: 1.0))
                    }
                    Text(suggestion.readableType)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()

                // Confidence badge
                VStack(spacing: 2) {
                    Text("\(suggestion.confidencePercent)%")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(confidenceColour)
                    Text("confidence")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            // Details row
            HStack(spacing: 16) {
                DetailPill(icon: "clock.fill",
                           text: suggestion.isSleepBased ? suggestion.timeString : suggestion.windowString,
                           label: suggestion.isSleepBased ? "Time" : "Window")

                DetailPill(icon: suggestion.action.icon,
                           text: suggestion.action.displayName,
                           label: "Action")

                if !suggestion.isSleepBased {
                    DetailPill(icon: "chart.bar.fill",
                               text: "\(suggestion.observationCount)×",
                               label: "Observed")
                }
            }

            // Brightness preview bar
            if suggestion.action != .powerOff && suggestion.action != .powerOn {
                HStack(spacing: 10) {
                    Image(systemName: "sun.min.fill").font(.system(size: 10)).foregroundColor(.white.opacity(0.3))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)).frame(height: 6)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.75, blue: 0.4), Color(red: 0.9, green: 0.95, blue: 1.0)],
                                        startPoint: suggestion.colourTemp > 128 ? .trailing : .leading,
                                        endPoint: suggestion.colourTemp > 128 ? .leading : .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(suggestion.brightness) / 255.0, height: 6)
                        }
                    }
                    .frame(height: 6)
                    Image(systemName: "sun.max.fill").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                }
            }

            // Action buttons
            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    Label("Dismiss", systemImage: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(10)
                }

                Button(action: onAccept) {
                    Label("Add Schedule", systemImage: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(confidenceColour)
                        .cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(confidenceColour.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct DetailPill: View {
    let icon: String; let text: String; let label: String
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                Text(text).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            }
            Text(label).font(.system(size: 9)).foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .cornerRadius(8)
    }
}

// MARK: - Health Banners

struct HealthPermissionBanner: View {
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color(red: 1.0, green: 0.3, blue: 0.5))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect Apple Health")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text("Automatically dim lights at bedtime & brighten at wake-up")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 1.0, green: 0.2, blue: 0.4).opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(red: 1.0, green: 0.3, blue: 0.5).opacity(0.3), lineWidth: 1))
            )
        }
    }
}

/// Shown when authorised + sleep data loaded — tapping opens revoke sheet
struct SleepSummaryBanner: View {
    let bedtime: Date
    let wakeTime: Date
    let onManage: () -> Void

    private let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        Button(action: onManage) {
            HStack(spacing: 16) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sleep Schedule Linked")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("Bedtime \(fmt.string(from: bedtime))  ·  Wake \(fmt.string(from: wakeTime))")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.3), lineWidth: 1))
            )
        }
    }
}

/// Shown when authorised but no sleep data yet
struct SleepLinkedBanner: View {
    let onManage: () -> Void
    var body: some View {
        Button(action: onManage) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.5))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Health Access Granted")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("Sleep data will appear when available from Apple Health")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.1, green: 0.4, blue: 0.2).opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(red: 0.3, green: 0.85, blue: 0.5).opacity(0.3), lineWidth: 1))
            )
        }
    }
}

/// Small inline hint shown in Suggestions tab when sleep data is available
struct SleepHintBanner: View {
    let bedtime: Date
    let wakeTime: Date
    private let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
            Text("Sleep-linked: bedtime \(fmt.string(from: bedtime)) · wake \(fmt.string(from: wakeTime))")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.55))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.12))
        .cornerRadius(10)
    }
}

// MARK: - Health Permission Sheet

struct HealthPermissionSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var requesting = false
    @State private var result: String = ""

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.12).ignoresSafeArea()
            VStack(spacing: 30) {
                Spacer()
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 72))
                    .foregroundColor(Color(red: 1.0, green: 0.3, blue: 0.5))

                VStack(spacing: 12) {
                    Text("Sleep-Linked Lighting")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text("Connect Apple Health so your lights automatically wind down before bed and gently brighten before wake-up.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                VStack(alignment: .leading, spacing: 16) {
                    HealthFeatureRow(icon: "moon.fill", colour: Color(red: 0.6, green: 0.4, blue: 1.0),
                                     title: "Wind-down Dim",
                                     desc: "Lights dim to warm 15 min before your sleep time")
                    HealthFeatureRow(icon: "sun.max.fill", colour: Color(red: 1.0, green: 0.8, blue: 0.3),
                                     title: "Gentle Wake-Up",
                                     desc: "Lights gradually brighten 15 min before you wake")
                    HealthFeatureRow(icon: "lock.fill", colour: Color(red: 0.3, green: 0.85, blue: 0.5),
                                     title: "Read-Only Access",
                                     desc: "Only sleep data is read. Nothing is written to Health.")
                }
                .padding(20)
                .background(Color.white.opacity(0.05))
                .cornerRadius(18)
                .padding(.horizontal, 20)

                if !result.isEmpty {
                    Text(result)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                Button(action: requestAccess) {
                    HStack(spacing: 8) {
                        if requesting { ProgressView().tint(.black).scaleEffect(0.8) }
                        Text(requesting ? "Requesting…" : "Allow Health Access")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 1.0, green: 0.3, blue: 0.5))
                    .cornerRadius(16)
                }
                .padding(.horizontal, 20)
                .disabled(requesting)

                Button("Not Now") { dismiss() }
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 10)

                Spacer()
            }
        }
    }

    func requestAccess() {
        requesting = true
        ScheduleManager.shared.requestHealthKitPermission { success, _ in
            requesting = false
            result = success
                ? "✓ Connected! Sleep schedules will appear shortly."
                : "Permission denied. You can enable it in Settings > Health."
            if success { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() } }
        }
    }
}

// MARK: - Health Revoke Sheet

struct HealthRevokeSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.12).ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 64))
                    .foregroundColor(Color(red: 1.0, green: 0.3, blue: 0.5))

                VStack(spacing: 10) {
                    Text("Health Access")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text("Apple Health sleep data is currently connected and used to generate sleep-linked lighting suggestions.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                VStack(spacing: 12) {
                    HealthFeatureRow(
                        icon: "checkmark.circle.fill",
                        colour: Color(red: 0.3, green: 0.85, blue: 0.5),
                        title: "Currently Active",
                        desc: "Sleep data is being read to personalise your schedules"
                    )
                    HealthFeatureRow(
                        icon: "lock.fill",
                        colour: Color(red: 0.6, green: 0.7, blue: 1.0),
                        title: "Read-Only",
                        desc: "This app never writes anything to Apple Health"
                    )
                }
                .padding(20)
                .background(Color.white.opacity(0.05))
                .cornerRadius(18)
                .padding(.horizontal, 20)

                // Revoke instructions — iOS doesn't expose a programmatic revoke API,
                // so we direct the user to Settings > Health as Apple requires.
                VStack(spacing: 16) {
                    Text("To revoke access:")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))

                    VStack(alignment: .leading, spacing: 10) {
                        RevokeStep(number: "1", text: "Open the Health app")
                        RevokeStep(number: "2", text: "Tap your profile photo → Apps")
                        RevokeStep(number: "3", text: "Find this app and tap Turn Off All")
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(14)
                    .padding(.horizontal, 20)

                    Button(action: openHealthSettings) {
                        Label("Open Health App", systemImage: "heart.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 1.0, green: 0.25, blue: 0.45))
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 20)
                }

                Button("Done") { dismiss() }
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 10)

                Spacer()
            }
        }
    }

    func openHealthSettings() {
        if let url = URL(string: "x-apple-health://") {
            UIApplication.shared.open(url)
        }
    }
}

struct RevokeStep: View {
    let number: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 22, height: 22)
                .background(Color(red: 1.0, green: 0.3, blue: 0.5))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

struct HealthFeatureRow: View {
    let icon: String; let colour: Color; let title: String; let desc: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(colour).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text(desc).font(.system(size: 12)).foregroundColor(.white.opacity(0.45))
            }
        }
    }
}

// MARK: - Add Schedule Sheet

struct AddScheduleSheet: View {
    let bulbId: String
    let bulbName: String

    @StateObject private var manager = ScheduleManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var selectedAction: ScheduleAction = .powerOn
    @State private var triggerTime = Date()
    @State private var brightness: Double = 200
    @State private var colourTemp: Double = 128
    @State private var daysSelected = [true, true, true, true, true, true, true]
    @State private var saving = false
    @State private var error = ""

    private let dayLabels = ["M","T","W","T","F","S","S"]

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.14).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    HStack {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("New Schedule").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                        Spacer()
                        Button("Save") { save() }
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(name.isEmpty ? .white.opacity(0.25) : Color(red: 0.4, green: 0.8, blue: 1.0))
                            .disabled(name.isEmpty || saving)
                    }
                    .padding(.top, 10)

                    // Sleep hint in Add sheet
                    if let bedtime = manager.sleepBedtime, let wake = manager.sleepWakeTime {
                        SleepHintBanner(bedtime: bedtime, wakeTime: wake)
                    }

                    // Name
                    SheetSection(title: "Schedule Name") {
                        TextField("e.g. Evening Dim", text: $name)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.07))
                            .cornerRadius(12)
                    }

                    // Time
                    SheetSection(title: "Trigger Time") {
                        DatePicker("", selection: $triggerTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .colorScheme(.dark)
                            .frame(maxWidth: .infinity)
                    }

                    // Action
                    SheetSection(title: "Action") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(ScheduleAction.allCases, id: \.self) { action in
                                Button(action: { selectedAction = action }) {
                                    Label(action.displayName, systemImage: action.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(selectedAction == action ? .black : .white.opacity(0.7))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(selectedAction == action ?
                                                    Color(red: 0.4, green: 0.85, blue: 0.6) :
                                                    Color.white.opacity(0.07))
                                        .cornerRadius(10)
                                }
                            }
                        }
                    }

                    // Brightness / colour (only relevant actions)
                    if selectedAction != .powerOff && selectedAction != .powerOn {
                        SheetSection(title: "Brightness (\(Int(brightness / 255 * 100))%)") {
                            HStack {
                                Image(systemName: "sun.min.fill").foregroundColor(.white.opacity(0.3))
                                Slider(value: $brightness, in: 0...255, step: 1)
                                    .accentColor(Color(red: 1.0, green: 0.8, blue: 0.3))
                                Image(systemName: "sun.max.fill").foregroundColor(.white.opacity(0.7))
                            }
                        }

                        SheetSection(title: "Colour Temperature") {
                            HStack {
                                Text("Cool").font(.system(size: 11)).foregroundColor(Color(red: 0.7, green: 0.9, blue: 1.0))
                                Slider(value: $colourTemp, in: 0...255, step: 1)
                                    .accentColor(Color(red: 1.0, green: 0.75, blue: 0.4))
                                Text("Warm").font(.system(size: 11)).foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.4))
                            }
                        }
                    }

                    // Days
                    SheetSection(title: "Repeat") {
                        HStack(spacing: 8) {
                            ForEach(0..<7) { i in
                                Button(action: { daysSelected[i].toggle() }) {
                                    Text(dayLabels[i])
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(daysSelected[i] ? .black : .white.opacity(0.4))
                                        .frame(width: 38, height: 38)
                                        .background(daysSelected[i] ? Color(red: 0.4, green: 0.8, blue: 1.0) : Color.white.opacity(0.08))
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if !error.isEmpty {
                        Text(error).foregroundColor(.red).font(.system(size: 13)).padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
    }

    func save() {
        saving = true
        let cal = Calendar.current
        let h = cal.component(.hour, from: triggerTime)
        let m = cal.component(.minute, from: triggerTime)
        let days = daysSelected.enumerated().compactMap { $1 ? $0 + 1 : nil }
        let daysStr = days.map { String($0) }.joined(separator: ",")
        let req = NewScheduleRequest(
            bulbId: bulbId, name: name.isEmpty ? "Schedule" : name,
            triggerHour: h, triggerMinute: m, endHour: nil, endMinute: nil,
            action: selectedAction,
            brightness: Int(brightness), colourTemp: Int(colourTemp),
            daysOfWeek: daysStr.isEmpty ? "1,2,3,4,5,6,7" : daysStr
        )
        manager.addSchedule(req) { success in
            saving = false
            if success { dismiss() } else { error = "Failed to save. Try again." }
        }
    }
}

// MARK: - Edit Schedule Sheet

struct EditScheduleSheet: View {
    let schedule: BulbSchedule
    let bulbId: String

    @StateObject private var manager = ScheduleManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var selectedAction: ScheduleAction
    @State private var triggerTime: Date
    @State private var brightness: Double
    @State private var colourTemp: Double
    @State private var daysSelected: [Bool]
    @State private var saving = false
    @State private var error = ""

    private let dayLabels = ["M","T","W","T","F","S","S"]

    init(schedule: BulbSchedule, bulbId: String) {
        self.schedule = schedule
        self.bulbId = bulbId
        _name = State(initialValue: schedule.scheduleName)
        _selectedAction = State(initialValue: schedule.action)
        var comps = DateComponents()
        comps.hour = schedule.triggerHour
        comps.minute = schedule.triggerMinute
        _triggerTime = State(initialValue: Calendar.current.date(from: comps) ?? Date())
        _brightness = State(initialValue: Double(schedule.brightness))
        _colourTemp = State(initialValue: Double(schedule.colourTemp))

        // Parse days string into booleans [Mon…Sun] (days are 1-based, 1=Mon)
        let activeDays = schedule.daysOfWeek.split(separator: ",").compactMap { Int($0) }
        _daysSelected = State(initialValue: (1...7).map { activeDays.contains($0) })
    }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.14).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    HStack {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("Edit Schedule")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button("Save") { save() }
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0))
                            .disabled(saving)
                    }
                    .padding(.top, 20)

                    // Sleep hint
                    if let bedtime = manager.sleepBedtime, let wake = manager.sleepWakeTime {
                        SleepHintBanner(bedtime: bedtime, wakeTime: wake)
                    }

                    // Name
                    SheetSection(title: "Schedule Name") {
                        TextField("Schedule name", text: $name)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.07))
                            .cornerRadius(12)
                    }

                    // Time
                    SheetSection(title: "Trigger Time") {
                        DatePicker("", selection: $triggerTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .colorScheme(.dark)
                            .frame(maxWidth: .infinity)
                    }

                    // Action
                    SheetSection(title: "Action") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(ScheduleAction.allCases, id: \.self) { action in
                                Button(action: { selectedAction = action }) {
                                    Label(action.displayName, systemImage: action.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(selectedAction == action ? .black : .white.opacity(0.7))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(selectedAction == action ?
                                                    Color(red: 0.4, green: 0.85, blue: 0.6) :
                                                    Color.white.opacity(0.07))
                                        .cornerRadius(10)
                                }
                            }
                        }
                    }

                    // Brightness / colour — shown whenever action uses them
                    if selectedAction != .powerOff && selectedAction != .powerOn {
                        SheetSection(title: "Brightness (\(Int(brightness / 255 * 100))%)") {
                            HStack {
                                Image(systemName: "sun.min.fill").foregroundColor(.white.opacity(0.3))
                                Slider(value: $brightness, in: 0...255, step: 1)
                                    .accentColor(Color(red: 1.0, green: 0.8, blue: 0.3))
                                Image(systemName: "sun.max.fill").foregroundColor(.white.opacity(0.7))
                            }
                        }

                        SheetSection(title: "Colour Temperature") {
                            HStack {
                                Text("Cool").font(.system(size: 11)).foregroundColor(Color(red: 0.7, green: 0.9, blue: 1.0))
                                Slider(value: $colourTemp, in: 0...255, step: 1)
                                    .accentColor(Color(red: 1.0, green: 0.75, blue: 0.4))
                                Text("Warm").font(.system(size: 11)).foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.4))
                            }
                        }
                    }

                    // Days
                    SheetSection(title: "Repeat") {
                        HStack(spacing: 8) {
                            ForEach(0..<7) { i in
                                Button(action: { daysSelected[i].toggle() }) {
                                    Text(dayLabels[i])
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(daysSelected[i] ? .black : .white.opacity(0.4))
                                        .frame(width: 38, height: 38)
                                        .background(daysSelected[i] ? Color(red: 0.4, green: 0.8, blue: 1.0) : Color.white.opacity(0.08))
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if !error.isEmpty {
                        Text(error).foregroundColor(.red).font(.system(size: 13)).padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
    }

    func save() {
        saving = true
        let cal = Calendar.current
        let h = cal.component(.hour, from: triggerTime)
        let m = cal.component(.minute, from: triggerTime)
        let days = daysSelected.enumerated().compactMap { $1 ? $0 + 1 : nil }
        let daysStr = days.map { String($0) }.joined(separator: ",")
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(endpoint: "/update_schedule", body: [
            "email": email,
            "schedule_id": schedule.id,
            "schedule_name": name,
            "trigger_hour": h,
            "trigger_minute": m,
            "action": selectedAction.rawValue,
            "brightness": Int(brightness),
            "colour_temp": Int(colourTemp),
            "days_of_week": daysStr.isEmpty ? "1,2,3,4,5,6,7" : daysStr
        ]) { result in
            saving = false
            if case .success = result {
                manager.loadSchedules(for: bulbId)
                dismiss()
            } else {
                error = "Failed to save."
            }
        }
    }
}

// MARK: - Sheet Section helper

struct SheetSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
                .tracking(1.5)
            content
        }
    }
}

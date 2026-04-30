// ScheduleView.swift
// AI-Based Smart Bulb for Adaptive Home Automation

// Presents the full scheduling interface for a single bulb, combining a user-managed schedule list, AI-generated suggestions derived from usage patterns, and optional Apple Health sleep-linked automation

// The view is split into two tabs "My Schedules" and "AI Suggestions" and surfaces relevant HealthKit banners depending on the current authorisation state
// Sheet overlays allow the user to add a new schedule, edit an existing one, and manage HealthKit permission from within the same screen

import SwiftUI
import HealthKit

// MARK: - Main Schedule View

/// The root view of the scheduling feature, scoped to a single bulb identified by "bulbId" and "bulbName"

/// Owns the tab switcher between "My Schedules" and "AI Suggestions", the header with the auto/manual mode toggle, all Health-related banners, and the sheet presentations for adding, editing, and managing HealthKit access

/// On appearance, "ScheduleManager" is instructed to reload schedules, reload suggestions, and trigger a fresh usage analysis for the given bulb so all three data sources are up to date when the view first renders
struct ScheduleView: View {
    let bulbId: String
    let bulbName: String

    /// The shared schedule manager, observed for schedule list, suggestion list, loading states, and HealthKit status
    @StateObject private var manager = ScheduleManager.shared

    /// Controls presentation of the "AddScheduleSheet" modal
    @State private var showAddSheet = false

    /// The schedule currently being edited; setting a non-nil value triggers the "EditScheduleSheet" modal
    @State private var editingSchedule: BulbSchedule?

    /// Controls the alert that explains and toggles between Auto and Manual scheduling modes
    @State private var showAutoToggleInfo = false

    /// Controls presentation of the "HealthPermissionSheet" modal
    @State private var showHealthPermission = false

    /// Controls presentation of the "HealthRevokeSheet" modal
    @State private var showHealthRevoke = false

    /// The currently active tab: 0 = My Schedules, 1 = AI Suggestions
    @State private var selectedTab = 0

    /// Used to dismiss this view and return to the previous screen
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            // Deep navy-to-purple diagonal gradient used as the global background
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

                // Header
                // Back button, bulb name subtitle, auto/manual mode pill, and add (+) button
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

                    // Auto/Manual mode pill
                    // Tapping opens an alert that explains the difference and lets the user switch
                    // Green pill = Auto (schedules fire automatically); white = Manual (suggestions only)
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

                    // Add schedule button - opens AddScheduleSheet
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

                // Health Banner
                // Three mutually exclusive states are handled:
                // 1. HealthKit is available but not yet authorised → prompt banner
                // 2. HealthKit is authorised and sleep data is loaded → sleep summary banner
                // 3. HealthKit is authorised but sleep data not yet available → "linked, waiting" banner
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
                        // Authorised but no sleep data yet available from Apple Health
                        SleepLinkedBanner { showHealthRevoke = true }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)
                    }
                }

                // Segment Picker
                // Two-tab underline picker switching between "My Schedules" and "AI Suggestions"
                // A red count badge is shown on the Suggestions tab when pending suggestions exist
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

                        // Red count badge overlaid on the Suggestions tab when pending suggestions exist
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

                // Tab Content
                // Renders either ScheduleListTab or SuggestionsTab depending on the selected segment
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
        // Alert explaining Auto vs Manual mode with a single toggle action
        .alert("Scheduling Mode", isPresented: $showAutoToggleInfo) {
            Button(manager.autoScheduleEnabled ? "Switch to Manual" : "Enable Auto") {
                manager.setAutoSchedule(enabled: !manager.autoScheduleEnabled)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(manager.autoScheduleEnabled
                 ? "Auto mode execute schedules automatically. Switch to Manual to only receive suggestions."
                 : "Manual mode shows suggestions for you to approve. Enable Auto to fire schedules automatically.")
        }
        // Trigger all three data loads on first appearance so the view is fully populated
        .onAppear {
            manager.loadSchedules(for: bulbId)
            manager.loadSuggestions(for: bulbId)
            manager.analyseUsage(bulbId: bulbId)
        }
    }
}

// MARK: - Schedule List Tab

/// The content of the "My Schedules" tab

/// Shows a loading spinner while "isLoading" is true, an empty-state prompt when there are no schedules, or a scrollable "LazyVStack" of "ScheduleCard" rows when schedules are present

/// All user interactions (toggle, delete, edit, add) are forwarded to the parent view via closures so that "ScheduleView" remains the single owner of "ScheduleManager"
struct ScheduleListTab: View {
    /// The current list of schedules to display
    let schedules: [BulbSchedule]

    /// When true a loading spinner is shown instead of the schedule list or empty state
    let isLoading: Bool

    /// Called when the user flips the enable/disable toggle on a schedule row; receives the schedule ID and new state
    let onToggle: (Int, Bool) -> Void

    /// Called when the user selects "Delete" from a schedule row's context menu; receives the schedule ID
    let onDelete: (Int) -> Void

    /// Called when the user selects "Edit" from a schedule row's context menu; receives the full schedule model
    let onEdit: (BulbSchedule) -> Void

    /// Called when the user taps the "Add Schedule" button in the empty state
    let onAdd: () -> Void

    var body: some View {
        if isLoading {
            Spacer()
            ProgressView().tint(.white).scaleEffect(1.3)
            Spacer()
        } else if schedules.isEmpty {
            // Empty state with a calendar icon, descriptive text, and a primary "Add Schedule" CTA
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

/// A single row in the schedule list representing one "BulbSchedule"

/// Displays the trigger time in monospaced digits, a coloured vertical accent bar whose colour reflects the scheduled action, the schedule name, action label, and source badge

/// The enable/disable toggle is managed with local "@State" so it responds instantly without waiting for a network round-trip; the change is also forwarded to the parent via "onToggle"

/// An ellipsis context menu provides "Edit" and "Delete" actions forwarded to the parent via closures
struct ScheduleCard: View {
    /// The schedule model to display
    let schedule: BulbSchedule

    /// Called when the user flips the toggle; receives the new enabled state
    let onToggle: (Bool) -> Void

    /// Called when the user taps "Delete" in the context menu
    let onDelete: () -> Void

    /// Called when the user taps "Edit" in the context menu
    let onEdit: () -> Void

    /// Local copy of the enabled state so the toggle animates immediately without a network round-trip
    @State private var isEnabled: Bool

    init(schedule: BulbSchedule, onToggle: @escaping (Bool) -> Void, onDelete: @escaping () -> Void, onEdit: @escaping () -> Void) {
        self.schedule = schedule
        self.onToggle = onToggle
        self.onDelete = onDelete
        self.onEdit = onEdit
        _isEnabled = State(initialValue: schedule.isEnabled)
    }

    /// The accent colour of the vertical bar and action label, derived from the schedule's action type

    /// - Green:  Power On
    /// - Red:    Power Off
    /// - Amber:  Dim Warm
    /// - Blue:   Brighten Cool
    /// - Purple: Any other action
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
            // Time block, hour and minute stacked in monospaced digits
            VStack(spacing: 2) {
                Text(String(format: "%02d", schedule.triggerHour))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(isEnabled ? .white : .white.opacity(0.3))
                Text(String(format: "%02d", schedule.triggerMinute))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(isEnabled ? .white.opacity(0.6) : .white.opacity(0.2))
            }
            .frame(width: 46)

            // Vertical accent bar, colour reflects action type; fades when disabled
            RoundedRectangle(cornerRadius: 2)
                .fill(actionColour.opacity(isEnabled ? 0.7 : 0.2))
                .frame(width: 3, height: 44)

            // Schedule name and action/source labels
            VStack(alignment: .leading, spacing: 5) {
                Text(schedule.scheduleName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isEnabled ? .white : .white.opacity(0.4))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(schedule.action.displayName, systemImage: schedule.action.icon)
                        .font(.system(size: 11))
                        .foregroundColor(actionColour.opacity(isEnabled ? 1 : 0.4))
                    // Source badge is only shown for non-manually-created schedules (e.g. AI-accepted)
                    if schedule.source != "manual" {
                        Label(schedule.sourceLabel, systemImage: schedule.sourceIcon)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
            }

            Spacer()

            // Enable/disable toggle and ellipsis context menu with Edit and Delete actions
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

/// The content of the "AI Suggestions" tab
    
/// Shows a loading spinner with a descriptive message while "isLoading" is true, an empty state encouraging continued usage when there are no suggestions, or a scrollable list of "SuggestionCard" rows when suggestions are present

/// If more than one suggestion exists an "Accept All" button is shown above the list so the user can convert all pending suggestions into active schedules in a single tap

/// A "SleepHintBanner" is shown at the top of the populated state whenever sleep data is available
struct SuggestionsTab: View {
    /// The current list of AI-generated schedule suggestions to display
    let suggestions: [ScheduleSuggestion]

    /// When true a loading spinner and analysis message are shown instead of the suggestion list
    let isLoading: Bool

    /// The user's detected sleep bedtime from Apple Health, used to populate the sleep hint banner
    let sleepBedtime: Date?

    /// The user's detected wake time from Apple Health, used to populate the sleep hint banner
    let sleepWakeTime: Date?

    /// Called when the user accepts a suggestion; receives the suggestion ID
    let onAccept: (Int) -> Void

    /// Called when the user dismisses a suggestion; receives the suggestion ID
    let onDismiss: (Int) -> Void

    /// Called when the user taps "Accept All" to auto-accept every pending suggestion at once
    let onAutoAcceptAll: () -> Void

    /// Called when the user taps "Analyse Now" in the empty state to trigger a fresh usage analysis
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
            // Empty state with a waveform icon, explanatory text, and an "Analyse Now" trigger button
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
                // Sleep hint banner shown above the list when sleep data is available
                if let bedtime = sleepBedtime, let wake = sleepWakeTime {
                    SleepHintBanner(bedtime: bedtime, wakeTime: wake)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                // "Accept All" button shown only when two or more suggestions are pending
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

/// A card view representing a single AI-generated schedule suggestion

/// Displays the suggestion's source type (sleep-linked or AI-detected), its readable schedule type, a confidence percentage badge colour-coded from green (high) through amber to yellow (low), detail pills for time/window, action, and observation count, and an optional brightness preview bar

/// "Accept" converts the suggestion into an active schedule via the parent's "onAccept" closure; "Dismiss" removes it permanently via "onDismiss"
struct SuggestionCard: View {
    /// The suggestion model to display
    let suggestion: ScheduleSuggestion

    /// Called when the user taps "Add Schedule" to accept this suggestion
    let onAccept: () -> Void

    /// Called when the user taps "Dismiss" to remove this suggestion
    let onDismiss: () -> Void

    /// The colour of the confidence badge and "Accept" button, derived from the confidence score
    
    /// - Green:  confidence ≥ 0.68 (high)
    /// - Amber:  confidence ≥ 0.52 (medium)
    /// - Yellow: confidence < 0.52 (low)
    var confidenceColour: Color {
        suggestion.confidence >= 0.68 ? Color(red: 0.2, green: 0.85, blue: 0.5) :
        suggestion.confidence >= 0.52 ? Color(red: 1.0, green: 0.65, blue: 0.2) :
        Color(red: 1.0, green: 0.85, blue: 0.2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top row: source badge (sleep-linked or AI-detected), readable type name, and confidence badge
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

                // Confidence badge: percentage in monospaced digits with a "confidence" label beneath
                VStack(spacing: 2) {
                    Text("\(suggestion.confidencePercent)%")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(confidenceColour)
                    Text("confidence")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            // Detail pills: time/window, action, and observation count (observation count omitted for sleep-based suggestions)
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

            // Brightness preview bar, only shown for actions that have a meaningful brightness value
            // The gradient direction reflects colour temperature: warm gradients flow right-to-left, cool left-to-right
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

            // Accept and Dismiss action buttons
            // "Accept" adopts the confidence colour; "Dismiss" uses a neutral translucent style
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

/// A compact three-line pill used inside "SuggestionCard" to display an icon, a primary value, and a label

/// Used for time/window, action, and observation count detail items
struct DetailPill: View {
    /// The SF Symbol name to display above the value
    let icon: String

    /// The primary value text (e.g. "21:00", "Dim Warm", "12×")
    let text: String

    /// The secondary label beneath the value (e.g. "Time", "Action", "Observed")
    let label: String

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

/// A tappable banner shown when HealthKit is available but not yet authorised
///
/// Tapping opens the "HealthPermissionSheet" via the "onTap" closure so the user can grant sleep access
struct HealthPermissionBanner: View {
    /// Called when the banner is tapped; should present the HealthKit permission sheet
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

/// A tappable banner shown when HealthKit is authorised and sleep data has been successfully loaded

/// Displays the detected bedtime and wake time; tapping opens the "HealthRevokeSheet" via "onManage" so the user can review or revoke access
struct SleepSummaryBanner: View {
    /// The detected sleep bedtime from Apple Health
    let bedtime: Date

    /// The detected wake time from Apple Health
    let wakeTime: Date

    /// Called when the banner is tapped; should present the HealthKit revoke/manage sheet
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

/// A tappable banner shown when HealthKit is authorised but sleep data is not yet available

/// Informs the user that access has been granted and sleep data will appear once Apple Health has recorded it; tapping opens the "HealthRevokeSheet" via "onManage"
struct SleepLinkedBanner: View {
    /// Called when the banner is tapped; should present the HealthKit revoke/manage sheet
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

/// A compact non-interactive inline banner shown at the top of the Suggestions tab when sleep data is available, reminding the user which bedtime and wake time are active
struct SleepHintBanner: View {
    /// The detected sleep bedtime from Apple Health
    let bedtime: Date

    /// The detected wake time from Apple Health
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

/// A full-screen modal that requests HealthKit sleep access

/// Describes the three benefits of connecting Apple Health (wind-down dim, gentle wake-up, read-only access), then calls "ScheduleManager.requestHealthKitPermission" when the user taps "Allow Health Access"
/// On success the sheet dismisses automatically after 1.5 seconds; on failure an inline message instructs the user to enable access manually via Settings → Health
struct HealthPermissionSheet: View {
    /// Used to dismiss this sheet once permission has been granted or the user taps "Not Now"
    @Environment(\.dismiss) var dismiss

    /// True while the HealthKit permission request is in flight
    @State private var requesting = false

    /// An inline status message shown after the permission request completes, indicating success or failure
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

                // Feature list explaining what HealthKit access enables
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

                // Inline status message shown after the permission request resolves
                if !result.isEmpty {
                    Text(result)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                // Primary CTA: shows a spinner while the request is in flight
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

    /// Initiates the HealthKit permission request via "ScheduleManager"
    
    /// Sets "requesting" to true while the system prompt is displayed, then updates "result" with a success or failure message; on success the sheet is dismissed after a 1.5-second delay
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

/// A full-screen modal shown when the user taps the sleep banner while HealthKit is already authorised

/// Confirms that sleep data is actively linked, explains that the app has read-only access, and provides step-by-step instructions for revoking access via the Health app

/// iOS does not expose a programmatic HealthKit revoke API, so the sheet uses a deep link to open the Health app directly and guides the user through the manual revoke flow
struct HealthRevokeSheet: View {
    /// Used to dismiss this sheet when the user taps "Done"
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

                // Status rows confirming the current state of the HealthKit connection
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

                // Revoke instructions, iOS does not expose a programmatic revoke API, so the user is directed to Settings > Health as Apple requires
                VStack(spacing: 16) {
                    Text("To revoke access:")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))

                    // Numbered step list guiding the user through the Health app revoke flow
                    VStack(alignment: .leading, spacing: 10) {
                        RevokeStep(number: "1", text: "Open the Health app")
                        RevokeStep(number: "2", text: "Tap your profile photo → Apps")
                        RevokeStep(number: "3", text: "Find this app and tap Turn Off All")
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(14)
                    .padding(.horizontal, 20)

                    // Deep link button that opens the Health app directly
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

    /// Opens the Apple Health app using the "x-apple-health://" deep link URL scheme
    func openHealthSettings() {
        if let url = URL(string: "x-apple-health://") {
            UIApplication.shared.open(url)
        }
    }
}

/// A numbered step row used inside "HealthRevokeSheet" to present a single revoke instruction

/// Renders a filled circle containing the step number alongside the instruction text
struct RevokeStep: View {
    /// The step number displayed inside the circle (e.g. "1", "2", "3")
    let number: String

    /// The instruction text displayed to the right of the number circle
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

/// A labelled icon row used in "HealthPermissionSheet" and "HealthRevokeSheet" to summarise a single HealthKit feature or status item
struct HealthFeatureRow: View {
    /// The SF Symbol name to display on the left
    let icon: String

    /// The tint colour applied to the icon
    let colour: Color

    /// The bold title text
    let title: String

    /// The secondary description text beneath the title
    let desc: String

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

/// A modal sheet for creating a new schedule for the given bulb

/// Collects a schedule name, trigger time, action type, brightness, colour temperature, and repeat days from the user via form controls, then submits a "NewScheduleRequest" to "ScheduleManager.addSchedule"

/// Brightness and colour temperature controls are hidden when the selected action is "Power On" or "Power Off" since those actions do not use those parameters

/// A "SleepHintBanner" is shown at the top of the form when sleep data is available from Apple Health, nudging the user to align the new schedule with their detected sleep/wake times
struct AddScheduleSheet: View {
    /// The identifier of the bulb this schedule will be attached to
    let bulbId: String

    /// The display name of the bulb, shown in the hint banner context
    let bulbName: String

    /// The shared schedule manager, observed to access sleep data for the hint banner and to call "addSchedule"
    @StateObject private var manager = ScheduleManager.shared

    /// Used to dismiss this sheet after a successful save
    @Environment(\.dismiss) var dismiss

    /// The schedule name entered by the user; the "Save" button is disabled until this is non-empty
    @State private var name = ""

    /// The action the schedule will perform at its trigger time
    @State private var selectedAction: ScheduleAction = .powerOn

    /// The time of day at which the schedule execute; hour and minute components are extracted on save
    @State private var triggerTime = Date()

    /// The brightness value (0–255) to apply when the schedule execute
    @State private var brightness: Double = 200

    /// The colour temperature value (0–255) to apply when the schedule execute; 0 = cool, 255 = warm
    @State private var colourTemp: Double = 128

    /// A seven-element array of booleans representing Monday through Sunday repeat selection
    @State private var daysSelected = [true, true, true, true, true, true, true]

    /// True while the save request is in flight to prevent duplicate submissions
    @State private var saving = false

    /// An inline error message shown when the save request fails
    @State private var error = ""

    /// Single-character day labels for the repeat day selector, Monday through Sunday
    private let dayLabels = ["M","T","W","T","F","S","S"]

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.14).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header with Cancel, title, and Save buttons
                    // Save is disabled when the name field is empty or a save is already in flight
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

                    // Sleep hint banner shown when Apple Health has provided bedtime and wake time
                    if let bedtime = manager.sleepBedtime, let wake = manager.sleepWakeTime {
                        SleepHintBanner(bedtime: bedtime, wakeTime: wake)
                    }

                    // Schedule name text field
                    SheetSection(title: "Schedule Name") {
                        TextField("e.g. Evening Dim", text: $name)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.07))
                            .cornerRadius(12)
                    }

                    // Wheel-style time picker for selecting the trigger hour and minute
                    SheetSection(title: "Trigger Time") {
                        DatePicker("", selection: $triggerTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .colorScheme(.dark)
                            .frame(maxWidth: .infinity)
                    }

                    // Two-column action grid; selected action is highlighted in green
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

                    // Brightness and colour temperature sliders — hidden for Power On and Power Off since those actions do not use light-level parameters
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

                    // Day-of-week repeat selector — circular toggle buttons, Mon through Sun
                    // If no days are selected the backend defaults to every day (1–7)
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

    /// Builds a "NewScheduleRequest" from the current form state and submits it to "ScheduleManager"

    /// Hour and minute are extracted from "triggerTime" via "Calendar.current"; the selected days array is converted to a comma-separated string of 1-based integers (1 = Monday)
    /// If no days are selected, the string defaults to "1,2,3,4,5,6,7" (every day)
    /// On success the sheet is dismissed; on failure "error" is set to an inline message
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

/// A modal sheet for modifying an existing schedule, pre-populated with the current schedule values

/// Mirrors the form layout of "AddScheduleSheet" but submits a PATCH request to "/update_schedule" via "NetworkManager" with the schedule's ID and the updated field values

/// All state properties are initialised from the existing "BulbSchedule" model in the custom "init", including parsing the comma-separated "daysOfWeek" string back into the Boolean array used by the picker
struct EditScheduleSheet: View {
    /// The existing schedule being edited
    let schedule: BulbSchedule

    /// The identifier of the bulb this schedule belongs to, used to reload the schedule list after saving
    let bulbId: String

    /// The shared schedule manager, observed for sleep data and used to reload schedules after a successful save
    @StateObject private var manager = ScheduleManager.shared

    /// Used to dismiss this sheet after saving or cancelling
    @Environment(\.dismiss) var dismiss

    /// The edited schedule name, pre-populated from "schedule.scheduleName"
    @State private var name: String

    /// The edited action type, pre-populated from "schedule.action"
    @State private var selectedAction: ScheduleAction

    /// The edited trigger time as a "Date", reconstructed from "schedule.triggerHour" and "schedule.triggerMinute"
    @State private var triggerTime: Date

    /// The edited brightness value (0–255), pre-populated from "schedule.brightness"
    @State private var brightness: Double

    /// The edited colour temperature value (0–255), pre-populated from "schedule.colourTemp"
    @State private var colourTemp: Double

    /// The edited repeat days as a Boolean array [Mon…Sun], parsed from "schedule.daysOfWeek"
    @State private var daysSelected: [Bool]

    /// True while the save request is in flight to prevent duplicate submissions
    @State private var saving = false

    /// An inline error message shown when the save request fails
    @State private var error = ""

    /// Single-character day labels for the repeat day selector, Monday through Sunday
    private let dayLabels = ["M","T","W","T","F","S","S"]

    /// Initialises all editable state from the provided "BulbSchedule" model

    /// - Parameters:
    ///   - schedule: The existing schedule whose values pre-populate the form
    ///   - bulbId: The identifier of the bulb this schedule belongs to
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

        // Parse the comma-separated days string into a [Mon…Sun] Boolean array (days are 1-based, 1 = Monday)
        let activeDays = schedule.daysOfWeek.split(separator: ",").compactMap { Int($0) }
        _daysSelected = State(initialValue: (1...7).map { activeDays.contains($0) })
    }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.14).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header with Cancel, title, and Save buttons
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

                    // Sleep hint banner shown when Apple Health has provided bedtime and wake time
                    if let bedtime = manager.sleepBedtime, let wake = manager.sleepWakeTime {
                        SleepHintBanner(bedtime: bedtime, wakeTime: wake)
                    }

                    // Schedule name text field
                    SheetSection(title: "Schedule Name") {
                        TextField("Schedule name", text: $name)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.07))
                            .cornerRadius(12)
                    }

                    // Wheel-style time picker for editing the trigger hour and minute
                    SheetSection(title: "Trigger Time") {
                        DatePicker("", selection: $triggerTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .colorScheme(.dark)
                            .frame(maxWidth: .infinity)
                    }

                    // Two-column action grid; selected action is highlighted in green
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

                    // Brightness and colour temperature sliders, hidden for Power On and Power Off
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

                    // Day-of-week repeat selector, circular toggle buttons, Mon through Sun
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

    /// Extracts the edited form values and submits a PATCH request to "/update_schedule" via "NetworkManager"
    
    /// Hour and minute are extracted from "triggerTime"; the selected days Boolean array is converted to a comma-separated string of 1-based integers; if no days are selected the string defaults to "1,2,3,4,5,6,7"
    /// On success "ScheduleManager" reloads the schedule list for the bulb and the sheet is dismissed; on failure "error" is set to an inline message
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

// MARK: - Sheet Section Helper

/// A reusable form section wrapper that renders a small all-caps tracking label above arbitrary content

/// Used throughout "AddScheduleSheet" and "EditScheduleSheet" to give each form field group a consistent labelled section heading without repeating the label styling
struct SheetSection<Content: View>: View {
    /// The section label text, rendered in uppercase with letter-spacing
    let title: String

    /// The content to render beneath the section label
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

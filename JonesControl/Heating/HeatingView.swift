import SwiftUI

struct HeatingView: View {
    private static let manualPresetTargets = [5.0, 12.0, 21.0]
    private static let manualTargetSendDebounceNanoseconds: UInt64 = 500_000_000

    @Environment(\.scenePhase) private var scenePhase
    @Environment(HeatingServiceSettings.self) private var heatingServiceSettings
    @State private var model = HeatingFeatureModel()
    @State private var selectedRuntimeMode = HeatingRuntimeControlMode.schedule
    @State private var manualTargetCelsius = HeatingFeatureModel.defaultManualTargetCelsius
    @State private var isSyncingRuntimeModeControls = false
    @State private var suppressNextRuntimeModeSelectionChange = false
    @State private var pendingManualTargetSendTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            content
        }
        .navigationTitle("Heating")
        .task(id: reloadTrigger) {
            guard scenePhase == .active else {
                return
            }

            await model.load()
        }
        .onAppear(perform: syncRuntimeModeControls)
        .onChange(of: model.runtimeModeDocument, initial: false) { _, _ in
            syncRuntimeModeControls()
        }
        .onChange(of: selectedRuntimeMode, initial: false) { oldValue, newValue in
            guard oldValue != newValue else {
                return
            }

            if suppressNextRuntimeModeSelectionChange {
                suppressNextRuntimeModeSelectionChange = false
                return
            }

            guard !isSyncingRuntimeModeControls else {
                return
            }

            Task { @MainActor in
                await applyRuntimeModeSelection(newValue)
            }
        }
        .onChange(of: manualTargetCelsius, initial: false) { oldValue, newValue in
            guard oldValue != newValue else {
                return
            }

            scheduleDebouncedManualTargetSendIfNeeded()
        }
        .onDisappear {
            pendingManualTargetSendTask?.cancel()
            pendingManualTargetSendTask = nil
        }
        .alert("Heating", isPresented: alertMessageIsPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var reloadTrigger: String {
        "\(scenePhase == .active)|\(heatingServiceSettings.trimmedBaseURLText)"
    }

    @ViewBuilder
    private var content: some View {
        switch model.serviceState {
        case .loading:
            ProgressView("Loading heating schedule...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
        case .notConfigured:
            statusView(
                title: model.statusTitle,
                message: model.statusMessage,
                systemImage: "gearshape",
                showsRetry: true
            ) {
                Task { @MainActor in
                    await model.load()
                }
            }
            case .unavailable:
                statusView(
                    title: model.statusTitle,
                    message: model.statusMessage,
                    systemImage: "icloud.slash",
                    showsRetry: true
                ) {
                Task { @MainActor in
                    await model.load()
                }
            }
            case .unsupportedShape:
                statusView(
                    title: model.statusTitle,
                    message: model.statusMessage,
                    systemImage: "exclamationmark.triangle",
                    showsRetry: true
                ) {
                Task { @MainActor in
                    await model.load()
                }
            }
        case .ready:
            scheduleView
        }
    }

    private var scheduleView: some View {
        List {
            Section("Runtime Mode") {
                LabeledContent("Current") {
                    Text(model.runtimeModeText)
                }

                Picker("Mode", selection: $selectedRuntimeMode) {
                    ForEach(HeatingRuntimeControlMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!model.canControlRuntimeMode || model.isChangingRuntimeMode)

                if selectedRuntimeMode == .manual {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Target") {
                            Text(temperatureLabel(for: manualTargetCelsius))
                                .monospacedDigit()
                        }

                        Stepper(
                            value: $manualTargetCelsius,
                            in: 5...30,
                            step: 0.5
                        ) {
                            Text("Adjust manual target")
                        }
                        .disabled(!model.canControlRuntimeMode || model.isChangingRuntimeMode)

                        HStack(spacing: 8) {
                            ForEach(Self.manualPresetTargets, id: \.self) { target in
                                Button(temperatureLabel(for: target)) {
                                    sendManualPreset(target)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!model.canControlRuntimeMode || model.isChangingRuntimeMode)
                            }
                        }
                    }
                }

                if model.isChangingRuntimeMode {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Sending settings to xtura...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.runtimeModeDocument?.mode == .boost {
                    Text("Boost is currently active. Moving the switch will replace the boost mode.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Schedule") {
                if let schedule = model.schedule {
                    ForEach(Array(schedule.activeSlots.enumerated()), id: \.offset) { index, slot in
                        NavigationLink {
                            HeatingSlotEditorView(
                                slotIndex: index,
                                slot: slot,
                                schedule: schedule
                            ) { updatedSchedule in
                                try await model.save(schedule: updatedSchedule)
                            }
                        } label: {
                            HeatingScheduleRow(slot: slot)
                        }
                        .disabled(!model.canEditSchedule)
                    }
                } else {
                    Text("No heating schedule is loaded.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay(alignment: .top) {
            if model.serviceState == .loading {
                ProgressView()
                    .padding(.top, 12)
            }
        }
    }

    private func statusView(
        title: String,
        message: String,
        systemImage: String,
        showsRetry: Bool = false,
        retryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2.weight(.semibold))

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if showsRetry, let retryAction {
                Button("Retry", action: retryAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var alertMessageIsPresented: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.alertMessage = nil
                }
            }
        )
    }

    private func setRuntimeModeSchedule() async {
        do {
            try await model.setRuntimeModeSchedule()
        } catch let error as HeatingFeatureModelError {
            model.alertMessage = HeatingFeatureModel.message(for: error)
            syncRuntimeModeControls()
        } catch {
            model.alertMessage = error.localizedDescription
            syncRuntimeModeControls()
        }
    }

    private func setRuntimeModeManual(targetCelsius: Double) async {
        do {
            try await model.setRuntimeModeManual(targetCelsius: targetCelsius)
        } catch let error as HeatingFeatureModelError {
            model.alertMessage = HeatingFeatureModel.message(for: error)
            syncRuntimeModeControls()
        } catch {
            model.alertMessage = error.localizedDescription
            syncRuntimeModeControls()
        }
    }

    private func setRuntimeModeOff() async {
        do {
            try await model.setRuntimeModeOff()
        } catch let error as HeatingFeatureModelError {
            model.alertMessage = HeatingFeatureModel.message(for: error)
            syncRuntimeModeControls()
        } catch {
            model.alertMessage = error.localizedDescription
            syncRuntimeModeControls()
        }
    }

    private func syncRuntimeModeControls() {
        isSyncingRuntimeModeControls = true
        pendingManualTargetSendTask?.cancel()
        pendingManualTargetSendTask = nil
        let syncedSelection = model.runtimeModeControlSelection
        if selectedRuntimeMode != syncedSelection {
            suppressNextRuntimeModeSelectionChange = true
            selectedRuntimeMode = syncedSelection
        }
        manualTargetCelsius = model.effectiveManualTargetCelsius
        isSyncingRuntimeModeControls = false
    }

    private func applyRuntimeModeSelection(_ selection: HeatingRuntimeControlMode) async {
        switch selection {
        case .schedule:
            await setRuntimeModeSchedule()
        case .manual:
            await setRuntimeModeManual(targetCelsius: manualTargetCelsius)
        case .off:
            await setRuntimeModeOff()
        }
    }

    private func scheduleDebouncedManualTargetSendIfNeeded() {
        guard selectedRuntimeMode == .manual,
              model.runtimeModeControlSelection == .manual,
              model.canControlRuntimeMode,
              !model.isChangingRuntimeMode,
              manualTargetNeedsSending else {
            return
        }

        pendingManualTargetSendTask?.cancel()
        let target = manualTargetCelsius
        pendingManualTargetSendTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.manualTargetSendDebounceNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            await setRuntimeModeManual(targetCelsius: target)
            pendingManualTargetSendTask = nil
        }
    }

    private func sendManualPreset(_ targetCelsius: Double) {
        pendingManualTargetSendTask?.cancel()
        pendingManualTargetSendTask = nil
        manualTargetCelsius = targetCelsius

        Task { @MainActor in
            await setRuntimeModeManual(targetCelsius: targetCelsius)
        }
    }

    private var manualTargetNeedsSending: Bool {
        guard model.runtimeModeDocument?.mode == .manual else {
            return false
        }

        return abs(model.effectiveManualTargetCelsius - manualTargetCelsius) >= 0.05
    }

    private func temperatureLabel(for temperature: Double) -> String {
        HeatingFeatureModel.formatTemperature(temperature) + "°C"
    }
}

private struct HeatingScheduleRow: View {
    let slot: HeatingScheduleSlot

    var body: some View {
        let display = HeatingScheduleRowDisplay(slot: slot)
        row(title: display.timeRangeText, mode: display.modeText, targetTemperatureText: display.targetTemperatureText)
    }

    private func row(title: String, mode: String, targetTemperatureText: String?) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(mode)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)

            if let targetTemperatureText {
                Text(targetTemperatureText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
            } else {
                Text(" ")
                    .font(.callout.monospacedDigit())
                    .frame(width: 52, alignment: .leading)
            }
        }
    }
}

struct HeatingScheduleRowDisplay: Equatable, Sendable {
    var timeRangeText: String
    var modeText: String
    var targetTemperatureText: String?

    init(timeRangeText: String, modeText: String, targetTemperatureText: String?) {
        self.timeRangeText = timeRangeText
        self.modeText = modeText
        self.targetTemperatureText = targetTemperatureText
    }

    init(slot: HeatingScheduleSlot) {
        self.timeRangeText = "\(Self.displayTimeString(for: slot.startMinuteOfDay)) - \(Self.displayTimeString(for: slot.endMinuteOfDay))"
        self.modeText = slot.mode == .heat ? "On" : "Off"
        self.targetTemperatureText = Self.displayTargetTemperatureText(for: slot)
    }

    private static func displayTimeString(for minuteOfDay: Int) -> String {
        guard minuteOfDay >= 0, minuteOfDay <= HeatingSchedule.minutesInDay else {
            return "--:--"
        }

        if minuteOfDay == HeatingSchedule.minutesInDay {
            return "24:00"
        }

        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    private static func displayTargetTemperatureText(for slot: HeatingScheduleSlot) -> String? {
        guard slot.mode == .heat, let temperature = slot.targetTemperatureCelsius else {
            return nil
        }

        return formatTemperature(temperature) + "°C"
    }

    private static func formatTemperature(_ temperature: Double) -> String {
        if temperature.rounded(.towardZero) == temperature {
            return String(format: "%.0f", temperature)
        }

        return String(format: "%.1f", temperature)
    }
}

#Preview("Heating") {
    HeatingView()
}

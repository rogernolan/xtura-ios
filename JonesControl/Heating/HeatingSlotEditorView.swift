import Foundation
import SwiftUI

struct HeatingSlotEditorView: View {
    @Binding private var schedule: HeatingSchedule
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HeatingSlotEditorDraft
    @State private var alertMessage: String?

    private let slotIndex: Int

    init(
        slotIndex: Int,
        slot: HeatingScheduleSlot,
        schedule: Binding<HeatingSchedule>
    ) {
        self.slotIndex = slotIndex
        self._schedule = schedule
        self._draft = State(initialValue: HeatingSlotEditorDraft(slot: slot))
    }

    var body: some View {
        Form {
            Section("Slot") {
                Picker("Type", selection: $draft.slotKind) {
                    Text("Off").tag(HeatingSlotEditorDraft.SlotKind.off)
                    Text("Heat").tag(HeatingSlotEditorDraft.SlotKind.heat)
                }
                .pickerStyle(.segmented)
            }

            Section("Time") {
                Picker("Start time", selection: $draft.startMinuteOfDay) {
                    ForEach(startMinuteOptions, id: \.self) { minute in
                        Text(Self.timeLabel(for: minute)).tag(minute)
                    }
                }

                Picker("End time", selection: $draft.endMinuteOfDay) {
                    ForEach(endMinuteOptions, id: \.self) { minute in
                        Text(Self.timeLabel(for: minute)).tag(minute)
                    }
                }
            }

            if draft.slotKind == .heat {
                let targetTemperatureText = Self.temperatureLabel(
                    for: draft.currentHeatTargetTemperatureCelsius ?? Self.defaultTargetTemperatureCelsius
                )

                Section("Target Temperature") {
                    Stepper(
                        value: targetTemperatureBinding,
                        in: Self.temperatureRange,
                        step: Self.temperatureStep
                    ) {
                        Text("Target \(targetTemperatureText)")
                    }
                }
            }
        }
        .navigationTitle("Slot \(slotIndex + 1)")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .alert("Unable to Save", isPresented: alertMessageIsPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
        .onChange(of: draft.startMinuteOfDay) { _, newValue in
            draft.endMinuteOfDay = max(draft.endMinuteOfDay, newValue + Self.minimumDuration)
            clampDraftTimes()
        }
        .onChange(of: draft.slotKind) { _, newValue in
            if newValue == .heat, draft.currentHeatTargetTemperatureCelsius == nil {
                draft.currentHeatTargetTemperatureCelsius = Self.defaultTargetTemperatureCelsius
            }
        }
    }

    private var alertMessageIsPresented: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    alertMessage = nil
                }
            }
        )
    }

    private var endMinuteOptions: [Int] {
        guard let bounds = schedule.editingBounds(forSlotAt: slotIndex) else {
            return [draft.endMinuteOfDay]
        }

        let earliestEnd = max(bounds.earliestEndMinuteOfDay, draft.startMinuteOfDay + Self.minimumDuration)
        return Array(stride(from: earliestEnd, through: bounds.latestEndMinuteOfDay, by: Self.minimumDuration))
    }

    private var startMinuteOptions: [Int] {
        guard let bounds = schedule.editingBounds(forSlotAt: slotIndex) else {
            return [draft.startMinuteOfDay]
        }

        let latestStart = min(bounds.latestStartMinuteOfDay, draft.endMinuteOfDay - Self.minimumDuration)
        return Array(stride(from: bounds.earliestStartMinuteOfDay, through: latestStart, by: Self.minimumDuration))
    }

    private var targetTemperatureBinding: Binding<Double> {
        Binding(
            get: { draft.currentHeatTargetTemperatureCelsius ?? Self.defaultTargetTemperatureCelsius },
            set: { draft.currentHeatTargetTemperatureCelsius = $0 }
        )
    }

    private func save() {
        switch draft.slotKind {
        case .off:
            switch schedule.updatingLinkedSlot(
                at: slotIndex,
                startMinuteOfDay: draft.startMinuteOfDay,
                endMinuteOfDay: draft.endMinuteOfDay,
                mode: .off,
                targetTemperatureCelsius: nil
            ) {
            case .success(let updatedSchedule):
                schedule = updatedSchedule
                dismiss()
            case .failure(let error):
                alertMessage = Self.message(for: error)
            }
        case .heat:
            switch schedule.updatingLinkedSlot(
                at: slotIndex,
                startMinuteOfDay: draft.startMinuteOfDay,
                endMinuteOfDay: draft.endMinuteOfDay,
                mode: .heat,
                targetTemperatureCelsius: draft.currentHeatTargetTemperatureCelsius ?? Self.defaultTargetTemperatureCelsius
            ) {
            case .success(let updatedSchedule):
                schedule = updatedSchedule
                dismiss()
            case .failure(let error):
                alertMessage = Self.message(for: error)
            }
        }
    }

    private func clampDraftTimes() {
        guard let bounds = schedule.editingBounds(forSlotAt: slotIndex) else {
            return
        }

        let maximumStart = min(bounds.latestStartMinuteOfDay, draft.endMinuteOfDay - Self.minimumDuration)
        draft.startMinuteOfDay = min(max(draft.startMinuteOfDay, bounds.earliestStartMinuteOfDay), maximumStart)

        let minimumEnd = max(bounds.earliestEndMinuteOfDay, draft.startMinuteOfDay + Self.minimumDuration)
        draft.endMinuteOfDay = min(max(draft.endMinuteOfDay, minimumEnd), bounds.latestEndMinuteOfDay)
    }

    private static func message(for error: HeatingScheduleUpdateError) -> String {
        switch error {
        case .slotIndexOutOfRange:
            return "That slot no longer exists."
        case .slotCountInvalid:
            return "The schedule is missing slots."
        case .validationErrors(let errors):
            return errors.map { Self.message(for: $0) }.joined(separator: "\n")
        }
    }

    private static func message(for error: HeatingScheduleValidationError) -> String {
        switch error {
        case .startMinuteOutOfRange:
            return "Start time is out of range."
        case .endMinuteOutOfRange:
            return "End time is out of range."
        case .invalidTimeRange:
            return "End time must be later than start time."
        case .missingTargetTemperature:
            return "Heat on slots need a target temperature."
        case .overlappingSlots:
            return "This edit overlaps another slot."
        }
    }

    private static func timeLabel(for minuteOfDay: Int) -> String {
        if minuteOfDay == HeatingSchedule.minutesInDay {
            return "24:00"
        }

        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        return String(format: "%02d:%02d", hour, minute)
    }
}

private struct HeatingSlotEditorDraft: Equatable {
    var startMinuteOfDay: Int
    var endMinuteOfDay: Int
    var slotKind: SlotKind
    var currentHeatTargetTemperatureCelsius: Double?

    init(slot: HeatingScheduleSlot) {
        startMinuteOfDay = slot.startMinuteOfDay
        endMinuteOfDay = slot.endMinuteOfDay
        slotKind = slot.mode == .heat ? .heat : .off
        currentHeatTargetTemperatureCelsius = slot.targetTemperatureCelsius
    }

    static let minimumDuration = 15
    static let defaultTargetTemperatureCelsius = 20.0

    enum SlotKind: Equatable {
        case off
        case heat
    }
}

private extension HeatingSlotEditorView {
    static let minimumDuration = 15
    static let defaultTargetTemperatureCelsius = 20.0
    static let temperatureRange = 5.0...30.0
    static let temperatureStep = 0.5

    static func temperatureLabel(for temperature: Double) -> String {
        if temperature.rounded(.towardZero) == temperature {
            return String(format: "%.0f°C", temperature)
        }

        return String(format: "%.1f°C", temperature)
    }
}

import SwiftUI

struct HeatingView: View {
    @State private var schedule: HeatingSchedule

    init(schedule: HeatingSchedule = Self.makeSeededLocalSchedule()) {
        self._schedule = State(initialValue: schedule)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Schedule") {
                    ForEach(Array(schedule.activeSlots.enumerated()), id: \.offset) { index, slot in
                        NavigationLink {
                            HeatingSlotEditorView(slotIndex: index, slot: slot, schedule: $schedule)
                        } label: {
                            HeatingScheduleRow(slot: slot)
                        }
                    }
                }
            }
            .navigationTitle("Heating")
        }
    }
}

extension HeatingView {
    static func makeSeededLocalSchedule() -> HeatingSchedule {
        HeatingSchedule(visibleSlots: SeededLocalVisibleSlots.slots)!
    }
}

private enum SeededLocalVisibleSlots {
    static let slots: [HeatingScheduleVisibleSlot] = [
        .active(HeatingScheduleSlot(
            startMinuteOfDay: 0,
            endMinuteOfDay: 6 * 60 + 30,
            mode: .off
        )),
        .active(HeatingScheduleSlot(
            startMinuteOfDay: 6 * 60 + 30,
            endMinuteOfDay: 8 * 60,
            mode: .heat,
            targetTemperatureCelsius: 21
        )),
        .active(HeatingScheduleSlot(
            startMinuteOfDay: 8 * 60,
            endMinuteOfDay: 17 * 60,
            mode: .off
        )),
        .active(HeatingScheduleSlot(
            startMinuteOfDay: 17 * 60,
            endMinuteOfDay: HeatingSchedule.minutesInDay,
            mode: .heat,
            targetTemperatureCelsius: 19
        ))
    ]
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

import SwiftUI

struct EventLogView: View {
    let events: [EventLog]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(events) { event in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(color(for: event.level))
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)

                    Text(event.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)

                    Text(event.message)
                        .font(.caption)
                }
            }
        }
    }

    private func color(for level: EventLog.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

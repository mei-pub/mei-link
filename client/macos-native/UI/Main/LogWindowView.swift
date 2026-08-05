import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LogWindowView: View {
    @ObservedObject var manager: TunnelManager
    @State private var selectedEventIDs: Set<EventLog.ID> = []
    @State private var statusMessage: String?

    private var selectedEvents: [EventLog] {
        manager.events.filter { selectedEventIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text("运行日志")
                    .font(.title3.weight(.semibold))
                Text("\(manager.events.count) 条事件 · 最近的连接检测、自动重连和隧道变更")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                copy(text: formattedLogs(manager.events), message: "已复制全部日志")
            } label: {
                Label("复制全部", systemImage: "doc.on.doc")
            }
            .disabled(manager.events.isEmpty)

            Button {
                exportLogs()
            } label: {
                Label("导出", systemImage: "square.and.arrow.down")
            }
            .disabled(manager.events.isEmpty)
        }
        .padding(18)
    }

    @ViewBuilder
    private var content: some View {
        if manager.events.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 34))
                    .foregroundColor(.secondary)
                Text("暂无日志")
                    .font(.headline)
                Text("连接检测、自动重连和配置变更会显示在这里。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(manager.events, selection: $selectedEventIDs) {
                TableColumn("时间") { event in
                    Text(formatTimestamp(event.timestamp))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .width(148)

                TableColumn("级别") { event in
                    Label(levelTitle(event.level), systemImage: levelImage(event.level))
                        .foregroundColor(levelColor(event.level))
                        .labelStyle(.titleAndIcon)
                }
                .width(92)

                TableColumn("内容") { event in
                    Text(event.message)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            .contextMenu {
                Button("复制选中日志") {
                    copySelected()
                }
                .disabled(selectedEventIDs.isEmpty)

                Button("复制全部日志") {
                    copy(text: formattedLogs(manager.events), message: "已复制全部日志")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                copySelected()
            } label: {
                Label("复制选中", systemImage: "doc.on.clipboard")
            }
            .disabled(selectedEventIDs.isEmpty)

            Button(role: .destructive) {
                manager.clearEvents()
                selectedEventIDs = []
                statusMessage = "日志已清空"
            } label: {
                Label("清空日志", systemImage: "trash")
            }
            .disabled(manager.events.isEmpty)
        }
        .padding(14)
    }

    private func copySelected() {
        guard !selectedEventIDs.isEmpty else { return }
        copy(text: formattedLogs(selectedEvents), message: "已复制选中日志")
    }

    private func copy(text: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = message
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.title = "导出 Meilink 日志"
        panel.nameFieldStringValue = "meilink-logs-\(filenameTimestamp()).log"
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try formattedLogs(manager.events).write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "日志已导出"
        } catch {
            statusMessage = "导出失败: \(error.localizedDescription)"
        }
    }

    private func formattedLogs(_ events: [EventLog]) -> String {
        events
            .sorted { $0.timestamp < $1.timestamp }
            .map { "[\(formatTimestamp($0.timestamp))] [\(levelTitle($0.level))] \($0.message)" }
            .joined(separator: "\n")
    }

    private func formatTimestamp(_ date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }

    private func filenameTimestamp() -> String {
        Self.filenameFormatter.string(from: Date())
    }

    private func levelTitle(_ level: EventLog.LogLevel) -> String {
        switch level {
        case .info: return "信息"
        case .warning: return "警告"
        case .error: return "错误"
        }
    }

    private func levelImage(_ level: EventLog.LogLevel) -> String {
        switch level {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    private func levelColor(_ level: EventLog.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

import AppKit

enum AppIconProvider {
    static var image: NSImage {
        if let path = ProcessInfo.processInfo.environment["MEILINK_APP_ICON"],
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        return NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 64, height: 64))
    }
}

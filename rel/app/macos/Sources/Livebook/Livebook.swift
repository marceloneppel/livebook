import AppKit
import ElixirKit

#if canImport(AppIntents)
    import AppIntents
#endif

@main
public struct Livebook {
    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var logPath: String!
    private var launchedByOpenURL = false
    internal var initialURLs: [URL] = []
    private var url: String?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        logPath = "\(NSHomeDirectory())/Library/Logs/Livebook.log"

        ElixirKit.API.start(
            name: "app",
            logPath: logPath,
            readyHandler: {
                if (self.initialURLs == []) {
                    ElixirKit.API.publish("open", "")
                }
                else {
                    for url in self.initialURLs {
                        ElixirKit.API.publish("open", url.absoluteString)
                    }
                }
            },
            terminationHandler: { process in
                if process.terminationStatus != 0 {
                    DispatchQueue.main.sync {
                        let alert = NSAlert()
                        alert.alertStyle = .critical
                        alert.messageText = "Livebook exited with error status \(process.terminationStatus)"
                        alert.addButton(withTitle: "Dismiss")
                        alert.addButton(withTitle: "View Logs")

                        switch alert.runModal() {
                        case .alertSecondButtonReturn:
                            self.viewLogs()
                        default:
                            ()
                        }
                    }
                }

                NSApp.terminate(nil)
            }
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let button = statusItem.button!
        let icon = NSImage(named: "Icon")!
        let resizedIcon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { (dstRect) -> Bool in
            icon.draw(in: dstRect)
            return true
        }
        button.image = resizedIcon
        let menu = NSMenu()

        let copyURLItem = NSMenuItem(title: "Copy URL", action: nil, keyEquivalent: "c")

        menu.items = [
            NSMenuItem(title: "Open", action: #selector(open), keyEquivalent: "o"),
            copyURLItem,
            NSMenuItem(title: "View Logs", action: #selector(viewLogs), keyEquivalent: "l"),
        ]

        if #available(macOS 13, *) {
            menu.items.append(
                NSMenuItem(title: "Add \"New Notebook\" Shortcut", action: #selector(addNewNotebookShortcut), keyEquivalent: "")
            )
        }

        menu.items.append(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.items.append(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        ElixirKit.API.addObserver(queue: .main) { (name, data) in
            switch name {
            case "url":
                copyURLItem.action = #selector(self.copyURL)
                self.url = data
            default:
                fatalError("unknown event \(name)")
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        ElixirKit.API.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ElixirKit.API.publish("open", "")
        return true
    }

    func application(_ app: NSApplication, open urls: [URL]) {
        if !ElixirKit.API.isRunning {
            initialURLs = urls
            return
        }

        for url in urls {
            ElixirKit.API.publish("open", url.absoluteString)
        }
    }

    @objc
    func open() {
        ElixirKit.API.publish("open", "")
    }

    @objc
    func copyURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(url!.data(using: .utf8), forType: NSPasteboard.PasteboardType.URL)
    }

    @objc
    func viewLogs() {
        NSWorkspace.shared.open(NSURL.fileURL(withPath: logPath))
    }

    @objc
    func openSettings() {
        ElixirKit.API.publish("open", "/settings")
    }

    @objc
    func addNewNotebookShortcut() {
        let url = URL(string: "shortcuts://shortcuts/c0fecf5a034642cbb2cf66dbf9f581ed")!
        NSWorkspace.shared.open(url)
    }
}

@available(macOS 13, *)
struct NewNotebookIntent: AppIntent {
    static var title: LocalizedStringResource = "Create New Livebook"

    static var description = IntentDescription("Create a new notebook.")

    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ElixirKit.API.publish("open", "/new")

        if ElixirKit.API.isRunning {
            ElixirKit.API.publish("open", "/new")
        }
        else {
            /* (NSApplication.shared.delegate).initialUrls = [URL(string: "/new")!] */
        }

        return .result(value: "ok")
    }
}

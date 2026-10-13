import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
  private var intentsChannel: FlutterMethodChannel?
  private var macosChannel: FlutterMethodChannel?
  private var pendingUrl: String?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // the app lives in the menu bar; closing the window only hides it
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else { return }
    let messenger = controller.engine.binaryMessenger

    intentsChannel = FlutterMethodChannel(name: "personal_calendar/intents", binaryMessenger: messenger)
    intentsChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getInitialIntent":
        if let url = self?.pendingUrl {
          self?.pendingUrl = nil
          result(["uri": url, "text": URLComponents(string: url)?.queryItems?.first { $0.name == "text" }?.value as Any])
        } else {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    macosChannel = FlutterMethodChannel(name: "personal_calendar/macos", binaryMessenger: messenger)
    macosChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "setLaunchAtLogin":
        let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
        if #available(macOS 13.0, *) {
          do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            result(nil)
          } catch {
            result(FlutterError(code: "launch_at_login", message: error.localizedDescription, details: nil))
          }
        } else {
          result(FlutterError(code: "unsupported", message: "macOS 13 or newer is required", details: nil))
        }
      case "isLaunchAtLogin":
        if #available(macOS 13.0, *) {
          result(SMAppService.mainApp.status == .enabled)
        } else {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    super.applicationDidFinishLaunching(notification)
  }

  /// personalcalendar://capture?text=… from Shortcuts, Automator, other apps.
  override func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.first else { return }
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "text" }?.value
    if let ch = intentsChannel {
      ch.invokeMethod("intent", arguments: ["uri": url.absoluteString, "text": text as Any])
    } else {
      pendingUrl = url.absoluteString
    }
  }

  /// Dock icon click (when not hidden) brings the window back.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
    }
    return true
  }
}

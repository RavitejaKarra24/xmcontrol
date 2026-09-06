import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  var controller: HeadphoneController?
  var statusController: StatusItemController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    controller?.ensureStarted()
    if let controller {
      statusController = StatusItemController(controller: controller)
    }
  }
}

@main
struct XMControlApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var controller: HeadphoneController

  init() {
    let c = HeadphoneController()
    _controller = StateObject(wrappedValue: c)
    appDelegate.controller = c
  }

  var body: some Scene {
    Window("XM Control", id: "main") {
      MainWindowView()
        .environmentObject(controller)
    }
    .defaultSize(width: 960, height: 900)
    .defaultPosition(.center)
    .windowResizability(.contentMinSize)
    .windowToolbarStyle(.unifiedCompact)
  }
}

/// Native menu bar item: left-click opens the control panel popover,
/// right-click shows a context menu with Reconnect / Quit.
@MainActor
final class StatusItemController: NSObject {
  private let controller: HeadphoneController
  private let popover = NSPopover()
  private var statusItem: NSStatusItem?
  private var cancellables: Set<AnyCancellable> = []

  init(controller: HeadphoneController) {
    self.controller = controller
    super.init()

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item

    if let button = item.button {
      button.image = statusImage()
      button.image?.size = NSSize(width: 18, height: 18)
      button.title = ""
      button.font = .monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      button.target = self
      button.action = #selector(statusItemClicked)
    }

    popover.behavior = .transient
    popover.animates = true
    popover.contentViewController = NSHostingController(
      rootView: PanelView().environmentObject(controller)
    )

    // Keep the icon and battery text in sync with live state.
    controller.$battery
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.refreshStatusItem() }
      .store(in: &cancellables)
    controller.$conn
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.refreshStatusItem() }
      .store(in: &cancellables)
  }

  // MARK: Interaction

  @objc private func statusItemClicked() {
    // Status bar buttons fire the action for left *and* right clicks;
    // inspect the current event to tell them apart.
    let event = NSApp.currentEvent
    if event?.type == .rightMouseUp || event?.type == .otherMouseUp {
      showContextMenu()
    } else {
      togglePopover()
    }
  }

  private func togglePopover() {
    guard let button = statusItem?.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }

  private func showContextMenu() {
    guard let button = statusItem?.button else { return }

    let menu = NSMenu()
    let reconnect = NSMenuItem(
      title: "Reconnect",
      action: #selector(reconnectClicked),
      keyEquivalent: ""
    )
    reconnect.target = self
    menu.addItem(reconnect)
    menu.addItem(.separator())
    let quit = NSMenuItem(
      title: "Quit XMControl",
      action: #selector(quitClicked),
      keyEquivalent: "q"
    )
    quit.target = self
    menu.addItem(quit)

    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
  }

  @objc private func reconnectClicked() {
    controller.reconnect()
  }

  @objc private func quitClicked() {
    NSApp.terminate(nil)
  }

  // MARK: Appearance

  private func refreshStatusItem() {
    guard let button = statusItem?.button else { return }
    button.image = statusImage()
    if case .connected = controller.conn, let battery = controller.battery {
      button.title = "\(battery.percent)%"
    } else {
      button.title = ""
    }
  }

  private func statusImage() -> NSImage? {
    let lowBattery: Bool
    if case .connected = controller.conn, let battery = controller.battery {
      lowBattery = battery.percent <= 20
    } else {
      lowBattery = false
    }
    let name: String
    switch controller.conn {
    case .connected:
      name = lowBattery ? "headphones.badge.exclamationmark" : "headphones"
    case .waitingForHeadphones:
      name = "headphones.slash"
    default:
      name = "headphones"
    }
    let image = NSImage(systemSymbolName: name, accessibilityDescription: "XMControl")
    image?.isTemplate = true
    return image
  }
}

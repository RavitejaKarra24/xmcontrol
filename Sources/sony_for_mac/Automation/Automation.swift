import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

/// A listening profile applied while a particular app is frontmost.
struct AppProfileRule: Codable, Equatable, Identifiable {
  var bundleID: String
  var appName: String
  var profile: String

  var id: String { bundleID }
  var listeningProfile: ListeningProfile? { ListeningProfile(rawValue: profile) }
}

/// Commands accepted from `sonyformac://` links, e.g. from Shortcuts.
/// Only reversible listening changes are exposed; nothing that pairs,
/// forgets, disconnects or powers off.
enum URLCommand: Equatable {
  case mode(ANCMode)
  case nextMode
  case profile(ListeningProfile)
  case profileOff

  static let scheme = "sonyformac"

  init?(url: URL) {
    guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else { return nil }
    let value = url.pathComponents.dropFirst().first?.lowercased() ?? ""
    switch (host, value) {
    case ("mode", "nc"), ("mode", "noise-cancelling"): self = .mode(.noiseCancelling)
    case ("mode", "transparency"), ("mode", "ambient"): self = .mode(.ambient)
    case ("mode", "off"): self = .mode(.off)
    case ("mode", "next"): self = .nextMode
    case ("profile", "off"): self = .profileOff
    case ("profile", let name):
      guard let profile = ListeningProfile(rawValue: name) else { return nil }
      self = .profile(profile)
    default: return nil
    }
  }
}

/// Mac-side automation: per-app profiles, global hotkeys and URL commands.
@MainActor
final class Automation: ObservableObject {
  nonisolated static let rulesKey = "automation.appProfileRules"
  nonisolated static let appProfilesKey = "automation.appProfilesEnabled"
  nonisolated static let hotkeysKey = "automation.hotkeysEnabled"

  @Published private(set) var rules: [AppProfileRule]
  @Published var appProfilesEnabled: Bool {
    didSet {
      defaults.set(appProfilesEnabled, forKey: Self.appProfilesKey)
      if !appProfilesEnabled { leaveAutomaticProfile() } else { evaluateFrontmostApp() }
    }
  }
  @Published var hotkeysEnabled: Bool {
    didSet {
      defaults.set(hotkeysEnabled, forKey: Self.hotkeysKey)
      hotkeys.setEnabled(hotkeysEnabled)
    }
  }

  private let controller: HeadphoneController
  private let defaults: UserDefaults
  private let hotkeys = HotKeyCenter()
  private var cancellables: Set<AnyCancellable> = []
  private var activationObserver: NSObjectProtocol?
  /// The profile automation applied, and what was selected before it.
  private var automaticProfile: ListeningProfile?
  private var profileBeforeAutomation: ListeningProfile?
  private var pendingURLCommand: (command: URLCommand, at: Date)?

  init(controller: HeadphoneController, defaults: UserDefaults = .standard) {
    self.controller = controller
    self.defaults = defaults
    rules = Self.loadRules(from: defaults)
    appProfilesEnabled = defaults.bool(forKey: Self.appProfilesKey)
    hotkeysEnabled = defaults.bool(forKey: Self.hotkeysKey)
  }

  func start() {
    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.evaluateFrontmostApp() }
    }
    controller.$isReady
      .removeDuplicates()
      .sink { [weak self] ready in
        guard ready else {
          self?.automaticProfile = nil
          self?.profileBeforeAutomation = nil
          return
        }
        Task { @MainActor in
          self?.runPendingURLCommand()
          self?.evaluateFrontmostApp()
        }
      }
      .store(in: &cancellables)

    hotkeys.onHotKey = { [weak self] key in self?.perform(key) }
    hotkeys.setEnabled(hotkeysEnabled)
  }

  // MARK: Rules

  nonisolated static func loadRules(from defaults: UserDefaults) -> [AppProfileRule] {
    guard let data = defaults.data(forKey: rulesKey),
      let rules = try? JSONDecoder().decode([AppProfileRule].self, from: data) else { return [] }
    return rules.filter { $0.listeningProfile != nil && !$0.bundleID.isEmpty }
  }

  func addRule(bundleID: String, appName: String, profile: ListeningProfile) {
    guard bundleID != Bundle.main.bundleIdentifier else { return }
    rules.removeAll { $0.bundleID == bundleID }
    rules.append(AppProfileRule(bundleID: bundleID, appName: appName, profile: profile.rawValue))
    rules.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    saveRules()
    evaluateFrontmostApp()
  }

  func setProfile(_ profile: ListeningProfile, for rule: AppProfileRule) {
    guard let index = rules.firstIndex(of: rule) else { return }
    rules[index].profile = profile.rawValue
    saveRules()
    evaluateFrontmostApp()
  }

  func removeRule(_ rule: AppProfileRule) {
    rules.removeAll { $0 == rule }
    saveRules()
    evaluateFrontmostApp()
  }

  /// Lets the user pick an app bundle to add a rule for.
  func chooseApp(profile: ListeningProfile) {
    let panel = NSOpenPanel()
    panel.title = "Choose an app"
    panel.prompt = "Add"
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowsMultipleSelection = false
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let url = panel.url,
      let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
    let name = FileManager.default.displayName(atPath: url.path)
      .replacingOccurrences(of: ".app", with: "")
    addRule(bundleID: bundleID, appName: name, profile: profile)
  }

  private func saveRules() {
    if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: Self.rulesKey) }
  }

  // MARK: Frontmost app

  private func evaluateFrontmostApp() {
    guard appProfilesEnabled, controller.isReady,
      let app = NSWorkspace.shared.frontmostApplication,
      app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
    if let rule = rules.first(where: { $0.bundleID == app.bundleIdentifier }),
      let profile = rule.listeningProfile
    {
      guard controller.selectedProfile != profile else { return }
      if automaticProfile == nil { profileBeforeAutomation = controller.selectedProfile }
      automaticProfile = profile
      controller.applyProfile(profile, reason: "\(profile.title) on for \(rule.appName).")
    } else {
      leaveAutomaticProfile()
    }
  }

  /// Restores what the user had, unless they changed settings since.
  private func leaveAutomaticProfile() {
    guard let applied = automaticProfile else { return }
    automaticProfile = nil
    let previous = profileBeforeAutomation
    profileBeforeAutomation = nil
    guard controller.selectedProfile == applied else { return }
    if let previous {
      controller.applyProfile(previous, reason: "\(previous.title) is back.")
    } else {
      controller.clearProfile()
    }
  }

  // MARK: Hotkeys and URLs

  private func perform(_ key: HotKeyCenter.Key) {
    switch key {
    case .nextMode: run(.nextMode)
    case .profile(let profile):
      run(controller.selectedProfile == profile ? .profileOff : .profile(profile))
    }
  }

  func handle(_ url: URL) {
    guard let command = URLCommand(url: url) else { return }
    if controller.isReady {
      run(command)
    } else {
      pendingURLCommand = (command, Date())
      controller.ensureStarted()
    }
  }

  private func runPendingURLCommand() {
    guard let pending = pendingURLCommand else { return }
    pendingURLCommand = nil
    if Date().timeIntervalSince(pending.at) < 60 { run(pending.command) }
  }

  private func run(_ command: URLCommand) {
    guard controller.isReady else { return }
    // A manual or scripted change takes over from automation.
    automaticProfile = nil
    profileBeforeAutomation = nil
    switch command {
    case .mode(let mode): controller.setMode(mode)
    case .nextMode: controller.setMode(controller.anc.mode.next)
    case .profile(let profile): controller.applyProfile(profile)
    case .profileOff: controller.clearProfile()
    }
  }
}

extension ANCMode {
  /// Noise cancelling → Transparency → Off.
  var next: ANCMode {
    switch self {
    case .noiseCancelling: return .ambient
    case .ambient: return .off
    case .off: return .noiseCancelling
    }
  }
}

// MARK: - Global hotkeys

/// System-wide shortcuts through Carbon's RegisterEventHotKey, which needs no
/// Accessibility or Input Monitoring permission.
@MainActor
final class HotKeyCenter {
  enum Key: Equatable {
    case nextMode
    case profile(ListeningProfile)
  }

  /// ⌃⌥⌘ plus N, or 1–4 for the profiles in display order.
  static let bindings: [(key: Key, keyCode: Int, label: String)] = [
    (.nextMode, kVK_ANSI_N, "⌃⌥⌘N"),
    (.profile(.focus), kVK_ANSI_1, "⌃⌥⌘1"),
    (.profile(.commute), kVK_ANSI_2, "⌃⌥⌘2"),
    (.profile(.aware), kVK_ANSI_3, "⌃⌥⌘3"),
    (.profile(.podcast), kVK_ANSI_4, "⌃⌥⌘4"),
  ]
  private static let signature: OSType = 0x53_46_4D_48  // "SFMH"
  private static weak var current: HotKeyCenter?

  var onHotKey: ((Key) -> Void)?
  private var refs: [EventHotKeyRef] = []
  private var handler: EventHandlerRef?

  func setEnabled(_ enabled: Bool) {
    unregister()
    guard enabled else { return }
    Self.current = self
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
      var id = EventHotKeyID()
      let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
      guard status == noErr, id.signature == HotKeyCenter.signature else { return OSStatus(eventNotHandledErr) }
      let index = Int(id.id)
      Task { @MainActor in
        guard HotKeyCenter.bindings.indices.contains(index) else { return }
        HotKeyCenter.current?.onHotKey?(HotKeyCenter.bindings[index].key)
      }
      return noErr
    }, 1, &spec, nil, &handler)

    let modifiers = UInt32(controlKey | optionKey | cmdKey)
    for (index, binding) in Self.bindings.enumerated() {
      var ref: EventHotKeyRef?
      let id = EventHotKeyID(signature: Self.signature, id: UInt32(index))
      if RegisterEventHotKey(UInt32(binding.keyCode), modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
        let ref
      {
        refs.append(ref)
      }
    }
  }

  private func unregister() {
    refs.forEach { UnregisterEventHotKey($0) }
    refs.removeAll()
    if let handler { RemoveEventHandler(handler) }
    handler = nil
  }
}

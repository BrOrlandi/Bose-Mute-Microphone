import AppKit
import BoseMuteCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let backend = CoreAudioBackend()
    private lazy var controller = MuteController(backend: FilteringBackend(base: backend) { [weak self] device in
        !(self?.ignoredUIDs.contains(device.uid) ?? false)
    })
    private let store = SnapshotStore.default
    private let bose = BoseButtonMonitor()
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var enforceTimer: Timer?
    private let log = EventLog()
    private let defaults = UserDefaults.standard

    private var soundsEnabled: Bool {
        get { defaults.object(forKey: "soundsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "soundsEnabled") }
    }
    private var boseEnabled: Bool {
        get { defaults.object(forKey: "boseShortcutEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "boseShortcutEnabled") }
    }

    /// Devices the user chose to leave out (e.g. virtual loopbacks that ignore mute writes).
    private var ignoredUIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "ignoredDeviceUIDs") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "ignoredDeviceUIDs") }
    }

    private lazy var muteSound = NSSound(data: ToneGenerator.wav(ToneGenerator.muteCue))
    private lazy var unmuteSound = NSSound(data: ToneGenerator.wav(ToneGenerator.unmuteCue))

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller.onSnapshotsChanged = { [store] in store.save($0) }
        // Never mutes on launch. Only resumes a mute that was active when a previous run died.
        let saved = store.load()
        if !saved.isEmpty {
            controller.resume(from: saved)
            log.add("Retomado estado mutado salvo de execução anterior (\(saved.count) dispositivo(s)).")
        }

        backend.startObserving { [weak self] in self?.audioChanged() }
        hotKey = HotKey { [weak self] in self?.toggle(source: "atalho ⌃⌥⌘M") }
        if hotKey == nil { log.add("Atalho ⌃⌥⌘M indisponível (já registrado por outro app?).") }

        bose.onPress = { [weak self] address in self?.toggle(source: "Bose (HFP voice recognition \(address))") }
        bose.onStateChange = { [weak self] state in
            self?.log.add("Monitor Bose: \(state)")
            self?.updateIcon()
        }
        bose.onDiagnostic = { [weak self] message in self?.log.add("HFP: \(message)") }
        if boseEnabled { bose.start() }

        log.add("App iniciado. Dispositivos: " + backend.inputDevices().map(\.name).joined(separator: ", "))
        configureLoginItemOnFirstRun()
        refreshEnforceTimer()
        updateIcon()
    }

    // MARK: Launch at login

    /// Registers the app as a Login Item (System Settings > General > Login Items) once.
    /// Afterwards the menu checkbox is the source of truth, so a user who turns it off stays off.
    private func configureLoginItemOnFirstRun() {
        guard !defaults.bool(forKey: "loginItemConfigured") else { return }
        defaults.set(true, forKey: "loginItemConfigured")
        setLaunchAtLogin(true)
    }

    private var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            log.add("Iniciar com o Mac: \(enabled ? "ativado" : "desativado") (status \(SMAppService.mainApp.status.rawValue)).")
        } catch {
            log.add("Iniciar com o Mac: falhou ao \(enabled ? "ativar" : "desativar"): \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bose.stop()
        // Never leave the mics silenced without an indicator.
        if controller.isMuted {
            controller.unmute()
            log.add("Encerrando: estado anterior restaurado.")
        }
    }

    // MARK: Actions

    private func toggle(source: String) {
        let wasMuted = controller.isMuted
        controller.toggle()
        let status = controller.status
        if wasMuted {
            let issues = controller.lastRestoreIssues
            log.add("UNMUTE via \(source). " + (issues.isEmpty ? "Restauração verificada." :
                "Problemas: " + issues.map { "\($0.name): \($0.reason)" }.joined(separator: " | ")))
            if soundsEnabled { play(unmuteSound) }
        } else {
            log.add("MUTE via \(source). \(describe(status)). " + deviceSummary())
            if soundsEnabled { play(muteSound) }
        }
        refreshEnforceTimer()
        updateIcon()
    }

    private func play(_ sound: NSSound?) {
        guard let sound else { return }
        sound.stop()
        sound.play()
    }

    private func audioChanged() {
        if controller.isMuted {
            let before = controller.reports
            controller.enforce()
            if before != controller.reports { log.add("Mudança de áudio enquanto mutado: " + deviceSummary()) }
        }
        updateIcon()
    }

    private func refreshEnforceTimer() {
        enforceTimer?.invalidate()
        enforceTimer = nil
        guard controller.isMuted else { return }
        // Safety net in addition to Core Audio listeners.
        enforceTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.audioChanged() }
    }

    // MARK: UI

    private func describe(_ status: MuteStatus) -> String {
        switch status {
        case .unmuted: return "Microfones ativos"
        case .muted(let n): return "Microfones MUTADOS (\(n)/\(n) verificados)"
        case .partial(let n, let total): return "Mute PARCIAL (\(n)/\(total) verificados)"
        }
    }

    private func deviceSummary() -> String {
        controller.reports.values.sorted { $0.device.name < $1.device.name }.map { r in
            "\(r.device.name)=\(outcomeText(r.outcome))"
        }.joined(separator: ", ")
    }

    private func outcomeText(_ o: DeviceOutcome) -> String {
        switch o {
        case .muted(.muteProperty): return "mute verificado (software do driver)"
        case .muted(.volumeZero): return "volume de entrada 0 verificado (sem controle de mute)"
        case .unsupported(let r): return "NÃO suportado: \(r)"
        case .failed(let r): return "FALHOU: \(r)"
        }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let status = controller.status
        let symbol: String
        var color: NSColor? = nil
        var title = ""
        switch status {
        case .unmuted:
            symbol = "mic.fill"
        case .muted:
            symbol = "mic.slash.fill"; color = .systemRed; title = " MUTE"
        case .partial:
            symbol = "exclamationmark.triangle.fill"; color = .systemOrange; title = " MUTE?"
        }
        var image = NSImage(systemSymbolName: symbol, accessibilityDescription: describe(status))
        if let color {
            image = image?.withSymbolConfiguration(.init(paletteColors: [color]))
            image?.isTemplate = false
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: color, .font: NSFont.systemFont(ofSize: 11, weight: .bold)])
        } else {
            image?.isTemplate = true
            button.title = ""
        }
        button.image = image
        button.imagePosition = .imageLeading
        button.toolTip = describe(status)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = controller.status
        menu.addItem(disabled(describe(status)))
        let toggleItem = NSMenuItem(title: controller.isMuted ? "Reativar microfones" : "Silenciar todos os microfones",
                                    action: #selector(menuToggle), keyEquivalent: "m")
        toggleItem.keyEquivalentModifierMask = [.control, .option, .command]
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        menu.addItem(disabled("Dispositivos de entrada"))
        for device in backend.inputDevices() {
            var line = "  " + device.name
            if device.isDefaultInput { line += " (padrão)" }
            if device.isRunningSomewhere { line += " · em uso" }
            if ignoredUIDs.contains(device.uid) {
                line += " — ignorado (não é mutado)"
            } else if controller.isMuted {
                line += " — " + (controller.reports[device.uid].map { outcomeText($0.outcome) } ?? "pendente")
            } else {
                let s = backend.readState(of: device)
                line += " — " + (s.mute == true ? "mutado (fora do app)" : "ativo")
            }
            menu.addItem(disabled(line))
        }
        for issue in controller.lastRestoreIssues {
            menu.addItem(disabled("  ⚠︎ \(issue.name): \(issue.reason)"))
        }
        let ignoreMenu = NSMenu()
        for device in backend.inputDevices() {
            let item = NSMenuItem(title: device.name, action: #selector(toggleIgnored(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.state = ignoredUIDs.contains(device.uid) ? .on : .off
            ignoreMenu.addItem(item)
        }
        let ignoreItem = NSMenuItem(title: "Ignorar dispositivos", action: nil, keyEquivalent: "")
        ignoreItem.submenu = ignoreMenu
        menu.addItem(ignoreItem)
        menu.addItem(.separator())

        let boseItem = NSMenuItem(title: "Usar atalho do Bose (Shortcut → voice control)", action: #selector(toggleBose), keyEquivalent: "")
        boseItem.target = self
        boseItem.state = boseEnabled ? .on : .off
        menu.addItem(boseItem)
        var boseLine = "  Monitor: "
        switch bose.state {
        case .running: boseLine += "ativo (log do bluetoothd)"
        case .stopped: boseLine += "desligado"
        case .failed(let r): boseLine += "erro — \(r)"
        }
        menu.addItem(disabled(boseLine))
        if let last = bose.lastEvent {
            let f = DateFormatter(); f.timeStyle = .medium
            menu.addItem(disabled("  Último evento: \(f.string(from: last.date)) de \(last.address)"))
        }
        let loginItem = NSMenuItem(title: "Iniciar com o Mac", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = launchAtLogin ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval {
            loginItem.title += " (aprovar em Ajustes > Itens de Início)"
        }
        menu.addItem(loginItem)
        let soundItem = NSMenuItem(title: "Sons de mute/unmute", action: #selector(toggleSounds), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = soundsEnabled ? .on : .off
        menu.addItem(soundItem)
        let logItem = NSMenuItem(title: "Abrir log de diagnóstico", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Sair (restaura microfones)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func menuToggle() { toggle(source: "menu") }

    @objc private func toggleBose() {
        boseEnabled.toggle()
        boseEnabled ? bose.start() : bose.stop()
    }

    @objc private func toggleIgnored(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        if ignoredUIDs.contains(uid) {
            ignoredUIDs.remove(uid)
            controller.enforce() // mutes it now if muted mode is on
        } else {
            ignoredUIDs.insert(uid)
            var note = "Dispositivo \(sender.title) marcado como ignorado."
            if let device = backend.inputDevices().first(where: { $0.uid == uid }) {
                if let issue = controller.release(device) { note += " Restauração falhou: \(issue.reason)" }
                else if controller.isMuted { note += " Estado anterior restaurado." }
            }
            log.add(note)
        }
        updateIcon()
    }

    @objc private func toggleLaunchAtLogin() { setLaunchAtLogin(!launchAtLogin) }

    @objc private func toggleSounds() { soundsEnabled.toggle() }

    @objc private func openLog() { NSWorkspace.shared.open(log.url) }
}

/// Plain-text event log in ~/Library/Logs (no audio content, only state changes).
final class EventLog {
    let url: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/Bose-Mute-Microphone.log")
    private let formatter = ISO8601DateFormatter()

    func add(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        NSLog("%@", message)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

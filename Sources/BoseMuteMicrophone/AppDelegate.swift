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
    private let siriCanceller = SiriCanceller()
    private var cancelSiriEnabled: Bool {
        // On by default: tested 2026-10-16, four presses in a row toggled reliably with Siri closed each time.
        get { defaults.object(forKey: "cancelSiriAfterBose") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "cancelSiriAfterBose") }
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

        siriCanceller.log = { [weak self] in self?.log.add($0) }
        bose.onPress = { [weak self] address in
            guard let self else { return }
            if self.cancelSiriEnabled { self.siriCanceller.arm() }
            self.toggle(source: "Bose (HFP voice recognition \(address))", fromBose: true)
        }
        bose.onStateChange = { [weak self] state in
            self?.log.add("Monitor Bose: \(state)")
            self?.updateIcon()
        }
        bose.onDiagnostic = { [weak self] message in
            self?.log.add("HFP: \(message)")
            self?.siriCanceller.observe(message)
            self?.cueAfterVoiceLink(message)
        }
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

    private func toggle(source: String, fromBose: Bool = false) {
        let wasMuted = controller.isMuted
        controller.toggle()
        let status = controller.status
        if wasMuted {
            let issues = controller.lastRestoreIssues
            log.add("UNMUTE via \(source). " + (issues.isEmpty ? "Restauração verificada." :
                "Problemas: " + issues.map { "\($0.name): \($0.reason)" }.joined(separator: " | ")))
            if soundsEnabled { cue(unmuteSound, fromBose: fromBose) }
        } else {
            log.add("MUTE via \(source). \(describe(status)). " + deviceSummary())
            if soundsEnabled { cue(muteSound, fromBose: fromBose) }
        }
        refreshEnforceTimer()
        updateIcon()
    }

    // MARK: Cues

    /// A Bose press also makes macOS open an HFP voice link for Siri, which switches the headset
    /// audio route and closes again ~1 s later. A cue played during that switch is lost (observed for
    /// mute, which also spends time verifying devices before the cue). So for Bose presses the cue
    /// waits until bluetoothd reports the voice link closed, with a fallback timeout.
    private var pendingCue: NSSound?
    private var pendingCueFallback: DispatchWorkItem?

    private func cue(_ sound: NSSound?, fromBose: Bool) {
        guard fromBose else { play(sound); return }
        pendingCue = sound
        pendingCueFallback?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.firePendingCue(reason: "tempo limite") }
        pendingCueFallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func cueAfterVoiceLink(_ message: String) {
        guard pendingCue != nil, message.contains("Received voice disconnection event") else { return }
        pendingCueFallback?.cancel()
        // let the route settle back to the normal (A2DP) output before playing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.firePendingCue(reason: "canal de voz fechado") }
    }

    private func firePendingCue(reason: String) {
        guard let sound = pendingCue else { return }
        pendingCue = nil
        pendingCueFallback?.cancel()
        pendingCueFallback = nil
        play(sound)
        log.add("Som tocado após \(reason).")
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
        } else if controller.isWatchingRestore {
            let before = controller.restoreReapplied.count
            controller.enforce()
            if controller.restoreReapplied.count > before {
                log.add("Driver mudou o valor após o unmute; restaurado de novo: " +
                        controller.restoreReapplied.suffix(from: before).joined(separator: ", "))
            }
        } else if enforceTimer != nil {
            refreshEnforceTimer() // restore watch over: stop the timer
        }
        updateIcon()
    }

    private func refreshEnforceTimer() {
        enforceTimer?.invalidate()
        enforceTimer = nil
        guard controller.isMuted || controller.isWatchingRestore else { return }
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
        if siriEnabled == false {
            // Tested 2026-10-15/16: with Siri off nobody answers the headset's voice request and it
            // stops sending presses until it reconnects.
            menu.addItem(disabled("  ⚠︎ Siri desligada: o atalho do Bose para após 1 toque. Ligue a Siri."))
        } else {
            if !cancelSiriEnabled {
                menu.addItem(disabled("  Dica: com a Siri ligada, o atalho do Bose também a abre."))
            }
        }
        let siriItem = NSMenuItem(title: "Abrir ajustes da Siri…",
                                  action: #selector(openSiriSettings), keyEquivalent: "")
        siriItem.target = self
        siriItem.toolTip = "O app só abre a tela de ajustes; não altera configurações do sistema."
        menu.addItem(siriItem)
        let cancelItem = NSMenuItem(title: "Fechar a Siri aberta pelo atalho do Bose",
                                    action: #selector(toggleCancelSiri), keyEquivalent: "")
        cancelItem.target = self
        cancelItem.state = cancelSiriEnabled ? .on : .off
        menu.addItem(cancelItem)
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

    /// Read-only look at the system Siri switch; nil when it cannot be read.
    private var siriEnabled: Bool? {
        CFPreferencesCopyAppValue("Assistant Enabled" as CFString, "com.apple.assistant.support" as CFString) as? Bool
    }

    @objc private func openSiriSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleCancelSiri() {
        cancelSiriEnabled.toggle()
        log.add("Cancelar a Siri após o atalho do Bose: \(cancelSiriEnabled ? "ligado" : "desligado").")
    }

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

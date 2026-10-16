import AppKit

/// Ends the Siri session that macOS starts for every Bose Shortcut press.
///
/// bluetoothd hands the headset's HFP voice-recognition request to Siri through a private
/// channel; no public API can veto that. With Siri turned off nobody answers the request and the
/// headset stops sending presses until it reconnects. So Siri stays on and, right after a Bose
/// press, this asks Siri to quit (and force-quits it if it ignores that). launchd relaunches it
/// on demand. Only Bose presses trigger it; Siri invoked any other way is left alone.
final class SiriCanceller {
    static let bundleID = "com.apple.Siri"
    private var armedUntil: Date?
    private var fallback: DispatchWorkItem?
    var log: ((String) -> Void)?

    /// Call on a Bose press. Cancels Siri when its voice link comes up, or after `fallbackDelay`.
    func arm(fallbackDelay: TimeInterval = 1.5) {
        armedUntil = Date().addingTimeInterval(5)
        fallback?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.cancel(reason: "tempo limite") }
        fallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + fallbackDelay, execute: work)
    }

    /// Feed HFP log lines; the SCO link for Siri's voice command is the signal it is listening.
    func observe(_ message: String) {
        guard let until = armedUntil, Date() < until else { return }
        if message.contains("Received voice audio connected event") || message.contains("for playing voice-command") {
            cancel(reason: "canal de voz da Siri aberto")
        }
    }

    private func cancel(reason: String) {
        guard armedUntil != nil else { return }
        armedUntil = nil
        fallback?.cancel()
        fallback = nil
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        guard let siri = apps.first else {
            log?("Siri: processo não encontrado (\(reason)).")
            return
        }
        let pid = siri.processIdentifier
        let asked = siri.terminate()
        log?("Siri: pedido para encerrar (\(reason)), aceito=\(asked), pid \(pid).")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard !siri.isTerminated else { self?.log?("Siri: encerrada."); return }
            let forced = siri.forceTerminate()
            self?.log?("Siri: ignorou o pedido; encerramento forçado=\(forced).")
        }
    }
}

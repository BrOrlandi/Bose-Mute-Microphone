import BoseMuteCore
import Foundation

/// Diagnostics without the menu bar app.
///   bose-mute-diag list                       read-only device/control report
///   bose-mute-diag selftest <uid-or-name>     mute + verify + restore ONE device (refuses devices in use)
///   bose-mute-diag watch-bose                 print Bose shortcut events (HFP voice recognition)
setvbuf(stdout, nil, _IOLBF, 0)
let backend = CoreAudioBackend()
let args = Array(CommandLine.arguments.dropFirst())

func describe(_ s: InputControlState) -> String {
    let vols = s.volumes.sorted { $0.key < $1.key }.map { "el\($0.key)=\(String(format: "%.3f", $0.value))" }
    return "mute=\(s.mute.map { "\($0)" } ?? "n/a") volume[\(vols.joined(separator: " "))]"
}

switch args.first {
case "list", nil:
    for d in backend.inputDevices() {
        let sup = backend.support(for: d)
        print("\(d.name)\n  uid=\(d.uid) transport=\(d.transport) default=\(d.isDefaultInput) inUse=\(d.isRunningSomewhere)")
        print("  muteSettable=\(sup.muteSettable) settableVolumeElements=\(sup.settableVolumeElements)")
        print("  state: \(describe(backend.readState(of: d)))")
    }

case "selftest":
    guard args.count >= 2, let device = backend.inputDevices().first(where: { $0.uid == args[1] || $0.name == args[1] }) else {
        print("uso: bose-mute-diag selftest <uid-ou-nome> [--allow-in-use]"); exit(2)
    }
    if device.isRunningSomewhere && !args.contains("--allow-in-use") {
        print("RECUSADO: \(device.name) está em uso por algum processo (possível conversa ativa). Use --allow-in-use só com combinação prévia.")
        exit(3)
    }
    let before = backend.readState(of: device)
    print("antes:     \(describe(before))")
    let controller = MuteController(backend: FilteringBackend(base: backend) { $0.uid == device.uid })
    controller.mute()
    let report = controller.reports[device.uid]
    print("mute:      \(report.map { "\($0.outcome)" } ?? "sem relatório") -> \(describe(backend.readState(of: device)))")
    print("status:    \(controller.status)")
    Thread.sleep(forTimeInterval: 0.5)
    controller.unmute()
    let after = backend.readState(of: device)
    print("restaurado:\(describe(after))")
    let issues = controller.lastRestoreIssues
    let same = after.mute == before.mute && before.volumes.allSatisfy { abs((after.volumes[$0.key] ?? -1) - $0.value) < 0.01 }
    print(issues.isEmpty && same ? "OK: estado original restaurado e verificado" : "PROBLEMA: \(issues) igual=\(same)")
    exit(issues.isEmpty && same && report?.outcome.isVerifiedMuted == true ? 0 : 1)

case "watch-bose":
    let monitor = BoseButtonMonitor()
    monitor.onPress = { print("\(Date()) Bose shortcut (HFP voice recognition) de \($0)") }
    monitor.onStateChange = { print("monitor: \($0)") }
    monitor.onDiagnostic = { print("\(Date()) HFP: \($0)") }
    monitor.start()
    print("Aguardando eventos. Ctrl-C para sair. Predicado: \(BoseButtonMonitor.predicate)")
    RunLoop.main.run()

default:
    print("comandos: list | selftest <uid-ou-nome> [--allow-in-use] | watch-bose")
    exit(2)
}

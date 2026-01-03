//
//  ContentView.swift
//  Marcello2020-dev
//
//  Created by Marcel Mißbach on 03.01.26.
//

import SwiftUI
import AppKit
import Foundation
import Combine
import Darwin

// MARK: - UI

struct ContentView: View {
    @StateObject private var svc = AusweisAppResetService()

    // ISO/IEC 7810 ID-1 (Ausweis/Kreditkarte) aspect ratio
    private let cardAspect: CGFloat = 85.60 / 53.98

    private var brandNSImage: NSImage {
        // Optional: if you later add an asset named "BrandIcon" it will be used automatically.
        NSImage(named: "BrandIcon") ?? NSApplication.shared.applicationIconImage
    }

    var body: some View {
        ZStack {
            // Subtle page background
            LinearGradient(
                colors: [Color.black.opacity(0.06), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Card surface
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)

                // Large watermark icon
                Image(nsImage: brandNSImage)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.10)
                    .rotationEffect(.degrees(-10))
                    .scaleEffect(1.10)
                    .offset(x: 210, y: 60)
                    .allowsHitTesting(false)

                // Bottom tricolor stripe (Schwarz–Rot–Gold)
                VStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.black.opacity(0.90))
                        Rectangle().fill(Color.red.opacity(0.85))
                        Rectangle().fill(Color(red: 0.83, green: 0.69, blue: 0.22)) // #D4AF37
                    }
                    .frame(height: 18)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
                .allowsHitTesting(false)

                // Foreground content
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(nsImage: brandNSImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 76, height: 76)
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("AusweisApp Reset Tool")
                                .font(.system(size: 24, weight: .semibold))
                            Text("Reset, Neuinstallation und Log – kompakt in einer Karte")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Button("Großer Reset + Neuinstallation") {
                            Task { await svc.bigResetAndReinstall() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.83, green: 0.69, blue: 0.22)) // #D4AF37
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)

                        Button("Kleiner Reset") {
                            Task { await svc.smallReset() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.black.opacity(0.85))
                        .controlSize(.large)
                    }

                    Text("Log")
                        .font(.subheadline)

                    TextEditor(text: $svc.logText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 320)
                        .scrollContentBackground(.hidden)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Hinweis: Nach einem Reset ist die Smartphone-Kopplung in der Regel neu einzurichten. Für das Entfernen aus /Applications und das Löschen von ~/Library/Containers kann macOS zusätzliche Datenschutz-Rechte verlangen (Vollzugriff auf Festplatte + App-Management). Falls Homebrew/mas fehlen, wird Homebrew in Terminal gestartet (mit Log-Streaming) und danach mas via brew installiert; anschließend erfolgt die Neuinstallation via mas (Mac App Store).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button("Datenschutz & Sicherheit öffnen") {
                                svc.openPrivacySettingsRoot()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.black.opacity(0.85))

                            Button("Vollzugriff auf Festplatte") {
                                svc.openFullDiskAccessSettings()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.83, green: 0.69, blue: 0.22)) // #D4AF37

                            Button("App-Management") {
                                svc.openAppManagementSettings()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.red.opacity(0.85))
                        }
                        .controlSize(.regular)
                    }
                }
                .padding(18)
            }
            .aspectRatio(cardAspect, contentMode: .fit)
            .frame(maxWidth: 980)
            .padding(18)
        }
        // Window/scene sizing: keep the "Ausweis" feeling
        .frame(minWidth: 980, minHeight: 620)
    }
}

#Preview {
    ContentView()
}

// MARK: - Service (Variante A + B)

@MainActor
final class AusweisAppResetService: ObservableObject {
    @Published var logText: String = ""

    // App Store ID: AusweisApp Bund
    private let appStoreId = "948660805"

    // Default (häufig relevant für Prefs/Container); tatsächliche Bundle-ID wird aus der App gelesen, wenn möglich.
    private let fallbackBundleId = "com.governikus.ausweisapp2"

    private let possibleAppNames = ["AusweisApp Bund.app", "AusweisApp.app"]

    private var tailProcess: Process?
    private var adminPromptCount: Int = 0

    private struct DeleteTargetsResult {
        var needsAdmin: [String] = []
        var needsFullDiskAccess: Bool = false
    }

    // MARK: Public API

    func smallReset() async {
        append("== Kleiner Reset ==")

        let appURL = findAusweisAppURL()
        if let appURL {
            append("App gefunden: \(appURL.path)")
        } else {
            append("WARNUNG: App nicht gefunden. Ich räume nur typische User-Datenpfade.")
        }

        let bundleId = readBundleId(appURL: appURL) ?? fallbackBundleId
        append("Bundle-ID: \(bundleId)")

        let del = await performBaseReset(appURL: appURL, bundleId: bundleId)

        if del.needsFullDiskAccess {
            append("ABBRUCH: macOS blockiert das Löschen (TCC). Erforderlich: Vollzugriff auf Festplatte für dieses Tool.")
            append("Hinweis: Nach dem Aktivieren die Tool-App einmal komplett beenden und neu starten.")
            openFullDiskAccessSettings()
            append("Fertig.")
            return
        }

        if !del.needsAdmin.isEmpty {
            let ok = runAdminDeleteBatch(del.needsAdmin)
            if !ok {
                append("ABBRUCH: Einige Pfade konnten trotz Admin nicht gelöscht werden (macOS Datenschutz/TCC).")
                append("Aktiviere je nach Hinweis im Log: Vollzugriff auf Festplatte und starte dann erneut.")
                append("Wichtig: Bei Ausführung aus Xcode gelten Rechte für den Debug-Runner; für stabile Rechte die exportierte/standalone App autorisieren.")
                append("Fertig.")
                return
            }
        }

        // Neustart erst NACH dem finalen Löschen
        if let urlToOpen = appURL ?? findAusweisAppURL() {
            append("Starte App nach Reset neu…")
            openApp(at: urlToOpen)
        } else {
            append("Hinweis: App-Pfad nicht gefunden; bitte manuell über Launchpad/Programme starten.")
        }

        append("Fertig.")
    }

    func bigResetAndReinstall() async {
        append("== Großer Reset + Neuinstallation ==")

        guard let appURL = findAusweisAppURL() else {
            append("FEHLER: AusweisApp nicht gefunden. Für Variante A wird das App-Bundle benötigt.")
            append("Fallback: App Store Seite öffnen.")
            openURL("https://apps.apple.com/de/app/ausweisapp-bund/id\(appStoreId)")
            return
        }

        let bundleId = readBundleId(appURL: appURL) ?? fallbackBundleId
        append("App: \(appURL.path)")
        append("Bundle-ID: \(bundleId)")

        // 1) Reset-Kern: Kill + User-Daten löschen
        let del = await performBaseReset(appURL: appURL, bundleId: bundleId)

        if del.needsFullDiskAccess {
            append("ABBRUCH: macOS blockiert das Löschen der User-Daten (TCC). Erforderlich: Vollzugriff auf Festplatte für dieses Tool.")
            append("Hinweis: Nach dem Aktivieren die Tool-App einmal komplett beenden und neu starten.")
            openFullDiskAccessSettings()
            append("Fertig.")
            return
        }

        if !del.needsAdmin.isEmpty {
            let ok = runAdminDeleteBatch(del.needsAdmin)
            if !ok {
                append("ABBRUCH: Einige Pfade konnten trotz Admin nicht gelöscht werden (macOS Datenschutz/TCC).")
                append("Aktiviere je nach Hinweis im Log: Vollzugriff auf Festplatte und starte dann erneut.")
                append("Wichtig: Bei Ausführung aus Xcode gelten Rechte für den Debug-Runner; für stabile Rechte die exportierte/standalone App autorisieren.")
                append("Fertig.")
                return
            }
        }

        // 2) App entfernen
        if appURL.path.hasPrefix("/Applications/") {
            append("Entferne App aus /Applications (benötigt ggf. App-Management)…")
            let ok = await recycleApplicationBundle(appURL)
            guard ok else {
                append("Fertig.")
                return
            }
        } else {
            append("Entferne App (kein /Applications-Pfad; ohne Admin)…")
            do {
                try FileManager.default.removeItem(at: appURL)
            } catch {
                append("FEHLER: App konnte nicht entfernt werden: \(error.localizedDescription)")
                return
            }
        }

        // 3) Homebrew sicherstellen (ggf. Terminal-Installer starten + Log in GUI streamen)
        guard let brew = await ensureHomebrewInstalled() else {
            append("Abbruch: Homebrew ist nicht verfügbar. Bitte Installation im Terminal abschließen und erneut versuchen.")
            return
        }

        // 4) mas sicherstellen (Terminalausgabe in GUI)
        let masOk = await ensureMasInstalled(brewPath: brew)
        guard masOk else {
            append("Abbruch: mas steht nicht zur Verfügung. Öffne App Store Seite als Fallback.")
            openURL("https://apps.apple.com/de/app/ausweisapp-bund/id\(appStoreId)")
            return
        }

        // 5) Neuinstallation via mas
        append("Installiere AusweisApp Bund via mas install \(appStoreId)…")
        append("Hinweis: Du musst im Mac App Store angemeldet sein.")

        // WICHTIG: mas als root via AppleScript führt zu „Failed to get sudo uid“.
        // Daher: mas als Nutzer im Terminal (TTY vorhanden), Log in GUI streamen.
        let masLogURL = URL(fileURLWithPath: "/tmp/ausweisapp-mas-install.log")
        try? "".write(to: masLogURL, atomically: true, encoding: .utf8)
        startTailing(masLogURL)

        let termMasCmd = "/bin/zsh -lc \"mas install \(appStoreId) 2>&1 | tee -a \(masLogURL.path)\""
        openTerminalAndRun(termMasCmd, autoCloseWhenDone: true)

        // Poll: warte bis App wieder auftaucht (max ~5 Minuten)
        var installedURL: URL? = nil
        for _ in 0..<150 {
            if let u = findAusweisAppURL() {
                installedURL = u
                break
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
        }

        stopTailing()

        guard let newURL = installedURL else {
            append("FEHLER: App wurde nach mas install nicht gefunden (Timeout).")
            append("Prüfe Terminal: ggf. sudo-Prompt, Store-Login, Netzwerk.")
            append("Fallback: App Store Seite öffnen.")
            openURL("https://apps.apple.com/de/app/ausweisapp-bund/id\(appStoreId)")
            return
        }

        append("Installation abgeschlossen: \(newURL.path)")
        append("Starte App neu…")
        openApp(at: newURL)

        append("Fertig.")
    }

    // MARK: - Discovery

    private func findAusweisAppURL() -> URL? {
        let fm = FileManager.default

        let standardCandidates = [
            "/Applications/AusweisApp Bund.app",
            "/Applications/AusweisApp.app",
            "\(NSHomeDirectory())/Applications/AusweisApp Bund.app",
            "\(NSHomeDirectory())/Applications/AusweisApp.app"
        ]

        for path in standardCandidates where fm.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        // Spotlight fallback
        for name in possibleAppNames {
            let query = "kMDItemKind == 'Application' && kMDItemFSName == '\(name)'"
            let output = runProcessCapture("/usr/bin/mdfind", [query])
            if let first = output.split(separator: "\n").first {
                let p = String(first)
                if !p.isEmpty, fm.fileExists(atPath: p) {
                    return URL(fileURLWithPath: p)
                }
            }
        }

        return nil
    }

    private func readBundleId(appURL: URL?) -> String? {
        guard let appURL, let bundle = Bundle(url: appURL) else { return nil }
        return bundle.bundleIdentifier
    }

    // MARK: - Reset Targets (eng gefasst)

    private func buildTargets(bundleId: String) -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let lib = home.appendingPathComponent("Library", isDirectory: true)

        // Eng gefasst, keine weiten Wildcards.
        let possible: [URL] = [
            lib.appendingPathComponent("Preferences/\(bundleId).plist"),
            lib.appendingPathComponent("Preferences/com.governikus.ausweisapp2.plist"),

            lib.appendingPathComponent("Containers/\(bundleId)", isDirectory: true),
            lib.appendingPathComponent("Containers/AusweisApp", isDirectory: true),
            lib.appendingPathComponent("Containers/AusweisAppAutostartHelper", isDirectory: true),

            lib.appendingPathComponent("Caches/\(bundleId)", isDirectory: true),
            lib.appendingPathComponent("Saved Application State/\(bundleId).savedState", isDirectory: true)
        ]

        let fm = FileManager.default
        return possible.filter { fm.fileExists(atPath: $0.path) }
    }

    private func listTargets(_ header: String, _ targets: [URL]) {
        append(header)
        if targets.isEmpty {
            append("  (keine gefunden)")
        } else {
            for t in targets {
                append("  - \(t.path)")
            }
        }
    }

    private func deleteTargets(_ targets: [URL]) async -> DeleteTargetsResult {
        let fm = FileManager.default
        var result = DeleteTargetsResult()

        func isTCCBlock(_ error: Error) -> Bool {
            let msg = error.localizedDescription.lowercased()
            // typischerweise TCC: „Operation not permitted“ / „don’t have permission to access …“
            return msg.contains("operation not permitted") ||
                   msg.contains("don’t have permission") ||
                   msg.contains("dont have permission") ||
                   msg.contains("keine berecht") ||
                   msg.contains("nicht berechtigt")
        }

        for url in targets {
            do {
                if fm.fileExists(atPath: url.path) {
                    try fm.removeItem(at: url)
                    append("Gelöscht: \(url.path)")
                }
            } catch {
                append("FEHLER beim Löschen \(url.path): \(error.localizedDescription)")

                // Wenn es nach TCC aussieht, NICHT per Admin-osascript eskalieren (das ist i.d.R. wirkungslos),
                // sondern Vollzugriff auf Festplatte anfordern.
                if isTCCBlock(error) {
                    result.needsFullDiskAccess = true
                    continue
                }

                let ns = error as NSError
                let isPermissionError =
                    (ns.domain == NSCocoaErrorDomain
                     && (ns.code == CocoaError.Code.fileWriteNoPermission.rawValue || ns.code == 513 || ns.code == 257))
                    || error.localizedDescription.localizedCaseInsensitiveContains("permission")
                    || error.localizedDescription.localizedCaseInsensitiveContains("berecht")

                guard isPermissionError else { continue }

                if fm.fileExists(atPath: url.path) {
                    result.needsAdmin.append(url.path)
                }
            }
        }

        return result
    }

    // MARK: - Gemeinsamer Reset-Kern (Variante B ist die Basis; Variante A = B + Zusatzschritte)

    /// Identischer Reset-Kern für A und B: Kill + User-Daten löschen. Gibt Ergebnis über benötigte Adminrechte/Vollzugriff zurück.
    private func performBaseReset(appURL: URL?, bundleId: String) async -> DeleteTargetsResult {
        await quitAppBestEffort(bundleId: bundleId, appURL: appURL)

        let targets = buildTargets(bundleId: bundleId)
        listTargets("Entferne User-Daten:", targets)
        return await deleteTargets(targets)
    }

    // MARK: - App Control

    private func quitAppBestEffort(bundleId: String, appURL: URL?) async {
        append("Beende App (HARTE Variante)…")

        let nameCandidates = ["AusweisApp Bund", "AusweisApp"]

        func sendSignal(_ pid: pid_t, _ sig: Int32) {
            let rc = kill(pid, sig)
            if rc == 0 { return }

            let err = errno
            if err == EPERM {
                append("Signal \(sig) an PID \(pid) fehlgeschlagen: EPERM (keine zusätzliche Admin-Abfrage; Admin wird gebündelt für Dateilöschungen).")
                return
            }

            if let cmsg = strerror(err) {
                append("Signal \(sig) an PID \(pid) fehlgeschlagen: errno \(err) (\(String(cString: cmsg)))")
            } else {
                append("Signal \(sig) an PID \(pid) fehlgeschlagen: errno \(err)")
            }
        }

        // Sammle laufende Prozesse (PIDs) über Bundle-ID und sichtbare App-Namen.
        var apps: [NSRunningApplication] = []
        apps.append(contentsOf: NSRunningApplication.runningApplications(withBundleIdentifier: bundleId))
        apps.append(contentsOf: NSWorkspace.shared.runningApplications.filter { app in
            guard let name = app.localizedName else { return false }
            return nameCandidates.contains(name)
        })

        // Dedup nach PID
        var pids: [pid_t] = []
        var seen = Set<pid_t>()
        for a in apps {
            let pid = a.processIdentifier
            if pid > 0, !seen.contains(pid) {
                seen.insert(pid)
                pids.append(pid)
            }
        }

        if pids.isEmpty {
            append("Keine laufenden Instanzen gefunden.")
            return
        }

        append("Gefundene PIDs: \(pids.map { String($0) }.joined(separator: ", "))")

        // Best-effort: erst freundlich über NSRunningApplication
        for pid in pids {
            if let ra = NSRunningApplication(processIdentifier: pid) {
                _ = ra.terminate()
            }
        }

        // 1) SIGTERM
        append("Sende SIGTERM…")
        for pid in pids { sendSignal(pid, SIGTERM) }

        // kurz warten
        try? await Task.sleep(nanoseconds: 400_000_000)

        // 2) SIGKILL (-9) falls noch da
        append("Sende SIGKILL (-9) an verbleibende Prozesse…")
        for pid in pids where kill(pid, 0) == 0 {
            // forceTerminate als best-effort
            if let ra = NSRunningApplication(processIdentifier: pid) {
                _ = ra.forceTerminate()
            }
            sendSignal(pid, SIGKILL)
        }

        // Final: kurz warten bis weg (max ~5s)
        for _ in 0..<10 {
            let still = pids.contains { kill($0, 0) == 0 }
            if !still {
                append("App ist beendet.")
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        append("WARNUNG: Prozess(e) laufen weiterhin. Falls nötig, bitte macOS 'Sofort beenden' nutzen und Log senden.")
    }

    private func openApp(at url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, err in
            guard let err else { return }
            Task { @MainActor [weak self] in
                self?.append("Startfehler: \(err.localizedDescription)")
            }
        }
    }

    // MARK: - System Settings Shortcuts (TCC/Privacy)

    /// Öffnet: Systemeinstellungen → Datenschutz & Sicherheit (Root)
    func openPrivacySettingsRoot() {
        // Best-effort deep link (funktioniert je nach macOS-Version). Fallback: Root öffnen.
        if !openSystemSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            openSystemSettings(urlString: "x-apple.systempreferences:com.apple.preference.security")
        }
    }

    /// Öffnet: Systemeinstellungen → Datenschutz & Sicherheit → Vollzugriff auf Festplatte
    func openFullDiskAccessSettings() {
        if !openSystemSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            openPrivacySettingsRoot()
        }
    }

    /// Öffnet: Systemeinstellungen → Datenschutz & Sicherheit → App-Management
    func openAppManagementSettings() {
        if !openSystemSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppManagement") {
            openPrivacySettingsRoot()
        }
    }

    @discardableResult
    private func openSystemSettings(urlString: String) -> Bool {
        guard let u = URL(string: urlString) else { return false }
        return NSWorkspace.shared.open(u)
    }

    private func openURL(_ s: String) {
        guard let u = URL(string: s) else { return }
        NSWorkspace.shared.open(u)
    }

    // MARK: - Homebrew + mas

    private func brewPath() -> String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }

        let out = runProcessCapture("/bin/zsh", ["-lc", "command -v brew 2>/dev/null || true"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    private func masExists() -> Bool {
        let out = runProcessCapture("/bin/zsh", ["-lc", "command -v mas >/dev/null 2>&1; echo $?"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out == "0"
    }

    private func ensureHomebrewInstalled() async -> String? {
        if let p = brewPath() {
            append("Homebrew vorhanden: \(p)")
            return p
        }

        append("Homebrew nicht gefunden.")
        append("Ich starte die Homebrew-Installation automatisiert in Terminal, weil dort ggf. Passwort/CLT-Dialoge bestätigt werden müssen.")
        append("Die Terminalausgabe wird live in dieses Log gestreamt.")

        let logURL = URL(fileURLWithPath: "/tmp/ausweisapp-homebrew-install.log")
        try? "".write(to: logURL, atomically: true, encoding: .utf8)

        startTailing(logURL)

        // Offizieller Installer: install.sh via curl | bash (läuft in Terminal)
        let terminalCmd = "/bin/bash -lc \"/bin/bash -c \\\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\\" 2>&1 | tee -a \(logURL.path)\""
        openTerminalAndRun(terminalCmd, autoCloseWhenDone: false)

        // Poll, bis brew auftaucht
        for _ in 0..<120 {
            if let p = brewPath() {
                append("Homebrew jetzt verfügbar: \(p)")
                stopTailing()
                return p
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
        }

        append("Homebrew ist noch nicht verfügbar. Prüfe das Terminal-Fenster und schließe die Installation ab.")
        return nil
    }

    private func ensureMasInstalled(brewPath: String) async -> Bool {
        if masExists() {
            append("mas ist vorhanden.")
            return true
        }

        append("mas ist nicht vorhanden. Installiere mas via Homebrew…")
        append("== Homebrew Output (brew install mas) ==")

        let status = await runProcessStreaming(brewPath, ["install", "mas"])
        append("== Homebrew Ende (exit \(status)) ==")

        if status == 0, masExists() {
            append("mas wurde erfolgreich installiert.")
            return true
        }

        append("FEHLER: mas-Installation fehlgeschlagen oder mas weiterhin nicht verfügbar.")
        return false
    }

    // MARK: - Tail Terminal Log

    private func startTailing(_ logURL: URL) {
        stopTailing()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        p.arguments = ["-n", "+1", "-f", logURL.path]

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8), !s.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logText += s
                if !s.hasSuffix("\n") { self.logText += "\n" }
            }
        }

        do {
            try p.run()
            tailProcess = p
        } catch {
            append("tail-Fehler: \(error.localizedDescription)")
        }
    }

    private func stopTailing() {
        tailProcess?.terminate()
        tailProcess = nil
    }

    private func openTerminalAndRun(_ cmd: String, autoCloseWhenDone: Bool = false) {
        // 1) Open a Terminal tab and run the command; return the tab id immediately.
        let scriptOpen = """
        tell application \"Terminal\"
          activate
          if (count of windows) is 0 then
            do script \"\"
          end if
          set theTab to do script \"\(escapeForAppleScript(cmd))\" in front window
          return id of theTab
        end tell
        """

        let out = runProcessCapture("/usr/bin/osascript", ["-e", scriptOpen])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard autoCloseWhenDone else { return }

        // 2) Fire-and-forget watcher that closes the specific tab once it is no longer busy.
        guard let tabId = Int(out), tabId > 0 else { return }

        let scriptClose = """
        tell application \"Terminal\"
          set targetTab to missing value
          repeat with w in windows
            repeat with t in tabs of w
              if (id of t) is \(tabId) then
                set targetTab to t
                exit repeat
              end if
            end repeat
            if targetTab is not missing value then exit repeat
          end repeat

          if targetTab is missing value then return

          repeat while (busy of targetTab)
            delay 0.5
          end repeat

          try
            close targetTab
          end try
        end tell
        """

        runProcessFireAndForget("/usr/bin/osascript", ["-e", scriptClose])
    }

    // MARK: - Process Helpers

    private func runProcessCapture(_ launchPath: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            append("Process-Fehler (\(launchPath)): \(error.localizedDescription)")
            return ""
        }
    }

    private func runProcessFireAndForget(_ launchPath: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args

        // Silence output; this is best-effort.
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        do {
            try p.run()
        } catch {
            append("Process-Fehler (fire-and-forget, \(launchPath)): \(error.localizedDescription)")
        }
    }

    private func runProcessStreaming(_ launchPath: String, _ args: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: launchPath)
            p.arguments = args

            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                let data = h.availableData
                guard !data.isEmpty, let s = String(data: data, encoding: .utf8), !s.isEmpty else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.logText += s
                    if !s.hasSuffix("\n") { self.logText += "\n" }
                }
            }

            p.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: p.terminationStatus)
            }

            do {
                try p.run()
            } catch {
                Task { @MainActor [weak self] in
                    self?.logText += "Process-Fehler (\(launchPath)): \(error.localizedDescription)\n"
                }
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: 127)
            }
        }
    }

    // MARK: - Admin / Quoting

    @discardableResult
    private func runAsAdminShell(_ command: String) -> Bool {
        let res = runAsAdminShellWithOutput(command)
        let trimmed = res.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !res.ok, !trimmed.isEmpty {
            append("Admin-Fehler: \(trimmed)")
        }
        return res.ok
    }

    /// Führt ein Shell-Kommando via osascript mit Administratorrechten aus und gibt Erfolg + Output zurück.
    /// Hinweis: "do shell script" liefert bei Exit != 0 typischerweise einen AppleScript-"execution error".
    private func runAsAdminShellWithOutput(_ command: String) -> (ok: Bool, output: String) {
        // Bring this app to the foreground so the auth dialog is not hidden behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        adminPromptCount += 1
        append("Admin-Abfrage (osascript) #\(adminPromptCount): \(command.prefix(120))\(command.count > 120 ? "…" : "")")

        // macOS may offer Touch ID here (if configured for admin auth), otherwise password.
        let prompt = "Administratorrechte erforderlich (AusweisApp Reset Tool)"
        let script = "do shell script \"\(escapeForAppleScript(command))\" with administrator privileges with prompt \"\(escapeForAppleScript(prompt))\""
        let out = runProcessCapture("/usr/bin/osascript", ["-e", script])
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only treat AppleScript execution errors as failure.
        if trimmed.localizedCaseInsensitiveContains("execution error") {
            return (false, trimmed)
        }

        return (true, trimmed)
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Löscht eine Liste von Pfaden gebündelt in EINEM Admin-Aufruf (ein Prompt).
    /// Gibt false zurück, wenn nach dem Admin-Run noch Pfade existieren (typisch: TCC "Operation not permitted").
    private func runAdminDeleteBatch(_ paths: [String]) -> Bool {
        let fm = FileManager.default
        let unique = Array(Set(paths)).sorted()
        guard !unique.isEmpty else { return true }

        append("Admin-Batch: Lösche \(unique.count) Pfad(e) (ein Prompt)…")

        let list = unique.map { shellQuote($0) }.joined(separator: " ")
        let adminScript =
            "for p in \(list); do " +
            "/usr/bin/chflags -R nouchg,noschg \"$p\" 2>/dev/null || true; " +
            "/bin/chmod -RN \"$p\" 2>/dev/null || true; " +
            "/bin/chmod -R u+rwX,go+rX \"$p\" 2>/dev/null || true; " +
            "/usr/bin/xattr -cr \"$p\" 2>/dev/null || true; " +
            "/bin/rm -rf \"$p\"; " +
            "done"

        let adminCmd = "/bin/zsh -lc \"\(adminScript)\""
        let res = runAsAdminShellWithOutput(adminCmd)

        if !res.ok {
            let trimmed = res.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { append("Admin-Fehler: \(trimmed)") }
            return false
        }

        var remaining: [String] = []
        for p in unique {
            if fm.fileExists(atPath: p) {
                remaining.append(p)
            }
        }

        if remaining.isEmpty {
            for p in unique { append("Gelöscht (Admin-Batch): \(p)") }
            return true
        }

        // Typischer TCC-Block (Admin reicht nicht). Kein Terminal/sudo-Fallback, um weitere Passwortprompts zu vermeiden.
        append("WARNUNG: Einige Pfade konnten trotz Admin nicht gelöscht werden (typisch: TCC / \"Operation not permitted\").")

        let needsFullDiskAccess = remaining.contains { $0.contains("/Library/Containers/") || $0.contains("/Library/Application Support/") || $0.contains("/Library/Preferences/") }
        let needsAppManagement = remaining.contains { $0.hasPrefix("/Applications/") }

        if needsFullDiskAccess {
            append("Erforderlich: Systemeinstellungen → Datenschutz & Sicherheit → Vollzugriff auf Festplatte → dieses Tool aktivieren.")
        }
        if needsAppManagement {
            append("Erforderlich: Systemeinstellungen → Datenschutz & Sicherheit → App-Management → dieses Tool aktivieren.")
        }

        append("Wichtig: Rechte müssen der exportierten/standalone Tool-App erteilt werden (nicht nur dem Xcode-Runner/Debug-Prozess).")
        append("Nicht gelöscht:\n  \(remaining.joined(separator: "\n  "))")

        // Komfort: Systemeinstellungen öffnen (best-effort)
        if needsAppManagement {
            openAppManagementSettings()
        } else if needsFullDiskAccess {
            openFullDiskAccessSettings()
        } else {
            openPrivacySettingsRoot()
        }

        return false
    }

    // MARK: - /Applications Removal (App-Management-aware)

    /// Attempts to move an app bundle in /Applications to Trash.
    /// Preference order:
    /// 1) `FileManager.trashItem` (may trigger the standard macOS authorization prompt)
    /// 2) `NSWorkspace.recycle` as a fallback
    ///
    /// If both fail with permission errors, the most likely root cause is missing macOS
    /// Privacy permission: Datenschutz & Sicherheit → App-Management.
    private func recycleApplicationBundle(_ appURL: URL) async -> Bool {
        append("Verschiebe App in Papierkorb…")

        func isPermissionLike(_ message: String) -> Bool {
            let msg = message.lowercased()
            return msg.contains("permission") ||
                   msg.contains("not permitted") ||
                   msg.contains("operation not permitted") ||
                   msg.contains("keine berecht") ||
                   msg.contains("nicht berechtigt")
        }

        // 1) First try FileManager.trashItem (often behaves closer to Finder semantics)
        do {
            _ = try FileManager.default.trashItem(at: appURL, resultingItemURL: nil)

            if !FileManager.default.fileExists(atPath: appURL.path) {
                append("App nach Papierkorb verschoben: \(appURL.path)")
                return true
            }
        } catch {
            let msg = error.localizedDescription
            append("FEHLER: Entfernen aus /Applications fehlgeschlagen: \(msg)")

            // Wenn es nach fehlenden Rechten aussieht: NICHT noch einmal über NSWorkspace probieren (das führt
            // fast immer zu doppelten Fehlermeldungen), sondern direkt einen Admin-Fallback anbieten.
            if isPermissionLike(msg) {
                append("Ursache sehr wahrscheinlich: macOS Datenschutz (App-Management) und/oder fehlende Admin-Rechte für /Applications.")
                append("Erforderlich: Systemeinstellungen → Datenschutz & Sicherheit → App-Management → dieses Tool aktivieren.")
                if ProcessInfo.processInfo.environment["XCODE_VERSION_ACTUAL"] != nil {
                    append("Hinweis: Du startest vermutlich aus Xcode. Dann in App-Management ggf. auch Xcode aktivieren, sonst wird die Aktion weiterhin blockiert.")
                }
                openAppManagementSettings()

                append("Versuche Entfernen als Admin (ein Prompt)…")

                // Prefer moving to the user’s Trash (so it behaves like Finder). If that fails, fall back to rm -rf.
                if adminMoveAppToUserTrash(appURL) {
                    return true
                }

                append("Admin-Entfernen via Papierkorb fehlgeschlagen; versuche rm -rf (Admin)…")
                return runAdminDeleteBatch([appURL.path])
            }

            // For non-permission errors, continue with NSWorkspace fallback below.
        }

        // 2) Fallback: NSWorkspace.recycle
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle([appURL]) { [weak self] _, error in
                Task { @MainActor [weak self] in
                    guard let self else {
                        continuation.resume(returning: false)
                        return
                    }

                    if let error {
                        let msg = error.localizedDescription
                        self.append("FEHLER: Entfernen aus /Applications fehlgeschlagen: \(msg)")

                        if isPermissionLike(msg) {
                            self.append("Erforderlich: Systemeinstellungen → Datenschutz & Sicherheit → App-Management → dieses Tool aktivieren.")
                            if ProcessInfo.processInfo.environment["XCODE_VERSION_ACTUAL"] != nil {
                                self.append("Hinweis: Du startest vermutlich aus Xcode. Dann in App-Management ggf. auch Xcode aktivieren.")
                            }
                            self.openAppManagementSettings()

                            self.append("Versuche Entfernen als Admin (ein Prompt)…")
                            if self.adminMoveAppToUserTrash(appURL) {
                                continuation.resume(returning: true)
                                return
                            }
                            let ok = self.runAdminDeleteBatch([appURL.path])
                            continuation.resume(returning: ok)
                            return
                        }

                        continuation.resume(returning: false)
                        return
                    }

                    // Best-effort: verify the bundle path is gone
                    if FileManager.default.fileExists(atPath: appURL.path) {
                        self.append("WARNUNG: App existiert weiterhin unter \(appURL.path).")
                        self.append("Erforderlich: Systemeinstellungen → Datenschutz & Sicherheit → App-Management → dieses Tool aktivieren.")
                        if ProcessInfo.processInfo.environment["XCODE_VERSION_ACTUAL"] != nil {
                            self.append("Hinweis: Du startest vermutlich aus Xcode. Dann in App-Management ggf. auch Xcode aktivieren.")
                        }
                        self.openAppManagementSettings()
                        continuation.resume(returning: false)
                        return
                    }

                    self.append("App nach Papierkorb verschoben: \(appURL.path)")
                    continuation.resume(returning: true)
                }
            }
        }
    }

    /// Admin-Fallback: versucht, das App-Bundle in den Papierkorb des aktuellen Users zu verschieben.
    /// (Wenn App-Management fehlt, schlägt auch das als Admin häufig fehl.)
    private func adminMoveAppToUserTrash(_ appURL: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: appURL.path) else { return true }

        let user = NSUserName()
        let trash = "/Users/\(user)/.Trash"
        let ts = Int(Date().timeIntervalSince1970)
        let dest = "\(trash)/\(appURL.lastPathComponent).\(ts)"

        let cmd = "/bin/zsh -lc \"/bin/mkdir -p \(shellQuote(trash)); /bin/mv -f \(shellQuote(appURL.path)) \(shellQuote(dest))\""
        let res = runAsAdminShellWithOutput(cmd)

        if res.ok, !fm.fileExists(atPath: appURL.path) {
            append("App nach Papierkorb verschoben (Admin): \(dest)")
            return true
        }

        // If the move failed, keep a concise log entry (the detailed AppleScript error is already logged by caller paths).
        return false
    }

    // MARK: - Logging

    private func append(_ line: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        logText += "[\(ts)] \(line)\n"
    }
}


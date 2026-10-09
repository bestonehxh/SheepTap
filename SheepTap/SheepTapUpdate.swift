import AppKit

// SheepTap's half of the in-app updater: the ONLY file that ties the generic updater in
// SheepTap/Update/ (copied unchanged from SheepTerm 5.0, 9 Oct 2026) to this app. Releases come
// from the public repository's latest GitHub Release: `SheepTap-<mv>.zip` plus its Ed25519
// `.zip.sig`, both made by the Sheep-family release.sh (/ship) from `.ship.conf`.
//
// SheepTap runs in the App Sandbox, and so does every process it starts. What that means here:
// - Checking (GitHub API), downloading, the Ed25519 check, `ditto -x -k` and
//   `codesign --verify` all work: the network client entitlement is on and everything is
//   done inside the container's temporary folder (UpdaterTests runs ditto + codesign from
//   the sandboxed test host to prove it).
// - Replacing /Applications/SheepTap.app does not: the sandbox denies the write, so
//   `UpdateCore.installTarget` sees /Applications as not writable and returns nil, and the
//   updater moves the VERIFIED zip to ~/Downloads (Downloads read/write entitlement) and
//   reveals it in Finder for the user to install by hand.
// The hooks below only adapt the wording to that, and refuse a self-install outright should
// the writability check ever say yes (the helper would inherit the sandbox and fail after
// the app had already quit).

extension UpdateConfig {
    /// The Ed25519 key whose private half is in the release Mac's login Keychain (service
    /// `signingKeychainService`, account `ed25519`, made once by SheepTerm's Tools/update-keygen.sh
    /// on 9 Oct 2026). `.ship.conf` carries the same value as UPDATE_SIGN_PUBLIC_KEY,
    /// and UpdaterTests fails when the two differ. Not another app's key: one key per app.
    static let sheepTap = UpdateConfig(
        appName: "SheepTap",
        repository: "bestonehxh/SheepTap",
        tagScheme: .semver,
        publicKeyBase64: "OZSntHcrbDJDHwCoZQLdDihAqi5FwtQTerXgcpOiv3I=",
        signingKeychainService: "Bestchaan.SheepTap.update-signing"
    )
}

@MainActor
enum AppUpdater {
    static let shared = Updater(config: .sheepTap, hooks: UpdateHooks(
        confirmBeforeQuit: { SheepTapUpdateSandbox.confirmSelfInstall() },
        presenter: SheepTapUpdatePresenter(sandboxed: SheepTapUpdateSandbox.isSandboxed)
    ))

    /// Called at launch. Not while XCTest drives the app as its test host: an automatic
    /// check would put an alert in front of the tests.
    /// Automatic checks are always on (the user, 9 Oct 2026: no option for it), so a stored
    /// "off" from an earlier build is cleared before the updater reads it.
    static func startUnlessTesting() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        UserDefaults.standard.removeObject(forKey: UpdateCore.autoCheckKey)
        shared.start()
    }
}

@MainActor
enum SheepTapUpdateSandbox {
    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Reached only if `UpdateCore.installTarget` found the bundle writable. Sandboxed, the
    /// install helper could not move the bundle anyway, so say so instead of quitting.
    static func confirmSelfInstall() -> Bool {
        guard isSandboxed else { return true }
        let answer = SheepTapUpdatePresenter(sandboxed: true).present(
            title: "The update was not installed",
            message: "SheepTap runs in the App Sandbox and cannot replace itself. Download it from the release page instead.",
            accessory: nil,
            buttons: [UpdateAlertButton(title: "Open Release Page", role: .primary),
                      UpdateAlertButton(title: "Close")])
        if answer == 0 { NSWorkspace.shared.open(UpdateConfig.sheepTap.releasesPage) }
        return false
    }
}

/// The family's centred update alert (`CenteredUpdatePresenter`, Update/UpdateAlertPanel.swift),
/// with `activatesApp`: SheepTap is a menu-bar (LSUIElement) app, so an alert from an automatic
/// check would otherwise open behind whatever app is active. Sandboxed, the offer's button and
/// the "downloaded" alert say what actually happens (download + reveal, no relaunch); button
/// order and meaning are unchanged.
struct SheepTapUpdatePresenter: UpdateAlertPresenting {
    var sandboxed: Bool
    var centered = CenteredUpdatePresenter(activatesApp: true)

    static let downloadTitle = "Download Update"

    func present(title: String, message: String, accessory: NSView?, buttons: [UpdateAlertButton]) -> Int {
        let (message, buttons) = adapted(title: title, message: message, buttons: buttons)
        return centered.present(title: title, message: message, accessory: accessory, buttons: buttons)
    }

    func adapted(title: String, message: String, buttons: [UpdateAlertButton]) -> (String, [UpdateAlertButton]) {
        guard sandboxed else { return (message, buttons) }
        let buttons = buttons.map { button in
            var button = button
            if button.title == UpdateOfferAction.install.title { button.title = Self.downloadTitle }
            return button
        }
        var message = message
        if title == "Update downloaded", let verified = message.range(of: "The verified ") {
            message = "SheepTap runs in the App Sandbox, so it cannot replace itself in Applications. "
                + message[verified.lowerBound...]
                + " Quit SheepTap before replacing it."
        }
        return (message, buttons)
    }
}

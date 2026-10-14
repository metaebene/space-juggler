# 3DxWare 10.8.13 for macOS: what the installer puts on the Mac

Read from the package on 2026-10-14 (expanded with `pkgutil --expand`, nothing run). For ADR-0004.

## Package

- `Install 3Dconnexion software.pkg` (DMG "3Dconnexion Software"), signed "Developer ID Installer: 3Dconnexion S.A.M.
  (9D93Y2RD6L)", notarized, timestamp 2026-06-09. macOS 12 or later, Intel and Apple silicon, asks for a restart.
- A wrapper: it puts `3DxInstallCheck.app` and the real installer into `/Users/Shared/3DxInstallCheck`; its
  postinstall uninstalls an existing driver extension through the installed helper (`3DconnexionHelper -uninstall`),
  stops running 3Dconnexion processes **and System Settings** (`ps | grep "System Sett" | kill`), then runs the real
  installer with `installer -pkg` and removes the folder. A previous installation in a bad state stops it.
- The real installer: 3DxWare **10.8.13**, revision 3908 (`/Library/Application Support/3Dconnexion/3DxWare/3DxWare.plist`).

## Components

| Part | Where | Version |
|---|---|---|
| `3DconnexionHelper.app` (`com.3dconnexion.driver.helper`, LSUIElement) | `/Applications` (unzipped by the postinstall) | 1.4.4 |
| Driver extension `com.3dconnexion.driver.dext` | inside the helper, `Contents/Library/SystemExtensions` | 1.4.623 |
| `3DconnexionClient.framework` (the classic client API) | `/Library/Frameworks` | 1.4.4.623 |
| `3DconnexionNavlib.framework` | `/Library/Frameworks` | 0.9.1 |
| Preference pane with 3DxRadialMenu, 3DxVirtualNumpad, updater | `/Library/PreferencePanes/3Dconnexion.prefPane` | 1.4.4 |
| 3Dconnexion Home, demos, uninstaller | `/Applications/3Dconnexion`, `/Applications/3DconnexionUninstaller.app` | |
| 3DxNLServer (Navigation Library server for web apps) | `/Applications/3Dconnexion/3DxNLServer` | 1.5.0 |
| Plug-ins (Photoshop, SketchUp, Maya, Cinema 4D, Unreal), 3Dconnexion Pairing, Puzzle, Trainer, Viewer | | |

- **Launch agent** `/Library/LaunchAgents/com.3dconnexion.helper.plist`: `open -W /Applications/3DconnexionHelper.app`,
  `RunAtLoad`, not kept alive: the helper starts at every login, for every user.
- The **driver extension** matches `IOUserResources` only (personality `TDxDriverService`, virtual HID data device
  `TDxVirtualHIDData`; entitlements for virtual HID devices and HID event services). It does not claim the physical
  SpaceMouse: that is read by the helper in user space, which holds it exclusively (stagehand findings, helper 1.4.1).
  So there is one driver with two states, helper running or not; the "DriverKit edition without the helper" of the
  findings (2026-10-06) was this driver with its helper not running.
- 3DxNLServer's postinstall runs `certhelper -i`, which adds its own root certificate to the **System keychain as
  trusted** (`security add-trusted-cert -r trustRoot … /Library/Keychains/System.keychain`) for TLS on 127.51.68.120.
- The last postinstall opens 3Dconnexion's registration page in the browser.

## What it means for Space Juggler

- After a login the helper runs and holds every SpaceMouse: Space Juggler's seize fails with `kIOReturnExclusiveAccess`
  (the driver case of ADR-0004). Not measured: what the helper does when Space Juggler held the device first.
- Helper 1.4.4 is newer than the 1.4.2 that crashed after a manual (`'++++'`) registration from Space Glider's app
  bundle; whether 1.4.4 does so too is the first thing to measure.

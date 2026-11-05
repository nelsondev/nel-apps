# NelApps — Groceries + Reef Log

A single native SwiftUI app with two independently navigable modules, backed by their existing servers.

- Groceries: `https://grocery.home.lab`, interactive Lock Screen Live Activity, grocery Home Screen widget, duplicate-item messaging.
- Reef Log: `https://reef.home.lab`, water tests, trends, maintenance, local notifications, reef Home Screen widget.
- One app target and **one combined WidgetKit extension**. This is intentional to reduce free Apple ID App ID usage.
- Native iPhone/iPad layouts; app launcher keeps both modules separate.

## Build and install

1. Push the **contents** of this ZIP to the root of your GitHub repository.
2. Run **Build NelApps SideStore IPA** in Actions (or let a push to `main` trigger it).
3. Download `NelApps-SideStore-IPA`, extract the IPA from the Actions artifact, and install with SideStore **keeping app extensions enabled**.
4. You must free an installed-app slot by deactivating or removing the standalone Grocery app before installing NelApps. NelApps is a separate bundle identifier; it does not replace the Grocery installation in-place.
5. Start a **new** grocery shopping Live Activity from inside NelApps. Old Grocery activities belong to the old app.

## Notes

The two existing Node.js backends and their data are unchanged. The native app uses the existing APIs. Local notification permissions must be granted for Reef reminders. Widget data is fetched from the servers. App Group entitlements are not configured because free SideStore signing may not support them; cache fallback is process-local.

Source and ZIP integrity checked. **No Xcode compiler or iPhone installation test was possible in this environment.**

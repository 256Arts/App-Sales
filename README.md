# App Sales

<img src="https://www.256arts.com/appsales/icon_appsales.webp" alt="App Sales icon" width="128" align="right">

Your App Store Connect sales, downloads, and proceeds — in an app, on your Home Screen, and on your wrist.

[Download on the App Store](https://apps.apple.com/app/app-sales/id6471903677) · [256arts.com/appsales](https://www.256arts.com/appsales/)

<img src="https://www.256arts.com/appsales/shot1.webp" alt="The medium sales widget twice on an iOS wallpaper" width="300"> <img src="https://www.256arts.com/appsales/shot4.webp" alt="The app's Summary: 30-day proceeds and downloads, their change, and a per-app bar chart" width="300">

## Features

- **Sales at a glance** — 30-day proceeds, downloads, updates, and in-app purchases, compared with the 30 days before, for every app on your account.
- **Per-app pages** — daily charts, downloads by device, ratings and latest reviews, and App Store impressions and page views from the Analytics Reports API.
- **Widgets** — Home Screen, Lock Screen, and desktop widgets, plus Apple Watch complications.
- **Apple Watch** — a standalone watch app; accounts sync over iCloud Keychain.
- **AI usage limits** — Claude and Codex rate limits in the app, a widget, and a Mac menu bar extra.
- **Shortcuts & Siri** — ask for a performance summary, per-app summaries, or AI usage without opening the app.
- iPhone, iPad, Mac, Apple Vision Pro, and Apple Watch.

## App Store Connect API key

Create a key in App Store Connect → Users and Access → Integrations → App Store Connect API, then add its issuer ID, key ID, private key (`.p8`), and your vendor number in the app.

- **Sales and Reports** or **Finance** — enough for sales, downloads, and proceeds.
- **Admin** — needed once per app to turn on analytics reports (impressions, page views). After that, a Sales and Reports key can read them.

Keys are stored in your iCloud Keychain, never on a server.

## Building

Open `App Sales.xcodeproj` in the latest Xcode (beta) and run the `App Sales` scheme. To explore without a key, choose Add Demo Account in the Accounts list. See [`AGENTS.md`](AGENTS.md) for the architecture.

## Credits

App Sales is a fork of AC Widget by NO-COMMENT, now maintained by [256 Arts](https://www.256arts.com). MIT licensed — see [`LICENSE`](LICENSE).

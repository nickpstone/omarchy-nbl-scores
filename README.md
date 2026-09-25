# NBL Scores & Fixtures — Omarchy Shell Plugin

An [Omarchy](https://omarchy.org) Quickshell bar widget and rich flyout panel that tracks the **Australian National Basketball League (NBL)** in real time, powered by ESPN's public API.

## Features

- **Live Bar Widget**:
  - Displays live scores (`🔴 CNS 93 - 87 TAS (Final)` or in-game quarters/clock e.g. `🔴 MEL 78 - 72 SYD (Q3 4:21)`).
  - Shows next upcoming fixture when no game is active (e.g. `🏀 Next: SEM vs MEL (Thu 07:30 PM)`).
  - Pulsing live indicator during active games.
  - Left-click: Open the Match Center panel.
  - Right-click: Force an immediate refresh from ESPN.
  - Middle-click: Open ESPN NBL scoreboard in your browser.

- **Match Center Panel**:
  - **Scores Tab**: Live game box scores with team logos, venues, and completed recent results.
  - **Schedule Tab**: Next 14 days of upcoming fixtures with date, local kickoff times, and venues.
  - **Standings Tab**: Full 10-team NBL ladder with rank (#1–6 highlighted for playoffs), wins, losses, win percentage, point differential, and win/loss streak.
  - Integrated "↻" refresh and "↗" browser scoreboard shortcuts.

- **Omarchy Design System**:
  - Fully theme-reactive: respects active Omarchy theme colors (background, foreground, accent, urgent, fonts).
  - High performance: cached in `~/.local/state/omarchy/nbl/data.json` with zero third-party Python dependencies (uses Python standard library).

## Installation

Install directly with the Omarchy CLI:

```bash
omarchy plugin add https://github.com/nickpstone/omarchy-nbl-scores --enable
```

Or enable and choose your preferred bar section (left, center, right):
```bash
omarchy plugin add https://github.com/nickpstone/omarchy-nbl-scores
omarchy plugin enable omarchy-nbl-scores --section right
```

## Configuration

In `~/.config/omarchy/shell.json`:

```json
{
  "bar": {
    "layout": {
      "center": [
        {
          "id": "omarchy-nbl-scores"
        }
      ]
    }
  }
}
```

## License

[MIT](LICENSE) © 2026 Nick Stone


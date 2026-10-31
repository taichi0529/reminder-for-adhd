# Reminder For ADHD

English | [日本語](README.ja.md)

A macOS menu bar app that shows your calendar events in a large panel across the bottom quarter of the screen when they are due. Built with ADHD in mind: the panel stays until you press "Got it".

It works with any calendar synced to your Mac: Google Calendar, iCloud, Exchange / Microsoft 365, other CalDAV accounts such as Yahoo!, local "On My Mac" calendars, and subscribed calendars.

## Features

- Shows a panel on every display and every Space (including over full-screen apps) when an event is due
  - Choose when to be alerted from the menu: 5 minutes before, 1 minute before, and/or at start time. Multiple choices are allowed. The default is start time only, and the last remaining choice cannot be unchecked
  - "Got it" dismisses only the current alert; later alerts for the same event still appear
  - "Join" dismisses all remaining alerts for that event
  - Buttons: `Join` (when a Meet / Zoom / Teams link is found) / `Got it` / `Remind me in 5 minutes`
  - Never steals keyboard focus
  - Still shows events up to 30 minutes after they start (e.g. after waking from sleep)
  - Skips all-day events, canceled events, and events you have declined
- Warns you, through the menu bar icon and the panel, when audio output is muted or the volume is 0. You can unmute from the panel (the volume is left unchanged)
- Choose which calendars trigger alerts from the menu (grouped by account; all calendars, including newly added ones, start unchecked; the menu bar icon and the menu warn you while none is selected)
  - Turn all of an account's calendars on or off at once
  - Calendars with events today show the count ("今日 N件"), and the submenu title shows how many you have selected, such as "(2/15)"
- Today's events in the menu also show which calendar each one is in
- Clicking the menu bar icon opens a panel. The top shows how long until your next event, in large type. Below it are today's events, anything that would stop alerts from reaching you (muted audio, no calendar selected, no calendar access) with a button to fix it, the alert timing options, the calendar choices, a test panel, and Quit. The app version is shown at the bottom
- When installed in `/Applications`, it registers itself as a login item on first launch

The app's UI is currently in Japanese.

## Setup

1. **Add your calendar account to your Mac**
   In System Settings → Internet Accounts, add your account (Google, iCloud, Exchange, and so on) and turn on "Calendars".
2. **Check which calendars sync to your Mac**
   The app's menu only lists calendars synced to your Mac. For Google, if a shared calendar is missing from the menu, check it in [Google's sync settings](https://calendar.google.com/calendar/syncselect).
3. **Choose the sync interval**
   In Calendar.app → Settings → Accounts → (your account) → "Refresh Calendars". "Every 5 minutes" is recommended.
4. **Build and install** (requires XcodeGen: `brew install xcodegen`)

   ```sh
   make install   # copies a Release build to /Applications/Reminder For ADHD.app and launches it
   ```

   On first launch, the app asks for access to your calendars. After granting access, check the calendars you want alerts for under "通知するカレンダー" (Calendars to alert) in the menu. All calendars start unchecked, so you get no alerts until you pick at least one.

   If registering as a login item fails, check the log:

   ```sh
   log show --predicate 'subsystem == "jp.co.asaichi.reminder"' --last 10m
   ```

### You don't need to use Calendar.app

This app never contacts calendar services such as Google directly; it reads the events macOS syncs in the background. Syncing happens even when Calendar.app is not running, so you don't need to use Calendar.app day to day. Keep adding and editing events wherever you usually do, such as Google Calendar on the web or your phone.

You only need to open Calendar.app to check that your events have synced to your Mac, or to change the sync interval.

## Development

```sh
make generate  # generate Reminder.xcodeproj from project.yml
make build     # Debug build
make run       # launch the Debug build (use "テスト表示" (Test panel) in the menu to preview the panel)
make test      # unit tests
```

The `.xcodeproj` is generated, so it is not checked in.

### Code signing

By default the app is ad-hoc signed (no certificate). With ad-hoc signing, macOS may ask for calendar access again after each rebuild.

To sign with your own certificate, copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` and fill in your certificate and team ID. That file is ignored by git.

## Project structure

| Directory | Role |
|---|---|
| `Reminder/Core` | Alert timing, meeting link detection, and display strings. Depends only on Foundation and is covered by unit tests |
| `Reminder/Calendar` | The event source (`CalendarSource`) and its EventKit implementation |
| `Reminder/Audio` | Watching mute and volume via CoreAudio |
| `Reminder/Overlay` | The alert panel (NSPanel + SwiftUI) |
| `Reminder/App` | Entry point, menu bar, timers, and login item |

### Battery usage

The app never polls. It reloads events only:

- when calendar sync finishes (`EKEventStoreChanged`)
- at the next moment the display can change (an alert time, an event's end, or a snooze ending)
- after waking from sleep, when the date changes, and when the clock or time zone changes
- once every 30 minutes as a fallback in case a change notification is missed (with a generous timer tolerance)

App Nap is disabled only from 2 minutes before an alert until it is shown. Mute status is also re-read only when CoreAudio reports a change.

## License

[MIT License](LICENSE)

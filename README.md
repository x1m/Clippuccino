# Clippuccino

Clipboard history app for macOS 13+ built with Swift + AppKit.

## Build and run

1. Open `/Users/x1m/Development/Clippuccino/Clippuccino/Clippuccino.xcodeproj` in Xcode 15+.
2. Select the `Clippuccino` scheme.
3. Build and run.

## Known limitations

- Text-only clipboard capture (`public.utf8-plain-text` / `NSPasteboard.PasteboardType.string` only).
- Automatic paste requires macOS Accessibility permission for this app.
- Clipboard history is memory-only and is cleared on app restart.

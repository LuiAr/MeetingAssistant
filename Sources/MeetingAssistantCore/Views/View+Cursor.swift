import AppKit
import SwiftUI

extension View {
  /// Shows the macOS pointing-hand cursor while the pointer is over this view, signalling
  /// that it is clickable.
  ///
  /// Backed by an AppKit tracking area (`cursorUpdate`), not `NSCursor` push/pop or SwiftUI's
  /// `pointerStyle`:
  /// - `pointerStyle` leaks window-wide when applied inside NSToolbar-backed items and `List`
  ///   rows (it showed the hand over the transcript).
  /// - `NSCursor` push/pop relies on a matching hover-exit that the same containers drop, so
  ///   the hand got "stuck" and bled onto the transcript dividers.
  ///
  /// A tracking area lets the system own the cursor for the tracked rect and revert it
  /// automatically when the pointer leaves, so neither failure mode applies. The overlay is
  /// non-interactive, so it never intercepts clicks or hover from the control beneath it.
  ///
  /// - Parameter enabled: When `false`, the hand is suppressed so disabled controls keep the
  ///   normal arrow.
  func pointingHandCursor(enabled: Bool = true) -> some View {
    overlay(
      CursorArea(cursor: enabled ? .pointingHand : nil)
        .allowsHitTesting(false)
    )
  }
}

private struct CursorArea: NSViewRepresentable {
  let cursor: NSCursor?

  func makeNSView(context: Context) -> CursorTrackingView {
    CursorTrackingView(cursor: cursor)
  }

  func updateNSView(_ nsView: CursorTrackingView, context: Context) {
    nsView.cursor = cursor
  }
}

/// A transparent AppKit view whose tracking area sets the pointer while the mouse is inside it.
/// `hitTest` returns nil so clicks pass through to the SwiftUI control underneath.
private final class CursorTrackingView: NSView {
  var cursor: NSCursor?

  init(cursor: NSCursor?) {
    self.cursor = cursor
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [.activeInActiveApp, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
        owner: self
      )
    )
  }

  override func cursorUpdate(with event: NSEvent) {
    if let cursor {
      cursor.set()
    } else {
      super.cursorUpdate(with: event)
    }
  }
}

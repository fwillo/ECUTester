import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let screenFrame = NSScreen.main?.visibleFrame ?? self.frame
    let windowSize = NSSize(width: 1280, height: 700)
    let windowOrigin = NSPoint(
      x: screenFrame.midX - windowSize.width / 2,
      y: screenFrame.midY - windowSize.height / 2
    )
    let windowFrame = NSRect(origin: windowOrigin, size: windowSize)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

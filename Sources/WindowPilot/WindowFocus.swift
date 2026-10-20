import ApplicationServices
import CoreGraphics
import Darwin

/// Activates an application with exactly one of its windows in front.
///
/// `NSRunningApplication.activate()` brings the app's main and key windows forward. Electron apps such as
/// VS Code often still report their previous window as main, so with several displays that window is raised
/// as well. The window server can instead activate a process *for a given window*
/// (`_SLPSSetFrontProcessWithOptions` with the user-generated flag, followed by a make-key event record),
/// which is what window switchers use. These are private SkyLight symbols, resolved at runtime; when any is
/// missing `focus` returns false and the caller falls back to the public activation path.
enum WindowFocus {
    private typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError
    private typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    /// kCPSUserGenerated: activate as if the user clicked this window, without raising the app's other windows.
    private static let userGenerated: UInt32 = 0x200

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let processForPID: ProcessForPID? = symbol("GetProcessForPID", in: dlopen(nil, RTLD_LAZY))
    private static let setFrontProcess: SetFrontProcess? = symbol("_SLPSSetFrontProcessWithOptions", in: skyLight)
    private static let postEventRecord: PostEventRecord? = symbol("SLPSPostEventRecordTo", in: skyLight)

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer?) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static var isAvailable: Bool { processForPID != nil && setFrontProcess != nil && postEventRecord != nil }

    static func focus(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let processForPID, let setFrontProcess, let postEventRecord else { return false }
        var psn = ProcessSerialNumber()
        guard processForPID(pid, &psn) == noErr,
              setFrontProcess(&psn, windowID, userGenerated) == .success else { return false }
        // Two synthetic window-server events (press/release on the window's title area) make it the key window.
        for phase: UInt8 in [0x01, 0x02] {
            var record = [UInt8](repeating: 0, count: 0xF8)
            record[0x04] = 0xF8
            record[0x08] = phase
            record[0x3A] = 0x10
            withUnsafeBytes(of: windowID) { bytes in
                for (offset, byte) in bytes.enumerated() { record[0x3C + offset] = byte }
            }
            for offset in 0x20..<0x30 { record[offset] = 0xFF }
            _ = record.withUnsafeMutableBufferPointer { postEventRecord(&psn, $0.baseAddress!) }
        }
        return true
    }

    // MARK: - Accessibility element ↔ window ID

    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    /// `_AXUIElementGetWindow` (HIServices) returns the window-server ID of an Accessibility window element,
    /// which lets us pick exactly the selected window instead of guessing by title and frame.
    private static let getWindow: GetWindow? = symbol("_AXUIElementGetWindow", in: dlopen(nil, RTLD_LAZY))

    static var canResolveWindowIDs: Bool { getWindow != nil }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        return getWindow(element, &id) == .success && id != 0 ? id : nil
    }
}

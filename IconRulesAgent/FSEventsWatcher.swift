import Foundation
import CoreServices

final class FSEventsWatcher {
    typealias Callback = (_ changedPath: URL?) -> Void

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "icons.fsevents.queue")

    func startWatching(path: URL, callback: @escaping Callback) {
        stop()

        let pathsToWatch = [path.path] as CFArray
        let latency: CFTimeInterval = 0.15

        let cbBox = CallbackBox(callback)
        var ctx = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passRetained(cbBox).toOpaque()),
            retain: nil,
            release: { info in
                if let info {
                    Unmanaged<CallbackBox>.fromOpaque(info).release()
                }
            },
            copyDescription: nil
        )

        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        stream = FSEventStreamCreate(
            nil,
            { (_ streamRef, clientCallBackInfo, _ numEvents, eventPathsPointer, _ eventFlags, _ eventIds) in
                guard let clientCallBackInfo else { return }
                let box = Unmanaged<CallbackBox>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

                let eventPaths = unsafeBitCast(eventPathsPointer, to: NSArray.self) as? [String] ?? []
                let last = eventPaths.last.map { URL(fileURLWithPath: $0) }
                box.callback(last)
            },
            &ctx,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )

        guard let stream else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private final class CallbackBox {
        let callback: Callback
        init(_ callback: @escaping Callback) { self.callback = callback }
    }
}

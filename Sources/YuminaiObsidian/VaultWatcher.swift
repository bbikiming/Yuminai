import Foundation
import CoreServices

/// FSEventStream 기반 Vault 변경 감지. debounce 후 변경된 path set을 emit.
///
/// 단일 actor — start/stop을 race 없이 관리. AsyncStream으로 외부에 노출.
public final class VaultWatcher: @unchecked Sendable {
    public let rootURL: URL
    public let debounceInterval: TimeInterval

    public let changes: AsyncStream<Set<String>>
    private let continuation: AsyncStream<Set<String>>.Continuation

    private let queue: DispatchQueue
    private var stream: FSEventStreamRef?
    private var pendingChanges: Set<String> = []
    private var debounceWorkItem: DispatchWorkItem?
    private let lock = NSLock()

    public init(rootURL: URL, debounceInterval: TimeInterval = 0.8) {
        self.rootURL = rootURL
        self.debounceInterval = debounceInterval
        self.queue = DispatchQueue(label: "com.yuminai.vault-watcher", qos: .utility)

        var cont: AsyncStream<Set<String>>.Continuation!
        self.changes = AsyncStream<Set<String>> { c in cont = c }
        self.continuation = cont
    }

    deinit {
        stop()
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard stream == nil else { return }

        let watchedPaths = [rootURL.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: UInt32 = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagUseCFTypes
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, flags, _ in
                guard let info else { return }
                let watcher = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleEvents(count: count, paths: paths, flags: flags)
            },
            &context,
            watchedPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingChanges.removeAll()
    }

    private func handleEvents(count: Int, paths: UnsafeMutableRawPointer, flags: UnsafePointer<FSEventStreamEventFlags>) {
        let pathArray = unsafeBitCast(paths, to: NSArray.self)
        let rootPath = rootURL.standardizedFileURL.path

        var newChanges: Set<String> = []
        for i in 0..<count {
            guard let path = pathArray[i] as? String else { continue }
            // Vault 외부 변경은 무시
            guard path.hasPrefix(rootPath) else { continue }
            // 숨김 폴더 (.obsidian/.trash) 제외
            let relative = String(path.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
            if relative.hasPrefix(".obsidian") || relative.hasPrefix(".trash") { continue }
            newChanges.insert(relative)

            _ = flags[i]  // 향후 flag별 분기 시 사용
        }

        guard !newChanges.isEmpty else { return }

        lock.lock()
        pendingChanges.formUnion(newChanges)
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        debounceWorkItem = work
        lock.unlock()

        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func flush() {
        lock.lock()
        let snapshot = pendingChanges
        pendingChanges.removeAll()
        debounceWorkItem = nil
        lock.unlock()

        guard !snapshot.isEmpty else { return }
        continuation.yield(snapshot)
    }
}

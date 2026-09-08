import Foundation

/// Watches config.json and calls back (debounced) when it changes. Survives atomic replaces by editors.
final class ConfigWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var pending: DispatchWorkItem?
    private let url: URL
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        watch()
    }

    private func watch() {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File missing right now (mid-replace); retry shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.watch() }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            self.schedule()
            if flags.contains(.delete) || flags.contains(.rename) {
                src.cancel()
            }
        }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            close(self.fd)
            self.fd = -1
            self.source = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.watch() }
        }
        source = src
        src.resume()
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}

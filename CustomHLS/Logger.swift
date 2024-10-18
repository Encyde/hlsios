import Foundation

enum LogLevel: Int {
    case verbose
    case debug
    case info
    case error
    case disabled
    
    fileprivate static let level = LogLevel.debug
}

struct SyncLogger {
    static let queue = DispatchQueue(label: UUID().uuidString)
    private let impl: Impl
    
    init(module: String) {
        self.impl = Impl(module: module)
    }
    
    @inline(__always)
    func verbose(tag: String? = nil, _ text: String) {
        log(level: .verbose, tag: tag, text)
    }
    @inline(__always)
    func debug(tag: String? = nil, _ text: String) {
        log(level: .debug, tag: tag, text)
    }
    @inline(__always)
    func info(tag: String? = nil, _ text: String) {
        log(level: .info, tag: tag, text)
    }
    @inline(__always)
    func error(tag: String? = nil, _ text: String) {
        log(level: .error, tag: tag, text)
    }
    @inline(__always)
    func log(level: LogLevel, tag: String? = nil, _ text: String) {
        #if DEBUG
        guard level.rawValue >= LogLevel.level.rawValue else { return }
        Self.queue.async {
            impl.log(level: level, tag: tag, text)
        }
        #endif
    }
    
    private class Impl {
        private let module: String
        private var lastLogTime: DispatchTime?
        
        init(module: String) {
            self.module = module
        }
        
        func log(level: LogLevel, tag: String?, _ text: String) {
            let time = DispatchTime.now()
            let tag = tag.map { "[\(module).\($0)]" } ?? "[\(module)]"
            if let lastLogTime {
                let diff = (time.uptimeNanoseconds - lastLogTime.uptimeNanoseconds) / 1_000_000
                print("\(tag)[diff:\(diff)] \(text)")
            } else {
                print("\(tag)[diff: –] \(text)")
            }
            lastLogTime = time
        }
    }
}

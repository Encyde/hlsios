import AVFoundation

enum PlayState {
    case pause
    case playing
    case buffering
}

class Player {
    private let renderer: BuffersRenderer
    
    private let playerQueue: DispatchQueue
    
    private let hls = HLS()
    private var hlsSession: HLSSession?
    private var hlsInput: HLSSession.Input?
    
    private(set) var playState = PlayState.pause {
        didSet {
            onPlayStateChanged?(playState)
        }
    }
    
    private var displayLink: CADisplayLink?
    
    private let logger = SyncLogger(module: "Player")
    
    var onPlayStateChanged: ((PlayState) -> Void)?
    var onFullTimeUpdate: ((Double) -> Void)?
    var onBufferedTimeUpdate: ((Double) -> Void)?
    var onCurrentTimeUpdate: ((Double) -> Void)?
    
    init(layer: AVSampleBufferDisplayLayer) {
        let playerQueue = DispatchQueue(label: "hls.player")
        self.playerQueue = playerQueue
        self.renderer = BuffersRenderer(playerQueue: playerQueue, sbLayer: layer)
    }
    
    func setup() {
        let link = CADisplayLink(target: self, selector: #selector(displayLinkTrigger))
        self.displayLink = link
        link.add(to: .main, forMode: .default)
        renderer.setup()
    }
    
    func load(masterUrl: URL) {
        playerQueue.async { [weak self] in
            self?.hls.loadSession(masterM3U8Url: masterUrl) { [weak self] session in
                self?.playerQueue.async { [weak self] in
                    guard let self else { return }
                    self.hlsSession = session
                    session.setup(output: createHLSOutput()) { [weak self] input in
                        self?.playerQueue.async { [weak self] in
                            guard let self else { return }
                            self.hlsInput = input
                            session.start()
                        }
                    }
                }
            }
        }
    }
    
    private func createHLSOutput() -> HLSSession.Output {
        HLSSession.Output(
            currentTimestamp: { [weak self] in
                self?.playerQueue.sync { [weak self] in
                    self?.renderer.time.seconds
                }
            },
            onNewFragment: { [weak self] hlsSession, hlsFragment in
                self?.playerQueue.async { [weak self] in
                    self?.handle(session: hlsSession, newFragment: hlsFragment)
                }
            },
            fullDurationUpdated: { [weak self] fullDuration in
                self?.handle(fullDuration: fullDuration)
            }
        )
    }
    
    func play() {
        playerQueue.async { [weak self] in
            self?._play()
        }
    }
    
    private func _play() {
        switch playState {
        case .pause:
            if hlsSession != nil {
                resumePlayback()
            }
        case .playing:
            break
        case .buffering:
            break
        }
    }
    
    func seek(timestamp: Double) {
        playerQueue.async { [weak self] in
            self?._seek(timestamp: timestamp)
        }
    }
    
    private func _seek(timestamp: Double) {
        hlsInput?.seekTimestamp(timestamp)
        renderer.seek(timestamp: timestamp)
        playState = .buffering
    }
    
    func pause() {
        playerQueue.async { [weak self] in
            self?._pause()
        }
    }
    
    private func _pause() {
        playState = .pause
        renderer.pause()
    }
    
    @objc
    private func displayLinkTrigger() {
        playerQueue.async { [weak self, logger] in
            guard self?.playState == .playing else { return }
            logger.verbose(tag: "displayLinkTrigger", "ts: \(self?.renderer.time.seconds.description ?? "-")")
            self?.renderer.displayLinkTrigger()
            self?.onCurrentTimeUpdate?(self?.renderer.time.seconds ?? .zero)
        }
    }
    
    
    private func resumePlayback() {
        self.playState = .playing
        renderer.play()
    }
    
    private func handle(session: HLSSession, newFragment: HLSFragment) {
        onBufferedTimeUpdate?(session.loadingProgress)
        renderer.schedule(hlsFragment: newFragment) { [weak self] in
            self?.playerQueue.async { [weak self] in
                if self?.playState == .buffering {
                    self?.resumePlayback()
                }
            }
        }
    }
    
    private func handle(fullDuration: Double) {
        playerQueue.async { [weak self] in
            guard let self else { return }
            onFullTimeUpdate?(fullDuration)
        }
    }
}

import AVFoundation

//class RenderSync {
//    var rate: Double = 0 {
//        didSet {
//            guard oldValue != rate else { return }
//            updateRenderersRate()
//        }
//    }
//
//    var currentTime: CMTime {
//        CMTimebaseGetTime(audioRenderer.timebase)
//    }
//
//    private let videoRenderer: AVSampleBufferDisplayLayer
//    private let audioRenderer: AVSampleBufferAudioRenderer
//    private let audioSync: AVSampleBufferRenderSynchronizer
//    
//    private var videoTimebase: CMTimebase {
//        videoRenderer.controlTimebase!
//    }
//    private var videoSyncRatio: Double = 1
//    
//    private let logger = SyncLogger(module: "RenderSync")
//
//    init(video: AVSampleBufferDisplayLayer, audio: AVSampleBufferAudioRenderer) {
//        self.videoRenderer = video
//        self.audioRenderer = audio
//        self.audioSync = AVSampleBufferRenderSynchronizer()
//        
//        self.audioSync.addRenderer(audioRenderer)
//        
//        let cmTimebasePointer = UnsafeMutablePointer<CMTimebase?>.allocate(capacity: 1)
//        CMTimebaseCreateWithSourceClock(
//            allocator: kCFAllocatorDefault,
//            sourceClock: CMClockGetHostTimeClock(),
//            timebaseOut: cmTimebasePointer
//        )
//        let timebase = cmTimebasePointer.pointee!
//        
//        video.controlTimebase = timebase
//        CMTimebaseSetRate(timebase, rate: 0)
//    }
//    
//    func seek(time: CMTime) {
//        CMTimebaseSetRate(videoTimebase, rate: 0)
//        audioSync.setRate(0, time: time)
//        CMTimebaseSetTime(videoTimebase, time: time)
//    }
//    
//    private struct SyncTimestamp {
//        let video: CMTime
//        let audio: CMTime
//    }
//    private var timestamps = RingBuffer<SyncTimestamp>(capacity: 100)
//    func addFragment(newFragment: HLSFragment) {
//        let timestamp = SyncTimestamp(video: newFragment.videoDuration, audio: newFragment.audioDuration)
//        timestamps.enqueue(timestamp)
//    }
//    
//    func updateRatio() {
////        let now = currentTime
////        if let timestamp = timestamps.peek(), CMTimeCompare(now, timestamp.audio) >= 0 {
////            _ = timestamps.dequeue()
////            let diff = CMTimeSubtract(now, timestamp.audio)
////            CMTimebaseSetTime(videoTimebase, time: CMTimeAdd(timestamp.video, diff))
////        }
////        logger.debug(tag: "updateRatio", "vt: \(CMTimebaseGetTime(videoTimebase).seconds) at: \(currentTime.seconds)")
//    }
//
//    private func updateRenderersRate() {
//        CMTimebaseSetRate(videoTimebase, rate: rate * videoSyncRatio)
//        audioSync.rate = Float(rate)
//    }
//}

class BuffersRenderer {
    private let sbLayer: AVSampleBufferDisplayLayer
    private let audio: AVSampleBufferAudioRenderer
    private let sync: AVSampleBufferRenderSynchronizer
    
    private let playerQueue: DispatchQueue
    private var isRunning = false
    
    private var enqueueInProgress = false
    private let bufferingQueue = DispatchQueue(label: "hls.renderer.bufferingQueue")
//    private var videoBuffers = AccumulatingBuffer(capacity: 2000, processedCapacity: 200)
//    private var audioBuffers = AccumulatingBuffer(capacity: 500, processedCapacity: 50)
    private var videoBuffers = RingBuffer<CMSampleBuffer>(capacity: 2000)
//    private var videoProcessingBuffers = RingBuffer<CMSampleBuffer>(capacity: 100)
    private var audioBuffers = RingBuffer<CMSampleBuffer>(capacity: 500)
//    private var audioProcessingBuffers = RingBuffer<CMSampleBuffer>(capacity: 100)
    private var lastScheduledVideoTimeEnd: CMTime?
    private var lastScheduledAudioTimeEnd: CMTime?
    
    private let logger = SyncLogger(module: "BufferLayer")
    
    init(
        playerQueue: DispatchQueue,
        sbLayer: AVSampleBufferDisplayLayer
    ) {
        self.playerQueue = playerQueue
        self.sbLayer = sbLayer
        self.audio = AVSampleBufferAudioRenderer()
        self.sync = AVSampleBufferRenderSynchronizer()
        sync.addRenderer(sbLayer)
        sync.addRenderer(audio)
    }
    
    var time: CMTime {
        sync.currentTime()
    }
    
    func setup() {}
    
    func schedule(hlsFragment: HLSFragment, completion: @escaping () -> Void) {
        func schedule(buffers: [CMSampleBuffer], queue: inout RingBuffer<CMSampleBuffer>, basetime: CMTime) -> CMTime {
            var lastConsumed: CMSampleBuffer?
            for buffer in buffers {
//                let adjusted = buffer.adjustTiming(baseTime: basetime) ?? buffer
                let adjusted = buffer
                queue.enqueue(adjusted)
                if adjusted.time.duration != .zero {
                    lastConsumed = adjusted
                }
            }
            return (lastConsumed?.time ?? buffers[buffers.count - 1].time).end
        }
        
        bufferingQueue.async { [weak self] in
            guard let self else { return }
            logger.info("scheduling frag: \(hlsFragment.fragment.byteRange.length)@\(hlsFragment.fragment.byteRange.start)")
            lastScheduledVideoTimeEnd = schedule(buffers: hlsFragment.videoBuffers, queue: &videoBuffers, basetime: lastScheduledVideoTimeEnd ?? .zero)
            lastScheduledAudioTimeEnd = schedule(buffers: hlsFragment.audioBuffers, queue: &audioBuffers, basetime: lastScheduledAudioTimeEnd ?? .zero)
//            sync.addFragment(newFragment: hlsFragment)
            completion()
        }
    }
    
    func play() {
        guard !isRunning else { return }
        self.isRunning = true
        sync.rate = 1
    }
    
    func pause() {
        guard isRunning else { return }
        self.isRunning = false
        sync.rate = 0
    }
    
    func seek(timestamp: Double) {
        isRunning = false
        let time = CMTime(seconds: timestamp, preferredTimescale: .max)
        sync.setRate(0, time: time)
        self.sbLayer.flush()
        self.audio.flush()
        bufferingQueue.async { [weak self] in
            // TODO: It's an error
            self?.lastScheduledVideoTimeEnd = time
            self?.lastScheduledAudioTimeEnd = time
            self?.videoBuffers.flush()
            self?.audioBuffers.flush()
        }
    }
    
    func displayLinkTrigger() {
        bufferingQueue.async { [weak self] in
            guard let self, isRunning, !enqueueInProgress else { return }
            enqueueInProgress = true
            while sbLayer.isReadyForMoreMediaData, let buffer = videoBuffers.dequeue() {
                sbLayer.enqueue(buffer)
            }
            while audio.isReadyForMoreMediaData, let buffer = audioBuffers.dequeue() {
                audio.enqueue(buffer)
            }
//            sync.updateRatio()
            enqueueInProgress = false
        }
    }
}

struct AccumulatingBuffer {
    private var buffers: RingBuffer<CMSampleBuffer>
    private var processedBuffers: RingBuffer<CMSampleBuffer>
    
    private(set) var unprocessedDuration: CMTime = .zero
    
    init(capacity: Int, processedCapacity: Int) {
        self.buffers = RingBuffer<CMSampleBuffer>(capacity: capacity)
        self.processedBuffers = RingBuffer<CMSampleBuffer>(capacity: processedCapacity)
    }
    
    mutating func enqueue(_ buffer: CMSampleBuffer) {
        buffers.enqueue(buffer)
        unprocessedDuration = CMTimeAdd(unprocessedDuration, buffer.time.duration)
    }
    
    mutating func dequeue() -> CMSampleBuffer? {
        guard let buffer = buffers.dequeue() else { return nil }
        processedBuffers.enqueue(buffer)
        return buffer
    }
    
    mutating func updateDuration(timestamp: CMTime) {
        while let nextProcessedBuffer = processedBuffers.peek(), CMTimeCompare(nextProcessedBuffer.time.end, timestamp) >= 0 {
            _ = processedBuffers.dequeue()
            unprocessedDuration = CMTimeSubtract(unprocessedDuration, nextProcessedBuffer.time.duration)
        }
    }
    
    mutating func flush() {
        buffers.flush()
        processedBuffers.flush()
        unprocessedDuration = .zero
    }
}

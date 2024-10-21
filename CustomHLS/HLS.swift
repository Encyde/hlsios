import Foundation
import AVFoundation

final class ABR {
    let queue: DispatchQueue
    let bufferingDuration: Double = 30
    let normalBitrateMargin: Double = 1.3
    let urgentBitrateMargin: Double = 2
    
    private(set) var currentBitrateEstimate: Int = 0 // 8000000
    private var bitrateSamples: [Int] = [0]
    
    private let logger = SyncLogger(module: "ABR")
    
    init(queue: DispatchQueue) {
        self.queue = queue
    }
    
    func loaded(fragment: HLSFragment, duration: Double) {
        let rate = Int(Double(fragment.fragment.byteRange.length * 8) / duration)
        bitrateSamples.append(rate)
        if bitrateSamples.count > 10 {
            bitrateSamples.removeFirst()
        }
        currentBitrateEstimate = bitrateSamples.reduce(0, +) / bitrateSamples.count
        logger.info(tag: "changeEstimation", "rate: \(currentBitrateEstimate)")
    }
    
    func choose(playlists: [M3U8Playlist], urgent: Bool = true) -> M3U8Playlist {
        let playlistsSorted = playlists.sorted(by: { $0.bandwidth > $1.bandwidth })
        var playlist = playlistsSorted[playlistsSorted.count - 1]
        for i in 0..<playlistsSorted.count {
            let bitrateRatio = Double(currentBitrateEstimate) / (Double(playlistsSorted[i].bandwidth) * (urgent ? urgentBitrateMargin : normalBitrateMargin))
            if bitrateRatio > 1 {
                playlist = playlistsSorted[i]
                break
            }
        }
        return playlist
    }
    
    func needsToLoad(playlist: M3U8Playlist, currentTimestamp: Double, bufferedTimestamp: Double) -> Bool {
        let estTimeToLoad = Double(playlist.bandwidth * playlist.targetDuration * 8) / Double(currentBitrateEstimate)
        let timeLeftBuffered = bufferedTimestamp - currentTimestamp - estTimeToLoad
        return timeLeftBuffered < bufferingDuration
    }
}

struct HLSFragment {
    let fragment: M3U8Playlist.Fragment
    
    let videoBuffers: [CMSampleBuffer]
    let audioBuffers: [CMSampleBuffer]
    
    let videoDuration: CMTime
    let audioDuration: CMTime
    let assetDuration: CMTime
    
    init(
        fragment: M3U8Playlist.Fragment,
        videoBuffers: [CMSampleBuffer],
        audioBuffers: [CMSampleBuffer],
        videoDuration: CMTime,
        audioDuration: CMTime,
        assetDuration: CMTime
    ) {
        self.fragment = fragment
        self.videoBuffers = videoBuffers
        self.audioBuffers = audioBuffers
        self.videoDuration = videoDuration
        self.audioDuration = audioDuration
        self.assetDuration = assetDuration
    }
}

final class HLSPlaylistLoader {
    let playlist: M3U8Playlist
    let queue: DispatchQueue
    
    private let decodingQueue = DispatchQueue(label: "hls.decode")
    private let logger = SyncLogger(module: "HLSPlaylistLoader")
    
    private var initSegmentData: Data?
    private var previousReadAsset: AVURLAsset?
    
    init(playlist: M3U8Playlist, queue: DispatchQueue) {
        self.playlist = playlist
        self.queue = queue
    }
    
    func load(fragmentIndex: Int, basetime: CMTime, completion: @escaping (HLSFragment) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let fragment = playlist.fragments[fragmentIndex]
            if let initSegmentData {
                load(playlistId: playlist.id, initSegment: initSegmentData, basetime: basetime, fragment: fragment, completion: completion)
            } else {
                loadSegment(url: playlist.map.url, start: playlist.map.byteRange.start, length: playlist.map.byteRange.length) { [weak self] data in
                    self?.queue.async { [weak self] in
                        guard let self else { return }
                        initSegmentData = data
                        load(playlistId: playlist.id, initSegment: data, basetime: basetime, fragment: fragment, completion: completion)
                    }
                }
            }
        }
    }
    
    func flush() {
        self.previousReadAsset = nil
    }
    
    private func load(playlistId: Int, initSegment: Data, basetime: CMTime, fragment: M3U8Playlist.Fragment, completion: @escaping (HLSFragment) -> Void) {
        loadSegment(url: fragment.url, start: fragment.byteRange.start, length: fragment.byteRange.length) { [weak self] data in
            self?.decodingQueue.async { [weak self] in
                guard let self else { return }
                self.read(fragment: fragment, initSegmentData: initSegment, fragmentData: data, basetime: basetime, completion: completion)
            }
        }
    }
    
    var nextAudioStartTime: CMTime = .zero
    var nextVideoStartTime: CMTime = .zero

    private func read(
        fragment: M3U8Playlist.Fragment,
        initSegmentData: Data,
        fragmentData: Data,
        basetime: CMTime,
        completion: @escaping (HLSFragment) -> Void
    ) {
        let fullData = initSegmentData + fragmentData
        
        let tmpDir = FileManager.default.temporaryDirectory
        let filename = "frag-\(playlist.id)-\(fragment.hashValue).mp4"
        let fileUrl = tmpDir.appendingPathComponent(filename)
        try! fullData.write(to: fileUrl)
        
        var audioBuffers = [CMSampleBuffer]()
        var videoBuffers = [CMSampleBuffer]()
        var avAudioDuration: CMTime = .zero
        var avVideoDuration: CMTime = .zero
        
        let asset = AVURLAsset(url: fileUrl)
        
        let reader = try! AVAssetReader(asset: asset)
        
        let audioTrack = asset.tracks(withMediaType: .audio)[0]
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        reader.add(audioOutput)
        
        let videoTrack = asset.tracks(withMediaType: .video)[0]
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        reader.add(videoOutput)
        reader.startReading()
        
        let audioOrigin = nextAudioStartTime

        while let buffer = audioOutput.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(buffer) == 0 {
                continue
            }

            let adjustedBuffer = buffer.adjustTiming(baseTime: audioOrigin)!
            // only need to apply for the first sample buffer of every subsequent file

            if audioOrigin != .zero
            {
                // trimming from non-initial fragments causes an audio dropout
                CMRemoveAttachment(adjustedBuffer, key: kCMSampleBufferAttachmentKey_TrimDurationAtStart)
            }

            audioBuffers.append(adjustedBuffer)

            avAudioDuration = CMTimeAdd(avAudioDuration, buffer.time.duration)

            nextAudioStartTime = CMTimeAdd(nextAudioStartTime, CMSampleBufferGetDuration(buffer))
        }

        let videoOrigin = nextVideoStartTime
        
        while let buffer = videoOutput.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(buffer) == 0 {
                continue // edit boundary, drain after decoding, EmptyMedia, PermanentEmptyMedia
            }

            let adjustedBuffer = buffer.adjustTiming(baseTime: videoOrigin)!
                videoBuffers.append(adjustedBuffer)

            if videoOrigin != .zero {
                // This doesn't seem to matter as initial change is likely an i-frame
                // but the non segmented file doesn't have it, so rip it out
                CMRemoveAttachment(adjustedBuffer, key: kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding)
            }

            avVideoDuration = CMTimeAdd(avVideoDuration, buffer.time.duration)

            nextVideoStartTime = CMTimeAdd(nextVideoStartTime, CMSampleBufferGetDuration(buffer))
        }

        let loadedFragment = HLSFragment(
            fragment: fragment,
            videoBuffers: videoBuffers,
            audioBuffers: audioBuffers ,
            videoDuration: avVideoDuration,
            audioDuration: avAudioDuration,
            assetDuration: asset.duration
        )
        
        if let previousReadAsset {
            try! FileManager.default.removeItem(at: previousReadAsset.url)
        }
        self.previousReadAsset = asset
        logger.debug(tag: "readEnd", "r: \(playlist.resolution), ad: \(avAudioDuration.seconds), vd: \(avVideoDuration.seconds)")
        
        queue.async {
            completion(loadedFragment)
        }
    }
}

final class HLSSession {
    struct Input {
        let seekTimestamp: (Double) -> Void
    }
    
    struct Output {
        let currentTimestamp: () -> Double?
        
        let onNewFragment: (HLSSession, HLSFragment) -> Void
        let fullDurationUpdated: (Double) -> Void
    }
    
    struct Fragment {
        let index: Int
        let playlists: [M3U8Playlist]
        let timestamp: CMTime
        
        var duration: Double {
            playlists[0].fragments[index].duration
        }
        
        var fragments: [M3U8Playlist.Fragment] {
            playlists.map { $0.fragments[index] }
        }
        
        init(index: Int, playlists: [M3U8Playlist], timestamp: CMTime) {
            self.index = index
            self.playlists = playlists
            self.timestamp = timestamp
        }
    }
    
    let url: URL
    let master: M3U8MasterPlaylist
    
    private(set) var currentFragmentIndex: Int
    private(set) var isStarted: Bool = false
    private(set) var loadingProgress: Double = 0
    
    private let loaders: [Int: HLSPlaylistLoader]
    private let fragments: [Fragment]
    private let abr: ABR
    
    private let queue: DispatchQueue
    private var skipSheduled = false
    private var bufferingId = UUID()
    private var loadUnurgent = 0
    
    private var output: Output?
    
    private var timer: Timer?
    
    private let logger = SyncLogger(module: "HLSSession")
    
    init(
        url: URL,
        master: M3U8MasterPlaylist,
        mediaPlaylists: [M3U8Playlist],
        queue: DispatchQueue
    ) {
        self.url = url
        self.master = master
        self.currentFragmentIndex = 0
        self.queue = queue
        
        var loaders = [Int: HLSPlaylistLoader]()
        mediaPlaylists.forEach {
            loaders[$0.id] = HLSPlaylistLoader(playlist: $0, queue: queue)
        }
        self.loaders = loaders
        
        var timestamp = CMTime.zero
        self.fragments = (0..<(mediaPlaylists[0].fragments.count)).map { i in
            let duration = CMTime(seconds: mediaPlaylists[0].fragments[i].duration, preferredTimescale: 10000)
            let fragTimestamp = timestamp
            timestamp = CMTimeAdd(timestamp, duration)
            return Fragment(index: i, playlists: mediaPlaylists, timestamp: fragTimestamp)
        }
        self.abr = ABR(queue: queue)
    }
    
    deinit {
        timer?.invalidate()
    }
    
    func setup(output: Output, completion: @escaping (Input?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !isStarted else {
                assertionFailure()
                return
            }
            
            let input = Input(
                seekTimestamp: { [weak self] timetsamp in
                    self?.queue.async { [weak self] in
                        self?.seek(timestamp: timetsamp)
                    }
                }
            )
            
            self.output = output
            completion(input)
        }
    }
    
    func start() {
        queue.async { [weak self, logger] in
            logger.info(tag: "start", "will try start session")
            guard let self, !isStarted else { return }
            self.isStarted = true
            self.loadUnurgent = 3
            let timer = Timer(timeInterval: 0.1, repeats: true, block: { [weak self] _ in
                self?.queue.async { [weak self] in
                    self?.scheduledRun()
                }
            })
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            logger.info(tag: "start", "session started")
            
            let fullDuration = fragments.map { $0.duration }.reduce(0, +)
            output?.fullDurationUpdated(fullDuration)
        }
    }
    
    private func seek(timestamp: Double) {
        var accDuration = 0.0
        var fragmentIndex = fragments.count - 1
        for i in 0..<fragments.count {
            if accDuration + fragments[i].duration > timestamp {
                fragmentIndex = i
                break
            } else {
                accDuration += fragments[i].duration
            }
        }
        bufferingId = UUID()
        currentFragmentIndex = fragmentIndex
        loadingProgress = timestamp
        loadUnurgent = 3
        loaders.values.forEach {
            $0.flush()
        }
        logger.info(tag: "seek", "\(bufferingId), i: \(fragmentIndex) lp: \(loadingProgress)")
        run()
    }
    
    private func scheduledRun() {
        guard isStarted else {
            logger.verbose(tag: "scheduledRun", "will not shedule run - not started")
            return
        }
        
        guard currentFragmentIndex < fragments.count else {
            logger.verbose(tag: "scheduledRun", "will not shedule run - end of playlist")
            return
        }
        
        guard !skipSheduled else {
            logger.verbose(tag: "scheduledRun", "will not shedule run - locked for schedule")
            return
        }
        
        run()
    }
    
    private func run() {
        guard let playerTimestamp = output?.currentTimestamp() else { return }
        
        let playlist = abr.choose(playlists: fragments[currentFragmentIndex].playlists, urgent: loadUnurgent == 0)
        guard abr.needsToLoad(playlist: playlist, currentTimestamp: playerTimestamp, bufferedTimestamp: loadingProgress) else { return }
        if loadUnurgent > 0 {
            loadUnurgent -= 1
        }
        
        skipSheduled = true
        let bufferingId = bufferingId
        let loadingStart = DispatchTime.now()
//        let basetime = CMTime(seconds: loadingProgress, preferredTimescale: 1000)
        let basetime = fragments[currentFragmentIndex].timestamp
        logger.info(tag: "run", "decided to load next fragment \(currentFragmentIndex), estBitrate: \(abr.currentBitrateEstimate), bt: \(basetime.seconds), pr: \(loadingProgress)")
        loaders[playlist.id]?.load(fragmentIndex: currentFragmentIndex, basetime: basetime, completion: { [weak self, logger] hlsFragment in
            guard let self, self.bufferingId == bufferingId else { return }
            logger.info(tag: "run", "loaded next fragment - br: \(hlsFragment.fragment.byteRange), vd: \(hlsFragment.videoDuration.seconds), ad: \(hlsFragment.audioDuration.seconds)")
            loadingProgress += hlsFragment.fragment.duration
            currentFragmentIndex += 1
            self.output?.onNewFragment(self, hlsFragment)
            self.skipSheduled = false
            let loadingFinish = DispatchTime.now()
            let loadingTimeSec = Double(loadingFinish.uptimeNanoseconds - loadingStart.uptimeNanoseconds) / 1_000_000_000
            abr.loaded(fragment: hlsFragment, duration: loadingTimeSec)
        })
    }
}

final class HLS: NSObject {
    static let queue = DispatchQueue(label: "hls.base")
    var queue: DispatchQueue {
        Self.queue
    }
    
    func loadSession(masterM3U8Url: URL, completion: @escaping (HLSSession) -> Void) {
        loadM3U8(url: masterM3U8Url) { [queue] result in
            guard case let .success(masterData) = result else {
                return
            }
            
            let masterPlaylist = M3U8MasterPlaylist(data: masterData, baseUrl: masterM3U8Url)!
            queue.async {
                var array = [M3U8Playlist]()
                let group = DispatchGroup()
                masterPlaylist.variants.forEach { variant in
                    group.enter()
                    loadM3U8(url: variant.url) { mediaResult in
                        guard 
                            case let .success(mediaData) = mediaResult,
                            let mediaPlaylist = M3U8Playlist(masterVariant: variant, data: mediaData, baseUrl: variant.url)
                        else {
                            group.leave()
                            return
                        }
                        
                        queue.async {
                            array.append(mediaPlaylist)
                            group.leave()
                        }
                    }
                }
                
                group.notify(queue: queue) {
                    let session = HLSSession(url: masterM3U8Url, master: masterPlaylist, mediaPlaylists: array, queue: queue)
                    completion(session)
                }
            }
        }
    }
}

private func loadM3U8(url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
    let request = URLRequest(url: url)
    URLSession(configuration: .ephemeral).dataTask(with: request) { data, _, error in
        if let data {
            completion(.success(data))
        } else if let error {
            completion(.failure(error))
        } else {
            assertionFailure()
        }
    }.resume()
}

private func loadSegment(url: URL, start: Int, length: Int, completion: @escaping (Data) -> Void) {
    var request = URLRequest(url: url)
    request.setValue("bytes=\(start)-\(start+length-1)", forHTTPHeaderField: "Range")
    URLSession(configuration: .ephemeral).dataTask(with: request) { data, _, _ in
        guard let data = data else { return }
        completion(data)
    }.resume()
}

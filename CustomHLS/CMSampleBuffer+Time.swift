import AVFoundation

struct SampleBufferTimeInfo {
    let start: CMTime
    let duration: CMTime
    
    var end: CMTime {
        CMTimeAdd(start, duration)
    }
}

extension CMSampleBuffer {
    var time: SampleBufferTimeInfo {
        SampleBufferTimeInfo(
            start: CMSampleBufferGetPresentationTimeStamp(self),
            duration: CMSampleBufferGetDuration(self)
        )
    }
    
    var isKey: Bool {
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[CFString: Any]],
           let attachment = attachments.first {
            let isKeyFrame = !(attachment[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
            return isKeyFrame
        }
        
        return true
    }
    
//    func adjustBasetimeToZero() -> CMSampleBuffer? {
//        guard !time.start.seconds.isNaN else {
//            return self
//        }
//        
//        var timingInfo = CMSampleTimingInfo()
//        
//        guard CMSampleBufferGetSampleTimingInfo(self, at: .zero, timingInfoOut: &timingInfo) == noErr else {
//            return nil
//        }
//        
//        timingInfo.presentationTimeStamp = .zero
//
//        var newSampleBuffer: CMSampleBuffer?
//        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
//                                              sampleBuffer: self,
//                                              sampleTimingEntryCount: 1,
//                                              sampleTimingArray: &timingInfo,
//                                              sampleBufferOut: &newSampleBuffer)
//
//        return newSampleBuffer
//    }
    
    func adjustTiming(baseTime: CMTime? = nil) -> CMSampleBuffer? {
        var timingInfo = CMSampleTimingInfo()
        
        guard CMSampleBufferGetSampleTimingInfo(self, at: .zero, timingInfoOut: &timingInfo) == noErr else {
            return nil
        }
        
        if let baseTime {
            timingInfo.presentationTimeStamp = CMTimeAdd(timingInfo.presentationTimeStamp, baseTime)
            // don't really seem to need DTS, but let's try to appear more like non segmented file
            timingInfo.decodeTimeStamp = CMTimeAdd(timingInfo.decodeTimeStamp, baseTime)
        }

        var newSampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                              sampleBuffer: self,
                                              sampleTimingEntryCount: 1,
                                              sampleTimingArray: &timingInfo,
                                              sampleBufferOut: &newSampleBuffer)

        return newSampleBuffer
    }
}

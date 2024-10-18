import UIKit

class ProgressView: UIView {
    
    var onSeekToTimestamp: ((Double) -> Void)?
    
    private var fullDuration: TimeInterval = 0
    private var currentTime: TimeInterval = 0
    private var bufferedTime: TimeInterval = 0
    
    // Progress layers
    private let progressLayer = CALayer()
    private let bufferedLayer = CALayer()
    private let currentIndicator = UIView()
    
    // Pan gesture recognizer
    private var panGesture: UIPanGestureRecognizer!
    private var druggingIndicator = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
        setupPanGesture()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        setupPanGesture()
    }
    
    // Setup visual elements for the progress bar
    private func setupLayers() {
        self.layer.addSublayer(bufferedLayer)
        self.layer.addSublayer(progressLayer)
        backgroundColor = UIColor.gray
        layer.cornerRadius = 5
        layer.masksToBounds = true
        bufferedLayer.backgroundColor = UIColor.lightGray.cgColor
        progressLayer.backgroundColor = UIColor.blue.cgColor
        
        // Setup the draggable current time indicator
        currentIndicator.backgroundColor = UIColor.red
        currentIndicator.layer.cornerRadius = 5
        currentIndicator.frame = CGRect(x: 0, y: -5, width: 10, height: self.bounds.height + 10)
        self.addSubview(currentIndicator)
    }
    
    // Setup pan gesture recognizer
    private func setupPanGesture() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        currentIndicator.addGestureRecognizer(panGesture)
        currentIndicator.isUserInteractionEnabled = true
    }
    
    // Setup full duration for the progress bar
    func setFullDuration(_ duration: TimeInterval) {
        fullDuration = duration
        updateLayers()
    }
    
    // Update the current progress on the progress bar
    func setCurrentTime(_ time: TimeInterval) {
        currentTime = min(max(time, 0), fullDuration) // Ensure time stays within range
        updateLayers()
    }
    
    // Update buffered time (shows data ready to be played)
    func setBufferedTime(_ time: TimeInterval) {
        bufferedTime = min(time, fullDuration) // Ensure buffered time doesn't exceed full duration
        updateLayers()
    }
    
    // Updates the visual layers based on current time, buffered time, and full duration
    private func updateLayers() {
        let width = self.bounds.width
        let progressWidth = CGFloat(currentTime / fullDuration) * width
        let bufferedWidth = CGFloat(bufferedTime / fullDuration) * width
        
        // Update progress and buffer layers width
        progressLayer.frame = CGRect(x: 0, y: 0, width: progressWidth, height: self.bounds.height)
        bufferedLayer.frame = CGRect(x: 0, y: 0, width: bufferedWidth, height: self.bounds.height)
        
        // Update position of the indicator
        if !druggingIndicator {
            currentIndicator.center = CGPoint(x: progressLayer.frame.maxX, y: self.bounds.midY)
        }
    }
    
    // Handle pan gesture to allow users to scrub through the progress bar
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        let totalWidth = self.bounds.width
        
        // Update the current time based on horizontal drag
        let newX = min(totalWidth, max(0, location.x))
        let newTime = (newX / totalWidth) * fullDuration
        
        gesture.setTranslation(.zero, in: self)
        
        switch gesture.state {
        case .began:
            druggingIndicator = true
        case .changed:
            break
        case .ended:
            druggingIndicator = false
            onSeekToTimestamp?(newTime)
        case .cancelled:
            druggingIndicator = false
        case .failed:
            druggingIndicator = false
        default:
            break
        }
        
        currentIndicator.center = CGPoint(x: newX, y: self.bounds.midY)
    }
}

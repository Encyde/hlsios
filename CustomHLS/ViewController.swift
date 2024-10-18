//
//  ViewController.swift
//  CustomHLS
//
//  Created by Maxim Bezdenezhnykh on 04/10/2024.
//

import UIKit
import AVKit
import AVFoundation

class ViewController: UIViewController {
    private var startButton: UIButton!
    
    private lazy var layer = AVSampleBufferDisplayLayer()
    
    private lazy var player = Player(layer: layer)
    private lazy var progressBar = ProgressView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
//        let session = AVAudioSession.sharedInstance()
//        try! session.setCategory(AVAudioSession.Category.playback, mode: AVAudioSession.Mode.default)
//        try! session.setActive(true)
        
        view.backgroundColor = .white
        
        let screen = UIScreen.main.bounds
        layer.frame = .init(
            x: 0,
            y: 200,
            width: screen.width,
            height: screen.width / 16 * 9
        )
        view.layer.addSublayer(layer)
        
        view.addSubview(progressBar)
        progressBar.frame = .init(x: 32, y: screen.height / 2, width: screen.width - 64, height: 10)
        
        startButton = UIButton()
        startButton.setTitle("Play", for: .normal)
        startButton.setTitleColor(.blue, for: .normal)
        view.addSubview(startButton)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            startButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -150),
            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        startButton.addTarget(self, action: #selector(play), for: .touchUpInside)
        
        player.setup()
        player.load(masterUrl: Const.m3u8MasterPlaylistSync)
        
        player.onFullTimeUpdate = { [weak self] time in
            DispatchQueue.main.async {
                self?.progressBar.setFullDuration(time)
            }
        }
        
        player.onCurrentTimeUpdate = { [weak self] time in
            DispatchQueue.main.async {
                self?.progressBar.setCurrentTime(time)
            }
        }
        
        player.onBufferedTimeUpdate = { [weak self] time in
            DispatchQueue.main.async {
                self?.progressBar.setBufferedTime(time)
            }
        }
        
        player.onPlayStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                if state == .pause {
                    self?.startButton.setTitle("Play", for: .normal)
                } else {
                    self?.startButton.setTitle("Pause", for: .normal)
                }
            }
        }
        
        progressBar.onSeekToTimestamp = { [weak self] newTime in
            self?.player.seek(timestamp: newTime)
        }
    }
    
    @objc
    private func play() {
        if player.playState != .pause {
            player.pause()
        } else {
            player.play()
        }
    }
    
    @objc
    private func forwardVideo() {
        
    }
}

private enum Const {
//    static let m3u8Playlist = URL(string: "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8")!
//    static let m3u8MasterPlaylist = URL(string: "http://localhost:8080/master.m3u8")!
//    static let m3u8MasterPlaylist = URL(string: "http://192.168.178.102:8080/master.m3u8")!
    static let m3u8MasterPlaylistSync = URL(string: "http://127.0.0.1:8080/master.m3u8")!
//    static let m3u8MasterPlaylistSync = URL(string: "http://192.168.178.102:8080/master.m3u8")!
}

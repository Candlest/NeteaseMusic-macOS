//
//  PlaybackViewModel.swift
//  NeteaseMusic
//
//  Created by Codex on 2026/4/23.
//

import Cocoa

final class PlaybackViewModel: NSObject {
    static let shared = PlaybackViewModel()
    
    private let playCore = PlayCore.shared
    private var observations = [NSKeyValueObservation]()
    
    @objc dynamic private(set) var currentTrack: Track?
    @objc dynamic private(set) var playerState: PlayCore.PlayerState = .stopped
    @objc dynamic private(set) var playProgress: Double = 0
    @objc dynamic private(set) var playbackElapsedTime: Double = 0
    @objc dynamic private(set) var playbackDuration: Double = 0
    @objc dynamic private(set) var fmMode = false
    @objc dynamic private(set) var pnItemType: PlayCore.PNItemType = .withoutPreviousAndNext
    @objc dynamic private(set) var isCurrentTrackPlaying = false
    
    private override init() {
        super.init()
        bindToPlayCore()
        syncAll()
    }
    
    private func bindToPlayCore() {
        observations = [
            playCore.observe(\.currentTrack, options: [.initial, .new]) { [weak self] _, _ in
                self?.syncTrack()
            },
            playCore.observe(\.playerState, options: [.initial, .new]) { [weak self] _, _ in
                self?.syncPlaybackState()
            },
            playCore.observe(\.playProgress, options: [.initial, .new]) { [weak self] _, _ in
                self?.playProgress = self?.playCore.playProgress ?? 0
            },
            playCore.observe(\.playbackElapsedTime, options: [.initial, .new]) { [weak self] _, _ in
                self?.playbackElapsedTime = self?.playCore.playbackElapsedTime ?? 0
            },
            playCore.observe(\.playbackDuration, options: [.initial, .new]) { [weak self] _, _ in
                self?.playbackDuration = self?.playCore.playbackDuration ?? 0
            },
            playCore.observe(\.fmMode, options: [.initial, .new]) { [weak self] _, _ in
                self?.fmMode = self?.playCore.fmMode ?? false
            },
            playCore.observe(\.pnItemType, options: [.initial, .new]) { [weak self] _, _ in
                self?.pnItemType = self?.playCore.pnItemType ?? .withoutPreviousAndNext
            }
        ]
    }
    
    private func syncAll() {
        syncTrack()
        syncPlaybackState()
        playProgress = playCore.playProgress
        playbackElapsedTime = playCore.playbackElapsedTime
        playbackDuration = playCore.playbackDuration
        fmMode = playCore.fmMode
        pnItemType = playCore.pnItemType
    }
    
    private func syncTrack() {
        currentTrack = playCore.currentTrack
        isCurrentTrackPlaying = playCore.isCurrentTrackPlaying
    }
    
    private func syncPlaybackState() {
        playerState = playCore.playerState
        isCurrentTrackPlaying = playCore.isCurrentTrackPlaying
    }
}

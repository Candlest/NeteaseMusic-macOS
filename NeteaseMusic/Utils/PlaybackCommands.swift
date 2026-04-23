//
//  PlaybackCommands.swift
//  NeteaseMusic
//
//  Created by Codex on 2026/4/23.
//

import AVFoundation

final class PlaybackCommands {
    static let shared = PlaybackCommands()
    
    private let playCore = PlayCore.shared
    
    private init() {}
    
    func start(_ tracks: [Track], id: Int = -1, enterFMMode: Bool = false) {
        playCore.start(tracks, id: id, enterFMMode: enterFMMode)
    }
    
    func togglePlayPause() {
        playCore.togglePlayPause()
    }
    
    func stop() {
        playCore.stop()
    }
    
    func nextSong() {
        playCore.nextSong()
    }
    
    func previousSong() {
        playCore.previousSong()
    }
    
    func seek(to time: CMTime) {
        playCore.seekToPlaybackTime(time)
    }
    
    func setVolume(_ volume: Float) {
        playCore.player.volume = volume
        Preferences.shared.volume = volume
    }
    
    func setMuted(_ muted: Bool) {
        playCore.player.isMuted = muted
        Preferences.shared.mute = muted
    }
    
    func increaseVolume() {
        playCore.increaseVolume()
    }
    
    func decreaseVolume() {
        playCore.decreaseVolume()
    }
    
    func clearPlaylist() {
        playCore.playlist.removeAll()
    }
    
    func clearHistory() {
        playCore.historys.removeAll()
    }
    
    func removePlaylistTracks(ids: [Int]) {
        playCore.playlist = playCore.playlist.filter { !ids.contains($0.id) }
    }
    
    func setupSystemMediaKeys() {
        playCore.setupSystemMediaKeys()
    }
}

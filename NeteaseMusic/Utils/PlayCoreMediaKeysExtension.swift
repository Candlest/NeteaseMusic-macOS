//
//  PlayCoreMediaKeysExtension.swift
//  NeteaseMusic
//
//  Created by xjbeta on 2019/11/17.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa
import MediaPlayer
import SDWebImage

final class PlayCoreRemoteCommandHandler: NSObject {
    weak var playCore: PlayCore?
    
    init(playCore: PlayCore) {
        self.playCore = playCore
    }
    
    @objc func handlePlayCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        mediaCenterTrace("remoteCommand play")
        guard let playCore, playCore.resumeFromMediaCenter() else {
            return .commandFailed
        }
        playCore.dumpMediaCenterDebugState(reason: "remote command play")
        return .success
    }
    
    @objc func handlePauseCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        mediaCenterTrace("remoteCommand pause")
        guard let playCore, playCore.pauseFromMediaCenter() else {
            return .commandFailed
        }
        playCore.dumpMediaCenterDebugState(reason: "remote command pause")
        return .success
    }
    
    @objc func handleTogglePlayPauseCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        mediaCenterTrace("remoteCommand togglePlayPause")
        guard let playCore,
              playCore.currentTrack != nil else {
            return .commandFailed
        }
        playCore.togglePlayPause()
        playCore.dumpMediaCenterDebugState(reason: "remote command toggle")
        return .success
    }
    
    @objc func handleStopCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        mediaCenterTrace("remoteCommand stop")
        guard let playCore,
              playCore.currentTrack != nil else {
            return .commandFailed
        }
        playCore.stop()
        playCore.dumpMediaCenterDebugState(reason: "remote command stop")
        return .success
    }
    
    @objc func handleNextTrackCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        mediaCenterTrace("remoteCommand nextTrack")
        guard let playCore else { return .commandFailed }
        playCore.nextSong()
        playCore.dumpMediaCenterDebugState(reason: "remote command next")
        return .success
    }
    
    @objc func handlePreviousTrackCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        mediaCenterTrace("remoteCommand previousTrack")
        guard let playCore else { return .commandFailed }
        playCore.previousSong()
        playCore.dumpMediaCenterDebugState(reason: "remote command previous")
        return .success
    }
    
    @objc func handleChangePlaybackPositionCommand(_ event: MPChangePlaybackPositionCommandEvent) -> MPRemoteCommandHandlerStatus {
        mediaCenterTrace("remoteCommand changePlaybackPosition=\(event.positionTime)")
        guard let playCore,
              playCore.currentTrack != nil else {
            return .commandFailed
        }
        let time = CMTime(seconds: event.positionTime, preferredTimescale: 1000)
        playCore.seekToPlaybackTime(time)
        playCore.dumpMediaCenterDebugState(reason: "remote command seek")
        return .success
    }
}

final class PlayCoreNowPlayingCoordinator {
    weak var playCore: PlayCore?
    
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    private var remoteCommandHandler: PlayCoreRemoteCommandHandler?
    private var remoteCommandsRegistered = false
    private var enabled = false
    private var remoteCommandsEnabled = false
    
    init(playCore: PlayCore) {
        self.playCore = playCore
    }
    
    func activate() {
        enabled = true
        mediaCenterTrace("coordinator activateNowPlaying")
        refreshSnapshot(resetPlaybackTime: false)
        debugDump(reason: "coordinator activateNowPlaying")
    }
    
    func deactivate() {
        enabled = false
        remoteCommandsEnabled = false
        mediaCenterTrace("coordinator deactivateNowPlaying")
        disableCommands()
        clear()
        debugDump(reason: "coordinator deactivateNowPlaying")
    }
    
    func setRemoteCommandsEnabled(_ enabled: Bool) {
        remoteCommandsEnabled = enabled
        mediaCenterTrace("coordinator remoteCommandsEnabled=\(enabled)")
        guard self.enabled else {
            debugDump(reason: "set remote commands before activation")
            return
        }
        
        guard enabled,
              let playCore,
              playCore.currentTrack != nil else {
            disableCommands()
            debugDump(reason: "disable remote commands")
            return
        }
        
        registerCommands(hasPrevious: playCore.hasPreviousTrack,
                         hasNext: playCore.hasNextTrack,
                         canSeek: playCore.currentTrack != nil)
        debugDump(reason: "enable remote commands")
    }
    
    func refreshSnapshot(resetPlaybackTime: Bool) {
        guard enabled,
              let playCore,
              let track = playCore.currentTrack else {
            clear()
            return
        }
        
        var info = metadata(for: track, fallbackArtwork: NSApp.applicationIconImage)
        applyPlaybackContext(
            to: &info,
            from: playCore,
            resetPlaybackTime: resetPlaybackTime
        )
        nowPlayingInfoCenter.nowPlayingInfo = info
        if remoteCommandsEnabled {
            registerCommands(hasPrevious: playCore.hasPreviousTrack,
                             hasNext: playCore.hasNextTrack,
                             canSeek: playCore.currentTrack != nil)
        } else {
            disableCommands()
        }
        updatePlaybackState(playCore.playerState)
        mediaCenterTrace("refreshNowPlayingInfo track=\(track.id) reset=\(resetPlaybackTime) prev=\(playCore.hasPreviousTrack) next=\(playCore.hasNextTrack)")
        debugDump(reason: "refresh snapshot")
    }
    
    func updateProgress() {
        guard enabled,
              let playCore,
              playCore.currentTrack != nil,
              var info = nowPlayingInfoCenter.nowPlayingInfo else {
            return
        }
        
        applyPlaybackContext(
            to: &info,
            from: playCore,
            resetPlaybackTime: false
        )
        nowPlayingInfoCenter.nowPlayingInfo = info
        updatePlaybackState(playCore.playerState)
        mediaCenterTrace("updateNowPlayingInfo elapsed=\(playCore.nowPlayingElapsedTime) duration=\(playCore.nowPlayingDuration) rate=\(playCore.nowPlayingPlaybackRate)")
        debugDump(reason: "update progress")
    }
    
    func updatePlaybackState(_ state: PlayCore.PlayerState) {
        guard enabled else { return }
        
        let nowPlayingState: MPNowPlayingPlaybackState?
        switch state {
        case .playing:
            nowPlayingState = .playing
        case .paused:
            nowPlayingState = .paused
        case .stopped:
            nowPlayingState = .stopped
        case .interrupted:
            nowPlayingState = .interrupted
        case .unknown:
            nowPlayingState = nil
        }
        
        guard let nowPlayingState else {
            mediaCenterTrace("skip playbackState update for unknown state")
            return
        }
        nowPlayingInfoCenter.playbackState = nowPlayingState
        mediaCenterTrace("playbackState=\(nowPlayingState.rawValue)")
        debugDump(reason: "update playback state")
    }
    
    func clear() {
        nowPlayingInfoCenter.nowPlayingInfo = nil
        nowPlayingInfoCenter.playbackState = .stopped
        mediaCenterTrace("clearNowPlayingInfo")
        debugDump(reason: "clear")
    }
    
    private func registerCommands(hasPrevious: Bool, hasNext: Bool, canSeek: Bool) {
        guard remoteCommandsEnabled else { return }
        
        let handler = remoteCommandHandler ?? {
            guard let playCore else { return nil }
            let handler = PlayCoreRemoteCommandHandler(playCore: playCore)
            remoteCommandHandler = handler
            return handler
        }()
        
        guard let handler else { return }
        
        if remoteCommandsRegistered {
            removeTargets(handler)
        }
        
        remoteCommandCenter.playCommand.isEnabled = true
        remoteCommandCenter.pauseCommand.isEnabled = true
        remoteCommandCenter.togglePlayPauseCommand.isEnabled = true
        remoteCommandCenter.stopCommand.isEnabled = true
        remoteCommandCenter.nextTrackCommand.isEnabled = hasNext
        remoteCommandCenter.previousTrackCommand.isEnabled = hasPrevious
        remoteCommandCenter.changePlaybackPositionCommand.isEnabled = canSeek
        remoteCommandCenter.seekForwardCommand.isEnabled = false
        remoteCommandCenter.seekBackwardCommand.isEnabled = false
        remoteCommandCenter.changeRepeatModeCommand.isEnabled = false
        remoteCommandCenter.changeShuffleModeCommand.isEnabled = false
        remoteCommandCenter.changePlaybackRateCommand.isEnabled = false
        
        remoteCommandCenter.playCommand.addTarget(handler, action: #selector(PlayCoreRemoteCommandHandler.handlePlayCommand(_:)))
        remoteCommandCenter.pauseCommand.addTarget(handler, action: #selector(PlayCoreRemoteCommandHandler.handlePauseCommand(_:)))
        remoteCommandCenter.togglePlayPauseCommand.addTarget(handler, action: #selector(PlayCoreRemoteCommandHandler.handleTogglePlayPauseCommand(_:)))
        remoteCommandCenter.stopCommand.addTarget(handler, action: #selector(PlayCoreRemoteCommandHandler.handleStopCommand(_:)))
        remoteCommandCenter.nextTrackCommand.addTarget(handler, action: #selector(PlayCoreRemoteCommandHandler.handleNextTrackCommand(_:)))
        remoteCommandCenter.previousTrackCommand.addTarget(handler, action: #selector(PlayCoreRemoteCommandHandler.handlePreviousTrackCommand(_:)))
        remoteCommandCenter.changePlaybackPositionCommand.addTarget(handler, action: #selector(PlayCoreRemoteCommandHandler.handleChangePlaybackPositionCommand(_:)))
        
        remoteCommandsRegistered = true
        mediaCenterTrace("registerCommands prev=\(hasPrevious) next=\(hasNext) seek=\(canSeek)")
        debugDump(reason: "register commands")
    }
    
    private func disableCommands() {
        if remoteCommandsRegistered, let handler = remoteCommandHandler {
            removeTargets(handler)
        }
        remoteCommandsRegistered = false
        remoteCommandCenter.playCommand.isEnabled = false
        remoteCommandCenter.pauseCommand.isEnabled = false
        remoteCommandCenter.togglePlayPauseCommand.isEnabled = false
        remoteCommandCenter.stopCommand.isEnabled = false
        remoteCommandCenter.nextTrackCommand.isEnabled = false
        remoteCommandCenter.previousTrackCommand.isEnabled = false
        remoteCommandCenter.changePlaybackPositionCommand.isEnabled = false
        remoteCommandCenter.seekForwardCommand.isEnabled = false
        remoteCommandCenter.seekBackwardCommand.isEnabled = false
        remoteCommandCenter.changeRepeatModeCommand.isEnabled = false
        remoteCommandCenter.changeShuffleModeCommand.isEnabled = false
        remoteCommandCenter.changePlaybackRateCommand.isEnabled = false
        debugDump(reason: "disable commands")
    }
    
    private func removeTargets(_ handler: PlayCoreRemoteCommandHandler) {
        remoteCommandCenter.playCommand.removeTarget(handler)
        remoteCommandCenter.pauseCommand.removeTarget(handler)
        remoteCommandCenter.togglePlayPauseCommand.removeTarget(handler)
        remoteCommandCenter.stopCommand.removeTarget(handler)
        remoteCommandCenter.nextTrackCommand.removeTarget(handler)
        remoteCommandCenter.previousTrackCommand.removeTarget(handler)
        remoteCommandCenter.changePlaybackPositionCommand.removeTarget(handler)
    }
    
    private func metadata(for track: Track, fallbackArtwork: NSImage?) -> [String: Any] {
        var info = [String: Any]()
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPMediaItemPropertyMediaType] = MPMediaType.music.rawValue
        info[MPMediaItemPropertyPersistentID] = NSNumber(value: track.id)
        info[MPMediaItemPropertyTitle] = track.name
        info[MPMediaItemPropertyArtist] = track.artistsString
        info[MPMediaItemPropertyAlbumArtist] = track.album.artists?.artistsString
        info[MPMediaItemPropertyAlbumTitle] = track.album.name
        info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: .init(width: 512, height: 512)) { size in
            guard let rawURL = track.album.picUrl?.absoluteString.appending("?param=\(Int(size.width))y\(Int(size.height))"),
                  let url = URL(string: rawURL),
                  let key = ImageLoader.key(url) else {
                return fallbackArtwork ?? NSImage()
            }
            
            if let image = SDImageCache.shared.imageFromMemoryCache(forKey: key) {
                return image
            }
            if let image = NSImage(contentsOf: url) {
                SDImageCache.shared.store(image, forKey: key, completion: nil)
                return image
            }
            return fallbackArtwork ?? NSImage()
        }
        return info
    }
    
    private func applyPlaybackContext(to info: inout [String: Any],
                                      from playCore: PlayCore,
                                      resetPlaybackTime: Bool) {
        let duration = playCore.nowPlayingDuration
        let elapsed = resetPlaybackTime ? 0 : playCore.nowPlayingElapsedTime
        
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        if duration > 0 {
            info[MPNowPlayingInfoPropertyPlaybackProgress] = min(max(elapsed / duration, 0), 1)
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = playCore.nowPlayingPlaybackRate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyCurrentPlaybackDate] = Date()
    }
    
    func debugDump(reason: String) {
        let state = debugState(reason: reason)
        mediaCenterWriteState(state)
    }
    
    private func debugState(reason: String) -> [String: Any] {
        var state: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "reason": reason,
            "bundlePath": Bundle.main.bundlePath,
            "executablePath": Bundle.main.executablePath ?? "",
            "processIdentifier": ProcessInfo.processInfo.processIdentifier,
            "enabled": enabled,
            "remoteCommandsEnabled": remoteCommandsEnabled,
            "remoteCommandsRegistered": remoteCommandsRegistered,
            "hasRemoteCommandHandler": remoteCommandHandler != nil,
            "preferencesUseSystemMediaControl": Preferences.shared.useSystemMediaControl,
            "commands": [
                "play": remoteCommandCenter.playCommand.isEnabled,
                "pause": remoteCommandCenter.pauseCommand.isEnabled,
                "togglePlayPause": remoteCommandCenter.togglePlayPauseCommand.isEnabled,
                "stop": remoteCommandCenter.stopCommand.isEnabled,
                "nextTrack": remoteCommandCenter.nextTrackCommand.isEnabled,
                "previousTrack": remoteCommandCenter.previousTrackCommand.isEnabled,
                "changePlaybackPosition": remoteCommandCenter.changePlaybackPositionCommand.isEnabled,
                "seekForward": remoteCommandCenter.seekForwardCommand.isEnabled,
                "seekBackward": remoteCommandCenter.seekBackwardCommand.isEnabled,
                "changeRepeatMode": remoteCommandCenter.changeRepeatModeCommand.isEnabled,
                "changeShuffleMode": remoteCommandCenter.changeShuffleModeCommand.isEnabled,
                "changePlaybackRate": remoteCommandCenter.changePlaybackRateCommand.isEnabled
            ],
            "nowPlayingCenter": [
                "playbackStateRaw": nowPlayingInfoCenter.playbackState.rawValue,
                "playbackState": String(describing: nowPlayingInfoCenter.playbackState),
                "nowPlayingInfo": mediaCenterSanitizedJSON(nowPlayingInfoCenter.nowPlayingInfo ?? [:])
            ]
        ]
        
        if let playCore {
            state["playCore"] = mediaCenterSanitizedJSON(playCore.mediaCenterDebugState())
        }
        
        return state
    }
}

extension PlayCore {
    var hasPreviousTrack: Bool {
        pnItemType != .withoutPrevious && pnItemType != .withoutPreviousAndNext
    }
    
    var hasNextTrack: Bool {
        pnItemType != .withoutNext && pnItemType != .withoutPreviousAndNext
    }
    
    var nowPlayingDuration: Double {
        max(0, playbackDuration)
    }
    
    var nowPlayingElapsedTime: Double {
        max(0, playbackElapsedTime)
    }
    
    var nowPlayingPlaybackRate: Double {
        guard playerState == .playing else { return 0 }
        return playbackRate > 0 ? playbackRate : 1.0
    }
    
    @discardableResult
    func resumeFromMediaCenter() -> Bool {
        guard currentTrack != nil else { return false }
        guard playerState != .playing else { return true }
        player.play()
        syncPlaybackProgress()
        transitionPlaybackState(to: .playing, reason: "remote command play")
        return true
    }
    
    @discardableResult
    func pauseFromMediaCenter() -> Bool {
        guard currentTrack != nil else { return false }
        guard playerState == .playing else { return true }
        player.pause()
        syncPlaybackProgress()
        transitionPlaybackState(to: .paused, reason: "remote command pause")
        return true
    }
    
    func seekToPlaybackTime(_ time: CMTime) {
        player.seek(to: time) { _ in
            self.syncPlaybackProgress(from: time)
        }
    }
    
    func setupRemoteCommandCenter() {
        nowPlayingCoordinator.activate()
    }
    
    func activateNowPlayingRegistration() {
        nowPlayingCoordinator.activate()
    }
    
    func enableRemoteCommands() {
        nowPlayingCoordinator.setRemoteCommandsEnabled(true)
    }
    
    func disableRemoteCommands() {
        nowPlayingCoordinator.setRemoteCommandsEnabled(false)
    }
    
    func updateNowPlayingState(_ state: MPNowPlayingPlaybackState) {
        switch state {
        case .unknown:
            break
        case .playing:
            nowPlayingCoordinator.updatePlaybackState(.playing)
        case .paused:
            nowPlayingCoordinator.updatePlaybackState(.paused)
        case .stopped:
            nowPlayingCoordinator.updatePlaybackState(.stopped)
        case .interrupted:
            nowPlayingCoordinator.updatePlaybackState(.interrupted)
        @unknown default:
            break
        }
    }
    
    func clearNowPlayingInfo() {
        nowPlayingCoordinator.clear()
    }
    
    func initNowPlayingInfo() {
        refreshNowPlayingInfo(resetPlaybackTime: true)
    }
    
    func refreshNowPlayingInfo(resetPlaybackTime: Bool = false) {
        nowPlayingCoordinator.refreshSnapshot(resetPlaybackTime: resetPlaybackTime)
    }
    
    func updateNowPlayingInfo() {
        nowPlayingCoordinator.updateProgress()
    }
    
    func dumpMediaCenterDebugState(reason: String) {
        nowPlayingCoordinator.debugDump(reason: reason)
    }
    
    func mediaCenterDebugState() -> [String: Any] {
        let currentItem = player.currentItem
        return [
            "currentTrack": currentTrack.map {
                [
                    "id": $0.id,
                    "name": $0.name,
                    "artists": $0.artistsString,
                    "album": $0.album.name,
                    "durationMS": $0.duration
                ]
            } as Any,
            "playerStateRaw": playerState.rawValue,
            "playerState": String(describing: playerState),
            "timeControlStatusRaw": timeControlStatus.rawValue,
            "timeControlStatus": String(describing: timeControlStatus),
            "playbackElapsedTime": playbackElapsedTime,
            "playbackDuration": playbackDuration,
            "playProgress": playProgress,
            "playbackRate": playbackRate,
            "isCurrentTrackPlaying": isCurrentTrackPlaying,
            "pnItemTypeRaw": pnItemType.rawValue,
            "pnItemType": String(describing: pnItemType),
            "fmMode": fmMode,
            "player": [
                "rate": player.rate,
                "statusRaw": player.status.rawValue,
                "status": String(describing: player.status),
                "currentTime": sanitizePlaybackSeconds(player.currentTime().seconds),
                "error": player.error?.localizedDescription as Any
            ],
            "currentItem": [
                "exists": currentItem != nil,
                "statusRaw": currentItem?.status.rawValue as Any,
                "status": currentItem.map { String(describing: $0.status) } as Any,
                "isPlaybackLikelyToKeepUp": currentItem?.isPlaybackLikelyToKeepUp as Any,
                "isPlaybackBufferEmpty": currentItem?.isPlaybackBufferEmpty as Any,
                "isPlaybackBufferFull": currentItem?.isPlaybackBufferFull as Any,
                "loadedTimeRanges": currentItem?.loadedTimeRanges.map { String(describing: $0.timeRangeValue) } as Any,
                "error": currentItem?.error?.localizedDescription as Any
            ]
        ]
    }
}

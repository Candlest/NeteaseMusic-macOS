//
//  PlayCore.swift
//  NeteaseMusic
//
//  Created by xjbeta on 2019/3/31.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa
import MediaPlayer
import AVFoundation
import PromiseKit
import GSPlayer

private let mediaCenterTraceURL: URL = {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/NeteaseMusic-media-center.log")
}()

private let mediaCenterStateURL: URL = {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/NeteaseMusic-media-center-state.json")
}()

private func mediaCenterEnsureLogDirectory() {
    let dir = mediaCenterTraceURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
}

func mediaCenterTrace(_ message: String) {
    let line = "[MediaCenter] \(message)"
    NSLog("%@", line)
    Log.info(line)
    
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let fileLine = "\(timestamp) \(line)\n"
    let data = Data(fileLine.utf8)
    
    mediaCenterEnsureLogDirectory()
    if !FileManager.default.fileExists(atPath: mediaCenterTraceURL.path) {
        FileManager.default.createFile(atPath: mediaCenterTraceURL.path, contents: nil)
    }
    if let handle = try? FileHandle(forWritingTo: mediaCenterTraceURL) {
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        handle.write(data)
    }
}

func mediaCenterSanitizedJSON(_ value: Any?) -> Any {
    guard let value else { return NSNull() }
    
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number
    case let bool as Bool:
        return bool
    case let int as Int:
        return int
    case let double as Double:
        return double.isFinite ? double : String(double)
    case let float as Float:
        return float.isFinite ? float : String(float)
    case let date as Date:
        return ISO8601DateFormatter().string(from: date)
    case let url as URL:
        return url.absoluteString
    case let time as CMTime:
        return time.seconds.isFinite ? time.seconds : String(describing: time)
    case let array as [Any]:
        return array.map(mediaCenterSanitizedJSON)
    case let dictionary as [String: Any]:
        return dictionary.mapValues(mediaCenterSanitizedJSON)
    default:
        return String(describing: value)
    }
}

func mediaCenterWriteState(_ state: [String: Any]) {
    mediaCenterEnsureLogDirectory()
    guard JSONSerialization.isValidJSONObject(state),
          let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) else {
        return
    }
    try? data.write(to: mediaCenterStateURL, options: .atomic)
}

class PlayCore: NSObject {
    static let shared = PlayCore()
    
    private override init() {
        player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = false
        VideoPreloadManager.shared.preloadByteCount *= 2
        super.init()
        initPlayerObservers()
    }
    
// MARK: - NowPlayingInfoCenter
    
    lazy var nowPlayingCoordinator = PlayCoreNowPlayingCoordinator(playCore: self)
    var currentItemStatusObserver: NSKeyValueObservation?
    var currentItemLikelyToKeepUpObserver: NSKeyValueObservation?
    
// MARK: - AVPlayer
    
    private let playerQueue = DispatchQueue(label: "com.xjbeta.NeteaseMusic.AVPlayerItem")
    
    let api = NeteaseMusicAPI()
    @objc dynamic var timeControlStatus: AVPlayer.TimeControlStatus = .waitingToPlayAtSpecifiedRate
    
    
    let player: AVPlayer
    
    @objc dynamic var playProgress: Double = 0
    @objc dynamic var playbackElapsedTime: Double = 0
    @objc dynamic var playbackDuration: Double = 0
    @objc dynamic var playbackRate: Double = 0
    
    @objc enum PlayerState: Int {
        case unknown = 0
        case playing = 1
        case paused = 2
        case stopped = 3
        case interrupted = 4
    }
    
    @objc dynamic var playerState: PlayerState = .stopped {
        didSet {
            applySystemPlaybackState()
            switch playerState {
            case .playing:
                refreshNowPlayingInfo(resetPlaybackTime: false)
            case .paused, .interrupted:
                updateNowPlayingInfo()
            case .stopped:
                clearNowPlayingInfo()
            case .unknown:
                break
            }
        }
    }

    var periodicTimeObserverToken: Any?
    var timeControlStautsObserver: NSKeyValueObservation?
    
    
    private var playerReloadTimer: Timer?
    private var isTryingToReload = false
    
    var playerShouldNextObserver: NSObjectProtocol?
    var playerStateObserver: NSKeyValueObservation?
    
    @objc dynamic var currentTrack: Track? {
        didSet {
            guard let currentTrack else {
                playbackDuration = 0
                playbackElapsedTime = 0
                playProgress = 0
                return
            }
            playbackDuration = max(0, Double(currentTrack.duration) / 1000)
            if oldValue != currentTrack {
                playbackElapsedTime = 0
                updateExplicitPlayProgress()
            }
        }
    }
    
    @objc dynamic var playlist: [Track] = [] {
        didSet {
            guard fmMode else { return }
            if let ct = currentTrack,
               let i = playlist.firstIndex(of: ct) {
                internalPlaylistIndex = i
            } else {
                internalPlaylistIndex = -1
            }
        }
    }
    @objc dynamic var historys: [Track] = []
    @objc dynamic var fmMode = false
    
    @objc enum PNItemType: Int {
        case withoutNext
        case withoutPrevious
        case withoutPreviousAndNext
        case other
    }
    
    @objc dynamic var pnItemType: PNItemType = .withoutPreviousAndNext
    
    private var fmSavedTime = (id: -1, time: CMTime())
    
// MARK: - AVPlayer Internal Playlist
    private var playingNextLimit = 20
    private var playingNextList: [Int] {
        get {
            if fmMode {
                let list = playlist[internalPlaylistIndex..<playlist.count]
                return list.map({ $0.id })
            }
            
            let repeatMode = Preferences.shared.repeatMode
            updateInternalPlaylist()
            
            switch repeatMode {
            case .repeatItem where currentTrack != nil:
                return [currentTrack!.id]
            case .repeatItem where playlist.first != nil:
                return [playlist.first!.id]
            case .noRepeat, .repeatPlayList:
                let sIndex = internalPlaylistIndex + 1
                var eIndex = sIndex + playingNextLimit
                if eIndex > internalPlaylist.count {
                    eIndex = internalPlaylist.count
                }
                return internalPlaylist[sIndex..<eIndex].map{ $0 }
            default:
                return []
            }
        }
    }
    
    private var internalPlaylistIndex = -1 {
        didSet {
            switch (internalPlaylistIndex, fmMode) {
            case (0, false) where internalPlaylist.count == 1:
                pnItemType = .withoutPreviousAndNext
            case (0, _):
                pnItemType = .withoutPrevious
            case (-1, _):
                pnItemType = .withoutPreviousAndNext
            case (internalPlaylist.count - 1, false):
                pnItemType = .withoutNext
            case (playlist.count - 1, true):
                pnItemType = .withoutNext
            default:
                pnItemType = .other
            }
        }
    }
    private var internalPlaylist = [Int]()
    
    
// MARK: - AVPlayer Waiting
    
    private var itemWaitingToLoad: Int?
    private var loadingList = [Int]()
    
    
// MARK: - AVPlayer Functions
    
    func start(_ playlist: [Track],
               id: Int = -1,
               enterFMMode: Bool = false) {
        
        let pl = playlist.filter {
            $0.playable
        }
        guard pl.count > 0 else {
            return
        }
        
        var sid = id
        if fmMode {
            if !enterFMMode {
                fmSavedTime = (currentTrack?.id ?? -1, CMTime(value: 0, timescale: 1000))
            } else {
                sid = fmSavedTime.id
            }
        }
        fmMode = enterFMMode
        
        stop()
        
        self.playlist = pl
        
        initInternalPlaylist(sid)
        updateInternalPlaylist()

        if fmMode {
            var time = CMTime(value: 0, timescale: 1000)
            let id = id == -1 ? playlist.first!.id : id
            if id == fmSavedTime.id {
                time = fmSavedTime.time
            }
            
            guard let i = playlist.firstIndex(where: { $0.id == id }) else {
                return
            }
            internalPlaylistIndex = i
            let track = playlist[i]
            play(track, time: time)
        } else if id != -1,
                  let i = internalPlaylist.firstIndex(of: id),
                  let track = playlist.first(where: { $0.id == id }) {
            internalPlaylistIndex = i
            play(track)
        } else if let id = internalPlaylist.first,
                  let track = playlist.first(where: { $0.id == id }) {
            internalPlaylistIndex = 0
            play(track)
        } else {
            Log.error("Not find track to start play.")
        }
    }
    
    func playNow(_ tracks: [Track]) {
        if let currentTrack = currentTrack,
            let i = playlist.enumerated().filter({ $0.element == currentTrack }).first?.offset {
            playlist.insert(contentsOf: tracks, at: i + 1)
        } else {
            playlist.append(contentsOf: tracks)
        }
        if let t = tracks.first {
            play(t)
        }
    }
    
    func nextSong() {
        if fmMode {
            guard let c = currentTrack,
                  let ci = playlist.firstIndex(of: c),
                  let track = playlist[safe: ci + 1]
            else {
                Log.error("Can't find next fm track.")
                stop()
                return
            }
            play(track)
        } else {
            let repeatMode = Preferences.shared.repeatMode
            guard repeatMode != .repeatItem else {
                player.seek(to: CMTime(value: 0, timescale: 1000))
                player.play()
                setPlaybackElapsedTime(0)
                transitionPlaybackState(to: .playing, reason: "repeat current item")
                refreshNowPlayingInfo(resetPlaybackTime: true)
                return
            }
            
            updateInternalPlaylist()
            
            guard let id = internalPlaylist[safe: internalPlaylistIndex + 1],
                  let track = playlist.first(where: { $0.id == id })
            else {
                Log.error("Can't find next track.")
                stop()
                return
            }
            internalPlaylistIndex += 1
            play(track)
        }
    }
    
    func previousSong() {
        let list = fmMode ? playlist.map({ $0.id }) : internalPlaylist
        
        guard let id = list[safe: internalPlaylistIndex - 1],
              let track = playlist.first(where: { $0.id == id })
              else {
            return
        }
        internalPlaylistIndex -= 1
        play(track)
    }

    func togglePlayPause() {
        guard player.error == nil else { return }
        func playOrPause() {
            if player.rate == 0 {
                player.play()
                syncPlaybackProgress()
                transitionPlaybackState(to: .playing, reason: "toggle play")
            } else {
                player.pause()
                syncPlaybackProgress()
                transitionPlaybackState(to: .paused, reason: "toggle pause")
            }
        }
        if currentTrack != nil {
            playOrPause()
        } else if let item = ViewControllerManager.shared.selectedSidebarItem?.type {
            switch item {
            case .fm:
                start([], enterFMMode: true)
            case .createdPlaylist, .subscribedPlaylist:
                let todo = "play playlist."
                break
            default:
                break
            }
        }
    }
    
    func increaseVolume() {
        var v = player.volume
        guard v < 1 else {
            return
        }
        v += 0.1
        player.volume = v >= 1 ? 1 : v
        playerVolumeChanged()
    }
    
    func decreaseVolume() {
        var v = player.volume
        guard v >= 0 else {
            player.volume = 0
            return
        }
        v -= 0.1
        player.volume = v < 0 ? 0 : v
        playerVolumeChanged()
    }
    
    func playerVolumeChanged() {
        Preferences.shared.volume = player.volume
        NotificationCenter.default.post(name: .volumeChanged, object: nil)
    }
    
    func stop() {
        transitionPlaybackState(to: .stopped, reason: "stop")
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        player.currentItem?.asset.cancelLoading()
        invalidateCurrentItemObservers()
        player.replaceCurrentItem(with: nil)
        currentTrack = nil
        internalPlaylist.removeAll()
        internalPlaylistIndex = -1
        pnItemType = .withoutPreviousAndNext
        playlist.removeAll()
        clearNowPlayingInfo()
    }
    
    func toggleRepeatMode() {
        print(#function)
    }
    
    func toggleShuffleMode() {
        print(#function)
    }
    
    func seekForward(_ seconds: Double) {
        let lhs = player.currentTime()
        let rhs = CMTimeMakeWithSeconds(5, preferredTimescale: 1)
        let t = CMTimeAdd(lhs, rhs)
        player.seek(to: t)
    }
    
    func seekBackward(_ seconds: Double) {
        let lhs = player.currentTime()
        let rhs = CMTimeMakeWithSeconds(-5, preferredTimescale: 1)
        let t = CMTimeAdd(lhs, rhs)
        player.seek(to: t)
    }
    
// MARK: - AVPlayer Internal Functions
    
    private func play(_ track: Track,
                      time: CMTime = CMTime(value: 0, timescale: 1000)) {
        
        stageTrack(track, elapsedTime: time.seconds)
        
        if let song = track.song,
           song.urlValid {
            itemWaitingToLoad = nil
            realPlay(track)
        } else if itemWaitingToLoad == track.id {
            return
        } else {
            itemWaitingToLoad = track.id
            loadUrls(track)
        }
    }
    
    
    private func loadUrls(_ track: Track) {
        let list = playingNextList.filter {
            !loadingList.contains($0)
        }.compactMap { id in
            playlist.first(where: { $0.id == id })
        }.filter {
            $0.playable
        }.filter {
            !($0.song?.urlValid ?? false)
        }
        
        var ids = [track.id]
        if list.count >= 4 {
            let l = list[0..<4].map { $0.id }
            ids.append(contentsOf: l)
        } else {
            let l = list.map { $0.id }
            ids.append(contentsOf: l)
        }
        
        ids = Array(Set(ids))
        loadingList.append(contentsOf: ids)
        
        let br = Preferences.shared.musicBitRate.rawValue
        api.songUrl(ids, br).done(on: .main) {
            var preloadUrls = [URL]()
            $0.forEach { song in
                guard let track = self.playlist.first(where: { $0.id == song.id }) else { return }
                track.song = song
                self.loadingList.removeAll(where: { $0 == song.id })
                
                if self.itemWaitingToLoad == song.id {
                    self.realPlay(track)
                    self.itemWaitingToLoad = nil
                } else if let u = song.url?.https {
                    preloadUrls.append(u)
                }
            }
            
            let vpm = VideoPreloadManager.shared
            vpm.set(waiting: preloadUrls)
        }.catch {
            Log.error("Load Song urls error: \($0)")
        }
    }
    
    
    private func realPlay(_ track: Track) {
        guard let song = track.song,
              let url = song.url?.https else {
            return
        }
        
        playerQueue.async {
            let item = AVPlayerItem(loader: url)
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            
            DispatchQueue.main.async {
                self.observeCurrentItem(item)
                self.player.replaceCurrentItem(with: item)
                self.player.play()
                self.transitionPlaybackState(to: .playing, reason: "start track \(track.id)")
                self.refreshNowPlayingInfo(resetPlaybackTime: true)
                mediaCenterTrace("replaceCurrentItem track=\(track.id) name=\(track.name)")
                
                self.historys.removeAll {
                    $0.id == track.id
                }
                self.historys.append(track)
                
                if self.historys.count > 100 {
                    self.historys.removeFirst()
                }
            }
        }
    }
    
    private func initInternalPlaylist(_ sid: Int) {
        let repeatMode = Preferences.shared.repeatMode
        let shuffleMode = Preferences.shared.shuffleMode
        internalPlaylist.removeAll()
        let idList = playlist.map {
            $0.id
        }
        var sid = sid
        guard idList.count > 0,
              let fid = idList.first,
              !fmMode else {
            internalPlaylistIndex = -1
            return
        }
        internalPlaylistIndex = 0
        
        if sid == -1 || !idList.contains(sid) {
            sid = fid
        }
        
        switch (repeatMode, shuffleMode) {
        case (.repeatItem, _):
            internalPlaylist = [sid]
        case (.noRepeat, .noShuffle),
             (.repeatPlayList, .noShuffle):
            var l = idList
            let i = l.firstIndex(of: sid)!
            l.removeSubrange(0..<i)
            internalPlaylist = l
        case (.noRepeat, .shuffleItems),
             (.repeatPlayList, .shuffleItems):
            var l = idList.shuffled()
            l.removeAll {
                $0 == sid
            }
            l.insert(sid, at: 0)
            internalPlaylist = l
        case (.noRepeat, .shuffleAlbums),
             (.repeatPlayList, .shuffleAlbums):
            var albumList = Set<Int>()
            var dic = [Int: [Int]]()
            playlist.forEach {
                let aid = $0.album.id
                var items = dic[aid] ?? []
                items.append($0.id)
                dic[aid] = items
                albumList.insert(aid)
            }
            let todo = ""
            break
        }
    }
    
    private func updateInternalPlaylist() {
        guard !fmMode else { return }
        guard playlist.count > 0 else {
            Log.error("Nothing playable.")
            internalPlaylistIndex = -1
            currentTrack = nil
            return
        }
        
        let repeatMode = Preferences.shared.repeatMode
        let shuffleMode = Preferences.shared.shuffleMode
        
        let idList = playlist.map {
            $0.id
        }
        
        switch (repeatMode, shuffleMode) {
        case (.repeatPlayList, .noShuffle):
            while internalPlaylist.count - internalPlaylistIndex < playingNextLimit {
                internalPlaylist.append(contentsOf: idList)
            }
        case (.repeatPlayList, .shuffleItems):
            while internalPlaylist.count - internalPlaylistIndex < playingNextLimit {
                let list = idList + idList
                internalPlaylist.append(contentsOf: list.shuffled())
            }
        case (.repeatPlayList, .shuffleAlbums):
            break
        default:
            break
        }
    }
    
    func updateRepeatShuffleMode() {
        initInternalPlaylist(currentTrack?.id ?? -1)
    }
    
    func startPlayerReloadTimer() {
        print("startPlayerReloadTimer")
        playerReloadTimer?.invalidate()
        playerReloadTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            guard let self,
                  player.timeControlStatus == .waitingToPlayAtSpecifiedRate else {
                self?.stopPlayerReloadTimer()
                return
            }
            
            print("Player reloading")
            
            guard let manager = api.reachabilityManager,
                  manager.isReachable,
                  let track = currentTrack,
                  let song = track.song,
                  let url = song.url?.https else {
                return
            }
            
            let time = player.currentItem?.currentTime()
            
            playerQueue.async {
                let item = AVPlayerItem(loader: url)
                item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
                
                DispatchQueue.main.async {
                    self.observeCurrentItem(item)
                    self.player.replaceCurrentItem(with: item)
                    if let time {
                        self.player.seek(to: time)
                        self.setPlaybackElapsedTime(time.seconds)
                    } else {
                        self.setPlaybackElapsedTime(0)
                    }
                    
                    self.player.play()
                    self.transitionPlaybackState(to: .playing, reason: "reload track \(track.id)")
                    self.refreshNowPlayingInfo(resetPlaybackTime: time == nil)
                    mediaCenterTrace("reloadCurrentItem track=\(track.id) name=\(track.name)")
                }
            }
        }
        self.isTryingToReload = true
    }
    
    func stopPlayerReloadTimer() {
        print("stopPlayerReloadTimer")
        playerReloadTimer?.invalidate()
        playerReloadTimer = nil
        isTryingToReload = false
    }
    
// MARK: - System Media Keys
    
    func setupSystemMediaKeys() {
        if #available(macOS 10.13, *) {
            activateNowPlayingRegistration()
            enableRemoteCommands()
            dumpMediaCenterDebugState(reason: "setupSystemMediaKeys")
        }
    }
    
// MARK: - Observers
    func initPlayerObservers() {
        
        timeControlStautsObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] (player, changes) in
            
            guard let self else { return }
            
            let newStatus = player.timeControlStatus
            
            if newStatus == .waitingToPlayAtSpecifiedRate {
                if !isTryingToReload {
                    startPlayerReloadTimer()
                }
            } else if isTryingToReload {
                stopPlayerReloadTimer()
            }
            
            timeControlStatus = newStatus
            mediaCenterTrace("timeControlStatus=\(String(describing: newStatus.rawValue)) currentTrack=\(self.currentTrack?.id ?? -1) rate=\(player.rate)")
        }
        
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let time = CMTime(seconds: 0.5, preferredTimescale: timeScale)
        

        playerStateObserver = player.observe(\.rate, options: [.initial, .new]) { player, _ in
            guard player.status == .readyToPlay else { return }
            
            mediaCenterTrace("playerRate=\(player.rate) state=\(self.playerState.rawValue) currentTrack=\(self.currentTrack?.id ?? -1)")
        }
        
        periodicTimeObserverToken = player .addPeriodicTimeObserver(forInterval: time, queue: .main) { [weak self] time in
            self?.syncPlaybackProgress(from: time)
        }
        
        playerShouldNextObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { _ in
            self.nextSong()
        }
    }
    
    func deinitPlayerObservers() {
        if let timeObserverToken = periodicTimeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            periodicTimeObserverToken = nil
            playProgress = 0
        }
        playerStateObserver?.invalidate()
        timeControlStautsObserver?.invalidate()
        invalidateCurrentItemObservers()
        
        if let obs = playerShouldNextObserver {
            NotificationCenter.default.removeObserver(obs)
            playerShouldNextObserver = nil
        }
    }
    
    
    deinit {
        deinitPlayerObservers()
    }

    private func observeCurrentItem(_ item: AVPlayerItem) {
        invalidateCurrentItemObservers()
        currentItemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                mediaCenterTrace("itemStatus=\(item.status.rawValue) currentTrack=\(self.currentTrack?.id ?? -1)")
                switch item.status {
                case .readyToPlay:
                    mediaCenterTrace("itemReadyToPlay")
                case .failed:
                    self.transitionPlaybackState(to: .stopped, reason: "item failed")
                    self.clearNowPlayingInfo()
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        currentItemLikelyToKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            guard item.isPlaybackLikelyToKeepUp else { return }
            DispatchQueue.main.async {
                mediaCenterTrace("itemLikelyToKeepUp=true currentTrack=\(self.currentTrack?.id ?? -1)")
            }
        }
    }

    private func invalidateCurrentItemObservers() {
        currentItemStatusObserver?.invalidate()
        currentItemStatusObserver = nil
        currentItemLikelyToKeepUpObserver?.invalidate()
        currentItemLikelyToKeepUpObserver = nil
    }

    private func applySystemPlaybackState() {
        switch playerState {
        case .playing:
            updateNowPlayingState(.playing)
        case .paused:
            updateNowPlayingState(.paused)
        case .stopped:
            updateNowPlayingState(.stopped)
        case .interrupted:
            updateNowPlayingState(.interrupted)
        case .unknown:
            mediaCenterTrace("skip playbackState update for unknown state")
        }
    }
    
    var isCurrentTrackPlaying: Bool {
        currentTrack != nil && playerState == .playing
    }
    
    func stageTrack(_ track: Track, elapsedTime: Double = 0) {
        currentTrack = track
        setPlaybackElapsedTime(elapsedTime)
    }
    
    func setPlaybackElapsedTime(_ seconds: Double) {
        playbackElapsedTime = sanitizePlaybackSeconds(seconds)
        updateExplicitPlayProgress()
    }
    
    func syncPlaybackProgress(from time: CMTime? = nil) {
        let seconds = (time ?? player.currentTime()).seconds
        setPlaybackElapsedTime(seconds)
        guard isCurrentTrackPlaying else { return }
        updateNowPlayingInfo()
    }
    
    func transitionPlaybackState(to state: PlayerState, reason: String) {
        let previousState = playerState
        playbackRate = state == .playing ? 1 : 0
        mediaCenterTrace("playerState \(previousState.rawValue)->\(state.rawValue) reason=\(reason)")
        playerState = state
    }
    
    func sanitizePlaybackSeconds(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        return max(0, seconds)
    }
    
    func updateExplicitPlayProgress() {
        guard playbackDuration > 0 else {
            playProgress = 0
            return
        }
        playProgress = min(max(playbackElapsedTime / playbackDuration, 0), 1)
    }
}

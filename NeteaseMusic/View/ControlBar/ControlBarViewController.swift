//
//  ControlBarViewController.swift
//  NeteaseMusic
//
//  Created by xjbeta on 2019/4/10.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa
import AVFoundation

class ControlBarViewController: NSViewController {
    private let playbackCommands = PlaybackCommands.shared
    private let playbackViewModel = PlaybackViewModel.shared
    
    @IBOutlet weak var trackPicButton: NSButton!
    @IBOutlet weak var trackNameTextField: NSTextField!
    @IBOutlet weak var trackSecondNameTextField: NSTextField!

    @IBOutlet weak var previousButton: NSButton!
    @IBOutlet weak var pauseButton: NSButton!
    @IBOutlet weak var nextButton: NSButton!
    @IBOutlet weak var muteButton: NSButton!
    @IBOutlet weak var playlistButton: NSButton!
    @IBOutlet weak var repeatModeButton: NSButton!
    @IBOutlet weak var shuffleModeButton: NSButton!
    
    @IBAction func controlAction(_ sender: NSButton) {
        let pc = PlayCore.shared
        let player = pc.player
        let preferences = Preferences.shared
        
        switch sender {
        case previousButton:
            playbackCommands.previousSong()
        case pauseButton:
            playbackCommands.togglePlayPause()
        case nextButton:
            playbackCommands.nextSong()
            if playbackViewModel.fmMode,
               let id = playbackViewModel.currentTrack?.id {
                let seconds = Int(playbackViewModel.playbackElapsedTime)
                pc.api.radioSkip(id, seconds).done {
                    Log.info("Song skipped, id: \(id) seconds: \(seconds)")
                }.catch {
                    Log.error($0)
                }
            }
        case muteButton:
            let mute = !player.isMuted
            playbackCommands.setMuted(mute)
            initVolumeButton()
        case repeatModeButton:
            switch preferences.repeatMode {
            case .noRepeat:
                preferences.repeatMode = .repeatPlayList
            case .repeatPlayList:
                preferences.repeatMode = .repeatItem
            case .repeatItem:
                preferences.repeatMode = .noRepeat
            }
            initPlayModeButton()
        case shuffleModeButton:
            switch preferences.shuffleMode {
            case .noShuffle:
                preferences.shuffleMode = .shuffleItems
            case .shuffleItems:
                preferences.shuffleMode = .noShuffle
            case .shuffleAlbums:
                break
            }
            initPlayModeButton()
        case trackPicButton:
            NotificationCenter.default.post(name: .showPlayingSong, object: nil)
        default:
            break
        }
    }
    
    @IBOutlet weak var durationSlider: PlayerSlider!
    @IBOutlet weak var durationTextField: NSTextField!
    @IBOutlet weak var volumeSlider: NSSlider!
    
    @IBAction func sliderAction(_ sender: NSSlider) {
        switch sender {
        case durationSlider:
            let time = CMTime(seconds: sender.doubleValue, preferredTimescale: 1000)
            playbackCommands.seek(to: time)
            if let eventType = NSApp.currentEvent?.type,
                eventType == .leftMouseUp {
                durationSlider.ignoreValueUpdate = false
            }
        case volumeSlider:
            let v = volumeSlider.floatValue
            playbackCommands.setVolume(v)
            initVolumeButton()
        default:
            break
        }
    }
    
    var playProgressObserver: NSKeyValueObservation?
    var pauseStautsObserver: NSKeyValueObservation?
    var previousButtonObserver: NSKeyValueObservation?
    var currentTrackObserver: NSKeyValueObservation?
    var fmModeObserver: NSKeyValueObservation?
    var volumeChangedNotification: NSObjectProtocol?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureTahoeAppearance()
        applySymbolImages()
        
        let pc = PlayCore.shared
        initVolumeButton()
        
        
        trackPicButton.wantsLayer = true
        trackPicButton.layer?.cornerRadius = 4
        
        trackNameTextField.stringValue = ""
        trackSecondNameTextField.stringValue = ""
        artistButtonsViewController()?.removeAllButtons()
        
        initPlayModeButton()
        
        playProgressObserver = playbackViewModel.observe(\.playProgress, options: [.initial, .new]) { [weak self] viewModel, _ in
            guard let slider = self?.durationSlider,
                  let textFiled = self?.durationTextField else { return }
            let player = pc.player
            guard player.currentItem != nil,
                  viewModel.currentTrack != nil else {
                slider.maxValue = 1
                slider.doubleValue = 0
                slider.cachedDoubleValue = 0
                textFiled.stringValue = "00:00 / 00:00"
                return
            }
            
            let cd = viewModel.playbackElapsedTime
            let td = viewModel.playbackDuration
            
            if td != slider.maxValue {
                slider.maxValue = td
            }
            slider.updateValue(cd)
            slider.cachedDoubleValue = max(0, player.currentBufferDuration)
            
            textFiled.stringValue = "\(cd.durationFormatter()) / \(td.durationFormatter())"
        }
        
        pauseStautsObserver = playbackViewModel.observe(\.playerState, options: [.initial, .new]) { [weak self] viewModel, _ in
            guard let btn = self?.pauseButton else { return }
            if #available(macOS 11.0, *) {
                let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
                let symbol = viewModel.playerState == .playing ? "pause.fill" : "play.fill"
                btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            } else {
                let name = viewModel.playerState == .playing ? "pause.circle.Light-L" : "play.circle.Light-L"
                btn.image = NSImage(named: .init(name))
            }
            btn.contentTintColor = .labelColor
        }
        
        previousButtonObserver = playbackViewModel.observe(\.pnItemType, options: [.initial, .new]) { [weak self] viewModel, _ in
            
            self?.previousButton.isEnabled = true
            self?.nextButton.isEnabled = true
            
            switch viewModel.pnItemType {
            case .withoutNext:
                self?.nextButton.isEnabled = false
            case .withoutPrevious:
                self?.previousButton.isEnabled = false
            case .withoutPreviousAndNext:
                self?.nextButton.isEnabled = false
                self?.previousButton.isEnabled = false
            case .other:
                break
            }
            
        }
        
        currentTrackObserver = playbackViewModel.observe(\.currentTrack, options: [.initial, .new]) { [weak self] viewModel, _ in
            self?.initViews(viewModel.currentTrack)
        }
        
        fmModeObserver = playbackViewModel.observe(\.fmMode, options: [.initial, .new]) { [weak self] viewModel, _ in
            let fmMode = viewModel.fmMode
            self?.previousButton.isHidden = fmMode
            self?.repeatModeButton.isHidden = fmMode
            self?.shuffleModeButton.isHidden = fmMode
        }
        
        volumeChangedNotification = NotificationCenter.default.addObserver(forName: .volumeChanged, object: nil, queue: .main) { _ in
            self.initVolumeButton()
        }
        
        if durationSlider.trackingAreas.isEmpty {
            durationSlider.addTrackingArea(NSTrackingArea(rect: durationSlider.frame, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: ["obj": 0]))
        }
    }
    
    
    func initViews(_ track: Track?) {
        if let t = track {
            trackPicButton.setImage(t.album.picUrl?.absoluteString, true)
            trackNameTextField.stringValue = t.name
            let subtitle = controlBarSubtitle(for: t)
            trackSecondNameTextField.isHidden = subtitle.isEmpty
            trackSecondNameTextField.stringValue = subtitle
            artistButtonsViewController()?.removeAllButtons()
            durationTextField.isHidden = false
        } else {
            trackPicButton.image = nil
            trackNameTextField.stringValue = ""
            trackSecondNameTextField.stringValue = ""
            artistButtonsViewController()?.removeAllButtons()
            durationTextField.isHidden = true
        }
        
        durationSlider.maxValue = 1
        durationSlider.doubleValue = 0
        durationSlider.cachedDoubleValue = 0
        durationTextField.stringValue = "00:00 / 00:00"
        
        durationSlider.mouseResponse = !durationTextField.isHidden
    }

    private func controlBarSubtitle(for track: Track) -> String {
        let artists = track.artists.map(\.name).joined(separator: " / ")
        return artists.isEmpty ? track.secondName : artists
    }

    private func configureTahoeAppearance() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        if let box = view.subviews.compactMap({ $0 as? NSBox }).first {
            box.isTransparent = true
            box.borderType = .noBorder
            box.boxType = .custom
            box.fillColor = .clear
        }
        
        if view.subviews.first(where: { $0.identifier?.rawValue == "TahoeControlBarBackground" }) == nil {
            let effectView = NSVisualEffectView(frame: view.bounds)
            effectView.identifier = NSUserInterfaceItemIdentifier("TahoeControlBarBackground")
            effectView.autoresizingMask = [.width, .height]
            effectView.material = .hudWindow
            effectView.blendingMode = .withinWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = 18
            effectView.layer?.borderWidth = 1
            effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            effectView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.2).cgColor
            effectView.layer?.shadowOpacity = 1
            effectView.layer?.shadowRadius = 18
            effectView.layer?.shadowOffset = CGSize(width: 0, height: -2)
            if #available(macOS 10.15, *) {
                effectView.layer?.cornerCurve = .continuous
            }
            view.addSubview(effectView, positioned: .below, relativeTo: view.subviews.first)
        }
        
        durationSlider.controlSize = .small
        volumeSlider.controlSize = .small

        durationTextField.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        durationTextField.textColor = .tertiaryLabelColor
        durationTextField.alignment = .right
        trackNameTextField.font = .systemFont(ofSize: 13, weight: .semibold)
        trackNameTextField.textColor = .labelColor
        trackNameTextField.lineBreakMode = .byTruncatingTail
        trackSecondNameTextField.font = .systemFont(ofSize: 11, weight: .regular)
        trackSecondNameTextField.textColor = .secondaryLabelColor
        trackSecondNameTextField.lineBreakMode = .byTruncatingTail
        
        configureControlButton(previousButton, prominent: false)
        configureControlButton(nextButton, prominent: false)
        configureControlButton(pauseButton, prominent: true)
        configureControlButton(muteButton, prominent: false)
        configureControlButton(repeatModeButton, prominent: false)
        configureControlButton(shuffleModeButton, prominent: false)
        configureControlButton(playlistButton, prominent: false)
        configureTrailingControls()
        configureLeadingInformationRegion()
        rebalanceHorizontalLayout()
        
        trackPicButton.wantsLayer = true
        trackPicButton.layer?.cornerRadius = 9
        trackPicButton.layer?.masksToBounds = true
        trackPicButton.layer?.borderWidth = 1
        trackPicButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        trackPicButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        trackPicButton.layer?.shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        trackPicButton.layer?.shadowOpacity = 1
        trackPicButton.layer?.shadowRadius = 10
        trackPicButton.layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    private func applySymbolImages() {
        if #available(macOS 11.0, *) {
            let compact = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let prominent = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            previousButton.image = NSImage(systemSymbolName: "backward.fill", accessibilityDescription: nil)?.withSymbolConfiguration(compact)
            nextButton.image = NSImage(systemSymbolName: "forward.fill", accessibilityDescription: nil)?.withSymbolConfiguration(compact)
            pauseButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)?.withSymbolConfiguration(prominent)
            playlistButton.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)?.withSymbolConfiguration(compact)
            repeatModeButton.image = NSImage(systemSymbolName: "repeat", accessibilityDescription: nil)?.withSymbolConfiguration(compact)
            shuffleModeButton.image = NSImage(systemSymbolName: "shuffle", accessibilityDescription: nil)?.withSymbolConfiguration(compact)
        } else {
            playlistButton.image = NSImage(named: .init("music.note.list.Regular-M"))
        }
    }
    
    private func configureControlButton(_ button: NSButton, prominent: Bool) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = prominent ? 17 : 9
        if #available(macOS 10.15, *) {
            button.layer?.cornerCurve = .continuous
        }
        button.layer?.borderWidth = 1
        button.layer?.borderColor = prominent ? NSColor.white.withAlphaComponent(0.14).cgColor : NSColor.white.withAlphaComponent(0.06).cgColor
        button.layer?.backgroundColor = prominent
            ? NSColor.white.withAlphaComponent(0.1).cgColor
            : NSColor.white.withAlphaComponent(0.035).cgColor
        button.contentTintColor = prominent ? .labelColor : .secondaryLabelColor
    }

    private func configureTrailingControls() {
        firstAncestorStackView(of: playlistButton)?.alignment = .centerY
        [muteButton, repeatModeButton, shuffleModeButton, playlistButton].forEach {
            setSquareSize(26, for: $0)
        }
        setWidth(78, for: volumeSlider)
        setStackSpacing(8, for: volumeSlider)
        setStackSpacing(10, for: muteButton)
        setStackSpacing(14, for: playlistButton)
    }

    private func configureLeadingInformationRegion() {
        setSquareSize(34, for: trackPicButton)
        if let stack = firstAncestorStackView(of: trackNameTextField) {
            stack.spacing = 1
            stack.setHuggingPriority(.defaultLow, for: .horizontal)
            if stack.constraints.first(where: { $0.identifier == "ControlBarInfoMaxWidth" }) == nil {
                let width = stack.widthAnchor.constraint(lessThanOrEqualToConstant: 188)
                width.identifier = "ControlBarInfoMaxWidth"
                width.isActive = true
            }
        }
        if let artistContainer = artistButtonsViewController()?.view.superview {
            artistContainer.isHidden = true
            for constraint in artistContainer.constraints where constraint.firstAttribute == .width {
                constraint.constant = 0
            }
        }
        adjustSiblingSpacing(between: trackPicButton, and: trackNameTextField, to: 6)
    }

    private func rebalanceHorizontalLayout() {
        if let volumeStack = firstAncestorStackView(of: muteButton),
           let playModeStack = firstAncestorStackView(of: playlistButton),
           let contentView = volumeStack.superview {
            for constraint in contentView.constraints {
                if matches(constraint, first: playModeStack, firstAttribute: .trailing, second: contentView, secondAttribute: .trailing) {
                    constraint.constant = 18
                } else if matches(constraint, first: playModeStack, firstAttribute: .leading, second: volumeStack, secondAttribute: .trailing) {
                    constraint.constant = 14
                }
            }
        }
    }

    private func setSquareSize(_ size: CGFloat, for button: NSButton) {
        var hasWidthConstraint = false
        var hasHeightConstraint = false
        for constraint in button.constraints {
            switch constraint.firstAttribute {
            case .width:
                constraint.constant = size
                hasWidthConstraint = true
            case .height:
                constraint.constant = size
                hasHeightConstraint = true
            default:
                break
            }
        }
        if !hasWidthConstraint {
            button.widthAnchor.constraint(equalToConstant: size).isActive = true
        }
        if !hasHeightConstraint {
            button.heightAnchor.constraint(equalToConstant: size).isActive = true
        }
    }

    private func setWidth(_ width: CGFloat, for slider: NSSlider) {
        for constraint in slider.constraints where constraint.firstAttribute == .width {
            constraint.constant = width
        }
    }

    private func setStackSpacing(_ spacing: CGFloat, for view: NSView) {
        var current: NSView? = view
        while let candidate = current?.superview {
            if let stackView = candidate as? NSStackView {
                stackView.spacing = spacing
                return
            }
            current = candidate
        }
    }

    private func firstAncestorStackView(of view: NSView) -> NSStackView? {
        var current: NSView? = view
        while let candidate = current?.superview {
            if let stackView = candidate as? NSStackView {
                return stackView
            }
            current = candidate
        }
        return nil
    }

    private func adjustSiblingSpacing(between leftView: NSView, and rightView: NSView, to constant: CGFloat) {
        guard let container = leftView.superview else { return }
        for constraint in container.constraints where matches(constraint, first: rightView, firstAttribute: .leading, second: leftView, secondAttribute: .trailing) {
            constraint.constant = constant
        }
    }

    private func matches(_ constraint: NSLayoutConstraint,
                         first: AnyObject,
                         firstAttribute: NSLayoutConstraint.Attribute,
                         second: AnyObject,
                         secondAttribute: NSLayoutConstraint.Attribute) -> Bool {
        (constraint.firstItem === first &&
         constraint.firstAttribute == firstAttribute &&
         constraint.secondItem === second &&
         constraint.secondAttribute == secondAttribute) ||
        (constraint.firstItem === second &&
         constraint.firstAttribute == secondAttribute &&
         constraint.secondItem === first &&
         constraint.secondAttribute == firstAttribute)
    }

    
    func initVolumeButton() {
        let pc = PlayCore.shared
        let pref = Preferences.shared
        
        let volume = pref.volume
        volumeSlider.floatValue = volume
        pc.player.volume = volume
        
        let mute = pref.mute
        pc.player.isMuted = mute
        
        var imageName = ""
        var color = NSColor.secondaryLabelColor
        if mute {
            imageName = "speaker.slash"
            color = .systemGray
        } else {
            switch volume {
            case 0:
                imageName = "speaker"
                color = .systemGray
            case 0..<1/3:
                imageName = "speaker.wave.1"
            case 1/3..<2/3:
                imageName = "speaker.wave.2"
            case 2/3...1:
                imageName = "speaker.wave.3"
            default:
                imageName = "speaker"
            }
        }
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let symbolMap = [
                "speaker.slash": "speaker.slash.fill",
                "speaker": "speaker.slash",
                "speaker.wave.1": "speaker.wave.1.fill",
                "speaker.wave.2": "speaker.wave.2.fill",
                "speaker.wave.3": "speaker.wave.3.fill"
            ]
            muteButton.image = NSImage(systemSymbolName: symbolMap[imageName] ?? "speaker.wave.2.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        } else {
            imageName += ".Regular-M"
            muteButton.image = NSImage(named: .init(imageName))
        }
        muteButton.contentTintColor = color
    }
    
    func initPlayModeButton() {
        let pref = Preferences.shared
        
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let repeatSymbol = pref.repeatMode == .repeatItem ? "repeat.1" : "repeat"
            repeatModeButton.image = NSImage(systemSymbolName: repeatSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            shuffleModeButton.image = NSImage(systemSymbolName: "shuffle", accessibilityDescription: nil)?.withSymbolConfiguration(config)
            playlistButton.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        } else {
            var repeatImgName = pref.repeatMode == .repeatItem ? "repeat.1" : "repeat"
            repeatImgName += ".Regular-M"
            var shuffleImgName = "shuffle"
            shuffleImgName += ".Regular-M"
            repeatModeButton.image = NSImage(named: .init(repeatImgName))
            shuffleModeButton.image = NSImage(named: .init(shuffleImgName))
        }
        
        repeatModeButton.contentTintColor = pref.repeatMode == .noRepeat ? .systemGray : .labelColor
        shuffleModeButton.contentTintColor = pref.shuffleMode == .noShuffle ? .systemGray : .labelColor
        
        PlayCore.shared.updateRepeatShuffleMode()
    }
    
    func artistButtonsViewController() -> ArtistButtonsViewController? {
        let vc = children.compactMap {
            $0 as? ArtistButtonsViewController
        }.first
        return vc
    }
    
    deinit {
        playProgressObserver?.invalidate()
        pauseStautsObserver?.invalidate()
        previousButtonObserver?.invalidate()
//        muteStautsObserver?.invalidate()
        currentTrackObserver?.invalidate()
        fmModeObserver?.invalidate()
        
        if let n = volumeChangedNotification {
            NotificationCenter.default.removeObserver(n)
        }
        
    }
    
}

extension ControlBarViewController {
    
    override func mouseEntered(with event: NSEvent) {
        guard let userInfo = event.trackingArea?.userInfo as? [String: Int],
              userInfo["obj"] == 0 else {
            return
        }
        durationSlider.mouseIn = true
    }
    
    override func mouseExited(with event: NSEvent) {
        guard let userInfo = event.trackingArea?.userInfo as? [String: Int],
              userInfo["obj"] == 0 else {
            return
        }
        durationSlider.mouseIn = false
    }
    
}

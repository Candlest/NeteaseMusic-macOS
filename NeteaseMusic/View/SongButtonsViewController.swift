//
//  SongButtonsViewController.swift
//  NeteaseMusic
//
//  Created by xjbeta on 2019/7/21.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa

class SongButtonsViewController: NSViewController {
    private let playbackCommands = PlaybackCommands.shared
    private let playbackViewModel = PlaybackViewModel.shared
    @IBOutlet weak var loveButton: NSButton!
    @IBOutlet weak var subscribeButton: NSButton!
    @IBOutlet weak var deleteButton: NSButton!
    @IBOutlet weak var linkButton: NSButton!
    @IBOutlet weak var moreButton: NSButton!
    @IBOutlet var moreMenu: NSMenu!
    
    private var buttonTintColor: NSColor = .secondaryLabelColor
    private var destructiveTintColor: NSColor = .tertiaryLabelColor
    private var lovedTintColor: NSColor = .systemPink
    
    @IBAction func buttonsAction(_ sender: NSButton) {
        let id = trackId
        guard id > 0 else { return }
        let seconds = playbackViewModel.playbackElapsedTime
        let time = seconds.isNaN ? 25 : Int(seconds)
        switch sender {
        case loveButton:
            loveButton.isEnabled = false
            let loved = self.loved
            pc.api.like(id, !loved, time).done {
                self.checkLikeList()
            }.catch {
                Log.error("Like error \($0)")
            }
        case deleteButton:
            deleteButton.isEnabled = false
            pc.api.fmTrash(id: id, time).done {
                guard let vc = self.parent as? FMViewController,
                      let track = vc.fmPlaylist.enumerated().first(where: {
                        $0.element.id == id
                    }) else { return }
                
                let index = track.offset
                vc.fmPlaylist.remove(at: index)
                if self.playbackViewModel.fmMode {
                    self.playbackCommands.start(vc.fmPlaylist,
                                                id: track.element.id,
                                                enterFMMode: true)
                }
            }.ensure(on: .main) {
                self.deleteButton.isEnabled = true
            }.catch {
                Log.error("fmTrash error \($0)")
            }
        case moreButton:
            if let event = NSApp.currentEvent {
                NSMenu.popUpContextMenu(moreMenu, with: event, for: sender)
            }
        default:
            break
        }
    }
    
    let pc = PlayCore.shared
    var trackId = -1 {
        didSet {
            checkLikeList()
        }
    }
    
    var loved = false {
        didSet {
            initButtonImage(loveButton)
            updateButtonAppearance()
        }
    }
    
    var isFMView = true {
        didSet {
            deleteButton.isHidden = !isFMView
            moreButton.isHidden = !isFMView
            linkButton.isHidden = isFMView
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureTahoeAppearance()
        applySymbolImages()
        updateButtonAppearance()
    }
    
    func initButtonImage(_ button: NSButton) {
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            let symbolName: String
            switch button {
            case loveButton:
                symbolName = loved ? "heart.fill" : "heart"
            case subscribeButton:
                symbolName = "plus"
            case deleteButton:
                symbolName = "trash"
            case moreButton:
                symbolName = "ellipsis"
            case linkButton:
                symbolName = "link"
            default:
                return
            }
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            button.imagePosition = .imageOnly
            return
        }

        var name = ""
        switch button {
        case loveButton:
            name = loved ? "heart.circle.fill" : "heart.circle"
        case subscribeButton:
            name = "plus.circle"
        case deleteButton:
            name = "trash.circle"
        case moreButton:
            name = "ellipsis.circle"
        case linkButton:
            name = "link.circle"
        default:
            return
        }
        name += ".Thin-L"
        button.image = NSImage(named: .init(name))
    }
    
    func checkLikeList() {
        let id = trackId
        loved = false
        loveButton.isEnabled = false
        pc.api.likeList().done(on: .main) {
            guard id == self.trackId else { return }
            self.loved = $0.contains(id)
        }.ensure(on: .main) {
            self.loveButton.isEnabled = true
        }.catch {
            Log.error("likeList error \($0)")
        }
    }

    private func configureTahoeAppearance() {
        [loveButton, subscribeButton, deleteButton, linkButton, moreButton].forEach { button in
            guard let button else { return }
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.layer?.borderWidth = 0
            button.layer?.borderColor = NSColor.clear.cgColor
            button.contentTintColor = buttonTintColor
            if #available(macOS 10.15, *) {
                button.layer?.cornerCurve = .continuous
            }
        }
        
        deleteButton.contentTintColor = destructiveTintColor
    }

    private func applySymbolImages() {
        [loveButton, subscribeButton, deleteButton, linkButton, moreButton].forEach(initButtonImage)
    }

    private func updateButtonAppearance() {
        [loveButton, subscribeButton, deleteButton, linkButton, moreButton].forEach { button in
            guard let button else { return }
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.contentTintColor = buttonTintColor
        }
        loveButton.contentTintColor = loved ? lovedTintColor : buttonTintColor
        if loved {
            loveButton.layer?.backgroundColor = lovedTintColor.withAlphaComponent(0.16).cgColor
        }
        deleteButton.contentTintColor = destructiveTintColor
    }
    
    func applyImmersiveAppearance(buttonTintColor: NSColor, destructiveTintColor: NSColor, lovedTintColor: NSColor) {
        self.buttonTintColor = buttonTintColor
        self.destructiveTintColor = destructiveTintColor
        self.lovedTintColor = lovedTintColor
        updateButtonAppearance()
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let vc = segue.destinationController as? SongButtonsPopUpViewController {
            vc.loadPlaylists()
            vc.trackId = trackId
        }
    }
    
    @IBAction func copyLink(_ sender: Any) {
        let str = "https://music.163.com/song?id=\(trackId)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([str as NSString])
    }
    
    @IBAction func trash(_ sender: Any) {
        ViewControllerManager.shared.selectSidebarItem(.fmTrash)
    }
    
}

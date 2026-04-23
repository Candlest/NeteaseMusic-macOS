//
//  TrackTableViewController.swift
//  NeteaseMusic
//
//  Created by xjbeta on 2019/12/11.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa

class TrackTableViewController: NSViewController {
    private let playbackCommands = PlaybackCommands.shared
    private let playbackViewModel = PlaybackViewModel.shared

    @IBOutlet weak var scrollView: UnresponsiveScrollView!
    @IBOutlet weak var tableView: NSTableView!
    
    @IBAction func doubleAction(_ sender: NSTableView) {
        let clickedRow = sender.clickedRow
        guard let track = tracks[safe: clickedRow] else { return }
        playbackCommands.start(tracks, id: track.id)
    }
    
    @objc dynamic var tracks = [Track]() {
        didSet {
            initCurrentTrack()
        }
    }
    var playlistId = -1
    var playlistType: SidebarViewController.ItemType = .none {
        didSet {
            initTableColumn()
        }
    }
    
    var currentTrackObserver: NSKeyValueObservation?
    var playerStateObserver: NSKeyValueObservation?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.responsiveScrolling = true
        tableView.delegate = self
        tableView.selectionHighlightStyle = .none
        tableView.rowHeight = 30
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        initTableColumn()
        initObservers()
    }
    
    func initObservers() {
        currentTrackObserver?.invalidate()
        playerStateObserver?.invalidate()
        currentTrackObserver = playbackViewModel.observe(\.currentTrack, options: [.new, .initial]) { [weak self] _, _ in
            self?.initCurrentTrack()
        }
        
        playerStateObserver =  playbackViewModel.observe(\.playerState, options: [.new, .initial]) { [weak self] viewModel, _ in
            self?.tracks.first {
                $0.isCurrentTrack
                }?.isPlaying = viewModel.isCurrentTrackPlaying
        }
    }
    
    func initCurrentTrack() {
        tracks.filter {
            $0.isCurrentTrack
        }.forEach {
            $0.isCurrentTrack = false
        }
        
        guard let c = playbackViewModel.currentTrack else { return }

        let t = tracks.first {
            $0.from == c.from && $0.id == c.id
        }
        t?.isCurrentTrack = true
        t?.isPlaying = playbackViewModel.isCurrentTrackPlaying
    }
    
    func initTableColumn() {
        let albumMode = playlistType == .album
        tableView.tableColumn(withIdentifier: .init("PlaylistAlbum"))?.isHidden = albumMode
        tableView.tableColumn(withIdentifier: .init("PlaylistPop"))?.isHidden = !albumMode
    }
    
    func resetData() {
        tracks.removeAll()
    }
    
    deinit {
        currentTrackObserver?.invalidate()
        playerStateObserver?.invalidate()
    }
    
}

extension TrackTableViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        TahoeTableRowView()
    }
}

final class TahoeTableRowView: NSTableRowView {
    private var hover = false {
        didSet { needsDisplay = true }
    }
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        selectionHighlightStyle = .none
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        selectionHighlightStyle = .none
        wantsLayer = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        hover = true
    }

    override func mouseExited(with event: NSEvent) {
        hover = false
    }

    override func drawSelection(in dirtyRect: NSRect) {
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)

        let rect = bounds.insetBy(dx: 6, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)

        if isSelected {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.5).setFill()
            path.fill()
        } else if hover {
            NSColor.labelColor.withAlphaComponent(0.045).setFill()
            path.fill()
        }
    }
}

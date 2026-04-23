//
//  LyricViewController.swift
//  NeteaseMusic
//
//  Created by xjbeta on 2019/5/9.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa
import AVFoundation

class LyricViewController: NSViewController {
    private static let highlightLayerName = "LyricHighlightLayer"
    private static let highlightPulseAnimationKey = "LyricHighlightPulse"
    private let playbackViewModel = PlaybackViewModel.shared
    @IBOutlet weak var scrollView: NSScrollView!
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var textField: NSTextField!
    
    private var primaryTextColor: NSColor = .labelColor
    private var secondaryTextColor: NSColor = .secondaryLabelColor
    private var highlightTextColor: NSColor = .systemPink
    private var translationHighlightTextColor: NSColor = .systemPink
    private var currentLineBackgroundColor: NSColor = .white
    
    var mouseInLyric = false
    var autoScrollLyrics = true
    
    struct Lyricline {
        enum LyricType {
            case first, second, both
        }
        
        var stringF: String?
        var stringS: String?
        let time: LyricTime
        var type: LyricType
        var highlighted = false
    }
    var lyriclines = [Lyricline]()
    var currentLyricId = -1 {
        willSet {
            guard newValue != currentLyricId else { return }
            tableView.scrollToBeginningOfDocument(nil)
            
            if newValue == -1 {
                // reset views
                lyriclines.removeAll()
                tableView.reloadData()
            } else {
                getLyric(for: newValue)
            }
        }
    }
    
    // lyricOffset ms
    @objc dynamic var lyricOffset = 0
    
    var playProgressObserver: NSKeyValueObservation?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        textField.isHidden = true
        tableView.refusesFirstResponder = true
        configureImmersiveAppearance()
        

        initTrackingArea()
    }
    
    
    
    func updateLyric(_ time: Double) {
        var periodicMS = Int(time * 1000)
        periodicMS += lyricOffset

        guard let line = lyriclines.filter({ $0.time.totalMS < periodicMS }).last else {
            return
        }
        let lins = lyriclines.enumerated().filter({ $0.element.time == line.time }).filter({ !($0.element.stringF ?? "").isEmpty })
        guard lins.count > 0 else { return }

        var offsets = lins.map({ $0.offset })

        lyriclines.enumerated().forEach {
            lyriclines[$0.offset].highlighted = offsets.contains($0.offset)
            if $0.element.highlighted, !offsets.contains($0.offset) {
                offsets.append($0.offset)
            }
        }
        let indexSet = IndexSet(offsets)
        tableView.reloadData(forRowIndexes: indexSet, columnIndexes: .init(integer: 0))
        DispatchQueue.main.async { [weak self] in
            self?.applyVisibleLyricFocusEffects(animated: true)
        }
        guard let i = offsets.first, autoScrollLyrics else { return }

        let frame = tableView.frameOfCell(atColumn: 0, row: i)
        let y = frame.midY - scrollView.frame.height / 2
        NSAnimationContext.runAnimationGroup { [weak self] (context) in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            self?.tableView.animator().scroll(.init(x: 0, y: y))
        } completionHandler: { [weak self] in
            self?.applyVisibleLyricFocusEffects(animated: true)
        }
    }
    
    func getLyric(for id: Int) {
        PlayCore.shared.api.lyric(id).map {
            guard self.currentLyricId == id else { return }
            self.initLyric(lyric: $0)
            }.done(on: .main) {
                self.tableView.reloadData()
                self.applyVisibleLyricFocusEffects(animated: false)
            }.catch {
                Log.error($0)
        }
    }
    
    func initLyric(lyric: LyricResult) {
        lyriclines.removeAll()
        textField.isHidden = true
        if let nolyric = lyric.nolyric, nolyric {
            textField.isHidden = false
            textField.stringValue = "no lyric"
        } else if let uncollected = lyric.uncollected, uncollected {
            textField.isHidden = false
            textField.stringValue = "uncollected"
        } else {
            if let lyricStr = lyric.lrc?.lyric {
                let linesF = Lyric(lyricStr).lyrics.map {
                    Lyricline(stringF: $0.1, stringS: nil, time: $0.0, type: .first)
                }
                lyriclines.append(contentsOf: linesF)
            }
            
            Lyric(lyric.tlyric?.lyric ?? "").lyrics.forEach { l in
                if let i = lyriclines.enumerated().first(where: { $0.element.time == l.0 })?.offset {
                    lyriclines[i].type = .both
                    lyriclines[i].stringS = l.1
                } else if !l.1.isEmpty {
                    let line = Lyricline(stringF: nil, stringS: l.1, time: l.0, type: .second)
                    lyriclines.append(line)
                }
            }
        }
        
        lyriclines.sort {
            return $0.type == .first && $1.type == .second
        }
        
        lyriclines.sort {
            return $0.time.totalMS < $1.time.totalMS
        }
    }
    
    func addPlayProgressObserver() {
        guard playProgressObserver == nil else { return }
        playProgressObserver = playbackViewModel.observe(\.playProgress, options: [.initial, .new]) { [weak self] viewModel, _ in
            let time = viewModel.playbackElapsedTime
            self?.updateLyric(time)
        }
    }
    
    func removePlayProgressObserver() {
        playProgressObserver?.invalidate()
        playProgressObserver = nil
    }
    
    func applyImmersiveAppearance(
        primaryTextColor: NSColor,
        secondaryTextColor: NSColor,
        highlightTextColor: NSColor,
        translationHighlightTextColor: NSColor
    ) {
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.highlightTextColor = highlightTextColor
        self.translationHighlightTextColor = translationHighlightTextColor
        self.currentLineBackgroundColor = highlightTextColor.withAlphaComponent(0.16)
        textField.textColor = primaryTextColor
        tableView.reloadData()
    }
    
    private func configureImmersiveAppearance() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        textField.textColor = primaryTextColor
        textField.font = .systemFont(ofSize: 19, weight: .semibold)
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.enclosingScrollView?.drawsBackground = false
        view.subviews.compactMap { $0 as? NSBox }.forEach { $0.isHidden = true }
    }
    
    func initTrackingArea() {
        scrollView.addTrackingArea(.init(
            rect: scrollView.bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .mouseMoved],
            owner: self,
            userInfo: nil))
        
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewDidScroll(_:)), name: NSScrollView.didLiveScrollNotification, object: scrollView)
        
    }
    
    override func mouseEntered(with event: NSEvent) {
        mouseInLyric = true
    }
    
    override func mouseExited(with event: NSEvent) {
        mouseInLyric = false
        autoScrollLyrics = true
        let time = playbackViewModel.playbackElapsedTime
        updateLyric(time)
    }
    
    
    @objc func scrollViewDidScroll(_ notification: Notification) {
        guard let sv = notification.object as? NSScrollView,
              sv == scrollView else {
                  return
              }
        
        if mouseInLyric,
           autoScrollLyrics {
            autoScrollLyrics = false
        }
        applyVisibleLyricFocusEffects(animated: false)
    }
    
}


extension LyricViewController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return lyriclines.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let line = lyriclines[safe: row] else { return nil }
        let sStr = line.stringS ?? ""
        
        let fSize = line.highlighted ? 19 : 17
        let sSize = line.highlighted ? 14 : 13
        
        let fColor = line.highlighted ? highlightTextColor : primaryTextColor
        let sColor = line.highlighted ? translationHighlightTextColor : secondaryTextColor
        
        return ["firstString": line.stringF ?? "",
                "firstSize": fSize,
                "firstColor": fColor,
                "secondString": sStr,
                "secondSize": sSize,
                "secondColor": sColor,
                "hideSecond": sStr.isEmpty]
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let cellView = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier("LyricCellView"),
            owner: self
        ) as? NSTableCellView,
        let line = lyriclines[safe: row] else {
            return nil
        }
        
        let primaryField = cellView.subviews
            .compactMap { $0 as? NSStackView }
            .flatMap(\.arrangedSubviews)
            .first { $0.identifier?.rawValue == "PrimaryLyricField" } as? NSTextField
        let secondaryField = cellView.subviews
            .compactMap { $0 as? NSStackView }
            .flatMap(\.arrangedSubviews)
            .first { $0.identifier?.rawValue == "SecondaryLyricField" } as? NSTextField
        
        let isHighlighted = line.highlighted
        let primaryFont = NSFont.systemFont(
            ofSize: isHighlighted ? 24 : 17,
            weight: isHighlighted ? .bold : .medium
        )
        let secondaryFont = NSFont.systemFont(
            ofSize: isHighlighted ? 16 : 13,
            weight: isHighlighted ? .semibold : .regular
        )
        primaryField?.stringValue = line.stringF ?? ""
        primaryField?.font = primaryFont
        primaryField?.textColor = isHighlighted
            ? highlightTextColor
            : primaryTextColor.withAlphaComponent(0.76)
        primaryField?.maximumNumberOfLines = 3
        
        let secondaryText = line.stringS ?? ""
        secondaryField?.isHidden = secondaryText.isEmpty
        secondaryField?.stringValue = secondaryText
        secondaryField?.font = secondaryFont
        secondaryField?.textColor = isHighlighted
            ? translationHighlightTextColor
            : secondaryTextColor.withAlphaComponent(0.58)
        secondaryField?.maximumNumberOfLines = 2
        
        cellView.wantsLayer = true
        cellView.layer?.backgroundColor = NSColor.clear.cgColor
        configureHighlightLayer(in: cellView, highlighted: isHighlighted)
        applyFocusEffect(to: cellView, row: row, animated: false)
        return cellView
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }
    
    private func configureHighlightLayer(in cellView: NSTableCellView, highlighted: Bool) {
        let highlightLayer: CALayer
        if let existing = cellView.layer?.sublayers?.first(where: { $0.name == Self.highlightLayerName }) {
            highlightLayer = existing
        } else {
            let layer = CALayer()
            layer.name = Self.highlightLayerName
            layer.cornerRadius = 18
            layer.zPosition = -1
            cellView.layer?.insertSublayer(layer, at: 0)
            highlightLayer = layer
        }
        
        let insetX: CGFloat = 0
        let insetY: CGFloat = 2
        highlightLayer.frame = cellView.bounds.insetBy(dx: insetX, dy: insetY)
        highlightLayer.backgroundColor = currentLineBackgroundColor.cgColor
        highlightLayer.shadowColor = highlightTextColor.withAlphaComponent(0.42).cgColor
        highlightLayer.shadowOpacity = highlighted ? 1 : 0
        highlightLayer.shadowRadius = highlighted ? 24 : 0
        highlightLayer.shadowOffset = .zero
        highlightLayer.opacity = highlighted ? 1 : 0
        
        if highlighted {
            if highlightLayer.animation(forKey: Self.highlightPulseAnimationKey) == nil {
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 0.72
                pulse.toValue = 1.0
                pulse.duration = 1.6
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                highlightLayer.add(pulse, forKey: Self.highlightPulseAnimationKey)
            }
        } else {
            highlightLayer.removeAnimation(forKey: Self.highlightPulseAnimationKey)
        }
    }
    
    private func applyVisibleLyricFocusEffects(animated: Bool) {
        let rows = tableView.rows(in: scrollView.documentVisibleRect)
        guard rows.length > 0 else { return }
        for row in rows.location..<(rows.location + rows.length) {
            guard let cellView = tableView.view(
                atColumn: 0,
                row: row,
                makeIfNecessary: false
            ) as? NSTableCellView else {
                continue
            }
            applyFocusEffect(to: cellView, row: row, animated: animated)
        }
    }
    
    private func applyFocusEffect(to cellView: NSTableCellView, row: Int, animated: Bool) {
        let rowFrame = tableView.rect(ofRow: row)
        let visibleRect = scrollView.documentVisibleRect
        let visibleMidY = visibleRect.midY
        let distance = abs(rowFrame.midY - visibleMidY)
        let normalized = min(distance / max(visibleRect.height * 0.42, 1), 1)
        let line = lyriclines[safe: row]
        let isHighlighted = line?.highlighted == true
        
        let targetOpacity: Float = isHighlighted ? 1 : Float(1 - normalized * 0.7)
        let targetScale = isHighlighted ? 1.0 : (1 - normalized * 0.12)
        let direction: CGFloat = rowFrame.midY < visibleMidY ? 1 : -1
        let targetTranslation = isHighlighted ? 0 : normalized * 10 * direction
        let glowOpacity: Float = isHighlighted
            ? 1
            : Float(max(0, 0.16 - normalized * 0.16))
        
        cellView.wantsLayer = true
        let transform = CATransform3DConcat(
            CATransform3DMakeScale(targetScale, targetScale, 1),
            CATransform3DMakeTranslation(0, targetTranslation, 0)
        )
        
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            cellView.layer?.opacity = targetOpacity
            cellView.layer?.transform = transform
            cellView.layer?.sublayers?
                .first(where: { $0.name == Self.highlightLayerName })?
                .opacity = glowOpacity
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cellView.layer?.opacity = targetOpacity
            cellView.layer?.transform = transform
            cellView.layer?.sublayers?
                .first(where: { $0.name == Self.highlightLayerName })?
                .opacity = glowOpacity
            CATransaction.commit()
        }
    }
}

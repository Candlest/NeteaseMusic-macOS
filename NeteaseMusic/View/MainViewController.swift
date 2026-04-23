//
//  MainViewController.swift
//  NeteaseMusic
//
//  Created by xjbeta on 2019/4/9.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa
import PromiseKit

class MainViewController: NSViewController {
    private let playbackViewModel = PlaybackViewModel.shared
    private let navigationAnimationDuration: TimeInterval = 0.34
    @IBOutlet weak var mainTabView: NSTabView!
    @IBOutlet weak var contentTabView: NSTabView!
    @IBOutlet weak var playingSongTabView: NSTabView!
    enum ContentTabItems: Int {
        case loading, playlist, fm, preferences, discover, favourite, search, artist, mySubscription
    }
    enum MainTabItems: Int {
        case main, login
    }
    
    enum playingSongTabItems: Int {
        case main, playingSong
    }
    
    @IBOutlet weak var playingSongView: NSView!
    @IBOutlet weak var messageBox: NSBox!
    @IBOutlet weak var messageTextField: NSTextField!
    private var messageID = ""
    private var lastContentTabItem: ContentTabItems?
    private var lastPlayingSongTabItem: playingSongTabItems = .main
    
    var sidebarItemObserver: NSKeyValueObservation?
    var playlistNotification: NSObjectProtocol?
    var playingSongNotification: NSObjectProtocol?
    var displayMessageNotification: NSObjectProtocol?
    var playingSongViewStatus: ExtendedViewState = .hidden {
        didSet {
            NotificationCenter.default.post(name: .playingSongViewStatus, object: nil, userInfo: ["status": playingSongViewStatus])
        }
    }
    
// MARK: - Loading Tab
    @IBOutlet var loadingTabView: NSTabView!
    enum loadingTabItems: Int {
        case loading, tryAgain
    }
    
    @IBOutlet var loadingProgressIndicator: NSProgressIndicator!
    
    @IBAction func loadingTryAgain(_ sender: NSButton) {
        guard let item = ViewControllerManager.shared.selectedSidebarItem else {
            return
        }

        sender.isEnabled = false
        
        let napi = PlayCore.shared.api
        napi.nuserAccount().get {
            if let id = $0?.userId {
                self.updateContentTabView(item)
                NotificationCenter.default.post(name: .initSidebarPlaylists, object: nil)
            } else {
                throw NeteaseMusicAPI.RequestError.errorCode((301, ""))
            }
        }.ensure(on: .main) {
            sender.isEnabled = true
        }.catch {
            Log.error($0)
        }
    }
    
// MARK: - viewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        sidebarItemObserver = ViewControllerManager.shared.observe(\.selectedSidebarItem, options: [.initial, .new]) { vcm, _ in
            
            guard let item = vcm.selectedSidebarItem else {
                return
            }
            
            DispatchQueue.main.async {
                self.updateContentTabView(item)
            }
        }
        
        playingSongNotification = NotificationCenter.default.addObserver(forName: .showPlayingSong, object: nil, queue: .main) { [weak self] _ in
            if self?.playbackViewModel.fmMode == true,
               self?.playbackViewModel.currentTrack != nil {
                ViewControllerManager.shared.selectSidebarItem(.fm)
            } else if self?.playbackViewModel.fmMode == false,
                      self?.playbackViewModel.currentTrack != nil,
                      let playingSongViewStatus = self?.playingSongViewStatus {
                
                let newItem: playingSongTabItems = playingSongViewStatus == .hidden ? .playingSong : .main
                self?.updatePlayingSongTabView(newItem)
                self?.playingSongViewStatus = newItem == .playingSong ? .display : .hidden
            }
        }
        
        displayMessageNotification = NotificationCenter.default.addObserver(forName: .displayMessage, object: nil, queue: .main) {
            guard let kv = $0.userInfo as? [String: Any],
                let message = kv["message"] as? String else {
                return
            }
            self.showMessage(message)
        }
    }
    
    func showMessage(_ str: String) {
        let id = UUID().uuidString
        messageTextField.stringValue = str
        if messageID == "" {
            messageBox.alphaValue = 0
            messageBox.isHidden = false
            messageBox.animator().alphaValue = 1
        }
        messageID = id
        Log.info("Display message \(str)")
        after(seconds: 3).done {
            guard id == self.messageID else { return }
            Log.info("Hide message box")
            self.messageBox.animator().alphaValue = 0
            self.messageID = ""
        }
    }
    
    func updateMainTabView(_ item: MainTabItems) {
        mainTabView.selectTabViewItem(at: item.rawValue)
    }
    
    func updateContentTabView(_ item: SidebarViewController.SidebarItem) {
        
        var ctItem: ContentTabItems = .loading
        
        switch item.type {
        case .discover:
            ctItem = .discover
        case .fm:
            ctItem = .fm
        case .mySubscription:
            ctItem = .mySubscription
        case .subscribedPlaylist, .createdPlaylist, .favourite, .discoverPlaylist, .album, .topSongs, .fmTrash:
            ctItem = .playlist
        case .artist:
            ctItem = .artist
        case .preferences:
            ctItem = .preferences
        case .searchSuggestionHeaderSongs,
             .searchSuggestionHeaderAlbums,
             .searchSuggestionHeaderArtists,
             .searchSuggestionHeaderPlaylists:
            ctItem = .search
        default:
            break
        }
        
        
        guard let vc = contentTabVC(ctItem) else {
            transitionContentTab(to: ctItem, style: .content)
            return
        }
        
        
        loadingTabView.selectTabViewItem(at: loadingTabItems.loading.rawValue)
        loadingProgressIndicator.startAnimation(nil)
        transitionContentTab(to: .loading, style: .loading)
        
        vc.initContent().ensure {
            self.loadingProgressIndicator.stopAnimation(nil)
        }.done(on:.main) {
            self.transitionContentTab(to: ctItem, style: .content)
            Log.info("\(ctItem) \(item.id) Content inited.")
        }.catch {
            Log.error("\(ctItem) \(item.id) Content init failed.  \($0)")
            self.loadingTabView.selectTabViewItem(at: loadingTabItems.tryAgain.rawValue)
            self.transitionContentTab(to: .loading, style: .retry)
        }
    }
    
    func currentContentTabVC() -> ContentTabViewController? {
        guard let item = contentTabView.selectedTabViewItem else {
                  return nil
              }
        let index = contentTabView.indexOfTabViewItem(item)
        guard let ctItem = ContentTabItems(rawValue: index) else {
            return nil
        }
        return contentTabVC(ctItem)
    }
    
    func contentTabVC(_ item: ContentTabItems) -> ContentTabViewController? {
        children.compactMap {
            $0 as? ContentTabViewController
        }.first {
//            case playlist, fm, preferences, discover, favourite, search, artist, mySubscription
            switch item {
            case .playlist:
                return $0 is PlaylistViewController
            case .fm:
                return $0 is FMViewController
            case .discover:
                return $0 is DiscoverViewController
            case .search:
                return $0 is SearchResultViewController
            case .artist:
                return $0 is ArtistViewController
            case .mySubscription:
                return $0 is SublistViewController
            case .preferences:
                return $0 is PreferencesViewController
            default:
                return false
            }
        }
    }
    
    func updatePlayingSongTabView(_ item: playingSongTabItems) {
        transitionTabView(playingSongTabView,
                          to: item.rawValue,
                          previousRawValue: lastPlayingSongTabItem.rawValue,
                          style: item == .playingSong ? .immersive : .content)
        lastPlayingSongTabItem = item
    }
    
    private enum TabTransitionStyle {
        case loading
        case content
        case retry
        case immersive
    }
    
    private func transitionContentTab(to item: ContentTabItems, style: TabTransitionStyle) {
        transitionTabView(contentTabView,
                          to: item.rawValue,
                          previousRawValue: lastContentTabItem?.rawValue,
                          style: style)
        lastContentTabItem = item
    }
    
    private func transitionTabView(_ tabView: NSTabView,
                                   to index: Int,
                                   previousRawValue: Int?,
                                   style: TabTransitionStyle) {
        guard tabView.numberOfTabViewItems > index,
              index >= 0 else {
            return
        }
        
        let selectedIndex = previousRawValue ?? tabView.indexOfTabViewItem(tabView.selectedTabViewItem ?? NSTabViewItem())
        let shouldAnimate = view.window != nil && selectedIndex != index
        
        if shouldAnimate {
            let transition = CATransition()
            transition.type = .push
            transition.duration = navigationAnimationDuration
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            transition.fillMode = .both
            transition.isRemovedOnCompletion = true
            transition.subtype = transitionSubtype(from: selectedIndex, to: index, style: style)
            transition.startProgress = style == .immersive ? 0.08 : 0
            transition.endProgress = style == .loading ? 0.86 : 1
            tabView.wantsLayer = true
            tabView.layer?.add(transition, forKey: "tabTransition")
        }
        
        tabView.selectTabViewItem(at: index)
        
        guard shouldAnimate,
              let destinationView = tabView.selectedTabViewItem?.view else {
            return
        }
        
        animateTabPresentation(destinationView, style: style)
    }
    
    private func animateTabPresentation(_ destinationView: NSView, style: TabTransitionStyle) {
        destinationView.wantsLayer = true
        let direction: CGFloat
        let startScale: CGFloat
        let startOpacity: Float
        
        switch style {
        case .loading:
            direction = 10
            startScale = 0.995
            startOpacity = 0.0
        case .retry:
            direction = -8
            startScale = 0.992
            startOpacity = 0.18
        case .immersive:
            direction = 22
            startScale = 1.01
            startOpacity = 0.0
        case .content:
            direction = 16
            startScale = 0.986
            startOpacity = 0.08
        }
        
        destinationView.alphaValue = 0.84
        destinationView.layer?.opacity = startOpacity
        destinationView.layer?.transform = CATransform3DMakeScale(startScale, startScale, 1)
        destinationView.layer?.sublayerTransform = CATransform3DMakeTranslation(0, direction, 0)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = navigationAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            destinationView.animator().alphaValue = 1
        }
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = startOpacity
        opacityAnimation.toValue = 1
        
        let transformAnimation = CABasicAnimation(keyPath: "transform")
        transformAnimation.fromValue = CATransform3DMakeScale(startScale, startScale, 1)
        transformAnimation.toValue = CATransform3DIdentity
        
        let translationAnimation = CABasicAnimation(keyPath: "sublayerTransform")
        translationAnimation.fromValue = CATransform3DMakeTranslation(0, direction, 0)
        translationAnimation.toValue = CATransform3DIdentity
        
        let group = CAAnimationGroup()
        group.animations = [opacityAnimation, transformAnimation, translationAnimation]
        group.duration = navigationAnimationDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        
        destinationView.layer?.opacity = 1
        destinationView.layer?.transform = CATransform3DIdentity
        destinationView.layer?.sublayerTransform = CATransform3DIdentity
        destinationView.layer?.add(group, forKey: "tabPresentation")
    }
    
    private func transitionSubtype(from previous: Int, to current: Int, style: TabTransitionStyle) -> CATransitionSubtype {
        switch style {
        case .immersive:
            return current > previous ? .fromTop : .fromBottom
        case .loading:
            return .fromTop
        case .retry:
            return .fromBottom
        case .content:
            return current >= previous ? .fromRight : .fromLeft
        }
    }
    
    deinit {
        sidebarItemObserver?.invalidate()
        if let obs = playlistNotification {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = playingSongNotification {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = displayMessageNotification {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}

//
//  PlayingSongViewController.swift
//  NeteaseMusic
//
//  Created by xjbeta on 2019/4/22.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa
import AVFoundation
import PromiseKit

class PlayingSongViewController: NSViewController {
    private static let backgroundTintLayerName = "PlayingArtworkTintLayer"
    private static let backgroundGlowLayerName = "PlayingArtworkGlowLayer"
    private static let backgroundScrimLayerName = "PlayingArtworkScrimLayer"
    private static let backgroundGlowPulseAnimationKey = "PlayingArtworkGlowPulse"
    private let playbackViewModel = PlaybackViewModel.shared
    private let ciContext = CIContext(options: nil)
    private let themeTransitionDuration: CFTimeInterval = 0.24
    private var backgroundArtworkImageView: NSImageView?
    private var backgroundOverlayView: NSView?
    @IBOutlet weak var visualEffectView: NSVisualEffectView?
    @IBOutlet weak var cdRunImageView: NSImageView?
    @IBOutlet weak var cdwarpImageView: NSImageView?
    @IBOutlet weak var cdImgImageView: NSImageView!
    
    @IBOutlet weak var lyricContainerView: NSView!
    @IBOutlet weak var offsetTextField: NSTextField!
    @IBOutlet weak var offsetUpButton: NSButton!
    @IBOutlet weak var offsetDownButton: NSButton!
    @IBAction func offset(_ sender: NSButton) {
        // 0.1s  0.5s
        let v = NSEvent.modifierFlags.contains(.option) ? 100 : 500

        switch sender {
        case offsetUpButton:
            lyricOffset -= v
        case offsetDownButton:
            lyricOffset += v
        default:
            break
        }
        
        let time = playbackViewModel.playbackElapsedTime
        lyricViewController()?.updateLyric(time)
    }
    
    // lyricOffset ms
    @objc dynamic var lyricOffset = 0 {
        didSet {
            lyricViewController()?.lyricOffset = lyricOffset
        }
    }
    
    var currentTrackObserver: NSKeyValueObservation?
    var playerStatueObserver: NSKeyValueObservation?
    var viewStatusObserver: NSObjectProtocol?
    var fmModeObserver: NSKeyValueObservation?
    var viewFrameObserver: NSKeyValueObservation?
    var viewStatus: ExtendedViewState = .unkonwn
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureTahoeAppearance()
        currentTrackObserver = playbackViewModel.observe(\.currentTrack, options: [.initial, .new]) { [weak self] _, _ in
            self?.initView()
        }
        
        playerStatueObserver = playbackViewModel.observe(\.playerState, options: [.initial, .new]) { [weak self] viewModel, _ in
            switch viewModel.playerState {
            case .playing:
                self?.cdwarpImageView?.resumeAnimation()
                self?.cdImgImageView.resumeAnimation()
                self?.updateCDRunImage()
            case .paused:
                self?.cdwarpImageView?.pauseAnimation()
                self?.cdImgImageView.pauseAnimation()
                self?.updateCDRunImage()
            default:
                break
            }
        }
        
        viewStatusObserver = NotificationCenter.default.addObserver(forName: .playingSongViewStatus, object: nil, queue: .main) { [weak self] in
            guard let dic = $0.userInfo as? [String: ExtendedViewState],
                let status = dic["status"] else {
                    self?.viewStatus = .unkonwn
                    return
            }
            self?.viewStatus = status
            
            switch status {
            case .display:
                self?.initView()
                after(seconds: 0.1).done {
                    self?.layoutArtworkCard()
                }
            default:
                self?.cdwarpImageView?.layer?.removeAllAnimations()
                self?.cdImgImageView.layer?.removeAllAnimations()
            }
        }
        
        fmModeObserver = playbackViewModel.observe(\.fmMode, options: [.initial, .new]) { [weak self] viewModel, _ in
            guard let vc = self?.lyricViewController() else { return }
            if !viewModel.fmMode {
                vc.addPlayProgressObserver()
            } else {
                vc.removePlayProgressObserver()
            }
        }
        
        viewFrameObserver = view.observe(\.frame, options: [.initial, .new]) { [weak self] (_, changes) in
            guard let status = self?.viewStatus, status == .display else { return }
            
            self?.installArtworkBackground()
            self?.layoutArtworkCard()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutArtworkBackground()
        layoutArtworkCard()
    }
    
    private func configureTahoeAppearance() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        makeRootChromeTransparent()
        visualEffectView?.material = .underWindowBackground
        visualEffectView?.blendingMode = .behindWindow
        visualEffectView?.state = .active
        installArtworkBackground()
        cdwarpImageView?.isHidden = true
        cdRunImageView?.isHidden = true
        
        lyricContainerView.wantsLayer = true
        lyricContainerView.layer?.cornerRadius = 24
        lyricContainerView.layer?.masksToBounds = false
        lyricContainerView.layer?.borderWidth = 0
        lyricContainerView.layer?.borderColor = NSColor.clear.cgColor
        lyricContainerView.layer?.backgroundColor = NSColor.clear.cgColor
        lyricContainerView.layer?.shadowColor = NSColor.clear.cgColor
        lyricContainerView.layer?.shadowOpacity = 1
        lyricContainerView.layer?.shadowRadius = 0
        lyricContainerView.layer?.shadowOffset = .zero
        if #available(macOS 10.15, *) {
            lyricContainerView.layer?.cornerCurve = .continuous
        }
        
        let artworkContainer = cdImgImageView.superview
        artworkContainer?.wantsLayer = true
        artworkContainer?.layer?.cornerRadius = 30
        artworkContainer?.layer?.backgroundColor = NSColor.clear.cgColor
        artworkContainer?.layer?.borderWidth = 0
        artworkContainer?.layer?.borderColor = NSColor.clear.cgColor
        artworkContainer?.layer?.shadowColor = NSColor.black.withAlphaComponent(0.28).cgColor
        artworkContainer?.layer?.shadowOpacity = 1
        artworkContainer?.layer?.shadowRadius = 48
        artworkContainer?.layer?.shadowOffset = CGSize(width: 0, height: -8)
        if #available(macOS 10.15, *) {
            artworkContainer?.layer?.cornerCurve = .continuous
        }
        
        cdImgImageView.wantsLayer = true
        cdImgImageView.layer?.masksToBounds = true
        cdImgImageView.layer?.cornerRadius = 24
        cdImgImageView.layer?.borderWidth = 0
        cdImgImageView.layer?.borderColor = NSColor.clear.cgColor
        layoutArtworkCard()
        
        offsetTextField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        offsetTextField.textColor = .secondaryLabelColor
        applySymbolImages()
        styleOffsetButton(offsetUpButton)
        styleOffsetButton(offsetDownButton)
        styleEmbeddedViews()
    }
    
    private func styleOffsetButton(_ button: NSButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.borderWidth = 0
        button.layer?.borderColor = NSColor.clear.cgColor
        button.contentTintColor = .labelColor
        if #available(macOS 10.15, *) {
            button.layer?.cornerCurve = .continuous
        }
    }

    private func makeRootChromeTransparent() {
        view.subviews.compactMap { $0 as? NSBox }.forEach {
            $0.isTransparent = true
            $0.borderType = .noBorder
            $0.boxType = .custom
            $0.fillColor = .clear
        }
        view.subviews.forEach { makeTransparent($0) }
    }

    private func makeTransparent(_ view: NSView) {
        if let box = view as? NSBox {
            box.isTransparent = true
            box.borderType = .noBorder
            box.boxType = .custom
            box.fillColor = .clear
        }
        if view !== lyricContainerView,
           view !== cdImgImageView,
           view !== cdImgImageView.superview,
           view.identifier?.rawValue != "PlayingArtworkBackground",
           view.identifier?.rawValue != "PlayingArtworkOverlay" {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
        }
        view.subviews.forEach { makeTransparent($0) }
    }

    private func applySymbolImages() {
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            offsetUpButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?.withSymbolConfiguration(config)
            offsetDownButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: nil)?.withSymbolConfiguration(config)
            offsetUpButton.imagePosition = .imageOnly
            offsetDownButton.imagePosition = .imageOnly
        }
    }
    
    private func installArtworkBackground() {
        let backgroundImageView: NSImageView
        if let existing = backgroundArtworkImageView {
            backgroundImageView = existing
        } else {
            backgroundImageView = NSImageView(frame: view.bounds)
            backgroundImageView.identifier = NSUserInterfaceItemIdentifier("PlayingArtworkBackground")
            backgroundImageView.autoresizingMask = [.width, .height]
            backgroundImageView.wantsLayer = true
            backgroundImageView.layer?.contentsGravity = .resizeAspectFill
            backgroundImageView.layer?.masksToBounds = true
            backgroundImageView.alphaValue = 1
            view.addSubview(backgroundImageView, positioned: .below, relativeTo: view.subviews.first)
            backgroundArtworkImageView = backgroundImageView
        }
        
        let overlayView: NSView
        if let existing = backgroundOverlayView {
            overlayView = existing
        } else {
            overlayView = NSView(frame: view.bounds)
            overlayView.identifier = NSUserInterfaceItemIdentifier("PlayingArtworkOverlay")
            overlayView.autoresizingMask = [.width, .height]
            overlayView.wantsLayer = true
            view.addSubview(overlayView, positioned: .above, relativeTo: backgroundImageView)
            backgroundOverlayView = overlayView
        }
        
        layoutArtworkBackground()
        installTahoeGradientBackground()
    }
    
    private func layoutArtworkBackground() {
        backgroundArtworkImageView?.frame = view.bounds
        backgroundOverlayView?.frame = view.bounds
        backgroundOverlayView?.layer?.sublayers?.forEach { $0.frame = view.bounds }
    }

    private func installTahoeGradientBackground(style: ArtworkBackgroundStyle? = nil) {
        guard let rootLayer = backgroundOverlayView?.layer ?? view.layer else { return }
        let resolvedStyle = style ?? ArtworkBackgroundStyle.default
        let tintLayer = ensureGradientLayer(
            named: Self.backgroundTintLayerName,
            on: rootLayer
        )
        let glowLayer = ensureGradientLayer(
            named: Self.backgroundGlowLayerName,
            on: rootLayer
        )
        let scrimLayer = ensureGradientLayer(
            named: Self.backgroundScrimLayerName,
            on: rootLayer
        )
        
        tintLayer.frame = view.bounds
        let tintColors = [
            resolvedStyle.primary.withAlphaComponent(0.92).cgColor,
            resolvedStyle.secondary.withAlphaComponent(0.78).cgColor
        ]
        applyAnimatedColors(tintColors, to: tintLayer)
        tintLayer.locations = [0, 1]
        tintLayer.startPoint = CGPoint(x: 0.0, y: 1.0)
        tintLayer.endPoint = CGPoint(x: 1.0, y: 0.12)
        
        glowLayer.frame = view.bounds
        if #available(macOS 10.14, *) {
            glowLayer.type = .radial
        }
        let glowColors = [
            resolvedStyle.secondary.withAlphaComponent(0.44).cgColor,
            resolvedStyle.primary.withAlphaComponent(0.16).cgColor,
            NSColor.clear.cgColor
        ]
        applyAnimatedColors(glowColors, to: glowLayer)
        glowLayer.locations = [0, 0.34, 1]
        glowLayer.startPoint = CGPoint(x: 0.22, y: 0.82)
        glowLayer.endPoint = CGPoint(x: 0.88, y: 0.1)
        if glowLayer.animation(forKey: Self.backgroundGlowPulseAnimationKey) == nil {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.82
            pulse.toValue = 1.0
            pulse.duration = 4.2
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glowLayer.add(pulse, forKey: Self.backgroundGlowPulseAnimationKey)
        }
        
        scrimLayer.frame = view.bounds
        let scrimColors = [
            NSColor.black.withAlphaComponent(0.12).cgColor,
            NSColor.black.withAlphaComponent(0.08).cgColor,
            resolvedStyle.shadow.withAlphaComponent(0.72).cgColor
        ]
        applyAnimatedColors(scrimColors, to: scrimLayer)
        scrimLayer.locations = [0, 0.5, 1]
        scrimLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        scrimLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
    }
    
    private func ensureGradientLayer(named name: String, on rootLayer: CALayer) -> CAGradientLayer {
        if let existing = rootLayer.sublayers?.first(where: { $0.name == name }) as? CAGradientLayer {
            return existing
        }
        let layer = CAGradientLayer()
        layer.name = name
        layer.zPosition = 0
        rootLayer.addSublayer(layer)
        return layer
    }
    
    private func applyAnimatedColors(_ colors: [CGColor], to layer: CAGradientLayer) {
        if let currentColors = layer.colors as? [CGColor], !currentColors.isEmpty {
            let animation = CABasicAnimation(keyPath: "colors")
            animation.fromValue = currentColors
            animation.toValue = colors
            animation.duration = themeTransitionDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "colors")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.colors = colors
        CATransaction.commit()
    }
    
    private func styleEmbeddedViews() {
        songInfoViewController()?.view.subviews.first?.alphaValue = 0.98
        if let buttonsView = songButtonsViewController()?.view {
            buttonsView.wantsLayer = true
            buttonsView.layer?.cornerRadius = 20
            if #available(macOS 10.15, *) {
                buttonsView.layer?.cornerCurve = .continuous
            }
            buttonsView.layer?.backgroundColor = NSColor.clear.cgColor
            buttonsView.layer?.borderWidth = 0
            buttonsView.layer?.borderColor = NSColor.clear.cgColor
        }
    }
    
    private func layoutArtworkCard() {
        let side = min(cdImgImageView.bounds.width, cdImgImageView.bounds.height)
        guard side > 0 else { return }
        cdImgImageView.layer?.cornerRadius = min(28, side * 0.1)
    }
    
    func initView() {
        guard let track = playbackViewModel.currentTrack else {
            cdImgImageView.image = nil
            backgroundArtworkImageView?.image = nil
            backgroundArtworkImageView?.layer?.contents = nil
            installTahoeGradientBackground()
            lyricViewController()?.currentLyricId = -1
            songButtonsViewController()?.trackId = -1
            return
        }
        
        if let u = track.album.picUrl {
            cdImgImageView.wantsLayer = true
            layoutArtworkCard()
            cdImgImageView.setImage(u.absoluteString, true)
            updateBackgroundArtwork(u.absoluteString)
        } else {
            cdImgImageView.image = nil
            backgroundArtworkImageView?.image = nil
            backgroundArtworkImageView?.layer?.contents = nil
            installTahoeGradientBackground()
        }

        songInfoViewController()?.initInfos(track)
        songButtonsViewController()?.trackId = track.id
        songButtonsViewController()?.isFMView = false
        lyricViewController()?.currentLyricId = track.id
        styleEmbeddedViews()
    }

    private func updateBackgroundArtwork(_ url: String) {
        ImageLoader.image(url, true, max(view.bounds.width, view.bounds.height) * 0.55) { [weak self] image in
            guard let self else { return }
            guard self.playbackViewModel.currentTrack?.album.picUrl?.absoluteString == url else { return }
            if let layer = self.backgroundArtworkImageView?.layer {
                let transition = CATransition()
                transition.type = .fade
                transition.duration = self.themeTransitionDuration
                transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(transition, forKey: "contents")
            }
            self.backgroundArtworkImageView?.layer?.contents = self.blurredBackgroundImage(from: image) ?? image
            if let image {
                let style = self.backgroundStyle(from: image)
                self.installTahoeGradientBackground(style: style)
                self.applyImmersiveForeground(style: style)
            } else {
                self.installTahoeGradientBackground()
                self.applyImmersiveForeground(style: .default)
            }
        }
    }

    private func blurredBackgroundImage(from image: NSImage?) -> NSImage? {
        guard let image,
              let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return nil
        }
        
        let clampFilter = CIFilter(name: "CIAffineClamp")
        clampFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        let clampedImage = clampFilter?.outputImage ?? ciImage
        
        let blurFilter = CIFilter(name: "CIGaussianBlur")
        blurFilter?.setValue(clampedImage, forKey: kCIInputImageKey)
        blurFilter?.setValue(56, forKey: kCIInputRadiusKey)
        
        let colorControls = CIFilter(name: "CIColorControls")
        colorControls?.setValue(blurFilter?.outputImage, forKey: kCIInputImageKey)
        colorControls?.setValue(1.28, forKey: kCIInputSaturationKey)
        colorControls?.setValue(0.1, forKey: kCIInputBrightnessKey)
        colorControls?.setValue(1.18, forKey: kCIInputContrastKey)
        
        guard let outputImage = colorControls?.outputImage?.cropped(to: ciImage.extent),
              let cgImage = ciContext.createCGImage(outputImage, from: ciImage.extent) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: image.size)
    }
    
    private func backgroundStyle(from image: NSImage) -> ArtworkBackgroundStyle {
        let seed = dominantArtworkColor(from: image) ?? ArtworkBackgroundStyle.default.primary
        let normalized = seed.normalizedArtworkSeed()
        return ArtworkBackgroundStyle(
            primary: normalized.shifted(hueBy: -0.035, saturationBy: 0.12, brightnessBy: -0.28),
            secondary: normalized.shifted(hueBy: -0.09, saturationBy: 0.06, brightnessBy: 0.12),
            shadow: normalized.shifted(hueBy: 0.025, saturationBy: -0.08, brightnessBy: -0.5)
        )
    }
    
    private func applyImmersiveForeground(style: ArtworkBackgroundStyle) {
        let averageBackground = style.primary.blended(withFraction: 0.55, of: style.secondary) ?? style.primary
        let luminance = averageBackground.relativeLuminance
        let prefersDarkText = luminance > 0.5
        
        let titleColor = prefersDarkText
            ? NSColor.black.withAlphaComponent(0.9)
            : NSColor.white.withAlphaComponent(0.96)
        let secondaryColor = prefersDarkText
            ? NSColor.black.withAlphaComponent(0.58)
            : NSColor.white.withAlphaComponent(0.66)
        let accentBase = prefersDarkText
            ? style.shadow.shifted(hueBy: -0.02, saturationBy: 0.1, brightnessBy: 0.06)
            : style.secondary.shifted(hueBy: -0.03, saturationBy: 0.16, brightnessBy: 0.28)
        let accentColor = accentBase.bestContrastingAccent(on: averageBackground, prefersDarkText: prefersDarkText)
        let translationHighlightColor = accentColor.withAlphaComponent(prefersDarkText ? 0.72 : 0.82)
        
        offsetTextField.textColor = secondaryColor
        offsetUpButton.contentTintColor = secondaryColor
        offsetDownButton.contentTintColor = secondaryColor
        
        songInfoViewController()?.applyImmersiveAppearance(
            titleColor: titleColor,
            secondaryColor: secondaryColor,
            accentColor: titleColor
        )
        lyricViewController()?.applyImmersiveAppearance(
            primaryTextColor: titleColor,
            secondaryTextColor: secondaryColor,
            highlightTextColor: accentColor,
            translationHighlightTextColor: translationHighlightColor
        )
        songButtonsViewController()?.applyImmersiveAppearance(
            buttonTintColor: secondaryColor,
            destructiveTintColor: secondaryColor.withAlphaComponent(0.5),
            lovedTintColor: accentColor
        )
    }
    
    private func dominantArtworkColor(from image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let width = 40
        let height = 40
        let bitsPerComponent = 8
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var red = CGFloat.zero
        var green = CGFloat.zero
        var blue = CGFloat.zero
        var totalWeight = CGFloat.zero
        
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let alpha = CGFloat(pixels[index + 3]) / 255
            if alpha < 0.35 {
                continue
            }
            
            let r = CGFloat(pixels[index]) / 255
            let g = CGFloat(pixels[index + 1]) / 255
            let b = CGFloat(pixels[index + 2]) / 255
            let maxValue = max(r, g, b)
            let minValue = min(r, g, b)
            let brightness = maxValue
            let saturation = maxValue == 0 ? 0 : (maxValue - minValue) / maxValue
            
            if brightness < 0.08 || brightness > 0.9 || saturation < 0.12 {
                continue
            }
            
            let weight = (saturation * 0.75 + 0.25) * (1 - abs(brightness - 0.46))
            red += r * weight
            green += g * weight
            blue += b * weight
            totalWeight += weight
        }
        
        guard totalWeight > 0 else { return nil }
        return NSColor(
            srgbRed: red / totalWeight,
            green: green / totalWeight,
            blue: blue / totalWeight,
            alpha: 1
        )
    }
    
    
    func updateCDRunImage() {
        guard let cdRunImageView, !cdRunImageView.isHidden else { return }
        cdRunImageView.wantsLayer = true
        guard let layer = cdRunImageView.layer else { return }
        var toValue: Double = 0
        var fromValue: Double = 0
        let value = Double.pi / 5.3
        switch playbackViewModel.playerState {
        case .playing:
            fromValue = value
        case .paused:
            toValue = value
        default:
            layer.removeAllAnimations()
            return
        }
        
        let frame = cdRunImageView.frame
        let rotationPoint = CGPoint(x: frame.origin.x + 27,
                                    y: frame.origin.y + frame.height - 26.5)
        
        layer.anchorPoint = CGPoint(x: (rotationPoint.x - frame.minX) / frame.width,
                                    y: (rotationPoint.y - frame.minY) / frame.height)
        layer.position = rotationPoint
        
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = NSNumber(value: fromValue)
        rotation.toValue = NSNumber(value: toValue)
        rotation.duration = 0.35
        rotation.fillMode = .forwards
        rotation.isRemovedOnCompletion = false
        layer.removeAllAnimations()
        layer.add(rotation, forKey: "rotationAnimation")
    }
    
    func lyricViewController() -> LyricViewController? {
        let lyricVC = children.compactMap {
            $0 as? LyricViewController
        }.first
        return lyricVC
    }
    
    func songInfoViewController() -> SongInfoViewController? {
        let songInfoVC = children.compactMap {
            $0 as? SongInfoViewController
            }.first
        return songInfoVC
    }
    
    func songButtonsViewController() -> SongButtonsViewController? {
        let vc = children.compactMap {
            $0 as? SongButtonsViewController
            }.first
        return vc
    }
    
    deinit {
        currentTrackObserver?.invalidate()
        playerStatueObserver?.invalidate()
        fmModeObserver?.invalidate()
        viewFrameObserver?.invalidate()
        lyricViewController()?.removePlayProgressObserver()
        if let obs = viewStatusObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}

private struct ArtworkBackgroundStyle {
    let primary: NSColor
    let secondary: NSColor
    let shadow: NSColor
    
    static let `default` = ArtworkBackgroundStyle(
        primary: NSColor(srgbRed: 0.17, green: 0.19, blue: 0.24, alpha: 1),
        secondary: NSColor(srgbRed: 0.28, green: 0.24, blue: 0.34, alpha: 1),
        shadow: NSColor(srgbRed: 0.03, green: 0.04, blue: 0.06, alpha: 1)
    )
}

private extension NSColor {
    func normalizedArtworkSeed() -> NSColor {
        shifted(hueBy: 0, saturationBy: 0.18, brightnessBy: -0.06)
    }
    
    func shifted(hueBy hueDelta: CGFloat, saturationBy saturationDelta: CGFloat, brightnessBy brightnessDelta: CGFloat) -> NSColor {
        guard let color = usingColorSpace(.deviceRGB) else { return self }
        let hue = color.hueComponent
        let saturation = color.saturationComponent
        let brightness = color.brightnessComponent
        let alpha = color.alphaComponent
        
        let adjustedHue = hue.wrappedUnitOffset(by: hueDelta)
        let adjustedSaturation = min(max(saturation + saturationDelta, 0.18), 0.88)
        let adjustedBrightness = min(max(brightness + brightnessDelta, 0.16), 0.8)
        return NSColor(
            hue: adjustedHue,
            saturation: adjustedSaturation,
            brightness: adjustedBrightness,
            alpha: alpha
        )
    }
    
    var relativeLuminance: CGFloat {
        guard let color = usingColorSpace(.sRGB) else { return 0 }
        func convert(_ component: CGFloat) -> CGFloat {
            component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        let r = convert(color.redComponent)
        let g = convert(color.greenComponent)
        let b = convert(color.blueComponent)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    
    func bestContrastingAccent(on background: NSColor, prefersDarkText: Bool) -> NSColor {
        let candidate = usingColorSpace(.deviceRGB) ?? self
        let bg = background.usingColorSpace(.deviceRGB) ?? background
        let contrast = abs(candidate.relativeLuminance - bg.relativeLuminance)
        if contrast > 0.34 {
            return candidate
        }
        return prefersDarkText
            ? candidate.shifted(hueBy: 0, saturationBy: 0.08, brightnessBy: -0.28)
            : candidate.shifted(hueBy: 0, saturationBy: 0.08, brightnessBy: 0.18)
    }
}

private extension CGFloat {
    func wrappedUnitOffset(by delta: CGFloat) -> CGFloat {
        var value = self + delta
        while value < 0 {
            value += 1
        }
        while value > 1 {
            value -= 1
        }
        return value
    }
}

//
//  ArtistButtonsViewController.swift
//  NeteaseMusic
//
//  Created by xjbeta on 8/7/21.
//  Copyright © 2021 xjbeta. All rights reserved.
//

import Cocoa

class ArtistButtonsViewController: NSViewController {
    @IBOutlet var scrollView: NSScrollView!
    @IBOutlet var stackView: NSStackView!
    
    private var immersiveTextColor: NSColor = .secondaryLabelColor
    private var immersiveSeparatorColor: NSColor = .tertiaryLabelColor
    
    @IBAction @objc func buttonAction(_ sender: IdButton) {
        ViewControllerManager.shared.selectSidebarItem(.artist, sender.id)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.drawsBackground = false
    }
    
    func removeAllButtons() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }
    
    func initButtons(_ track: Track, small: Bool = false) {
        removeAllButtons()

        let buttons = track.artists.map { artist -> IdButton in
            let b = IdButton(title: artist.name, target: self, action: #selector(buttonAction(_:)))
            b.id = artist.id
            b.isEnabled = artist.id > 0
            b.isBordered = false
            b.contentTintColor = immersiveTextColor
            b.attributedTitle = NSAttributedString(
                string: artist.name,
                attributes: [
                    .foregroundColor: immersiveTextColor,
                    .font: small
                        ? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                        : NSFont.systemFont(ofSize: 14, weight: .medium)
                ]
            )
            
            if small {
                b.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            }
            return b
        }
        
        buttons.enumerated().forEach {
            stackView.addArrangedSubview($0.element)
            if $0.offset < (buttons.count - 1) {
                let textField = NSTextField(labelWithString: "/")
                textField.textColor = immersiveSeparatorColor
                if small {
                    textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                }
                stackView.addArrangedSubview(textField)
            }
        }
    }
    
    func applyImmersiveAppearance(textColor: NSColor, separatorColor: NSColor) {
        immersiveTextColor = textColor
        immersiveSeparatorColor = separatorColor
        stackView.arrangedSubviews.forEach { view in
            if let button = view as? NSButton {
                button.contentTintColor = textColor
                button.attributedTitle = NSAttributedString(
                    string: button.title,
                    attributes: [
                        .foregroundColor: textColor,
                        .font: button.font ?? NSFont.systemFont(ofSize: 14, weight: .medium)
                    ]
                )
            } else if let textField = view as? NSTextField {
                textField.textColor = separatorColor
            }
        }
    }
}

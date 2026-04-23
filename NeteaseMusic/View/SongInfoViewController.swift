//
//  SongInfoViewController.swift
//  NeteaseMusic
//
//  Created by xjbeta on 2019/5/14.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa

class SongInfoViewController: NSViewController {
    @IBOutlet weak var nameTextField: NSTextField!
    @IBOutlet weak var secondNameTextField: NSTextField!
    @IBOutlet weak var albumButton: IdButton!
    @IBOutlet weak var albumPrefixTextField: NSTextField!
    @IBOutlet weak var artistPrefixTextField: NSTextField!
    @IBAction @objc func buttonAction(_ sender: IdButton) {
        if sender == albumButton {
            ViewControllerManager.shared.selectSidebarItem(.album, sender.id)
        } else {
            ViewControllerManager.shared.selectSidebarItem(.artist, sender.id)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureTahoeAppearance()
    }
    
    func initInfos(_ track: Track) {
        nameTextField.stringValue = track.name
        secondNameTextField.isHidden = track.secondName.isEmpty
        secondNameTextField.stringValue = track.secondName
        albumButton.title = track.album.name
        albumButton.id = track.album.id
        
        artistButtonsViewController()?.initButtons(track)
    }
    
    func artistButtonsViewController() -> ArtistButtonsViewController? {
        let vc = children.compactMap {
            $0 as? ArtistButtonsViewController
        }.first
        return vc
    }

    private func configureTahoeAppearance() {
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        nameTextField.font = .systemFont(ofSize: 28, weight: .bold)
        nameTextField.textColor = .labelColor
        nameTextField.lineBreakMode = .byTruncatingTail
        secondNameTextField.font = .systemFont(ofSize: 14, weight: .medium)
        secondNameTextField.textColor = .secondaryLabelColor
        secondNameTextField.lineBreakMode = .byTruncatingTail
        
        albumButton.font = .systemFont(ofSize: 13, weight: .semibold)
        albumButton.contentTintColor = .labelColor
        albumButton.isBordered = false
        albumButton.setButtonType(.momentaryChange)
        albumButton.lineBreakMode = .byTruncatingTail
        albumButton.wantsLayer = true
        albumButton.layer?.cornerRadius = 11
        if #available(macOS 10.15, *) {
            albumButton.layer?.cornerCurve = .continuous
        }
        albumButton.layer?.backgroundColor = NSColor.clear.cgColor
        albumButton.layer?.borderWidth = 0
        albumButton.layer?.borderColor = NSColor.clear.cgColor
    }
    
    func applyImmersiveAppearance(
        titleColor: NSColor,
        secondaryColor: NSColor,
        accentColor: NSColor
    ) {
        nameTextField.textColor = titleColor
        secondNameTextField.textColor = secondaryColor
        albumPrefixTextField.textColor = secondaryColor
        artistPrefixTextField.textColor = secondaryColor
        albumButton.contentTintColor = accentColor
        let attributed = NSAttributedString(
            string: albumButton.title,
            attributes: [
                .foregroundColor: accentColor,
                .font: albumButton.font ?? NSFont.systemFont(ofSize: 13, weight: .semibold)
            ]
        )
        albumButton.attributedTitle = attributed
        artistButtonsViewController()?.applyImmersiveAppearance(
            textColor: secondaryColor,
            separatorColor: secondaryColor.withAlphaComponent(0.55)
        )
    }
    
}

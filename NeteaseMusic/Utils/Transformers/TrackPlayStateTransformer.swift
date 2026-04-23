//
//  TrackPlayStateTransformer.swift
//  NeteaseMusic
//
//  Created by xjbeta on 2020/2/16.
//  Copyright © 2020 xjbeta. All rights reserved.
//

import Cocoa

@objc(TrackPlayStateTransformer)
class TrackPlayStateTransformer: ValueTransformer {
    override func transformedValue(_ value: Any?) -> Any? {
        guard let isPlaying = value as? Bool else {
            return nil
        }
        if #available(macOS 11.0, *) {
            let symbolName = isPlaying ? "speaker.wave.2.fill" : "pause.fill"
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }
        return NSImage(named: .init(isPlaying ? "playstate" : "playstate_pause"))
    }
}

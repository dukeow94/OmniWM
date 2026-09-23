// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

enum FocusScrollAnimationStyle: String, CaseIterable, Codable, Identifiable {
    case direct
    case smoothPreview

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .direct: "Direct"
        case .smoothPreview: "Smooth Preview"
        }
    }
}

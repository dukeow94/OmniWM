// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/BarutSRB/OmniWM

import Foundation

enum MonitorCrossingFocus: String, CaseIterable, Codable, Identifiable {
    case spatial
    case last

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .spatial: "Spatial Neighbor"
        case .last: "Last Focused"
        }
    }
}

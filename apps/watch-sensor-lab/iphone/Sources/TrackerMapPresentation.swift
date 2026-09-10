import MapKit
import SwiftUI

enum TrackerMapStyleChoice: String, CaseIterable, Identifiable {
    case standard
    case hybrid
    case satellite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Plan"
        case .hybrid: return "Hybride"
        case .satellite: return "Satellite"
        }
    }

    var symbol: String {
        switch self {
        case .standard: return "map.fill"
        case .hybrid: return "square.3.layers.3d.top.filled"
        case .satellite: return "globe.europe.africa.fill"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard:
            return .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll)
        case .hybrid:
            return .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .satellite:
            return .imagery(elevation: .realistic)
        }
    }
}

struct TrackerMapStyleMenu: View {
    @Binding var selection: TrackerMapStyleChoice

    var body: some View {
        Menu {
            ForEach(TrackerMapStyleChoice.allCases) { style in
                Button {
                    selection = style
                } label: {
                    Label(style.label, systemImage: style.symbol)
                }
            }
        } label: {
            Image(systemName: selection.symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Style de carte")
    }
}

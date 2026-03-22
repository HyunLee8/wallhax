import SwiftUI

extension UseCase {
    static let military = UseCase(
        id: "military",
        title: "Military",
        subtitle: "Tactical operations & site mapping",
        icon: "shield.fill",
        badge: "TACTICAL",
        accentColor: Color(red: 0.60, green: 0.62, blue: 0.66),
        pinLabels: [
            (label: "Objective",   icon: "scope"),
            (label: "Threat",      icon: "exclamationmark.triangle.fill"),
            (label: "Door",        icon: "door.left.hand.open"),
            (label: "Breach",      icon: "bolt.fill"),
            (label: "Rally",       icon: "person.3.fill"),
            (label: "IED",         icon: "flame.fill")
        ]
    )
}

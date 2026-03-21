import SwiftUI

extension UseCase {
    static let military = UseCase(
        id: "military",
        title: "Military",
        subtitle: "Tactical operations & site mapping",
        icon: "shield.fill",
        badge: "TACTICAL",
        accentColor: Color(red: 0.55, green: 0.71, blue: 0.31),
        pinLabels: [
            (label: "Objective",   icon: "scope"),
            (label: "Threat",      icon: "exclamationmark.triangle.fill"),
            (label: "Rally",       icon: "person.3.fill"),
            (label: "Cover",       icon: "shield.fill"),
            (label: "Observation", icon: "eye.fill"),
            (label: "Checkpoint",  icon: "checkmark.circle.fill")
        ]
    )
}

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
            (label: "Objective",   icon: "scope",                          color: .blue),
            (label: "Threat",      icon: "exclamationmark.triangle.fill",  color: .red),
            (label: "Door",        icon: "door.left.hand.open",            color: .green),
            (label: "Breach",      icon: "bolt.fill",                      color: .orange),
            (label: "Rally",       icon: "person.3.fill",                  color: .cyan),
            (label: "IED",         icon: "flame.fill",                     color: .yellow)
        ]
    )
}

import SwiftUI

extension UseCase {
    static let firefighter = UseCase(
        id: "firefighter",
        title: "Firefighter",
        subtitle: "Structure entry & hazard marking",
        icon: "flame.fill",
        badge: "FIRE OPS",
        accentColor: Color(red: 0.95, green: 0.27, blue: 0.12),
        pinLabels: [
            (label: "Fire",    icon: "flame.fill",                          color: .red),
            (label: "Entry",   icon: "door.left.hand.open",                color: .green),
            (label: "Exit",    icon: "rectangle.portrait.and.arrow.right", color: .blue),
            (label: "Victim",  icon: "person.fill",                        color: .orange),
            (label: "Hazard",  icon: "exclamationmark.octagon.fill",       color: .yellow),
            (label: "Hydrant", icon: "drop.fill",                          color: .cyan)
        ]
    )
}

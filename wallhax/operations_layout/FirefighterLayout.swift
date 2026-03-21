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
            (label: "Fire",    icon: "flame.fill"),
            (label: "Entry",   icon: "door.left.hand.open"),
            (label: "Exit",    icon: "rectangle.portrait.and.arrow.right"),
            (label: "Victim",  icon: "person.fill"),
            (label: "Hazard",  icon: "exclamationmark.octagon.fill"),
            (label: "Hydrant", icon: "drop.fill")
        ]
    )
}

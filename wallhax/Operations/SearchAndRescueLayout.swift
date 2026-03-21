import SwiftUI

extension UseCase {
    static let searchAndRescue = UseCase(
        id: "searchAndRescue",
        title: "Search & Rescue",
        subtitle: "Victim location & area clearance",
        icon: "magnifyingglass.circle.fill",
        badge: "SAR",
        accentColor: Color(red: 1.0, green: 0.55, blue: 0.13),
        pinLabels: [
            (label: "Victim",   icon: "person.fill"),
            (label: "Found",    icon: "checkmark.seal.fill"),
            (label: "Hazard",   icon: "exclamationmark.triangle"),
            (label: "Clear",    icon: "checkmark.circle"),
            (label: "Medical",  icon: "cross.fill"),
            (label: "Command",  icon: "star.fill")
        ]
    )
}

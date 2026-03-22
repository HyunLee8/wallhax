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
            (label: "Victim",   icon: "person.fill",              color: .red),
            (label: "Found",    icon: "checkmark.seal.fill",      color: .green),
            (label: "Hazard",   icon: "exclamationmark.triangle", color: .orange),
            (label: "Clear",    icon: "checkmark.circle",         color: .mint),
            (label: "Medical",  icon: "cross.fill",               color: .pink),
            (label: "Command",  icon: "star.fill",                color: .yellow)
        ]
    )
}

import SwiftUI

struct UseCase: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let badge: String
    let accentColor: Color
    let pinLabels: [(label: String, icon: String)]

    static let allCases: [UseCase] = [.military, .searchAndRescue, .firefighter]
}

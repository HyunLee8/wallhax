//
//  UseCase.swift
//  wallhax-ios
//

import SwiftUI

enum UseCase: String, CaseIterable, Identifiable {
    case military
    case searchAndRescue
    case firefighter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .military:       return "Military"
        case .searchAndRescue: return "Search & Rescue"
        case .firefighter:    return "Firefighter"
        }
    }

    var subtitle: String {
        switch self {
        case .military:       return "Tactical operations & site mapping"
        case .searchAndRescue: return "Victim location & area clearance"
        case .firefighter:    return "Structure entry & hazard marking"
        }
    }

    var icon: String {
        switch self {
        case .military:       return "shield.fill"
        case .searchAndRescue: return "magnifyingglass.circle.fill"
        case .firefighter:    return "flame.fill"
        }
    }

    var badge: String {
        switch self {
        case .military:       return "TACTICAL"
        case .searchAndRescue: return "SAR"
        case .firefighter:    return "FIRE OPS"
        }
    }

    var accentColor: Color {
        switch self {
        case .military:       return Color(red: 0.55, green: 0.71, blue: 0.31)
        case .searchAndRescue: return Color(red: 1.0,  green: 0.55, blue: 0.13)
        case .firefighter:    return Color(red: 0.95, green: 0.27, blue: 0.12)
        }
    }

    var pinLabels: [(label: String, icon: String)] {
        switch self {
        case .military:
            return [
                (label: "Objective",   icon: "scope"),
                (label: "Threat",      icon: "exclamationmark.triangle.fill"),
                (label: "Rally",       icon: "person.3.fill"),
                (label: "Cover",       icon: "shield.fill"),
                (label: "Observation", icon: "eye.fill"),
                (label: "Checkpoint",  icon: "checkmark.circle.fill")
            ]
        case .searchAndRescue:
            return [
                (label: "Victim",   icon: "person.fill"),
                (label: "Found",    icon: "checkmark.seal.fill"),
                (label: "Hazard",   icon: "exclamationmark.triangle"),
                (label: "Clear",    icon: "checkmark.circle"),
                (label: "Medical",  icon: "cross.fill"),
                (label: "Command",  icon: "star.fill")
            ]
        case .firefighter:
            return [
                (label: "Fire",    icon: "flame.fill"),
                (label: "Entry",   icon: "door.left.hand.open"),
                (label: "Exit",    icon: "rectangle.portrait.and.arrow.right"),
                (label: "Victim",  icon: "person.fill"),
                (label: "Hazard",  icon: "exclamationmark.octagon.fill"),
                (label: "Hydrant", icon: "drop.fill")
            ]
        }
    }
}

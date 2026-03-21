//
//  MapPin.swift
//  wallhax
//
//  Created by Ken Zhou on 3/21/26.
//

import Foundation

struct MapPin: Identifiable {
    let id = UUID()
    let position: SIMD3<Float>
    let position2D: SIMD2<Float>
    let label: String
    let timestamp: Date
}

//
//  InsightModels.swift
//  Dobbie Sign Up
//
//  Created by David Cohen on 03/10/2025.
//

import Foundation
import SwiftUI


extension Array where Element == WalkData {
    mutating func addQuickLog(for day: String) {
        if let idx = firstIndex(where: { $0.day == day }) {
            self[idx] = WalkData(day: day, count: self[idx].count + 1)
        } else {
            append(WalkData(day: day, count: 1))
        }
    }
}

extension Array where Element == ActivityData {
    mutating func addQuickLog(for day: String, type: String = "Play", minutes: Int = 15) {
        if let idx = firstIndex(where: { $0.day == day && $0.type == type }) {
            let current = self[idx]
            self[idx] = ActivityData(day: day, type: type, minutes: current.minutes + minutes)
        } else {
            append(ActivityData(day: day, type: type, minutes: minutes))
        }
    }
}

extension Array where Element == PottyData {
    mutating func addQuickLog(for day: String, type: String) {
        if let idx = firstIndex(where: { $0.day == day && $0.type == type }) {
            let current = self[idx]
            self[idx] = PottyData(day: day, type: type, count: current.count + 1)
        } else {
            append(PottyData(day: day, type: type, count: 1))
        }
    }
}

// ====================================================
// MARK: - Periods
// ====================================================

/// Time periods for charts + insights
enum Period: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    
    var id: String { rawValue }
}
enum InsightKind: String, Identifiable, CaseIterable {
    case walks
    case activity
    case potty
    
    var id: String { rawValue }
}


// ====================================================
// MARK: - Weekly Goals
// ====================================================

enum WeeklyGoals {
    static let walksTarget = 14           // ~2 per day
    static let playMinutesTarget = 180    // ~30 mins/day
    static let pottyTarget = 20           // ~3/day
}

// ====================================================
// MARK: - Chart Data Models
// ====================================================

/// For walk insights
struct WalkData: Identifiable, Equatable {
    let id = UUID()
    let day: String   // e.g. "Mon"
    let count: Int    // number of walks
}

/// For play/activity insights
struct ActivityData: Identifiable, Equatable {
    let id = UUID()
    let day: String   // e.g. "Mon"
    let type: String  // "Play", "Sleep", etc.
    let minutes: Int  // minutes spent
}

/// For potty insights
struct PottyData: Identifiable, Equatable {
    let id = UUID()
    let day: String   // e.g. "Mon"
    let type: String  // "Pee" or "Poo"
    let count: Int    // number of events
}



// ====================================================
// MARK: - Helpers
// ====================================================

/// Order days Mon..Sun for charts
func dayOfWeekIndex(_ day: String) -> Int {
    let order = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
    return order.firstIndex(of: day) ?? 0
}

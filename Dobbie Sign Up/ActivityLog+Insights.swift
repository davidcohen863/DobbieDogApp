//
//  ActivityLog+Insights.swift
//  Dobbie Sign Up
//
//  Created by David Cohen on 03/10/2025.
//

import SwiftUI
import Foundation

// MARK: - ActivityLog Helpers for Insights
extension Array where Element == SupabaseManager.ActivityLog {

    func groupedByDay() -> [String: [String: Int]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"  // Mon, Tue, Wed
        var result: [String: [String: Int]] = [:]
        
        for log in self {
            let day = formatter.string(from: log.timestamp)
            var dayDict = result[day, default: [:]]
            dayDict[log.event_type, default: 0] += 1
            result[day] = dayDict
        }
        return result
    }
    
    /// Totals across the whole array by event type
    func totalsByType() -> [String: Int] {
        var result: [String: Int] = [:]
        for log in self {
            result[log.event_type, default: 0] += 1
        }
        return result
    }
    
    /// Logs for this week only
    func thisWeek() -> [SupabaseManager.ActivityLog] {
        let cal = Calendar.current
        let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        return self.filter { $0.timestamp >= startOfWeek }
    }
    
    /// Logs for this month only
    func thisMonth() -> [SupabaseManager.ActivityLog] {
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        return self.filter { $0.timestamp >= startOfMonth }
    }
    
    // MARK: - Transformations for Insights

    func toWalkData() -> [WalkData] {
        let grouped = self.filter { $0.event_type == "walk" }.groupedByDay()
        return grouped.map { WalkData(day: $0.key, count: $0.value["walk"] ?? 0) }
            .sorted { dayOfWeekIndex($0.day) < dayOfWeekIndex($1.day) }
    }

    func toActivityData() -> [ActivityData] {
        let grouped = self.groupedByDay()
        var result: [ActivityData] = []
        for (day, events) in grouped {
            for (type, count) in events {
                result.append(ActivityData(day: day, type: type.capitalized, minutes: count * 15))
            }
        }
        return result.sorted { dayOfWeekIndex($0.day) < dayOfWeekIndex($1.day) }
    }

    func toPottyData() -> [PottyData] {
        let grouped = self.groupedByDay()
        var result: [PottyData] = []
        for (day, events) in grouped {
            for (type, count) in events where (type == "pee" || type == "poo") {
                result.append(PottyData(day: day, type: type.capitalized, count: count))
            }
        }
        return result.sorted { dayOfWeekIndex($0.day) < dayOfWeekIndex($1.day) }
    }
}

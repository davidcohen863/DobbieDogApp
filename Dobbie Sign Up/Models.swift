//
//  Models.swift
//  Dobbie Sign Up
//
//  Created by David Cohen on 24/09/2025.
//

import Foundation
import SwiftUI

// MARK: - Dog Models

/// For inserting a new dog into Supabase
// For inserting a new dog (client shouldn't send user_id)
struct DogInsert: Codable {
    let name: String
    let breed: String
    let dob: String
    let gender: String
    let weight: Double?
}

/// For reading a dog back from Supabase
struct Dog: Codable, Identifiable {
    let id: String
    let user_id: String
    let name: String
    let breed: String
    let dob: String
    let gender: String
    let weight: Double?
    let created_at: String
}


// MARK: - Activity Log Models

struct ActivityLogInsert: Codable {
    let dog_id: String
    let event_type: String   // "eat", "drink", "pee", "poo", "sleep", "walk", "play"
    let timestamp: Date

}

struct ActivityLog: Codable, Identifiable {
    let id: String
    let dog_id: String
    var event_type: String    // ✅ make editable
    var timestamp: Date       // ✅ make editable
    let created_at: Date
    var notes: String?        // ✅ new
   
}




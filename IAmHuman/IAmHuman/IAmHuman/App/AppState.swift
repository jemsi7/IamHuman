// App/AppState.swift

import Foundation
import Combine
import SwiftUI

// MARK: - User Profile Model

struct UserProfile: Codable {
    var name: String
    var birthdate: Date
    var gender: Gender
    var profileImageData: Data?
    
    enum Gender: String, Codable, CaseIterable {
        case male = "남성"
        case female = "여성"
        
        var icon: String {
            switch self {
            case .male: return "♂"
            case .female: return "♀"
            }
        }
        
        var color: Color {
            switch self {
            case .male: return .blue
            case .female: return .pink
            }
        }
    }
    
    var age: Int {
        Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 0
    }
    
    var formattedBirthdate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy년 MM월 dd일"
        return formatter.string(from: birthdate)
    }
}

// MARK: - Family Member Model

struct FamilyMember: Identifiable, Codable {
    let id: UUID
    var name: String
    var birthdate: Date
    var relationship: String  // 닉네임으로 사용 (예: 엄마, 아빠, 동생)
    var shareCode: String     // 상대방의 ID::HASH 형식 코드
    
    init(id: UUID = UUID(), name: String, birthdate: Date, relationship: String, shareCode: String) {
        self.id = id
        self.name = name
        self.birthdate = birthdate
        self.relationship = relationship
        self.shareCode = shareCode
    }
    
    var age: Int {
        Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 0
    }
    
    var formattedBirthdate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy년 MM월 dd일"
        return formatter.string(from: birthdate)
    }
}

@Observable
final class AppState {
    
    enum AuthStatus {
        case unauthenticated
        case authenticated(VerifiableCredential)
    }
    
    var authStatus: AuthStatus = .unauthenticated
    var currentVC: VerifiableCredential?
    var userProfile: UserProfile?
    var familyMembers: [FamilyMember] = []
    
    // Navigation
    var showingRegistration = false
    var showingScanner = false
    var showingProfileSetup = false
    var hasStarted = false
    
    private let profileKey = "UserProfile"
    private let hasStartedKey = "HasStarted"
    private let familyMembersKey = "FamilyMembers"
    
    init() {
        // Load hasStarted state
        hasStarted = UserDefaults.standard.bool(forKey: hasStartedKey)
        
        // Load existing profile
        loadProfile()
        
        // Load family members
        loadFamilyMembers()
        
        // Load existing VC if any
        if let vcs = try? VCStore.shared.loadAll(), let first = vcs.first {
            authStatus = .authenticated(first)
            currentVC = first
        }
    }
    
    func setAuthenticated(vc: VerifiableCredential) {
        authStatus = .authenticated(vc)
        currentVC = vc
        try? VCStore.shared.save(vc)
    }
    
    func setProfile(_ profile: UserProfile) {
        userProfile = profile
        saveProfile()
    }
    
    func startApp() {
        hasStarted = true
        UserDefaults.standard.set(true, forKey: hasStartedKey)
    }
    
    private func saveProfile() {
        guard let profile = userProfile else { return }
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }
    
    private func loadProfile() {
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            userProfile = profile
        }
    }
    
    func reset() {
        authStatus = .unauthenticated
        currentVC = nil
        userProfile = nil
        UserDefaults.standard.removeObject(forKey: profileKey)
    }
    
    func renewVC() {
        // Clear current VC and require re-authentication
        authStatus = .unauthenticated
        currentVC = nil
        // Keep user profile, just require new human verification
        showingRegistration = true
    }
    
    // MARK: - Family Members
    
    func addFamilyMember(_ member: FamilyMember) {
        familyMembers.append(member)
        saveFamilyMembers()
    }
    
    func removeFamilyMember(at offsets: IndexSet) {
        familyMembers.remove(atOffsets: offsets)
        saveFamilyMembers()
    }
    
    func removeFamilyMember(id: UUID) {
        familyMembers.removeAll { $0.id == id }
        saveFamilyMembers()
    }

    func updateFamilyMember(_ updatedMember: FamilyMember) {
        if let index = familyMembers.firstIndex(where: { $0.id == updatedMember.id }) {
            familyMembers[index] = updatedMember
            saveFamilyMembers()
        }
    }

    // Find family member by share code (ID::HASH format)
    func findFamilyMember(byShareCode shareCode: String) -> FamilyMember? {
        return familyMembers.first { $0.shareCode == shareCode }
    }

    // Find family member by ID portion of share code
    func findFamilyMember(byId id: String) -> FamilyMember? {
        return familyMembers.first { member in
            let components = member.shareCode.components(separatedBy: "::")
            return components.first == id
        }
    }

    private func saveFamilyMembers() {
        if let data = try? JSONEncoder().encode(familyMembers) {
            UserDefaults.standard.set(data, forKey: familyMembersKey)
        }
    }
    
    private func loadFamilyMembers() {
        if let data = UserDefaults.standard.data(forKey: familyMembersKey),
           let members = try? JSONDecoder().decode([FamilyMember].self, from: data) {
            familyMembers = members
        }
    }
}


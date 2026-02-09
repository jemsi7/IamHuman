// App/IAmHumanApp.swift

import SwiftUI
import CoreImage.CIFilterBuiltins
import PhotosUI
import AVFoundation
import AudioToolbox
import UniformTypeIdentifiers

@main
struct IAmHumanApp: App {
    @State private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }
}

struct MainView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        Group {
            if !appState.hasStarted {
                NavigationStack {
                    WelcomeView()
                }
            } else {
                switch appState.authStatus {
                case .unauthenticated:
                    NavigationStack {
                        if appState.userProfile == nil {
                            ProfileSetupView()
                        } else {
                            RegistrationPromptView()
                        }
                    }
                    .fullScreenCover(isPresented: Bindable(appState).showingRegistration) {
                        RegistrationFlowView()
                    }
                case .authenticated(let vc):
                    TabView {
                        NavigationStack {
                            DashboardView(vc: vc)
                        }
                        .tabItem {
                            Image(systemName: "person.fill")
                            Text("나")
                        }
                        
                        NavigationStack {
                            FamilyView()
                        }
                        .tabItem {
                            Image(systemName: "person.3.fill")
                            Text("가족")
                        }
                    }
                    .fullScreenCover(isPresented: Bindable(appState).showingRegistration) {
                        RegistrationFlowView()
                    }
                }
            }
        }
    }
}

// MARK: - Registration Prompt View (after profile setup)

struct RegistrationPromptView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            if let profile = appState.userProfile {
                // Profile Preview
                VStack(spacing: 15) {
                    if let imageData = profile.profileImageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(profile.gender.color, lineWidth: 3))
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                            )
                    }
                    
                    Text("안녕하세요, \(profile.name)님!")
                        .font(.title2)
                        .bold()
                }
            }
            
            VStack(spacing: 16) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("신원 인증을 시작하세요")
                    .font(.title3)
                    .foregroundColor(.white)
                
                Text("카메라, 마이크, 센서를 사용하여\n인간임을 증명합니다.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                    .font(.subheadline)
            }
            
            Spacer()
            
            Button(action: {
                appState.showingRegistration = true
            }) {
                Text("인증 시작")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal)
            .padding(.bottom, 50)
        }
        .padding()
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack(spacing: 50) {
            Spacer()
            
            // Logo
            VStack(spacing: 25) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.3), Color.blue.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 150, height: 150)
                    
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 70))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(spacing: 10) {
                    Text("I Am Human")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .gray.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    Text("프라이버시를 지키는 신원 인증")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Start Button
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    appState.startApp()
                }
            } label: {
                HStack {
                    Text("시작하기")
                        .font(.headline)
                    Image(systemName: "arrow.right")
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.white, .gray.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(14)
                .shadow(color: .white.opacity(0.2), radius: 10, x: 0, y: 5)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .background(
            ZStack {
                Color.black
                
                // Ambient glow
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 300, height: 300)
                    .blur(radius: 100)
                    .offset(y: -100)
            }
        )
    }
}

// MARK: - Profile Setup View

struct ProfileSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var name = ""
    @State private var birthdate = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var gender: UserProfile.Gender = .male
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // Profile Photo
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        ZStack {
                            if let profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 120, height: 120)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray)
                            }
                            
                            Circle()
                                .stroke(Color.white.opacity(0.5), lineWidth: 3)
                                .frame(width: 120, height: 120)
                        }
                    }
                    .onChange(of: selectedPhoto) { _, newValue in
                        Task {
                            if let data = try? await newValue?.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                profileImage = image
                            }
                        }
                    }
                    
                    Text("프로필 사진 추가")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    // Input Fields
                    VStack(spacing: 20) {
                        // Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("이름")
                                .font(.caption)
                                .foregroundColor(.gray)
                            TextField("이름을 입력하세요", text: $name)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(10)
                        }
                        
                        // Birthdate
                        VStack(alignment: .leading, spacing: 8) {
                            Text("생년월일")
                                .font(.caption)
                                .foregroundColor(.gray)
                            DatePicker("", selection: $birthdate, displayedComponents: .date)
                                .environment(\.locale, Locale(identifier: "ko_KR"))
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(10)
                        }
                        
                        // Gender
                        VStack(alignment: .leading, spacing: 8) {
                            Text("성별")
                                .font(.caption)
                                .foregroundColor(.gray)
                            HStack(spacing: 15) {
                                ForEach(UserProfile.Gender.allCases, id: \.self) { g in
                                    Button {
                                        gender = g
                                    } label: {
                                        HStack {
                                            Text(g.icon)
                                            Text(g.rawValue)
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(gender == g ? g.color.opacity(0.3) : Color.gray.opacity(0.2))
                                        .foregroundColor(gender == g ? g.color : .white)
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(gender == g ? g.color : Color.clear, lineWidth: 2)
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer().frame(height: 40)
                    
                    // Continue Button
                    Button {
                        let profile = UserProfile(
                            name: name,
                            birthdate: birthdate,
                            gender: gender,
                            profileImageData: profileImage?.jpegData(compressionQuality: 0.8)
                        )
                        appState.setProfile(profile)
                    } label: {
                        Text("계속하기")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(name.isEmpty ? Color.gray : Color.white)
                            .cornerRadius(14)
                    }
                    .disabled(name.isEmpty)
                    .padding(.horizontal)
                }
                .padding(.top, 40)
            }
            .navigationTitle("프로필 설정")
        }
    }
}



struct DashboardView: View {
    @Environment(AppState.self) private var appState
    let vc: VerifiableCredential
    @State private var showingCode = false
    @State private var showingIdentityCheck = false
    @State private var showingProfileEdit = false
    @State private var showingRenewalConfirm = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                // Profile Section
                if let profile = appState.userProfile {
                    VStack(spacing: 15) {
                        // Profile Photo with Gender Badge
                        ZStack(alignment: .bottomTrailing) {
                            if let imageData = profile.profileImageData,
                               let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(profile.gender.color, lineWidth: 3)
                                    )
                            } else {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(profile.gender.color, lineWidth: 3)
                                    )
                            }
                            
                            // Gender Badge
                            Text(profile.gender.icon)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(profile.gender.color)
                                .clipShape(Circle())
                                .offset(x: 5, y: 5)
                        }
                        .onTapGesture {
                            showingProfileEdit = true
                        }
                        
                        // Name
                        Text(profile.name)
                            .font(.title2)
                            .bold()
                        
                        // Birthdate & Age
                        HStack(spacing: 10) {
                            Label(profile.formattedBirthdate, systemImage: "calendar")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Text("(\(profile.age)세)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.top, 20)
                }
                
                // Verification Card
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        let hasName = !(appState.userProfile?.name.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
                        let isReportedByOthers = ReportedUsersStore.shared.isUserReported(id: vc.vcId)
                        let isVerified = vc.trustLevel == "A" && hasName && !isReportedByOthers
                        
                        if isReportedByOthers {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("분쟁중인 사용자")
                                .font(.headline)
                                .foregroundColor(.orange)
                        } else {
                            Image(systemName: isVerified ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .foregroundColor(isVerified ? .green : .orange)
                            Text(isVerified ? "인증된 사용자" : "인증되지 않은 사용자")
                                .font(.headline)
                        }
                        Spacer()
                        Text("등급 \(vc.trustLevel)")
                            .bold()
                            .padding(5)
                            .background((isVerified && !isReportedByOthers ? Color.green : Color.orange).opacity(0.2))
                            .cornerRadius(5)
                    }
                    
                    Divider().background(Color.white.opacity(0.3))
                    
                    Text("ID: \(vc.vcId)")
                        .font(.system(.caption, design: .monospaced))
                        .opacity(0.7)
                    
                    Text("만료일: \(vc.expirationDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .opacity(0.7)
                }
                .padding()
                .background(
                    LinearGradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .cornerRadius(20)
                .padding(.horizontal)
                .shadow(radius: 10)
                
                // Actions
                HStack(spacing: 20) {
                    ActionButton(icon: "qrcode", label: "QR 코드") {
                        showingCode.toggle()
                    }
                    
                    ActionButton(icon: "person.badge.shield.checkmark.fill", label: "신원조회") {
                        showingIdentityCheck.toggle()
                    }
                }
                .padding(.horizontal)
                
                // ID Renewal Button
                Button {
                    showingRenewalConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("ID 재발급")
                    }
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(10)
                }
                .padding(.top, 10)
                
                Spacer()
            }
        }
        .sheet(isPresented: $showingCode) {
            VStack(spacing: 20) {
                Text("내 인증 QR 코드")
                    .font(.headline)
                    .padding(.top)
                
                if let qrData = generateVerificationQRData(),
                   let qrImage = generateQRCode(from: qrData) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .background(Color.white)
                        .cornerRadius(10)
                        .padding(.horizontal)
                } else {
                    Image(systemName: "qrcode")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding(.horizontal)
                }
                
                Text("스캔하여 신원 확인")
                    .foregroundColor(.gray)
                    .font(.caption)
                
                // ID Copy Section
                VStack(spacing: 10) {
                    Text("또는 고유 식별 코드 공유")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    if let shareCode = generateShareableCode() {
                        Button {
                            UIPasteboard.general.string = shareCode
                        } label: {
                            HStack {
                                Text(shareCode)
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                Image(systemName: "doc.on.doc")
                                    .foregroundColor(.blue)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        
                        Text("탭하여 복사")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                
                if let profile = appState.userProfile {
                    Text("이름: \(profile.name)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingIdentityCheck) {
            IdentityCheckView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingProfileEdit) {
            ProfileEditView()
                .presentationDetents([.large])
        }
        .alert("ID 재발급", isPresented: $showingRenewalConfirm) {
            Button("취소", role: .cancel) { }
            Button("재발급", role: .destructive) {
                appState.renewVC()
            }
        } message: {
            Text("기존 ID가 무효화되고 새 ID가 발급됩니다. 이전에 공유한 식별 코드는 더 이상 사용할 수 없게 됩니다.\n\n계속하시겠습니까?")
        }
        .navigationTitle(appState.userProfile.map { "환영합니다, \($0.name)님" } ?? "환영합니다")
    }
    
    private func generateVerificationQRData() -> String? {
        guard let profile = appState.userProfile else { return nil }
        
        // Create identity hash from name + birthdate
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let birthdateString = dateFormatter.string(from: profile.birthdate)
        let identityString = "\(profile.name)|\(birthdateString)"
        
        // Create hash
        let identityHash = identityString.data(using: .utf8)?.base64EncodedString() ?? ""
        
        // Create QR data as JSON
        let qrData: [String: String] = [
            "id": vc.vcId,
            "hash": identityHash,
            "name": profile.name,
            "birthdate": birthdateString
        ]
        
        if let jsonData = try? JSONEncoder().encode(qrData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return nil
    }
    
    private func generateShareableCode() -> String? {
        guard let profile = appState.userProfile else { return nil }
        
        // Create identity hash from name + birthdate
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let birthdateString = dateFormatter.string(from: profile.birthdate)
        let identityString = "\(profile.name)|\(birthdateString)"
        let identityHash = identityString.data(using: .utf8)?.base64EncodedString() ?? ""
        
        // Encode ID + hash together (format: ID::HASH)
        return "\(vc.vcId)::\(identityHash)"
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scale = 10.0
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Profile Edit View

struct ProfileEditView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var birthdate = Date()
    @State private var gender: UserProfile.Gender = .male
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // Profile Photo
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        ZStack {
                            if let profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else if let imageData = appState.userProfile?.profileImageData,
                                      let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 120, height: 120)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray)
                            }
                            
                            Circle()
                                .stroke(gender.color, lineWidth: 3)
                                .frame(width: 120, height: 120)
                            
                            // Edit badge
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .background(Circle().fill(Color.blue))
                                .offset(x: 45, y: 45)
                        }
                    }
                    .onChange(of: selectedPhoto) { _, newValue in
                        Task {
                            if let data = try? await newValue?.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                profileImage = image
                            }
                        }
                    }
                    
                    // Input Fields
                    VStack(spacing: 20) {
                        // Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("이름")
                                .font(.caption)
                                .foregroundColor(.gray)
                            TextField("이름을 입력하세요", text: $name)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(10)
                        }
                        
                        // Birthdate
                        VStack(alignment: .leading, spacing: 8) {
                            Text("생년월일")
                                .font(.caption)
                                .foregroundColor(.gray)
                            DatePicker("", selection: $birthdate, displayedComponents: .date)
                                .environment(\.locale, Locale(identifier: "ko_KR"))
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(10)
                        }
                        
                        // Gender
                        VStack(alignment: .leading, spacing: 8) {
                            Text("성별")
                                .font(.caption)
                                .foregroundColor(.gray)
                            HStack(spacing: 15) {
                                ForEach(UserProfile.Gender.allCases, id: \.self) { g in
                                    Button {
                                        gender = g
                                    } label: {
                                        HStack {
                                            Text(g.icon)
                                            Text(g.rawValue)
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(gender == g ? g.color.opacity(0.3) : Color.gray.opacity(0.2))
                                        .foregroundColor(gender == g ? g.color : .white)
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(gender == g ? g.color : Color.clear, lineWidth: 2)
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 20)
            }
            .navigationTitle("프로필 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
                        saveProfile()
                        dismiss()
                    }
                    .bold()
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let profile = appState.userProfile {
                    name = profile.name
                    birthdate = profile.birthdate
                    gender = profile.gender
                }
            }
        }
    }
    
    private func saveProfile() {
        var imageData = appState.userProfile?.profileImageData
        if let newImage = profileImage {
            imageData = newImage.jpegData(compressionQuality: 0.8)
        }
        
        let profile = UserProfile(
            name: name,
            birthdate: birthdate,
            gender: gender,
            profileImageData: imageData
        )
        appState.setProfile(profile)
    }
}

// MARK: - Reported Users Store

class ReportedUsersStore {
    static let shared = ReportedUsersStore()
    private let key = "ReportedUserIds"
    
    private init() {}
    
    func reportUser(id: String) {
        var reported = getReportedUsers()
        if !reported.contains(id) {
            reported.append(id)
            UserDefaults.standard.set(reported, forKey: key)
        }
    }
    
    func isUserReported(id: String) -> Bool {
        return getReportedUsers().contains(id)
    }
    
    func getReportedUsers() -> [String] {
        return UserDefaults.standard.stringArray(forKey: key) ?? []
    }
}

struct IdentityCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var scanState: ScanState = .methodSelection
    @State private var scannedData: ScannedUserData?
    @State private var inputName: String = ""
    @State private var inputBirthdate: Date = Date()
    @State private var showingReport = false
    @State private var manualCode: String = ""
    @State private var verificationMethod: VerificationMethod = .qrScan
    @State private var isFamilyMember: Bool = false
    
    struct ScannedUserData {
        let id: String
        let name: String
        let birthdate: String
        let hash: String
    }
    
    enum VerificationMethod {
        case qrScan
        case codeInput
    }
    
    enum ScanState {
        case methodSelection
        case scanning
        case codeInputMode
        case verifying
        case inputVerification
        case success
        case failed
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                switch scanState {
                case .methodSelection:
                    VStack(spacing: 30) {
                        Image(systemName: "person.badge.shield.checkmark")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("신원 조회 방식 선택")
                            .font(.title2)
                            .bold()
                        
                        Text("상대방의 QR 코드를 스캔하거나\n고유 식별 코드를 입력하세요.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                            .font(.subheadline)
                        
                        VStack(spacing: 15) {
                            Button {
                                scanState = .scanning
                                verificationMethod = .qrScan
                            } label: {
                                HStack {
                                    Image(systemName: "qrcode.viewfinder")
                                        .font(.title2)
                                    VStack(alignment: .leading) {
                                        Text("QR 코드 스캔")
                                            .font(.headline)
                                        Text("카메라로 QR 코드를 스캔합니다")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue.opacity(0.3))
                                .cornerRadius(12)
                            }
                            
                            Button {
                                scanState = .codeInputMode
                                verificationMethod = .codeInput
                            } label: {
                                HStack {
                                    Image(systemName: "textformat.123")
                                        .font(.title2)
                                    VStack(alignment: .leading) {
                                        Text("코드 직접 입력")
                                            .font(.headline)
                                        Text("고유 식별 코드를 입력합니다")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.purple.opacity(0.3))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                    
                case .codeInputMode:
                    ScrollView {
                        VStack(spacing: 25) {
                            Image(systemName: "textformat.123")
                                .font(.system(size: 60))
                                .foregroundColor(.purple)
                            
                            Text("고유 식별 코드 입력")
                                .font(.title2)
                                .bold()
                            
                            Text("상대방에게 받은 고유 식별 코드(ID)를\n입력해주세요.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.gray)
                                .font(.subheadline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("고유 식별 코드")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                TextField("예: A1B2C3D4-E5F6-7890-...", text: $manualCode)
                                    .font(.system(.body, design: .monospaced))
                                    .autocapitalization(.allCharacters)
                                    .disableAutocorrection(true)
                                    .padding()
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(10)
                            }
                            .padding(.horizontal)
                            
                            Button {
                                handleManualCodeInput()
                            } label: {
                                Text("조회하기")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(manualCode.count >= 8 ? Color.white : Color.gray)
                                    .cornerRadius(14)
                            }
                            .disabled(manualCode.count < 8)
                            .padding(.horizontal)
                            
                            Button("방식 다시 선택") {
                                scanState = .methodSelection
                                manualCode = ""
                                isFamilyMember = false
                            }
                            .foregroundColor(.blue)
                        }
                        .padding(.top, 40)
                    }
                    
                case .scanning:
                    QRScannerView { code in
                        handleScannedCode(code)
                    }
                    .ignoresSafeArea()
                    
                    // Overlay
                    VStack {
                        Spacer()
                        
                        // Scan frame
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 250, height: 250)
                            
                            // Corner accents
                            VStack {
                                HStack {
                                    CornerShape()
                                        .stroke(Color.blue, lineWidth: 4)
                                        .frame(width: 40, height: 40)
                                    Spacer()
                                    CornerShape()
                                        .stroke(Color.blue, lineWidth: 4)
                                        .frame(width: 40, height: 40)
                                        .rotationEffect(.degrees(90))
                                }
                                Spacer()
                                HStack {
                                    CornerShape()
                                        .stroke(Color.blue, lineWidth: 4)
                                        .frame(width: 40, height: 40)
                                        .rotationEffect(.degrees(-90))
                                    Spacer()
                                    CornerShape()
                                        .stroke(Color.blue, lineWidth: 4)
                                        .frame(width: 40, height: 40)
                                        .rotationEffect(.degrees(180))
                                }
                            }
                            .frame(width: 250, height: 250)
                        }
                        
                        Spacer()
                        
                        Text("QR 코드를 프레임 안에 맞춰주세요")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(10)
                            .padding(.bottom, 50)
                    }
                    
                case .verifying:
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(2)
                            .tint(.white)
                        
                        Text("신원 확인 중...")
                            .foregroundColor(.gray)
                    }
                    
                case .inputVerification:
                    ScrollView {
                        VStack(spacing: 25) {
                            Image(systemName: "person.badge.shield.checkmark")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                            
                            Text("신원 확인")
                                .font(.title2)
                                .bold()
                            
                            Text("상대방의 이름과 생년월일을 입력하여\n신원을 확인하세요.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.gray)
                                .font(.subheadline)
                            
                            VStack(spacing: 15) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("이름")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    TextField("이름을 입력하세요", text: $inputName)
                                        .padding()
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(10)
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("생년월일")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    DatePicker("", selection: $inputBirthdate, displayedComponents: .date)
                                        .environment(\.locale, Locale(identifier: "ko_KR"))
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .padding()
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal)
                            
                            Button {
                                verifyIdentity()
                            } label: {
                                Text("확인")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(inputName.isEmpty ? Color.gray : Color.white)
                                    .cornerRadius(14)
                            }
                            .disabled(inputName.isEmpty)
                            .padding(.horizontal)
                            
                            Button("처음으로") {
                                scanState = .methodSelection
                                scannedData = nil
                                inputName = ""
                                manualCode = ""
                                isFamilyMember = false
                            }
                            .foregroundColor(.blue)
                        }
                        .padding(.top, 40)
                    }
                    
                case .success:
                    ScrollView {
                        VStack(spacing: 20) {
                            if let data = scannedData {
                                let isReported = ReportedUsersStore.shared.isUserReported(id: data.id)
                                let isUnverified = data.name == "확인 필요" || data.name.isEmpty
                                
                                if isReported {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 80))
                                        .foregroundColor(.orange)
                                    
                                    Text("분쟁중인 사용자")
                                        .font(.title)
                                        .bold()
                                        .foregroundColor(.orange)
                                } else if isUnverified {
                                    Image(systemName: "exclamationmark.shield.fill")
                                        .font(.system(size: 80))
                                        .foregroundColor(.orange)
                                    
                                    Text("신원 정보 부족")
                                        .font(.title)
                                        .bold()
                                        .foregroundColor(.orange)
                                    
                                    Text("이 사용자의 이름이 확인되지 않았습니다.")
                                        .font(.body)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                } else {
                                    Image(systemName: isFamilyMember ? "person.2.circle.fill" : "checkmark.circle.fill")
                                        .font(.system(size: 80))
                                        .foregroundColor(.green)

                                    Text(isFamilyMember ? "가족 인증 완료" : "신원 확인 완료")
                                        .font(.title)
                                        .bold()

                                    if isFamilyMember {
                                        Text("등록된 가족입니다")
                                            .font(.subheadline)
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                VStack(spacing: 12) {
                                    HStack {
                                        Text("이름")
                                            .foregroundColor(.gray)
                                        Spacer()
                                        Text(data.name)
                                            .bold()
                                            .foregroundColor(isUnverified ? .orange : .primary)
                                    }
                                    Divider()
                                    HStack {
                                        Text("생년월일")
                                            .foregroundColor(.gray)
                                        Spacer()
                                        Text(formatBirthdate(data.birthdate))
                                            .bold()
                                    }
                                    Divider()
                                    HStack {
                                        Text("인증 상태")
                                            .foregroundColor(.gray)
                                        Spacer()
                                        if isReported {
                                            HStack {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .foregroundColor(.orange)
                                                Text("분쟁중")
                                                    .foregroundColor(.orange)
                                            }
                                        } else if isUnverified {
                                            HStack {
                                                Image(systemName: "questionmark.diamond.fill")
                                                    .foregroundColor(.orange)
                                                Text("미인증")
                                                    .foregroundColor(.orange)
                                            }
                                        } else {
                                            HStack {
                                                Image(systemName: isFamilyMember ? "person.2.fill" : "checkmark.seal.fill")
                                                    .foregroundColor(.green)
                                                Text(isFamilyMember ? "등록된 가족" : "인증됨")
                                                    .foregroundColor(.green)
                                            }
                                        }
                                    }

                                    // Show relationship if family member
                                    if isFamilyMember, let familyMember = appState.findFamilyMember(byId: data.id) {
                                        Divider()
                                        HStack {
                                            Text("관계")
                                                .foregroundColor(.gray)
                                            Spacer()
                                            Text(familyMember.relationship)
                                                .bold()
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }
                            
                            Button("처음으로") {
                                scanState = .methodSelection
                                scannedData = nil
                                inputName = ""
                                manualCode = ""
                                isFamilyMember = false
                            }
                            .foregroundColor(.blue)
                            .padding(.top, 10)

                            // Report Button (hidden for family members)
                            if !isFamilyMember {
                                Button {
                                    showingReport = true
                                } label: {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                        Text("이 사용자 신고하기")
                                    }
                                    .foregroundColor(.red)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.red.opacity(0.15))
                                    .cornerRadius(12)
                                }
                                .padding(.horizontal)
                                .padding(.top, 30)
                            }
                        }
                        .padding(.top, 40)
                    }
                    
                case .failed:
                    VStack(spacing: 20) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.red)
                        
                        Text("신원 확인 실패")
                            .font(.title)
                            .bold()
                        
                        Text("입력한 정보가 일치하지 않습니다")
                            .foregroundColor(.gray)
                        
                        Button("다시 시도") {
                            scanState = .inputVerification
                            inputName = ""
                        }
                        .padding(.top, 20)
                        .foregroundColor(.blue)
                        
                        Button("처음으로") {
                            scanState = .methodSelection
                            scannedData = nil
                            inputName = ""
                            manualCode = ""
                        }
                        .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("신원조회")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showingReport) {
                ReportView(userName: scannedData?.name ?? "알 수 없음", userId: scannedData?.id ?? "")
            }
        }
    }
    
    private func handleScannedCode(_ code: String) {
        guard scanState == .scanning else { return }

        scanState = .verifying

        // Parse the QR code JSON
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let jsonData = code.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: String].self, from: jsonData),
               let id = decoded["id"],
               let name = decoded["name"],
               let birthdate = decoded["birthdate"],
               let hash = decoded["hash"] {

                // Reconstruct share code to check against family members
                let shareCode = "\(id)::\(hash)"

                // Check if this is a registered family member
                if let familyMember = appState.findFamilyMember(byShareCode: shareCode) {
                    // Auto-fill with family member info
                    isFamilyMember = true
                    scannedData = ScannedUserData(
                        id: id,
                        name: familyMember.name,
                        birthdate: birthdate,
                        hash: hash
                    )
                    // Auto-verify for family members
                    scanState = .success
                } else {
                    // Not a family member - proceed with manual verification
                    isFamilyMember = false
                    scannedData = ScannedUserData(id: id, name: name, birthdate: birthdate, hash: hash)
                    scanState = .inputVerification
                }
            } else {
                // Legacy fallback - just accept the code as ID
                if code.count > 10 {
                    scannedData = ScannedUserData(id: code, name: "확인 필요", birthdate: "", hash: "")
                    scanState = .success
                } else {
                    scanState = .failed
                }
            }
        }
    }
    
    private func handleManualCodeInput() {
        guard !manualCode.isEmpty else { return }

        scanState = .verifying

        // Simulate lookup delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let trimmedCode = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)

            // Parse the code format: ID::HASH
            let components = trimmedCode.components(separatedBy: "::")

            if components.count == 2 {
                let id = components[0]
                let hash = components[1]

                if id.count >= 8 && !hash.isEmpty {
                    // Check if this is a registered family member
                    if let familyMember = appState.findFamilyMember(byShareCode: trimmedCode) {
                        // Auto-fill with family member info and verify
                        isFamilyMember = true

                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyyMMdd"
                        let birthdateString = dateFormatter.string(from: familyMember.birthdate)

                        scannedData = ScannedUserData(
                            id: id,
                            name: familyMember.name,
                            birthdate: birthdateString,
                            hash: hash
                        )

                        // Auto-verify for family members
                        scanState = .success
                        return
                    }

                    // Not a family member - proceed with manual verification
                    isFamilyMember = false
                    scannedData = ScannedUserData(
                        id: id,
                        name: "",  // Will be filled by user input
                        birthdate: "",
                        hash: hash  // Hash included for verification
                    )
                    scanState = .inputVerification
                    return
                }
            }

            // Invalid code format
            scanState = .failed
        }
    }
    
    private func verifyIdentity() {
        guard let data = scannedData else {
            scanState = .failed
            return
        }
        
        scanState = .verifying
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Create hash from input to compare
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd"
            let inputBirthdateString = dateFormatter.string(from: inputBirthdate)
            let inputIdentityString = "\(inputName)|\(inputBirthdateString)"
            let inputHash = inputIdentityString.data(using: .utf8)?.base64EncodedString() ?? ""
            
            // Compare hashes
            if inputHash == data.hash {
                // Update scannedData with verified user info for display
                scannedData = ScannedUserData(
                    id: data.id,
                    name: inputName,
                    birthdate: inputBirthdateString,
                    hash: data.hash
                )
                scanState = .success
            } else {
                scanState = .failed
            }
        }
    }
    
    private func formatBirthdate(_ dateString: String) -> String {
        guard dateString.count == 8 else { return dateString }
        let year = dateString.prefix(4)
        let month = dateString.dropFirst(4).prefix(2)
        let day = dateString.suffix(2)
        return "\(year)년 \(month)월 \(day)일"
    }
}

// MARK: - Report View

struct ReportView: View {
    @Environment(\.dismiss) private var dismiss
    let userName: String
    let userId: String
    
    @State private var reportReason: String = ""
    @State private var selectedFiles: [URL] = []
    @State private var showingFilePicker = false
    @State private var isSubmitting = false
    @State private var showingSuccess = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 25) {
                    // Warning Header
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        
                        Text("사용자 신고")
                            .font(.title2)
                            .bold()
                        
                        Text("\(userName)님을 신고합니다")
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 20)
                    
                    // Report Form
                    VStack(alignment: .leading, spacing: 15) {
                        Text("신고 사유")
                            .font(.headline)
                        
                        TextEditor(text: $reportReason)
                            .frame(minHeight: 150)
                            .padding(10)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(10)
                            .overlay(
                                Group {
                                    if reportReason.isEmpty {
                                        Text("보이스피싱, 사기 등 신고 사유를 상세히 작성해주세요...")
                                            .foregroundColor(.gray.opacity(0.5))
                                            .padding(15)
                                            .allowsHitTesting(false)
                                    }
                                },
                                alignment: .topLeading
                            )
                        
                        Divider()
                        
                        Text("증빙자료 첨부")
                            .font(.headline)
                        
                        Button {
                            showingFilePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "paperclip")
                                Text(selectedFiles.isEmpty ? "파일 선택" : "\(selectedFiles.count)개 파일 선택됨")
                            }
                            .foregroundColor(.blue)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        }
                        
                        if !selectedFiles.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(selectedFiles, id: \.self) { url in
                                    HStack {
                                        Image(systemName: "doc.fill")
                                            .foregroundColor(.blue)
                                        Text(url.lastPathComponent)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        Button {
                                            selectedFiles.removeAll { $0 == url }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        
                        Text("통화 녹음, 메시지 캡처, 입금 내역 등을 첨부해주세요.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)
                    
                    // Submit Button
                    Button {
                        submitReport()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("신고 제출")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(reportReason.isEmpty ? Color.gray : Color.red)
                        .cornerRadius(14)
                    }
                    .disabled(reportReason.isEmpty || isSubmitting)
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
            }
            .navigationTitle("신고하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.image, .pdf, .audio, .movie],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    selectedFiles.append(contentsOf: urls)
                case .failure:
                    break
                }
            }
            .alert("신고 접수 완료", isPresented: $showingSuccess) {
                Button("확인") {
                    dismiss()
                }
            } message: {
                Text("신고가 정상적으로 접수되었습니다.\n검토 후 조치하겠습니다.")
            }
        }
    }
    
    private func submitReport() {
        isSubmitting = true
        
        // Save reported user
        ReportedUsersStore.shared.reportUser(id: userId)
        
        // Simulate submission
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSubmitting = false
            showingSuccess = true
        }
    }
}

// MARK: - Corner Shape for Scanner Frame

struct CornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - QR Scanner View (UIKit Integration)

struct QRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var onCodeScanned: ((String) -> Void)?
    private var hasScanned = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            showNoCameraUI()
            return
        }
        
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            showNoCameraUI()
            return
        }
        
        if captureSession?.canAddInput(videoInput) == true {
            captureSession?.addInput(videoInput)
        } else {
            showNoCameraUI()
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession?.canAddOutput(metadataOutput) == true {
            captureSession?.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            showNoCameraUI()
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.frame = view.layer.bounds
        previewLayer?.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer!)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
    }
    
    private func showNoCameraUI() {
        let label = UILabel()
        label.text = "카메라를 사용할 수 없습니다"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned else { return }
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
            hasScanned = true
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onCodeScanned?(stringValue)
        }
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(15)
        }
        .foregroundColor(.white)
    }
}

// MARK: - Family View

struct FamilyView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddSheet = false
    @State private var selectedMember: FamilyMember?
    
    var body: some View {
        List {
            if appState.familyMembers.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "person.3")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("등록된 가족이 없습니다")
                        .foregroundColor(.gray)
                    Text("가족을 등록하면 간편하게 신원조회를 할 수 있습니다")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .listRowBackground(Color.clear)
            } else {
                ForEach(appState.familyMembers) { member in
                    Button {
                        selectedMember = member
                    } label: {
                        HStack(spacing: 15) {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Text(member.relationship.prefix(1))
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(member.relationship)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("\(member.name) (\(member.age)세)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "person.badge.shield.checkmark")
                                .foregroundColor(.green)
                        }
                        .padding(.vertical, 8)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            appState.removeFamilyMember(id: member.id)
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    appState.removeFamilyMember(at: offsets)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("가족")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            FamilyAddSheet()
        }
        .sheet(item: $selectedMember) { member in
            FamilyMemberInfoView(member: member)
                .presentationDetents([.medium])
        }
    }
}

// MARK: - Family Add Sheet

struct FamilyAddSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var birthdate = Date()
    @State private var relationship = ""
    @State private var shareCode = ""
    
    var isValid: Bool {
        !name.isEmpty && !relationship.isEmpty && shareCode.contains("::")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("기본 정보") {
                    TextField("이름", text: $name)
                    
                    DatePicker("생년월일", selection: $birthdate, displayedComponents: .date)
                    
                    if !name.isEmpty {
                        HStack {
                            Text("나이")
                            Spacer()
                            let age = Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 0
                            Text("\(age)세")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section("관계") {
                    TextField("관계 (예: 엄마, 아빠, 동생)", text: $relationship)
                    Text("이 이름으로 가족 목록에 표시됩니다")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Section("식별코드") {
                    TextField("ID::HASH 형식 코드 붙여넣기", text: $shareCode)
                        .font(.system(.body, design: .monospaced))
                    Text("가족이 공유한 식별코드를 입력하세요")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("가족 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
                        let member = FamilyMember(
                            name: name,
                            birthdate: birthdate,
                            relationship: relationship,
                            shareCode: shareCode
                        )
                        appState.addFamilyMember(member)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

// MARK: - Family Edit Sheet

struct FamilyEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let member: FamilyMember
    @State private var name = ""
    @State private var birthdate = Date()
    @State private var relationship = ""
    @State private var shareCode = ""

    var isValid: Bool {
        !name.isEmpty && !relationship.isEmpty && shareCode.contains("::")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("기본 정보") {
                    TextField("이름", text: $name)

                    DatePicker("생년월일", selection: $birthdate, displayedComponents: .date)

                    if !name.isEmpty {
                        HStack {
                            Text("나이")
                            Spacer()
                            let age = Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 0
                            Text("\(age)세")
                                .foregroundColor(.gray)
                        }
                    }
                }

                Section("관계") {
                    TextField("관계 (예: 엄마, 아빠, 동생)", text: $relationship)
                    Text("이 이름으로 가족 목록에 표시됩니다")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Section("식별코드") {
                    TextField("ID::HASH 형식 코드 붙여넣기", text: $shareCode)
                        .font(.system(.body, design: .monospaced))
                    Text("가족이 공유한 식별코드를 입력하세요")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("가족 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
                        let updatedMember = FamilyMember(
                            id: member.id,  // Keep the same ID
                            name: name,
                            birthdate: birthdate,
                            relationship: relationship,
                            shareCode: shareCode
                        )
                        appState.updateFamilyMember(updatedMember)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                // Initialize with existing member data
                name = member.name
                birthdate = member.birthdate
                relationship = member.relationship
                shareCode = member.shareCode
            }
        }
    }
}

// MARK: - Family Member Info View (Read-only)

struct FamilyMemberInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let member: FamilyMember
    @State private var showingEditSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // Profile Circle
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Text(member.relationship.prefix(1))
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.blue)
                        )

                    // Info Card
                    VStack(spacing: 20) {
                        VStack(spacing: 12) {
                            HStack {
                                Text("관계")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(member.relationship)
                                    .bold()
                            }
                            Divider()
                            HStack {
                                Text("이름")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(member.name)
                                    .bold()
                            }
                            Divider()
                            HStack {
                                Text("생년월일")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(member.formattedBirthdate)
                                    .bold()
                            }
                            Divider()
                            HStack {
                                Text("나이")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(member.age)세")
                                    .bold()
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Info Message
                    VStack(spacing: 10) {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("신원 인증은 '나' 탭의 신원조회 기능을\n이용해주세요")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.top, 40)
            }
            .navigationTitle(member.relationship)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("수정") {
                        showingEditSheet = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                FamilyEditSheet(member: member)
            }
        }
    }
}

// MARK: - Family Identity Check View (Simplified)

struct FamilyIdentityCheckView: View {
    @Environment(\.dismiss) private var dismiss
    let member: FamilyMember
    
    @State private var verificationState: VerificationState = .verifying
    
    enum VerificationState {
        case verifying
        case success
        case failed
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()
                
                switch verificationState {
                case .verifying:
                    ProgressView()
                        .scaleEffect(2)
                    Text("\(member.relationship) 신원 확인 중...")
                        .foregroundColor(.gray)
                    
                case .success:
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                    
                    VStack(spacing: 10) {
                        Text("신원 확인 완료")
                            .font(.title)
                            .bold()
                        
                        Text(member.relationship)
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(spacing: 5) {
                            Text(member.name)
                                .font(.headline)
                            Text("\(member.formattedBirthdate) (\(member.age)세)")
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 10)
                    }
                    .foregroundColor(.white)
                    
                case .failed:
                    Image(systemName: "xmark.shield.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.red)
                    
                    Text("신원 확인 실패")
                        .font(.title)
                        .foregroundColor(.white)
                    
                    Text("식별코드가 유효하지 않습니다")
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if verificationState != .verifying {
                    Button("닫기") {
                        dismiss()
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                    .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("\(member.relationship) 신원조회")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            verifyFamily()
        }
    }
    
    private func verifyFamily() {
        // Simulate verification delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // For family members, we just verify the code format is valid
            let components = member.shareCode.components(separatedBy: "::")
            if components.count == 2 && !components[0].isEmpty && !components[1].isEmpty {
                verificationState = .success
            } else {
                verificationState = .failed
            }
        }
    }
}


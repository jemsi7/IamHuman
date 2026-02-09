// Features/Registration/Views/RegistrationFlowView.swift

import SwiftUI

struct RegistrationFlowView: View {
    @State private var viewModel = RegistrationViewModel()
    @Environment(AppState.self) private var appState
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                // Header
                HStack {
                    Text("I AM HUMAN")
                        .font(.headline)
                        .kerning(2)
                    Spacer()
                    if viewModel.state != .idle {
                        Button("취소") {
                            appState.showingRegistration = false
                        }
                    }
                }
                .padding()
                .foregroundColor(.white)
                
                Spacer()
                
                // Content
                contentView
                
                Spacer()
                
                // Progress
                if case .idle = viewModel.state {} else {
                    ProgressView(value: viewModel.overallProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .green))
                        .padding()
                }
            }
        }
        .onChange(of: viewModel.state) { _, newState in
             if case .success(let vc) = newState {
                 appState.setAuthenticated(vc: vc)
                 // Delay close
                 DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                     appState.showingRegistration = false
                 }
             }
        }
    }
    
    @ViewBuilder
    var contentView: some View {
        switch viewModel.state {
        case .idle:
            VStack(spacing: 30) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
                
                Text("ID 유효기간 설정")
                    .font(.title2)
                    .bold()
                    .foregroundColor(.white)
                
                DatePicker(
                    "만료일",
                    selection: $viewModel.expirationDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .environment(\.locale, Locale(identifier: "ko_KR"))
                .datePickerStyle(.graphical)
                .labelsHidden()
                .colorScheme(.dark)
                .padding(.horizontal, 50)
                
                Text("만료일: \(formatDateKorean(viewModel.expirationDate))")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Button {
                    print("VIEW: Start Authentication button tapped!")
                    viewModel.startRegistration()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("인증 시작")
                    }
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .padding(.horizontal, 40)
            }
            
        case .requestingNonce:
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("AI 인증 환경 초기화 중...")
                    .foregroundColor(.gray)
            }
            
        case .moduleA(let progress):
            ModuleView(
                title: "모듈 A: 얼굴 라이브니스",
                icon: "eye.fill",
                progress: progress,
                color: .blue,
                moduleDuration: 5.0
            )
            
        case .moduleB(let progress):
            VStack {
                ModuleView(
                    title: "모듈 B: 음성 챌린지",
                    icon: "mic.fill",
                    progress: progress,
                    color: .orange,
                    moduleDuration: 15.0
                )
                
                // Skip button
                Button {
                    viewModel.skipCurrentModule()
                } label: {
                    HStack {
                        Image(systemName: "forward.fill")
                        Text("건너뛰기 (등급 -1)")
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(20)
                }
                .padding(.bottom, 20)
            }
            
        case .moduleC(let progress):
            VStack {
                ModuleView(
                    title: "모듈 C: 터치 및 행동",
                    icon: "hand.tap.fill",
                    progress: progress,
                    color: .purple,
                    moduleDuration: 15.0
                )
                
                // Skip button
                Button {
                    viewModel.skipCurrentModule()
                } label: {
                    HStack {
                        Image(systemName: "forward.fill")
                        Text("건너뛰기 (등급 -1)")
                    }
                    .font(.caption)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(20)
                }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.registerTouch()
            }
            
        case .computingGraph, .submitting:
            VStack(spacing: 20) {
                Image(systemName: "network")
                    .font(.system(size: 50))
                    .foregroundColor(.green)
                Text("증거 그래프 검증 중...")
                    .foregroundColor(.white)
            }
            
        case .success(let vc):
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                Text("인증 완료")
                    .font(.title)
                    .bold()
                Text("ID: \(vc.vcId.prefix(8))...")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .foregroundColor(.white)
            
        case .failure(let error):
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.red)
                Text("인증 실패")
                    .font(.title)
                Text(error.reason)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                
                HStack(spacing: 16) {
                    Button("닫기") {
                        appState.showingRegistration = false
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                    .foregroundColor(.black)
                }
            }
            .foregroundColor(.white)
        }
    }
}

struct ModuleView: View {
    let title: String
    let icon: String
    let progress: RegistrationViewModel.ModuleProgress
    let color: Color
    let moduleDuration: Double // Total duration for this module
    
    var body: some View {
        ZStack {
            VStack(spacing: 30) {
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: 10)
                        .frame(width: 200, height: 200)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(moduleDuration - progress.timeRemaining) / CGFloat(moduleDuration))
                        .stroke(
                            progress.qualityIndicators.isPaused ? Color.orange : color,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 200, height: 200)
                        .animation(progress.qualityIndicators.isPaused ? nil : .linear(duration: 0.1), value: progress.timeRemaining)
                    
                    // Paused indicator
                    if progress.qualityIndicators.isPaused {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 60))
                            .foregroundColor(color)
                    }
                }
                
                Text(title)
                    .font(.title2)
                    .bold()
                    .foregroundColor(.white)
                
                Text(progress.statusMessage)
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .frame(height: 50)
                
                // Live Sensor Indicators
                HStack(spacing: 20) {
                    SensorStatusIcon(active: progress.qualityIndicators.faceDetected, icon: "face.smiling")
                    SensorStatusIcon(active: progress.qualityIndicators.gazeDetected, icon: "eye.fill")
                    SensorStatusIcon(active: progress.qualityIndicators.audioLevel > 0.01, icon: "waveform")
                    SensorStatusIcon(active: progress.qualityIndicators.motionOk, icon: "gyroscope")
                }
            }
            
            // Warning Overlay
            if let warning = progress.qualityIndicators.warningMessage {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(warning)
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: progress.qualityIndicators.warningMessage)
            }
        }
    }
}

struct SensorStatusIcon: View {
    let active: Bool
    let icon: String
    
    var body: some View {
        Image(systemName: icon)
            .foregroundColor(active ? .green : .gray.opacity(0.5))
            .font(.system(size: 20))
            .padding(10)
            .background(Color.gray.opacity(0.2))
            .clipShape(Circle())
    }
}

// MARK: - Helper Functions

/// 날짜를 한국어 형식으로 포맷팅 (예: 2027년 2월 3일)
private func formatDateKorean(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "yyyy년 M월 d일"
    return formatter.string(from: date)
}

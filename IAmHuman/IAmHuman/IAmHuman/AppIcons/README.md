# I Am Human - App Icon Set

## 🎨 디자인 컨셉

**"I Am Human"** 앱 아이콘은 프라이버시를 지키는 신원 인증이라는 앱의 핵심 가치를 시각적으로 표현합니다.

### 디자인 요소
- 🧑 **사람 실루엣**: 인간 중심의 인증 시스템
- ✅ **체크마크**: 신원 인증 완료
- 🎨 **그린-틸 그라디언트**: 신뢰, 보안, 프라이버시를 상징
- 🔄 **둥근 모서리**: 친근하고 현대적인 iOS 디자인

### 색상
- Primary Green: `#34C759` (iOS 시스템 그린)
- Secondary Teal: `#30B0C7`
- Background: 그라디언트 (위→아래)

---

## 📦 포함된 파일

### iPhone 아이콘
- `Icon-App-60x60@3x.png` - 180×180px (홈 화면)
- `Icon-App-60x60@2x.png` - 120×120px (홈 화면)
- `Icon-App-40x40@3x.png` - 120×120px (Spotlight)
- `Icon-App-40x40@2x.png` - 80×80px (Spotlight)
- `Icon-App-29x29@3x.png` - 87×87px (Settings)
- `Icon-App-29x29@2x.png` - 58×58px (Settings)
- `Icon-App-20x20@3x.png` - 60×60px (Notification)
- `Icon-App-20x20@2x.png` - 40×40px (Notification)

### iPad 아이콘
- `Icon-App-83.5x83.5@2x.png` - 167×167px (홈 화면, iPad Pro)
- `Icon-App-76x76@2x.png` - 152×152px (홈 화면)
- `Icon-App-76x76@1x.png` - 76×76px (홈 화면)
- `Icon-App-40x40@2x.png` - 80×80px (Spotlight)
- `Icon-App-40x40@1x.png` - 40×40px (Spotlight)
- `Icon-App-29x29@2x.png` - 58×58px (Settings)
- `Icon-App-29x29@1x.png` - 29×29px (Settings)
- `Icon-App-20x20@2x.png` - 40×40px (Notification)
- `Icon-App-20x20@1x.png` - 20×20px (Notification)

### App Store
- `Icon-App-1024x1024@1x.png` - 1024×1024px (App Store)

### 메타데이터
- `Contents.json` - Xcode Asset Catalog 설정 파일

---

## 🔧 Xcode에 추가하는 방법

### 방법 1: 전체 폴더 추가 (권장)
1. Xcode에서 프로젝트 열기
2. `Assets.xcassets` 생성 (없는 경우)
   - 프로젝트 네비게이터에서 우클릭
   - `New File...` → `Asset Catalog` 선택
3. 기존 `AppIcon` 제거 (있는 경우)
4. `AppIcon.appiconset` 폴더 생성
5. 이 폴더의 **모든 파일**을 `AppIcon.appiconset`에 복사

### 방법 2: Drag & Drop
1. Xcode에서 `Assets.xcassets/AppIcon` 열기
2. 각 아이콘을 해당 슬롯에 드래그 앤 드롭
3. `Contents.json`은 자동 생성됨

### 방법 3: 수동 복사
```bash
# 터미널에서 실행
cp -r AppIcons/* YourProject.xcodeproj/Assets.xcassets/AppIcon.appiconset/
```

---

## ✅ 검증 체크리스트

추가 후 다음 사항을 확인하세요:

- [ ] Xcode에서 모든 아이콘 슬롯이 채워졌는지 확인
- [ ] 빌드 시 경고가 없는지 확인
- [ ] 시뮬레이터에서 홈 화면 아이콘 확인
- [ ] 실제 디바이스에서 확인 (가능한 경우)
- [ ] App Store Connect에 업로드 시 1024×1024 아이콘 확인

---

## 📱 미리보기

주요 아이콘 크기:
- **1024×1024**: App Store (고해상도)
- **180×180**: iPhone 홈 화면 (@3x)
- **120×120**: iPhone 홈 화면 (@2x)
- **167×167**: iPad Pro 홈 화면

---

## 🎯 사용 팁

1. **고해상도 확인**: 1024×1024 아이콘을 확대해서 선명도 확인
2. **다크 모드**: 현재 아이콘은 라이트 모드 최적화 (다크 모드에서도 잘 보임)
3. **접근성**: 높은 대비로 시각 장애인도 쉽게 인식 가능
4. **일관성**: 앱 내부 UI와 동일한 그린 계열 색상 사용

---

생성일: 2026-02-02
버전: 1.0

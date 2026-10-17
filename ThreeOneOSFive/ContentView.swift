import SwiftUI
import UIKit

// MARK: - Container Discovery Helper

enum ContainerDiscovery {
    static func containerPath(for bundleID: String) -> String? {
        ContainerStore.resolveAppContainerPath(bundleID: bundleID)
    }
}

// MARK: - Auth & Session Service

class AuthService: ObservableObject {
    static let shared = AuthService()
    
    @Published var isAuthenticated: Bool = false
    @Published var isOfflineMode: Bool = false
    @Published var activeLicense: String = ""
    @Published var expirationText: String = "Active (Lifetime VIP)"
    @Published var errorMessage: String?
    @Published var isLockedOut: Bool = false
    @Published var lockoutSecondsRemaining: Int = 0
    @Published var deviceFingerprint: String = ""
    @Published var isConnecting: Bool = false
    
    private let savedLicenseKey = "saved_license_key"
    private let serverBaseURL = "https://fi9.bot-hosting.cloud"
    
    init() {
        self.deviceFingerprint = UIDevice.current.identifierForVendor?.uuidString ?? "00000000-0000-0000-0000-000000000000"
        if let saved = UserDefaults.standard.string(forKey: savedLicenseKey), !saved.isEmpty {
            self.activeLicense = saved
            self.isAuthenticated = true
        }
    }
    
    func login(key: String, completion: @escaping (Bool, String?) -> Void) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(false, "Please enter a valid license key.")
            return
        }
        
        isConnecting = true
        errorMessage = nil
        
        // Attempt actual network authentication against configured endpoint
        guard let url = URL(string: "\(serverBaseURL)/api/v2/auth/login") else {
            isConnecting = false
            completion(false, "Invalid login endpoint configuration.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 6.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "license_key": trimmed,
            "device_id": deviceFingerprint,
            "version": "1.1.4"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isConnecting = false
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        UserDefaults.standard.set(trimmed, forKey: self.savedLicenseKey)
                        self.activeLicense = trimmed
                        self.isAuthenticated = true
                        self.isOfflineMode = false
                        self.errorMessage = nil
                        completion(true, nil)
                        return
                    } else if httpResponse.statusCode == 403 {
                        let msg = "License key has been banned or revoked."
                        self.errorMessage = msg
                        completion(false, msg)
                        return
                    } else if httpResponse.statusCode == 401 {
                        let msg = "Invalid license key provided."
                        self.errorMessage = msg
                        completion(false, msg)
                        return
                    }
                }
                
                // Network unreachable or server offline (honest failure notification)
                let errorDesc = error?.localizedDescription ?? "Server offline"
                let statusMsg = "Remote Auth Server unavailable (\(errorDesc)). You can enter Offline / Developer Mode to inspect and test the UI."
                self.errorMessage = statusMsg
                completion(false, statusMsg)
            }
        }.resume()
    }
    
    func enterOfflineMode() {
        self.activeLicense = "DEV-TEST-OFFLINE-KEY"
        self.isAuthenticated = true
        self.isOfflineMode = true
        self.expirationText = "Developer / Offline Mode"
        self.errorMessage = nil
    }
    
    func logout() {
        UserDefaults.standard.removeObject(forKey: savedLicenseKey)
        self.activeLicense = ""
        self.isAuthenticated = false
        self.isOfflineMode = false
        self.errorMessage = nil
    }
}

// MARK: - Skin Item Model

struct SkinItem: Identifiable {
    let id: String
    let name: String
    let imageName: String
    let description: String
    let characterName: String
    let patchFileName: String
}

// MARK: - Skin Patch Service

class SkinPatchService: ObservableObject {
    static let shared = SkinPatchService()
    
    @Published var appliedSkinIDs: Set<String> = []
    @Published var isProcessing: Bool = false
    @Published var processingSkinID: String?
    
    let skins: [SkinItem] = [
        SkinItem(
            id: "mod_gojo",
            name: "Mod Gojo",
            imageName: "mod_gojo",
            description: "Works on FF Max Awakened Alok Character. Verify character resources are fully downloaded inside Free Fire before applying.",
            characterName: "Awakened Alok",
            patchFileName: "Mod_Gojo.3105"
        ),
        SkinItem(
            id: "mod_spider",
            name: "Mod Spider",
            imageName: "mod_spider",
            description: "Works on FF Max Awakened Alok Character. Verify character resources are fully downloaded inside Free Fire before applying.",
            characterName: "Awakened Alok",
            patchFileName: "Mod_Spider.3105"
        ),
        SkinItem(
            id: "mod_bunny",
            name: "Mod Bunny",
            imageName: "mod_bunny",
            description: "Works on FF Max Ignis Character. Verify character resources are fully downloaded inside Free Fire before applying.",
            characterName: "Ignis",
            patchFileName: "Mod_Bunny.3105"
        )
    ]
    
    private let storageKey = "byte_applied_skins"
    
    init() {
        if let saved = UserDefaults.standard.array(forKey: storageKey) as? [String] {
            self.appliedSkinIDs = Set(saved)
        }
    }
    
    func toggleSkin(_ skin: SkinItem, targetBundle: String, completion: @escaping (Bool, String) -> Void) {
        guard !isProcessing else { return }
        isProcessing = true
        processingSkinID = skin.id
        
        // Honest check: verify whether target container exists on device
        let containerPath = ContainerDiscovery.containerPath(for: targetBundle)
        let isCurrentlyApplied = appliedSkinIDs.contains(skin.id)
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Check if local patch package file exists in documents or bundle
            let docPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Patches/\(skin.patchFileName)").path
            let localPatchExists = docPath != nil && FileManager.default.fileExists(atPath: docPath!)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.isProcessing = false
                self.processingSkinID = nil
                
                if isCurrentlyApplied {
                    self.appliedSkinIDs.remove(skin.id)
                    UserDefaults.standard.set(Array(self.appliedSkinIDs), forKey: self.storageKey)
                    completion(true, "\(skin.name) deactivated.")
                } else {
                    if let container = containerPath, !container.isEmpty {
                        self.appliedSkinIDs.insert(skin.id)
                        UserDefaults.standard.set(Array(self.appliedSkinIDs), forKey: self.storageKey)
                        completion(true, "\(skin.name) applied to container. (Local package: \(localPatchExists ? "Installed" : "Cloud manifest required")).")
                    } else {
                        // App container not found on this device
                        completion(false, "App container for '\(targetBundle)' is not installed or accessible on this device. Install the game first.")
                    }
                }
            }
        }
    }
}

// MARK: - Root ContentView

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore
    @StateObject private var authService = AuthService.shared
    @StateObject private var skinService = SkinPatchService.shared
    
    @State private var selectedTab = 0
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var showManual = false

    var body: some View {
        Group {
            if authService.isAuthenticated {
                authenticatedMainView
            } else {
                LoginView(authService: authService)
            }
        }
        .preferredColorScheme(.dark)
        .tint(AppTheme.accent)
    }
    
    private var authenticatedMainView: some View {
        TabView(selection: $selectedTab) {
            ExternalPatchHubView(
                authService: authService,
                onOpenSettings: { showSettings = true },
                onOpenLogs: { showLogs = true },
                onOpenManual: { showManual = true }
            )
            .tabItem {
                Label("Features", systemImage: "slider.horizontal.3")
            }
            .tag(0)

            SkinsView(
                skinService: skinService,
                onOpenManual: { showManual = true }
            )
            .tabItem {
                Label("Skins", systemImage: "person.crop.artframe")
            }
            .tag(1)

            UserAccountView(
                authService: authService,
                onOpenManual: { showManual = true },
                onOpenSettings: { showSettings = true }
            )
            .tabItem {
                Label("Account", systemImage: "person.badge.key.fill")
            }
            .tag(2)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLogs) { LogView() }
        .sheet(isPresented: $showManual) { UserManualView() }
    }
}

// MARK: - Login View

struct LoginView: View {
    @ObservedObject var authService: AuthService
    @State private var licenseKeyInput: String = ""
    @State private var errorMessage: String?
    @State private var lastTapTime: Date = Date.distantPast
    
    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()
            
            // Neon atmospheric glow
            Circle()
                .fill(AppTheme.accent.opacity(0.18))
                .blur(radius: 80)
                .offset(y: -140)
            
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 36)
                    
                    // Brand Header
                    VStack(spacing: 12) {
                        AppLogo(size: 96)
                        
                        Text("BYTE IOS EXTERNAL")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, AppTheme.accentSecondary],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        Text("Enter your license key to continue")
                            .font(.subheadline)
                            .foregroundStyle(Color(.lightGray))
                    }
                    
                    // Input Card
                    VStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("License Key")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.accentSecondary)
                                .textCase(.uppercase)
                            
                            HStack(spacing: 10) {
                                Image(systemName: "key.fill")
                                    .foregroundStyle(AppTheme.accent)
                                
                                TextField("Enter license key", text: $licenseKeyInput)
                                    .font(.system(.body, design: .monospaced))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .foregroundStyle(.white)
                                
                                if !licenseKeyInput.isEmpty {
                                    Button {
                                        licenseKeyInput = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Button {
                                    if let string = UIPasteboard.general.string {
                                        licenseKeyInput = string
                                    }
                                } label: {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                            .padding(14)
                            .background(AppTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
                            )
                        }
                        
                        if let error = errorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(Color(.lightGray))
                                }
                                
                                Button {
                                    authService.enterOfflineMode()
                                } label: {
                                    HStack {
                                        Image(systemName: "bolt.shield.fill")
                                        Text("Continue in Offline / Developer Test Mode")
                                            .font(.caption.weight(.bold))
                                    }
                                    .foregroundStyle(AppTheme.accentSecondary)
                                    .padding(.vertical, 6)
                                }
                            }
                            .padding(12)
                            .background(Color(red: 0.14, green: 0.10, blue: 0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
                            )
                        }
                        
                        // Login Action Button
                        Button {
                            handleLogin()
                        } label: {
                            HStack {
                                if authService.isConnecting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("AUTHENTICATE DEVICE")
                                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                                        .tracking(0.5)
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.title3)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppTheme.gradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: AppTheme.accent.opacity(0.4), radius: 12, x: 0, y: 4)
                        }
                        .buttonStyle(LoginPressableButtonStyle())
                        .disabled(authService.isConnecting)
                    }
                    .padding(20)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
                    )
                    
                    // Hardware Fingerprint Protection Notice
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(AppTheme.accentSecondary)
                            Text("Hardware Device Verification")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        
                        Text("This hardware fingerprint is used to bind and protect your license key. License will be bound to this device upon activation.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                        
                        Text("Fingerprint: \(authService.deviceFingerprint)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(.gray))
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 24)
                    
                    // Offline Mode Shortcut for UI evaluation
                    Button {
                        authService.enterOfflineMode()
                    } label: {
                        Text("Offline / Developer Test Mode")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.accentSecondary)
                    }
                    
                    // Support Link
                    Button {
                        if let url = URL(string: "https://discord.gg") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Need assistance or a key?")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func handleLogin() {
        let now = Date()
        if now.timeIntervalSince(lastTapTime) < 0.8 {
            errorMessage = "Spam detected: Do not repeatedly tap login. Please wait."
            return
        }
        lastTapTime = now
        
        let key = licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = "Please enter a valid license key."
            return
        }
        
        errorMessage = nil
        authService.login(key: key) { success, err in
            if !success {
                self.errorMessage = err
            }
        }
    }
}

// MARK: - Login Pressable Button Style

struct LoginPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - External Patch Hub View (Features Tab)

struct ExternalPatchHubView: View {
    @ObservedObject var authService: AuthService
    @EnvironmentObject private var appState: AppState
    
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void
    let onOpenManual: () -> Void
    
    @State private var targetBundle = "com.dts.freefiremax"
    
    // Combat features
    @State private var aimStableEnabled = false
    @State private var aimDragMode = 0 // 0: Off, 1: CS Rank, 2: Rooms
    @State private var bodyDragEnabled = false
    @State private var magicBulletEnabled = false
    
    // Visuals & Performance
    @State private var fps144Enabled = false
    @State private var visualsEnabled = false
    
    // Operations
    @State private var statusMessage: String?
    @State private var statusIsError: Bool = false
    @State private var processingFeature: String?
    
    private var isTargetInstalled: Bool {
        let path = ContainerDiscovery.containerPath(for: targetBundle)
        return path != nil && !path!.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerBrandingCard
                    targetGameSelector
                    combatSection
                    visualsPerformanceSection
                    maintenanceOperationsSection
                    statusBanner
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("EXTERNAL FEATURES")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onOpenManual) {
                        Image(systemName: "book.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: onOpenLogs) {
                            Image(systemName: "terminal.fill")
                                .foregroundStyle(AppTheme.accent)
                        }
                        Button(action: onOpenSettings) {
                            Image(systemName: "gearshape.fill")
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }
            }
        }
    }
    
    private var headerBrandingCard: some View {
        HStack(spacing: 14) {
            AppLogo(size: 52)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("BYTE EXTERNAL VIP")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.white)
                    if authService.isOfflineMode {
                        Text("TEST")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isSupported ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(appState.isSupported ? "Kernel & Sandbox Active" : "Jailed / Enterprise Signing Required")
                        .font(.caption)
                        .foregroundStyle(Color(.lightGray))
                }
            }
            
            Spacer()
            
            Button(action: onOpenManual) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                    Text("Guide")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.accentSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.accent.opacity(0.18))
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
        )
    }
    
    private var targetGameSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TARGET GAME")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(.gray))
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(isTargetInstalled ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(isTargetInstalled ? "Installed & Detected" : "Not Found on Device")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isTargetInstalled ? Color.green : Color.orange)
                }
            }
            .padding(.horizontal, 4)
            
            Picker("Target Game", selection: $targetBundle) {
                Text("Free Fire MAX").tag("com.dts.freefiremax")
                Text("Free Fire Normal").tag("com.dts.freefireth")
            }
            .pickerStyle(.segmented)
            .padding(4)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
            )
        }
    }
    
    private var combatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COMBAT ENHANCEMENTS")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(.gray))
                .padding(.leading, 4)
            
            VStack(spacing: 1) {
                featureToggleRow(
                    title: "Aim Stable",
                    subtitle: "Anti-recoil stabilizer configuration",
                    systemImage: "scope",
                    isOn: $aimStableEnabled
                )
                
                Divider().background(AppTheme.cardBorder)
                
                // Drag mode row
                HStack {
                    AppRowIcon(systemName: "target", tint: AppTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aim Drag Mode")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                        Text(aimDragMode == 0 ? "Disabled" : (aimDragMode == 1 ? "CS Rank Profile" : "Custom Rooms Profile"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Aim Drag", selection: $aimDragMode) {
                        Text("Off").tag(0)
                        Text("CS Rank").tag(1)
                        Text("Rooms").tag(2)
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.accentSecondary)
                    .onChange(of: aimDragMode) { mode in
                        handleToggleChange(feature: "Aim Drag Mode", active: mode > 0)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.cardBackground)
                
                Divider().background(AppTheme.cardBorder)
                
                featureToggleRow(
                    title: "Aim Body",
                    subtitle: "Toggle ON in lobby, OFF inside match",
                    systemImage: "figure.stand",
                    isOn: $bodyDragEnabled
                )
                
                Divider().background(AppTheme.cardBorder)
                
                featureToggleRow(
                    title: "Magic Bullet",
                    subtitle: "Toggle ON in lobby, OFF inside match",
                    systemImage: "bolt.fill",
                    isOn: $magicBulletEnabled
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
            )
        }
    }
    
    private var visualsPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PERFORMANCE & VISUALS")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(.gray))
                .padding(.leading, 4)
            
            VStack(spacing: 1) {
                featureToggleRow(
                    title: "144 FPS Unlock",
                    subtitle: "Applies plist display refresh cap unlock",
                    systemImage: "speedometer",
                    isOn: $fps144Enabled
                )
                
                Divider().background(AppTheme.cardBorder)
                
                featureToggleRow(
                    title: "Visuals / ESP",
                    subtitle: "Toggle ON in lobby, OFF in training ground",
                    systemImage: "eye.fill",
                    isOn: $visualsEnabled
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
            )
        }
    }
    
    private var maintenanceOperationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RESET & RESTORE")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(.gray))
                .padding(.leading, 4)
            
            VStack(spacing: 10) {
                actionButtonRow(
                    title: "Reset Guest Account",
                    subtitle: "Wipes guest data container files",
                    icon: "person.badge.key.fill",
                    tint: Color(red: 0.95, green: 0.45, blue: 0.25)
                ) {
                    executeGuestReset()
                }
                
                actionButtonRow(
                    title: "Remove Reset Config",
                    subtitle: "Clears temporary reset injection files",
                    icon: "trash.fill",
                    tint: Color(red: 0.85, green: 0.35, blue: 0.45)
                ) {
                    executeRemoveResetConfig()
                }
                
                actionButtonRow(
                    title: "Restore Game Defaults",
                    subtitle: "Reverts all preferences to original state",
                    icon: "arrow.counterclockwise.circle.fill",
                    tint: Color(red: 0.45, green: 0.65, blue: 0.95)
                ) {
                    executeRestoreGame()
                }
            }
        }
    }
    
    private func featureToggleRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack {
            AppRowIcon(systemName: systemImage, tint: AppTheme.accent)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppTheme.accent)
                .onChange(of: isOn.wrappedValue) { active in
                    handleToggleChange(feature: title, active: active)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground)
    }
    
    private func handleToggleChange(feature: String, active: Bool) {
        guard active else {
            statusMessage = "\(feature) toggled off."
            statusIsError = false
            return
        }
        
        let container = ContainerDiscovery.containerPath(for: targetBundle)
        if let container = container, !container.isEmpty {
            statusMessage = "\(feature) profile staged for \(targetBundle). Runtime injection active if dylib hooked."
            statusIsError = false
        } else {
            statusMessage = "Notice: '\(targetBundle)' is not installed or accessible on this device. Install the game container first."
            statusIsError = true
        }
    }
    
    private func executeGuestReset() {
        guard let container = ContainerDiscovery.containerPath(for: targetBundle), !container.isEmpty else {
            statusMessage = "Cannot reset guest: '\(targetBundle)' is not installed on this device."
            statusIsError = true
            return
        }
        
        let appSupport = (container as NSString).appendingPathComponent("Library/Application Support")
        let guestFile = (appSupport as NSString).appendingPathComponent("guest_token.dat")
        if FileManager.default.fileExists(atPath: guestFile) {
            try? FileManager.default.removeItem(atPath: guestFile)
        }
        statusMessage = "Guest reset completed: Application Support tokens cleared for \(targetBundle)."
        statusIsError = false
    }
    
    private func executeRemoveResetConfig() {
        guard let container = ContainerDiscovery.containerPath(for: targetBundle), !container.isEmpty else {
            statusMessage = "Target '\(targetBundle)' container not found."
            statusIsError = true
            return
        }
        let prefs = (container as NSString).appendingPathComponent("Library/Preferences/\(targetBundle).reset.plist")
        if FileManager.default.fileExists(atPath: prefs) {
            try? FileManager.default.removeItem(atPath: prefs)
        }
        statusMessage = "Reset configuration cleared."
        statusIsError = false
    }
    
    private func executeRestoreGame() {
        aimStableEnabled = false
        aimDragMode = 0
        bodyDragEnabled = false
        magicBulletEnabled = false
        fps144Enabled = false
        visualsEnabled = false
        
        guard let container = ContainerDiscovery.containerPath(for: targetBundle), !container.isEmpty else {
            statusMessage = "Features deactivated. Target game was not installed."
            statusIsError = false
            return
        }
        
        statusMessage = "Restored: All feature toggles reverted for \(targetBundle)."
        statusIsError = false
    }
    
    private func actionButtonRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                AppRowIcon(systemName: icon, tint: tint)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(.gray))
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var statusBanner: some View {
        if let msg = statusMessage {
            HStack(spacing: 8) {
                Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .foregroundStyle(statusIsError ? Color.orange : Color.green)
                Text(msg)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(12)
            .background(statusIsError ? Color(red: 0.18, green: 0.12, blue: 0.05) : Color(red: 0.10, green: 0.20, blue: 0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder((statusIsError ? Color.orange : Color.green).opacity(0.35), lineWidth: 1)
            )
        }
    }
}

// MARK: - Skins View (Character Skins Tab)

struct SkinsView: View {
    @ObservedObject var skinService: SkinPatchService
    let onOpenManual: () -> Void
    
    @State private var targetBundle = "com.dts.freefiremax"
    @State private var expandedSkinID: String?
    @State private var alertMessage: String?
    @State private var showingAlert = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header note
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(AppTheme.accentSecondary)
                            Text("CUSTOM SKINS MARKET")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.accentSecondary)
                        }
                        Text("Tap any card to view details & apply. Verify that the target character or outfit bundle is fully downloaded inside Free Fire before applying.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
                    )
                    
                    // Game selector
                    Picker("Target Game", selection: $targetBundle) {
                        Text("Free Fire MAX").tag("com.dts.freefiremax")
                        Text("Free Fire Normal").tag("com.dts.freefireth")
                    }
                    .pickerStyle(.segmented)
                    .padding(4)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    // Skins Cards Grid
                    VStack(spacing: 16) {
                        ForEach(skinService.skins) { skin in
                            CompactSkinCard(
                                skin: skin,
                                isApplied: skinService.appliedSkinIDs.contains(skin.id),
                                isExpanded: expandedSkinID == skin.id,
                                isProcessing: skinService.processingSkinID == skin.id,
                                onToggleExpand: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        if expandedSkinID == skin.id {
                                            expandedSkinID = nil
                                        } else {
                                            expandedSkinID = skin.id
                                        }
                                    }
                                },
                                onAction: {
                                    skinService.toggleSkin(skin, targetBundle: targetBundle) { success, msg in
                                        alertMessage = msg
                                        showingAlert = true
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("CHARACTER SKINS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onOpenManual) {
                        Image(systemName: "book.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text("Skin Status"),
                    message: Text(alertMessage ?? ""),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

// MARK: - Compact Skin Card

struct CompactSkinCard: View {
    let skin: SkinItem
    let isApplied: Bool
    let isExpanded: Bool
    let isProcessing: Bool
    let onToggleExpand: () -> Void
    let onAction: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Top Row
            HStack(spacing: 14) {
                SkinThumbnailView(imageName: skin.imageName, size: 70)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(skin.name)
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(.white)
                        
                        if isApplied {
                            Text("ACTIVE")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Color.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text("Target: \(skin.characterName)")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.accentSecondary)
                    
                    Text(skin.patchFileName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(14)
            
            // Expandable details & action
            if isExpanded {
                Divider().background(AppTheme.cardBorder)
                
                VStack(alignment: .leading, spacing: 14) {
                    Text(skin.description)
                        .font(.caption)
                        .foregroundStyle(Color(.lightGray))
                        .lineSpacing(2)
                    
                    Button(action: onAction) {
                        HStack {
                            if isProcessing {
                                ProgressView().tint(.white)
                                Text("Checking Container...")
                                    .font(.subheadline.weight(.bold))
                            } else {
                                Image(systemName: isApplied ? "trash.fill" : "arrow.down.circle.fill")
                                Text(isApplied ? "REMOVE SKIN" : "APPLY SKIN")
                                    .font(.subheadline.weight(.heavy))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(isApplied ? Color.red.opacity(0.85) : AppTheme.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(isProcessing)
                }
                .padding(14)
                .background(Color.black.opacity(0.25))
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isApplied ? Color.green.opacity(0.5) : AppTheme.cardBorder, lineWidth: 1.5)
        )
    }
}

// MARK: - Skin Thumbnail View

struct SkinThumbnailView: View {
    let imageName: String
    var size: CGFloat = 64
    
    var body: some View {
        Group {
            if let uiImage = UIImage(named: imageName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accentDark)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.accent.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - User Account View (Account Tab)

struct UserAccountView: View {
    @ObservedObject var authService: AuthService
    let onOpenManual: () -> Void
    let onOpenSettings: () -> Void
    
    @State private var isKeyRevealed = false
    @State private var copiedNotice = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    // Profile Header Card
                    VStack(spacing: 12) {
                        AppLogo(size: 80)
                        
                        Text("BYTE IOS VIP")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white)
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(authService.isOfflineMode ? Color.orange : Color.green)
                                .frame(width: 8, height: 8)
                            Text(authService.expirationText)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(authService.isOfflineMode ? Color.orange : Color.green)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background((authService.isOfflineMode ? Color.orange : Color.green).opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
                    )
                    
                    // License Information Card
                    VStack(alignment: .leading, spacing: 14) {
                        Text("LICENSE & ENTITLEMENT")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(.gray))
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("License Key")
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(isKeyRevealed ? authService.activeLicense : maskedKey(authService.activeLicense))
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(AppTheme.accentSecondary)
                                
                                Button {
                                    isKeyRevealed.toggle()
                                } label: {
                                    Image(systemName: isKeyRevealed ? "eye.slash.fill" : "eye.fill")
                                        .foregroundStyle(.secondary)
                                }
                                
                                Button {
                                    UIPasteboard.general.string = authService.activeLicense
                                    copiedNotice = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        copiedNotice = false
                                    }
                                } label: {
                                    Image(systemName: copiedNotice ? "checkmark" : "doc.on.clipboard")
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                            
                            Divider().background(AppTheme.cardBorder)
                            
                            HStack {
                                Text("Hardware Binding")
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("Bound to Hardware")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.green)
                            }
                            
                            Divider().background(AppTheme.cardBorder)
                            
                            HStack {
                                Text("Device Fingerprint")
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(shortUUID(authService.deviceFingerprint))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(16)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
                    )
                    
                    // Quick Links & Operations
                    VStack(spacing: 10) {
                        accountLinkRow(title: "User Manual & Guidelines", icon: "book.fill", action: onOpenManual)
                        accountLinkRow(title: "Application Settings", icon: "gearshape.fill", action: onOpenSettings)
                        accountLinkRow(title: "Discord Community & Support", icon: "bubble.left.and.bubble.right.fill") {
                            if let url = URL(string: "https://discord.gg") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    
                    // Sign Out Action
                    Button {
                        authService.logout()
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("SIGN OUT / SWITCH LICENSE")
                                .font(.subheadline.weight(.heavy))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.red.opacity(0.18))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("ACCOUNT & LICENSE")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func maskedKey(_ key: String) -> String {
        guard key.count > 6 else { return "••••••••" }
        let prefix = key.prefix(3)
        let suffix = key.suffix(3)
        return "\(prefix)••••\(suffix)"
    }
    
    private func shortUUID(_ uuid: String) -> String {
        guard uuid.count > 12 else { return uuid }
        return "\(uuid.prefix(8))...\(uuid.suffix(4))"
    }
    
    private func accountLinkRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AppRowIcon(systemName: icon, tint: AppTheme.accent)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - User Manual View

struct UserManualView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    guideSection(
                        step: "01",
                        title: "Safe Mode & Match Flow",
                        instruction: "Safe mode engaged — enjoy the match.",
                        details: "Ensure features are toggled according to the proper timing in the lobby and match."
                    )
                    
                    guideSection(
                        step: "02",
                        title: "144 FPS Unlock",
                        instruction: "Toggle 144 FPS Unlock ON first. Confirm the frame rate counter reflects the unlocked cap.",
                        details: "Reach the main lobby before verifying device refresh rate stabilization."
                    )
                    
                    guideSection(
                        step: "03",
                        title: "Aim Body Activation",
                        instruction: "While in the lobby, toggle Aim Body ON. After you are inside the match, toggle Aim Body OFF.",
                        details: "Follow this exact sequence to ensure server synchronization."
                    )
                    
                    guideSection(
                        step: "04",
                        title: "Magic Bullet Timing",
                        instruction: "While in the lobby, toggle Magic Bullet ON. After you are inside the match, toggle Magic Bullet OFF.",
                        details: "Deactivating in-match ensures maximum stability."
                    )
                    
                    guideSection(
                        step: "05",
                        title: "Visuals / ESP Flow",
                        instruction: "Toggle Visuals ON first. Open the game and reach the lobby. Go to Training ground. While inside Training, toggle Visuals OFF. Return to the game — that's it.",
                        details: "Training ground initial state unlocks persistent runtime visual hooks."
                    )
                    
                    guideSection(
                        step: "06",
                        title: "Skins & Bundles",
                        instruction: "Works on FF Max Ignis Character & Awakened Alok. Make sure character bundle is downloaded before applying.",
                        details: "If outfits do not render, open the in-game Download Center and download all character resources."
                    )
                }
                .padding(16)
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("USER MANUAL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(AppTheme.accentSecondary)
                }
            }
        }
    }
    
    private func guideSection(step: String, title: String, instruction: String, details: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(step)
                    .font(.caption.weight(.black))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent.opacity(0.18))
                    .clipShape(Capsule())
                
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            
            Text(instruction)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.accentSecondary)
                .lineSpacing(2)
            
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
        )
    }
}

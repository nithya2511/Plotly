//
//  PlotlyApp.swift
//  Plotly
//
//  Created by Nithya Vasudevan on 08.07.26.
//

import SwiftUI
import SwiftData

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    static func normalized(_ rawValue: String) -> AppAppearanceMode {
        AppAppearanceMode(rawValue: rawValue) ?? .system
    }
}

@main
struct PlotlyApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([UserAccount.self, Plan.self, PlanStop.self])
        let configuration = ModelConfiguration(schema: schema)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create Plotly model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(modelContainer)
    }
}

private struct AppRootView: View {
    @AppStorage("appAppearanceMode") private var appAppearanceModeRawValue = AppAppearanceMode.system.rawValue
    @State private var isShowingSplash = true

    var body: some View {
        Group {
            if isShowingSplash {
                SplashScreen()
            } else {
                ContentView()
            }
        }
        .preferredColorScheme(AppAppearanceMode.normalized(appAppearanceModeRawValue).colorScheme)
        .task {
            do {
                try await Task.sleep(nanoseconds: 1_200_000_000)
            } catch {
                return
            }

            isShowingSplash = false
        }
    }
}

//
//  PlotlyApp.swift
//  Plotly
//
//  Created by Nithya Vasudevan on 08.07.26.
//

import SwiftUI
import SwiftData

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
    @State private var isShowingSplash = true

    var body: some View {
        Group {
            if isShowingSplash {
                SplashScreen()
            } else {
                ContentView()
            }
        }
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

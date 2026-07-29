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
        let schema = Schema([Plan.self, PlanStop.self])
        let configuration = ModelConfiguration(schema: schema)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create Plotly model container: \(error)")
        }
    }()

    init() {
        GoogleSDKBootstrap.configureIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

//
//  HermesApp.swift
//  Hermes
//
//  Created by Mike Felder on 8/6/26.
//

import SwiftUI

@main
struct HermesApp: App {
    @State private var appModel: AppModel

    init() {
        _appModel = State(initialValue: AppModel(environment: .production()))
    }

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel)
                .preferredColorScheme(.dark)
        }
    }
}

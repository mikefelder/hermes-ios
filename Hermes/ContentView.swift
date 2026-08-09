
//  ContentView.swift
//  Hermes
//
//  Created by Mike Felder on 8/6/26.
//

import SwiftUI

struct ContentView: View {
    @State private var appModel = AppModel(environment: .production())

    var body: some View {
        RootView(appModel: appModel)
            .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}

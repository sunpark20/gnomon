//
//  GnomonApp.swift
//  Gnomon
//
//  Ambient-light-based external monitor brightness controller for macOS.
//

import SwiftUI

@main
struct GnomonApp: App {
    @State private var controller = AutoLoopController()

    var body: some Scene {
        WindowGroup {
            MainWindow(controller: controller)
                .task { await controller.start() }
        }
        .windowResizability(.contentSize)
    }
}

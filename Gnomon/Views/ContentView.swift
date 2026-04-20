//
//  ContentView.swift
//  Gnomon
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Gnomon")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Phase 0 — project skeleton")
                .foregroundStyle(.secondary)
        }
        .frame(width: 400, height: 300)
        .padding()
    }
}

#Preview {
    ContentView()
}

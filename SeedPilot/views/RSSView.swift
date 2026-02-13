//
//  RSSView.swift
//  SeedPilot
//
//  Created by gangz1o on 2026/2/13.
//

import SwiftUI

struct RSSView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                    .padding()
                Text("自动化")
                    .font(.title)
            }
            .navigationTitle("自动化")
        }
    }
}

#Preview {
    RSSView()
}

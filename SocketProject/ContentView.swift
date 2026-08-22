//
//  ContentView.swift
//  SocketProject
//
//  Created by Martenier Santos on 18/08/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
        .onAppear {
            TCPServer(port: 8080).start()
        }
    }
}

#Preview {
    ContentView()
}

//
//  ContentView.swift
//  macos-audio-penetrator
//
//  Created by 114514 on 2026/10/31.
//

import SwiftUI

struct ContentView: View {
    @State private var audio = AudioRoutingModel()

    var body: some View {
        VStack {
            Button(action: {
                audio.toggle()
            }) {
                HStack {
                    Text(audio.isRunning ? "停止する" : "起動する")
                }
            }
            
            Text("入出力先設定")
                .font(.title2)
                
            Picker("入力先", selection: $audio.selectedInputDevice) {
                ForEach(audio.inputDevices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            
            Picker("出力先", selection: $audio.selectedOutputDevice) {
                ForEach(audio.outputDevices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            
            Text("\(audio.selectedInputName) → \(audio.selectedOutputName)")
        }
        .padding()
        .onDisappear { audio.stop() }
    }
}

#Preview {
    ContentView()
}

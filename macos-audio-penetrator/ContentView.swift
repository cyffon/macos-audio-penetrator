//
//  ContentView.swift
//  macos-audio-penetrator
//
//  Created by 114514 on 2026/10/31.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedOutputDevice = "Default ({DeviceName})"
    let outputDevices = ["Default ({DeviceName})"]
    
    @State private var selectedInputDevice = "Default ({DeviceName})"
    let inputDevices = ["Default ({DeviceName})"]
    var body: some View {
        VStack {
            Button(action: {
                print("button is tapped")
            }) {
                HStack {
                    Text("起動する")
                }
            }
            
            Text("入出力先設定")
                .font(.title2)
                
            Picker("入力先", selection: $selectedInputDevice) {
                ForEach(inputDevices, id: \.self) {
                    inp in Text(inp).tag(inp)
                }
            }
            
            Picker("出力先", selection: $selectedOutputDevice) {
                ForEach(outputDevices, id: \.self) {
                    dev in Text(dev).tag(dev)
                }
            }
            
            Text("\(selectedInputDevice) → \(selectedOutputDevice)")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

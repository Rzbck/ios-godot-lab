import SwiftUI

@main
struct WatchSensorLabWatchApp: App {
    @StateObject private var model = SensorModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: SensorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("WATCH SENSOR LAB")
                    .font(.headline)

                Text("SHA \(BuildInfo.gitSHA)")
                    .font(.caption2)

                Text(model.sessionStatus)
                    .font(.caption)

                Group {
                    Text("ACCEL")
                        .font(.caption.bold())
                    Text(String(format: "x %.3f", model.accelX))
                    Text(String(format: "y %.3f", model.accelY))
                    Text(String(format: "z %.3f", model.accelZ))

                    Text("GYRO")
                        .font(.caption.bold())
                    Text(String(format: "x %.3f", model.gyroX))
                    Text(String(format: "y %.3f", model.gyroY))
                    Text(String(format: "z %.3f", model.gyroZ))
                }
                .font(.system(.caption, design: .monospaced))

                Button(model.running ? "STOP" : "START") {
                    model.running ? model.stop() : model.start()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
        }
        .onAppear {
            model.activateSession()
        }
    }
}

import SwiftUI

public struct RootAppView: View {
    @StateObject private var healthService = StartupHealthService.shared

    public init() {}

    public var body: some View {
        Group {
            if healthService.isHealthy {
                MainSynthView()
            } else if healthService.isAborted {
                StartupAbortView(healthService: healthService)
            } else {
                StartupProgressView(healthService: healthService)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            healthService.runPreflight()
        }
    }
}

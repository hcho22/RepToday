import SwiftUI

#if COACH_IPHONE_QA
/// Requires the same configured runtime actor as model QA, so concurrent handshakes are denied.
@MainActor
struct CoachRuntimeProofProbeView: View {
    @State private var probe: CoachRuntimeProofProbe
    @State private var confirmed = false
    @State private var task: Task<Void, Never>?

    init(transport: RuntimeAuthenticatedCoachTransport?) {
        _probe = State(initialValue: CoachRuntimeProofProbe(
            enabled: CoachSyntheticQAConfiguration.isEnabled(), verifier: transport))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Server proof admission — preparation only").font(Theme.Typography.headline)
            Text("Requires separate approval for this installed build, device, Apple proof and matched reviewed server revision. Sends only signed {} and, after both gates pass, its exact replay. No workout context or model request. Purchase selection permits StoreKit-verified Production or Apple Sandbox proof; the server must independently verify that same environment. This does not enable TestFlight Premium.")
            Toggle("This exact proof-only operation is separately authorized", isOn: $confirmed)
                .disabled(probe.running)
            Button("Verify server gates once") {
                task = Task { await probe.run(confirmed: confirmed) }
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.buttonHeight)
            .disabled(!probe.available || !confirmed)
            if probe.running { ProgressView("Bounded server proof verification") }
            if let outcome = probe.outcome { Text(outcome.rawValue).accessibilityLabel(outcome.rawValue) }
            if probe.attempted && !probe.running { Text("Attempt reserved. No retry or reset is provided.") }
            Text("Report only fixed outcomes with the independently confirmed build/channel and deployed revision. Leaving clears output. Offline workouts remain available.")
                .font(Theme.Typography.caption)
        }
        .padding(Theme.Spacing.md)
        .onDisappear { task?.cancel(); task = nil; confirmed = false; probe.close() }
    }
}

/// Hidden dedicated-QA surface. The identity input and opaque proofs never enter product content.
@MainActor
struct CoachProofSchemaProbeView: View {
    @State private var probe = CoachProofSchemaProbe(enabled: CoachSyntheticQAConfiguration.isEnabled())
    @State private var prefix = ""
    @State private var confirmed = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Apple proof schema — preparation only")
                .font(Theme.Typography.headline)
            Text("Requires separate approval for this exact signed TestFlight build and device operation. One new Apple key, one attestation, one randomized assertion. No Coach, purchase, model or telemetry request. This does not enable TestFlight Premium.")
            SecureField("Approved App ID prefix", text: $prefix)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
                .disabled(probe.running || probe.attempted)
            Toggle("This exact schema-only operation is separately authorized", isOn: $confirmed)
                .disabled(probe.running)
            Button("Verify Apple schema once") {
                let input = prefix
                prefix = ""
                task = Task { await probe.run(prefix: input, confirmed: confirmed) }
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.buttonHeight)
            .disabled(!probe.available || !confirmed || !CoachProofSchemaVerifier.validPrefix(prefix))
            if probe.running { ProgressView("Bounded Apple schema verification") }
            if let result = probe.result { Text(result.text).accessibilityLabel(result.text) }
            if probe.attempted && !probe.running { Text("Attempt reserved. No retry or reset is provided.") }
            Text("Report only the fixed result and schema names/types/flags. Do not screenshot the identity input, copy proofs or use application logs. A verified binding is a format observation; distribution remains unresolved.")
                .font(Theme.Typography.caption)
        }
        .font(Theme.Typography.body)
        .padding(Theme.Spacing.md)
        .onDisappear { task?.cancel(); task = nil; prefix = ""; confirmed = false; probe.close() }
    }
}
#endif

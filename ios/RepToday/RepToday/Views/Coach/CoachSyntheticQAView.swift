import SwiftUI

/// Local-only inspection of the two approved synthetic turns. No conversational free-text input, clipboard,
/// share, transcript persistence, history/policy writes, or launch-time requests.
@MainActor
struct CoachSyntheticQAView: View {
    @Environment(\.dismiss) private var dismiss
    private let appState: AppState
    private let configurationEnabled: Bool
    private let runtimeTransport: RuntimeAuthenticatedCoachTransport?
    @State private var viewModel: CoachSyntheticQAViewModel
    @State private var showDisclosure = false
    @State private var sendTask: Task<Void, Never>?
    #if COACH_IPHONE_QA
    @State private var showProofSchema = false
    @State private var showRuntimeProof = false
    #endif

    init(services: ServiceContainer, appState: AppState) {
        self.appState = appState
        configurationEnabled = CoachSyntheticQAConfiguration.isEnabled()
        runtimeTransport = services.coachClient?.transport as? RuntimeAuthenticatedCoachTransport
        _viewModel = State(initialValue: CoachSyntheticQAViewModel(
            client: configurationEnabled ? services.coachClient : nil,
            subscription: services.subscriptionService,
            consent: { appState.hasAcknowledgedCoachDataSharing },
            budget: CoachSyntheticQABudget()
        ))
    }

    /// Hosted offline evidence uses an explicit client double and isolated defaults.
    init(viewModel: CoachSyntheticQAViewModel, appState: AppState, configurationEnabled: Bool) {
        self.appState = appState
        self.configurationEnabled = configurationEnabled
        runtimeTransport = nil
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Synthetic QA — not your workout data")
                        .font(Theme.Typography.title)
                        #if COACH_IPHONE_QA
                        .onLongPressGesture(minimumDuration: 3) {
                            guard !viewModel.isSending else { return }
                            showProofSchema.toggle()
                        }
                        .accessibilityAction(named: "Open schema verification preparation") {
                            guard !viewModel.isSending else { return }
                            showProofSchema = true
                        }
                        #endif
                    #if COACH_IPHONE_QA
                    if showProofSchema {
                        Toggle("Server admission preparation", isOn: $showRuntimeProof)
                        if showRuntimeProof {
                            CoachRuntimeProofProbeView(transport: runtimeTransport)
                        } else {
                            CoachProofSchemaProbeView()
                        }
                        Text("Close and reopen this screen to return to synthetic model QA.")
                    }
                    #endif
                    Group {
                    Text("Preparation build. Requires an eligible signed physical iPhone, an existing Production or Apple Sandbox Premium purchase or trial, and a matched reviewed server revision. The currently deployed revision accepts Production only; Sandbox-capable source is undeployed and TestFlight admission remains unverified.")
                    Text("At most two model requests total: why squats, then pistol form. Each needs a tap. Stop on the first failure; never retry a timeout. This installation remembers attempts across relaunches. Reinstalling does not authorize a new budget.")
                    if !configurationEnabled || !viewModel.isAvailable {
                        Text("QA configuration unavailable. No request can be sent.")
                    }
                    Text(viewModel.isPremium ? "Locally verified Premium: eligible. Fresh Apple proof in the matched Production or Sandbox environment is still required for each request." : "Locally verified Premium: not eligible. Restore an existing eligible purchase through the app; this screen cannot grant Premium or buy it.")
                    if !viewModel.hasConsent {
                        Button("Read Coach data disclosure") { showDisclosure = true }
                            .frame(minHeight: Theme.Spacing.buttonHeight)
                    }
                    Toggle("Service and signed-device readiness confirmed for the approved two-request run", isOn: $viewModel.readinessConfirmed)
                        .disabled(viewModel.isSending)
                    Text("Budget: \(viewModel.budget.summary)")
                        .font(Theme.Typography.caption)
                    Text(viewModel.status)
                    if let selection = viewModel.budget.next {
                        fixture(selection)
                        Button("Send synthetic \(selection.title) once") {
                            sendTask = Task { await viewModel.sendNext() }
                        }
                        .font(Theme.Typography.button)
                        .frame(maxWidth: .infinity, minHeight: Theme.Spacing.buttonHeight)
                        .buttonStyle(.borderedProminent)
                        .disabled(!configurationEnabled || !viewModel.canSend)
                    }
                    if viewModel.isSending { ProgressView("Awaiting bounded Coach request") }
                    if let reply = viewModel.reply, let selection = viewModel.returnedSelection {
                        Text("Synthetic QA reply: \(selection.title) — local review only")
                            .font(Theme.Typography.headline)
                        Text(reply)
                            .accessibilityLabel("Synthetic QA reply. \(reply)")
                        fixture(selection)
                        Text("Non-empty text does not prove correctness. Check the supplied phase, frontier, recent patterns and consistency; distinguish summary reasoning from today's unknown exact session. For pistol form, check safe guidance relative to the assisted frontier. Reject any fabricated or altered workout or policy. Do not copy, log, screenshot or export the prompt, context, reply or Apple proofs.")
                        Button("Local semantic review passes — clear reply") {
                            viewModel.reviewReturnedReply(passed: true)
                        }
                        .frame(minHeight: Theme.Spacing.buttonHeight)
                        Button("Review fails or is uncertain — stop QA") {
                            viewModel.reviewReturnedReply(passed: false)
                        }
                        .frame(minHeight: Theme.Spacing.buttonHeight)
                    }
                    Text("Replies exist only on this screen in memory and clear on review or leaving. Leaving before review stops the run. Your deterministic offline workout remains available.")
                        .font(Theme.Typography.caption)
                    }
                    #if COACH_IPHONE_QA
                    .disabled(showProofSchema)
                    .opacity(showProofSchema ? 0.4 : 1)
                    #endif
                }
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tint(Theme.Colors.accent)
                .padding(Theme.Spacing.md)
            }
            if showDisclosure {
                CoachDataDisclosureView(onAcknowledge: {
                    appState.markCoachDataSharingAcknowledged()
                    showDisclosure = false
                }, onDecline: { dismiss() })
            }
        }
        .navigationTitle("Coach Synthetic QA")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadEligibility() }
        .onDisappear {
            sendTask?.cancel()
            sendTask = nil
            viewModel.close()
        }
    }

    private func fixture(_ selection: CoachSyntheticFixtures.Selection) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Approved synthetic fixture: \(selection.title)")
                .font(Theme.Typography.headline)
            Text(selection.prompt)
            // Render the actual fixture, including every field; never construct a second summary.
            Text(contextText(selection.context))
                .font(Theme.Typography.caption)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
    }

    private func contextText(_ context: CoachContextBundle) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(context), let text = String(data: data, encoding: .utf8) else {
            return "Fixture unavailable"
        }
        return text
    }
}

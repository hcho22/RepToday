import SwiftUI

/// The premium AI coach chat surface (US-AC02, the *talking* coach). A free-text conversation where
/// the user asks questions - "why this workout?", "how do I do a pistol squat?", "is this safe with a
/// sore wrist?", "I'm bored" - and the coach answers, grounded in their real on-device history through
/// the audited `CoachContextBundle` and the stateless `CoachProxyClient` transport.
///
/// It only ever *talks*: it never generates or changes a workout (the deterministic engine owns every
/// session; the persona enforces this in the proxy). On any transport failure it degrades to a clear,
/// non-blocking, retryable banner, and when no coach proxy is configured for the build it shows a
/// calm "unavailable" state - the free core loop is never affected and never waits on it.
///
/// **Not premium-gated here.** This is a minimal, reachable, ungated entry so the surface is navigable
/// and testable now. US-AC03 owns the entitlement gate and the upsell entry point and will wrap this
/// surface (or its entry row) rather than replacing it.
struct CoachView: View {
    @Environment(\.services) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel: CoachViewModel

    /// Production entry: builds the view model from the container's services (and its build-configured
    /// coach client) off the environment.
    init(services: ServiceContainer) {
        _viewModel = State(initialValue: CoachViewModel(services: services))
    }

    /// Test/preview entry: injects a pre-built view model (e.g. one backed by a stub transport with a
    /// seeded transcript), so the surface can be hosted and read without a live proxy.
    init(viewModel: CoachViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            if viewModel.isAvailable {
                conversation
            } else {
                unavailableState
            }
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Available: the conversation

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        if viewModel.messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        if viewModel.isSending {
                            typingIndicator
                                .id(Self.typingIndicatorID)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: viewModel.isSending) { _, _ in
                    scrollToBottom(proxy)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                errorBanner(errorMessage)
            }

            inputBar
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Ask your coach")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("It can explain why today's session looks the way it does, teach you a movement, or "
                 + "talk through staying consistent. It never changes your workout - the app builds that.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(CoachViewModel.suggestedPrompts, id: \.self) { prompt in
                    Button {
                        viewModel.draft = prompt
                        Task { await viewModel.send() }
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Theme.Colors.accent)
                            Text(prompt)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, minHeight: Theme.Spacing.minTouchTarget, alignment: .leading)
                        .background(
                            Theme.Colors.surface,
                            in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
                        )
                    }
                    .accessibilityLabel(prompt)
                    .accessibilityHint("Asks the coach this question")
                }
            }
            .padding(.top, Theme.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typingIndicator: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView()
            Text("Coach is thinking...")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach is thinking")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.danger)
            Text(message)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if viewModel.canRetry {
                Button("Try again") {
                    Task { await viewModel.retryLastMessage() }
                }
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(minHeight: Theme.Spacing.minTouchTarget)
                .accessibilityHint("Sends your last question to the coach again")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .accessibilityElement(children: .combine)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
            TextField("Ask the coach...", text: $viewModel.draft, axis: .vertical)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1...5)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .frame(minHeight: Theme.Spacing.minTouchTarget)
                .background(
                    Theme.Colors.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
                )
                .disabled(viewModel.isSending)
                .accessibilityLabel("Message to the coach")

            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(viewModel.canSend ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    .frame(width: Theme.Spacing.minTouchTarget, height: Theme.Spacing.minTouchTarget)
            }
            .disabled(!viewModel.canSend)
            .accessibilityLabel("Send")
            .accessibilityHint("Sends your question to the coach")
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.background)
    }

    // MARK: - Unavailable

    private var unavailableState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(minWidth: Theme.Spacing.minTouchTarget, minHeight: Theme.Spacing.minTouchTarget)

            Text("Coach isn't available right now")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("Your workouts are unaffected - the app still builds every session on its own. "
                 + "Check back soon.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach isn't available right now. Your workouts are unaffected.")
    }

    // MARK: - Helpers

    /// A stable id for the typing indicator so the scroll-to-bottom target exists while a reply is in
    /// flight (before the coach's message has been appended).
    private static let typingIndicatorID = "coach.typingIndicator"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let target: AnyHashable = viewModel.isSending
            ? AnyHashable(Self.typingIndicatorID)
            : (viewModel.messages.last?.id).map(AnyHashable.init) ?? AnyHashable(Self.typingIndicatorID)
        if reduceMotion {
            proxy.scrollTo(target, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }
}

/// One turn in the transcript. The user's questions align trailing on the accent colour; the coach's
/// answers align leading on the surface colour, so the two voices read apart at a glance and to
/// VoiceOver (each bubble names who is speaking).
private struct MessageBubble: View {
    let message: CoachViewModel.Message

    private var isUser: Bool { message.author == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: Theme.Spacing.xl) }

            Text(message.text)
                .font(Theme.Typography.body)
                .foregroundStyle(isUser ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    isUser ? Theme.Colors.accent : Theme.Colors.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
                )
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: Theme.Spacing.xl) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUser ? "You said: \(message.text)" : "Coach said: \(message.text)")
    }
}

#if DEBUG
/// A canned transport for previews - returns one fixed reply, makes no network call - so the chat
/// surface renders and a tapped suggested prompt answers without a live proxy.
private struct PreviewCoachTransport: CoachProxyTransport {
    func post(
        to url: URL,
        jsonBody: Data,
        headers: [String: String],
        timeoutSeconds: Double
    ) async throws -> (data: Data, statusCode: Int) {
        let reply = "Squats came up because they were your stalest movement this week - the engine "
            + "leads with whatever you've trained least. You're building a real base here."
        return (Data(#"{"reply":"\#(reply)"}"#.utf8), 200)
    }
}

extension CoachViewModel {
    /// An available coach backed by the canned preview transport and the mock services.
    static func preview() -> CoachViewModel {
        CoachViewModel(
            client: CoachProxyClient(
                endpoint: URL(string: "https://preview.example.com/coach")!,
                transport: PreviewCoachTransport()
            ),
            userService: MockUserService(),
            workoutLogService: MockWorkoutLogService(),
            exerciseService: try! MockExerciseService()
        )
    }

    /// An unconfigured coach (no client), which renders the "unavailable" state.
    static func previewUnavailable() -> CoachViewModel {
        CoachViewModel(
            client: nil,
            userService: MockUserService(),
            workoutLogService: MockWorkoutLogService(),
            exerciseService: try! MockExerciseService()
        )
    }
}

#Preview("Conversation") {
    NavigationStack {
        CoachView(viewModel: CoachViewModel.preview())
    }
    .environment(\.services, ServiceContainer.mock())
}

#Preview("Unavailable") {
    NavigationStack {
        CoachView(viewModel: CoachViewModel.previewUnavailable())
    }
    .environment(\.services, ServiceContainer.mock())
}
#endif

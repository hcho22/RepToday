import SwiftUI

struct WeeklyReportView: View {
    @Environment(\.services) private var services
    @State private var viewModel = WeeklyReportViewModel()

    var body: some View {
        Group {
            if !viewModel.isPremium {
                premiumGate
            } else if viewModel.isLoading {
                ProgressView("Loading reports...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.reports.isEmpty {
                ContentUnavailableView(
                    "No Reports Yet",
                    systemImage: "doc.text",
                    description: Text("Complete workouts to generate weekly reports.")
                )
            } else {
                reportList
            }
        }
        .background(AppColors.background)
        .navigationTitle("Weekly Report")
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.loadReports(services: services) }
    }

    // MARK: - Report List

    private var reportList: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.md) {
                ForEach(viewModel.reports) { report in
                    reportCard(report)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
        }
    }

    // MARK: - Report Card

    private func reportCard(_ report: WeeklyReportViewModel.WeekReport) -> some View {
        FitSnackCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Header: date range
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(AppColors.brand)
                    Text(report.dateRangeFormatted)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                }

                // Stats row
                HStack(spacing: AppSpacing.lg) {
                    statPill(value: "\(report.workoutCount)", label: "workouts")
                    statPill(value: "\(report.totalMinutes)", label: "min")
                }

                // Narrative or states
                if report.isEmpty {
                    Text("No workouts this week.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .italic()
                } else if report.isGenerating {
                    HStack(spacing: AppSpacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating insight...")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                } else {
                    Text(report.narrative)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func statPill(value: String, label: String) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Text(value)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.brand)
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Premium Gate

    private var premiumGate: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.warning)
            Text("Premium Feature")
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)
            Text("Weekly AI reports are available for premium members. Upgrade to get personalized training insights every week.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)
            NavigationLink(destination: SubscriptionView()) {
                Text("View Plans")
                    .font(AppTypography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppSpacing.buttonHeight)
                    .background(AppColors.brand)
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            }
            .padding(.horizontal, AppSpacing.lg)
            Spacer()
        }
    }
}

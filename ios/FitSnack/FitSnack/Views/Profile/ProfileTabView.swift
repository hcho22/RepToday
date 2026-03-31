import SwiftUI

struct ProfileTabView: View {
    @Environment(\.services) private var services
    @State private var viewModel = ProfileViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    // Profile header: name, fitness level, member since
                    FitSnackCard {
                        VStack(spacing: AppSpacing.md) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(AppColors.brand)

                            Text(viewModel.profile?.displayName.isEmpty == false ? viewModel.profile!.displayName : "FitSnacker")
                                .font(AppTypography.title)
                                .foregroundStyle(AppColors.textPrimary)

                            Text(viewModel.profile?.fitnessLevel.displayName ?? "Beginner")
                                .font(AppTypography.subheadline)
                                .foregroundStyle(AppColors.textSecondary)

                            Text("Member since \((viewModel.profile?.createdAt ?? Date()).formatted(.dateTime.month(.wide).year()))")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)

                    // Stats summary: total workouts, total XP, current level
                    FitSnackCard {
                        HStack(spacing: AppSpacing.sm) {
                            statItem(value: "\(viewModel.stats.totalWorkoutsCompleted)", label: "Workouts")
                            statItem(value: "\(viewModel.stats.xp)", label: "Total XP")
                            statItem(value: "Lv.\(viewModel.stats.level)", label: "Level")
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)

                    // Quick links
                    VStack(spacing: AppSpacing.sm) {
                        if let profile = viewModel.profile {
                            quickLink(icon: "person.fill", title: "Edit Profile") {
                                ProfileEditView(
                                    profile: Binding(
                                        get: { self.viewModel.profile ?? profile },
                                        set: { self.viewModel.profile = $0 }
                                    ),
                                    onSave: { Task { await viewModel.updateProfile(viewModel.profile ?? profile, services: services) } }
                                )
                            }
                            quickLink(icon: "dumbbell.fill", title: "Equipment") {
                                SettingsView(
                                    profile: Binding(
                                        get: { self.viewModel.profile ?? profile },
                                        set: { self.viewModel.profile = $0 }
                                    ),
                                    onSave: { Task { await viewModel.updateProfile(viewModel.profile ?? profile, services: services) } }
                                )
                            }
                            quickLink(icon: "gearshape.fill", title: "Settings") {
                                SettingsView(
                                    profile: Binding(
                                        get: { self.viewModel.profile ?? profile },
                                        set: { self.viewModel.profile = $0 }
                                    ),
                                    onSave: { Task { await viewModel.updateProfile(viewModel.profile ?? profile, services: services) } }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                }
                .padding(.top, AppSpacing.md)
            }
            .background(AppColors.background)
            .navigationTitle("Profile")
        }
        .task { await viewModel.loadData(services: services) }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text(value)
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.brand)
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func quickLink<Destination: View>(icon: String, title: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            FitSnackCard {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(AppColors.brand)
                    Text(title)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }
}

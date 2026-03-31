import SwiftUI

struct EquipmentEditView: View {
    @Binding var equipment: [Equipment]
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var equipmentSet: Set<Equipment> {
        Set(equipment)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Text("What equipment do you have?")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Select all that apply")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)

                FlowLayout(spacing: AppSpacing.sm) {
                    ForEach(Equipment.allCases) { item in
                        SelectableChip(
                            title: item.displayName,
                            isSelected: equipmentSet.contains(item)
                        ) {
                            toggleItem(item)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
            }
            .padding(.top, AppSpacing.lg)
        }
        .background(AppColors.background)
        .navigationTitle("Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave()
                    dismiss()
                }
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.brand)
            }
        }
    }

    private func toggleItem(_ item: Equipment) {
        if item == .none {
            equipment = [.none]
        } else {
            equipment.removeAll { $0 == .none }
            if equipment.contains(item) {
                equipment.removeAll { $0 == item }
            } else {
                equipment.append(item)
            }
            if equipment.isEmpty {
                equipment = [.none]
            }
        }
    }
}

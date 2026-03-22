import SwiftUI

struct PinSheet: View {
    @Binding var isPresented: Bool
    let pinLabels: [(label: String, icon: String, color: Color)]
    let accentColor: Color
    let onDrop: (String) -> Void

    @State private var customLabel = ""

    var body: some View {
        VStack(spacing: 20) {
            // Handle bar
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 4)

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "mappin")
                        .foregroundColor(accentColor)
                        .font(.system(size: 16, weight: .semibold))
                    Text("Drop Pin")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                Button(action: { withAnimation(.easeOut(duration: 0.2)) { isPresented = false } }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }

            // Quick labels
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(Array(pinLabels.enumerated()), id: \.offset) { _, item in
                    Button(action: {
                        onDrop(item.label)
                        withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: 16))
                                .foregroundColor(item.color)
                            Text(item.label)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                }
            }

            // Custom label
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "tag")
                        .foregroundColor(.white.opacity(0.3))
                        .font(.system(size: 13))
                    TextField("Custom label...", text: $customLabel)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                Button(action: {
                    if !customLabel.isEmpty {
                        onDrop(customLabel)
                        withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
                    }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(customLabel.isEmpty ? .white.opacity(0.15) : accentColor)
                }
                .disabled(customLabel.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 8)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
    }
}

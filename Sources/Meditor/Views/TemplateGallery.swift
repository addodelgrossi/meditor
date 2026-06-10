import SwiftUI

struct TemplateGallery: View {
    let onSelect: (MermaidTemplate) -> Void
    let onStartBlank: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                MeditorMark()
                    .frame(width: 78, height: 78)

                VStack(spacing: 6) {
                    Text("Start with an idea")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("Choose a template or begin typing Mermaid.")
                        .foregroundStyle(.secondary)
                }

                Button("Start blank", action: onStartBlank)
                    .buttonStyle(.glassProminent)
                    .tint(Brand.indigo)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(MermaidTemplate.all) { template in
                        Button {
                            onSelect(template)
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: template.systemImage)
                                    .font(.title2)
                                    .foregroundStyle(Brand.gradient)
                                Spacer()
                                Text(template.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(template.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.separator.opacity(0.35))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 720)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .background(.ultraThinMaterial)
    }
}

struct MeditorMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Brand.gradient, lineWidth: 1.5)

            Canvas { context, size in
                let leftTop = CGPoint(x: size.width * 0.24, y: size.height * 0.30)
                let leftBottom = CGPoint(x: size.width * 0.24, y: size.height * 0.72)
                let center = CGPoint(x: size.width * 0.50, y: size.height * 0.54)
                let rightTop = CGPoint(x: size.width * 0.76, y: size.height * 0.30)
                let rightBottom = CGPoint(x: size.width * 0.76, y: size.height * 0.72)

                var path = Path()
                path.move(to: leftBottom)
                path.addLine(to: leftTop)
                path.addLine(to: center)
                path.addLine(to: rightTop)
                path.addLine(to: rightBottom)
                context.stroke(path, with: .linearGradient(
                    Gradient(colors: [Brand.aqua, Brand.indigo]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                ), lineWidth: 5)

                for point in [leftTop, leftBottom, center, rightTop, rightBottom] {
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
                        with: .color(.white)
                    )
                }
            }
            .padding(9)
        }
        .shadow(color: Brand.indigo.opacity(0.18), radius: 18, y: 8)
        .accessibilityHidden(true)
    }
}

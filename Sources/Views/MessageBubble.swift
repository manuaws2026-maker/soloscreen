import SwiftUI

struct MessageBubble: View {
    let message: Message
    @State private var isHovering = false
    @State private var showCopied = false

    private let accentTeal = Color(hex: "00BCD4")
    private let surfaceColor = Color(hex: "161B22")
    private let borderColor = Color(hex: "30363D")

    private var isUser: Bool { message.role == .user }
    private var isAssistant: Bool { message.role == .assistant }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Attachments
                if !message.attachments.isEmpty {
                    attachmentsView
                }

                // Message content
                contentBubble

                // Timestamp (shown on hover)
                if isHovering {
                    Text(formatTimestamp(message.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }

            if isAssistant { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    // MARK: - Content Bubble

    private var contentBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isAssistant {
                assistantAvatar
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 0) {
                if isAssistant {
                    markdownContent
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            BubbleShape(isUser: false)
                                .fill(surfaceColor)
                                .overlay(
                                    BubbleShape(isUser: false)
                                        .stroke(borderColor, lineWidth: 1)
                                )
                        )
                } else {
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.95))
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            BubbleShape(isUser: true)
                                .fill(accentTeal.opacity(0.2))
                                .overlay(
                                    BubbleShape(isUser: true)
                                        .stroke(accentTeal.opacity(0.35), lineWidth: 1)
                                )
                        )
                }
            }

            // Copy button for assistant messages
            if isAssistant && isHovering {
                copyButton
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }

    // MARK: - Assistant Avatar

    private var assistantAvatar: some View {
        ZStack {
            Circle()
                .fill(accentTeal.opacity(0.15))
                .frame(width: 28, height: 28)

            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accentTeal)
        }
    }

    // MARK: - Markdown Content

    private var markdownContent: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: message.content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .tint(accentTeal)
            } else {
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Attachments

    private var attachmentsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(message.attachments) { attachment in
                    attachmentThumbnail(attachment)
                }
            }
        }
        .padding(.horizontal, isUser ? 0 : 36)
    }

    private func attachmentThumbnail(_ attachment: Message.Attachment) -> some View {
        Group {
            if attachment.type == .screenshot, let nsImage = NSImage(data: attachment.data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "doc")
                        .font(.system(size: 12))
                        .foregroundStyle(accentTeal.opacity(0.7))

                    Text(attachment.fileName ?? "File")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(surfaceColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(borderColor, lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Copy Button

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.content, forType: .string)
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopied = false
            }
        } label: {
            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(showCopied ? .green : .white.opacity(0.4))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(surfaceColor)
                        .overlay(Circle().strokeBorder(borderColor, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .help("Copy message")
    }

    // MARK: - Helpers

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Bubble Shape

private struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 14
        let smallRadius: CGFloat = 4
        return Path { path in
            if isUser {
                // User: rounded corners, smaller bottom-right
                path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
                path.addArc(
                    center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                    radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
                )
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - smallRadius))
                path.addArc(
                    center: CGPoint(x: rect.maxX - smallRadius, y: rect.maxY - smallRadius),
                    radius: smallRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
                )
                path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
                path.addArc(
                    center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                    radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
                )
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
                path.addArc(
                    center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                    radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
                )
            } else {
                // Assistant: rounded corners, smaller bottom-left
                path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
                path.addArc(
                    center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                    radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
                )
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
                path.addArc(
                    center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                    radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
                )
                path.addLine(to: CGPoint(x: rect.minX + smallRadius, y: rect.maxY))
                path.addArc(
                    center: CGPoint(x: rect.minX + smallRadius, y: rect.maxY - smallRadius),
                    radius: smallRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
                )
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
                path.addArc(
                    center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                    radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
                )
            }
            path.closeSubpath()
        }
    }
}

#Preview {
    VStack {
        MessageBubble(message: Message(
            id: UUID(),
            role: .user,
            content: "Hello, can you help me with something?",
            attachments: [],
            timestamp: Date()
        ))
        MessageBubble(message: Message(
            id: UUID(),
            role: .assistant,
            content: "Of course! I'd be happy to help. What do you need assistance with?",
            attachments: [],
            timestamp: Date()
        ))
    }
    .padding()
    .background(Color(hex: "0D1117"))
}

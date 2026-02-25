import SwiftUI
import AppKit

struct RichTextToolbar: View {
    var coordinator: RichTextEditor.Coordinator?

    @State private var selectedHeading: HeadingStyle = .body
    @State private var showHighlightPicker = false
    @State private var showFontColorPicker = false
    @State private var showTablePopover = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Text formatting group
                toolbarGroup {
                    HStack(spacing: 1) {
                        toolbarButton(icon: "bold", tooltip: "Bold (Cmd+B)") {
                            coordinator?.toggleBold()
                        }
                        toolbarButton(icon: "italic", tooltip: "Italic (Cmd+I)") {
                            coordinator?.toggleItalic()
                        }
                        toolbarButton(icon: "underline", tooltip: "Underline (Cmd+U)") {
                            coordinator?.toggleUnderline()
                        }
                        toolbarButton(icon: "strikethrough", tooltip: "Strikethrough (Cmd+Shift+X)") {
                            coordinator?.toggleStrikethrough()
                        }
                    }
                }

                // Heading picker
                Picker("", selection: $selectedHeading) {
                    ForEach(HeadingStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .frame(width: 100)
                .controlSize(.small)
                .onChange(of: selectedHeading) { _, newValue in
                    coordinator?.applyHeading(newValue)
                }

                // Colors
                toolbarGroup {
                    HStack(spacing: 2) {
                        // Highlight color
                        Button {
                            showHighlightPicker.toggle()
                            showFontColorPicker = false
                        } label: {
                            VStack(spacing: 1) {
                                Image(systemName: "highlighter")
                                    .font(.system(size: 11, weight: .medium))
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.yellow)
                                    .frame(width: 14, height: 3)
                            }
                            .frame(width: 28, height: 26)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(ToolbarItemButtonStyle())
                        .help("Highlight color")
                        .popover(isPresented: $showHighlightPicker) {
                            ColorSwatchGrid(
                                title: "Highlight",
                                colors: PresetColors.highlights,
                                showNone: true,
                                onSelect: { color in
                                    coordinator?.applyHighlight(color.map { NSColor($0) })
                                    showHighlightPicker = false
                                }
                            )
                        }

                        // Text color
                        Button {
                            showFontColorPicker.toggle()
                            showHighlightPicker = false
                        } label: {
                            VStack(spacing: 1) {
                                Image(systemName: "textformat")
                                    .font(.system(size: 11, weight: .bold))
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.red)
                                    .frame(width: 14, height: 3)
                            }
                            .frame(width: 28, height: 26)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(ToolbarItemButtonStyle())
                        .help("Text color")
                        .popover(isPresented: $showFontColorPicker) {
                            ColorSwatchGrid(
                                title: "Text Color",
                                colors: PresetColors.textColors,
                                showNone: false,
                                onSelect: { color in
                                    if let c = color {
                                        coordinator?.applyFontColor(NSColor(c))
                                    }
                                    showFontColorPicker = false
                                }
                            )
                        }
                    }
                }

                // Lists
                toolbarGroup {
                    HStack(spacing: 1) {
                        toolbarButton(icon: "list.bullet", tooltip: "Bullet list") {
                            coordinator?.insertBulletList()
                        }
                        toolbarButton(icon: "list.number", tooltip: "Numbered list") {
                            coordinator?.insertNumberedList()
                        }
                        toolbarButton(icon: "checklist", tooltip: "Checklist (Cmd+Shift+L)") {
                            coordinator?.toggleChecklist()
                        }
                    }
                }

                // Table + Divider
                toolbarGroup {
                    HStack(spacing: 1) {
                        Button {
                            showTablePopover = true
                        } label: {
                            Image(systemName: "tablecells")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 28, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ToolbarItemButtonStyle())
                        .help("Insert table")
                        .popover(isPresented: $showTablePopover) {
                            TableInsertSheet { rows, cols in
                                coordinator?.insertTable(rows: rows, columns: cols)
                            }
                        }

                        toolbarButton(icon: "minus", tooltip: "Insert divider (or type ---)") {
                            coordinator?.insertDivider()
                        }
                    }
                }

                // Media
                toolbarGroup {
                    HStack(spacing: 1) {
                        toolbarButton(icon: "photo", tooltip: "Insert image") {
                            coordinator?.insertImage()
                        }
                        toolbarButton(icon: "link", tooltip: "Insert link (Cmd+K)") {
                            coordinator?.insertLink()
                        }
                        toolbarButton(icon: "pencil.and.scribble", tooltip: "Insert sketch") {
                            coordinator?.insertInlineSketch()
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
    }

    // MARK: - Toolbar Group Container

    private func toolbarGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
    }

    // MARK: - Toolbar Button

    private func toolbarButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarItemButtonStyle())
        .help(tooltip)
    }
}

// MARK: - Hover Button Style

struct ToolbarItemButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? .primary : (isHovered ? .primary : .secondary))
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.2) : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Preset Colors

enum PresetColors {
    static let highlights: [(String, Color)] = [
        ("Yellow", Color(.sRGB, red: 0.95, green: 0.90, blue: 0.45, opacity: 0.35)),
        ("Orange", Color(.sRGB, red: 0.95, green: 0.70, blue: 0.40, opacity: 0.35)),
        ("Pink",   Color(.sRGB, red: 0.95, green: 0.55, blue: 0.65, opacity: 0.35)),
        ("Purple", Color(.sRGB, red: 0.75, green: 0.55, blue: 0.90, opacity: 0.35)),
        ("Blue",   Color(.sRGB, red: 0.50, green: 0.70, blue: 0.95, opacity: 0.35)),
        ("Green",  Color(.sRGB, red: 0.50, green: 0.85, blue: 0.55, opacity: 0.35)),
        ("Mint",   Color(.sRGB, red: 0.50, green: 0.90, blue: 0.80, opacity: 0.35)),
        ("Gray",   Color(.sRGB, red: 0.70, green: 0.70, blue: 0.70, opacity: 0.25)),
    ]

    static let textColors: [(String, Color)] = [
        ("Default", Color.primary),
        ("Red", Color.red),
        ("Orange", Color.orange),
        ("Yellow", Color(nsColor: .systemYellow)),
        ("Green", Color.green),
        ("Blue", Color.blue),
        ("Purple", Color.purple),
        ("Pink", Color.pink),
        ("Gray", Color.gray),
    ]
}

// MARK: - Color Swatch Grid

struct ColorSwatchGrid: View {
    let title: String
    let colors: [(String, Color)]
    let showNone: Bool
    let onSelect: (Color?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 4), spacing: 6) {
                if showNone {
                    Button {
                        onSelect(nil)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                            // Diagonal line for "none"
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help("None")
                }

                ForEach(colors, id: \.0) { name, color in
                    Button {
                        onSelect(color)
                    } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: 26, height: 26)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(name)
                }
            }
        }
        .padding(12)
        .frame(width: 150)
    }
}

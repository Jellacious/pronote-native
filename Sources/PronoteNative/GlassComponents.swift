import AppKit
import SwiftUI

/// Fond ambiant discret inspiré de Papillon pour faire ressortir les cartes en verre.
struct AmbientBackground: View {
    @AppStorage("glassBackgroundEnabled") private var glassEnabled: Bool = true

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if glassEnabled {
                RadialGradient(
                    colors: [Color.accentColor.opacity(0.12), Color.clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 680
                )
                RadialGradient(
                    colors: [Color.indigo.opacity(0.08), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 620
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// Carte Liquid Glass avec matériau translucide, bordure spéculaire et ombre douce.
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 16, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.75),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

/// Badge d'icône coloré style Papillon / Réglages macOS pour la barre latérale.
struct SectionIconBadge: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(
                LinearGradient(
                    colors: [color, color.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}

/// Détecteur de swipe horizontal interactif à deux doigts sur le trackpad macOS.
struct InteractiveTrackpadSwipeModifier: ViewModifier {
    @Binding var dragOffset: CGFloat
    @Binding var swipeOpacity: Double
    let threshold: CGFloat
    let onCommitLeft: () -> Void
    let onCommitRight: () -> Void

    @State private var monitor: Any?
    @State private var rawAccumulatedX: CGFloat = 0
    @State private var crossedThreshold: Bool = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    handleScroll(event)
                    return event
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
    }

    private func handleScroll(_ event: NSEvent) {
        // Ignorer l'inertie pour qu'un seul geste ne déclenche qu'une semaine
        guard event.momentumPhase == [], event.locationInWindow.x > 240 else { return }

        if event.phase == .began {
            rawAccumulatedX = 0
            crossedThreshold = false
            return
        }

        if event.phase == .ended || event.phase == .cancelled {
            let finalOffset = dragOffset
            if finalOffset <= -threshold {
                Haptics.play(.generic)
                withAnimation(.easeOut(duration: 0.13)) {
                    dragOffset = -130
                    swipeOpacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                    onCommitLeft()
                    dragOffset = 38
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        dragOffset = 0
                        swipeOpacity = 1
                    }
                }
            } else if finalOffset >= threshold {
                Haptics.play(.generic)
                withAnimation(.easeOut(duration: 0.13)) {
                    dragOffset = 130
                    swipeOpacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                    onCommitRight()
                    dragOffset = -38
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        dragOffset = 0
                        swipeOpacity = 1
                    }
                }
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    dragOffset = 0
                    swipeOpacity = 1
                }
            }
            rawAccumulatedX = 0
            crossedThreshold = false
            return
        }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard abs(dx) > abs(dy) * 1.25 else { return }

        rawAccumulatedX += dx
        let damped: CGFloat
        if abs(rawAccumulatedX) > threshold {
            let extra = abs(rawAccumulatedX) - threshold
            damped = (rawAccumulatedX >= 0 ? 1 : -1) * (threshold + extra * 0.35)
        } else {
            damped = rawAccumulatedX
        }
        dragOffset = max(-160, min(160, damped))

        let isNowCrossed = abs(dragOffset) >= threshold
        if isNowCrossed != crossedThreshold {
            crossedThreshold = isNowCrossed
            Haptics.play(.alignment)
        }
    }
}

extension View {
    func onInteractiveTrackpadSwipe(
        dragOffset: Binding<CGFloat>,
        swipeOpacity: Binding<Double>,
        threshold: CGFloat = 90,
        onCommitLeft: @escaping () -> Void,
        onCommitRight: @escaping () -> Void
    ) -> some View {
        modifier(
            InteractiveTrackpadSwipeModifier(
                dragOffset: dragOffset,
                swipeOpacity: swipeOpacity,
                threshold: threshold,
                onCommitLeft: onCommitLeft,
                onCommitRight: onCommitRight
            )
        )
    }
}

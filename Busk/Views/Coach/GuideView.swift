import SwiftUI

/// First-run guide: how to set the phone up, which angle to pick, what Busk shows while you shoot, and how the plan works.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.hasSeenSetupTips) private var hasSeen = false
    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let lines: [(String, String)]
    }

    private let pages: [Page] = [
        Page(id: 0, symbol: "camera.on.rectangle", title: "Set your phone up", lines: [
            ("ruler", "Phone 3-4 m away, about waist height, on a tripod or leaning on something steady."),
            ("person.crop.rectangle", "Your whole body in frame, head to feet, with room above your hands at the release."),
            ("sun.max", "Light behind the phone, not behind you."),
            ("speaker.wave.2", "Volume up or AirPods in: Busk talks to you after every shot."),
        ]),
        Page(id: 1, symbol: "camera.viewfinder", title: "Pick an angle", lines: [
            ("person.fill", "Facing me checks your elbow and guide hand. Start here: they're the most common beginner misses."),
            ("figure.walk", "Side on checks your arc. Use it once your elbow and guide hand are solid."),
            ("checkmark.circle", "Both angles check set point, legs, balance, rhythm, release timing and follow-through."),
        ]),
        Page(id: 2, symbol: "figure.basketball", title: "While you shoot", lines: [
            ("figure.stand", "The top pill says what Busk sees: waiting, gathering, follow through. A crossed-out person means step back into frame."),
            ("text.bubble", "After each shot you hear one fix, the most important one. Fix that, ignore the rest."),
            ("gauge.with.needle", "Form score out of 100: green 85+, yellow 65+, red below. It's your form, not whether it went in."),
            ("circle.grid.3x3", "Each part of the shot gets a dot: green good, yellow close, red needs work."),
        ]),
        Page(id: 3, symbol: "graduationcap", title: "Your coach", lines: [
            ("scope", "After 10 shots Busk picks one focus, the part that's off most often, and builds a daily workout around it."),
            ("book", "Every part has a lesson: why it matters, how to do it, and drills, most without a ball."),
            ("chart.line.uptrend.xyaxis", "Hit 70% good on your focus over 15+ shots and it's mastered. Then Busk moves you to the next one."),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages) { p in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            Image(systemName: p.symbol).font(.system(size: 56)).foregroundStyle(Theme.orange)
                                .frame(maxWidth: .infinity).padding(.top, 40)
                            Text(p.title).font(.largeTitle.bold())
                            ForEach(Array(p.lines.enumerated()), id: \.offset) { _, line in
                                Label {
                                    Text(line.1)
                                } icon: {
                                    Image(systemName: line.0).foregroundStyle(Theme.orange).frame(width: 28)
                                }
                            }
                        }
                        .padding(24)
                    }
                    .tag(p.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .accessibilityIdentifier("guidePages")

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    hasSeen = true
                    dismiss()
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Let's go")
                    .font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24).padding(.bottom, 12)
            .accessibilityIdentifier("guideNextButton")
        }
        .background(Theme.court.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button("Skip") {
                hasSeen = true
                dismiss()
            }
            .padding(20)
            .accessibilityIdentifier("guideSkipButton")
        }
    }
}

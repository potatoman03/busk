import Foundation

/// One lesson in the shooting curriculum: what to do, why, how it goes wrong, and the drills that build it.
struct Lesson: Identifiable, Hashable, Sendable {
    let id: String
    /// The form area Busk measures for this lesson. Nil for the overview lesson.
    let area: FormArea?
    let unit: Unit
    let title: String
    let summary: String
    let why: String
    let steps: [String]
    let mistakes: [String]
    /// A few words to think while shooting.
    let feel: String
    let drillIDs: [String]

    enum Unit: Int, CaseIterable, Sendable {
        case basics, base, upperBody, release
        var title: String {
            switch self {
            case .basics: return "Start here"
            case .base: return "Your base"
            case .upperBody: return "Set and aim"
            case .release: return "The release"
            }
        }
    }

    var drills: [Drill] { drillIDs.compactMap(Drill.byID) }

    /// What Busk looks at for this area, in plain words.
    var howBuskChecks: String? {
        guard let area else { return nil }
        switch area {
        case .setPoint: return "Where your shooting hand is when the ball stops rising: above your head is good, at your shoulders or below is a push."
        case .balance: return "How far your feet move between takeoff and landing, sideways or toward and away from the phone."
        case .rhythm: return "How long the ball sits still at the set point before you shoot. A pause over a quarter second reads as a hitch."
        case .releaseTiming: return "When your hand lets go compared with the top of your jump. Late means you're already coming down."
        case .elbow: return "With the phone facing you: how far your elbow sits outside your wrist just before the release."
        case .guideHand: return "With the phone facing you: whether your guide hand moves toward the hoop after the release."
        case .arc: return "With the phone side on: the angle your arm points at the release. Busk estimates the ball leaves about 20° flatter."
        case .legs: return "How far your hips sink in the dip before you rise."
        case .followThrough: return "How long your shooting hand stays up after the release. Hold it until the ball would reach the rim."
        }
    }

    static func byID(_ id: String) -> Lesson? { all.first { $0.id == id } }
    static func forArea(_ area: FormArea) -> Lesson? { all.first { $0.area == area } }

    static let all: [Lesson] = [
        Lesson(
            id: "overview", area: nil, unit: .basics, title: "How a jump shot works",
            summary: "The four beats of every good shot, and how Busk coaches them.",
            why: "Good shooters look different, but they all repeat the same four beats: dip, set, release, hold. Learn the beats first and every fix that follows has somewhere to go.",
            steps: [
                "Stance: feet shoulder-width, shooting foot a little ahead, toes toward the rim.",
                "Dip: bend your knees and bring the ball into your shooting pocket, by your waist on your shooting side.",
                "Set: lift the ball in one motion to just above your forehead, shooting hand under the ball, elbow under your wrist.",
                "Release: rise, push up through the ball, and let it go near the top of your jump.",
                "Hold: snap your wrist and keep your hand up, fingers pointing at the rim, until the ball lands.",
            ],
            mistakes: [
                "Trying to fix everything at once. Busk gives you one focus at a time on purpose.",
                "Shooting from too far out too soon. Form is built close to the rim.",
            ],
            feel: "Dip, set, release, hold",
            drillIDs: ["shadow", "formShooting"]),
        Lesson(
            id: "legs", area: .legs, unit: .base, title: "Shoot with your legs",
            summary: "Range comes from your legs, not your arms.",
            why: "Stiff legs make your arms do all the work, so tired arms push the ball flat and short. A real dip turns your whole body into the spring.",
            steps: [
                "Start with a slight knee bend, weight on the balls of your feet.",
                "Dip until your thighs are about a third of the way to a squat.",
                "Rise straight up and let the ball travel up with you; legs and arms move together.",
                "Finish on your toes, then land softly.",
            ],
            mistakes: [
                "Bending at the waist instead of the knees.",
                "Dipping, stopping, then shooting: the power leaks out in the pause.",
            ],
            feel: "Sit, then spring",
            drillIDs: ["dipRise", "shadow", "oneStepBack"]),
        Lesson(
            id: "balance", area: .balance, unit: .base, title: "Land where you took off",
            summary: "Jump straight up so every shot starts from the same place.",
            why: "Drifting sideways or fading back changes the shot every time, so you can't repeat it. A straight-up jump is the same shot from anywhere.",
            steps: [
                "Square your feet and hips to the rim before the dip.",
                "Keep your chest over your feet as you rise.",
                "Jump up, not forward, back or sideways.",
                "Land on both feet on the spot you jumped from, and hold the landing for a second.",
            ],
            mistakes: [
                "Leaning back to get the ball off, which turns into a fade.",
                "Jumping toward the rim on every shot (a little forward is fine, a long way isn't).",
            ],
            feel: "Up and down on the X",
            drillIDs: ["landOnX", "shadow", "freeThrows"]),
        Lesson(
            id: "setPoint", area: .setPoint, unit: .upperBody, title: "Set the ball high",
            summary: "Shoot from above your forehead, not from your chest.",
            why: "A chest push throws the ball forward, so it comes out flat and easy to block. Setting high gives the ball a line up and over the rim.",
            steps: [
                "From the dip, lift the ball straight up the middle of your body.",
                "Stop rising when the ball is just above your forehead, slightly to your shooting side. You should see the rim under the ball.",
                "Shooting hand under the ball, wrist cocked back, fingers spread.",
                "From there the ball only goes up and out.",
            ],
            mistakes: [
                "Two hands pushing from the chest, like a pass.",
                "Taking the ball behind your head, which adds a loop.",
            ],
            feel: "Up through the window",
            drillIDs: ["setFreeze", "formShooting", "shadow"]),
        Lesson(
            id: "elbow", area: .elbow, unit: .upperBody, title: "Elbow under the ball",
            summary: "Line up wrist, elbow and knee so the ball goes straight.",
            why: "When your elbow flares out, your push goes sideways and the ball misses left or right. A tucked elbow means your arm pushes straight at the rim.",
            steps: [
                "At the set point your shooting arm makes an L: upper arm level-ish, forearm straight up.",
                "Your elbow sits right under your wrist, pointing at the rim.",
                "If it feels cramped, turn your feet and shoulders a little toward your guide hand. That makes room for the elbow.",
                "Push straight up through the L.",
            ],
            mistakes: [
                "Forcing the elbow in so hard the shoulder tenses. Turn your body instead.",
                "Elbow fine at the set point, then flaring on the way up. Keep it in until the release.",
            ],
            feel: "Elbow points at the rim",
            drillIDs: ["mirrorL", "formShooting", "shadow"]),
        Lesson(
            id: "guideHand", area: .guideHand, unit: .upperBody, title: "Quiet guide hand",
            summary: "The guide hand holds the ball; it never shoots it.",
            why: "A guide hand that pushes or flicks adds sideways spin and sends the ball off line. One hand shoots, the other just steadies.",
            steps: [
                "Guide hand on the side of the ball, fingers pointing up.",
                "Let it come off the ball just before the release.",
                "After the release, the guide hand stays still with its fingers up; it doesn't move toward the rim.",
            ],
            mistakes: [
                "Thumb on the guide hand flicking the ball (the guide-hand thumb push).",
                "Both hands turning over at the finish like a chest pass.",
            ],
            feel: "One hand shoots",
            drillIDs: ["guideOff", "oneHandForm", "shadow"]),
        Lesson(
            id: "rhythm", area: .rhythm, unit: .release, title: "One smooth motion",
            summary: "Dip to release without stopping the ball.",
            why: "Stopping the ball at the set point splits your shot in two: your legs finish before your arms start. One motion carries the leg power into the ball and speeds up your release.",
            steps: [
                "Dip and lift the ball at the same time.",
                "Let the ball pass through the set point without parking it there.",
                "Your release starts as your legs finish straightening.",
                "Say \"dip-up-flick\" as one word while you shoot.",
            ],
            mistakes: [
                "Freezing at the set point to aim. Aim before the dip, with your eyes on the rim.",
                "Rushing so much that the set point disappears. Smooth is not the same as fast.",
            ],
            feel: "Dip-up-flick",
            drillIDs: ["oneCount", "shadow", "freeThrows"]),
        Lesson(
            id: "releaseTiming", area: .releaseTiming, unit: .release, title: "Release at the top",
            summary: "Let the ball go at the peak of your jump.",
            why: "Releasing on the way down means your legs have stopped helping and your arms have to make up the difference, so shots fall short. At the peak your body is still and the legs have given you everything.",
            steps: [
                "Close to the rim, jump only a little, and let the ball go just before your feet leave the floor or right as they do.",
                "Move back a step at a time; the jump gets bigger but the release stays at the top.",
                "If you feel yourself hanging in the air before releasing, you're late.",
            ],
            mistakes: [
                "Jumping as high as you can and then shooting. Jump only as high as you need.",
                "Waiting at the top to aim, which drifts into a late release.",
            ],
            feel: "Up and out",
            drillIDs: ["peakRelease", "shadow", "oneStepBack"]),
        Lesson(
            id: "arc", area: .arc, unit: .release, title: "Put arc on it",
            summary: "Shoot up and over the rim, not at it.",
            why: "A flat shot has a tiny target: the front of the rim. A higher arc makes the hoop bigger from the ball's point of view, so more shots drop. Aim for a launch around 45° to 50°.",
            steps: [
                "Set the ball high (see the set-point lesson). A low set point makes arc hard.",
                "Push the ball up as much as forward, finishing with your arm pointing above the rim.",
                "Think of shooting over a tall defender's hand.",
                "Keep your eyes on the back of the rim and drop the ball over the front.",
            ],
            mistakes: [
                "Throwing the ball at the rim with a straight arm.",
                "Getting arc by leaning back. Arc comes from the arm, not the body.",
            ],
            feel: "Up and over",
            drillIDs: ["wallFlick", "formShooting", "arcOverHand"]),
        Lesson(
            id: "followThrough", area: .followThrough, unit: .release, title: "Hold your follow-through",
            summary: "Snap your wrist and leave your hand up until the ball lands.",
            why: "The follow-through is how the ball gets backspin and a straight line. Dropping your hand early usually means you cut the release short too.",
            steps: [
                "At the release, push up until your arm is straight.",
                "Snap your wrist so your fingers point down at the rim, like reaching into a cookie jar on a high shelf.",
                "Hold it there until the ball hits the rim or the net.",
                "Index and middle fingers are the last to touch the ball.",
            ],
            mistakes: [
                "Pulling the hand back down straight away to chase the rebound.",
                "Finishing with fingers pointing sideways: that's the ball's spin going sideways too.",
            ],
            feel: "Reach into the cookie jar",
            drillIDs: ["wallFlick", "oneHandForm", "shadow"]),
    ]
}

/// A drill: a short exercise that builds one or two parts of the shot. Some need a ball, some only space to move.
struct Drill: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String
    let needsBall: Bool
    let areas: [FormArea]
    /// How much to do, e.g. "3 sets of 10".
    let dose: String
    let steps: [String]
    /// Busk can watch this drill with the camera and grade every rep.
    let tracked: Bool

    static func byID(_ id: String) -> Drill? { all.first { $0.id == id } }

    static let all: [Drill] = [
        Drill(id: "shadow", title: "Shadow shooting", summary: "Your full shot with no ball. Busk tracks and grades every rep.",
              needsBall: false, areas: FormArea.allCases, dose: "3 sets of 10",
              steps: [
                  "Set your phone up as for a session, whole body in frame.",
                  "Hold your hands as if on a ball in your shooting pocket.",
                  "Dip, set, release and hold, at full speed, like a real shot.",
                  "Reset your feet between reps. Busk speaks a cue after each one.",
              ], tracked: true),
        Drill(id: "dipRise", title: "Dip and rise", summary: "Train the leg spring and the arms rising with it.",
              needsBall: false, areas: [.legs, .rhythm], dose: "3 sets of 8",
              steps: [
                  "Feet shoulder-width, hands in your shooting pocket.",
                  "Dip as if you were about to sit on a tall bar stool: knees bent, hips back a little, heels down.",
                  "Jump straight up, just a few centimetres off the floor, bringing your hands to the set point on the way.",
                  "Land softly on both feet where you took off, then reset. Speed up, never pause at the bottom.",
              ], tracked: true),
        Drill(id: "landOnX", title: "Land on the X", summary: "Jump straight up and down on a mark.",
              needsBall: false, areas: [.balance], dose: "2 sets of 10",
              steps: [
                  "Mark an X on the floor with tape or chalk and stand on it.",
                  "Shoot (with or without a ball) and land with both feet back on the X.",
                  "Hold the landing for one second. Any wobble means you drifted.",
              ], tracked: true),
        Drill(id: "setFreeze", title: "Set-point freeze", summary: "Find a high set point and memorize the feel.",
              needsBall: false, areas: [.setPoint, .elbow], dose: "2 sets of 10",
              steps: [
                  "From your shooting pocket, lift your hands in one motion to just above your forehead.",
                  "Freeze for two seconds. Check: rim visible under your hands, elbow under your wrist.",
                  "Lower and repeat. Do the last few with your eyes closed.",
              ], tracked: false),
        Drill(id: "mirrorL", title: "Mirror L check", summary: "Line up the elbow in front of a mirror or your phone.",
              needsBall: false, areas: [.elbow], dose: "3 sets of 10",
              steps: [
                  "Stand facing a mirror, or set Busk to Facing me.",
                  "Lift to the set point: your arm makes an L with the elbow straight under the wrist.",
                  "Push straight up from the L and hold the finish. Your hand should end above your eyebrow, not out to the side.",
                  "If the elbow flares, turn your feet a little toward your guide hand and try again.",
              ], tracked: true),
        Drill(id: "guideOff", title: "Guide hand off", summary: "Teach the guide hand to stay quiet.",
              needsBall: false, areas: [.guideHand], dose: "3 sets of 10",
              steps: [
                  "Set Busk to Facing me so it can check your guide hand, then start a session.",
                  "Shadow shoot with your guide hand flat on the side of an imaginary ball, fingers up.",
                  "At the release, freeze. Your guide hand should still point up, at the same height, not toward the rim.",
                  "With a ball: shoot from 1-2 m and take the guide hand off just before the release.",
              ], tracked: true),
        Drill(id: "oneCount", title: "One-count rhythm", summary: "Shoot from dip to release as one beat.",
              needsBall: false, areas: [.rhythm, .releaseTiming], dose: "3 sets of 10",
              steps: [
                  "Say \"dip-up-flick\" out loud, as one word.",
                  "Shoot to the words: dip on \"dip\", rise on \"up\", release on \"flick\".",
                  "No stop at the set point. Speed up the count only when it stays smooth.",
              ], tracked: true),
        Drill(id: "peakRelease", title: "Peak release", summary: "Time the release to the top of a small jump.",
              needsBall: false, areas: [.releaseTiming, .legs], dose: "3 sets of 8",
              steps: [
                  "Shadow shoot with a small jump.",
                  "Your hand should snap at the moment you stop rising, not after.",
                  "Add a little more jump each set while keeping the release at the top.",
              ], tracked: true),
        Drill(id: "wallFlick", title: "Wall flick", summary: "Grooves a high finish and a wrist snap, no ball needed.",
              needsBall: false, areas: [.followThrough, .arc], dose: "3 sets of 15",
              steps: [
                  "Stand with your shooting side to a wall. Hold your arm straight out sideways: your fingertips should just touch it.",
                  "From the set point, push up so your fingertips brush the wall high above your head.",
                  "Snap your wrist so your fingers point down. Hold for two seconds.",
                  "With a ball: lie on your back and flick the ball straight up a metre, catch, repeat.",
              ], tracked: false),
        Drill(id: "formShooting", title: "Form shooting", summary: "One-hand shots right at the rim to build a clean, repeatable stroke.",
              needsBall: true, areas: [.elbow, .followThrough, .setPoint, .arc], dose: "5 makes from 3 spots",
              steps: [
                  "Stand 1 m from the rim, straight in front.",
                  "Shooting hand only, guide hand behind your back.",
                  "Set high, elbow under, push up, hold the finish until it drops.",
                  "Move to 2 m after 5 makes, then 3 m. If you miss 3 in a row, step in.",
              ], tracked: true),
        Drill(id: "oneHandForm", title: "One-hand form", summary: "Shoot with only your shooting hand so the guide hand can't interfere.",
              needsBall: true, areas: [.guideHand, .followThrough], dose: "3 sets of 10",
              steps: [
                  "Guide hand behind your back, 1-2 m from the rim.",
                  "Balance the ball on your shooting hand, fingers spread.",
                  "Shoot and hold the finish. Add the guide hand back for the last set, touching only the side.",
              ], tracked: true),
        Drill(id: "arcOverHand", title: "Over the hand", summary: "Practise arc by shooting over a high target.",
              needsBall: true, areas: [.arc], dose: "3 sets of 10",
              steps: [
                  "Shoot from 2-3 m. Imagine a defender's hand a metre in front of you at full stretch, or have a friend hold one up.",
                  "Every shot goes over the hand and drops into the rim.",
                  "Listen for swishes: a flat shot rattles the front of the rim.",
              ], tracked: true),
        Drill(id: "oneStepBack", title: "One step back", summary: "Grow range without losing form.",
              needsBall: true, areas: [.legs, .releaseTiming], dose: "Until you miss twice at a spot",
              steps: [
                  "Start 2 m from the rim. Make 2 in a row, take a step back.",
                  "The extra distance comes from more dip, not a harder arm push.",
                  "Two misses in a row: step back in and start again.",
              ], tracked: true),
        Drill(id: "freeThrows", title: "Free throws", summary: "Same routine, same shot, every time.",
              needsBall: true, areas: [.rhythm, .balance], dose: "2 sets of 10",
              steps: [
                  "Pick a routine: bounces, a breath, eyes on the rim. Do the same one every shot.",
                  "Shoot with a small knee bend, no jump, one smooth motion.",
                  "Count your makes out of 10 and try to beat it next time.",
              ], tracked: true),
    ]
}

extension FormArea {
    /// The camera angle that measures this area. Elbow and guide hand are only judged facing you, arc only side on.
    var bestView: CameraView? {
        switch self {
        case .elbow, .guideHand: return .front
        case .arc: return .side
        default: return nil
        }
    }

    /// Spoken after a focus-set shot where this area was good.
    func praise(_ n: Int) -> String {
        let name = title.lowercased()
        let lines = ["Good \(name) that time. Same again", "That's it on your \(name). Keep it", "\(title) looked right. Again",
                     "Yes, spot on with your \(name). Repeat it"]
        return lines[abs(n) % lines.count]
    }
}

extension AreaResult {
    /// What this measurement means, in plain words for the shot card.
    var plain: String {
        let (good, ok, bad): (String, String, String)
        switch area {
        case .setPoint: (good, ok, bad) = ("High set, above your forehead", "Set a little low", "Ball set too low, from your chest")
        case .releaseTiming: (good, ok, bad) = ("Let go at the top of your jump", "Let go a touch late", "Let go on the way down")
        case .balance: (good, ok, bad) = ("Landed where you took off", "Drifted a little in the air", "Drifted a lot in the air")
        case .rhythm: (good, ok, bad) = ("One smooth motion", "Small pause at the top", "Ball stopped at the set point")
        case .elbow: (good, ok, bad) = ("Elbow under the ball", "Elbow out a little", "Elbow flared out wide")
        case .guideHand: (good, ok, bad) = ("Guide hand came off clean", "Guide hand nudged the ball", "Guide hand pushed the ball")
        case .arc: (good, ok, bad) = ("Good arc", "Arc a little flat", "Flat shot, aim higher")
        case .legs: (good, ok, bad) = ("Good dip into your legs", "Not much knee bend", "Barely any knee bend")
        case .followThrough: (good, ok, bad) = ("Held your follow-through", "Follow-through a bit short", "Dropped your hand right away")
        }
        switch grade {
        case .good: return good
        case .ok: return ok
        case .needsWork: return bad
        }
    }
}

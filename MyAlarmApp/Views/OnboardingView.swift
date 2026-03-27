import SwiftUI
 
struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @State private var currentPage = 0
    @State private var opacity: Double = 1.0
 
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09)
                .ignoresSafeArea()
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            if value.translation.width < -50 {
                                if currentPage < 5 { navigate(to: currentPage + 1) }
                            } else if value.translation.width > 50 {
                                if currentPage > 0 { navigate(to: currentPage - 1) }
                            }
                        }
                )
 
            VStack(spacing: 0) {
 
                // MARK: Status bar spacer
                Spacer().frame(height: 12)
 
                // MARK: Skip button
                HStack {
                    Spacer()
                    if currentPage < 5 {
                        Button("Skip") {
                            // ✅ UPDATED — skip goes directly to main app, not last onboarding screen
                            hasSeenOnboarding = true
                        }
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .padding(.trailing, 24)
                    }
                }
                .frame(height: 36)
 
                // MARK: Screen content
                ZStack {
                    switch currentPage {
                    case 0: Screen1().transition(.opacity)
                    case 1: Screen2().transition(.opacity)
                    case 2: Screen3().transition(.opacity)
                    case 3: Screen4().transition(.opacity)
                    case 4: Screen5().transition(.opacity)
                    case 5: Screen6().transition(.opacity)
                    default: Screen1().transition(.opacity)
                    }
                }
                .opacity(opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // ✅ ADDED — swipe left to go next, swipe right to go back
 
                // MARK: Dots
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(i == currentPage ? Color.orange : Color.white.opacity(0.18))
                            .frame(width: i == currentPage ? 28 : 8, height: 8)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 20)
 
                // MARK: Buttons
                HStack(spacing: 12) {
                    // ✅ UPDATED — Back button now shows on ALL pages including last page (page 5)
                    if currentPage > 0 {
                        Button {
                            navigate(to: currentPage - 1)
                        } label: {
                            Text("Back")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.orange.opacity(0.35), lineWidth: 1.5)
                                )
                        }
                    }
 
                    Button {
                        if currentPage == 5 {
                            hasSeenOnboarding = true
                        } else {
                            navigate(to: currentPage + 1)
                        }
                    } label: {
                        Text(currentPage == 5 ? "🚀 Get Started" : "Next")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .orange.opacity(0.4), radius: 12, y: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
        // ✅ ADDED — force dark mode for onboarding always
        .preferredColorScheme(.dark)
    }
 
    func navigate(to page: Int) {
        withAnimation(.easeOut(duration: 0.18)) { opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            currentPage = page
            withAnimation(.easeIn(duration: 0.18)) { opacity = 1 }
        }
    }
}
 
// MARK: - Screen 1: Welcome
private struct Screen1: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            // Icon with glow
            ZStack {
                RadialGradient(
                    colors: [Color.orange.opacity(0.3), Color.clear],
                    center: .center, startRadius: 10, endRadius: 130
                )
                .frame(width: 260, height: 260)
 
                RoundedRectangle(cornerRadius: 44)
                    .fill(Color(red: 0.15, green: 0.11, blue: 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 44)
                            .stroke(Color.orange.opacity(0.12), lineWidth: 1)
                    )
                    .frame(width: 180, height: 180)
 
                Image(systemName: "alarm")
                    .font(.system(size: 80, weight: .thin))
                    .foregroundStyle(Color.orange)
            }
            .padding(.bottom, 48)
 
            // Title
            HStack(spacing: 0) {
                Text("Future ")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Alarm")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(.orange)
            }
            .padding(.bottom, 12)
 
            Text("Your smart alarm companion")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.4))
 
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}
 
// MARK: - Screen 2: Future Alarm / Set in Advance
private struct Screen2: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
 
            // Illustration
            ZStack {
                RadialGradient(
                    colors: [Color.orange.opacity(0.18), Color.clear],
                    center: .center, startRadius: 10, endRadius: 120
                )
                .frame(width: 240, height: 240)
 
                Canvas { ctx, size in
                    let cx: CGFloat = 100, cy: CGFloat = 108, r: CGFloat = 68
                    var facePath = Path()
                    facePath.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
                    ctx.fill(facePath, with: .color(Color(red: 0.11, green: 0.07, blue: 0.02).opacity(0.7)))
 
                    var arcPath = Path()
                    arcPath.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(-190), endAngle: .degrees(80), clockwise: false)
                    ctx.stroke(arcPath, with: .color(.orange), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [18, 8]))
 
                    var hourPath = Path()
                    hourPath.move(to: CGPoint(x: cx, y: cy))
                    hourPath.addLine(to: CGPoint(x: cx, y: cy - 40))
                    ctx.stroke(hourPath, with: .color(.white), style: StrokeStyle(lineWidth: 5, lineCap: .round))
 
                    var minPath = Path()
                    minPath.move(to: CGPoint(x: cx, y: cy))
                    minPath.addLine(to: CGPoint(x: cx + 36, y: cy))
                    ctx.stroke(minPath, with: .color(.white), style: StrokeStyle(lineWidth: 5, lineCap: .round))
 
                    var dotPath = Path()
                    dotPath.addArc(center: CGPoint(x: cx, y: cy), radius: 5, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
                    ctx.fill(dotPath, with: .color(.white))
                }
                .frame(width: 200, height: 200)
 
                // Calendar popup
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange)
                            .frame(width: 20, height: 9)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange.opacity(0.35))
                            .frame(width: 9, height: 9)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange.opacity(0.35))
                            .frame(width: 9, height: 9)
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 9, height: 9)
                        }
                    }
                }
                .padding(12)
                .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange, lineWidth: 2))
                .offset(x: 68, y: -62)
            }
            .padding(.bottom, 40)
 
            Text("Future Alarm")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.bottom, 6)
 
            Text("(Set in Advance)")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.orange)
                .italic()
                .padding(.bottom, 16)
 
            Text("Set alarms days or weeks ahead.\nNever miss important events.\nSchedule your future self!")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
 
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}
 
// MARK: - Screen 3: Smart Alarms
private struct Screen3: View {
    let bars: [CGFloat] = [0.6, 0.3, 0.8, 0.4, 0.9, 0.35, 0.7, 0.45, 0.55, 0.3]
 
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
 
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(red: 0.42, green: 0.23, blue: 0.72))
                        .frame(width: 34, height: 34)
                        .overlay(Text("♪").foregroundStyle(.white).font(.system(size: 17)))
 
                    Text("Select Your Ringtone")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
 
                    Spacer()
 
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().fill(.white).frame(width: 7, height: 7))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(Color.orange.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange, lineWidth: 1.5))
 
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white)
                                .frame(width: 11, height: 11)
                        )
 
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(0..<10, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i < 5 ? Color.orange : Color.white.opacity(0.2))
                                .frame(width: 4, height: bars[i] * 26)
                        }
                    }
                    .frame(maxWidth: .infinity)
 
                    Text("00:04")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(Color(white: 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(14)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .padding(.bottom, 32)
 
            Text("Smart Alarms")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.bottom, 12)
 
            Text("Pick your favourite ringtone — or record\nyour own voice to wake up motivated!")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
 
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
 
// MARK: - Screen 4: Timers & Live Activity
private struct Screen4: View {
    @State private var progress: CGFloat = 0.65
 
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
 
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 34)
                    .fill(Color(white: 0.1))
                    .frame(width: 255, height: 290)
                    .overlay(
                        RoundedRectangle(cornerRadius: 34)
                            .stroke(Color(white: 0.18), lineWidth: 5)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
 
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.black)
                        .frame(width: 76, height: 20)
                        .padding(.top, 10)
 
                    VStack(spacing: 0) {
                        Text("MONDAY, JULY 15")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .tracking(2)
                            .padding(.top, 10)
 
                        Text("10:09")
                            .font(.system(size: 44, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.top, 2)
                            .padding(.bottom, 14)
 
                        VStack(spacing: 0) {
                            HStack {
                                HStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.orange)
                                        .frame(width: 20, height: 20)
                                        .overlay(Image(systemName: "alarm").font(.system(size: 10)).foregroundStyle(.black))
                                    Text("FUTURE ALARM")
                                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.white.opacity(0.45))
                                        .tracking(1)
                                }
                                Spacer()
                                Text("Now")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.3))
                            }
                            .padding(.bottom, 5)
 
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Morning Coffee")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("04:52")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundStyle(.orange)
                                }
                                Spacer()
                                ZStack {
                                    Circle()
                                        .stroke(Color.orange.opacity(0.18), lineWidth: 3)
                                    Circle()
                                        .trim(from: 0, to: progress)
                                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                }
                                .frame(width: 46, height: 46)
                            }
                        }
                        .padding(12)
                        .background(Color(white: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.orange.opacity(0.28), lineWidth: 1))
                        .padding(.horizontal, 14)
 
                        HStack {
                            Text("⏱ Kitchen Timer")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.38))
                            Spacer()
                            Text("12:30")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(Color(white: 0.11))
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.bottom, 34)
            .onAppear {
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                    progress = 0.0
                }
            }
 
            Text("Timers & Live Activity")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.bottom, 12)
 
            Text("Countdown timers live on your lock screen.\nNo need to unlock — always in sight!")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
 
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
 
// MARK: - Screen 5: Quick Actions
private struct Screen5: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
 
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 36)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.11, green: 0.11, blue: 0.18), Color(red: 0.06, green: 0.06, blue: 0.13)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 300, height: 285)
                    .overlay(RoundedRectangle(cornerRadius: 36).stroke(Color.white.opacity(0.07), lineWidth: 1))
 
                HStack(spacing: 14) {
                    ForEach(0..<4) { _ in
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 54, height: 54)
                    }
                }
                .padding(.top, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 18)
 
                VStack(alignment: .trailing, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(["New Alarm", "New Timer", "5 Min Timer", "Settings"], id: \.self) { item in
                            HStack {
                                Text(item)
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 13)
                            if item != "Settings" {
                                Divider().background(Color.white.opacity(0.07))
                            }
                        }
                    }
                    .background(Color(red: 0.17, green: 0.17, blue: 0.19))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.07), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                    .frame(width: 178)
                    .padding(.trailing, 14)
 
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.orange)
                        .frame(width: 64, height: 64)
                        .overlay(Image(systemName: "alarm").font(.system(size: 30, weight: .medium)).foregroundStyle(.black))
                        .shadow(color: .orange.opacity(0.5), radius: 10, y: 4)
                        .padding(.trailing, 14)
                        .padding(.bottom, 18)
                }
            }
            .frame(width: 300, height: 285)
            .padding(.bottom, 34)
 
            Text("Quick Actions")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.bottom, 12)
 
            Text("Long press the app icon for instant shortcuts like **New Alarm**, **New Timer**, or **Settings** via Haptic Touch.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
 
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
 
// MARK: - Screen 6: Calendar Integration
private struct Screen6: View {
    let week1 = [28, 29, 30, 1, 2, 3, 4]
    let week2 = [5, 6, 7, 8, 9, 10, 11]
    let dotDates: Set<Int> = [1, 4, 7]
    let dayHeaders = ["S","M","T","W","T","F","S"]
 
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
 
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("October")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Spacer()
                    HStack(spacing: 8) {
                        Circle().fill(Color.white.opacity(0.18)).frame(width: 9, height: 9)
                        Circle().fill(Color.white.opacity(0.18)).frame(width: 9, height: 9)
                    }
                }
                .padding(.bottom, 14)
 
                HStack(spacing: 0) {
                    ForEach(dayHeaders, id: \.self) { d in
                        Text(d)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.3))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 6)
 
                ForEach([week1, week2], id: \.first) { week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { idx, date in
                            let isCurrentMonth = !(week == week1 && idx < 3)
                            VStack(spacing: 2) {
                                Text("\(date)")
                                    .font(.system(size: 15, weight: .regular, design: .rounded))
                                    .foregroundStyle(isCurrentMonth ? .white : Color.white.opacity(0.18))
                                if dotDates.contains(date) && isCurrentMonth {
                                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                                } else {
                                    Circle().fill(Color.clear).frame(width: 6, height: 6)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                        }
                    }
                }
 
                Divider()
                    .background(Color.white.opacity(0.07))
                    .padding(.vertical, 10)
 
                Text("UPCOMING")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .tracking(1.5)
                    .padding(.bottom, 8)
 
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange)
                        .frame(width: 3, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Morning Workout")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                        Text("07:00 AM")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
            }
            .padding(20)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.05), lineWidth: 1))
            .padding(.bottom, 32)
 
            Text("Calendar Integration")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.bottom, 12)
 
            Text("Alarms sync to your iPhone Calendar.\nSee everything at a glance with orange dots!")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
 
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
 
#if DEBUG && targetEnvironment(simulator)
#Preview {
    OnboardingView()
}
#endif

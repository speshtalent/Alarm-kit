import SwiftUI

struct AddTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int = 5
    @State private var seconds: Int = 0
    @State private var title: String = "Timer"
    var onStart: (TimeInterval, String) -> Void

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea()

            VStack(spacing: 24) {
                // Handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(white: 0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)

                Text("New Timer")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                // Time Picker
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(white: 0.13))
                    HStack(spacing: 0) {
                        Picker("Minutes", selection: $minutes) {
                            ForEach(0...179, id: \.self) { m in
                                Text("\(m) min").tag(m)
                                    .foregroundStyle(.white)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)

                        Picker("Seconds", selection: $seconds) {
                            ForEach(0...59, id: \.self) { s in
                                Text("\(s) sec").tag(s)
                                    .foregroundStyle(.white)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                    }
                    .colorScheme(.dark)
                    .padding(8)
                }
                .padding(.horizontal, 20)

                // Title Field
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.13))
                    HStack {
                        Image(systemName: "tag").foregroundStyle(.orange)
                        TextField("Timer title", text: $title)
                            .foregroundStyle(.white)
                            .tint(.orange)
                    }
                    .padding(16)
                }
                .frame(height: 54)
                .padding(.horizontal, 20)

                Spacer()

                // Start Button
                Button {
                    let duration = TimeInterval(minutes * 60 + seconds)
                    onStart(duration, title)
                    dismiss()
                } label: {
                    Text("Start Timer")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }
}

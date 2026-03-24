import SwiftUI

struct AddTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var minutes: Int = 5
    @State private var seconds: Int = 0
    @State private var title: String = "Timer"
    @State private var selectedSound = "nokia.caf"

    let sounds: [(name: String, file: String)] = [
        (name: "Nokia", file: "nokia.caf"),
        (name: "1985 Ring", file: "1985_ring2.caf"),
        (name: "Sony", file: "sony.caf")
    ]

    var onStart: (TimeInterval, String, String) -> Void

    var body: some View {
        ZStack {
            // ✅ UPDATED — dynamic background
            Color("AppBackground").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Handle
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color("SecondaryText").opacity(0.4))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)

                    Text("New Timer")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        // ✅ UPDATED — dynamic text
                        .foregroundStyle(Color("PrimaryText"))

                    // ✅ UPDATED — Time Picker card
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color("CardBackground"))
                        HStack(spacing: 0) {
                            Picker("Minutes", selection: $minutes) {
                                ForEach(0...179, id: \.self) { m in
                                    Text("\(m) min").tag(m)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)

                            Picker("Seconds", selection: $seconds) {
                                ForEach(0...59, id: \.self) { s in
                                    Text("\(s) sec").tag(s)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                        }
                        // ✅ UPDATED — follows system color scheme
                        .colorScheme(colorScheme)
                        .padding(8)
                    }
                    .padding(.horizontal, 20)

                    // ✅ UPDATED — Title Field card
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color("CardBackground"))
                        HStack {
                            Image(systemName: "tag").foregroundStyle(.orange)
                            TextField("Timer title", text: $title)
                                // ✅ UPDATED — dynamic text
                                .foregroundStyle(Color("PrimaryText"))
                                .tint(.orange)
                        }
                        .padding(16)
                    }
                    .frame(height: 54)
                    .padding(.horizontal, 20)

                    // ✅ UPDATED — Sound Picker card
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color("CardBackground"))
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "bell.fill")
                                    .foregroundStyle(.orange)
                                Text("Sound")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    // ✅ UPDATED — dynamic text
                                    .foregroundStyle(Color("PrimaryText"))
                            }
                            Divider()
                            ForEach(sounds, id: \.file) { sound in
                                Button {
                                    selectedSound = sound.file
                                } label: {
                                    HStack {
                                        Text(sound.name)
                                            .font(.system(size: 15, weight: .medium, design: .rounded))
                                            // ✅ UPDATED — dynamic text
                                            .foregroundStyle(Color("PrimaryText"))
                                        Spacer()
                                        if selectedSound == sound.file {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)

                    // Start Button
                    Button {
                        let duration = TimeInterval(minutes * 60 + seconds)
                        onStart(duration, title, selectedSound)
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
}

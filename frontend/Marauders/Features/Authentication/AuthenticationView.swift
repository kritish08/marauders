import SwiftUI

struct AuthenticationView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phone = "98765 43210"
    @State private var otp = ""
    @State private var step: Step = .phone
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    private let service = DemoAuthenticationService()

    enum Step { case phone, otp }
    private enum Field { case phone, otp }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.surface, Theme.surfaceContainer, Theme.goldLight.opacity(0.32)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            Circle()
                .fill(Theme.primary.opacity(0.08))
                .frame(width: 330)
                .blur(radius: 2)
                .offset(x: 160, y: -330)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    brand.oneTimeStaggeredReveal(0)
                    welcome.oneTimeStaggeredReveal(1)
                    authenticationCard.oneTimeStaggeredReveal(2)
                }
                .padding(.horizontal, 20)
                .padding(.top, 42)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .task(id: step) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedField = step == .phone ? .phone : .otp
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image("MaraudersLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Marauders logo")
            VStack(alignment: .leading, spacing: 0) {
                Text("MARAUDERS")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(2)
                Text("STORIES IN EVERY STEP")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.gold)
            }
        }
        .foregroundStyle(Theme.primary)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(step == .phone ? "Your journey starts here." : "Check your messages.")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(step == .phone ? "Unlock the stories hidden inside every monument." : "Enter the 6-digit code sent to +91 \(phone).")
                .font(.system(size: 17))
                .foregroundStyle(Theme.mutedInk)
        }
    }

    private var authenticationCard: some View {
        VStack(spacing: 18) {
            if step == .phone {
                phoneField
                Button(action: requestOTP) {
                    loadingLabel("Continue")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(phone.filter(\.isNumber).count < 10 || isLoading)

                divider

                Button {
                    focusedField = nil
                    session.signIn(phone: "Google demo account")
                } label: {
                    HStack(spacing: 12) {
                        Text("G").font(.system(size: 19, weight: .bold))
                        Text("Continue with Google").fontWeight(.semibold)
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 15).stroke(Theme.outline.opacity(0.7)) }
                }
                .accessibilityIdentifier("googleSignInButton")
            } else {
                otpField
                Text("Demo code: 123456")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.teal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: verifyOTP) {
                    loadingLabel("Verify & enter")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(otp.count != 6 || isLoading)
                .accessibilityIdentifier("verifyOTPButton")

                Button("Use a different number") {
                    focusedField = nil
                    withAnimation(Motion.change(reduceMotion: reduceMotion)) { step = .phone; otp = ""; errorMessage = nil }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primary)
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    .transition(.opacity)
            }

            Text("By continuing, you agree to the demo Terms and Privacy Policy.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.mutedInk.opacity(0.8))
        }
        .padding(22)
        .heritageCard()
    }

    private var phoneField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PHONE NUMBER").font(.caption.weight(.bold)).tracking(1).foregroundStyle(Theme.mutedInk)
            HStack {
                Text("+91").fontWeight(.semibold)
                Divider().frame(height: 24)
                TextField("98765 43210", text: $phone)
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: .phone)
                    .accessibilityIdentifier("phoneField")
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Theme.surfaceLow, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.outline.opacity(0.55)) }
        }
    }

    private var otpField: some View {
        TextField("123456", text: $otp)
            .keyboardType(.numberPad)
            .focused($focusedField, equals: .otp)
            .multilineTextAlignment(.center)
            .font(.system(size: 26, weight: .bold, design: .monospaced))
            .tracking(10)
            .padding(.leading, 10)
            .frame(height: 60)
            .background(Theme.surfaceLow, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.outline.opacity(0.55)) }
            .onChange(of: otp) { _, value in otp = String(value.filter(\.isNumber).prefix(6)) }
            .accessibilityIdentifier("otpField")
    }

    private var divider: some View {
        HStack { Rectangle().frame(height: 1); Text("OR").font(.caption.weight(.semibold)); Rectangle().frame(height: 1) }
            .foregroundStyle(Theme.outline)
    }

    private func loadingLabel(_ text: LocalizedStringKey) -> some View {
        HStack { if isLoading { ProgressView().tint(.white) }; Text(text) }
    }

    private func requestOTP() {
        focusedField = nil
        isLoading = true
        Task {
            try? await service.requestOTP(for: phone)
            isLoading = false
            withAnimation(Motion.change(reduceMotion: reduceMotion)) { step = .otp }
        }
    }

    private func verifyOTP() {
        focusedField = nil
        isLoading = true
        Task {
            let valid = (try? await service.verify(otp: otp)) ?? false
            isLoading = false
            if valid {
                session.signIn(phone: phone)
            } else {
                withAnimation(Motion.change(reduceMotion: reduceMotion)) {
                    errorMessage = "That code is not valid. Try 123456."
                }
            }
        }
    }
}

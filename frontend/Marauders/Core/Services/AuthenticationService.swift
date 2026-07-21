import Foundation

protocol AuthenticationServing {
    func requestOTP(for phone: String) async throws
    func verify(otp: String) async throws -> Bool
}

struct DemoAuthenticationService: AuthenticationServing {
    func requestOTP(for phone: String) async throws {
        try await Task.sleep(for: .milliseconds(450))
    }

    func verify(otp: String) async throws -> Bool {
        try await Task.sleep(for: .milliseconds(350))
        return otp == "123456"
    }
}

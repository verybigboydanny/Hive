import Foundation

enum HiveBackendError: LocalizedError {
    case serviceUnavailable(String)
    case invalidResponse
    case api(code: String, message: String, hint: String?)

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable(let message): message
        case .invalidResponse: "Hive returned a response the app could not read."
        case .api(let code, let message, let hint):
            if let hint {
                "\(message) (\(code))\n\(hint)"
            } else {
                "\(message) (\(code))"
            }
        }
    }
}

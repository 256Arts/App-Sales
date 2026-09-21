import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidCredentials
    case wrongPermissions
    case exceededLimit
    case noDataAvailable
    case unknown
    /// A failure none of the cases above describe, carrying its own explanation so it can be diagnosed.
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "The credentials you entered are incorrect."
        case .wrongPermissions:
            return "Your API-key does not have the right permissions."
        case .exceededLimit:
            return "You have exceeded the daily limit of API requests."
        case .noDataAvailable:
            return "Data is not yet available."
        case .unknown:
            return "An unknown error occurred. Please file a bug report."
        case .failed(let reason):
            return reason
        }
    }
}

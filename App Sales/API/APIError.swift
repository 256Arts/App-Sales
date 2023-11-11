//
//  APIError.swift
//  AC Widget by NO-COMMENT
//

import Foundation

enum APIError: LocalizedError {
    case invalidCredentials
    case wrongPermissions
    case exceededLimit
    case noDataAvailable
    case unknown

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
        }
    }
}

import Foundation

// MARK: - Auth

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct LoginResponse: Decodable {
    let access: String
    let refresh: String
}

struct RefreshRequest: Encodable {
    let refresh: String
}

struct RefreshResponse: Decodable {
    let access: String
}

struct RegisterRequest: Encodable {
    let email: String
    let username: String
    let first_name: String
    let last_name: String
    let password: String
    let password_confirm: String
    let profile: ProfileData
}

struct ProfileData: Encodable {
    let cpf: String
    let phone: String
    let birth_date: String
    let cep: String
}

// MARK: - User

struct UserModel: Codable {
    let id: Int
    let email: String
    let first_name: String
    let last_name: String

    var fullName: String {
        let name = "\(first_name) \(last_name)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? email : name
    }
}

// MARK: - Passwords

struct VerifyPasswordRequest: Encodable {
    let password: String
    let latitude: Double?
    let longitude: Double?
}

struct VerifyPasswordResponse: Decodable {
    let action: String
    let message: String?
    let attempts_count: Int?
    let max_attempts: Int?
    let wrong_attempts: Int?

    var attemptsCount: Int { attempts_count ?? wrong_attempts ?? 0 }
    var maxAttempts: Int  { max_attempts ?? 0 }
    var limitExceeded: Bool { maxAttempts > 0 && attemptsCount >= maxAttempts }
}

struct SetPasswordsRequest: Encodable {
    let bank_password: String
    let ppix_password: String
    let emergency_password: String
}

struct SavedPasswordsResponse: Decodable {
    let id: Int?
    let bank_password_plain: String?
    let ppix_password_plain: String?
    let emergency_password_plain: String?
    let max_wrong_attempts: Int?
    let reset_attempts_after_minutes: Int?
    // Paginado
    let results: [SavedPasswordsResponse]?
    let count: Int?
}

struct PasswordAttemptsRequest: Encodable {
    let max_wrong_attempts: Int
    let reset_attempts_after_minutes: Int
}

// MARK: - Vehicles

struct Vehicle: Codable, Identifiable {
    let id: Int?
    let model: String
    let license_plate: String
    let color: String
    let year: Int
    let is_active: Bool

    var displayText: String {
        let m = model.prefix(1).uppercased() + model.dropFirst()
        let c = color.prefix(1).uppercased() + color.dropFirst()
        return "\(m), \(year), \(c) - Placa: \(license_plate)"
    }
}

struct VehicleRequest: Encodable {
    let model: String
    let license_plate: String
    let color: String
    let year: Int
    let is_active: Bool
}

struct VehicleListResponse: Decodable {
    let results: [Vehicle]?
    let count: Int?
}

// MARK: - Alerts

struct Alert: Codable, Identifiable {
    let id: Int
    let sender: Int
    let sender_name: String
    let sender_email: String
    let alert_type: String
    let priority: String
    let status: String
    let title: String
    let message: String
    let latitude: String?
    let longitude: String?
    let has_location: Bool
    let location_url: String?
    let vehicle_info: VehicleInfo?
    let created_at: String
    let recipients: [AlertRecipient]

    var alertIcon: String {
        switch alert_type {
        case "emergency_password": return "🚨"
        case "wrong_password":     return "⚠️"
        default:                   return "📢"
        }
    }

    var vehicleText: String {
        guard let v = vehicle_info, !v.model.isEmpty else { return "" }
        let m = v.model.prefix(1).uppercased() + v.model.dropFirst()
        let c = v.color.prefix(1).uppercased() + v.color.dropFirst()
        return "\(m), \(v.year), \(c) - Placa: \(v.license_plate)"
    }

    var googleMapsURL: URL? {
        guard has_location, let lat = latitude, let lng = longitude else { return nil }
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lng)")
    }

    var formattedDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: created_at) else { return created_at }
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy HH:mm"
        df.locale = Locale(identifier: "pt_BR")
        return df.string(from: date)
    }
}

struct VehicleInfo: Codable {
    let model: String
    let license_plate: String
    let color: String
    let year: Int
}

struct AlertRecipient: Codable {
    let id: Int
    let recipient_name: String
    let recipient_email: String
    let delivery_status: String
}

struct AlertListResponse: Decodable {
    let results: [Alert]?
}

struct SendAlertRequest: Encodable {
    let alert_type: String
    let priority: String
    let title: String
    let message: String
    let latitude: String?
    let longitude: String?
    let metadata: AlertMetadata
    let recipient_ids: [Int]
}

struct AlertMetadata: Encodable {
    let timestamp: String
    let vehicle_info: VehicleInfoPayload?
}

struct VehicleInfoPayload: Encodable {
    let model: String
    let license_plate: String
    let color: String
    let year: Int
}

// MARK: - Connections

struct Connection: Identifiable {
    let id: Int
    let from_user: Int
    let to_user: Int
    let from_user_email: String
    let to_user_email: String
    let from_user_name: String
    let to_user_name: String
    let status: String

    func displayName(myEmail: String) -> String {
        let isRecipient = to_user_email.lowercased() == myEmail.lowercased()
        let name = isRecipient ? from_user_name : to_user_name
        let email = isRecipient ? from_user_email : to_user_email
        return name.trimmingCharacters(in: .whitespaces).isEmpty ? email : name
    }

    func userId(myEmail: String) -> Int {
        to_user_email.lowercased() == myEmail.lowercased() ? from_user : to_user
    }
}

// Decodable separado para suportar tanto from_user_name quanto from_user_first_name
extension Connection: Codable {
    enum CodingKeys: String, CodingKey {
        case id, from_user, to_user, from_user_email, to_user_email, status
        case from_user_name, to_user_name
        case from_user_first_name, from_user_last_name
        case to_user_first_name, to_user_last_name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(Int.self, forKey: .id)
        from_user     = try c.decode(Int.self, forKey: .from_user)
        to_user       = try c.decode(Int.self, forKey: .to_user)
        from_user_email = try c.decode(String.self, forKey: .from_user_email)
        to_user_email   = try c.decode(String.self, forKey: .to_user_email)
        status          = try c.decode(String.self, forKey: .status)

        // Suporta tanto "from_user_name" quanto "from_user_first_name + last_name"
        if let name = try? c.decode(String.self, forKey: .from_user_name), !name.isEmpty {
            from_user_name = name
        } else {
            let first = (try? c.decode(String.self, forKey: .from_user_first_name)) ?? ""
            let last  = (try? c.decode(String.self, forKey: .from_user_last_name)) ?? ""
            from_user_name = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        }

        if let name = try? c.decode(String.self, forKey: .to_user_name), !name.isEmpty {
            to_user_name = name
        } else {
            let first = (try? c.decode(String.self, forKey: .to_user_first_name)) ?? ""
            let last  = (try? c.decode(String.self, forKey: .to_user_last_name)) ?? ""
            to_user_name = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(from_user, forKey: .from_user)
        try c.encode(to_user, forKey: .to_user)
        try c.encode(from_user_email, forKey: .from_user_email)
        try c.encode(to_user_email, forKey: .to_user_email)
        try c.encode(status, forKey: .status)
        try c.encode(from_user_name, forKey: .from_user_name)
        try c.encode(to_user_name, forKey: .to_user_name)
    }
}

struct ConnectionListResponse: Decodable {
    let results: [Connection]?
    let count: Int?
}

struct SendConnectionRequest: Encodable {
    let to_user_email: String
}

// MARK: - FCM Device

struct FcmDeviceRequest: Encodable {
    let user: Int
    let device_token: String
    let platform: String
    let device_name: String
    let is_active: Bool
}

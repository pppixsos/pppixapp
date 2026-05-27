import Foundation

/// Equivalente ao RetrofitClient.kt + PPPIXApi.kt do Android.
/// Auto-refresh de token no 401, idêntico ao interceptor do OkHttp.
final class APIClient {

    static let shared = APIClient()
    private init() {}

    private let baseURL = "https://app.pppix.tech/api/v1/"
    private let session = URLSession.shared

    // MARK: - Auth

    func login(email: String, password: String) async throws -> LoginResponse {
        try await post("auth/login/", body: LoginRequest(email: email, password: password), auth: false)
    }

    func register(body: RegisterRequest) async throws {
        let _: EmptyResponse = try await post("users/", body: body, auth: false)
    }

    func getMe() async throws -> UserModel {
        try await get("users/me/")
    }

    // MARK: - Passwords

    func getPasswords() async throws -> [SavedPasswordsResponse] {
        let data = try await rawGet("passwords/")
        if let list = try? JSONDecoder().decode([SavedPasswordsResponse].self, from: data) {
            return list
        }
        if let paged = try? JSONDecoder().decode(SavedPasswordsResponse.self, from: data),
           let results = paged.results {
            return results
        }
        return []
    }

    func setPasswords(body: SetPasswordsRequest) async throws {
        let _: EmptyResponse = try await post("passwords/set_passwords/", body: body)
    }

    func verifyPassword(body: VerifyPasswordRequest) async throws -> VerifyPasswordResponse {
        try await post("passwords/verify/", body: body)
    }

    func updatePasswordSettings(id: Int, body: PasswordAttemptsRequest) async throws {
        let _: EmptyResponse = try await patch("passwords/\(id)/", body: body)
    }

    // MARK: - Vehicles

    func getVehicles() async throws -> [Vehicle] {
        let data = try await rawGet("vehicles/")
        if let list = try? JSONDecoder().decode([Vehicle].self, from: data) { return list }
        if let paged = try? JSONDecoder().decode(VehicleListResponse.self, from: data),
           let results = paged.results { return results }
        return []
    }

    func createVehicle(body: VehicleRequest) async throws -> Vehicle {
        try await post("vehicles/", body: body)
    }

    func updateVehicle(id: Int, body: VehicleRequest) async throws -> Vehicle {
        try await put("vehicles/\(id)/", body: body)
    }

    func deleteVehicle(id: Int) async throws {
        try await delete("vehicles/\(id)/")
    }

    func setActiveVehicle(id: Int) async throws -> Vehicle {
        try await post("vehicles/\(id)/set_active/", body: EmptyBody())
    }

    // MARK: - Alerts

    func getSentAlerts() async throws -> [Alert] {
        let r: AlertListResponse = try await get("alerts/sent/")
        return r.results ?? []
    }

    func getReceivedAlerts() async throws -> [Alert] {
        let r: AlertListResponse = try await get("alerts/received/")
        return r.results ?? []
    }

    func getAlert(id: Int) async throws -> Alert {
        try await get("alerts/\(id)/")
    }

    func sendAlert(body: SendAlertRequest) async throws -> Alert {
        try await post("alerts/send_alert/", body: body)
    }

    func patchAlertStatus(id: Int, status: String) async throws {
        let _: EmptyResponse = try await patch("alerts/\(id)/", body: ["status": status])
    }

    func markAlertRead(id: Int) async throws {
        let _: EmptyResponse = try await post("alerts/\(id)/mark_read/", body: EmptyBody())
    }

    // MARK: - Connections

    func getAcceptedConnections() async throws -> [Connection] {
        let data = try await rawGet("connections/accepted/")
        if let list = try? JSONDecoder().decode([Connection].self, from: data) { return list }
        if let paged = try? JSONDecoder().decode(ConnectionListResponse.self, from: data),
           let results = paged.results { return results }
        return []
    }

    func getPendingConnections() async throws -> [Connection] {
        let data = try await rawGet("connections/pending/")
        if let list = try? JSONDecoder().decode([Connection].self, from: data) { return list }
        if let paged = try? JSONDecoder().decode(ConnectionListResponse.self, from: data),
           let results = paged.results { return results }
        return []
    }

    func sendConnectionRequest(email: String) async throws {
        let _: EmptyResponse = try await post("connections/", body: SendConnectionRequest(to_user_email: email))
    }

    func acceptConnection(id: Int) async throws {
        let _: EmptyResponse = try await post("connections/\(id)/accept/", body: EmptyBody())
    }

    func deleteConnection(id: Int) async throws {
        try await delete("connections/\(id)/")
    }

    // MARK: - FCM Device

    func registerFcmDevice(token: String, platform: String) async throws {
        let userId = SessionManager.shared.userId
        let body = FcmDeviceRequest(
            user: userId,
            device_token: token,
            platform: platform,
            device_name: UIDeviceName(),
            is_active: true
        )
        let _: EmptyResponse = try await post("fcm-devices/", body: body)
    }

    private func UIDeviceName() -> String {
        return "iPhone"
    }

    // MARK: - HTTP Primitives

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await rawGet(path)
        return try decode(T.self, from: data)
    }

    private func rawGet(_ path: String) async throws -> Data {
        var request = try makeRequest(path: path, method: "GET", body: nil as EmptyBody?)
        return try await executeWithRefresh(&request)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B, auth: Bool = true) async throws -> T {
        var request = try makeRequest(path: path, method: "POST", body: body, auth: auth)
        let data = try await executeWithRefresh(&request, auth: auth)
        return try decode(T.self, from: data)
    }

    private func put<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var request = try makeRequest(path: path, method: "PUT", body: body)
        let data = try await executeWithRefresh(&request)
        return try decode(T.self, from: data)
    }

    private func patch<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var request = try makeRequest(path: path, method: "PATCH", body: body)
        let data = try await executeWithRefresh(&request)
        return try decode(T.self, from: data)
    }

    private func delete(_ path: String) async throws {
        var request = try makeRequest(path: path, method: "DELETE", body: nil as EmptyBody?)
        _ = try await executeWithRefresh(&request)
    }

    // MARK: - Request builder

    private func makeRequest<B: Encodable>(
        path: String,
        method: String,
        body: B?,
        auth: Bool = true
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if auth, let token = SessionManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body, !(body is EmptyBody) {
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    // MARK: - Execute with auto token refresh

    private func executeWithRefresh(_ request: inout URLRequest, auth: Bool = true) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 401 && auth {
            guard let newToken = try? await refreshAccessToken() else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResp) = try await session.data(for: request)
            guard let retryHttp = retryResp as? HTTPURLResponse else { throw APIError.invalidResponse }
            if retryHttp.statusCode == 401 { throw APIError.unauthorized }
            try checkStatus(retryHttp.statusCode, data: retryData)
            return retryData
        }

        try checkStatus(http.statusCode, data: data)
        return data
    }

    private func refreshAccessToken() async throws -> String {
        guard let refresh = SessionManager.shared.refreshToken else { throw APIError.unauthorized }
        let body = RefreshRequest(refresh: refresh)
        let request = try makeRequest(path: "auth/refresh/", method: "POST", body: body, auth: false)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw APIError.unauthorized }
        let refreshed = try JSONDecoder().decode(RefreshResponse.self, from: data)
        SessionManager.shared.saveTokens(access: refreshed.access, refresh: refresh)
        return refreshed.access
    }

    // MARK: - Helpers

    private func checkStatus(_ code: Int, data: Data) throws {
        switch code {
        case 200...299: return
        case 401: throw APIError.unauthorized
        case 400:
            let msg = parseErrorMessage(data) ?? "Dados inválidos."
            throw APIError.badRequest(msg)
        case 404: throw APIError.notFound
        case 500...: throw APIError.serverError
        default:
            let msg = parseErrorMessage(data) ?? "Erro \(code)"
            throw APIError.unknown(msg)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Parseia erros da API Django que podem vir em vários formatos:
    /// {"detail": "..."}, {"message": "..."}, {"field": ["erro"]}, {"non_field_errors": ["..."]}
    private func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Formato simples
        if let detail = json["detail"] as? String { return detail }
        if let msg = json["message"] as? String { return msg }
        if let error = json["error"] as? String { return error }

        // non_field_errors: ["mensagem"]
        if let nonField = json["non_field_errors"] as? [String], let first = nonField.first {
            return first
        }

        // Erros de campo: {"to_user_email": ["Usuário não encontrado"]}
        // Pega o primeiro erro de qualquer campo
        for (key, value) in json {
            if let arr = value as? [String], let first = arr.first {
                // Traduz nomes de campo técnicos para português amigável
                let fieldName = friendlyFieldName(key)
                return "\(fieldName): \(first)"
            }
            if let str = value as? String {
                let fieldName = friendlyFieldName(key)
                return "\(fieldName): \(str)"
            }
        }

        return nil
    }

    private func friendlyFieldName(_ key: String) -> String {
        switch key {
        case "to_user_email": return "Email"
        case "email": return "Email"
        case "password": return "Senha"
        case "cpf": return "CPF"
        case "phone": return "Telefone"
        case "birth_date": return "Data de nascimento"
        case "cep": return "CEP"
        case "username": return "Nome de usuário"
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case badRequest(String)
    case notFound
    case serverError
    case decodingError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:           return "Sessão expirada. Faça login novamente."
        case .badRequest(let msg):    return msg
        case .notFound:               return "Usuário não encontrado. Verifique o email."
        case .serverError:            return "Erro no servidor. Tente novamente."
        case .decodingError(let msg): return "Erro ao processar resposta: \(msg)"
        case .unknown(let msg):       return msg
        default:                      return "Erro de conexão."
        }
    }
}

// MARK: - Helpers

private struct EmptyBody: Encodable {}
private struct EmptyResponse: Decodable {}

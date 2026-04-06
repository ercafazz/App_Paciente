//
//  HealthKitManager.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/1/26.
//
//  Refactor v5.2 — Lote dedicado a FC + bootstrap 2h.
//
//  Cambios vs v5.1:
//  1. Bootstrap inicial usa ventana de 2h (no 24h) para datos clínicamente recientes.
//  2. Lote ahora es solo FC — SpO2/FR se envían como lecturas puntuales.
//  3. Intervalo del lote se calcula solo con muestras de FC.
//  4. POST a lotes_signos_vitales ya no incluye campos spo2_*/fr_*.
//
//  Mantenido de v5.1:
//  - MuestraLigera, autoreleasepool, límite 5000.
//  - EnvioLigero con URLSession directo + token refresh.
//  - BufferLocal como fallback.
//  - SpO2/FR como lecturas puntuales vía EnvioLigero.
//

import Foundation
import HealthKit
import UIKit

// MARK: - ════════════════════════════════════════════════
// MARK:   Notificación para Dashboard
// MARK: - ════════════════════════════════════════════════

extension Notification.Name {
    static let tueriLoteEnviado = Notification.Name("tueri.loteEnviado")
}

// MARK: - ════════════════════════════════════════════════
// MARK:   MuestraLigera — Representación minimal en RAM
// MARK: - ════════════════════════════════════════════════

/// Representación ultra-ligera de una muestra de HealthKit.
/// Solo contiene lo que necesitamos: el valor numérico y las fechas.
///
/// **Tamaño**: 24 bytes (Double + Date + Date)
/// vs `HKQuantitySample`: ~1-2KB (metadata, device, source, quantity, etc.)
///
/// Se extrae DENTRO del callback de la query y el HKQuantitySample
/// se libera inmediatamente después por ARC.
private struct MuestraLigera: Sendable {
    let valor: Double
    let inicio: Date
    let fin: Date
}

// MARK: - ════════════════════════════════════════════════
// MARK:   AnchorStore — Persistencia de Anchors
// MARK: - ════════════════════════════════════════════════

private enum AnchorStore {

    private static let prefix = "tueri.anchor."

    private static func key(for type: HKSampleType) -> String {
        "\(prefix)\(type.identifier)"
    }

    static func load(for type: HKSampleType) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: key(for: type)) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    static func save(_ anchor: HKQueryAnchor, for type: HKSampleType) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: anchor, requiringSecureCoding: true
        ) else {
            print("[AnchorStore] ❌ Error serializando anchor para \(type.identifier)")
            return
        }
        UserDefaults.standard.set(data, forKey: key(for: type))
    }

    static func clear(types: Set<HKSampleType>) {
        for type in types {
            UserDefaults.standard.removeObject(forKey: key(for: type))
        }
    }
}

// MARK: - ════════════════════════════════════════════════
// MARK:   ProcesadorLotes — Actor de serialización
// MARK: - ════════════════════════════════════════════════

private actor ProcesadorLotes {

    private var currentTask: Task<Void, Error>?

    func ejecutarSiDisponible(
        _ trabajo: @escaping @Sendable () async throws -> Void
    ) async -> Bool {
        // Si ya hay procesamiento en curso, retornar INMEDIATAMENTE.
        // NO esperar (await existing.value) — eso mantiene la Task + bgTask
        // vivos en memoria. En background (~50MB), 3 Tasks suspendidas = OOM.
        guard currentTask == nil else { return false }

        let task = Task<Void, Error> { try await trabajo() }
        currentTask = task
        defer { currentTask = nil }

        do {
            try await task.value
        } catch {
            print("[ProcesadorLotes] ⚠️ Error: \(error.localizedDescription)")
        }
        return true
    }
}

// MARK: - ════════════════════════════════════════════════
// MARK:   ResultadoAnchoredQuery — Resultado ligero
// MARK: - ════════════════════════════════════════════════

/// Resultado de una anchored query. Contiene solo `MuestraLigera`,
/// NO `HKQuantitySample`. Los objetos pesados de HealthKit ya fueron
/// liberados dentro del callback de la query.
private struct ResultadoAnchoredQuery {
    let tipo: HKQuantityType
    let muestras: [MuestraLigera]  // ~24 bytes c/u (no ~1.5KB)
    let nuevoAnchor: HKQueryAnchor
    let conteoHK: Int              // Cuántas muestras retornó HK (antes de filtrar)
}

// MARK: - ════════════════════════════════════════════════
// MARK:   BufferLocal — Lotes pendientes en disco
// MARK: - ════════════════════════════════════════════════

/// Guarda lotes como archivos JSON individuales en disco.
/// En background, escribir un archivo de ~1KB no consume RAM significativa.
/// En foreground, se leen y envían a Supabase.
private enum BufferLocal {

    private static var directorio: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tueri_buffer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Guarda un lote como archivo JSON. Nombre = timestamp para ordenar.
    static func guardar(_ lote: LoteSignosVitales) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(lote) else {
            print("[Buffer] ❌ Error codificando lote")
            return
        }
        let archivo = directorio.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000)).json")
        do {
            try data.write(to: archivo, options: .atomic)
            print("[Buffer] 💾 Lote guardado en disco (\(data.count) bytes)")
        } catch {
            print("[Buffer] ❌ Error escribiendo: \(error.localizedDescription)")
        }
    }

    /// Lee todos los lotes pendientes, ordenados por antigüedad.
    static func leerPendientes() -> [(url: URL, lote: LoteSignosVitales)] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let archivos = try? FileManager.default.contentsOfDirectory(
            at: directorio,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return archivos
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let lote = try? decoder.decode(LoteSignosVitales.self, from: data)
                else { return nil }
                return (url, lote)
            }
    }

    /// Elimina un archivo de lote después de enviarlo exitosamente.
    static func eliminar(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Cuántos lotes hay pendientes.
    static func conteo() -> Int {
        (try? FileManager.default.contentsOfDirectory(
            at: directorio,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }.count) ?? 0
    }
}

// MARK: - ════════════════════════════════════════════════
// MARK:   EnvioLigero — HTTP POST directo (sin Supabase SDK)
// MARK: - ════════════════════════════════════════════════

/// Envía un lote directamente a la REST API de Supabase usando URLSession.
/// NO carga el Supabase SDK (~swift-crypto, swift-http-types, Auth, Realtime, etc.)
/// Solo usa Foundation.URLSession — mínima memoria en background.
///
/// **Autenticación**: Usa el access_token JWT del usuario (guardado por TokenStore).
/// Si el token expiró (HTTP 401), intenta refrescarlo con el refresh_token
/// via POST ligero a /auth/v1/token. Si el refresh falla, retorna false
/// y el lote se guarda en BufferLocal para reintento en foreground.
private enum EnvioLigero {

    private static let baseURL = "https://aqopgqcpdmbmgkxmgvoy.supabase.co"
    private static let apiKey  = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFxb3BncWNwZG1ibWdreG1ndm95Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4MjcxNDIsImV4cCI6MjA5MDQwMzE0Mn0.O3Lt-rDU_658DvJ5zR6rxu6pg-j7HNsbLZ8gOODtZcQ"

    private static let isoFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    // MARK: Token Store (UserDefaults — persistente entre lanzamientos)

    private static let accessTokenKey  = "tueri.auth.accessToken"
    private static let refreshTokenKey = "tueri.auth.refreshToken"

    /// Guarda los tokens de sesión del usuario. Llamar después de login/refresh.
    static func guardarTokens(access: String, refresh: String) {
        UserDefaults.standard.set(access, forKey: accessTokenKey)
        UserDefaults.standard.set(refresh, forKey: refreshTokenKey)
        print("[EnvioLigero] 🔑 Tokens guardados.")
    }

    /// Limpia los tokens (logout).
    static func limpiarTokens() {
        UserDefaults.standard.removeObject(forKey: accessTokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
        print("[EnvioLigero] 🔑 Tokens eliminados.")
    }

    private static var accessToken: String? {
        UserDefaults.standard.string(forKey: accessTokenKey)
    }

    private static var refreshToken: String? {
        UserDefaults.standard.string(forKey: refreshTokenKey)
    }

    // MARK: Refresh token (ligero, sin Supabase SDK)

    /// Refresca el access_token usando el refresh_token via POST directo.
    /// Endpoint: POST /auth/v1/token?grant_type=refresh_token
    private static func refrescarToken() async -> Bool {
        guard let refresh = refreshToken,
              let url = URL(string: "\(baseURL)/auth/v1/token?grant_type=refresh_token")
        else {
            print("[EnvioLigero] ❌ No hay refresh_token para refrescar.")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 10

        let body: [String: String] = ["refresh_token": refresh]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                print("[EnvioLigero] ❌ Refresh falló (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
                return false
            }

            // Extraer nuevos tokens del JSON de respuesta
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccess = json["access_token"] as? String,
                  let newRefresh = json["refresh_token"] as? String
            else {
                print("[EnvioLigero] ❌ Refresh: respuesta inválida")
                return false
            }

            guardarTokens(access: newAccess, refresh: newRefresh)
            print("[EnvioLigero] 🔄 Token refrescado exitosamente.")
            return true
        } catch {
            print("[EnvioLigero] ❌ Refresh error de red: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Envío de lote

    /// Envía un lote via HTTP POST. Retorna true si fue exitoso (2xx).
    /// Si recibe 401, intenta refrescar el token y reintentar UNA vez.
    static func enviar(_ lote: LoteSignosVitales) async -> Bool {
        // Primer intento
        if let resultado = await ejecutarPost(lote) {
            return resultado
        }

        // Si fue 401 → intentar refresh + reintento
        print("[EnvioLigero] 🔄 Intentando refresh de token...")
        guard await refrescarToken() else { return false }

        // Reintento con token nuevo
        return await ejecutarPost(lote) ?? false
    }

    // MARK: Envío de lectura puntual (SpO2 / FR)

    /// Inserta una lectura puntual en `lecturas_puntuales`.
    /// - Parameters:
    ///   - idPaciente: UUID del paciente
    ///   - tipo: "spo2" o "fr"
    ///   - valor: valor numérico de la lectura
    ///   - fecha: fecha de la lectura (endDate de la muestra HK)
    static func enviarLecturaPuntual(
        idPaciente: UUID,
        tipo: String,
        valor: Double,
        fecha: Date
    ) async -> Bool {
        // Primer intento
        if let resultado = await ejecutarPostPuntual(
            idPaciente: idPaciente, tipo: tipo, valor: valor, fecha: fecha
        ) {
            return resultado
        }

        // 401 → refresh + reintento
        guard await refrescarToken() else { return false }
        return await ejecutarPostPuntual(
            idPaciente: idPaciente, tipo: tipo, valor: valor, fecha: fecha
        ) ?? false
    }

    private static func ejecutarPostPuntual(
        idPaciente: UUID,
        tipo: String,
        valor: Double,
        fecha: Date
    ) async -> Bool? {
        guard let token = accessToken else { return false }
        guard let url = URL(string: "\(baseURL)/rest/v1/lecturas_puntuales") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.timeoutInterval = 15

        let dict: [String: Any] = [
            "id_paciente": idPaciente.uuidString,
            "tipo_signo": tipo,
            "valor": valor,
            "fecha_lectura": isoFormatter.string(from: fecha),
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: dict) else { return false }
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    print("[EnvioLigero] ✅ Lectura puntual \(tipo) enviada (HTTP \(http.statusCode))")
                    return true
                } else if http.statusCode == 401 {
                    return nil
                } else {
                    print("[EnvioLigero] ❌ Lectura puntual \(tipo) HTTP \(http.statusCode)")
                    return false
                }
            }
            return false
        } catch {
            print("[EnvioLigero] ❌ Lectura puntual \(tipo) error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Envío de lote

    /// Ejecuta el POST. Retorna: true = éxito, false = error no-auth, nil = 401 (token expirado).
    private static func ejecutarPost(_ lote: LoteSignosVitales) async -> Bool? {
        guard let token = accessToken else {
            print("[EnvioLigero] ❌ No hay access_token. El usuario no ha iniciado sesión.")
            return false
        }

        guard let url = URL(string: "\(baseURL)/rest/v1/lotes_signos_vitales") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.timeoutInterval = 15

        // Construir JSON manual — solo FC + intervalo (Supabase usa DEFAULT para campos omitidos)
        var dict: [String: Any] = [
            "id_paciente": lote.idPaciente.uuidString,
            "inicio_intervalo": isoFormatter.string(from: lote.inicioIntervalo),
            "fin_intervalo": isoFormatter.string(from: lote.finIntervalo),
        ]

        // Solo FC — SpO2/FR se envían como lecturas puntuales
        if let v = lote.fcPromedio   { dict["fc_promedio"]   = v }
        if let v = lote.fcMaxima     { dict["fc_maxima"]     = v }
        if let v = lote.fcMinima     { dict["fc_minima"]     = v }
        if let v = lote.fcLecturas   { dict["fc_lecturas"]   = v }

        guard let body = try? JSONSerialization.data(withJSONObject: dict) else {
            print("[EnvioLigero] ❌ Error codificando lote")
            return false
        }
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    print("[EnvioLigero] ✅ POST exitoso (HTTP \(http.statusCode))")
                    return true
                } else if http.statusCode == 401 {
                    print("[EnvioLigero] ⚠️ HTTP 401 — token expirado.")
                    return nil  // Señal para intentar refresh
                } else {
                    print("[EnvioLigero] ❌ HTTP \(http.statusCode)")
                    return false
                }
            }
            return false
        } catch {
            print("[EnvioLigero] ❌ Error de red: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - ════════════════════════════════════════════════
// MARK:   HealthKitManager — Gestor principal
// MARK: - ════════════════════════════════════════════════

final class HealthKitManager: @unchecked Sendable {

    // MARK: Singleton

    static let shared = HealthKitManager()

    // MARK: Constantes

    /// Ventana de batching: mínimo entre envíos a Supabase.
    /// ⚠️ TEMPORAL: 5 min para pruebas. Producción: 1800 (30 min).
    private static let VENTANA_BATCHING: TimeInterval = 300

    /// Ventana máxima de antigüedad para muestras en modo incremental.
    /// SIEMPRE se aplica como predicate en las anchored queries para filtrar
    /// datos prehistóricos (ej. sincronizaciones tardías de iCloud desde hace un año).
    /// 24 horas es suficiente para no perder datos legítimos.
    private static let VENTANA_PREDICADO: TimeInterval = 86400

    /// Ventana para el bootstrap inicial (anchor == nil).
    /// Solo trae las últimas 2 horas para que el primer lote sea clínicamente
    /// reciente y el intervalo de FC no muestre un rango de 24h.
    private static let VENTANA_BOOTSTRAP: TimeInterval = 7200

    /// Límite de muestras por tipo por query. Safety net para evitar
    /// que una query descontrolada cargue todo el histórico en RAM.
    /// 5000 muestras × 24 bytes = 120KB por tipo = ~360KB total.
    private static let LIMITE_MUESTRAS_POR_QUERY = 5000

    /// Key para timestamp del último envío exitoso.
    private static let lastSendKey = "tueri.lastSendTimestamp"

    // MARK: Propiedades privadas

    private let healthStore = HKHealthStore()
    private let procesador = ProcesadorLotes()

    // MARK: Tipos de HealthKit

    private let tipoFC  = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let tipoSpO2 = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
    private let tipoFR  = HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!

    private var todosLosTipos: Set<HKQuantityType> { [tipoFC, tipoSpO2, tipoFR] }

    // MARK: Identidad del paciente (persistida)

    private static let idPacienteKey = "HealthKitManager.idPaciente"

    var idPaciente: UUID? {
        get {
            UserDefaults.standard.string(forKey: Self.idPacienteKey).flatMap(UUID.init)
        }
        set {
            if let id = newValue {
                UserDefaults.standard.set(id.uuidString, forKey: Self.idPacienteKey)
                print("[HKM] 🪪 idPaciente = \(id.uuidString.prefix(8))...")
            } else {
                UserDefaults.standard.removeObject(forKey: Self.idPacienteKey)
                print("[HKM] 🪪 idPaciente borrado")
            }
        }
    }

    // MARK: Control de observadores

    private var observadoresConfigurados = false
    private var queriesActivas: [HKObserverQuery] = []

    // MARK: Inicialización

    private init() {
        print("[HKM] ══════════════════════════════════════")
        print("[HKM] 🏥 Tuēri HealthKitManager v5.1")
        print("[HKM] ══════════════════════════════════════")
    }

    // MARK: Helpers

    private static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private func ts() -> String { Self.logFormatter.string(from: Date()) }

    private func nombre(_ tipo: HKQuantityType) -> String {
        switch tipo {
        case tipoFC:  return "FC"
        case tipoSpO2: return "SpO2"
        case tipoFR:  return "FR"
        default:       return tipo.identifier
        }
    }

    /// Retorna la unidad HK para un tipo dado.
    /// Se usa para extraer el Double en el callback de la query.
    private func unidad(para tipo: HKQuantityType) -> HKUnit {
        switch tipo {
        case tipoFC:  return HKUnit.count().unitDivided(by: .minute())
        case tipoSpO2: return HKUnit.percent()
        case tipoFR:  return HKUnit.count().unitDivided(by: .minute())
        default:       return HKUnit.count()
        }
    }

    // MARK: - ════════════════════════════════════════════════
    // MARK:   API PÚBLICA
    // MARK: - ════════════════════════════════════════════════

    func registrarObservadores() {
        print("[HKM] 📋 registrarObservadores() — \(ts())")
        configurarObservadores()
        habilitarBackgroundDelivery()
    }

    func configurarSistemaHealthKitCompleto() async {
        print("[HKM] 🔧 configurarSistemaHealthKitCompleto() — \(ts())")

        guard HKHealthStore.isHealthDataAvailable() else {
            print("[HKM] ❌ HealthKit no disponible.")
            return
        }

        do {
            try await healthStore.requestAuthorization(
                toShare: [],
                read: Set<HKSampleType>(todosLosTipos)
            )
            print("[HKM] ✅ Permisos verificados.")
        } catch {
            print("[HKM] ⚠️ Error permisos: \(error.localizedDescription). Continuando...")
        }

        registrarObservadores()
    }

    func forzarSincronizacion() async {
        print("[HKM] ⚡ forzarSincronizacion() — \(ts())")
        let _ = await procesador.ejecutarSiDisponible { [weak self] in
            await self?.procesarConAnchors(forzar: true)
        }
    }

    func sincronizarSiNecesario() async {
        let lastSend = UserDefaults.standard.object(forKey: Self.lastSendKey) as? Date ?? .distantPast
        let elapsed = Date().timeIntervalSince(lastSend)

        guard elapsed >= Self.VENTANA_BATCHING else {
            print("[HKM] ✅ Datos frescos (\(Int(elapsed))s). Sin acción.")
            return
        }

        print("[HKM] 📡 Datos obsoletos (\(Int(elapsed))s). Sincronizando...")
        await forzarSincronizacion()
    }

    func solicitarPermisos() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitManagerError.healthKitNoDisponible
        }
        try await healthStore.requestAuthorization(
            toShare: [],
            read: Set<HKSampleType>(todosLosTipos)
        )
        print("[HKM] ✅ Permisos solicitados.")
    }

    /// Guarda los tokens JWT de la sesión de Supabase para envío ligero en background.
    /// Llamar después de login, registro, o al restaurar sesión existente.
    func guardarTokensSesion(access: String, refresh: String) {
        EnvioLigero.guardarTokens(access: access, refresh: refresh)
    }

    func limpiarEstado() {
        idPaciente = nil
        AnchorStore.clear(types: Set<HKSampleType>(todosLosTipos))
        UserDefaults.standard.removeObject(forKey: Self.lastSendKey)
        EnvioLigero.limpiarTokens()
        print("[HKM] 🧹 Estado limpiado (logout).")
    }

    /// Envía todos los lotes almacenados en el buffer local a Supabase.
    /// Se llama desde foreground (scenePhase .active) para reintentar envíos fallidos.
    func flushBuffer() async {
        let pendientes = BufferLocal.leerPendientes()
        guard !pendientes.isEmpty else { return }

        print("[HKM] 📤 FLUSH: \(pendientes.count) lote(s) pendiente(s)")

        var enviados = 0
        for (url, lote) in pendientes {
            let ok = await EnvioLigero.enviar(lote)
            if ok {
                BufferLocal.eliminar(url)
                enviados += 1
            } else {
                // Parar al primer error — no bombardear si hay problema de red.
                break
            }
        }

        if enviados > 0 {
            print("[HKM] 📤 FLUSH COMPLETO: \(enviados)/\(pendientes.count) lotes enviados.")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .tueriLoteEnviado, object: nil)
            }
        }
    }

    // MARK: - ════════════════════════════════════════════════
    // MARK:   OBSERVERS
    // MARK: - ════════════════════════════════════════════════

    private func configurarObservadores() {
        guard !observadoresConfigurados else {
            print("[HKM] ⚠️ Observers ya configurados.")
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            print("[HKM] ⚠️ HealthKit no disponible.")
            return
        }

        for tipo in todosLosTipos {
            let tag = nombre(tipo)

            let query = HKObserverQuery(
                sampleType: tipo,
                predicate: nil
            ) { [weak self] _, completionHandler, error in
                guard let self else {
                    completionHandler()
                    return
                }

                if let error {
                    print("[HKM] ❌ Observer error [\(tag)]: \(error.localizedDescription)")
                    completionHandler()
                    return
                }

                print("[HKM] 🔔 OBSERVER: \(tag) — \(self.ts())")

                // beginBackgroundTask SINCRÓNICO — antes del Task.
                // iOS necesita esto ANTES de cualquier await para no suspender la app.
                let bgTaskID = UIApplication.shared.beginBackgroundTask(
                    withName: "tueri.sync.\(tipo.identifier)"
                ) {
                    print("[HKM] ⏰ bgTask EXPIRADO: \(tag)")
                }

                Task { [weak self] in
                    defer {
                        completionHandler()
                        if bgTaskID != .invalid {
                            UIApplication.shared.endBackgroundTask(bgTaskID)
                        }
                    }

                    guard let self else { return }

                    // ejecutarSiDisponible retorna false INMEDIATAMENTE si hay
                    // procesamiento en curso — no espera, no retiene memoria.
                    let ejecutado = await self.procesador.ejecutarSiDisponible {
                        [weak self] in
                        await self?.procesarConAnchors(forzar: false)
                    }

                    if !ejecutado {
                        print("[HKM] ↩️ \(tag) descartado (serializado).")
                    }
                }
            }

            healthStore.execute(query)
            queriesActivas.append(query)
            print("[HKM] 👂 Observer: \(tag)")
        }

        observadoresConfigurados = true
        print("[HKM] ✅ \(todosLosTipos.count) observers activos.")
    }

    // MARK: - ════════════════════════════════════════════════
    // MARK:   BACKGROUND DELIVERY
    // MARK: - ════════════════════════════════════════════════

    private func habilitarBackgroundDelivery() {
        for tipo in todosLosTipos {
            let tag = nombre(tipo)
            healthStore.enableBackgroundDelivery(
                for: tipo,
                frequency: .immediate
            ) { ok, error in
                if ok {
                    print("[HKM] ✅ BGDelivery ON: \(tag)")
                } else if let error {
                    print("[HKM] ❌ BGDelivery FAIL [\(tag)]: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - ════════════════════════════════════════════════
    // MARK:   PROCESAMIENTO PRINCIPAL
    // MARK: - ════════════════════════════════════════════════

    private func procesarConAnchors(forzar: Bool) async {
        guard let idPaciente else {
            print("[HKM] ❌ Sin idPaciente.")
            return
        }

        print("[HKM] 🔄 PROCESAMIENTO — \(ts())")

        // ── FETCH: SECUENCIAL para minimizar memoria ──
        // Cada query carga HKQuantitySample en el callback, los convierte
        // a MuestraLigera y los libera via autoreleasepool ANTES de la siguiente.
        // Secuencial = pico de ~120KB por tipo. Paralelo = ~360KB simultáneos.
        // En background (~50MB budget), esta diferencia es crítica.
        //
        // NOTA: El batching ya NO bloquea el fetch. Se evalúa por separado
        // solo para el flujo del lote FC. Las lecturas puntuales SpO2/FR
        // se envían siempre que haya muestras nuevas.
        let fc   = await consultarConAnchor(tipo: tipoFC)
        let spo2 = await consultarConAnchor(tipo: tipoSpO2)
        let fr   = await consultarConAnchor(tipo: tipoFR)

        let mFC   = fc?.muestras   ?? []
        let mSpO2 = spo2?.muestras ?? []
        let mFR   = fr?.muestras   ?? []
        let total = mFC.count + mSpO2.count + mFR.count

        guard total > 0 else {
            print("[HKM] 📭 Sin muestras nuevas.")
            guardarAnchors(fc: fc, spo2: spo2, fr: fr)
            return
        }

        print("[HKM] 📦 FC:\(mFC.count) SpO2:\(mSpO2.count) FR:\(mFR.count) — ~\(total * 24)B RAM")

        // Rastrear si algo se envió para decidir si notificar al dashboard.
        var algoEnviado = false

        // Rastrear si el anchor de FC debe avanzarse. Si el batching difiere
        // el lote, NO avanzamos el anchor FC — esas muestras se re-leen en
        // el próximo tick para formar parte del lote cuando venza la ventana.
        var avanzarAnchorFC = false

        // ═══════════════════════════════════════════════════
        // FLUJO 1: LOTE FC — sujeto a batching
        // ═══════════════════════════════════════════════════
        if !mFC.isEmpty {
            // El batching aplica SOLO al lote FC, NO a las lecturas puntuales.
            let lastSend = UserDefaults.standard.object(
                forKey: Self.lastSendKey
            ) as? Date ?? .distantPast
            let elapsed = Date().timeIntervalSince(lastSend)
            let batchingVencido = forzar || elapsed >= Self.VENTANA_BATCHING

            if batchingVencido {
                let estadFC = calcularEstadisticas(de: mFC)
                let inicio  = mFC.map(\.inicio).min() ?? Date()
                let fin     = mFC.map(\.fin).max()    ?? Date()

                let lote = LoteSignosVitales(
                    id: nil,
                    idPaciente: idPaciente,
                    inicioIntervalo: inicio,
                    finIntervalo: fin,
                    fcPromedio:   estadFC.promedio,
                    fcMaxima:     estadFC.maximo,
                    fcMinima:     estadFC.minimo,
                    fcLecturas:   estadFC.conteo,
                    creadoEn: nil
                )

                let enviado = await EnvioLigero.enviar(lote)
                if enviado {
                    print("[HKM] ✅ LOTE FC ENVIADO — \(mFC.count) muestras — \(ts())")
                    algoEnviado = true
                } else {
                    BufferLocal.guardar(lote)
                    print("[HKM] ⚠️ LOTE FC BUFFERED — \(mFC.count) muestras — pendientes: \(BufferLocal.conteo())")
                }

                // Lote procesado (enviado o buffered) → avanzar anchor FC
                // y reiniciar ventana de batching.
                avanzarAnchorFC = true
                UserDefaults.standard.set(Date(), forKey: Self.lastSendKey)
            } else {
                let restante = Int(Self.VENTANA_BATCHING - elapsed)
                print("[HKM] ⏳ BATCHING FC: faltan \(restante)s — lote diferido, puntuales continúan.")
                // avanzarAnchorFC queda en false → las muestras se re-leerán
                // en el próximo tick cuando la ventana haya vencido.
            }
        } else {
            print("[HKM] ℹ️ Sin FC en este ciclo — no se crea lote.")
        }

        // ═══════════════════════════════════════════════════
        // FLUJO 2: LECTURAS PUNTUALES — SIEMPRE (no sujetas a batching)
        // ═══════════════════════════════════════════════════
        if let ultimaSpO2 = mSpO2.max(by: { $0.fin < $1.fin }) {
            // HealthKit devuelve SpO2 como fracción (0.0–1.0) → ×100 para porcentaje
            let ok = await EnvioLigero.enviarLecturaPuntual(
                idPaciente: idPaciente, tipo: "spo2",
                valor: ultimaSpO2.valor * 100, fecha: ultimaSpO2.fin
            )
            if ok { algoEnviado = true }
            else  { print("[HKM] ⚠️ Lectura puntual SpO2 no enviada.") }
        }

        if let ultimaFR = mFR.max(by: { $0.fin < $1.fin }) {
            let ok = await EnvioLigero.enviarLecturaPuntual(
                idPaciente: idPaciente, tipo: "fr",
                valor: ultimaFR.valor, fecha: ultimaFR.fin
            )
            if ok { algoEnviado = true }
            else  { print("[HKM] ⚠️ Lectura puntual FR no enviada.") }
        }

        // ═══════════════════════════════════════════════════
        // CIERRE: anchors, notificación
        // ═══════════════════════════════════════════════════
        // SpO2/FR: siempre avanzar el anchor (las lecturas puntuales son
        // snapshots "best-effort" — solo publicamos la más reciente).
        if let spo2 { AnchorStore.save(spo2.nuevoAnchor, for: spo2.tipo) }
        if let fr   { AnchorStore.save(fr.nuevoAnchor,   for: fr.tipo) }
        // FC: avanzar anchor SOLO si el lote se procesó. Si el batching
        // lo difirió, preservamos el anchor anterior para re-leer esas
        // muestras en el próximo tick.
        if avanzarAnchorFC, let fc { AnchorStore.save(fc.nuevoAnchor, for: fc.tipo) }

        if algoEnviado {
            DispatchQueue.main.async {
                guard UIApplication.shared.applicationState == .active else {
                    print("[HKM] 📭 Datos enviados en background — dashboard se actualizará al abrir.")
                    return
                }
                NotificationCenter.default.post(name: .tueriLoteEnviado, object: nil)
            }
        }
    }

    // MARK: - ════════════════════════════════════════════════
    // MARK:   ANCHORED QUERIES — Extracción ligera
    // MARK: - ════════════════════════════════════════════════

    /// Ejecuta `HKAnchoredObjectQuery` y extrae valores DENTRO del callback.
    ///
    /// **Memoria**: Los `HKQuantitySample` se convierten a `MuestraLigera` (24 bytes)
    /// dentro de un `autoreleasepool` en el callback. Los objetos pesados de HK
    /// se liberan al salir del pool, ANTES de que el resultado salga del callback.
    ///
    /// **Límite**: Máximo `LIMITE_MUESTRAS_POR_QUERY` muestras por ejecución.
    /// Si hay más, el anchor avanza hasta donde se leyó y el resto se captura
    /// en la próxima ejecución.
    private func consultarConAnchor(tipo: HKQuantityType) async -> ResultadoAnchoredQuery? {
        let tag = nombre(tipo)
        let anchorGuardado = AnchorStore.load(for: tipo)
        let esBootstrap = anchorGuardado == nil
        let unidadTipo = unidad(para: tipo)

        // Bootstrap: ventana corta (2h) para que el primer lote sea clínicamente reciente.
        // Incremental: ventana amplia (24h) como filtro de seguridad contra datos prehistóricos.
        let ventana = esBootstrap ? Self.VENTANA_BOOTSTRAP : Self.VENTANA_PREDICADO
        let desde = Date().addingTimeInterval(-ventana)
        let predicate = HKQuery.predicateForSamples(withStart: desde, end: nil, options: [])

        if esBootstrap {
            print("[HKM] 🆕 BOOTSTRAP [\(tag)]: primera sync, ventana \(Int(ventana/3600))h")
        } else {
            print("[HKM] 🔄 INCREMENTAL [\(tag)]: anchor + predicado \(Int(ventana/3600))h")
        }

        return await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: tipo,
                predicate: predicate,
                anchor: anchorGuardado,
                limit: Self.LIMITE_MUESTRAS_POR_QUERY  // ← Safety net: máx 5000
            ) { _, addedSamples, _, newAnchor, error in

                if let error {
                    print("[HKM] ❌ AnchoredQuery [\(tag)]: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let newAnchor else {
                    print("[HKM] ⚠️ AnchoredQuery [\(tag)]: anchor nulo")
                    continuation.resume(returning: nil)
                    return
                }

                // ╔═══════════════════════════════════════════════════╗
                // ║  EXTRACCIÓN LIGERA + AUTORELEASEPOOL              ║
                // ║                                                    ║
                // ║  Extraemos Double + Date aquí mismo.               ║
                // ║  Al salir del pool, ARC libera los HKQuantitySample║
                // ║  ANTES de que el resultado se pase al caller.      ║
                // ║                                                    ║
                // ║  Memoria: [HKQuantitySample] ~1.5KB c/u → 0 bytes ║
                // ║           [MuestraLigera]    ~24 bytes c/u         ║
                // ╚═══════════════════════════════════════════════════╝
                let (muestrasLigeras, conteoHK) = autoreleasepool { () -> ([MuestraLigera], Int) in
                    let samples = addedSamples ?? []
                    let conteo = samples.count

                    let ligeras: [MuestraLigera] = samples.compactMap { sample in
                        guard let quantitySample = sample as? HKQuantitySample else {
                            return nil
                        }
                        let valor = quantitySample.quantity.doubleValue(for: unidadTipo)
                        guard valor.isFinite, valor > 0 else { return nil }
                        return MuestraLigera(
                            valor: valor,
                            inicio: quantitySample.startDate,
                            fin: quantitySample.endDate
                        )
                    }
                    // Al salir de este bloque, `samples` y todos los HKQuantitySample
                    // quedan fuera de scope → ARC los libera inmediatamente.
                    return (ligeras, conteo)
                }

                print("[HKM] 📊 [\(tag)]: HK=\(conteoHK) → filtradas=\(muestrasLigeras.count) (~\(muestrasLigeras.count * 24)B)")

                continuation.resume(returning: ResultadoAnchoredQuery(
                    tipo: tipo,
                    muestras: muestrasLigeras,
                    nuevoAnchor: newAnchor,
                    conteoHK: conteoHK
                ))
            }

            self.healthStore.execute(query)
        }
    }

    // MARK: - ════════════════════════════════════════════════
    // MARK:   ESTADÍSTICAS — Trabaja con MuestraLigera
    // MARK: - ════════════════════════════════════════════════

    struct EstadisticasSigno {
        let promedio: Double?
        let maximo: Double?
        let minimo: Double?
        let conteo: Int
    }

    /// Calcula estadísticas a partir de muestras ligeras.
    /// Los valores ya fueron filtrados (isFinite, > 0) durante la extracción.
    private func calcularEstadisticas(de muestras: [MuestraLigera]) -> EstadisticasSigno {
        guard !muestras.isEmpty else {
            return EstadisticasSigno(promedio: nil, maximo: nil, minimo: nil, conteo: 0)
        }

        let valores = muestras.map(\.valor)
        let promedio = (valores.reduce(0, +) / Double(valores.count) * 100).rounded() / 100

        return EstadisticasSigno(
            promedio: promedio,
            maximo: valores.max(),
            minimo: valores.min(),
            conteo: valores.count
        )
    }

    // MARK: - ════════════════════════════════════════════════
    // MARK:   HELPERS
    // MARK: - ════════════════════════════════════════════════

    private func guardarAnchors(
        fc: ResultadoAnchoredQuery?,
        spo2: ResultadoAnchoredQuery?,
        fr: ResultadoAnchoredQuery?
    ) {
        if let fc   { AnchorStore.save(fc.nuevoAnchor,   for: fc.tipo) }
        if let spo2 { AnchorStore.save(spo2.nuevoAnchor, for: spo2.tipo) }
        if let fr   { AnchorStore.save(fr.nuevoAnchor,   for: fr.tipo) }
    }
}

// MARK: - Errores

enum HealthKitManagerError: LocalizedError {
    case healthKitNoDisponible

    var errorDescription: String? {
        switch self {
        case .healthKitNoDisponible:
            return "HealthKit no está disponible en este dispositivo."
        }
    }
}

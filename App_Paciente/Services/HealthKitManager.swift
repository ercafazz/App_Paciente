//
//  HealthKitManager.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/1/26.
//
//  Refactor v5.8 — Poison Pill guard: un lote corrupto (4xx) deja de
//                  bloquear eternamente la cola de envíos.
//
//  Cambios vs v5.7:
//  1. Nuevo `ResultadoEnvio` con tres casos: `.exitoso`, `.transitorio`,
//     `.permanente`. Clasifica respuestas HTTP según si vale o no la pena
//     reintentar:
//       · 2xx              → exitoso
//       · 401/408/429/5xx  → transitorio (parar cola, reintentar)
//       · resto de 4xx     → permanente (descartar el lote y SEGUIR)
//     URLError/red → transitorio (sin info del servidor, asumir temporal).
//  2. `ejecutarPost`, `ejecutarPostPuntual`, `enviar`, `enviarLecturaPuntual`
//     ahora devuelven `ResultadoEnvio` en lugar de `Bool`. El caller ve
//     exactamente qué pasó y decide.
//  3. `flushBuffer()` y FASE 2 de `procesarConAnchors` manejan los 3 casos:
//     exitoso → eliminar y seguir; permanente → eliminar y seguir (poison
//     pill out); transitorio → parar el loop (permanece en buffer).
//     Antes: cualquier error hacía `break`, así que un 400/422 causado por
//     un payload malformado bloqueaba TODOS los lotes posteriores — hasta
//     que el usuario hiciera logout (que limpia todo) o reinstalara la app.
//  4. Los envíos puntuales (SpO2/FR) no tienen buffer, así que para ellos
//     transitorio y permanente tienen el mismo efecto operativo (se pierde
//     la lectura actual, el próximo tick traerá otra). Solo cambia el log.
//
//  Cambios v5.7 (Tokens unificados):
//  1. `EnvioLigero` deja de persistir tokens en UserDefaults y de refrescar
//     a mano vía POST /auth/v1/token. Ahora consulta `auth.session` del
//     SDK, que maneja el refresh atómicamente y la persistencia en Keychain.
//  2. Supabase usa **refresh token rotation**: cada refresh invalida el
//     anterior. Cuando EnvioLigero y el SDK competían por refrescar, uno
//     perdía la carrera y reutilizaba un refresh ya invalidado → GoTrue
//     lo interpretaba como ataque → **revocaba todas las sesiones del
//     usuario** → kick al login. Fin de ese bug.
//  3. Eliminadas: `guardarTokens`, `limpiarTokens`, `accessToken` getter,
//     `refreshToken` getter, `refrescarToken`, `guardarTokensSesion`.
//     Eliminadas también las 4 llamadas en AutenticacionView + ContentView.
//  4. Los helpers `ejecutarPost` y `ejecutarPostPuntual` devuelven `Bool`
//     (no `Bool?`) — ya no hay semántica especial de "401 = refresh".
//
//  Cambios v5.6 (BgTaskHolder):
//  1. Nuevo `BgTaskHolder` — envoltorio thread-safe e idempotente para
//     `UIBackgroundTaskIdentifier`. El expiration handler de
//     `beginBackgroundTask` ahora SIEMPRE llama `endBackgroundTask(_:)`
//     (requerido por Apple; omitirlo provoca crash `0x8badf00d`).
//  2. El `defer` del Task también libera el identifier, pero como el
//     holder es idempotente, cualquier carrera entre ambos caminos
//     es segura: el primero libera, el segundo es no-op.
//  3. El acceso al identifier está protegido por `NSLock` — el
//     expiration handler puede ser invocado desde cualquier queue de
//     UIKit, no solo main.
//
//  Cambios v5.5 (AcumuladorFC):
//  1. Nuevo `AcumuladorFC` en disco (~120 bytes fijos) que recibe
//     muestras incrementalmente entre ticks y **permite avanzar el anchor
//     FC siempre**, no solo al vencer el batching.
//  2. Antes: si el batching no vencía, las muestras se leían de HK pero
//     se descartaban sin avanzar anchor → el próximo tick re-leía las
//     mismas (durante ejercicio podía re-procesar el mismo bloque decenas
//     de veces). Ahora: muestras se fusionan al acumulador, anchor avanza,
//     próximo tick solo trae lecturas verdaderamente nuevas.
//  3. Estadísticas matemáticamente equivalentes (suma/conteo/min/max son
//     asociativos). El `idLote` del acumulador es estable hasta
//     consolidación → idempotencia end-to-end preservada.
//
//  Cambios v5.4 (Idempotencia + FechaISO):
//  1. Lotes generan UUID cliente (`id_lote`) y se envían con el header
//     `Prefer: resolution=ignore-duplicates`. Elimina duplicados cuando
//     la red muere después de que Supabase guardó pero antes del 200 OK.
//  2. Helper `FechaISO` unifica formato ISO8601 con milisegundos entre
//     RAM (EnvioLigero) y disco (BufferLocal). Antes, el encoder nativo
//     `.iso8601` amputaba las fracciones de segundo al persistir, así que
//     un lote reenviado desde buffer llegaba con timestamps menos precisos
//     que el flujo directo. El decoder es tolerante a ambos formatos para
//     no perder archivos legacy.
//
//  Cambios v5.3 (Avanzar y Persistir):
//  1. procesarConAnchors reordenado en dos fases:
//     FASE 1 (sin red): persistir lote FC en BufferLocal + guardar TODOS los anchors.
//     FASE 2 (red, best-effort): flushear buffer + enviar puntuales SpO2/FR.
//  2. Si iOS mata la app por timeout en background durante FASE 2,
//     los datos no se pierden (lote FC en buffer, anchors avanzados).
//  3. Soluciona el bug donde inicio_intervalo se "congelaba" y fc_lecturas
//     crecía indefinidamente (anchor nunca se guardaba al expirar bgTask).
//
//  Mantenido de v5.2:
//  - Bootstrap 2h, lote solo FC, SpO2/FR como puntuales.
//  - MuestraLigera, autoreleasepool, límite 5000.
//  - EnvioLigero con URLSession directo + token refresh.
//  - BufferLocal como almacenamiento durable intermedio.
//

import Foundation
import HealthKit
import UIKit
import Supabase

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
// MARK:   FechaISO — Formateo ISO8601 con milisegundos
// MARK: - ════════════════════════════════════════════════

/// Formateo unificado de fechas ISO8601 **con fracciones de segundo**.
///
/// **Motivo**: `JSONEncoder.DateEncodingStrategy.iso8601` (y su contraparte en
/// `JSONDecoder`) usa un `ISO8601DateFormatter` con las opciones por defecto
/// (`.withInternetDateTime`) — que **NO incluyen** `.withFractionalSeconds`.
/// Esto provocaba que los lotes guardados en `BufferLocal` perdieran los
/// milisegundos en disco, mientras que los enviados directo desde RAM vía
/// `EnvioLigero` sí los conservaban.
///
/// Efecto observado: un mismo `inicio_intervalo` se registraba como
/// `03:23:59.193+00` en el flujo feliz y `03:23:59+00` en el flujo de
/// reintento desde disco — precisión temporal inconsistente.
///
/// Este helper centraliza el formateo:
/// - **Escritura**: SIEMPRE con milisegundos.
/// - **Lectura**: tolerante a AMBOS formatos (con/sin ms), para no romper
///   archivos viejos del buffer guardados antes de este fix.
fileprivate enum FechaISO {

    /// Formatter canónico — escritura y lectura moderna (con ms).
    static let formatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    /// Formatter legacy — fallback para archivos antiguos sin ms.
    private static let formatterSinFracciones: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()

    /// Serializa una fecha en ISO8601 con milisegundos.
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    /// Parsea una fecha ISO8601 probando primero con ms, luego sin ms.
    static func date(from raw: String) -> Date? {
        if let d = formatter.date(from: raw) { return d }
        return formatterSinFracciones.date(from: raw)
    }

    /// Strategy para `JSONEncoder` — escribe SIEMPRE con milisegundos.
    static let encodingStrategy: JSONEncoder.DateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(string(from: date))
    }

    /// Strategy para `JSONDecoder` — tolera ambos formatos.
    static let decodingStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = date(from: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Fecha ISO8601 inválida: \(raw)"
            )
        }
        return parsed
    }
}

// MARK: - ════════════════════════════════════════════════
// MARK:   AcumuladorFC — Estadísticas incrementales en disco
// MARK: - ════════════════════════════════════════════════

/// Acumulador estadístico persistente para Frecuencia Cardíaca.
///
/// **Problema que resuelve**:
/// Antes, cuando el batching no vencía, el código leía las muestras de HK
/// y las descartaba SIN avanzar el anchor. Resultado: el próximo tick
/// re-leía las mismas muestras. Durante ejercicio (muestreo cada ~5s),
/// el mismo bloque de muestras se procesaba decenas de veces antes de
/// ser consolidado — desperdiciando RAM, CPU y budget de background.
///
/// **Solución**:
/// Cada tick fusiona las muestras nuevas en este acumulador (~120 bytes
/// fijos en disco, no crece con N muestras) y **avanza el anchor**. Las
/// muestras quedan resumidas en suma/conteo/min/max. Cuando el batching
/// vence, el acumulador se promueve a `LoteSignosVitales` y se limpia.
///
/// **Idempotencia**: el `idLote` se genera una sola vez (al crear el
/// acumulador) y se preserva hasta la consolidación. Si la app es matada
/// entre ticks, el UUID sobrevive en disco → el lote final sigue siendo
/// único de extremo a extremo.
fileprivate struct AcumuladorFC: Codable, Sendable {
    var idLote: UUID
    var conteo: Int
    var suma: Double
    var minimo: Double
    var maximo: Double
    var inicioIntervalo: Date
    var finIntervalo: Date

    /// Momento exacto (`HKQuantitySample.startDate`) de la muestra que estableció
    /// el `minimo` actual. Se actualiza cada vez que entra una muestra con valor
    /// estrictamente menor. Optional → nil para acumuladores legacy en disco.
    var momentoMinimo: Date?

    /// Momento exacto (`HKQuantitySample.startDate`) de la muestra que estableció
    /// el `maximo` actual. Se actualiza cada vez que entra una muestra con valor
    /// estrictamente mayor. Optional → nil para acumuladores legacy en disco.
    var momentoMaximo: Date?

    /// Convierte el acumulador a un lote listo para enviar.
    /// El promedio se redondea a 2 decimales (misma convención que antes).
    func aLote(idPaciente: UUID) -> LoteSignosVitales {
        let promedio = conteo > 0
            ? ((suma / Double(conteo)) * 100).rounded() / 100
            : nil

        // Duración del intervalo en HORAS (decimal). Ej.: 15 min = 0.25 h.
        // Redondeo a 4 decimales para que la columna NUMERIC no acumule
        // ruido de coma flotante (10⁻⁴ h ≈ 0.36 s — más que suficiente).
        let segundos = finIntervalo.timeIntervalSince(inicioIntervalo)
        let duracionHoras: Double? = (segundos > 0)
            ? (segundos / 3600.0 * 10000).rounded() / 10000
            : nil

        // Densidad = lecturas / horas. Defensivo contra duración 0 o negativa
        // (no debería ocurrir, pero blindamos para no escribir NaN/Inf en BD).
        let densidad: Double?
        if let h = duracionHoras, h > 0, conteo > 0 {
            densidad = ((Double(conteo) / h) * 100).rounded() / 100
        } else {
            densidad = nil
        }

        return LoteSignosVitales(
            id: idLote,
            idPaciente: idPaciente,
            inicioIntervalo: inicioIntervalo,
            finIntervalo: finIntervalo,
            fcPromedio: promedio,
            fcMaxima: conteo > 0 ? maximo : nil,
            fcMinima: conteo > 0 ? minimo : nil,
            fcLecturas: conteo > 0 ? conteo : nil,
            fcMinimaTimestamp: conteo > 0 ? momentoMinimo : nil,
            fcMaximaTimestamp: conteo > 0 ? momentoMaximo : nil,
            duracion: duracionHoras,
            densidadLecturas: densidad,
            // El cliente SIEMPRE escribe "pendiente". La Edge Function
            // (disparada por webhook tras INSERT) lo reemplaza por
            // "valido" o "invalido" según el modelo de calidad.
            estadoCalidad: "pendiente",
            creadoEn: nil
        )
    }
}

fileprivate enum AcumuladorFCStore {

    private static var archivoURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tueri_buffer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("acumulador_fc.json")
    }

    static func cargar() -> AcumuladorFC? {
        guard let data = try? Data(contentsOf: archivoURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = FechaISO.decodingStrategy
        return try? decoder.decode(AcumuladorFC.self, from: data)
    }

    static func guardar(_ acc: AcumuladorFC) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = FechaISO.encodingStrategy
        guard let data = try? encoder.encode(acc) else {
            print("[AccFC] ❌ Error codificando acumulador")
            return
        }
        try? data.write(to: archivoURL, options: .atomic)
    }

    static func limpiar() {
        try? FileManager.default.removeItem(at: archivoURL)
    }

    /// Fusiona muestras nuevas al acumulador existente (o crea uno).
    /// Operación completa: persiste el resultado en disco.
    /// - Returns: el acumulador resultante (para logging).
    @discardableResult
    static func fusionar(muestras: [MuestraLigera]) -> AcumuladorFC? {
        guard !muestras.isEmpty else { return cargar() }

        var acc = cargar() ?? AcumuladorFC(
            idLote: UUID(),
            conteo: 0,
            suma: 0,
            minimo: .infinity,
            maximo: -.infinity,
            inicioIntervalo: .distantFuture,
            finIntervalo: .distantPast,
            momentoMinimo: nil,
            momentoMaximo: nil
        )

        for m in muestras {
            acc.conteo += 1
            acc.suma += m.valor
            // Estricta menor/mayor: en empates conservamos la PRIMERA muestra
            // que estableció el extremo (timestamp más temprano).
            if m.valor < acc.minimo {
                acc.minimo = m.valor
                acc.momentoMinimo = m.inicio
            }
            if m.valor > acc.maximo {
                acc.maximo = m.valor
                acc.momentoMaximo = m.inicio
            }
            if m.inicio < acc.inicioIntervalo { acc.inicioIntervalo = m.inicio }
            if m.fin    > acc.finIntervalo    { acc.finIntervalo    = m.fin }
        }

        guardar(acc)
        return acc
    }
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
        // Escribe con milisegundos — misma precisión que el flujo directo
        // en RAM (EnvioLigero). Evita el bug de "amputación" de fracciones
        // que tenía .iso8601 por defecto.
        encoder.dateEncodingStrategy = FechaISO.encodingStrategy
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
        // Decodificador tolerante: acepta archivos nuevos (con ms) y
        // archivos legacy guardados antes del fix (sin ms). Garantiza
        // que ningún lote en disco quede "encallado" por incompatibilidad
        // de formato durante la transición.
        decoder.dateDecodingStrategy = FechaISO.decodingStrategy

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
// MARK:   ResultadoEnvio — Clasificación de respuestas HTTP
// MARK: - ════════════════════════════════════════════════

/// Resultado de un envío a Supabase. Distingue errores retryables de errores
/// "poison pill" (lotes defectuosos que nunca van a ser aceptados).
///
/// **Motivación**:
/// Antes, cualquier fallo retornaba `false`. El loop de `flushBuffer` hacía
/// `break` ante el primer error para no bombardear la red — razonable para
/// errores de red, pero **catastrófico** para errores de cliente (4xx):
/// un lote corrupto (payload mal formado, violación de constraint, etc.)
/// quedaba eternamente bloqueando TODA la cola posterior.
///
/// Ahora clasificamos:
/// - **Transitorio** → pausar cola, reintentar más tarde.
/// - **Permanente** → descartar el lote envenenado y **continuar** con el
///   siguiente. La cola se desatasca por sí sola.
fileprivate enum ResultadoEnvio {
    /// 2xx — el lote fue aceptado por el servidor.
    case exitoso

    /// Error retryable: red caída, 5xx, 408, 429, 401 (sesión revocada).
    /// El lote permanece en buffer. El caller debe **parar la cola** para
    /// no bombardear un servidor caído o una red sin conexión.
    case transitorio(razon: String)

    /// Error de cliente no retryable: 400, 403, 404, 409, 410, 413, 422.
    /// El payload o las credenciales nunca serán aceptadas. El caller
    /// debe **descartar el lote** y **continuar** con el siguiente.
    case permanente(status: Int, detalle: String)

    /// Clasifica un `HTTPURLResponse` según las reglas anteriores.
    /// - Parameters:
    ///   - response: la respuesta HTTP recibida
    ///   - data: el body (solo se logea en casos de error permanente)
    static func clasificar(_ response: HTTPURLResponse, data: Data) -> ResultadoEnvio {
        let status = response.statusCode

        // Éxito
        if (200...299).contains(status) {
            return .exitoso
        }

        // Transitorios (retryables):
        //  · 401 post-v5.7 = sesión revocada server-side (no es culpa del lote;
        //    se resolverá tras re-login)
        //  · 408 = request timeout
        //  · 429 = rate limit
        //  · 5xx = servidor caído
        if status == 401 || status == 408 || status == 429 || (500...599).contains(status) {
            return .transitorio(razon: "HTTP \(status)")
        }

        // Resto de 4xx = permanente (400, 403, 404, 409, 410, 413, 422, ...)
        let detalle = String(data: data, encoding: .utf8)?
            .prefix(500)                       // no logear payloads gigantes
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "(sin body)"
        return .permanente(status: status, detalle: String(detalle))
    }
}

// MARK: - ════════════════════════════════════════════════
// MARK:   EnvioLigero — HTTP POST directo al REST de Supabase
// MARK: - ════════════════════════════════════════════════

/// Envía lotes y lecturas puntuales directamente a la REST API de Supabase
/// usando `URLSession`. La única razón de evitar el `.from(...).insert(...)`
/// del SDK es mantener control fino sobre headers (idempotencia, Prefer),
/// timeouts y serialización manual — NO es para evitar cargar el SDK.
///
/// **Autenticación (v5.7)**: delega por completo la gestión de tokens al
/// `AuthClient` del SDK oficial — el único canal que toca Keychain y el
/// endpoint `/auth/v1/token`. Antes mantenía los tokens en `UserDefaults`
/// y refrescaba a mano, causando una colisión brutal con el SDK:
///
///   • El SDK usa **refresh token rotation**: cada refresh invalida el
///     token anterior. Si dos canales (SDK + EnvioLigero) compiten por
///     refrescar, el que pierde la carrera reutiliza un refresh ya
///     invalidado → GoTrue lo interpreta como ataque → **revoca todas
///     las sesiones del usuario** → kick al login.
///
/// Pidiéndole el access token al SDK, él se encarga del refresh atómico
/// (thread-safe, protegido por su propio actor interno) y mantiene una
/// sola copia canónica de los tokens en Keychain.
private enum EnvioLigero {

    private static let baseURL = "https://aqopgqcpdmbmgkxmgvoy.supabase.co"
    private static let apiKey  = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFxb3BncWNwZG1ibWdreG1ndm95Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4MjcxNDIsImV4cCI6MjA5MDQwMzE0Mn0.O3Lt-rDU_658DvJ5zR6rxu6pg-j7HNsbLZ8gOODtZcQ"

    // Nota: formateo de fechas delegado a `FechaISO` (helper compartido con
    // BufferLocal). Esto garantiza que RAM y disco usen IDÉNTICA precisión
    // (ms) y evita que un lote reenviado desde buffer llegue a Supabase con
    // timestamps "amputados".

    // MARK: Access token (fuente única de verdad: SDK de Supabase)

    /// Obtiene el access token fresco del SDK de Supabase.
    ///
    /// El getter `auth.session` del SDK:
    /// 1. Lee la sesión del Keychain.
    /// 2. Si el access token está próximo a expirar, **refresca atómicamente**
    ///    usando el refresh token (thread-safe) y guarda la nueva sesión.
    /// 3. Devuelve la sesión con un access token válido.
    ///
    /// Si el refresh falla (refresh token revocado, sin red, etc.) lanza
    /// un error. Aquí lo convertimos a `nil`: el lote quedará en el
    /// BufferLocal y se reintentará más tarde con un token potencialmente
    /// válido (o el usuario será redirigido al login por `ContentView`).
    private static func obtenerAccessToken() async -> String? {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            return session.accessToken
        } catch {
            print("[EnvioLigero] ❌ Sin sesión válida: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Envío de lote

    /// Envía un lote via HTTP POST. Devuelve el resultado clasificado.
    ///
    /// Tres desenlaces posibles:
    ///  · `.exitoso` — 2xx, el caller debe eliminar el lote del buffer.
    ///  · `.transitorio` — red/5xx/401/408/429, el caller debe **parar la cola**.
    ///  · `.permanente` — 4xx del cliente, el caller debe **descartar el lote**
    ///    y continuar con los siguientes (evita poison pill).
    static func enviar(_ lote: LoteSignosVitales) async -> ResultadoEnvio {
        await ejecutarPost(lote)
    }

    // MARK: Envío de lectura puntual (SpO2 / FR)

    /// Inserta una lectura puntual en `lecturas_puntuales`.
    /// Mismo contrato que `enviar(_:)`: devuelve `ResultadoEnvio` clasificado.
    static func enviarLecturaPuntual(
        idPaciente: UUID,
        tipo: String,
        valor: Double,
        fecha: Date
    ) async -> ResultadoEnvio {
        await ejecutarPostPuntual(
            idPaciente: idPaciente, tipo: tipo, valor: valor, fecha: fecha
        )
    }

    private static func ejecutarPostPuntual(
        idPaciente: UUID,
        tipo: String,
        valor: Double,
        fecha: Date
    ) async -> ResultadoEnvio {
        guard let token = await obtenerAccessToken() else {
            return .transitorio(razon: "sin sesión")
        }
        guard let url = URL(string: "\(baseURL)/rest/v1/lecturas_puntuales") else {
            return .permanente(status: -1, detalle: "URL inválida")
        }

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
            "fecha_lectura": FechaISO.string(from: fecha),
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: dict) else {
            return .permanente(status: -1, detalle: "error serializando body")
        }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .transitorio(razon: "respuesta no-HTTP")
            }
            let resultado = ResultadoEnvio.clasificar(http, data: data)
            switch resultado {
            case .exitoso:
                print("[EnvioLigero] ✅ Lectura puntual \(tipo) enviada (HTTP \(http.statusCode))")
            case .transitorio(let razon):
                print("[EnvioLigero] ⚠️ Lectura puntual \(tipo) transitorio (\(razon)) — reintento más tarde.")
            case .permanente(let status, let detalle):
                print("[EnvioLigero] 🛑 Lectura puntual \(tipo) PERMANENTE (HTTP \(status)) — descarte. Body: \(detalle)")
            }
            return resultado
        } catch {
            print("[EnvioLigero] ❌ Lectura puntual \(tipo) error de red: \(error.localizedDescription)")
            return .transitorio(razon: "red: \(error.localizedDescription)")
        }
    }

    // MARK: Envío de lote

    /// Ejecuta el POST del lote de FC. Devuelve un `ResultadoEnvio` clasificado.
    private static func ejecutarPost(_ lote: LoteSignosVitales) async -> ResultadoEnvio {
        guard let token = await obtenerAccessToken() else {
            print("[EnvioLigero] ❌ No hay sesión. El usuario no ha iniciado sesión o la sesión expiró.")
            return .transitorio(razon: "sin sesión")
        }

        guard let url = URL(string: "\(baseURL)/rest/v1/lotes_signos_vitales") else {
            return .permanente(status: -1, detalle: "URL inválida")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Idempotencia: si el cliente reintenta con el MISMO id (PK),
        // PostgREST detecta el conflicto y hace no-op en lugar de
        // crear una fila duplicada. Esto resuelve la condición de carrera
        // donde Supabase ya guardó la fila pero la red murió antes del 200 OK.
        request.setValue("resolution=ignore-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.timeoutInterval = 15

        // Construir JSON manual — solo FC + intervalo (Supabase usa DEFAULT para campos omitidos)
        var dict: [String: Any] = [
            "id_paciente": lote.idPaciente.uuidString,
            "inicio_intervalo": FechaISO.string(from: lote.inicioIntervalo),
            "fin_intervalo": FechaISO.string(from: lote.finIntervalo),
        ]

        // Idempotencia: enviar el UUID generado por el cliente.
        // BufferLocal preserva este id entre reintentos, así que cualquier
        // reintento (sea por red caída, app killed, o token refresh) usa
        // exactamente el mismo PK → Supabase ignora el duplicado.
        // OJO: la columna real en Supabase se llama `id_lote` (ver CodingKeys).
        if let id = lote.id {
            dict["id_lote"] = id.uuidString
        }

        // Solo FC — SpO2/FR se envían como lecturas puntuales
        if let v = lote.fcPromedio   { dict["fc_promedio"]   = v }
        if let v = lote.fcMaxima     { dict["fc_maxima"]     = v }
        if let v = lote.fcMinima     { dict["fc_minima"]     = v }
        if let v = lote.fcLecturas   { dict["fc_lecturas"]   = v }

        // Momento exacto de la lectura mínima/máxima (HKQuantitySample.startDate).
        // Nullable en BD: si por alguna razón no hubo muestras válidas, omitimos.
        if let t = lote.fcMinimaTimestamp { dict["fc_minima_timestamp"] = FechaISO.string(from: t) }
        if let t = lote.fcMaximaTimestamp { dict["fc_maxima_timestamp"] = FechaISO.string(from: t) }

        // Calidad del lote — para el modelo de alarmas inteligentes.
        // - duracion: horas decimales del intervalo.
        // - densidad_lecturas: lecturas/hora (filtra lotes con muestreo pobre).
        // - estado_calidad: SIEMPRE "pendiente" desde el cliente; la Edge
        //   Function lo recalcula a "valido"/"invalido" tras el INSERT.
        if let v = lote.duracion         { dict["duracion"]          = v }
        if let v = lote.densidadLecturas { dict["densidad_lecturas"] = v }
        if let v = lote.estadoCalidad    { dict["estado_calidad"]    = v }

        guard let body = try? JSONSerialization.data(withJSONObject: dict) else {
            print("[EnvioLigero] ❌ Error codificando lote")
            return .permanente(status: -1, detalle: "error serializando body")
        }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .transitorio(razon: "respuesta no-HTTP")
            }
            let resultado = ResultadoEnvio.clasificar(http, data: data)
            switch resultado {
            case .exitoso:
                print("[EnvioLigero] ✅ POST lote exitoso (HTTP \(http.statusCode))")
            case .transitorio(let razon):
                print("[EnvioLigero] ⚠️ POST lote transitorio (\(razon)) — permanece en buffer.")
            case .permanente(let status, let detalle):
                print("[EnvioLigero] 🛑 POST lote PERMANENTE (HTTP \(status)) — descarte. Body: \(detalle)")
            }
            return resultado
        } catch {
            print("[EnvioLigero] ❌ Error de red: \(error.localizedDescription)")
            return .transitorio(razon: "red: \(error.localizedDescription)")
        }
    }
}

// MARK: - ════════════════════════════════════════════════
// MARK:   BgTaskHolder — Gestión segura de UIBackgroundTaskIdentifier
// MARK: - ════════════════════════════════════════════════

/// Envoltorio thread-safe e idempotente para `UIBackgroundTaskIdentifier`.
///
/// **Por qué existe**:
/// La documentación oficial de Apple (`UIApplication.beginBackgroundTask`)
/// exige llamar a `endBackgroundTask(_:)` **dentro del expiration handler**.
/// Si el tiempo se agota y el handler no libera el identifier, el Watchdog
/// de iOS mata la app con crash `0x8badf00d` ("ate bad food").
///
/// Además, el expiration handler y el bloque normal de trabajo corren en
/// paralelo. Si ambos llaman `endBackgroundTask` con el mismo ID, es un
/// error de doble liberación. Este holder resuelve ambos problemas:
///
/// 1. `finalizar()` puede ser llamado desde el expiration handler **y**
///    desde el `defer` del Task sin riesgo — el segundo es no-op.
/// 2. El acceso al identifier está protegido por `NSLock` (el expiration
///    handler puede ser invocado desde cualquier queue de UIKit).
fileprivate final class BgTaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var id: UIBackgroundTaskIdentifier = .invalid

    /// Registra el identifier recién obtenido de `beginBackgroundTask`.
    func asignar(_ nuevo: UIBackgroundTaskIdentifier) {
        lock.lock()
        id = nuevo
        lock.unlock()
    }

    /// Libera el background task de forma idempotente y thread-safe.
    /// Seguro de llamar múltiples veces: el primer call libera, los
    /// siguientes son no-op (el id ya quedó en `.invalid`).
    func finalizar() {
        lock.lock()
        let actual = id
        id = .invalid
        lock.unlock()
        if actual != .invalid {
            UIApplication.shared.endBackgroundTask(actual)
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

    /// Key para `finIntervalo` del último lote consolidado.
    /// Se usa como cota inferior al cerrar el siguiente lote para evitar
    /// que una muestra tardía de HealthKit (startDate en el pasado) haga
    /// que `inicioIntervalo` quede por debajo del `finIntervalo` previo
    /// y dos lotes consecutivos se solapen visualmente en la gráfica.
    private static let ultimoFinLoteKey = "tueri.ultimoFinLote"

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
        print("[HKM] 🏥 Tuēri HealthKitManager v5.8 (Poison Pill guard)")
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

    // (v5.7: `guardarTokensSesion` eliminado. El `AuthClient` del SDK de
    //  Supabase es la única fuente de verdad para los tokens — no hay que
    //  duplicarlos. Ver `EnvioLigero.obtenerAccessToken()`.)

    func limpiarEstado() {
        idPaciente = nil
        AnchorStore.clear(types: Set<HKSampleType>(todosLosTipos))
        UserDefaults.standard.removeObject(forKey: Self.lastSendKey)
        UserDefaults.standard.removeObject(forKey: Self.ultimoFinLoteKey)
        AcumuladorFCStore.limpiar()
        // Los tokens de Supabase los limpia el SDK en `auth.signOut()`.
        // No tocamos nada aquí para no competir con el SDK.
        print("[HKM] 🧹 Estado limpiado (logout).")
    }

    /// Envía todos los lotes almacenados en el buffer local a Supabase.
    /// Se llama desde foreground (scenePhase .active) para reintentar envíos fallidos.
    ///
    /// **Poison pill guard (v5.8)**: ante un error **permanente** (4xx que
    /// nunca será aceptado por el servidor) el lote se **descarta** y el
    /// loop **continúa** con el siguiente. Antes, cualquier fallo rompía el
    /// loop → un lote corrupto bloqueaba TODA la cola posterior para siempre.
    /// Los errores **transitorios** (red, 5xx, 401, 408, 429) sí paran la
    /// cola, que es el comportamiento correcto para no bombardear.
    func flushBuffer() async {
        let pendientes = BufferLocal.leerPendientes()
        guard !pendientes.isEmpty else { return }

        print("[HKM] 📤 FLUSH: \(pendientes.count) lote(s) pendiente(s)")

        var enviados = 0
        var descartados = 0
        for (url, lote) in pendientes {
            let resultado = await EnvioLigero.enviar(lote)
            switch resultado {
            case .exitoso:
                BufferLocal.eliminar(url)
                enviados += 1

            case .permanente(let status, let detalle):
                // Lote envenenado: el servidor NUNCA lo va a aceptar.
                // Descartarlo y continuar desatasca la cola para los siguientes.
                BufferLocal.eliminar(url)
                descartados += 1
                print("[HKM] 🛑 FLUSH: lote \(lote.id?.uuidString.prefix(8) ?? "?") descartado (HTTP \(status)). Body: \(detalle)")

            case .transitorio(let razon):
                // Red caída / servidor caído / sesión revocada: parar la cola.
                print("[HKM] ⏸️ FLUSH pausado: \(razon). Restantes en buffer: \(BufferLocal.conteo())")
                break
            }
            // Nota: `break` dentro de `switch` sale SOLO del switch, no del `for`.
            // Para detener el loop ante error transitorio, comprobamos aquí.
            if case .transitorio = resultado { break }
        }

        if enviados > 0 || descartados > 0 {
            print("[HKM] 📤 FLUSH COMPLETO: enviados=\(enviados), descartados=\(descartados), total procesados=\(enviados + descartados)/\(pendientes.count)")
            if enviados > 0 {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .tueriLoteEnviado, object: nil)
                }
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
                //
                // El holder garantiza:
                //   1) El expiration handler SIEMPRE libera el identifier
                //      (cumple con Apple y evita crash 0x8badf00d).
                //   2) El `defer` del Task también intenta liberar, pero si
                //      el handler ganó la carrera es un no-op seguro.
                let bgTask = BgTaskHolder()
                let bgTaskID = UIApplication.shared.beginBackgroundTask(
                    withName: "tueri.sync.\(tipo.identifier)"
                ) {
                    // ⚠️ Apple exige endBackgroundTask DENTRO del handler.
                    print("[HKM] ⏰ bgTask EXPIRADO: \(tag) — liberando identifier.")
                    bgTask.finalizar()
                }
                bgTask.asignar(bgTaskID)

                Task { [weak self] in
                    defer {
                        completionHandler()
                        bgTask.finalizar()  // idempotente — no-op si el handler ya liberó
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
        let fc   = await consultarConAnchor(tipo: tipoFC)
        let spo2 = await consultarConAnchor(tipo: tipoSpO2)
        let fr   = await consultarConAnchor(tipo: tipoFR)

        let mFC   = fc?.muestras   ?? []
        let mSpO2 = spo2?.muestras ?? []
        let mFR   = fr?.muestras   ?? []
        let total = mFC.count + mSpO2.count + mFR.count

        print("[HKM] 📦 FC:\(mFC.count) SpO2:\(mSpO2.count) FR:\(mFR.count) — ~\(total * 24)B RAM")

        // ╔══════════════════════════════════════════════════════════════╗
        // ║  FASE 1 — ACUMULAR Y AVANZAR  (sin red, sub-milisegundos)    ║
        // ║                                                               ║
        // ║  Las muestras nuevas se fusionan al `AcumuladorFC` en disco, ║
        // ║  y los anchors se avanzan INMEDIATAMENTE. Si el batching no  ║
        // ║  ha vencido, el anchor FC avanza igual — las muestras NO se  ║
        // ║  pierden porque su resumen estadístico ya quedó en disco.    ║
        // ║                                                               ║
        // ║  Esto evita el anti-patrón anterior donde las muestras se    ║
        // ║  re-leían en cada tick hasta que venciera la ventana.        ║
        // ╚══════════════════════════════════════════════════════════════╝

        // ─── FC: fusionar al acumulador + avanzar anchor ───
        if !mFC.isEmpty {
            let acc = AcumuladorFCStore.fusionar(muestras: mFC)
            if let fc { AnchorStore.save(fc.nuevoAnchor, for: fc.tipo) }
            if let acc {
                print("[HKM] 📈 +\(mFC.count) muestras FC → acumulador total: \(acc.conteo) lecturas.")
            }
        }

        // ─── Consolidar acumulador si el batching venció ───
        let lastSend = UserDefaults.standard.object(
            forKey: Self.lastSendKey
        ) as? Date ?? .distantPast
        let elapsed = Date().timeIntervalSince(lastSend)
        let batchingVencido = forzar || elapsed >= Self.VENTANA_BATCHING

        var huboLoteFCNuevo = false
        if batchingVencido, let acc = AcumuladorFCStore.cargar(), acc.conteo > 0 {
            // Clamp anti-solape: si HK entregó una muestra tardía cuyo
            // startDate cae dentro del lote anterior, la fusión marcó
            // `inicioIntervalo` por debajo del `finIntervalo` previo. Aquí
            // recortamos ese borde sin tocar las muestras (promedio/min/max
            // se preservan). +1 ms garantiza lotes estrictamente disjuntos.
            var accAjustado = acc
            let ultimoFin = UserDefaults.standard.object(
                forKey: Self.ultimoFinLoteKey
            ) as? Date ?? .distantPast
            if accAjustado.inicioIntervalo < ultimoFin {
                let recorteMs = ultimoFin.timeIntervalSince(accAjustado.inicioIntervalo) * 1000
                print("[HKM] ✂️ Clamp de inicio_intervalo — recortados \(String(format: "%.0f", recorteMs)) ms para evitar solape con lote anterior.")
                accAjustado.inicioIntervalo = ultimoFin.addingTimeInterval(0.001)
            }
            let lote = accAjustado.aLote(idPaciente: idPaciente)

            // 1️⃣ PERSISTIR — escribir el lote en disco (durable, sub-ms)
            BufferLocal.guardar(lote)

            // 2️⃣ LIMPIAR — el acumulador ya fue promovido a lote
            AcumuladorFCStore.limpiar()

            // 3️⃣ AVANZAR ventana de batching y guardar fin para clamp futuro
            UserDefaults.standard.set(Date(), forKey: Self.lastSendKey)
            UserDefaults.standard.set(lote.finIntervalo, forKey: Self.ultimoFinLoteKey)

            huboLoteFCNuevo = true
            print("[HKM] 💾 LOTE FC consolidado — \(acc.conteo) lecturas en la ventana — \(ts())")
        } else if !batchingVencido, let acc = AcumuladorFCStore.cargar() {
            let restante = max(0, Int(Self.VENTANA_BATCHING - elapsed))
            print("[HKM] ⏳ BATCHING FC: faltan \(restante)s — acumulador con \(acc.conteo) lecturas (sin re-leer HK).")
        }

        // ─── SpO2 / FR: avanzar anchors INMEDIATAMENTE ───
        // Las lecturas puntuales son snapshots "última lectura". Si el
        // envío de red falla, el próximo tick traerá una lectura aún más
        // reciente, así que perder la actual no es problema y avanzar el
        // anchor evita reprocesar muestras viejas.
        if let spo2 { AnchorStore.save(spo2.nuevoAnchor, for: spo2.tipo) }
        if let fr   { AnchorStore.save(fr.nuevoAnchor,   for: fr.tipo) }

        // ─── Early return si realmente no hay nada que hacer ───
        //     No hay muestras nuevas, no se consolidó nada, y el buffer está vacío.
        if total == 0 && !huboLoteFCNuevo && BufferLocal.conteo() == 0 {
            print("[HKM] 📭 Sin datos nuevos ni pendientes.")
            return
        }

        // ╔══════════════════════════════════════════════════════════════╗
        // ║  FASE 2 — RED (best-effort, puede fallar o exceder timeout)  ║
        // ║                                                               ║
        // ║  Cualquier fallo aquí es seguro: los datos ya están en       ║
        // ║  almacenamiento durable y los anchors ya avanzaron.          ║
        // ╚══════════════════════════════════════════════════════════════╝

        var algoEnviado = false

        // ─── Flush del buffer FC (incluye lote nuevo + cualquier antiguo) ───
        // Mismo manejo de 3 casos que en `flushBuffer()`:
        //  · .exitoso      → eliminar del buffer y seguir
        //  · .permanente   → descartar (poison pill) y seguir
        //  · .transitorio  → parar, permanece en buffer para el próximo tick
        if huboLoteFCNuevo || BufferLocal.conteo() > 0 {
            let pendientes = BufferLocal.leerPendientes()
            var loopRoto = false
            for (url, loteEnDisco) in pendientes where !loopRoto {
                let resultado = await EnvioLigero.enviar(loteEnDisco)
                switch resultado {
                case .exitoso:
                    BufferLocal.eliminar(url)
                    algoEnviado = true
                    print("[HKM] ✅ Lote FC enviado desde buffer — restantes: \(BufferLocal.conteo())")

                case .permanente(let status, let detalle):
                    BufferLocal.eliminar(url)
                    print("[HKM] 🛑 Lote FC \(loteEnDisco.id?.uuidString.prefix(8) ?? "?") descartado (HTTP \(status)). Body: \(detalle)")

                case .transitorio(let razon):
                    print("[HKM] ⚠️ Envío de lote pausado (\(razon)) — permanece en buffer.")
                    loopRoto = true
                }
            }
        }

        // ─── Puntuales SpO2 / FR (anchors ya avanzados) ───
        // Para puntuales, .transitorio y .permanente tienen el mismo efecto
        // práctico desde el lado del cliente: la lectura se "pierde" (pero
        // el próximo tick traerá una más reciente). No hay buffer de puntuales,
        // así que no hay poison pill que eliminar. Solo distinguimos log.
        if let ultimaSpO2 = mSpO2.max(by: { $0.fin < $1.fin }) {
            // HealthKit devuelve SpO2 como fracción (0.0–1.0) → ×100 para porcentaje
            let resultado = await EnvioLigero.enviarLecturaPuntual(
                idPaciente: idPaciente, tipo: "spo2",
                valor: ultimaSpO2.valor * 100, fecha: ultimaSpO2.fin
            )
            if case .exitoso = resultado { algoEnviado = true }
            else { print("[HKM] ⚠️ SpO2 no enviada — el próximo tick traerá una nueva.") }
        }

        if let ultimaFR = mFR.max(by: { $0.fin < $1.fin }) {
            let resultado = await EnvioLigero.enviarLecturaPuntual(
                idPaciente: idPaciente, tipo: "fr",
                valor: ultimaFR.valor, fecha: ultimaFR.fin
            )
            if case .exitoso = resultado { algoEnviado = true }
            else { print("[HKM] ⚠️ FR no enviada — el próximo tick traerá una nueva.") }
        }

        // ─── Notificación al dashboard ───
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

    // (v5.5: `calcularEstadisticas` y `guardarAnchors` eliminados.
    //  Las estadísticas viven ahora en `AcumuladorFC`, y los anchors se
    //  guardan inline dentro de `procesarConAnchors` para permitir que
    //  el anchor FC avance en cada tick aunque el batching no haya vencido.)
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

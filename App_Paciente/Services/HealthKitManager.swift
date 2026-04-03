//
//  HealthKitManager.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/1/26.
//

import Foundation
import HealthKit

/// Gestor central de HealthKit. Se encarga de:
/// 1. Solicitar permisos de lectura (FC, SpO2, FR).
/// 2. Configurar observadores en segundo plano (`HKObserverQuery` + `enableBackgroundDelivery`).
/// 3. Consultar muestras nuevas desde la última sincronización.
/// 4. Calcular promedios/máximos/mínimos y empaquetar un `LoteSignosVitales`.
/// 5. Enviar el lote a Supabase a través de `SupabaseManager`.
///
/// Es una `final class` con patrón Singleton. `HKHealthStore` es internamente thread-safe,
/// y toda la lógica de mutación del estado (`ultimaSincronizacion`) se serializa
/// mediante un `NSLock` para garantizar seguridad en concurrencia.
final class HealthKitManager: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = HealthKitManager()

    // MARK: - Propiedades

    private let healthStore = HKHealthStore()

    /// ID del paciente autenticado. Debe asignarse tras el login antes de iniciar observadores.
    var idPaciente: UUID?

    // MARK: - Última sincronización (thread-safe)

    private let lock = NSLock()
    private static let ultimaSincKey = "HealthKitManager.ultimaSincronizacion"

    /// Fecha de la última sincronización exitosa. Persistida en `UserDefaults`
    /// para sobrevivir cierres de la app y relanzamientos en segundo plano.
    private var ultimaSincronizacion: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return UserDefaults.standard.object(forKey: Self.ultimaSincKey) as? Date
                ?? Calendar.current.date(byAdding: .hour, value: -1, to: Date())!
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            UserDefaults.standard.set(newValue, forKey: Self.ultimaSincKey)
        }
    }

    // MARK: - Tipos de HealthKit

    private let tipoFC = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let tipoSpO2 = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
    private let tipoFR = HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!

    /// Los tres tipos de signos vitales que monitorea Tuēri.
    private var todosLosTipos: Set<HKQuantityType> {
        [tipoFC, tipoSpO2, tipoFR]
    }

    // MARK: - Inicialización

    private init() {
        print("[HealthKitManager] Instancia creada.")
    }

    // MARK: - 1. Solicitud de Permisos

    /// Solicita autorización de lectura para FC, SpO2 y FR.
    /// Debe llamarse al inicio de la app (idealmente en onboarding o tras el login).
    func solicitarPermisos() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[HealthKitManager] ❌ HealthKit no disponible en este dispositivo.")
            throw HealthKitManagerError.healthKitNoDisponible
        }

        let tiposLectura: Set<HKSampleType> = [tipoFC, tipoSpO2, tipoFR]

        try await healthStore.requestAuthorization(toShare: [], read: tiposLectura)

        print("[HealthKitManager] ✅ Permisos de lectura solicitados para FC, SpO2, FR.")
    }

    // MARK: - 2. Observadores en Segundo Plano

    /// Configura `HKObserverQuery` y `enableBackgroundDelivery` para los tres signos vitales.
    /// Cada vez que el Apple Watch deposite nuevos datos en HealthKit, iOS despertará la app
    /// y ejecutará `procesarNuevosDatos()`.
    ///
    /// **Llamar una sola vez**, típicamente en `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    func configurarObservadores() {
        for tipo in todosLosTipos {
            let query = HKObserverQuery(sampleType: tipo, predicate: nil) { [weak self] _, completionHandler, error in
                guard let self else {
                    completionHandler()
                    return
                }

                if let error {
                    print("[HealthKitManager] ❌ ObserverQuery error para \(tipo.identifier): \(error.localizedDescription)")
                    completionHandler()
                    return
                }

                print("[HealthKitManager] 🔔 Observador disparado para: \(tipo.identifier)")

                Task {
                    await self.procesarNuevosDatos()
                    completionHandler()
                }
            }

            healthStore.execute(query)

            healthStore.enableBackgroundDelivery(for: tipo, frequency: .immediate) { exito, error in
                if exito {
                    print("[HealthKitManager] ✅ Background delivery activado para: \(tipo.identifier)")
                } else if let error {
                    print("[HealthKitManager] ❌ Background delivery falló para \(tipo.identifier): \(error.localizedDescription)")
                }
            }
        }

        print("[HealthKitManager] Observadores configurados para los 3 signos vitales.")
    }

    // MARK: - 3. Cálculos Estadísticos

    /// Resultado de los cálculos estadísticos de un conjunto de muestras.
    struct EstadisticasSigno {
        let promedio: Double?
        let maximo: Double?
        let minimo: Double?
        let conteo: Int
    }

    /// Calcula promedio, máximo, mínimo y conteo a partir de un arreglo de `HKQuantitySample`.
    ///
    /// - Parameters:
    ///   - muestras: Arreglo de muestras obtenidas de HealthKit.
    ///   - unidad: La `HKUnit` para extraer el valor numérico (ej: `count()/min` para FC).
    /// - Returns: Tupla con los cálculos. Si no hay muestras válidas, promedio/max/min son `nil` y conteo es 0.
    func calcularEstadisticas(
        de muestras: [HKQuantitySample],
        unidad: HKUnit
    ) -> EstadisticasSigno {
        let valores = muestras.compactMap { muestra -> Double? in
            let valor = muestra.quantity.doubleValue(for: unidad)
            // Descartar valores fisiológicamente imposibles o corruptos
            guard valor.isFinite, valor > 0 else { return nil }
            return valor
        }

        guard !valores.isEmpty else {
            return EstadisticasSigno(promedio: nil, maximo: nil, minimo: nil, conteo: 0)
        }

        let suma = valores.reduce(0, +)
        let promedio = (suma / Double(valores.count) * 100).rounded() / 100

        return EstadisticasSigno(
            promedio: promedio,
            maximo: valores.max(),
            minimo: valores.min(),
            conteo: valores.count
        )
    }

    // MARK: - 4. Orquestación y Sincronización

    /// Flujo principal: consulta datos nuevos desde la última sincronización,
    /// calcula estadísticas, empaqueta un lote y lo envía a Supabase.
    private func procesarNuevosDatos() async {
        guard let idPaciente else {
            print("[HealthKitManager] ❌ No se puede procesar: idPaciente no asignado.")
            return
        }

        let desde = ultimaSincronizacion
        let hasta = Date()

        print("[HealthKitManager] Procesando datos desde \(desde) hasta \(hasta)")

        // Consultar los tres signos vitales en paralelo
        async let muestrasFC = consultarMuestras(tipo: tipoFC, desde: desde, hasta: hasta)
        async let muestrasSpo2 = consultarMuestras(tipo: tipoSpO2, desde: desde, hasta: hasta)
        async let muestrasFR = consultarMuestras(tipo: tipoFR, desde: desde, hasta: hasta)

        let fc = await muestrasFC
        let spo2 = await muestrasSpo2
        let fr = await muestrasFR

        // Si no hay absolutamente ninguna lectura, no enviar lote vacío
        guard !fc.isEmpty || !spo2.isEmpty || !fr.isEmpty else {
            print("[HealthKitManager] ⚠️ Sin lecturas nuevas en el intervalo. No se envía lote.")
            return
        }

        // Calcular estadísticas por signo vital
        let estadisticasFC = calcularEstadisticas(
            de: fc,
            unidad: HKUnit.count().unitDivided(by: .minute())
        )
        let estadisticasSpo2 = calcularEstadisticas(
            de: spo2,
            unidad: HKUnit.percent()
        )
        let estadisticasFR = calcularEstadisticas(
            de: fr,
            unidad: HKUnit.count().unitDivided(by: .minute())
        )

        // Determinar el intervalo real basado en las muestras obtenidas
        let todasLasMuestras: [HKSample] = fc + spo2 + fr
        let inicioReal = todasLasMuestras.map(\.startDate).min() ?? desde
        let finReal = todasLasMuestras.map(\.endDate).max() ?? hasta

        // Empaquetar el lote
        let lote = LoteSignosVitales(
            id: nil,
            idPaciente: idPaciente,
            inicioIntervalo: inicioReal,
            finIntervalo: finReal,
            fcPromedio: estadisticasFC.promedio,
            fcMaxima: estadisticasFC.maximo,
            fcMinima: estadisticasFC.minimo,
            fcLecturas: estadisticasFC.conteo,
            spo2Promedio: estadisticasSpo2.promedio,
            spo2Maxima: estadisticasSpo2.maximo,
            spo2Minima: estadisticasSpo2.minimo,
            spo2Lecturas: estadisticasSpo2.conteo,
            frPromedio: estadisticasFR.promedio,
            frMaxima: estadisticasFR.maximo,
            frMinima: estadisticasFR.minimo,
            frLecturas: estadisticasFR.conteo,
            creadoEn: nil
        )

        print("[HealthKitManager] 📦 Lote empaquetado — FC: \(estadisticasFC.conteo), SpO2: \(estadisticasSpo2.conteo), FR: \(estadisticasFR.conteo) lecturas")

        // Enviar a Supabase
        do {
            try await SupabaseManager.shared.enviarLote(lote)
            // Solo actualizar la marca si el envío fue exitoso
            ultimaSincronizacion = hasta
            print("[HealthKitManager] ✅ Sincronización completada. Próxima consulta desde: \(hasta)")
        } catch {
            print("[HealthKitManager] ❌ Fallo al enviar lote. Se reintentará en la próxima activación.")
            print("[HealthKitManager] La marca de sincronización NO se actualizó (quedó en \(desde)).")
        }
    }

    // MARK: - Consulta de Muestras

    /// Consulta muestras de un tipo de dato específico dentro de un rango de tiempo.
    /// Usa `withCheckedContinuation` para convertir la API de callbacks de HealthKit a `async`.
    ///
    /// - Parameters:
    ///   - tipo: El `HKQuantityType` a consultar.
    ///   - desde: Fecha de inicio del rango.
    ///   - hasta: Fecha de fin del rango.
    /// - Returns: Arreglo de `HKQuantitySample` ordenado cronológicamente. Vacío si hay error.
    private func consultarMuestras(
        tipo: HKQuantityType,
        desde: Date,
        hasta: Date
    ) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            let predicado = HKQuery.predicateForSamples(
                withStart: desde,
                end: hasta,
                options: .strictStartDate
            )

            let ordenCronologico = NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate,
                ascending: true
            )

            let query = HKSampleQuery(
                sampleType: tipo,
                predicate: predicado,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [ordenCronologico]
            ) { _, resultados, error in
                if let error {
                    print("[HealthKitManager] ❌ Error consultando \(tipo.identifier): \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }

                let muestras = (resultados as? [HKQuantitySample]) ?? []
                print("[HealthKitManager] 📊 \(tipo.identifier): \(muestras.count) muestras obtenidas.")
                continuation.resume(returning: muestras)
            }

            healthStore.execute(query)
        }
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

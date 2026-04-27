//
//  LoteSignosVitales.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/1/26.
//

import Foundation

/// Modelo que representa un registro de la tabla `lotes_signos_vitales` en Supabase.
/// Cada lote agrupa las lecturas de **Frecuencia Cardíaca** capturadas por HealthKit
/// durante un intervalo de tiempo determinado.
///
/// SpO2 y FR ya NO se incluyen en el lote — se manejan como lecturas puntuales
/// en la tabla `lecturas_puntuales`.
struct LoteSignosVitales: Codable, Identifiable, Sendable {

    // MARK: - Identificación

    var id: UUID?
    var idPaciente: UUID

    // MARK: - Intervalo de captura

    var inicioIntervalo: Date
    var finIntervalo: Date

    // MARK: - Frecuencia Cardíaca (lpm)

    var fcPromedio: Double?
    var fcMaxima: Double?
    var fcMinima: Double?
    var fcLecturas: Int?

    /// Momento exacto (`HKQuantitySample.startDate`) de la muestra que produjo
    /// `fcMinima` dentro del intervalo del lote. Nullable por compatibilidad con
    /// lotes legacy guardados antes de esta columna.
    var fcMinimaTimestamp: Date?

    /// Momento exacto (`HKQuantitySample.startDate`) de la muestra que produjo
    /// `fcMaxima` dentro del intervalo del lote. Nullable por compatibilidad con
    /// lotes legacy guardados antes de esta columna.
    var fcMaximaTimestamp: Date?

    // MARK: - Calidad del lote (alarmas inteligentes)

    /// Duración del intervalo del lote en **horas** (decimal).
    /// Ej.: lote de 15 min → `0.25`. Calculado como `(fin - inicio) / 3600`.
    var duracion: Double?

    /// Densidad de muestreo en **lecturas por hora** dentro del intervalo.
    /// Calculado como `fcLecturas / duracion`. nil si no hay lecturas o
    /// duración cero (edge case defensivo).
    var densidadLecturas: Double?

    /// Estado de calidad del lote. El cliente siempre escribe `"pendiente"`;
    /// una Edge Function (disparada por webhook tras el INSERT) lo actualiza
    /// a `"valido"` o `"invalido"` según el modelo de calidad.
    var estadoCalidad: String?

    // MARK: - Metadatos

    var creadoEn: Date?

    // MARK: - Identifiable

    var idLote: UUID? { id }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id = "id_lote"
        case idPaciente = "id_paciente"

        case inicioIntervalo = "inicio_intervalo"
        case finIntervalo = "fin_intervalo"

        case fcPromedio = "fc_promedio"
        case fcMaxima = "fc_maxima"
        case fcMinima = "fc_minima"
        case fcLecturas = "fc_lecturas"

        case fcMinimaTimestamp = "fc_minima_timestamp"
        case fcMaximaTimestamp = "fc_maxima_timestamp"

        case duracion = "duracion"
        case densidadLecturas = "densidad_lecturas"
        case estadoCalidad = "estado_calidad"

        case creadoEn = "creado_en"
    }
}

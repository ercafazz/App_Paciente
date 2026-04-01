//
//  LoteSignosVitales.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/1/26.
//

import Foundation

/// Modelo que representa un registro de la tabla `lotes_signos_vitales` en Supabase.
/// Cada lote agrupa las lecturas de signos vitales capturadas por HealthKit
/// durante un intervalo de tiempo determinado.
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

    // MARK: - Saturación de Oxígeno (%)

    var spo2Promedio: Double?
    var spo2Maxima: Double?
    var spo2Minima: Double?
    var spo2Lecturas: Int?

    // MARK: - Frecuencia Respiratoria (rpm)

    var frPromedio: Double?
    var frMaxima: Double?
    var frMinima: Double?
    var frLecturas: Int?

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

        case spo2Promedio = "spo2_promedio"
        case spo2Maxima = "spo2_maxima"
        case spo2Minima = "spo2_minima"
        case spo2Lecturas = "spo2_lecturas"

        case frPromedio = "fr_promedio"
        case frMaxima = "fr_maxima"
        case frMinima = "fr_minima"
        case frLecturas = "fr_lecturas"

        case creadoEn = "creado_en"
    }
}

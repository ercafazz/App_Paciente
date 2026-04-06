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

        case creadoEn = "creado_en"
    }
}

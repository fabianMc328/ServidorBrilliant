import 'estados_sala.dart';

/// Vista pública e inmutable del estado de un jugador dentro de la sala/partida.
class ResumenJugador {
  final String id;
  final String apodo;
  final bool esAnfitrion;
  final bool estaListo;
  final EstadoParticipacion participacion;
  final int puntuacion;
  final int regionesCompletadas;
  final int casillasOcupadas;
  final bool confirmoAccionActual;

  const ResumenJugador({
    required this.id,
    required this.apodo,
    required this.esAnfitrion,
    required this.estaListo,
    required this.participacion,
    this.puntuacion = 0,
    this.regionesCompletadas = 0,
    this.casillasOcupadas = 0,
    this.confirmoAccionActual = false,
  });

  ResumenJugador copiarCon({
    String? id,
    String? apodo,
    bool? esAnfitrion,
    bool? estaListo,
    EstadoParticipacion? participacion,
    int? puntuacion,
    int? regionesCompletadas,
    int? casillasOcupadas,
    bool? confirmoAccionActual,
  }) {
    return ResumenJugador(
      id: id ?? this.id,
      apodo: apodo ?? this.apodo,
      esAnfitrion: esAnfitrion ?? this.esAnfitrion,
      estaListo: estaListo ?? this.estaListo,
      participacion: participacion ?? this.participacion,
      puntuacion: puntuacion ?? this.puntuacion,
      regionesCompletadas: regionesCompletadas ?? this.regionesCompletadas,
      casillasOcupadas: casillasOcupadas ?? this.casillasOcupadas,
      confirmoAccionActual: confirmoAccionActual ?? this.confirmoAccionActual,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'apodo': apodo,
        'esAnfitrion': esAnfitrion,
        'estaListo': estaListo,
        'participacion': participacion.name,
        'puntuacion': puntuacion,
        'regionesCompletadas': regionesCompletadas,
        'casillasOcupadas': casillasOcupadas,
        'confirmoAccionActual': confirmoAccionActual,
      };

  factory ResumenJugador.fromJson(Map<String, dynamic> json) {
    return ResumenJugador(
      id: json['id'] as String,
      apodo: json['apodo'] as String,
      esAnfitrion: (json['esAnfitrion'] as bool?) ?? false,
      estaListo: (json['estaListo'] as bool?) ?? false,
      participacion: EstadoParticipacion.desdeNombre(
        (json['participacion'] as String?) ?? '',
      ),
      puntuacion: (json['puntuacion'] as num?)?.toInt() ?? 0,
      regionesCompletadas: (json['regionesCompletadas'] as num?)?.toInt() ?? 0,
      casillasOcupadas: (json['casillasOcupadas'] as num?)?.toInt() ?? 0,
      confirmoAccionActual: (json['confirmoAccionActual'] as bool?) ?? false,
    );
  }
}

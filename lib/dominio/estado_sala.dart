import '../constantes_servidor.dart';
import 'estados_sala.dart';
import 'jugador_sala.dart';
import 'modelos_mapa.dart';
import 'motor_puntuacion_carrera.dart';

/// Snapshot completo e inmutable de la sala/partida adaptado para un jugador concreto.
/// Contrato JSON idéntico al cliente Flutter.
class EstadoSalaMultijugador {
  final String codigoSala;
  final String miJugadorId;
  final FaseSala fase;
  final String nivelId;
  final List<ResumenJugador> jugadores;
  final int rondaActual;
  final int? dado1;
  final int? dado2;
  final int segundosRestantes;
  final int metaPuntos;
  final Map<PosicionMapa, int> misValoresTablero;
  final Map<String, int> miDesglosePuntos;
  final Map<String, EstadoCarreraRegion> carreraPorRegion;
  final List<String> ganadoresIds;
  final MotivoFinPartida? motivoFin;
  final String? mensajeEventoReciente;

  const EstadoSalaMultijugador({
    required this.codigoSala,
    required this.miJugadorId,
    required this.fase,
    required this.nivelId,
    required this.jugadores,
    this.rondaActual = 0,
    this.dado1,
    this.dado2,
    this.segundosRestantes = 0,
    this.metaPuntos = ConstantesServidor.metaPuntos2Jugadores,
    this.misValoresTablero = const {},
    this.miDesglosePuntos = const {},
    this.carreraPorRegion = const {},
    this.ganadoresIds = const [],
    this.motivoFin,
    this.mensajeEventoReciente,
  });

  ResumenJugador? get miResumen {
    for (final j in jugadores) {
      if (j.id == miJugadorId) return j;
    }
    return null;
  }

  bool get soyAnfitrion => miResumen?.esAnfitrion ?? false;

  bool get estoyListo => miResumen?.estaListo ?? false;

  int get cantidadListos => jugadores
      .where((j) => j.estaListo && j.participacion.estaConectadoActivo)
      .length;

  bool get todosListosParaIniciar =>
      jugadores.length >= ConstantesServidor.minJugadoresPartida &&
      jugadores.length <= ConstantesServidor.maxJugadoresSala &&
      jugadores.every(
        (j) => j.participacion.estaConectadoActivo && j.estaListo,
      );

  List<ResumenJugador> get clasificacionOrdenada {
    final copia = List<ResumenJugador>.from(jugadores);
    copia.sort((a, b) {
      final aCompite = a.participacion.sigueEnCompetencia ? 1 : 0;
      final bCompite = b.participacion.sigueEnCompetencia ? 1 : 0;
      if (aCompite != bCompite) return bCompite.compareTo(aCompite);
      final cmpPuntos = b.puntuacion.compareTo(a.puntuacion);
      if (cmpPuntos != 0) return cmpPuntos;
      return b.regionesCompletadas.compareTo(a.regionesCompletadas);
    });
    return copia;
  }

  Map<String, dynamic> toJson() => {
        'codigoSala': codigoSala,
        'miJugadorId': miJugadorId,
        'fase': fase.name,
        'nivelId': nivelId,
        'jugadores': jugadores.map((j) => j.toJson()).toList(),
        'rondaActual': rondaActual,
        'dado1': dado1,
        'dado2': dado2,
        'segundosRestantes': segundosRestantes,
        'metaPuntos': metaPuntos,
        'misValoresTablero': {
          for (final e in misValoresTablero.entries) e.key.clave: e.value,
        },
        'miDesglosePuntos': miDesglosePuntos,
        'carreraPorRegion': {
          for (final e in carreraPorRegion.entries) e.key: e.value.toJson(),
        },
        'ganadoresIds': ganadoresIds,
        'motivoFin': motivoFin?.name,
        'mensajeEventoReciente': mensajeEventoReciente,
      };

  factory EstadoSalaMultijugador.fromJson(Map<String, dynamic> json) {
    final mapaValoresRaw =
        (json['misValoresTablero'] as Map<String, dynamic>?) ?? const {};
    final misValores = <PosicionMapa, int>{};
    for (final entry in mapaValoresRaw.entries) {
      misValores[PosicionMapa.desdeClave(entry.key)] =
          (entry.value as num).toInt();
    }

    final desgloseRaw =
        (json['miDesglosePuntos'] as Map<String, dynamic>?) ?? const {};
    final miDesglose = <String, int>{
      for (final e in desgloseRaw.entries) e.key: (e.value as num).toInt(),
    };

    final carreraRaw =
        (json['carreraPorRegion'] as Map<String, dynamic>?) ?? const {};
    final carrera = <String, EstadoCarreraRegion>{
      for (final e in carreraRaw.entries)
        e.key: EstadoCarreraRegion.fromJson(e.value as Map<String, dynamic>),
    };

    return EstadoSalaMultijugador(
      codigoSala: json['codigoSala'] as String,
      miJugadorId: json['miJugadorId'] as String,
      fase: FaseSala.desdeNombre((json['fase'] as String?) ?? ''),
      nivelId: (json['nivelId'] as String?) ?? 'nivel_1',
      jugadores: ((json['jugadores'] as List<dynamic>?) ?? const [])
          .map((e) => ResumenJugador.fromJson(e as Map<String, dynamic>))
          .toList(),
      rondaActual: (json['rondaActual'] as num?)?.toInt() ?? 0,
      dado1: (json['dado1'] as num?)?.toInt(),
      dado2: (json['dado2'] as num?)?.toInt(),
      segundosRestantes: (json['segundosRestantes'] as num?)?.toInt() ?? 0,
      metaPuntos: (json['metaPuntos'] as num?)?.toInt() ??
          ConstantesServidor.metaPuntos2Jugadores,
      misValoresTablero: misValores,
      miDesglosePuntos: miDesglose,
      carreraPorRegion: carrera,
      ganadoresIds: ((json['ganadoresIds'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      motivoFin:
          MotivoFinPartida.desdeNombreONull(json['motivoFin'] as String?),
      mensajeEventoReciente: json['mensajeEventoReciente'] as String?,
    );
  }
}

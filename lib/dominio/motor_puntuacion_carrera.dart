import '../constantes_servidor.dart';
import 'modelos_mapa.dart';

/// Estado competitivo de una región específica en la carrera multijugador.
class EstadoCarreraRegion {
  final String regionId;
  final int completadosPrevios;
  final List<String> idsJugadoresCompletaron;

  const EstadoCarreraRegion({
    required this.regionId,
    this.completadosPrevios = 0,
    this.idsJugadoresCompletaron = const [],
  });

  /// Escalón disponible para el siguiente jugador en completar esta región (1, 2 o 3).
  int get escalonActual {
    if (completadosPrevios <= 0) {
      return ConstantesServidor.escalonPrimero;
    }
    if (completadosPrevios == 1) {
      return ConstantesServidor.escalonSegundo;
    }
    return ConstantesServidor.escalonTerceroOMas;
  }

  int puntosDisponibles(Map<int, int> tablaPuntuaciones) {
    return tablaPuntuaciones[escalonActual] ?? 0;
  }

  Map<String, dynamic> toJson() => {
        'regionId': regionId,
        'completadosPrevios': completadosPrevios,
        'idsJugadoresCompletaron': idsJugadoresCompletaron,
      };

  factory EstadoCarreraRegion.fromJson(Map<String, dynamic> json) {
    return EstadoCarreraRegion(
      regionId: json['regionId'] as String,
      completadosPrevios: (json['completadosPrevios'] as num?)?.toInt() ?? 0,
      idsJugadoresCompletaron:
          (json['idsJugadoresCompletaron'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
    );
  }
}

/// Resultado inmutable tras evaluar el cierre simultáneo de una ronda.
class ResultadoResolucionCarrera {
  final Map<String, EstadoCarreraRegion> carreraActualizada;
  final Map<String, Map<String, int>> desglosePorJugador;
  final Map<String, int> puntuacionTotalPorJugador;
  final List<String> eventosCompletadoRonda;

  const ResultadoResolucionCarrera({
    required this.carreraActualizada,
    required this.desglosePorJugador,
    required this.puntuacionTotalPorJugador,
    required this.eventosCompletadoRonda,
  });
}

/// Motor matemático puro de las reglas oficiales de carrera de Brilliant.
class MotorPuntuacionCarrera {
  MotorPuntuacionCarrera._();

  static Map<String, EstadoCarreraRegion> inicializarCarrera(EsquemaMapa mapa) {
    return {
      for (final r in mapa.regiones) r.id: EstadoCarreraRegion(regionId: r.id),
    };
  }

  /// Evalúa simultáneamente las regiones completadas al cierre de una ronda.
  /// Si varios jugadores completan la misma región en la misma ronda, todos
  /// reciben el premio disponible actual, y el escalón avanza según cuántos
  /// la completaron en total (el tercer escalón nunca se agota).
  static ResultadoResolucionCarrera resolverCierreDeRonda({
    required EsquemaMapa mapa,
    required Map<String, EstadoCarreraRegion> carreraActual,
    required Map<String, Set<String>> regionesCompletasTotalesPorJugador,
    required Map<String, Map<String, int>> desglosePrevioPorJugador,
    required Map<String, String> apodosPorJugador,
  }) {
    final nuevaCarrera = <String, EstadoCarreraRegion>{
      for (final e in carreraActual.entries) e.key: e.value,
    };

    final nuevoDesglose = <String, Map<String, int>>{
      for (final e in desglosePrevioPorJugador.entries)
        e.key: Map<String, int>.from(e.value),
    };

    for (final jugadorId in regionesCompletasTotalesPorJugador.keys) {
      nuevoDesglose.putIfAbsent(jugadorId, () => <String, int>{});
    }

    final eventos = <String>[];

    for (final region in mapa.regiones) {
      final estadoRegion =
          nuevaCarrera[region.id] ?? EstadoCarreraRegion(regionId: region.id);

      final nuevosGanadores = <String>[];
      for (final entry in regionesCompletasTotalesPorJugador.entries) {
        final jugadorId = entry.key;
        final completasJugador = entry.value;
        final yaPuntuada =
            nuevoDesglose[jugadorId]?.containsKey(region.id) ?? false;
        if (completasJugador.contains(region.id) && !yaPuntuada) {
          nuevosGanadores.add(jugadorId);
        }
      }

      if (nuevosGanadores.isNotEmpty) {
        final puntosPremio = estadoRegion.puntosDisponibles(region.puntuaciones);
        for (final jugadorId in nuevosGanadores) {
          nuevoDesglose[jugadorId]![region.id] = puntosPremio;
          final apodo = apodosPorJugador[jugadorId] ?? jugadorId;
          eventos.add('$apodo completó ${region.id} (+$puntosPremio pts)');
        }

        nuevaCarrera[region.id] = EstadoCarreraRegion(
          regionId: region.id,
          completadosPrevios:
              estadoRegion.completadosPrevios + nuevosGanadores.length,
          idsJugadoresCompletaron: [
            ...estadoRegion.idsJugadoresCompletaron,
            ...nuevosGanadores,
          ],
        );
      }
    }

    final totales = <String, int>{};
    for (final entry in nuevoDesglose.entries) {
      totales[entry.key] =
          entry.value.values.fold<int>(0, (acc, pts) => acc + pts);
    }

    return ResultadoResolucionCarrera(
      carreraActualizada: nuevaCarrera,
      desglosePorJugador: nuevoDesglose,
      puntuacionTotalPorJugador: totales,
      eventosCompletadoRonda: eventos,
    );
  }

  /// Determina si se alcanzó o superó la meta de puntos entre jugadores en competencia.
  static bool alguienAlcanzoMeta({
    required Iterable<String> jugadoresEnCompetenciaIds,
    required Map<String, int> puntuaciones,
    required int metaPuntos,
  }) {
    for (final id in jugadoresEnCompetenciaIds) {
      if ((puntuaciones[id] ?? 0) >= metaPuntos) {
        return true;
      }
    }
    return false;
  }

  /// Retorna el o los ganadores (soporta victoria compartida en empate).
  static List<String> determinarGanadores({
    required List<String> jugadoresElegiblesIds,
    required Map<String, int> puntuaciones,
  }) {
    if (jugadoresElegiblesIds.isEmpty) return const [];
    int maxPuntaje = -1;
    for (final id in jugadoresElegiblesIds) {
      final pts = puntuaciones[id] ?? 0;
      if (pts > maxPuntaje) maxPuntaje = pts;
    }
    return jugadoresElegiblesIds
        .where((id) => (puntuaciones[id] ?? 0) == maxPuntaje)
        .toList();
  }
}

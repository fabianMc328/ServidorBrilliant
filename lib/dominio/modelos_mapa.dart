import '../constantes_servidor.dart';
import 'reglas.dart';

/// Tipos de regla de región puros (sin dependencias gráficas).
enum TipoReglaRegion {
  azul,
  gris,
  morado,
  verde,
  amarillo,
  rojo,
  naranja1a3,
  naranja4a6;

  bool permiteInsertar(List<int> actuales, int numero) {
    switch (this) {
      case TipoReglaRegion.azul:
      case TipoReglaRegion.gris:
        return todosIgualesAlInsertar(actuales, numero);
      case TipoReglaRegion.morado:
        return areaMorada(actuales, numero);
      case TipoReglaRegion.verde:
        return cualquierNumeroAlInsertar(actuales, numero);
      case TipoReglaRegion.amarillo:
      case TipoReglaRegion.rojo:
        return todosDiferentesAlInsertar(actuales, numero);
      case TipoReglaRegion.naranja1a3:
        return numeroEnRangoAlInsertar(
          actuales,
          numero,
          ConstantesServidor.minRangoNaranjaBajo,
          ConstantesServidor.maxRangoNaranjaBajo,
        );
      case TipoReglaRegion.naranja4a6:
        return numeroEnRangoAlInsertar(
          actuales,
          numero,
          ConstantesServidor.minRangoNaranjaAlto,
          ConstantesServidor.maxRangoNaranjaAlto,
        );
    }
  }
}

/// Coordenada pura e inmutable serializable en JSON.
class PosicionMapa {
  final int fila;
  final int columna;

  const PosicionMapa(this.fila, this.columna);

  String get clave => '$fila,$columna';

  factory PosicionMapa.desdeClave(String clave) {
    final partes = clave.split(',');
    if (partes.length != 2) {
      throw FormatException('Clave de posición inválida: $clave');
    }
    return PosicionMapa(int.parse(partes[0]), int.parse(partes[1]));
  }

  Map<String, dynamic> toJson() => {'fila': fila, 'columna': columna};

  factory PosicionMapa.fromJson(Map<String, dynamic> json) {
    return PosicionMapa(
      (json['fila'] as num).toInt(),
      (json['columna'] as num).toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PosicionMapa && fila == other.fila && columna == other.columna;

  @override
  int get hashCode => Object.hash(fila, columna);

  @override
  String toString() => '($fila, $columna)';
}

/// Definición pura de una región del mapa para validación autoritativa.
class DefinicionRegionMapa {
  final String id;
  final TipoReglaRegion regla;
  final Map<int, int> puntuaciones;
  final Set<PosicionMapa> posiciones;

  const DefinicionRegionMapa({
    required this.id,
    required this.regla,
    required this.puntuaciones,
    required this.posiciones,
  });
}

/// Esquema completo e inmutable de un tablero oficial 7x7.
class EsquemaMapa {
  final String id;
  final int numero;
  final String nombre;
  final List<DefinicionRegionMapa> regiones;
  final List<PosicionMapa> casillasIniciales;

  const EsquemaMapa({
    required this.id,
    required this.numero,
    required this.nombre,
    required this.regiones,
    required this.casillasIniciales,
  });

  DefinicionRegionMapa? regionPorPosicion(PosicionMapa pos) {
    for (final r in regiones) {
      if (r.posiciones.contains(pos)) return r;
    }
    return null;
  }

  DefinicionRegionMapa? regionPorId(String regionId) {
    for (final r in regiones) {
      if (r.id == regionId) return r;
    }
    return null;
  }
}

/// Estado inmutable del tablero 7x7 de un jugador individual en el servidor.
class TableroServidorJugador {
  final EsquemaMapa mapa;
  final Map<PosicionMapa, int> _valores;

  TableroServidorJugador({
    required this.mapa,
    Map<PosicionMapa, int>? valoresIniciales,
  }) : _valores = Map<PosicionMapa, int>.from(valoresIniciales ?? const {});

  Map<PosicionMapa, int> get valores => Map.unmodifiable(_valores);

  int get cantidadOcupadas => _valores.length;

  bool get estaLleno =>
      _valores.length >= ConstantesServidor.totalCasillasTablero;

  bool estaOcupada(PosicionMapa pos) => _valores.containsKey(pos);

  int? valorEn(PosicionMapa pos) => _valores[pos];

  List<int> valoresEnRegion(DefinicionRegionMapa region) {
    final resultado = <int>[];
    for (final pos in region.posiciones) {
      final v = _valores[pos];
      if (v != null) resultado.add(v);
    }
    return resultado;
  }

  bool esRegionCompleta(DefinicionRegionMapa region) {
    return region.posiciones.every(_valores.containsKey);
  }

  Set<String> idsRegionesCompletas() {
    final ids = <String>{};
    for (final r in mapa.regiones) {
      if (esRegionCompleta(r)) ids.add(r.id);
    }
    return ids;
  }

  List<PosicionMapa> vecinosOrtogonales(PosicionMapa c) {
    const dim = ConstantesServidor.dimensionTablero;
    final candidatos = [
      PosicionMapa(c.fila - 1, c.columna),
      PosicionMapa(c.fila + 1, c.columna),
      PosicionMapa(c.fila, c.columna - 1),
      PosicionMapa(c.fila, c.columna + 1),
    ];
    return candidatos
        .where(
          (p) => p.fila >= 0 && p.fila < dim && p.columna >= 0 && p.columna < dim,
        )
        .toList();
  }

  bool esJugadaLegal({
    required PosicionMapa ancla,
    required PosicionMapa destino,
    required int dado1,
    required int dado2,
    required int valorAColocar,
  }) {
    final valorAncla = _valores[ancla];
    if (valorAncla == null) return false;
    if (_valores.containsKey(destino)) return false;

    final parValido =
        (valorAncla == dado1 && valorAColocar == dado2) ||
        (valorAncla == dado2 && valorAColocar == dado1);
    if (!parValido) return false;

    if (!vecinosOrtogonales(ancla).contains(destino)) return false;

    final region = mapa.regionPorPosicion(destino);
    if (region == null) return false;

    final actuales = valoresEnRegion(region);
    return region.regla.permiteInsertar(actuales, valorAColocar);
  }

  bool tieneAlgunaJugadaPosible(int dado1, int dado2) {
    for (final entry in _valores.entries) {
      final ancla = entry.key;
      final valorAncla = entry.value;
      if (valorAncla == dado1 && _puedeColocarJuntoA(ancla, dado2)) {
        return true;
      }
      if (valorAncla == dado2 && _puedeColocarJuntoA(ancla, dado1)) {
        return true;
      }
    }
    return false;
  }

  bool _puedeColocarJuntoA(PosicionMapa ancla, int numero) {
    for (final vecino in vecinosOrtogonales(ancla)) {
      if (_valores.containsKey(vecino)) continue;
      final region = mapa.regionPorPosicion(vecino);
      if (region != null &&
          region.regla.permiteInsertar(valoresEnRegion(region), numero)) {
        return true;
      }
    }
    return false;
  }

  TableroServidorJugador colocarValorDirecto(PosicionMapa pos, int valor) {
    final copia = Map<PosicionMapa, int>.from(_valores);
    copia[pos] = valor;
    return TableroServidorJugador(mapa: mapa, valoresIniciales: copia);
  }
}

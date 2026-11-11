import 'modelos_mapa.dart';

/// Catálogo puro de los 4 tableros oficiales de Brilliant (sin dependencias gráficas)
/// para validación autoritativa en el servidor.
class CatalogoEsquemasMapa {
  CatalogoEsquemasMapa._();

  static final EsquemaMapa nivel1 = EsquemaMapa(
    id: 'nivel_1',
    numero: 1,
    nombre: 'Nivel 1',
    regiones: [
      DefinicionRegionMapa(
        id: 'azul_1',
        regla: TipoReglaRegion.azul,
        puntuaciones: const {1: 7, 2: 5, 3: 3},
        posiciones: {
          const PosicionMapa(0, 2),
          const PosicionMapa(1, 2),
          const PosicionMapa(1, 3),
          const PosicionMapa(2, 3),
        },
      ),
      DefinicionRegionMapa(
        id: 'azul_2',
        regla: TipoReglaRegion.azul,
        puntuaciones: const {1: 7, 2: 5, 3: 3},
        posiciones: {
          const PosicionMapa(4, 6),
          const PosicionMapa(5, 5),
          const PosicionMapa(5, 6),
          const PosicionMapa(6, 5),
        },
      ),
      DefinicionRegionMapa(
        id: 'morado_1',
        regla: TipoReglaRegion.morado,
        puntuaciones: const {1: 6, 2: 4, 3: 2},
        posiciones: {
          const PosicionMapa(0, 3),
          const PosicionMapa(0, 4),
          const PosicionMapa(0, 5),
          const PosicionMapa(1, 4),
          const PosicionMapa(1, 5),
          const PosicionMapa(2, 4),
        },
      ),
      DefinicionRegionMapa(
        id: 'morado_2',
        regla: TipoReglaRegion.morado,
        puntuaciones: const {1: 6, 2: 4, 3: 2},
        posiciones: {
          const PosicionMapa(3, 2),
          const PosicionMapa(4, 2),
          const PosicionMapa(4, 3),
          const PosicionMapa(5, 2),
          const PosicionMapa(6, 1),
          const PosicionMapa(6, 2),
        },
      ),
      DefinicionRegionMapa(
        id: 'rojo_1',
        regla: TipoReglaRegion.rojo,
        puntuaciones: const {1: 6, 2: 4, 3: 2},
        posiciones: {
          const PosicionMapa(2, 1),
          const PosicionMapa(2, 2),
          const PosicionMapa(3, 1),
          const PosicionMapa(4, 1),
          const PosicionMapa(5, 0),
          const PosicionMapa(5, 1),
        },
      ),
      DefinicionRegionMapa(
        id: 'rojo_2',
        regla: TipoReglaRegion.rojo,
        puntuaciones: const {1: 6, 2: 4, 3: 2},
        posiciones: {
          const PosicionMapa(4, 4),
          const PosicionMapa(4, 5),
          const PosicionMapa(5, 3),
          const PosicionMapa(5, 4),
          const PosicionMapa(6, 3),
          const PosicionMapa(6, 4),
        },
      ),
      DefinicionRegionMapa(
        id: 'verde_1',
        regla: TipoReglaRegion.verde,
        puntuaciones: const {1: 4, 2: 3, 3: 2},
        posiciones: {
          const PosicionMapa(0, 1),
          const PosicionMapa(1, 0),
          const PosicionMapa(1, 1),
          const PosicionMapa(2, 0),
          const PosicionMapa(3, 0),
          const PosicionMapa(4, 0),
        },
      ),
      DefinicionRegionMapa(
        id: 'verde_2',
        regla: TipoReglaRegion.verde,
        puntuaciones: const {1: 4, 2: 3, 3: 2},
        posiciones: {
          const PosicionMapa(1, 6),
          const PosicionMapa(2, 5),
          const PosicionMapa(2, 6),
          const PosicionMapa(3, 4),
          const PosicionMapa(3, 5),
          const PosicionMapa(3, 6),
        },
      ),
      DefinicionRegionMapa(
        id: 'amarillo_1',
        regla: TipoReglaRegion.amarillo,
        puntuaciones: const {1: 8, 2: 6, 3: 4},
        posiciones: {
          const PosicionMapa(0, 0),
          const PosicionMapa(0, 6),
          const PosicionMapa(3, 3),
          const PosicionMapa(6, 0),
          const PosicionMapa(6, 6),
        },
      ),
    ],
    casillasIniciales: const [
      PosicionMapa(1, 2),
      PosicionMapa(1, 5),
      PosicionMapa(3, 1),
      PosicionMapa(3, 4),
      PosicionMapa(5, 2),
      PosicionMapa(6, 4),
    ],
  );

  static final EsquemaMapa nivel2 = EsquemaMapa(
    id: 'nivel_2',
    numero: 2,
    nombre: 'Nivel 2',
    regiones: [
      DefinicionRegionMapa(
        id: 'morado_1',
        regla: TipoReglaRegion.morado,
        puntuaciones: const {1: 6, 2: 4, 3: 2},
        posiciones: {
          const PosicionMapa(0, 0),
          const PosicionMapa(0, 1),
          const PosicionMapa(0, 2),
          const PosicionMapa(1, 0),
          const PosicionMapa(2, 0),
        },
      ),
      DefinicionRegionMapa(
        id: 'morado_2',
        regla: TipoReglaRegion.morado,
        puntuaciones: const {1: 6, 2: 4, 3: 2},
        posiciones: {
          const PosicionMapa(4, 6),
          const PosicionMapa(5, 6),
          const PosicionMapa(6, 4),
          const PosicionMapa(6, 5),
          const PosicionMapa(6, 6),
        },
      ),
      DefinicionRegionMapa(
        id: 'verde_1',
        regla: TipoReglaRegion.verde,
        puntuaciones: const {1: 4, 2: 3, 3: 2},
        posiciones: {
          const PosicionMapa(0, 4),
          const PosicionMapa(0, 5),
          const PosicionMapa(0, 6),
          const PosicionMapa(1, 6),
          const PosicionMapa(2, 6),
        },
      ),
      DefinicionRegionMapa(
        id: 'verde_2',
        regla: TipoReglaRegion.verde,
        puntuaciones: const {1: 4, 2: 3, 3: 2},
        posiciones: {
          const PosicionMapa(4, 0),
          const PosicionMapa(5, 0),
          const PosicionMapa(6, 0),
          const PosicionMapa(6, 1),
          const PosicionMapa(6, 2),
        },
      ),
      DefinicionRegionMapa(
        id: 'amarillo_1',
        regla: TipoReglaRegion.amarillo,
        puntuaciones: const {1: 6, 2: 4, 3: 2},
        posiciones: {
          const PosicionMapa(1, 1),
          const PosicionMapa(1, 5),
          const PosicionMapa(3, 3),
          const PosicionMapa(5, 1),
          const PosicionMapa(5, 5),
        },
      ),
      DefinicionRegionMapa(
        id: 'gris_1',
        regla: TipoReglaRegion.gris,
        puntuaciones: const {1: 3, 2: 2, 3: 1},
        posiciones: {
          const PosicionMapa(0, 3),
          const PosicionMapa(6, 3),
        },
      ),
      DefinicionRegionMapa(
        id: 'azul_1',
        regla: TipoReglaRegion.azul,
        puntuaciones: const {1: 7, 2: 5, 3: 3},
        posiciones: {
          const PosicionMapa(1, 2),
          const PosicionMapa(1, 3),
          const PosicionMapa(1, 4),
          const PosicionMapa(2, 3),
        },
      ),
      DefinicionRegionMapa(
        id: 'azul_2',
        regla: TipoReglaRegion.azul,
        puntuaciones: const {1: 7, 2: 5, 3: 3},
        posiciones: {
          const PosicionMapa(4, 3),
          const PosicionMapa(5, 2),
          const PosicionMapa(5, 3),
          const PosicionMapa(5, 4),
        },
      ),
      DefinicionRegionMapa(
        id: 'rojo_1',
        regla: TipoReglaRegion.rojo,
        puntuaciones: const {1: 6, 2: 4, 3: 2},
        posiciones: {
          const PosicionMapa(2, 1),
          const PosicionMapa(2, 2),
          const PosicionMapa(3, 0),
          const PosicionMapa(3, 1),
          const PosicionMapa(3, 2),
          const PosicionMapa(4, 1),
          const PosicionMapa(4, 2),
        },
      ),
      DefinicionRegionMapa(
        id: 'rojo_2',
        regla: TipoReglaRegion.rojo,
        puntuaciones: const {1: 6, 2: 4, 3: 2},
        posiciones: {
          const PosicionMapa(2, 4),
          const PosicionMapa(2, 5),
          const PosicionMapa(3, 4),
          const PosicionMapa(3, 5),
          const PosicionMapa(3, 6),
          const PosicionMapa(4, 4),
          const PosicionMapa(4, 5),
        },
      ),
    ],
    casillasIniciales: const [
      PosicionMapa(0, 4),
      PosicionMapa(2, 0),
      PosicionMapa(3, 2),
      PosicionMapa(4, 5),
      PosicionMapa(5, 1),
      PosicionMapa(6, 4),
    ],
  );

  static final EsquemaMapa nivel3 = EsquemaMapa(
    id: 'nivel_3',
    numero: 3,
    nombre: 'Nivel 3',
    regiones: [
      DefinicionRegionMapa(
        id: 'amarillo_1',
        regla: TipoReglaRegion.amarillo,
        puntuaciones: const {1: 7, 2: 5, 3: 3},
        posiciones: {
          const PosicionMapa(0, 0),
          const PosicionMapa(0, 1),
          const PosicionMapa(1, 1),
          const PosicionMapa(0, 5),
          const PosicionMapa(0, 6),
          const PosicionMapa(1, 5),
        },
      ),
      DefinicionRegionMapa(
        id: 'morado_1',
        regla: TipoReglaRegion.morado,
        puntuaciones: const {1: 7, 2: 5, 3: 3},
        posiciones: {
          const PosicionMapa(0, 2),
          const PosicionMapa(0, 4),
          const PosicionMapa(1, 2),
          const PosicionMapa(1, 3),
          const PosicionMapa(1, 4),
          const PosicionMapa(2, 3),
        },
      ),
      DefinicionRegionMapa(
        id: 'morado_2',
        regla: TipoReglaRegion.morado,
        puntuaciones: const {1: 7, 2: 5, 3: 3},
        posiciones: {
          const PosicionMapa(6, 0),
          const PosicionMapa(6, 1),
          const PosicionMapa(6, 2),
          const PosicionMapa(6, 4),
          const PosicionMapa(6, 5),
          const PosicionMapa(6, 6),
        },
      ),
      DefinicionRegionMapa(
        id: 'rojo_1',
        regla: TipoReglaRegion.rojo,
        puntuaciones: const {1: 6, 2: 4, 3: 2},
        posiciones: {
          const PosicionMapa(2, 0),
          const PosicionMapa(2, 1),
          const PosicionMapa(2, 2),
          const PosicionMapa(3, 0),
          const PosicionMapa(3, 1),
          const PosicionMapa(3, 2),
        },
      ),
      DefinicionRegionMapa(
        id: 'rojo_2',
        regla: TipoReglaRegion.rojo,
        puntuaciones: const {1: 6, 2: 4, 3: 2},
        posiciones: {
          const PosicionMapa(2, 4),
          const PosicionMapa(2, 5),
          const PosicionMapa(2, 6),
          const PosicionMapa(3, 4),
          const PosicionMapa(3, 5),
          const PosicionMapa(3, 6),
        },
      ),
      DefinicionRegionMapa(
        id: 'azul_1',
        regla: TipoReglaRegion.azul,
        puntuaciones: const {1: 7, 2: 5, 3: 3},
        posiciones: {
          const PosicionMapa(4, 1),
          const PosicionMapa(4, 2),
          const PosicionMapa(4, 3),
          const PosicionMapa(4, 4),
          const PosicionMapa(4, 5),
        },
      ),
      DefinicionRegionMapa(
        id: 'verde_1',
        regla: TipoReglaRegion.verde,
        puntuaciones: const {1: 6, 2: 5, 3: 4},
        posiciones: {
          const PosicionMapa(4, 0),
          const PosicionMapa(4, 6),
          const PosicionMapa(5, 0),
          const PosicionMapa(5, 1),
          const PosicionMapa(5, 2),
          const PosicionMapa(5, 3),
          const PosicionMapa(5, 4),
          const PosicionMapa(5, 5),
          const PosicionMapa(5, 6),
        },
      ),
      DefinicionRegionMapa(
        id: 'gris_1',
        regla: TipoReglaRegion.gris,
        puntuaciones: const {1: 8, 2: 6, 3: 4},
        posiciones: {
          const PosicionMapa(0, 3),
          const PosicionMapa(1, 0),
          const PosicionMapa(1, 6),
          const PosicionMapa(3, 3),
          const PosicionMapa(6, 3),
        },
      ),
    ],
    casillasIniciales: const [
      PosicionMapa(1, 2),
      PosicionMapa(1, 5),
      PosicionMapa(3, 3),
      PosicionMapa(4, 1),
      PosicionMapa(4, 6),
      PosicionMapa(6, 2),
    ],
  );

  static final EsquemaMapa nivel4 = EsquemaMapa(
    id: 'nivel_4',
    numero: 4,
    nombre: 'Nivel 4',
    regiones: [
      DefinicionRegionMapa(
        id: 'naranja_4_6',
        regla: TipoReglaRegion.naranja4a6,
        puntuaciones: const {1: 6, 2: 4, 3: 3},
        posiciones: {
          const PosicionMapa(0, 0),
          const PosicionMapa(0, 1),
          const PosicionMapa(0, 2),
          const PosicionMapa(0, 3),
          const PosicionMapa(0, 4),
          const PosicionMapa(0, 5),
          const PosicionMapa(0, 6),
        },
      ),
      DefinicionRegionMapa(
        id: 'naranja_1_3',
        regla: TipoReglaRegion.naranja1a3,
        puntuaciones: const {1: 6, 2: 4, 3: 3},
        posiciones: {
          const PosicionMapa(6, 0),
          const PosicionMapa(6, 1),
          const PosicionMapa(6, 2),
          const PosicionMapa(6, 3),
          const PosicionMapa(6, 4),
          const PosicionMapa(6, 5),
          const PosicionMapa(6, 6),
        },
      ),
      DefinicionRegionMapa(
        id: 'amarillo_1',
        regla: TipoReglaRegion.amarillo,
        puntuaciones: const {1: 8, 2: 6, 3: 4},
        posiciones: {
          const PosicionMapa(1, 0),
          const PosicionMapa(2, 0),
          const PosicionMapa(3, 0),
          const PosicionMapa(4, 0),
          const PosicionMapa(5, 0),
        },
      ),
      DefinicionRegionMapa(
        id: 'amarillo_2',
        regla: TipoReglaRegion.amarillo,
        puntuaciones: const {1: 8, 2: 6, 3: 4},
        posiciones: {
          const PosicionMapa(1, 6),
          const PosicionMapa(2, 6),
          const PosicionMapa(3, 6),
          const PosicionMapa(4, 6),
          const PosicionMapa(5, 6),
        },
      ),
      DefinicionRegionMapa(
        id: 'rojo_1',
        regla: TipoReglaRegion.rojo,
        puntuaciones: const {1: 6, 2: 4, 3: 2},
        posiciones: {
          const PosicionMapa(1, 1),
          const PosicionMapa(2, 1),
          const PosicionMapa(4, 1),
          const PosicionMapa(5, 1),
        },
      ),
      DefinicionRegionMapa(
        id: 'rojo_2',
        regla: TipoReglaRegion.rojo,
        puntuaciones: const {1: 6, 2: 4, 3: 2},
        posiciones: {
          const PosicionMapa(1, 5),
          const PosicionMapa(2, 5),
          const PosicionMapa(4, 5),
          const PosicionMapa(5, 5),
        },
      ),
      DefinicionRegionMapa(
        id: 'verde_1',
        regla: TipoReglaRegion.verde,
        puntuaciones: const {1: 3, 2: 2, 3: 1},
        posiciones: {
          const PosicionMapa(1, 3),
          const PosicionMapa(3, 1),
          const PosicionMapa(3, 5),
          const PosicionMapa(5, 3),
        },
      ),
      DefinicionRegionMapa(
        id: 'morado_1',
        regla: TipoReglaRegion.morado,
        puntuaciones: const {1: 7, 2: 5, 3: 3},
        posiciones: {
          const PosicionMapa(2, 2),
          const PosicionMapa(2, 3),
          const PosicionMapa(2, 4),
          const PosicionMapa(3, 3),
          const PosicionMapa(4, 2),
          const PosicionMapa(4, 3),
          const PosicionMapa(4, 4),
        },
      ),
      DefinicionRegionMapa(
        id: 'azul_1',
        regla: TipoReglaRegion.azul,
        puntuaciones: const {1: 8, 2: 6, 3: 4},
        posiciones: {
          const PosicionMapa(1, 2),
          const PosicionMapa(1, 4),
          const PosicionMapa(3, 2),
          const PosicionMapa(3, 4),
          const PosicionMapa(5, 2),
          const PosicionMapa(5, 4),
        },
      ),
    ],
    casillasIniciales: const [
      PosicionMapa(0, 4),
      PosicionMapa(2, 2),
      PosicionMapa(2, 5),
      PosicionMapa(3, 0),
      PosicionMapa(5, 4),
      PosicionMapa(6, 1),
    ],
  );

  static final List<EsquemaMapa> todos = [
    nivel1,
    nivel2,
    nivel3,
    nivel4,
  ];

  static EsquemaMapa? porIdONull(String id) {
    for (final m in todos) {
      if (m.id == id) return m;
    }
    return null;
  }

  static EsquemaMapa porId(String id) => porIdONull(id) ?? nivel1;
}

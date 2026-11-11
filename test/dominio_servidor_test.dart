import 'package:test/test.dart';

import 'package:servidor_brilliant/constantes_servidor.dart';
import 'package:servidor_brilliant/dominio/catalogo_esquemas_mapa.dart';
import 'package:servidor_brilliant/dominio/estado_sala.dart';
import 'package:servidor_brilliant/dominio/estados_sala.dart';
import 'package:servidor_brilliant/dominio/jugador_sala.dart';
import 'package:servidor_brilliant/dominio/mensajes_protocolo.dart';
import 'package:servidor_brilliant/dominio/modelos_mapa.dart';
import 'package:servidor_brilliant/dominio/motor_puntuacion_carrera.dart';

void main() {
  group('Dominio del Servidor - Mapas, Reglas y Puntuación de Carrera', () {
    test('Los 4 mapas oficiales cubren exactamente las 49 casillas (7x7) sin huecos ni traslapes y tienen 6 estrellas', () {
      expect(CatalogoEsquemasMapa.todos.length, 4);

      for (final mapa in CatalogoEsquemasMapa.todos) {
        final vistas = <PosicionMapa>{};
        for (final region in mapa.regiones) {
          expect(region.posiciones, isNotEmpty);
          expect(region.puntuaciones.containsKey(1), isTrue);
          expect(region.puntuaciones.containsKey(2), isTrue);
          expect(region.puntuaciones.containsKey(3), isTrue);

          for (final pos in region.posiciones) {
            expect(pos.fila, inInclusiveRange(0, 6));
            expect(pos.columna, inInclusiveRange(0, 6));
            expect(
              vistas.add(pos),
              isTrue,
              reason: 'Casilla duplicada $pos en ${mapa.id}',
            );
          }
        }

        expect(
          vistas.length,
          ConstantesServidor.totalCasillasTablero,
          reason: '${mapa.id} debe cubrir las 49 casillas',
        );
        expect(
          mapa.casillasIniciales.toSet().length,
          ConstantesServidor.cantidadEstrellasIniciales,
        );
      }
    });

    test('Reglas de región y TableroServidorJugador validan adyacencia, dados y restricciones', () {
      expect(TipoReglaRegion.azul.permiteInsertar([4, 4], 4), isTrue);
      expect(TipoReglaRegion.azul.permiteInsertar([4, 4], 2), isFalse);
      expect(TipoReglaRegion.morado.permiteInsertar([1, 3], 3), isTrue);
      expect(TipoReglaRegion.morado.permiteInsertar([1, 3], 5), isFalse);
      expect(TipoReglaRegion.rojo.permiteInsertar([2, 5], 4), isTrue);
      expect(TipoReglaRegion.rojo.permiteInsertar([2, 5], 2), isFalse);
      expect(TipoReglaRegion.naranja1a3.permiteInsertar([], 3), isTrue);
      expect(TipoReglaRegion.naranja1a3.permiteInsertar([], 4), isFalse);
      expect(TipoReglaRegion.naranja4a6.permiteInsertar([], 4), isTrue);
      expect(TipoReglaRegion.naranja4a6.permiteInsertar([], 3), isFalse);

      final tablero = TableroServidorJugador(
        mapa: CatalogoEsquemasMapa.nivel1,
        valoresIniciales: {const PosicionMapa(1, 2): 4}, // en azul_1
      );

      // (0,2) es vecino ortogonal de (1,2) dentro de azul_1 -> exige otro 4
      expect(
        tablero.esJugadaLegal(
          ancla: const PosicionMapa(1, 2),
          destino: const PosicionMapa(0, 2),
          dado1: 4,
          dado2: 4,
          valorAColocar: 4,
        ),
        isTrue,
      );
      expect(
        tablero.esJugadaLegal(
          ancla: const PosicionMapa(1, 2),
          destino: const PosicionMapa(0, 2),
          dado1: 4,
          dado2: 5,
          valorAColocar: 5,
        ),
        isFalse,
      );
      // No ortogonal (diagonal) -> ilegal
      expect(
        tablero.esJugadaLegal(
          ancla: const PosicionMapa(1, 2),
          destino: const PosicionMapa(0, 1),
          dado1: 4,
          dado2: 5,
          valorAColocar: 5,
        ),
        isFalse,
      );
    });

    test('Metas oficiales de puntos escalan de 2 a 6 jugadores (26, 24, 22, 20)', () {
      expect(ConstantesServidor.obtenerMetaPuntos(2), 26);
      expect(ConstantesServidor.obtenerMetaPuntos(3), 24);
      expect(ConstantesServidor.obtenerMetaPuntos(4), 22);
      expect(ConstantesServidor.obtenerMetaPuntos(5), 20);
      expect(ConstantesServidor.obtenerMetaPuntos(6), 20);
    });

    test('MotorPuntuacionCarrera asigna 1º, 2º y del 3º al 6º lugar y resuelve empates simultáneos', () {
      final mapa = CatalogoEsquemasMapa.nivel1;
      var carrera = MotorPuntuacionCarrera.inicializarCarrera(mapa);
      var desglose = <String, Map<String, int>>{};
      const apodos = {
        'j1': 'Ana',
        'j2': 'Beto',
        'j3': 'Carla',
        'j4': 'Dani',
        'j5': 'Elena',
        'j6': 'Fabian',
      };

      // Ana y Beto completan azul_1 (7, 5, 3) en la misma ronda -> ambos reciben 7 y salta al 3º escalón
      var res = MotorPuntuacionCarrera.resolverCierreDeRonda(
        mapa: mapa,
        carreraActual: carrera,
        regionesCompletasTotalesPorJugador: {
          'j1': {'azul_1'},
          'j2': {'azul_1'},
          'j3': {},
        },
        desglosePrevioPorJugador: desglose,
        apodosPorJugador: apodos,
      );
      carrera = res.carreraActualizada;
      desglose = res.desglosePorJugador;
      expect(res.puntuacionTotalPorJugador['j1'], 7);
      expect(res.puntuacionTotalPorJugador['j2'], 7);
      expect(carrera['azul_1']!.escalonActual, 3);

      // Del 3º al 6º jugador completan azul_1 después -> todos reciben 3 pts sin agotarse
      res = MotorPuntuacionCarrera.resolverCierreDeRonda(
        mapa: mapa,
        carreraActual: carrera,
        regionesCompletasTotalesPorJugador: {
          'j1': {'azul_1'},
          'j2': {'azul_1'},
          'j3': {'azul_1'},
          'j4': {'azul_1'},
          'j5': {'azul_1'},
          'j6': {'azul_1'},
        },
        desglosePrevioPorJugador: desglose,
        apodosPorJugador: apodos,
      );
      expect(res.puntuacionTotalPorJugador['j3'], 3);
      expect(res.puntuacionTotalPorJugador['j4'], 3);
      expect(res.puntuacionTotalPorJugador['j5'], 3);
      expect(res.puntuacionTotalPorJugador['j6'], 3);
    });

    test('Protocolo JSON serializa y reconstruye ComandoCliente y EventoServidor sin pérdida', () {
      const comando = ComandoCliente(
        tipo: TipoComandoCliente.jugarTurno,
        solicitudId: 'sol_99',
        datos: {
          'ronda': 2,
          'ancla': {'fila': 1, 'columna': 2},
          'destino': {'fila': 1, 'columna': 3},
          'valorColocado': 4,
        },
      );
      final comandoReconstruido = ComandoCliente.fromJson(comando.toJson());
      expect(comandoReconstruido.tipo, TipoComandoCliente.jugarTurno);
      expect(comandoReconstruido.solicitudId, 'sol_99');

      final evento = EventoServidor(
        tipo: TipoEventoServidor.sesionEstablecida,
        solicitudId: 'sol_1',
        credencial: const CredencialSesionSala(
          codigoSala: 'K7M4P9',
          jugadorId: 'jug_1',
          tokenSesion: 'tok_abc',
          apodo: 'Fabian',
        ),
        estadoSala: EstadoSalaMultijugador(
          codigoSala: 'K7M4P9',
          miJugadorId: 'jug_1',
          fase: FaseSala.jugandoRondas,
          nivelId: 'nivel_4',
          rondaActual: 3,
          dado1: 2,
          dado2: 5,
          metaPuntos: 20,
          misValoresTablero: {const PosicionMapa(0, 4): 6},
          jugadores: const [
            ResumenJugador(
              id: 'jug_1',
              apodo: 'Fabian',
              esAnfitrion: true,
              estaListo: true,
              participacion: EstadoParticipacion.conectado,
            ),
          ],
        ),
      );

      final reconstruido = EventoServidor.fromJson(evento.toJson());
      expect(reconstruido.tipo, TipoEventoServidor.sesionEstablecida);
      expect(reconstruido.credencial?.codigoSala, 'K7M4P9');
      expect(
        reconstruido.estadoSala?.misValoresTablero[const PosicionMapa(0, 4)],
        6,
      );
    });
  });
}

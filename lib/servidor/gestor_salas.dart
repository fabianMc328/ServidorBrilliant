import 'dart:async';
import 'dart:math';

import '../constantes_servidor.dart';
import '../dominio/catalogo_esquemas_mapa.dart';
import '../dominio/estado_sala.dart';
import '../dominio/estados_sala.dart';
import '../dominio/jugador_sala.dart';
import '../dominio/mensajes_protocolo.dart';
import '../dominio/modelos_mapa.dart';
import '../dominio/motor_puntuacion_carrera.dart';

/// Configuración inyectable de temporizadores del servidor (facilita pruebas rápidas).
class ConfiguracionTiemposServidor {
  final int segundosFaseInicial;
  final int segundosPorRonda;
  final int segundosGraciaReconexionPartida;
  final int segundosGraciaReconexionLobby;
  final Duration intervaloTickReloj;

  const ConfiguracionTiemposServidor({
    this.segundosFaseInicial = ConstantesServidor.segundosFaseInicial,
    this.segundosPorRonda = ConstantesServidor.segundosPorRonda,
    this.segundosGraciaReconexionPartida =
        ConstantesServidor.segundosGraciaReconexionPartida,
    this.segundosGraciaReconexionLobby =
        ConstantesServidor.segundosGraciaReconexionLobby,
    this.intervaloTickReloj = const Duration(seconds: 1),
  });
}

typedef EnviarEventoJugador = void Function(
  String jugadorId,
  EventoServidor evento,
);

class _EstadoInternoJugador {
  final String id;
  final String tokenSesion;
  final String apodo;
  bool esAnfitrion;
  bool estaListo;
  EstadoParticipacion participacion;
  TableroServidorJugador tablero;
  Map<String, int> desglosePuntos;
  int puntuacionTotal;
  bool confirmoAccionActual;
  int? ticksGraciaRestantes;

  _EstadoInternoJugador({
    required this.id,
    required this.tokenSesion,
    required this.apodo,
    required this.esAnfitrion,
    required EsquemaMapa mapaInicial,
  })  : estaListo = false,
        participacion = EstadoParticipacion.conectado,
        tablero = TableroServidorJugador(mapa: mapaInicial),
        desglosePuntos = <String, int>{},
        puntuacionTotal = 0,
        confirmoAccionActual = false;

  ResumenJugador aResumen() {
    return ResumenJugador(
      id: id,
      apodo: apodo,
      esAnfitrion: esAnfitrion,
      estaListo: estaListo,
      participacion: participacion,
      puntuacion: puntuacionTotal,
      regionesCompletadas: tablero.idsRegionesCompletas().length,
      casillasOcupadas: tablero.cantidadOcupadas,
      confirmoAccionActual: confirmoAccionActual,
    );
  }
}

class _SalaActiva {
  final String codigo;
  FaseSala fase = FaseSala.enLobby;
  EsquemaMapa mapa;
  final List<_EstadoInternoJugador> jugadores = [];
  int rondaActual = 0;
  int? dado1;
  int? dado2;
  int segundosRestantes = 0;
  int metaPuntos = ConstantesServidor.metaPuntos2Jugadores;
  Map<String, EstadoCarreraRegion> carreraPorRegion = {};
  List<String> ganadoresIds = [];
  MotivoFinPartida? motivoFin;
  String? mensajeEventoReciente;
  bool huboJugadaEnRondaActual = false;
  int rondasConsecutivasSinJugadas = 0;

  _SalaActiva({
    required this.codigo,
    required this.mapa,
  });

  _EstadoInternoJugador? jugadorPorId(String id) {
    for (final j in jugadores) {
      if (j.id == id) return j;
    }
    return null;
  }

  List<_EstadoInternoJugador> get jugadoresEnCompetencia =>
      jugadores.where((j) => j.participacion.sigueEnCompetencia).toList();
}

/// Motor autoritativo de salas, lobbies, sincronización de rondas, concesión y reconexiones.
class GestorSalas {
  final EnviarEventoJugador _enviarA;
  final ConfiguracionTiemposServidor _tiempos;
  final Random _random;
  final Map<String, _SalaActiva> _salasPorCodigo = {};
  final Map<String, String> _codigoSalaPorJugador = {};
  Timer? _relojGlobal;
  int _secuenciaIds = 0;

  GestorSalas({
    required EnviarEventoJugador enviarEventoAJugador,
    ConfiguracionTiemposServidor tiempos = const ConfiguracionTiemposServidor(),
    Random? random,
  })  : _enviarA = enviarEventoAJugador,
        _tiempos = tiempos,
        _random = random ?? Random() {
    _relojGlobal =
        Timer.periodic(_tiempos.intervaloTickReloj, (_) => _procesarTick());
  }

  int get cantidadSalasActivas => _salasPorCodigo.length;

  CredencialSesionSala crearSala({
    required String apodo,
    String nivelId = 'nivel_1',
    String? solicitudId,
  }) {
    final apodoLimpio = _validarYLimpiarApodo(apodo);
    final mapa = CatalogoEsquemasMapa.porIdONull(nivelId);
    if (mapa == null) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.mapaInvalido,
        mensaje: 'El mapa seleccionado no existe.',
      );
    }

    final codigo = _generarCodigoSalaUnico();
    final sala = _SalaActiva(codigo: codigo, mapa: mapa);
    final jugador = _EstadoInternoJugador(
      id: _nuevoJugadorId(),
      tokenSesion: _nuevoTokenSesion(),
      apodo: apodoLimpio,
      esAnfitrion: true,
      mapaInicial: mapa,
    );

    sala.jugadores.add(jugador);
    sala.mensajeEventoReciente =
        'Sala $codigo creada. Invita hasta 6 jugadores.';
    _salasPorCodigo[codigo] = sala;
    _codigoSalaPorJugador[jugador.id] = codigo;

    final credencial = CredencialSesionSala(
      codigoSala: codigo,
      jugadorId: jugador.id,
      tokenSesion: jugador.tokenSesion,
      apodo: jugador.apodo,
    );

    _enviarA(
      jugador.id,
      EventoServidor(
        tipo: TipoEventoServidor.sesionEstablecida,
        solicitudId: solicitudId,
        credencial: credencial,
        estadoSala: _construirSnapshotPara(sala, jugador),
      ),
    );

    return credencial;
  }

  CredencialSesionSala unirseASala({
    required String codigoSala,
    required String apodo,
    String? solicitudId,
  }) {
    final codigoNormalizado = codigoSala.trim().toUpperCase();
    if (codigoNormalizado.length != ConstantesServidor.longitudCodigoSala) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.codigoInvalido,
        mensaje: 'El código de invitación debe tener 6 caracteres.',
      );
    }

    final sala = _salasPorCodigo[codigoNormalizado];
    if (sala == null) {
      throw FalloMultijugador(
        codigo: CodigoFalloMultijugador.salaNoEncontrada,
        mensaje:
            'No existe ninguna sala activa con el código $codigoNormalizado.',
      );
    }

    if (sala.fase != FaseSala.enLobby) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.partidaYaIniciada,
        mensaje: 'La partida en esta sala ya comenzó.',
      );
    }

    if (sala.jugadores.length >= ConstantesServidor.maxJugadoresSala) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.salaLlena,
        mensaje: 'La sala ya alcanzó el máximo de 6 jugadores.',
      );
    }

    final apodoLimpio = _validarYLimpiarApodo(apodo);
    final repetido = sala.jugadores.any(
      (j) => j.apodo.toLowerCase() == apodoLimpio.toLowerCase(),
    );
    if (repetido) {
      throw FalloMultijugador(
        codigo: CodigoFalloMultijugador.apodoEnUso,
        mensaje: 'El nombre "$apodoLimpio" ya está en uso dentro de esta sala.',
      );
    }

    final jugador = _EstadoInternoJugador(
      id: _nuevoJugadorId(),
      tokenSesion: _nuevoTokenSesion(),
      apodo: apodoLimpio,
      esAnfitrion: false,
      mapaInicial: sala.mapa,
    );

    sala.jugadores.add(jugador);
    sala.mensajeEventoReciente = '${jugador.apodo} se unió a la sala.';
    _codigoSalaPorJugador[jugador.id] = sala.codigo;

    final credencial = CredencialSesionSala(
      codigoSala: sala.codigo,
      jugadorId: jugador.id,
      tokenSesion: jugador.tokenSesion,
      apodo: jugador.apodo,
    );

    _enviarA(
      jugador.id,
      EventoServidor(
        tipo: TipoEventoServidor.sesionEstablecida,
        solicitudId: solicitudId,
        credencial: credencial,
        estadoSala: _construirSnapshotPara(sala, jugador),
      ),
    );

    _difundirEstadoSala(sala, excluirJugadorId: jugador.id);
    return credencial;
  }

  CredencialSesionSala reconectarJugador({
    required String codigoSala,
    required String jugadorId,
    required String tokenSesion,
    String? solicitudId,
  }) {
    final codigoNormalizado = codigoSala.trim().toUpperCase();
    final sala = _salasPorCodigo[codigoNormalizado];
    if (sala == null) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.sesionExpirada,
        mensaje: 'La sala ya no se encuentra activa.',
      );
    }

    final jugador = sala.jugadorPorId(jugadorId);
    if (jugador == null || jugador.tokenSesion != tokenSesion) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.sesionExpirada,
        mensaje: 'Tu sesión expiró o las credenciales no son válidas.',
      );
    }

    if (jugador.participacion == EstadoParticipacion.abandonado) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.sesionExpirada,
        mensaje: 'El tiempo límite de reconexión se agotó.',
      );
    }

    if (jugador.participacion == EstadoParticipacion.reconectando) {
      jugador.participacion = EstadoParticipacion.conectado;
    }
    jugador.ticksGraciaRestantes = null;
    sala.mensajeEventoReciente = '${jugador.apodo} recuperó la conexión.';

    final credencial = CredencialSesionSala(
      codigoSala: sala.codigo,
      jugadorId: jugador.id,
      tokenSesion: jugador.tokenSesion,
      apodo: jugador.apodo,
    );

    _enviarA(
      jugador.id,
      EventoServidor(
        tipo: TipoEventoServidor.sesionEstablecida,
        solicitudId: solicitudId,
        credencial: credencial,
        estadoSala: _construirSnapshotPara(sala, jugador),
      ),
    );

    _difundirEstadoSala(sala, excluirJugadorId: jugador.id);
    return credencial;
  }

  void seleccionarNivel({
    required String jugadorId,
    required String nivelId,
  }) {
    final (sala, jugador) = _obtenerContextoJugador(jugadorId);
    if (sala.fase != FaseSala.enLobby) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.partidaYaIniciada,
        mensaje: 'No se puede cambiar el mapa con la partida en curso.',
      );
    }
    if (!jugador.esAnfitrion) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.permisoDenegado,
        mensaje: 'Solo el anfitrión de la sala puede elegir el mapa.',
      );
    }

    final nuevoMapa = CatalogoEsquemasMapa.porIdONull(nivelId);
    if (nuevoMapa == null) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.mapaInvalido,
        mensaje: 'El nivel indicado no es válido.',
      );
    }

    if (sala.mapa.id == nuevoMapa.id) return;

    sala.mapa = nuevoMapa;
    for (final j in sala.jugadores) {
      j.tablero = TableroServidorJugador(mapa: nuevoMapa);
      if (!j.esAnfitrion) {
        j.estaListo = false;
      }
    }
    sala.mensajeEventoReciente =
        'Mapa cambiado a ${nuevoMapa.nombre}. Confirmen estar listos.';
    _difundirEstadoSala(sala);
  }

  void alternarListo({
    required String jugadorId,
    required bool listo,
  }) {
    final (sala, jugador) = _obtenerContextoJugador(jugadorId);
    if (sala.fase != FaseSala.enLobby) return;

    jugador.estaListo = listo;
    sala.mensajeEventoReciente = listo
        ? '${jugador.apodo} está listo.'
        : '${jugador.apodo} canceló su estado de listo.';
    _difundirEstadoSala(sala);
  }

  void iniciarPartida({required String jugadorId}) {
    final (sala, jugador) = _obtenerContextoJugador(jugadorId);
    if (sala.fase != FaseSala.enLobby) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.partidaYaIniciada,
        mensaje: 'La partida ya está en curso.',
      );
    }
    if (!jugador.esAnfitrion) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.permisoDenegado,
        mensaje: 'Solo el anfitrión puede iniciar la partida.',
      );
    }
    if (sala.jugadores.length < ConstantesServidor.minJugadoresPartida) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.jugadoresInsuficientes,
        mensaje: 'Se necesitan al menos 2 jugadores para iniciar.',
      );
    }
    final todosConectadosYListos = sala.jugadores.every(
      (j) => j.participacion.estaConectadoActivo && j.estaListo,
    );
    if (!todosConectadosYListos) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.noTodosListos,
        mensaje: 'Todos los jugadores deben pulsar "Listo" antes de iniciar.',
      );
    }

    sala.fase = FaseSala.configurandoIniciales;
    sala.metaPuntos =
        ConstantesServidor.obtenerMetaPuntos(sala.jugadores.length);
    sala.carreraPorRegion = MotorPuntuacionCarrera.inicializarCarrera(sala.mapa);
    sala.segundosRestantes = _tiempos.segundosFaseInicial;
    for (final j in sala.jugadores) {
      j.tablero = TableroServidorJugador(mapa: sala.mapa);
      j.desglosePuntos = {};
      j.puntuacionTotal = 0;
      j.confirmoAccionActual = false;
    }
    sala.mensajeEventoReciente =
        '¡Partida iniciada en ${sala.mapa.nombre}! Coloquen sus 6 estrellas.';
    _difundirEstadoSala(sala);
  }

  void confirmarValoresIniciales({
    required String jugadorId,
    required Map<PosicionMapa, int> valoresEstrellas,
  }) {
    final (sala, jugador) = _obtenerContextoJugador(jugadorId);
    if (sala.fase != FaseSala.configurandoIniciales) return;
    if (!jugador.participacion.sigueEnCompetencia) return;
    if (jugador.confirmoAccionActual) return;

    final estrellasOficiales = sala.mapa.casillasIniciales.toSet();
    if (valoresEstrellas.length !=
            ConstantesServidor.cantidadEstrellasIniciales ||
        !valoresEstrellas.keys.toSet().containsAll(estrellasOficiales)) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.jugadaInvalida,
        mensaje:
            'Debes colocar exactamente las 6 casillas iniciales con estrella.',
      );
    }

    final valoresUnicos = valoresEstrellas.values.toSet();
    final esperados = {
      for (int v = ConstantesServidor.valorMinimoDado;
          v <= ConstantesServidor.valorMaximoDado;
          v++)
        v,
    };
    if (valoresUnicos.length != ConstantesServidor.cantidadEstrellasIniciales ||
        !valoresUnicos.containsAll(esperados)) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.jugadaInvalida,
        mensaje: 'Los valores iniciales deben ser del 1 al 6 sin repetir.',
      );
    }

    jugador.tablero = TableroServidorJugador(
      mapa: sala.mapa,
      valoresIniciales: valoresEstrellas,
    );
    jugador.confirmoAccionActual = true;
    sala.mensajeEventoReciente = '${jugador.apodo} confirmó sus estrellas.';

    if (_todosEnCompetenciaConfirmaron(sala)) {
      _avanzarASiguienteRonda(sala, esPrimeraRonda: true);
    } else {
      _difundirEstadoSala(sala);
    }
  }

  void jugarTurno({
    required String jugadorId,
    required int ronda,
    required PosicionMapa ancla,
    required PosicionMapa destino,
    required int valorColocado,
  }) {
    final (sala, jugador) = _obtenerContextoJugador(jugadorId);
    if (sala.fase != FaseSala.jugandoRondas) return;
    if (!jugador.participacion.sigueEnCompetencia) return;
    if (ronda != sala.rondaActual || jugador.confirmoAccionActual) return;

    final d1 = sala.dado1;
    final d2 = sala.dado2;
    if (d1 == null || d2 == null) return;

    final legal = jugador.tablero.esJugadaLegal(
      ancla: ancla,
      destino: destino,
      dado1: d1,
      dado2: d2,
      valorAColocar: valorColocado,
    );
    if (!legal) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.jugadaInvalida,
        mensaje:
            'Jugada no permitida por las reglas del tablero o dados actuales.',
      );
    }

    jugador.tablero =
        jugador.tablero.colocarValorDirecto(destino, valorColocado);
    jugador.confirmoAccionActual = true;
    sala.huboJugadaEnRondaActual = true;

    if (_todosEnCompetenciaConfirmaron(sala)) {
      _cerrarRondaYEvaluar(sala);
    } else {
      _difundirEstadoSala(sala);
    }
  }

  void pasarTurno({
    required String jugadorId,
    required int ronda,
  }) {
    final (sala, jugador) = _obtenerContextoJugador(jugadorId);
    if (sala.fase != FaseSala.jugandoRondas) return;
    if (!jugador.participacion.sigueEnCompetencia) return;
    if (ronda != sala.rondaActual || jugador.confirmoAccionActual) return;

    jugador.confirmoAccionActual = true;

    if (_todosEnCompetenciaConfirmaron(sala)) {
      _cerrarRondaYEvaluar(sala);
    } else {
      _difundirEstadoSala(sala);
    }
  }

  void concederPartida({required String jugadorId}) {
    final (sala, jugador) = _obtenerContextoJugador(jugadorId);
    if (sala.fase != FaseSala.configurandoIniciales &&
        sala.fase != FaseSala.jugandoRondas) {
      return;
    }
    if (!jugador.participacion.sigueEnCompetencia) return;

    jugador.participacion = EstadoParticipacion.concedido;
    jugador.confirmoAccionActual = true;
    jugador.ticksGraciaRestantes = null;
    sala.mensajeEventoReciente = '${jugador.apodo} ha concedido la partida.';

    if (_verificarFinPorUnicoSobreviviente(
      sala,
      motivo: MotivoFinPartida.concesionRival,
    )) {
      return;
    }

    if (sala.fase == FaseSala.configurandoIniciales &&
        _todosEnCompetenciaConfirmaron(sala)) {
      _avanzarASiguienteRonda(sala, esPrimeraRonda: true);
    } else if (sala.fase == FaseSala.jugandoRondas &&
        _todosEnCompetenciaConfirmaron(sala)) {
      _cerrarRondaYEvaluar(sala);
    } else {
      _difundirEstadoSala(sala);
    }
  }

  void salirDeSala({required String jugadorId}) {
    final codigo = _codigoSalaPorJugador.remove(jugadorId);
    if (codigo == null) return;
    final sala = _salasPorCodigo[codigo];
    if (sala == null) return;

    if (sala.fase == FaseSala.enLobby) {
      _removerJugadorDeLobby(sala, jugadorId, motivo: 'salió de la sala.');
      return;
    }

    final jugador = sala.jugadorPorId(jugadorId);
    if (jugador != null && jugador.participacion.sigueEnCompetencia) {
      concederPartida(jugadorId: jugadorId);
    }
  }

  void notificarDesconexionAbrupta(String jugadorId) {
    final codigo = _codigoSalaPorJugador[jugadorId];
    if (codigo == null) return;
    final sala = _salasPorCodigo[codigo];
    if (sala == null) return;
    final jugador = sala.jugadorPorId(jugadorId);
    if (jugador == null) return;

    if (sala.fase == FaseSala.finalizada) return;

    if (sala.fase == FaseSala.enLobby) {
      jugador.participacion = EstadoParticipacion.reconectando;
      jugador.estaListo = false;
      jugador.ticksGraciaRestantes = _tiempos.segundosGraciaReconexionLobby;
      sala.mensajeEventoReciente =
          '${jugador.apodo} perdió conexión en el lobby. Esperando reconexión...';
      _difundirEstadoSala(sala, excluirJugadorId: jugadorId);
      return;
    }

    if (jugador.participacion == EstadoParticipacion.conectado) {
      jugador.participacion = EstadoParticipacion.reconectando;
      jugador.ticksGraciaRestantes = _tiempos.segundosGraciaReconexionPartida;
      sala.mensajeEventoReciente =
          '${jugador.apodo} se desconectó. Tiene ${_tiempos.segundosGraciaReconexionPartida}s para reconectar.';
      _difundirEstadoSala(sala, excluirJugadorId: jugadorId);
    }
  }

  void cerrar() {
    _relojGlobal?.cancel();
    _salasPorCodigo.clear();
    _codigoSalaPorJugador.clear();
  }

  // --- Lógica interna de reloj, tolerancia a fallos y resolución ---

  void _procesarTick() {
    final codigos = _salasPorCodigo.keys.toList();
    for (final codigo in codigos) {
      final sala = _salasPorCodigo[codigo];
      if (sala == null) continue;

      bool huboCambio = false;

      final copiaJugadores = List<_EstadoInternoJugador>.from(sala.jugadores);
      for (final j in copiaJugadores) {
        if (j.participacion == EstadoParticipacion.reconectando &&
            j.ticksGraciaRestantes != null) {
          j.ticksGraciaRestantes = j.ticksGraciaRestantes! - 1;
          if (j.ticksGraciaRestantes! <= 0) {
            j.ticksGraciaRestantes = null;
            if (sala.fase == FaseSala.enLobby) {
              _codigoSalaPorJugador.remove(j.id);
              _removerJugadorDeLobby(
                sala,
                j.id,
                motivo: 'se desconectó del lobby.',
              );
              huboCambio = false;
            } else if (sala.fase != FaseSala.finalizada) {
              j.participacion = EstadoParticipacion.abandonado;
              j.confirmoAccionActual = true;
              sala.mensajeEventoReciente =
                  '${j.apodo} abandonó la partida por desconexión.';
              if (_verificarFinPorUnicoSobreviviente(
                sala,
                motivo: MotivoFinPartida.abandonoRival,
              )) {
                huboCambio = false;
                break;
              }
              huboCambio = true;
            }
          }
        }
      }

      if (!_salasPorCodigo.containsKey(codigo)) continue;
      if (sala.fase == FaseSala.enLobby || sala.fase == FaseSala.finalizada) {
        if (huboCambio) _difundirEstadoSala(sala);
        continue;
      }

      if (sala.segundosRestantes > 0) {
        sala.segundosRestantes -= 1;
        huboCambio = true;
      }

      if (sala.fase == FaseSala.configurandoIniciales) {
        if (_todosEnCompetenciaConfirmaron(sala) ||
            sala.segundosRestantes <= 0) {
          _rellenarEstrellasFaltantesAutomaticamente(sala);
          _avanzarASiguienteRonda(sala, esPrimeraRonda: true);
          continue;
        }
      } else if (sala.fase == FaseSala.jugandoRondas) {
        if (_todosEnCompetenciaConfirmaron(sala) ||
            sala.segundosRestantes <= 0) {
          for (final j in sala.jugadoresEnCompetencia) {
            j.confirmoAccionActual = true;
          }
          _cerrarRondaYEvaluar(sala);
          continue;
        }
      }

      if (huboCambio) {
        _difundirEstadoSala(sala);
      }
    }
  }

  void _removerJugadorDeLobby(
    _SalaActiva sala,
    String jugadorId, {
    required String motivo,
  }) {
    final indice = sala.jugadores.indexWhere((j) => j.id == jugadorId);
    if (indice < 0) return;
    final saliente = sala.jugadores.removeAt(indice);

    if (sala.jugadores.isEmpty) {
      _salasPorCodigo.remove(sala.codigo);
      return;
    }

    if (saliente.esAnfitrion) {
      final nuevoHost = sala.jugadores.firstWhere(
        (j) => j.participacion.estaConectadoActivo,
        orElse: () => sala.jugadores.first,
      );
      nuevoHost.esAnfitrion = true;
      sala.mensajeEventoReciente =
          '${saliente.apodo} $motivo ${nuevoHost.apodo} es ahora el anfitrión.';
    } else {
      sala.mensajeEventoReciente = '${saliente.apodo} $motivo';
    }

    _difundirEstadoSala(sala);
  }

  void _rellenarEstrellasFaltantesAutomaticamente(_SalaActiva sala) {
    for (final j in sala.jugadoresEnCompetencia) {
      if (!j.confirmoAccionActual) {
        final numeros = [1, 2, 3, 4, 5, 6]..shuffle(_random);
        final generados = <PosicionMapa, int>{};
        for (int i = 0; i < sala.mapa.casillasIniciales.length; i++) {
          generados[sala.mapa.casillasIniciales[i]] = numeros[i];
        }
        j.tablero = TableroServidorJugador(
          mapa: sala.mapa,
          valoresIniciales: generados,
        );
        j.confirmoAccionActual = true;
      }
    }
  }

  void _avanzarASiguienteRonda(
    _SalaActiva sala, {
    required bool esPrimeraRonda,
    String? mensajePrevio,
  }) {
    sala.fase = FaseSala.jugandoRondas;
    sala.rondaActual = esPrimeraRonda ? 1 : sala.rondaActual + 1;
    sala.dado1 = _random.nextInt(ConstantesServidor.valorMaximoDado) + 1;
    sala.dado2 = _random.nextInt(ConstantesServidor.valorMaximoDado) + 1;
    sala.segundosRestantes = _tiempos.segundosPorRonda;
    sala.huboJugadaEnRondaActual = false;

    for (final j in sala.jugadores) {
      j.confirmoAccionActual = !j.participacion.sigueEnCompetencia;
    }

    sala.mensajeEventoReciente = mensajePrevio ??
        'Ronda ${sala.rondaActual}: salieron los dados ${sala.dado1} y ${sala.dado2}.';
    _difundirEstadoSala(sala);
  }

  void _cerrarRondaYEvaluar(_SalaActiva sala) {
    final enCompetencia = sala.jugadoresEnCompetencia;
    final completasPorJugador = <String, Set<String>>{
      for (final j in enCompetencia) j.id: j.tablero.idsRegionesCompletas(),
    };
    final desglosePrevio = <String, Map<String, int>>{
      for (final j in sala.jugadores) j.id: j.desglosePuntos,
    };
    final apodos = <String, String>{
      for (final j in sala.jugadores) j.id: j.apodo,
    };

    final resolucion = MotorPuntuacionCarrera.resolverCierreDeRonda(
      mapa: sala.mapa,
      carreraActual: sala.carreraPorRegion,
      regionesCompletasTotalesPorJugador: completasPorJugador,
      desglosePrevioPorJugador: desglosePrevio,
      apodosPorJugador: apodos,
    );

    sala.carreraPorRegion = resolucion.carreraActualizada;
    for (final j in sala.jugadores) {
      j.desglosePuntos = resolucion.desglosePorJugador[j.id] ?? {};
      j.puntuacionTotal =
          resolucion.puntuacionTotalPorJugador[j.id] ?? j.puntuacionTotal;
    }

    if (sala.huboJugadaEnRondaActual) {
      sala.rondasConsecutivasSinJugadas = 0;
    } else {
      sala.rondasConsecutivasSinJugadas += 1;
    }

    final idsCompetencia = enCompetencia.map((j) => j.id).toList();
    final puntajes = {for (final j in sala.jugadores) j.id: j.puntuacionTotal};

    final alcanzoMeta = MotorPuntuacionCarrera.alguienAlcanzoMeta(
      jugadoresEnCompetenciaIds: idsCompetencia,
      puntuaciones: puntajes,
      metaPuntos: sala.metaPuntos,
    );

    final todosLlenos = enCompetencia.every((j) => j.tablero.estaLleno);
    final agotadoPorInactividad = sala.rondasConsecutivasSinJugadas >=
            ConstantesServidor.maxRondasSinAvance ||
        sala.rondaActual >= ConstantesServidor.maxRondasSeguridad;

    if (alcanzoMeta || todosLlenos || agotadoPorInactividad) {
      sala.fase = FaseSala.finalizada;
      sala.segundosRestantes = 0;
      sala.motivoFin = alcanzoMeta
          ? MotivoFinPartida.metaPuntosAlcanzada
          : MotivoFinPartida.sinJugadasRestantes;
      sala.ganadoresIds = MotorPuntuacionCarrera.determinarGanadores(
        jugadoresElegiblesIds: idsCompetencia,
        puntuaciones: puntajes,
      );
      final nombresGanadores = sala.jugadores
          .where((j) => sala.ganadoresIds.contains(j.id))
          .map((j) => j.apodo)
          .join(' y ');
      sala.mensajeEventoReciente =
          '¡Partida finalizada! Ganador(es): $nombresGanadores.';
      _difundirEstadoSala(sala);
      return;
    }

    final resumenEventos = resolucion.eventosCompletadoRonda.isNotEmpty
        ? resolucion.eventosCompletadoRonda.join(' • ')
        : null;
    _avanzarASiguienteRonda(
      sala,
      esPrimeraRonda: false,
      mensajePrevio: resumenEventos,
    );
  }

  bool _verificarFinPorUnicoSobreviviente(
    _SalaActiva sala, {
    required MotivoFinPartida motivo,
  }) {
    final activos = sala.jugadoresEnCompetencia;
    if (activos.length <= 1) {
      sala.fase = FaseSala.finalizada;
      sala.segundosRestantes = 0;
      sala.motivoFin = motivo;
      sala.ganadoresIds = activos.map((j) => j.id).toList();
      if (activos.length == 1) {
        sala.mensajeEventoReciente =
            '¡${activos.first.apodo} gana la partida porque los demás rivales se retiraron!';
      }
      _difundirEstadoSala(sala);
      return true;
    }
    return false;
  }

  bool _todosEnCompetenciaConfirmaron(_SalaActiva sala) {
    final enCompetencia = sala.jugadoresEnCompetencia;
    if (enCompetencia.isEmpty) return false;
    return enCompetencia.every((j) => j.confirmoAccionActual);
  }

  EstadoSalaMultijugador _construirSnapshotPara(
    _SalaActiva sala,
    _EstadoInternoJugador receptor,
  ) {
    return EstadoSalaMultijugador(
      codigoSala: sala.codigo,
      miJugadorId: receptor.id,
      fase: sala.fase,
      nivelId: sala.mapa.id,
      jugadores: sala.jugadores.map((j) => j.aResumen()).toList(),
      rondaActual: sala.rondaActual,
      dado1: sala.dado1,
      dado2: sala.dado2,
      segundosRestantes: sala.segundosRestantes,
      metaPuntos: sala.metaPuntos,
      misValoresTablero: receptor.tablero.valores,
      miDesglosePuntos: Map<String, int>.from(receptor.desglosePuntos),
      carreraPorRegion:
          Map<String, EstadoCarreraRegion>.from(sala.carreraPorRegion),
      ganadoresIds: List<String>.from(sala.ganadoresIds),
      motivoFin: sala.motivoFin,
      mensajeEventoReciente: sala.mensajeEventoReciente,
    );
  }

  void _difundirEstadoSala(_SalaActiva sala, {String? excluirJugadorId}) {
    for (final j in sala.jugadores) {
      if (j.id == excluirJugadorId) continue;
      if (!j.participacion.estaConectadoActivo) continue;
      _enviarA(
        j.id,
        EventoServidor(
          tipo: TipoEventoServidor.actualizacionSala,
          estadoSala: _construirSnapshotPara(sala, j),
        ),
      );
    }
  }

  (_SalaActiva, _EstadoInternoJugador) _obtenerContextoJugador(
    String jugadorId,
  ) {
    final codigo = _codigoSalaPorJugador[jugadorId];
    if (codigo == null) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.salaNoEncontrada,
        mensaje: 'No perteneces a ninguna sala activa.',
      );
    }
    final sala = _salasPorCodigo[codigo];
    final jugador = sala?.jugadorPorId(jugadorId);
    if (sala == null || jugador == null) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.sesionExpirada,
        mensaje: 'La sala ya no existe.',
      );
    }
    return (sala, jugador);
  }

  String _validarYLimpiarApodo(String apodo) {
    final limpio = apodo.trim();
    if (limpio.length < ConstantesServidor.minLongitudApodo ||
        limpio.length > ConstantesServidor.maxLongitudApodo) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.apodoInvalido,
        mensaje: 'El apodo debe tener entre 2 y 18 caracteres.',
      );
    }
    return limpio;
  }

  String _generarCodigoSalaUnico() {
    const alfabeto = ConstantesServidor.alfabetoCodigoSala;
    while (true) {
      final buffer = StringBuffer();
      for (int i = 0; i < ConstantesServidor.longitudCodigoSala; i++) {
        buffer.write(alfabeto[_random.nextInt(alfabeto.length)]);
      }
      final candidato = buffer.toString();
      if (!_salasPorCodigo.containsKey(candidato)) {
        return candidato;
      }
    }
  }

  String _nuevoJugadorId() {
    _secuenciaIds += 1;
    return 'jug_${_secuenciaIds}_${_random.nextInt(900000) + 100000}';
  }

  String _nuevoTokenSesion() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final buffer = StringBuffer();
    for (int i = 0; i < ConstantesServidor.longitudTokenSesion; i++) {
      buffer.write(chars[_random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }
}

/// Fase global en la que se encuentra la sala multijugador.
enum FaseSala {
  enLobby,
  configurandoIniciales,
  jugandoRondas,
  finalizada;

  static FaseSala desdeNombre(String nombre) {
    return FaseSala.values.firstWhere(
      (e) => e.name == nombre,
      orElse: () => FaseSala.enLobby,
    );
  }
}

/// Estado de participación y presencia de un jugador en la sala/partida.
enum EstadoParticipacion {
  conectado,
  reconectando,
  concedido,
  abandonado;

  bool get sigueEnCompetencia =>
      this == EstadoParticipacion.conectado ||
      this == EstadoParticipacion.reconectando;

  bool get estaConectadoActivo => this == EstadoParticipacion.conectado;

  static EstadoParticipacion desdeNombre(String nombre) {
    return EstadoParticipacion.values.firstWhere(
      (e) => e.name == nombre,
      orElse: () => EstadoParticipacion.conectado,
    );
  }
}

/// Motivo por el cual concluyó una partida multijugador.
enum MotivoFinPartida {
  metaPuntosAlcanzada,
  concesionRival,
  abandonoRival,
  sinJugadasRestantes;

  static MotivoFinPartida? desdeNombreONull(String? nombre) {
    if (nombre == null) return null;
    for (final m in MotivoFinPartida.values) {
      if (m.name == nombre) return m;
    }
    return null;
  }
}

/// Códigos tipados de error en operaciones de red, lobby y jugabilidad.
enum CodigoFalloMultijugador {
  sinConexionServidor,
  tiempoEsperaAgotado,
  codigoInvalido,
  salaNoEncontrada,
  salaLlena,
  partidaYaIniciada,
  apodoInvalido,
  apodoEnUso,
  permisoDenegado,
  jugadoresInsuficientes,
  noTodosListos,
  mapaInvalido,
  jugadaInvalida,
  sesionExpirada,
  mensajeMalformado,
  desconocido;

  static CodigoFalloMultijugador desdeNombre(String nombre) {
    return CodigoFalloMultijugador.values.firstWhere(
      (e) => e.name == nombre,
      orElse: () => CodigoFalloMultijugador.desconocido,
    );
  }
}

/// Excepción inmutable y descriptiva de fallos del protocolo multijugador.
class FalloMultijugador implements Exception {
  final CodigoFalloMultijugador codigo;
  final String mensaje;

  const FalloMultijugador({
    required this.codigo,
    required this.mensaje,
  });

  Map<String, dynamic> toJson() => {
        'codigo': codigo.name,
        'mensaje': mensaje,
      };

  factory FalloMultijugador.fromJson(Map<String, dynamic> json) {
    return FalloMultijugador(
      codigo: CodigoFalloMultijugador.desdeNombre(
        (json['codigo'] as String?) ?? '',
      ),
      mensaje: (json['mensaje'] as String?) ?? 'Ocurrió un error inesperado.',
    );
  }

  @override
  String toString() => 'FalloMultijugador(${codigo.name}: $mensaje)';
}

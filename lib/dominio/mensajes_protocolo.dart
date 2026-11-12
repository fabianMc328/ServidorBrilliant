import 'estado_sala.dart';
import 'estados_sala.dart';
import 'modelos_mapa.dart';

/// Tipos de comandos enviados desde el cliente hacia el servidor WebSocket.
enum TipoComandoCliente {
  crearSala,
  unirseSala,
  reconectarSala,
  salirSala,
  seleccionarNivel,
  alternarListo,
  iniciarPartida,
  confirmarIniciales,
  jugarTurno,
  pasarTurno,
  concederPartida,
  enviarMensajeChat,
  ping;

  static TipoComandoCliente? desdeNombre(String? nombre) {
    if (nombre == null) return null;
    for (final c in TipoComandoCliente.values) {
      if (c.name == nombre) return c;
    }
    return null;
  }
}

/// Tipos de eventos emitidos desde el servidor WebSocket hacia el cliente.
enum TipoEventoServidor {
  sesionEstablecida,
  actualizacionSala,
  mensajeChatRecibido,
  errorOperacion,
  pong;

  static TipoEventoServidor? desdeNombre(String? nombre) {
    if (nombre == null) return null;
    for (final e in TipoEventoServidor.values) {
      if (e.name == nombre) return e;
    }
    return null;
  }
}

/// Mensaje estructurado Cliente -> Servidor.
class ComandoCliente {
  final TipoComandoCliente tipo;
  final String? solicitudId;
  final Map<String, dynamic> datos;

  const ComandoCliente({
    required this.tipo,
    this.solicitudId,
    this.datos = const {},
  });

  Map<String, dynamic> toJson() => {
        'tipo': tipo.name,
        if (solicitudId != null) 'solicitudId': solicitudId,
        'datos': datos,
      };

  factory ComandoCliente.fromJson(Map<String, dynamic> json) {
    final tipo = TipoComandoCliente.desdeNombre(json['tipo'] as String?);
    if (tipo == null) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.mensajeMalformado,
        mensaje: 'Tipo de comando desconocido.',
      );
    }
    return ComandoCliente(
      tipo: tipo,
      solicitudId: json['solicitudId'] as String?,
      datos: (json['datos'] as Map<String, dynamic>?) ?? const {},
    );
  }

  static Map<String, int> serializarMapaPosiciones(
    Map<PosicionMapa, int> valores,
  ) {
    return {
      for (final e in valores.entries) e.key.clave: e.value,
    };
  }

  static Map<PosicionMapa, int> deserializarMapaPosiciones(
    Map<String, dynamic> raw,
  ) {
    final mapa = <PosicionMapa, int>{};
    for (final e in raw.entries) {
      mapa[PosicionMapa.desdeClave(e.key)] = (e.value as num).toInt();
    }
    return mapa;
  }
}

/// Credenciales ligeras de sesión para reconexión transparente ante caídas de red.
class CredencialSesionSala {
  final String codigoSala;
  final String jugadorId;
  final String tokenSesion;
  final String apodo;

  const CredencialSesionSala({
    required this.codigoSala,
    required this.jugadorId,
    required this.tokenSesion,
    required this.apodo,
  });

  Map<String, dynamic> toJson() => {
        'codigoSala': codigoSala,
        'jugadorId': jugadorId,
        'tokenSesion': tokenSesion,
        'apodo': apodo,
      };

  factory CredencialSesionSala.fromJson(Map<String, dynamic> json) {
    return CredencialSesionSala(
      codigoSala: json['codigoSala'] as String,
      jugadorId: json['jugadorId'] as String,
      tokenSesion: json['tokenSesion'] as String,
      apodo: json['apodo'] as String,
    );
  }
}

/// Mensaje de chat en tiempo real dentro de una sala multijugador.
class MensajeChat {
  final String id;
  final String codigoSala;
  final String remitenteId;
  final String remitenteApodo;
  final String texto;
  final DateTime fecha;
  final bool esSistema;

  const MensajeChat({
    required this.id,
    required this.codigoSala,
    required this.remitenteId,
    required this.remitenteApodo,
    required this.texto,
    required this.fecha,
    this.esSistema = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'codigoSala': codigoSala,
        'remitenteId': remitenteId,
        'remitenteApodo': remitenteApodo,
        'texto': texto,
        'fecha': fecha.toIso8601String(),
        'esSistema': esSistema,
      };

  factory MensajeChat.fromJson(Map<String, dynamic> json) {
    return MensajeChat(
      id: json['id'] as String,
      codigoSala: json['codigoSala'] as String,
      remitenteId: json['remitenteId'] as String,
      remitenteApodo: json['remitenteApodo'] as String,
      texto: json['texto'] as String,
      fecha:
          DateTime.tryParse(json['fecha'] as String? ?? '') ?? DateTime.now(),
      esSistema: (json['esSistema'] as bool?) ?? false,
    );
  }
}

/// Mensaje estructurado Servidor -> Cliente.
class EventoServidor {
  final TipoEventoServidor tipo;
  final String? solicitudId;
  final CredencialSesionSala? credencial;
  final EstadoSalaMultijugador? estadoSala;
  final MensajeChat? mensajeChat;
  final FalloMultijugador? fallo;

  const EventoServidor({
    required this.tipo,
    this.solicitudId,
    this.credencial,
    this.estadoSala,
    this.mensajeChat,
    this.fallo,
  });

  Map<String, dynamic> toJson() => {
        'tipo': tipo.name,
        if (solicitudId != null) 'solicitudId': solicitudId,
        if (credencial != null) 'credencial': credencial!.toJson(),
        if (estadoSala != null) 'estadoSala': estadoSala!.toJson(),
        if (mensajeChat != null) 'mensajeChat': mensajeChat!.toJson(),
        if (fallo != null) 'fallo': fallo!.toJson(),
      };

  factory EventoServidor.fromJson(Map<String, dynamic> json) {
    final tipo = TipoEventoServidor.desdeNombre(json['tipo'] as String?);
    if (tipo == null) {
      throw const FalloMultijugador(
        codigo: CodigoFalloMultijugador.mensajeMalformado,
        mensaje: 'Evento del servidor inválido.',
      );
    }
    return EventoServidor(
      tipo: tipo,
      solicitudId: json['solicitudId'] as String?,
      credencial: json['credencial'] != null
          ? CredencialSesionSala.fromJson(
              json['credencial'] as Map<String, dynamic>,
            )
          : null,
      estadoSala: json['estadoSala'] != null
          ? EstadoSalaMultijugador.fromJson(
              json['estadoSala'] as Map<String, dynamic>,
            )
          : null,
      mensajeChat: json['mensajeChat'] != null
          ? MensajeChat.fromJson(
              json['mensajeChat'] as Map<String, dynamic>,
            )
          : null,
      fallo: json['fallo'] != null
          ? FalloMultijugador.fromJson(json['fallo'] as Map<String, dynamic>)
          : null,
    );
  }
}

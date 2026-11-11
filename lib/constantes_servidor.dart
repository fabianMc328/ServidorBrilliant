/// Constantes explícitas del servidor multijugador Brilliant (cero números mágicos).
class ConstantesServidor {
  ConstantesServidor._();

  // Límites de sala y jugadores
  static const int minJugadoresPartida = 2;
  static const int maxJugadoresSala = 6;
  static const int longitudCodigoSala = 6;
  static const String alfabetoCodigoSala = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int minLongitudApodo = 2;
  static const int maxLongitudApodo = 18;
  static const int longitudTokenSesion = 24;

  // Geometría y dados del juego
  static const int dimensionTablero = 7;
  static const int totalCasillasTablero = 49;
  static const int cantidadEstrellasIniciales = 6;
  static const int valorMinimoDado = 1;
  static const int valorMaximoDado = 6;
  static const int minRangoNaranjaBajo = 1;
  static const int maxRangoNaranjaBajo = 3;
  static const int minRangoNaranjaAlto = 4;
  static const int maxRangoNaranjaAlto = 6;

  // Escalones de carrera oficial por región
  static const int escalonPrimero = 1;
  static const int escalonSegundo = 2;
  static const int escalonTerceroOMas = 3;

  // Metas de puntuación oficiales de Brilliant según número de jugadores
  static const int metaPuntos2Jugadores = 26;
  static const int metaPuntos3Jugadores = 24;
  static const int metaPuntos4Jugadores = 22;
  static const int metaPuntos5o6Jugadores = 20;

  // Red, temporizadores y tolerancia a desconexiones
  static const int puertoPorDefecto = 8080;
  static const int segundosFaseInicial = 60;
  static const int segundosPorRonda = 45;
  static const int segundosGraciaReconexionPartida = 45;
  static const int segundosGraciaReconexionLobby = 20;
  static const Duration intervaloHeartbeat = Duration(seconds: 5);
  static const int maxRondasSeguridad = 60;
  static const int maxRondasSinAvance = 5;

  /// Retorna el umbral oficial de puntos que dispara el fin de partida.
  static int obtenerMetaPuntos(int cantidadJugadores) {
    if (cantidadJugadores <= 2) return metaPuntos2Jugadores;
    if (cantidadJugadores == 3) return metaPuntos3Jugadores;
    if (cantidadJugadores == 4) return metaPuntos4Jugadores;
    return metaPuntos5o6Jugadores;
  }
}

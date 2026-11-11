# Servidor Multijugador Brilliant (`servidorBrilliant`)

Servidor WebSocket autoritativo desarrollado desde cero en **Dart puro** (bajo principios SOLID, inmutabilidad y cero números mágicos) para coordinar partidas multijugador de **2 a 6 jugadores** del juego **Brilliant**.

- **Ruta del Servidor:** `C:\Users\fabia\OneDrive\Desktop\servidorBrilliant`
- **Cliente Flutter Asociado:** `C:\Users\fabia\OneDrive\Desktop\brilliant`
- **Documentación de Contexto y Protocolo:** `C:\Users\fabia\OneDrive\Desktop\contexto brillian\contextoservidorbrilliant.md`

## 🚀 Cómo levantar el servidor

```powershell
dart pub get
dart run bin/servidor_brilliant.dart
```

Por defecto escucha en el puerto `8080` (puedes pasar otro puerto opcional, ej. `dart run bin/servidor_brilliant.dart 9090`):
- **PC / Web (Chrome) / Windows:** `ws://localhost:8080`
- **Emulador Android:** `ws://10.0.2.2:8080`
- **Celulares físicos en la misma red Wi-Fi:** `ws://<TU_IP_LAN>:8080` (se muestra en consola al arrancar)
- **Healthcheck HTTP:** `http://localhost:8080/salud`

## 🗂️ Estructura Interna
- `bin/servidor_brilliant.dart`: Ejecutable CLI.
- `lib/constantes_servidor.dart`: Constantes explícitas de sala, dados, metas y tiempos.
- `lib/dominio/`: Reglas puras, catálogo de los 4 mapas oficiales 7x7 (`CatalogoEsquemasMapa`), motor competitivo de carrera (`MotorPuntuacionCarrera`) y protocolo JSON (`ComandoCliente` / `EventoServidor`).
- `lib/servidor/`: `GestorSalas` (máquina autoritativa de salas, reloj por ronda, concesión, reconexión y *Host Migration*) y `ServidorWebsocketBrilliant`.

## ✨ Funcionalidades Principales
- **Lobby e invitación por código:** Códigos únicos de 6 caracteres (sin `0/O` ni `1/I`) para salas de 2 a 6 jugadores.
- **Mismo mapa y Botón "Listo" obligatorio:** Sincronización de los 4 niveles oficiales; la partida solo arranca cuando el 100% de los jugadores conectados presionan "Listo".
- **Rondas simultáneas y Carrera de Puntuación Oficial:** Mismos 2 dados para todos, reloj por ronda *anti-softlock*, escalones `1.º`, `2.º` y `3.º+` por región y metas oficiales (`26`, `24`, `22` y `20` puntos).
- **Tolerancia a desconexiones y Concesión:** Ventana de gracia con `tokenSesion` para reconexión transparente, *Host Migration* en el lobby y soporte para conceder la partida.

## 🧪 Pruebas y Calidad (18/18 pruebas al 100%, 0 warnings)

```powershell
dart analyze
dart test
```

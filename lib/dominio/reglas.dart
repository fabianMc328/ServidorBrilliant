/// Reglas matemáticas puras de colocación de números por región para Brilliant.
library;

/// Regla Azul / Gris: Todos los números en la región deben ser IGUALES.
bool todosIgualesAlInsertar(List<int> lista, int numeroAInsertar) {
  if (lista.isEmpty) {
    return true;
  }
  return lista.every((elemento) => elemento == numeroAInsertar);
}

/// Regla Amarillo / Rojo: Todos los números en la región deben ser DISTINTOS.
bool todosDiferentesAlInsertar(List<int> lista, int numeroAInsertar) {
  if (lista.contains(numeroAInsertar)) {
    return false;
  }
  final elementosUnicos = lista.toSet();
  return elementosUnicos.length == lista.length;
}

/// Regla Morado: Puede haber como máximo 2 valores distintos en la región.
bool areaMorada(List<int> lista, int numeroAInsertar) {
  final elementosUnicos = {...lista, numeroAInsertar};
  return elementosUnicos.length <= 2;
}

/// Regla Verde: Puede ser cualquier número.
bool cualquierNumeroAlInsertar(List<int> lista, int numeroAInsertar) {
  return true;
}

/// Regla Naranja: El número debe encontrarse dentro del rango [min, max].
bool numeroEnRangoAlInsertar(
  List<int> lista,
  int numeroAInsertar,
  int min,
  int max,
) {
  return numeroAInsertar >= min && numeroAInsertar <= max;
}

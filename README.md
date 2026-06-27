# WoW Classic Channel Guild

Addon para WoW Classic Season of Discovery que construye una interfaz social tipo guild a partir del canal custom `SODBALAST`.

## Objetivo

Mostrar en una misma ventana a todos los jugadores presentes en el canal, aunque no tengan el addon, y enriquecer con informacion adicional a los que si lo tengan instalado.

## Principios de diseño

- La presencia sale del roster real del canal.
- Los datos ricos viajan por `addon whisper`, no por el canal.
- La UI debe ser util desde la primera version, aunque falten perfiles.
- La persistencia es local con `SavedVariables`.

## Estado

Documentacion inicial creada y scaffold del addon arrancado.

## Documentos

- `docs/product-spec.md`: alcance funcional y reglas del producto.
- `docs/architecture.md`: arquitectura tecnica y modelo de datos.
- `docs/implementation-plan.md`: orden de trabajo y entregas.
- `docs/sync-cycles.md`: ciclos de sincronizacion y reconciliacion de roster/chat.
- `docs/manual-testing.md`: pruebas manuales recomendadas para validar el addon.

## Unit Testing

Hay una suite minima de tests fuera del juego en `tests/` para validar logica pura de `History`, `Store` y `Comm`.

Ejecucion:

```text
lua tests/test_runner.lua
```

Requiere tener un interprete `lua` disponible en local. La suite usa mocks pequenos del entorno WoW y no intenta cubrir UI ni APIs reales de Blizzard.

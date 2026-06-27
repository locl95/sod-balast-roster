# WoW Classic Channel Guild

Addon para WoW Classic Season of Discovery que construye una interfaz social tipo guild a partir del canal custom `SODBALAST`.

## Objetivo

Mostrar en una misma ventana a todos los jugadores presentes en el canal, aunque no tengan el addon, y enriquecer con informacion adicional a los que si lo tengan instalado.

## Principios de diseño

- La presencia no depende del roster detallado del canal en SoD.
- Para peers con addon, la presencia fiable sale del trafico addon (`INFO`/`HELLO`/`BYE`) y del heartbeat.
- Para peers sin addon, la presencia es best effort a partir de eventos del canal, mensajes visibles y `/who` manual.
- Los datos ricos viajan por `addon whisper`, no por el canal.
- La UI debe ser util desde la primera version, aunque falten perfiles.
- La persistencia es local con `SavedVariables`.

## Estado

Addon funcional con sincronizacion de perfil, roster enriquecido, reconciliacion de chat y presencia por heartbeat addon.

## Documentos

- `docs/product-spec.md`: alcance funcional y reglas del producto.
- `docs/architecture.md`: arquitectura tecnica y modelo de datos.
- `docs/implementation-plan.md`: orden de trabajo y entregas.
- `docs/sync-cycles.md`: ciclos de sincronizacion y reconciliacion de roster/chat.
- `docs/manual-testing.md`: pruebas manuales recomendadas para validar el addon.

## Unit Testing

Hay una suite minima de tests fuera del juego en `tests/` para validar logica pura de `History`, `Store`, `Comm` y `Channel`.

Ejecucion:

```text
lua tests/test_runner.lua
```

Requiere tener un interprete `lua` disponible en local. La suite usa mocks pequenos del entorno WoW y no intenta cubrir UI ni APIs reales de Blizzard.

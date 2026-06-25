# Implementation Plan

## Fase 0

Base documental y decisiones cerradas.

Entregables:

- alcance funcional
- arquitectura tecnica
- orden de trabajo

## Fase 1

Scaffold del addon.

Entregables:

- carpeta del addon
- `.toc`
- archivos base Lua
- `SavedVariables`
- slash command minima

## Fase 2

Canal y presencia.

Entregables:

- `JoinPermanentChannel("SODBALAST")`
- deteccion de `channel id`
- localizacion del `display index`
- lectura del roster del canal
- marcado online offline
- historico de entradas y salidas

## Fase 3

Sincronizacion de perfil.

Entregables:

- prefijo registrado
- manejo de `CHAT_MSG_ADDON`
- cola de requests por whisper
- mensajes `REQ` e `INFO`
- enriquecimiento del roster con perfil remoto

## Fase 4

UI inicial.

Entregables:

- ventana principal
- lista de roster
- filtros basicos
- acciones whisper e invite
- contador online total

## Fase 5

Historico y pulido.

Entregables:

- tab de historico
- cambios de nivel zona guild
- persistencia de posicion y filtros de UI
- mejoras de ordenacion y refresco manual

## Checklist tecnico detallado

### Scaffold

- crear `.toc`
- crear modulos `Core`, `Utils`, `Store`, `History`, `Channel`, `Comm`, `UI`
- inicializar namespace comun

### Store

- definir esquema minimo de DB
- helpers `GetMember`, `UpsertMember`, `SetProfile`
- helpers de UI state

### Channel

- `EnsureJoined`
- `GetChannelId`
- `FindDisplayIndexForChannel`
- `ScanRoster`
- diff contra roster previo

### Comm

- `RegisterPrefix`
- `QueueProfileRequest`
- `FlushRequestQueue`
- `HandleAddonMessage`
- `SendInfo`

### UI

- `CreateMainFrame`
- `RefreshRoster`
- `RefreshHistory`
- filtros y tabs

## Pruebas manuales previstas

1. Cliente A y B con addon en el canal.
2. Cliente C sin addon en el canal.
3. Verificar que:
   - A y B se ven con perfil rico
   - C aparece sin perfil rico
   - salir del canal genera evento
   - `reload` mantiene datos
   - filtros funcionan

## Orden recomendado de inicio de implementacion

1. Fase 1
2. Fase 2
3. Validacion manual del roster del canal
4. Fase 3
5. Fase 4
6. Fase 5

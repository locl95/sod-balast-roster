# Architecture

## Restriccion tecnica clave

En WoW Classic no se puede usar `C_ChatInfo.SendAddonMessage(..., "CHANNEL", ...)` para canales custom. Por eso el canal `SODBALAST` no puede ser el transporte directo del protocolo del addon.

Ademas, en Season of Discovery el roster detallado del canal no es una base fiable para construir presencia completa. El addon puede localizar el canal y su `display index`, pero no depende de resolver el roster completo por API para detectar peers online/offline.

## Enfoque tecnico

El addon se divide en tres planos:

1. Presencia
   - para peers con addon sale del trafico addon y de un heartbeat ligero por `WHISPER`
   - para peers sin addon es best effort desde `CHAT_MSG_CHANNEL_NOTICE`, `CHAT_MSG_CHANNEL` y `/who` manual
2. Perfil
   - se sincroniza entre clientes con `addon whispers`
3. Chat
   - se reconcilia entre peers con addon usando summaries y deltas

## Modulos

### Core

Responsable de inicializacion, eventos globales, slash commands y ciclo de actualizacion ligero.

### Utils

Funciones pequeñas reutilizables:

- normalizacion de nombres
- lectura segura de zona y guild
- utilidades de tiempo y parseo

### Store

Responsable del estado local persistente:

- roster conocido
- flags de presencia observada
- estado de heartbeat addon
- perfil enriquecido
- preferencias UI

### History

Responsable de registrar eventos resumidos y de recortar el historico.

### Channel

Responsable de:

- unirse al canal `SODBALAST`
- localizar su `channel id`
- encontrar su `display index`
- detectar si el canal esta visible
- ejecutar mantenimiento periodico ligado al canal
- disparar timeouts de presencia addon durante los scans

### Comm

Responsable de:

- registrar el prefijo del addon
- manejar `REQ`, `HELLO`, `INFO`, `RSUM`, `RREQ`, `RPRO`, `CSUM`, `CREQ`, `CMSG`, `BYE`
- enviar whispers con cola y rate limit
- actualizar el store con perfiles y presencia addon
- ejecutar heartbeat de peers con addon

### UI

Responsable de la ventana principal, filtros, tabs y render del roster e historico.

### Notify

Responsable de notificar el primer avistamiento de cada jugador durante la sesion actual (sonido + linea en el chat local, con el nombre como link de jugador clicable). El estado de "ya notificado" vive solo en memoria (se recrea en cada carga del addon), nunca en `SavedVariables`.

El descubrimiento del roster que ya estaba online al loguear no llega de golpe (whispers de bootstrap limitados a 1/s, listas de peers reenviadas, rescans), asi que el arranque usa un calentamiento adaptativo en vez de un temporizador fijo: cada avistamiento durante el arranque pospone el inicio de notificaciones (`QUIET_WINDOW_SECONDS`) hasta que hay un hueco de silencio real, con un techo duro (`MAX_WARMUP_SECONDS`) para no bloquear notificaciones legitimas si el canal esta muy activo. Los avistamientos que llegan juntos (dentro de `COALESCE_WINDOW`) se agrupan en un unico sonido/linea en vez de encadenar uno por uno.

## Modelo de datos

```lua
member = {
  name = "Player",
  isOnlineInChannel = true,
  hasAddon = true,
  firstSeenAt = 0,
  lastSeenAt = 0,
  lastObservedAt = 0,
  lastAddonSeenAt = 0,
  pendingAddonProbe = false,
  missedAddonProbes = 0,
  lastProfileAt = 0,
  lastUpdatedAt = 0,
  level = 14,
  classFile = "WARRIOR",
  zone = "The Barrens",
  guildName = "Fresh-07",
  spec = "Arms",
  specIcon = 136241,
}
```

```lua
historyEvent = {
  type = "joined_channel",
  name = "Player",
  at = 0,
  details = nil,
}
```

## Persistencia

`SavedVariables` contienen:

- `roster`
- `history`
- `ui`
- `historyMeta`
- `minimap`

## Protocolo addon

Prefijo: `SBRoster`

Mensajes activos:

- `REQ;4`
- `HELLO;4;player`
- `INFO;4;name;level;class;zone;guild;prof1;prof2;prof1Icon;prof2Icon;latestChatAt;peerList;spec;specIcon`
- `RSUM;4;player;latestRosterUpdatedAt;countRecent`
- `RREQ;4;sinceTimestamp`
- `RPRO;4;...;spec;specIcon`
- `CSUM;4;player;latestChatAt;countRecent;oldestAt;firstId;lastId`
- `CREQ;4;sinceTimestamp`
- `CMSG;4;...`
- `BYE;4;player`

### REQ

Se envia por `WHISPER` cuando:

- se descubre un peer con addon por notice/chat/sync
- no hay perfil local
- el perfil local esta caducado

### HELLO

Se envia por `WHISPER` como heartbeat ligero cuando un peer con addon lleva demasiado tiempo sin trafico addon.

El receptor responde con `INFO`.

### INFO

Se responde por `WHISPER` con el perfil vivo del jugador local y el ultimo timestamp de chat conocido.

`spec`/`specIcon` viajan como campos opcionales al final del payload (igual en `RPRO`): se autoreportan como las profesiones (arbol de talentos con mas puntos gastados, sin `GetSpecialization`, inexistente en Classic/SoD) y no requieren bump de `protocolVersion`: un emisor nuevo con un receptor viejo simplemente ignora los campos sobrantes, y un receptor nuevo con un emisor viejo los trata como vacios.

### RSUM / RREQ / RPRO

Implementan reconciliacion ligera del roster enriquecido entre peers con addon.

### CSUM / CREQ / CMSG

Implementan reconciliacion ligera del chat entre peers con addon.

`CSUM` no compara solo `latestChatAt`; tambien anuncia la ventana reciente (`count`, `oldestAt`, `firstId`, `lastId`) para detectar historiales divergentes.

### BYE

Se envia al cerrar sesion para marcar offline rapido a peers con addon cuando el cliente sale limpiamente.

## Frecuencias

- scan de mantenimiento del canal: cada `scanInterval`
- heartbeat addon: cuando un peer addon lleva `addonProbeTimeout` sin trafico addon y hasta `partialMissingThreshold` fallos antes de marcar offline
- peticiones de perfil: maximo 1 whisper por segundo
- TTL de perfil: `profileTTL`

## Flujo principal

1. Login o entering world.
2. Asegurar union al canal `SODBALAST`.
3. Refrescar el perfil local.
4. Ejecutar bootstrap de sync (`RSUM` y `CSUM`) contra pocos donors.
5. Marcar peers vistos por notice/chat/addon y enriquecer con `REQ`/`INFO`.
6. Mantener presencia addon con `HELLO` periodico y `BYE` al logout.
7. Reconciliar deltas de roster/chat solo cuando los summaries lo justifican.
8. Refrescar UI.

## Discovery actual

### Peer con addon

Un peer se descubre como peer con addon cuando llega cualquier `CHAT_MSG_ADDON` con prefijo valido.

En ese momento:

1. `Store.MarkAddonSeen()` lo marca online y con addon.
2. `REQ` y `HELLO` fuerzan respuesta `INFO`.
3. `INFO` actualiza perfil vivo.
4. `RSUM` y `CSUM` pueden disparar pulls de roster/chat.

### Jugador sin addon

Un jugador sin addon solo se descubre de forma best effort por:

1. `CHAT_MSG_CHANNEL_NOTICE` (`JOINED`, `LEFT`, `YOU_CHANGED`)
2. `CHAT_MSG_CHANNEL`
3. `/who` manual

No existe presencia fiable por heartbeat para este grupo.

## Riesgos tecnicos

1. La presencia de usuarios sin addon sigue siendo best effort.
2. Resolver correctamente el `display index` del canal custom.
3. Controlar bien el rate limit de whispers para evitar spam.
4. Manejar nombres con realm si aparecen con formatos distintos.

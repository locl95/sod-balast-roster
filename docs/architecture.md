# Architecture

## Restriccion tecnica clave

En WoW Classic no se puede usar `C_ChatInfo.SendAddonMessage(..., "CHANNEL", ...)` para canales custom. Por eso el canal `SODBALAST` no puede ser el transporte directo del protocolo del addon.

## Enfoque tecnico

El addon se divide en dos planos:

1. Presencia
   - sale del roster real del canal `SODBALAST`
2. Perfil
   - se sincroniza entre clientes con `addon whispers`

## Modulos previstos

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
- flags de presencia
- perfil enriquecido
- preferencias UI

### History

Responsable de registrar eventos resumidos y de recortar el historico.

### Channel

Responsable de:

- unirse al canal `SODBALAST`
- localizar su `channel id`
- encontrar su `display index`
- leer el roster del canal
- calcular altas y bajas

### Comm

Responsable de:

- registrar el prefijo del addon
- manejar `REQ` e `INFO`
- enviar whispers con cola y rate limit
- actualizar el store con los perfiles recibidos

### UI

Responsable de la ventana principal, filtros, tabs y render del roster e historico.

## Modelo de datos

```lua
member = {
  name = "Player",
  isOnlineInChannel = true,
  hasAddon = true,
  firstSeenAt = 0,
  lastSeenAt = 0,
  lastProfileAt = 0,
  level = 14,
  classFile = "WARRIOR",
  zone = "The Barrens",
  guildName = "Fresh-07",
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

`SavedVariables` contendran:

- `roster`
- `history`
- `ui`
- metadatos de version si hacen falta mas adelante

## Protocolo addon

Prefijo tentativo: `SBRoster`

Mensajes de V1:

- `REQ;1`
- `INFO;1;name;level;class;zone;guild`

### REQ

Se envia por `WHISPER` cuando:

- se descubre un jugador nuevo en el canal
- no hay perfil local
- el perfil local esta caducado

### INFO

Se responde por `WHISPER` con el perfil del jugador local.

## Frecuencias

- escaneo de roster del canal: cada 20-30 segundos
- peticiones de perfil: maximo 1 whisper por segundo
- TTL de perfil: 10-15 minutos

## Flujo principal

1. Login o entering world.
2. Asegurar union al canal `SODBALAST`.
3. Escanear roster del canal.
4. Marcar presencia y registrar diffs.
5. Encolar `REQ` para jugadores sin perfil fresco.
6. Recibir `INFO` y enriquecer roster.
7. Refrescar UI.

## Riesgos tecnicos

1. Validar que el roster del canal se puede consultar de forma fiable en SoD.
2. Resolver correctamente el `display index` del canal custom.
3. Controlar bien el rate limit de whispers para evitar spam.
4. Manejar nombres con realm si aparecen con formatos distintos.

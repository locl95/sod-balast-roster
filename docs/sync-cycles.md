# Sync Cycles

## Objetivo

El addon sincroniza dos entidades distintas entre peers con addon:

1. `Roster`
2. `Chat`

Ambas siguen el mismo patron general:

1. detectar peers validos
2. intercambiar summaries ligeras
3. pedir deltas solo si aportan valor
4. mergear localmente

No se hace full sync continuo entre todos los peers online.

## Principios

- La presencia de peers con addon sale del propio trafico addon y de un heartbeat ligero.
- La presencia de jugadores sin addon es best effort y no depende de resolver el roster completo del canal.
- El perfil rico se intercambia por `addon whisper`.
- La reconciliacion fuerte ocurre en bootstrap, no todo el tiempo.
- Los summaries son ligeros y periodicos.
- Los deltas se piden solo si el peer remoto sabe algo mas nuevo o si la ventana reciente diverge.
- El sync se hace por `unicast` a pocos donors, no por broadcast.

## Entidades

### Roster

Un miembro del roster contiene, entre otros:

- `name`
- `hasAddon`
- `isOnlineInChannel`
- `firstSeenAt`
- `lastSeenAt`
- `lastObservedAt`
- `lastAddonSeenAt`
- `lastUpdatedAt`
- `level`
- `classFile`
- `zone`
- `guildName`
- `profession1`
- `profession2`
- `profession1Icon`
- `profession2Icon`

`lastUpdatedAt` cambia solo cuando cambia el perfil util del miembro.

`isOnlineInChannel` no significa que el roster completo del canal se haya resuelto por API. En el estado actual significa que el jugador ha sido observado recientemente por notice, chat, addon o `/who`, y para peers con addon tambien por heartbeat.

### Chat

Un mensaje de chat contiene:

- `id`
- `source`
- `name`
- `at`
- `details`

El `id` debe ser determinista para evitar duplicados entre peers.

## Identidad del mensaje

Para `channel_message` se usa este orden:

1. `lineId` de `CHAT_MSG_CHANNEL` si Blizzard lo entrega
2. fallback con:
   - `sender_normalized`
   - `text_trimmed`
   - `time_bucket`

Esto permite que dos clientes que ven el mismo mensaje generen la misma identidad logica.

## Discovery y presencia

### Descubrimiento de peers con addon

Un peer se considera conocido con addon cuando llega cualquier `CHAT_MSG_ADDON` con prefijo valido.

Efectos:

1. `Store.MarkAddonSeen()` lo marca online.
2. `REQ` y `HELLO` fuerzan respuesta `INFO`.
3. `INFO` actualiza perfil vivo.
4. `RSUM` y `CSUM` permiten reconciliacion de roster/chat.

### Descubrimiento de jugadores sin addon

Un jugador sin addon solo se descubre de forma best effort por:

1. `CHAT_MSG_CHANNEL_NOTICE`
2. `CHAT_MSG_CHANNEL`
3. `/who` manual

No hay heartbeat para este grupo.

### Offline de peers con addon

Hay tres rutas:

1. `BYE` cuando el cliente sale limpiamente
2. timeout de heartbeat addon (`HELLO` no contestado durante varios probes)
3. `LEFT` si Blizzard emite el notice visible

La ruta fiable es el heartbeat addon; el roster detallado del canal no se usa para dar offlines duros.

## Ciclos de sincronizacion

### 1. Bootstrap fuerte

Se dispara en:

- `PLAYER_LOGIN`
- `PLAYER_ENTERING_WORLD`
- rejoin al canal
- refresh manual

Flujo:

1. asegurar union y visibilidad basica del canal
2. refrescar perfil local
3. elegir donors entre peers online con addon ya conocidos
4. enviar `HELLO` y `RSUM`
5. enviar `HELLO` y `CSUM`
6. si el donor remoto va por delante o su ventana reciente diverge:
   - enviar `RREQ`
   - enviar `CREQ`
7. importar `RPRO` y `CMSG`
8. parar pronto si el primer donor ya cubre el gap

### 2. Summary periodica

Se hace por `unicast` a donors, no a todos los peers.

Frecuencias actuales:

- `RSUM` cada `5 min`
- `CSUM` cada `3 min`

Solo anuncia el estado resumido. No empuja roster ni chat completos.

Cada envio de summaries va precedido por `HELLO` al donor elegido para refrescar presencia addon y forzar `INFO` si hacia falta.

### 3. Pull por delta

Si un summary remoto indica que el peer sabe algo mas nuevo que tu cliente:

- para roster: `RREQ`
- para chat: `CREQ`

Las respuestas son:

- `RPRO` para perfiles de roster
- `CMSG` para mensajes de chat

## Seleccion de donors

La seleccion de donors esta limitada para controlar el trafico.

Reglas:

- maximo `2` donors en bootstrap
- maximo `1` donor por ciclo periodico

Prioridad de donor:

1. peer online con addon
2. mayor `lastProfileAt`
3. mayor `lastSeenAt`
4. desempate por nombre

Si un peer deja de contestar heartbeats, deja de ser donor al pasar offline.

## Summary y payloads

### Perfil vivo

Mensajes:

- `REQ`
- `HELLO`
- `INFO`

`REQ` se usa para pedir perfil fresco cuando un peer se descubre o su perfil caduca.

`HELLO` se usa como heartbeat addon. El receptor responde con `INFO`.

`INFO` describe el peer actual y sirve para perfil vivo, presencia addon y para anunciar `latestChatAt`.

### Roster

#### `RSUM`

Formato:

```text
RSUM;4;<player>;<latest_roster_updated_at>;<member_count_recent>
```

#### `RREQ`

Formato:

```text
RREQ;4;<since_timestamp>
```

#### `RPRO`

Formato:

```text
RPRO;4;<name>;<hasAddon>;<level>;<class>;<zone>;<guild>;<prof1>;<prof2>;<prof1Icon>;<prof2Icon>;<lastSeenAt>;<lastUpdatedAt>
```

### Chat

#### `CSUM`

Formato:

```text
CSUM;4;<player>;<latest_chat_at>;<message_count_recent>;<oldest_at>;<first_id>;<last_id>
```

#### `CREQ`

Formato:

```text
CREQ;4;<since_timestamp>
```

#### `CMSG`

Formato:

```text
CMSG;4;<id>;<at>;<source>;<name>;<text>
```

## Reglas de merge

### Roster

Al recibir `RPRO`:

1. normalizar `name`
2. crear miembro si no existe
3. aplicar el perfil si aporta datos nuevos o si el perfil local estaba vacio
4. `lastSeenAt = max(local, incoming)`
5. `hasAddon = true` si el remoto lo marca
6. no sobrescribir presencia online con datos remotos viejos

`RPRO` enriquece roster y `lastSeenAt`, pero no es la fuente principal de presencia online para peers con addon si no hay trafico reciente.

### Chat

Al recibir `CMSG`:

1. si `id` ya existe, ignorar
2. si no existe, insertar ordenado por `at`
3. si no hay `id` usable, usar fallback por equivalencia:
   - mismo `sender`
   - mismo `text`
   - diferencia de tiempo pequena

Al recibir `CSUM`:

1. comparar `latestChatAt`
2. comparar tambien la ventana reciente anunciada (`count`, `oldestAt`, `firstId`, `lastId`)
3. si cualquier valor diverge, pedir `CREQ` desde `advertisedOldestAt - 1`

Esto permite mergear historiales recientes divergentes aunque el ultimo timestamp sea parecido.

## Ventanas y limites

### Roster

- `rosterSyncWindow = 7 dias`
- `rosterSyncLimit = 50`
- `rosterSyncCooldown = 5 min`

### Chat

- `chatSyncWindow = 24 horas`
- `chatSyncLimit = 50`
- `chatSyncCooldown = 60 s`

## Early stop

La reconciliacion debe parar pronto si no hay valor en seguir.

Parar si:

- `remote.latest_roster_updated_at <= local.latest_roster_updated_at`
- `remote.latest_chat_at <= local.latest_chat_at` y la ventana reciente coincide
- el primer donor ya cubrio los gaps detectados
- no hay deltas adicionales que pedir

## Lo que NO debe hacer el addon

- no reconciliar full roster contra todos los peers
- no reconciliar chat continuamente entre peers online
- no hacer broadcast de datos completos
- no usar `/who` como reconciliacion global
- no asumir que el roster detallado del canal es fiable en SoD
- no pedir sync si el summary no muestra ventaja remota o divergencia reciente

## Situacion actual del codigo

La base existente ya cubre:

- presencia addon por `HELLO`/`INFO`/`BYE` y timeout por heartbeat
- perfil vivo por `REQ/INFO`
- ids deterministas de `channel_message`
- reconciliacion ligera de roster en bootstrap y summaries periodicas
- reconciliacion de chat sin full sync continuo
- merge de chat reciente por ventana resumida, no solo por ultimo timestamp

## Flujo esperado de convergencia

### Cliente nuevo

1. entra al canal
2. descubre peers por notices, chat visible o trafico addon entrante
3. intercambia `HELLO` / `INFO`
4. pide o recibe `RSUM` y `CSUM`
5. si falta informacion, pide `RREQ` y `CREQ`
6. hereda roster y chat recientes

### Cliente que estuvo offline

1. vuelve al juego
2. bootstrap inicial
3. detecta que peers remotos tienen datos mas nuevos o ventana reciente distinta
4. trae solo los deltas

### Dos peers ya online y estables

1. intercambian heartbeats addon cuando hay silencio prolongado
2. intercambian summaries ligeras
3. si nadie va atrasado, no se hace nada mas

Esto mantiene el trafico bajo y la convergencia alta.

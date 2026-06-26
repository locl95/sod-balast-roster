# Sync Cycles

## Objetivo

El addon sincroniza dos entidades distintas:

1. `Roster`
2. `Chat`

Cada una tiene su propia estrategia de reconciliacion, pero ambas siguen el mismo patron general:

1. detectar donors
2. intercambiar summaries ligeras
3. pedir deltas solo si faltan datos
4. mergear localmente

No se hace full sync continuo entre todos los peers online.

## Principios

- La presencia sale del roster real del canal `SODBALAST`.
- El perfil rico se intercambia por `addon whisper`.
- La reconciliacion fuerte ocurre en bootstrap, no todo el tiempo.
- Los summaries son ligeros y periodicos.
- Los deltas se piden solo si el peer remoto sabe algo mas nuevo.
- El sync se hace por `unicast` a pocos donors, no por broadcast.

## Entidades

### Roster

Un miembro del roster contiene:

- `name`
- `has_addon`
- `is_online_in_channel`
- `first_seen_at`
- `last_seen_at`
- `last_updated_at`
- `level`
- `classFile`
- `zone`
- `guildName`
- `profession1`
- `profession2`
- `profession1Icon`
- `profession2Icon`

`last_updated_at` cambia solo cuando cambia el perfil util del miembro.

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

## Ciclos de sincronizacion

### 1. Bootstrap fuerte

Se dispara en:

- `PLAYER_LOGIN`
- `PLAYER_ENTERING_WORLD`
- rejoin al canal
- refresh manual

Flujo:

1. hacer scan del canal
2. detectar peers con addon
3. elegir donors
4. enviar `RSUM`
5. enviar `CSUM`
6. si el donor remoto va por delante:
   - enviar `RREQ`
   - enviar `CREQ`
7. importar `RPRO` y `CMSG`
8. parar pronto si el primer donor ya cubre el gap

### 2. Summary periodica

Se hace por `unicast` a donors, no a todos los peers.

Frecuencias recomendadas:

- `RSUM` cada `5 min`
- `CSUM` cada `3 min`

Solo anuncia el estado resumido. No empuja roster ni chat completos.

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

## Summary y payloads

### Perfil vivo

Mensajes:

- `REQ`
- `INFO`

`INFO` describe el peer actual y sirve para el perfil vivo.

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
CSUM;4;<player>;<latest_chat_at>;<message_count_recent>
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
3. aplicar el perfil solo si:
   - `incoming.last_updated_at > local.last_updated_at`
   - o el perfil local esta vacio
4. `last_seen_at = max(local, incoming)`
5. `has_addon = true` si el remoto lo marca
6. no sobrescribir presencia online con datos remotos viejos

### Chat

Al recibir `CMSG`:

1. si `id` ya existe, ignorar
2. si no existe, insertar ordenado por `at`
3. si no hay `id` usable, usar fallback por equivalencia:
   - mismo `sender`
   - mismo `text`
   - diferencia de tiempo pequena

## Ventanas y limites

### Roster

- `rosterSyncWindow = 7 dias`
- `rosterSyncLimit = 50`
- `rosterSyncCooldown = 5 min`

### Chat

- `chatSyncWindow = 24 horas`
- `chatSyncLimit = 100`
- `chatSyncCooldown = 5 min`

## Early stop

La reconciliacion debe parar pronto si no hay valor en seguir.

Parar si:

- `remote.latest_roster_updated_at <= local.latest_roster_updated_at`
- `remote.latest_chat_at <= local.latest_chat_at`
- el primer donor ya cubrio los gaps detectados
- no hay deltas adicionales que pedir

## Lo que NO debe hacer el addon

- no reconciliar full roster contra todos los peers
- no reconciliar chat continuamente entre peers online
- no hacer broadcast de datos completos
- no usar `/who` como reconciliacion global
- no pedir sync si el summary no muestra ventaja remota

## Situacion actual del codigo

La base existente ya cubre:

- presencia por roster del canal
- perfil vivo por `REQ/INFO`
- ids deterministas de `channel_message`
- reconciliacion ligera de roster en rejoin/reload
- reconciliacion de chat sin full sync continuo

La evolucion natural es seguir refinando:

1. donors
2. summaries
3. deltas
4. merge seguro

## Flujo esperado de convergencia

### Cliente nuevo

1. entra al canal
2. detecta peers con addon
3. pide `RSUM` y `CSUM`
4. si falta informacion, pide `RREQ` y `CREQ`
5. hereda roster y chat recientes

### Cliente que estuvo offline

1. vuelve al juego
2. bootstrap inicial
3. detecta que peers remotos tienen datos mas nuevos
4. trae solo los deltas

### Dos peers ya online y estables

1. solo intercambian summaries ligeras
2. si nadie va atrasado, no se hace nada mas

Esto mantiene el trafico bajo y la convergencia alta.

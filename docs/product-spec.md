# Product Spec

## Contexto

El canal `SODBALAST` agrupa a jugadores repartidos entre varias guilds Fresh dentro de un evento de Season of Discovery. El objetivo del addon es convertir ese canal en una capa social tipo guild con roster, visibilidad e historial local.

## Problema

El canal de chat permite coordinacion basica, pero no da una vista clara de:

- quien esta en el canal
- quien esta online ahora mismo
- cual es el contexto de cada personaje
- cuando se vio por ultima vez a un jugador
- como navegar facilmente entre todos los miembros

## Objetivo del producto

Construir una mini guild virtual basada en el canal `SODBALAST` con una interfaz de roster y un historico local.

## Objetivos de la V1

1. Mostrar a todos los personajes detectados en el canal.
2. Distinguir entre personajes con addon y sin addon.
3. Mostrar metadatos de los personajes con addon:
   - nivel
   - clase
   - spec (arbol de talentos dominante)
   - zona
   - guild real
4. Mantener un historico local de entradas y salidas del canal.
5. Permitir acciones sociales rapidas:
   - whisper
   - invite

## Fuera de alcance en V1

- notas compartidas entre clientes
- roles o rangos virtuales
- sincronizacion por canal custom con `SendAddonMessage`
- base de datos compartida entre jugadores
- integracion con Discord
- soporte multi canal

## Fuente de verdad

La presencia de un jugador se basa en el roster del canal custom, no en heartbeats entre addons.

Consecuencias:

- todos los miembros del canal pueden aparecer en la UI
- solo los jugadores con addon pueden aportar perfil rico
- la desaparicion del canal implica marcar al jugador como fuera del roster

## Casos de uso principales

1. Como jugador de BALAST quiero abrir una ventana y ver quien esta en `SODBALAST` para saber con quien puedo jugar o hablar.
2. Como jugador quiero ver el nivel, clase, spec, zona y guild de quien tenga addon para priorizar whispers e invites.
3. Como jugador quiero ver cuando aparecio o desaparecio alguien del canal para tener algo de historico.
4. Como jugador quiero filtrar la lista por online, por addon y por nombre.

## Requisitos funcionales

### Roster

- El addon debe intentar unirse a `SODBALAST` si el usuario no esta en el canal.
- El addon debe escanear periodicamente el roster del canal.
- El addon debe mostrar todos los miembros detectados en el canal.
- El addon debe conservar datos conocidos localmente aunque falten en un scan puntual.

### Enriquecimiento de perfil

- El addon debe poder pedir informacion a otros clientes por `WHISPER`.
- El addon debe responder a peticiones de perfil de otros clientes.
- El addon debe marcar visualmente si un jugador tiene addon.

### Historico

- El addon debe registrar entrada al canal.
- El addon debe registrar salida del canal.
- El addon debe registrar primer perfil recibido.
- El addon debe registrar cambios relevantes de perfil:
  - nivel
  - zona
  - guild

### UI

- Debe existir una ventana accesible por slash command.
- Debe haber una tab de roster y una tab de historico.
- La lista del roster debe ser ordenable y filtrable.

## Requisitos no funcionales

- trafico de whispers limitado y con cola
- persistencia local con `SavedVariables`
- cambios pequenos y faciles de depurar
- compatibilidad con WoW Classic SoD

## Criterios de aceptacion de V1

1. Dos jugadores con addon en `SODBALAST` se ven entre si con perfil completo.
2. Un jugador sin addon en `SODBALAST` aparece igualmente en el roster.
3. Al salir un jugador del canal, el roster lo marca como no presente y registra el evento.
4. El roster persiste entre `reload` y relog.
5. La UI permite filtrar por solo online, solo addon y texto.

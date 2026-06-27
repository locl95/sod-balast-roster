# Manual Testing

## Objetivo

Validar de forma manual:

1. presencia de peers con addon por heartbeat y notices
2. sincronizacion de perfil
3. reconciliacion de roster
4. reconciliacion de chat
5. fallback manual de `/who`
6. estabilidad visual de la UI

Estas pruebas estan pensadas para Season of Discovery / WoW Classic con al menos dos clientes con addon.

## Preparacion

Antes de empezar:

1. instalar la misma version del addon en todos los clientes que vayan a participar
2. hacer `/reload`
3. confirmar que el header del addon muestra la misma version en todos
4. activar `scriptErrors` si se quiere capturar errores:

```text
/console scriptErrors 1
/reload
```

5. unir todos los clientes al canal `SODBALAST`

## Caso 1. Carga basica del addon

Pasos:

1. abrir el juego
2. verificar que el addon carga sin error
3. ejecutar `/sb`

Esperado:

- se abre la ventana
- se ve el header con version
- no hay errores Lua

## Caso 2. Roster del canal

Pasos:

1. tener 2 o mas personajes en `SODBALAST`
2. abrir `/sb`
3. pulsar `Refresh`

Esperado:

- jugadores observados por notice, chat o addon aparecen en el roster
- miembros con addon muestran columna `A = Y`
- miembros sin addon muestran `A = -`

Nota:

- en SoD no se asume que el roster detallado del canal se pueda resolver por API
- para usuarios sin addon, la presencia sigue siendo best effort

## Caso 3. Perfil vivo entre peers con addon

Pasos:

1. cliente A y B con addon en el canal
2. esperar unos segundos o pulsar `Refresh`

Esperado:

- A ve a B con:
  - nivel
  - clase
  - zona
  - guild
  - profesiones
- B ve a A con lo mismo

## Caso 4. Professions

Pasos:

1. cliente A con dos profesiones principales
2. cliente B con addon
3. ambos online en `SODBALAST`

Esperado:

- A ve iconos correctos de sus profesiones
- B ve iconos correctos de A tras sync
- no aparecen cuadrados de textura verde para profesiones conocidas

Si falla:

1. ejecutar `/sbd`
2. revisar las lineas de profesiones

## Caso 5. Fallback manual `/who`

Escenario:

- personaje en el canal sin addon o sin perfil enriquecido

Pasos:

1. click derecho sobre el miembro
2. `Refresh Info`

Esperado:

- sale `who query: <name>` en chat
- si el servidor devuelve resultado util:
  - se rellenan `level/class/zone/guild`
- si no, se ve `who no match` o `who timeout`

Nota:

- `/who` es manual y depende de hardware event
- no debe esperarse resolucion automatica en background

## Caso 6. Last Seen y presencia

Pasos:

1. cliente A y B online en el canal
2. observar `Last Seen`

Esperado:

- si el peer esta online, `Last Seen` muestra `Online`
- si sale del canal o desaparece de forma estable, cambia a tiempo relativo

### Logout con addon

Pasos:

1. cliente B cierra sesion
2. A observa el roster

Esperado:

- A marca offline a B razonablemente rapido por `BYE` o por timeout de heartbeat addon
- si llega `BYE`, mejor aun

### Cambio de zona/canales

Pasos:

1. A o B cambia de zona donde Blizzard refresca canales
2. observar roster durante la transicion

Esperado:

- no se marca a todo el roster offline en masa
- no aparecen `left_channel` falsos por refresh transitorio

### Usuario sin addon

Pasos:

1. personaje sin addon entra al canal
2. hablar por el canal o provocar notice visible
3. observar el roster

Esperado:

- puede aparecer en roster por chat o notice
- su presencia puede tardar mas o ser menos fiable que la de peers con addon

## Caso 7. Chat visible

Pasos:

1. abrir tab `Chat`
2. enviar varios mensajes por el canal

Esperado:

- se ven solo mensajes de canal
- no se ven eventos internos como:
  - `joined_channel`
  - `left_channel`
  - `profile_discovered`

## Caso 8. Input del chat

Pasos:

1. abrir tab `Chat`
2. escribir en la caja inferior
3. pulsar `Enter`

Esperado:

- el mensaje se envia al canal `SODBALAST`
- la caja se limpia
- el chat baja al final tras tu envio

## Caso 9. Scroll del chat

Pasos:

1. llenar el chat con varios mensajes
2. subir usando la rueda
3. dejar la ventana abierta un rato sin enviar nada

Esperado:

- no debe bajar solo sin cambios de contenido
- si no hay mensajes nuevos, debe mantener posicion
- si envias un mensaje local, puede bajar al final

### Scrollbar lateral

Pasos:

1. usar flecha arriba y abajo del scrollbar
2. usar la rueda del raton

Esperado:

- ambas rutas mueven el chat
- el thumb refleja la posicion aproximada
- si el drag manual esta deshabilitado, no debe mover al arrastrar

## Caso 10. Reconciliacion de chat sin duplicados

Escenario:

- cliente A y B con addon online a la vez

Pasos:

1. A envia un mensaje
2. B envia un mensaje
3. ambos observan `Chat`

Esperado:

- cada mensaje aparece una sola vez
- no hay duplicados por reconciliacion

## Caso 11. Reconciliacion de chat tras offline

Escenario:

- A online
- B offline

Pasos:

1. A genera varios mensajes en el canal
2. B entra mas tarde
3. ambos coinciden en `SODBALAST`
4. esperar bootstrap o pulsar `Refresh`

Esperado:

- B recupera mensajes recientes
- no aparecen duplicados del mismo mensaje

## Caso 12. Reconciliacion de roster para cliente nuevo

Escenario:

- A lleva dias con addon y tiene roster rico
- B instala hoy el addon

Pasos:

1. A y B entran al canal
2. esperar sync inicial

Esperado:

- B hereda perfiles de roster conocidos desde A
- no necesita coincidir en vivo con todos los personajes para ver su informacion basica

## Caso 13. Donors y summaries

Objetivo:

verificar que el addon no hace spam.

Pasos:

1. dejar A y B online un rato
2. observar comportamiento funcional

Esperado:

- no se percibe spam de full sync continuo
- el addon converge sin peticiones visibles agresivas

## Caso 14. Heartbeat addon

Pasos:

1. cliente A y B con addon online
2. dejar de generar chat o interaccion un rato
3. cerrar B sin enviar mensajes visibles
4. observar A

Esperado:

- A mantiene a B online mientras siga habiendo trafico addon o heartbeat respondido
- si B desaparece, A termina marcandolo offline por timeout addon aunque no llegue `LEFT`

## Caso 15. UI lateral de navegacion

Pasos:

1. abrir el addon
2. revisar iconos laterales

Esperado:

- botones fuera del panel principal
- botones pegados al lado derecho de la ventana
- tamaño y espaciado correctos
- cambio de tab funcional

## Caso 16. Menu contextual del roster

Pasos:

1. click derecho sobre un miembro

Esperado:

- aparece menu contextual
- acciones disponibles segun el estado esperado
- `Refresh Info` solo para miembros sin addon

## Caso 17. Compatibilidad de versiones

Pasos:

1. cliente A con version nueva
2. cliente B con version anterior soportada
3. ambos online

Esperado:

- no rompe el sync basico
- si hay campos nuevos, el cliente viejo simplemente no los aprovecha

## Checklist rapido antes de dar por buena una release

1. el addon carga sin error
2. los peers con addon se detectan y mantienen online por heartbeat/notices
3. los peers con addon se ven con perfil completo
4. las profesiones se sincronizan y muestran icono
5. el `Chat` no duplica mensajes
6. el scroll del chat se comporta correctamente
7. el input inferior envia al canal
8. la reconciliacion de roster funciona para un cliente nuevo
9. no hay offline masivos falsos al cambiar de zona
10. no hay spam visible de sincronizacion continua

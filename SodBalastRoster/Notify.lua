local addonName, ns = ...

local Notify = {
  readyAt = nil,
  hardDeadline = nil,
  pending = {},
  coalesceScheduled = false,
}
ns.Notify = Notify

local COALESCE_WINDOW = 1.2

-- El descubrimiento de peers que ya estaban online al loguear no llega de
-- golpe: se resuelve poco a poco (whispers de bootstrap limitados a 1/s,
-- listas de peers reenviadas, rescans). Un temporizador fijo corta a mitad
-- de ese goteo y notifica sueltos con el sonido desincronizado del texto.
-- En su lugar, cada descubrimiento durante el arranque pospone el inicio
-- de notificaciones (debounce) hasta que haya un hueco de silencio real,
-- con un techo duro para no bloquear notificaciones legitimas si el canal
-- esta muy activo.
local QUIET_WINDOW_SECONDS = 6
local MAX_WARMUP_SECONDS = 20

function Notify.Arm()
  local now = GetTime()
  Notify.readyAt = now + QUIET_WINDOW_SECONDS
  Notify.hardDeadline = now + MAX_WARMUP_SECONDS
end

local function isReady()
  if not Notify.readyAt then
    return false
  end

  local now = GetTime()
  return now >= Notify.readyAt or now >= Notify.hardDeadline
end

local function extendWarmup()
  if not Notify.hardDeadline then
    return
  end

  Notify.readyAt = math.min(GetTime() + QUIET_WINDOW_SECONDS, Notify.hardDeadline)
end

local function playerLink(name)
  return string.format("|Hplayer:%s|h[%s]|h", name, name)
end

local function formatChatNames(names)
  local links = {}
  for _, name in ipairs(names) do
    links[#links + 1] = playerLink(name)
  end

  return table.concat(links, ", ")
end

local function playChime()
  if not PlaySound then
    return
  end

  if SOUNDKIT and SOUNDKIT.TELL_MESSAGE then
    PlaySound(SOUNDKIT.TELL_MESSAGE, "Master")
    return
  end

  PlaySound(3081, "Master")
end

local function printChannelLine(names)
  if not DEFAULT_CHAT_FRAME then
    return
  end

  local prefix = "|cff33ff99SODBALAST|r"
  local verb = #names > 1 and "have come online" or "has come online"
  DEFAULT_CHAT_FRAME:AddMessage(string.format(
    "%s: |cffffff00%s %s|r",
    prefix,
    formatChatNames(names),
    verb
  ))
end

local function flushPending()
  Notify.coalesceScheduled = false
  local names = Notify.pending
  Notify.pending = {}
  if #names == 0 then
    return
  end

  printChannelLine(names)
  playChime()
end

function Notify.PlayerDiscovered(name)
  if not name or name == "" then
    return
  end

  if not isReady() then
    extendWarmup()
    return
  end

  table.insert(Notify.pending, name)
  if not Notify.coalesceScheduled then
    Notify.coalesceScheduled = true
    C_Timer.After(COALESCE_WINDOW, flushPending)
  end
end

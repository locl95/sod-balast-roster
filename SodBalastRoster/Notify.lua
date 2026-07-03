local addonName, ns = ...

local Notify = {
  queue = {},
  active = false,
  readyAt = nil,
  hardDeadline = nil,
  pending = {},
  coalesceScheduled = false,
}
ns.Notify = Notify

local DISPLAY_DURATION = 2.4
local FADE_IN = 0.25
local FADE_OUT = 0.4
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

local function classColor(name)
  local member = ns.Store and ns.Store.GetRoster()[name]
  local palette = RAID_CLASS_COLORS or CUSTOM_CLASS_COLORS
  if member and palette and member.classFile ~= "" and palette[member.classFile] then
    local color = palette[member.classFile]
    return color.r, color.g, color.b
  end

  return 0.55, 0.9, 1
end

local function formatNames(names)
  local colored = {}
  for _, name in ipairs(names) do
    local r, g, b = classColor(name)
    colored[#colored + 1] = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name)
  end

  return table.concat(colored, ", ")
end

local function ensureFrame()
  if Notify.frame then
    return Notify.frame
  end

  local frame = CreateFrame("Frame", "SodBalastRosterDiscoveryToast", UIParent, BackdropTemplateMixin and "BackdropTemplate")
  frame:SetSize(280, 32)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
  frame:SetAlpha(0)
  frame:Hide()

  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    frame:SetBackdropBorderColor(0.4, 0.85, 0.5, 1)
  end

  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetSize(16, 16)
  frame.icon:SetPoint("LEFT", frame, "LEFT", 10, 0)
  frame.icon:SetTexture("Interface\\Icons\\Spell_Holy_Renew")

  frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
  frame.text:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
  frame.text:SetJustifyH("LEFT")

  Notify.frame = frame
  return frame
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
  DEFAULT_CHAT_FRAME:AddMessage(string.format("%s: [%s] %s", prefix, formatNames(names), verb))
end

local function showNext()
  local frame = ensureFrame()
  local entry = table.remove(Notify.queue, 1)
  if not entry then
    Notify.active = false
    if UIFrameFadeOut then
      UIFrameFadeOut(frame, FADE_OUT, frame:GetAlpha(), 0)
    else
      frame:Hide()
    end
    return
  end

  Notify.active = true
  local label
  if #entry == 1 then
    label = string.format("%s acaba de conectarse", formatNames(entry))
  else
    label = string.format("%d jugadores acaban de conectarse: %s", #entry, formatNames(entry))
  end
  frame.text:SetText(label)
  frame:Show()
  if UIFrameFadeIn then
    UIFrameFadeIn(frame, FADE_IN, frame:GetAlpha(), 1)
  else
    frame:SetAlpha(1)
  end
  playChime()

  C_Timer.After(DISPLAY_DURATION, function()
    if #Notify.queue > 0 then
      showNext()
    else
      Notify.active = false
      if UIFrameFadeOut then
        UIFrameFadeOut(frame, FADE_OUT, 1, 0)
      else
        frame:Hide()
      end
    end
  end)
end

local function flushPending()
  Notify.coalesceScheduled = false
  local names = Notify.pending
  Notify.pending = {}
  if #names == 0 then
    return
  end

  printChannelLine(names)
  table.insert(Notify.queue, names)
  if not Notify.active then
    showNext()
  end
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

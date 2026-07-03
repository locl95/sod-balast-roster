local addonName, ns = ...

local Notify = {
  queue = {},
  active = false,
  readyAt = nil,
}
ns.Notify = Notify

local DISPLAY_DURATION = 2.4
local FADE_IN = 0.25
local FADE_OUT = 0.4

-- Cubre el burst inicial de login: rescan (hasta +3s), bootstrap HELLO/INFO por
-- whisper y los CHAT_MSG_CHANNEL de gente que ya estaba en el canal. Sin esto,
-- cada peer que ya estaba online dispara una notificacion al loguearte.
local WARMUP_SECONDS = 8

function Notify.Arm()
  Notify.readyAt = GetTime() + WARMUP_SECONDS
end

local function isReady()
  return Notify.readyAt ~= nil and GetTime() >= Notify.readyAt
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

local function ensureFrame()
  if Notify.frame then
    return Notify.frame
  end

  local frame = CreateFrame("Frame", "SodBalastRosterDiscoveryToast", UIParent, BackdropTemplateMixin and "BackdropTemplate")
  frame:SetSize(260, 32)
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

local function printChannelLine(name)
  if not DEFAULT_CHAT_FRAME then
    return
  end

  local prefix = "|cff33ff99SODBALAST|r"
  local r, g, b = classColor(name)
  local coloredName = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name)
  DEFAULT_CHAT_FRAME:AddMessage(string.format("%s: [%s] has come online", prefix, coloredName))
end

local function showNext()
  local frame = ensureFrame()
  local name = table.remove(Notify.queue, 1)
  if not name then
    Notify.active = false
    if UIFrameFadeOut then
      UIFrameFadeOut(frame, FADE_OUT, frame:GetAlpha(), 0)
    else
      frame:Hide()
    end
    return
  end

  Notify.active = true
  local r, g, b = classColor(name)
  frame.text:SetText(string.format("|cff%02x%02x%02x%s|r acaba de conectarse", r * 255, g * 255, b * 255, name))
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

function Notify.PlayerDiscovered(name)
  if not name or name == "" then
    return
  end

  if not isReady() then
    return
  end

  printChannelLine(name)
  table.insert(Notify.queue, name)
  if not Notify.active then
    showNext()
  end
end

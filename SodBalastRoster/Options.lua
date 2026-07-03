local addonName, ns = ...

local Store = ns.Store
local Options = {}
ns.Options = Options

local function addHeader(parent, text, anchorTo, yOffset)
  local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset)
  header:SetJustifyH("LEFT")
  header:SetText(text)
  return header
end

local function addNote(parent, text, anchorTo, yOffset)
  local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset)
  note:SetPoint("RIGHT", parent, "RIGHT", -32, 0)
  note:SetJustifyH("LEFT")
  note:SetTextColor(0.7, 0.7, 0.7)
  note:SetText(text)
  return note
end

local function createCheckbox(parent, name, label, anchorTo, yOffset, getValue, setValue)
  local check = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
  check:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", -2, yOffset)
  _G[check:GetName() .. "Text"]:SetText(label)
  check:SetScript("OnClick", function(self)
    setValue(self:GetChecked() and true or false)
  end)
  check.RefreshValue = function()
    check:SetChecked(getValue())
  end
  return check
end

local function createSlider(parent, name, label, anchorTo, yOffset, minValue, maxValue, step, getValue, setValue, formatValue)
  local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 10, yOffset)
  slider:SetWidth(260)
  slider:SetMinMaxValues(minValue, maxValue)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)
  _G[name .. "Low"]:SetText(tostring(minValue))
  _G[name .. "High"]:SetText(tostring(maxValue))
  _G[name .. "Text"]:SetText(label)

  slider.valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  slider.valueText:SetPoint("LEFT", slider, "RIGHT", 12, 0)

  slider:SetScript("OnValueChanged", function(self, value)
    if self.suppressCallback then
      return
    end
    setValue(value)
    self.valueText:SetText(formatValue(value))
  end)

  slider.RefreshValue = function()
    slider.suppressCallback = true
    local value = getValue()
    slider:SetValue(value)
    slider.valueText:SetText(formatValue(value))
    slider.suppressCallback = false
  end

  return slider
end

local function formatSeconds(value)
  return string.format("%.0fs", value)
end

local function formatSendInterval(value)
  return string.format("%.1fs", value)
end

function Options.Create()
  if Options.panel then
    return Options.panel
  end

  local panel = CreateFrame("Frame", "SodBalastRosterOptionsPanel", UIParent)
  panel.name = "SodBalastRoster"

  panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  panel.title:SetPoint("TOPLEFT", 16, -16)
  panel.title:SetText(string.format("SodBalastRoster v%s", ns.version or "dev"))

  panel.socialHeader = addHeader(panel, "Notificaciones sociales", panel.title, -24)

  panel.textAlertCheck = createCheckbox(panel, "SodBalastRosterOptionsTextAlert",
    "Aviso de texto en el chat al ver jugadores conectados",
    panel.socialHeader, -12,
    Store.IsNotifyTextEnabled, Store.SetNotifyTextEnabled)

  panel.soundAlertCheck = createCheckbox(panel, "SodBalastRosterOptionsSoundAlert",
    "Sonido al ver jugadores conectados",
    panel.textAlertCheck, -8,
    Store.IsNotifySoundEnabled, Store.SetNotifySoundEnabled)

  panel.debugHeader = addHeader(panel, "Debug", panel.soundAlertCheck, -28)

  panel.debugCheck = createCheckbox(panel, "SodBalastRosterOptionsDebug",
    "Activar herramientas de debug",
    panel.debugHeader, -12,
    Store.IsCommDebugEnabled, function(value)
      Store.SetCommDebugEnabled(value)
      if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
        ns.UI.Refresh()
      end
    end)

  panel.debugNote = addNote(panel,
    "Registra el trafico de comunicacion entre addons y anade la pestana Debug a la ventana. Al desactivarlo, la pestana desaparece.",
    panel.debugCheck, -6)

  panel.advancedHeader = addHeader(panel, "Avanzado: frecuencia de red", panel.debugNote, -20)

  panel.advancedNote = addNote(panel,
    "Valores mas altos reducen el trafico y la carga en el canal, a costa de tardar mas en detectar cambios.",
    panel.advancedHeader, -6)

  panel.scanSlider = createSlider(panel, "SodBalastRosterOptionsScanInterval",
    "Escaneo del canal", panel.advancedNote, -30,
    15, 120, 5,
    function() return Store.GetAdvancedState().scanInterval end,
    function(value) Store.SetAdvancedValue("scanInterval", value) end,
    formatSeconds)

  panel.rosterSummarySlider = createSlider(panel, "SodBalastRosterOptionsRosterSummary",
    "Resumen de roster", panel.scanSlider, -40,
    60, 900, 30,
    function() return Store.GetAdvancedState().rosterSummaryInterval end,
    function(value) Store.SetAdvancedValue("rosterSummaryInterval", value) end,
    formatSeconds)

  panel.chatSummarySlider = createSlider(panel, "SodBalastRosterOptionsChatSummary",
    "Resumen de chat", panel.rosterSummarySlider, -40,
    60, 900, 30,
    function() return Store.GetAdvancedState().chatSummaryInterval end,
    function(value) Store.SetAdvancedValue("chatSummaryInterval", value) end,
    formatSeconds)

  panel.whoIntervalSlider = createSlider(panel, "SodBalastRosterOptionsWhoInterval",
    "Consultas /who", panel.chatSummarySlider, -40,
    3, 30, 1,
    function() return Store.GetAdvancedState().whoRequestInterval end,
    function(value) Store.SetAdvancedValue("whoRequestInterval", value) end,
    formatSeconds)

  panel.sendIntervalSlider = createSlider(panel, "SodBalastRosterOptionsSendInterval",
    "Ritmo de envio de mensajes de addon", panel.whoIntervalSlider, -40,
    0.5, 5, 0.5,
    function() return Store.GetAdvancedState().requestInterval end,
    function(value) Store.SetAdvancedValue("requestInterval", value) end,
    formatSendInterval)

  panel.refresh = function()
    panel.textAlertCheck.RefreshValue()
    panel.soundAlertCheck.RefreshValue()
    panel.debugCheck.RefreshValue()
    panel.scanSlider.RefreshValue()
    panel.rosterSummarySlider.RefreshValue()
    panel.chatSummarySlider.RefreshValue()
    panel.whoIntervalSlider.RefreshValue()
    panel.sendIntervalSlider.RefreshValue()
  end

  panel:SetScript("OnShow", panel.refresh)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    Options.category = category
  else
    InterfaceOptions_AddCategory(panel)
  end

  Options.panel = panel
  return panel
end

function Options.Open()
  Options.Create()

  if Settings and Settings.OpenToCategory and Options.category then
    Settings.OpenToCategory(Options.category:GetID())
    return
  end

  -- Blizzard: la primera llamada en la sesion no siempre resalta el panel; hay que llamarla dos veces.
  InterfaceOptionsFrame_OpenToCategory(Options.panel)
  InterfaceOptionsFrame_OpenToCategory(Options.panel)
end

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

local function createCheckbox(parent, name, label, anchorTo, xOffset, yOffset, getValue, setValue)
  local check = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
  check:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", xOffset, yOffset)
  _G[check:GetName() .. "Text"]:SetText(label)
  check:SetScript("OnClick", function(self)
    setValue(self:GetChecked() and true or false)
  end)
  check.RefreshValue = function()
    check:SetChecked(getValue())
  end
  return check
end

local function createSlider(parent, name, label, anchorTo, xOffset, yOffset, minValue, maxValue, step, getValue, setValue, formatValue)
  local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", xOffset, yOffset)
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

  panel.socialHeader = addHeader(panel, "Social Notifications", panel.title, -24)

  panel.textAlertCheck = createCheckbox(panel, "SodBalastRosterOptionsTextAlert",
    "Show a chat message when players come online",
    panel.socialHeader, -2, -12,
    Store.IsNotifyTextEnabled, Store.SetNotifyTextEnabled)

  panel.soundAlertCheck = createCheckbox(panel, "SodBalastRosterOptionsSoundAlert",
    "Play a sound when players come online",
    panel.textAlertCheck, 0, -8,
    Store.IsNotifySoundEnabled, Store.SetNotifySoundEnabled)

  panel.debugHeader = addHeader(panel, "Debug", panel.soundAlertCheck, -28)

  panel.debugCheck = createCheckbox(panel, "SodBalastRosterOptionsDebug",
    "Enable debug tools",
    panel.debugHeader, -2, -12,
    Store.IsCommDebugEnabled, function(value)
      Store.SetCommDebugEnabled(value)
      if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
        ns.UI.Refresh()
      end
    end)

  panel.debugNote = addNote(panel,
    "Logs addon-to-addon communication traffic and adds the Debug tab to the window. Turning it off hides that tab.",
    panel.debugCheck, 0, -6)

  panel.advancedHeader = addHeader(panel, "Advanced: Network Frequency", panel.debugNote, -20)

  panel.advancedNote = addNote(panel,
    "Higher values reduce channel traffic and load, at the cost of taking longer to detect changes.",
    panel.advancedHeader, 0, -6)

  panel.scanSlider = createSlider(panel, "SodBalastRosterOptionsScanInterval",
    "Channel scan", panel.advancedNote, 10, -30,
    15, 120, 5,
    function() return Store.GetAdvancedState().scanInterval end,
    function(value) Store.SetAdvancedValue("scanInterval", value) end,
    formatSeconds)

  panel.rosterSummarySlider = createSlider(panel, "SodBalastRosterOptionsRosterSummary",
    "Roster summary", panel.scanSlider, 0, -40,
    60, 900, 30,
    function() return Store.GetAdvancedState().rosterSummaryInterval end,
    function(value) Store.SetAdvancedValue("rosterSummaryInterval", value) end,
    formatSeconds)

  panel.chatSummarySlider = createSlider(panel, "SodBalastRosterOptionsChatSummary",
    "Chat summary", panel.rosterSummarySlider, 0, -40,
    60, 900, 30,
    function() return Store.GetAdvancedState().chatSummaryInterval end,
    function(value) Store.SetAdvancedValue("chatSummaryInterval", value) end,
    formatSeconds)

  panel.whoIntervalSlider = createSlider(panel, "SodBalastRosterOptionsWhoInterval",
    "/who queries", panel.chatSummarySlider, 0, -40,
    3, 30, 1,
    function() return Store.GetAdvancedState().whoRequestInterval end,
    function(value) Store.SetAdvancedValue("whoRequestInterval", value) end,
    formatSeconds)

  panel.sendIntervalSlider = createSlider(panel, "SodBalastRosterOptionsSendInterval",
    "Addon message send rate", panel.whoIntervalSlider, 0, -40,
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

  -- Blizzard: the first call in a session doesn't always highlight the panel; it must be called twice.
  InterfaceOptionsFrame_OpenToCategory(Options.panel)
  InterfaceOptionsFrame_OpenToCategory(Options.panel)
end

local addonName, ns = ...

local Utils = ns.Utils
local Store = ns.Store
local UI = {
  rows = {},
}
ns.UI = UI

local TAB_ROSTER = "roster"
local TAB_HISTORY = "history"
local ROW_HEIGHT = 18
local VISIBLE_ROWS = 16

local HISTORY_LABELS = {
  channel_message = "message",
  joined_channel = "joined channel",
  left_channel = "left channel",
  profile_discovered = "profile discovered",
  level_changed = "level changed",
  zone_changed = "zone changed",
  guild_changed = "guild changed",
}

local function createCheckLabel(checkButton, text)
  local label = checkButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("LEFT", checkButton, "RIGHT", 2, 1)
  label:SetText(text)
  return label
end

local function createLabel(parent, width, justify)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetWidth(width)
  label:SetJustifyH(justify or "LEFT")
  label:SetHeight(ROW_HEIGHT)
  return label
end

local function setRowTexts(row, member)
  row.online:SetText(member.isOnlineInChannel and "Y" or "N")
  row.name:SetText(member.name or "")
  row.addon:SetText(member.hasAddon and "Y" or "-")
  row.level:SetText(member.level and member.level > 0 and tostring(member.level) or "?")
  row.class:SetText(member.classFile ~= "" and member.classFile or "?")
  row.zone:SetText(member.zone ~= "" and member.zone or "?")
  row.guild:SetText(member.guildName ~= "" and member.guildName or "?")
  row.lastSeen:SetText(member.isOnlineInChannel and "Online" or Utils.FormatLastSeen(member.lastSeenAt))
end

local function createRow(parent, index)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(820, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -120 - ((index - 1) * ROW_HEIGHT))
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  row.online = createLabel(row, 28, "LEFT")
  row.online:SetPoint("LEFT", row, "LEFT", 0, 0)

  row.name = createLabel(row, 150, "LEFT")
  row.name:SetPoint("LEFT", row.online, "RIGHT", 4, 0)

  row.addon = createLabel(row, 42, "LEFT")
  row.addon:SetPoint("LEFT", row.name, "RIGHT", 4, 0)

  row.level = createLabel(row, 40, "LEFT")
  row.level:SetPoint("LEFT", row.addon, "RIGHT", 4, 0)

  row.class = createLabel(row, 90, "LEFT")
  row.class:SetPoint("LEFT", row.level, "RIGHT", 4, 0)

  row.zone = createLabel(row, 180, "LEFT")
  row.zone:SetPoint("LEFT", row.class, "RIGHT", 4, 0)

  row.guild = createLabel(row, 170, "LEFT")
  row.guild:SetPoint("LEFT", row.zone, "RIGHT", 4, 0)

  row.lastSeen = createLabel(row, 70, "LEFT")
  row.lastSeen:SetPoint("LEFT", row.guild, "RIGHT", 4, 0)

  row:SetScript("OnDoubleClick", function(self)
    if self.member then
      ChatFrame_SendTell(self.member.name)
    end
  end)

  row:SetScript("OnClick", function(self, button)
    if not self.member then
      return
    end

    if button == "RightButton" then
      InviteUnit(self.member.name)
    end
  end)

  return row
end

local function createTabButton(parent, text, x, tabName)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(90, 20)
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -32)
  button:SetText(text)
  button:SetScript("OnClick", function()
    Store.SetUIFlag("selectedTab", tabName)
    UI.Refresh()
  end)
  return button
end

local function formatHistoryEntry(entry)
  if entry.type == "channel_message" then
    return string.format("[%s] <%s> %s", date("%H:%M:%S", entry.at), entry.name, entry.details or "")
  end

  local label = HISTORY_LABELS[entry.type] or entry.type
  if entry.details and entry.details ~= "" then
    return string.format("[%s] %s: %s (%s)", date("%H:%M:%S", entry.at), entry.name, label, entry.details)
  end

  return string.format("[%s] %s: %s", date("%H:%M:%S", entry.at), entry.name, label)
end

function UI.Create()
  if UI.frame then
    return UI.frame
  end

  local state = Store.GetUIState()
  local frame = CreateFrame("Frame", "SodBalastRosterFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(state.width or 860, state.height or 420)
  frame:SetPoint(state.point or "CENTER", UIParent, state.relativePoint or state.point or "CENTER", state.x or 0, state.y or 0)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    Store.SaveFramePosition(self)
  end)
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 8, 0)
  frame.title:SetText("SodBalastRoster")

  frame.rosterTab = createTabButton(frame, "Roster", 12, TAB_ROSTER)
  frame.historyTab = createTabButton(frame, "Chat", 110, TAB_HISTORY)

  frame.onlyOnline = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  frame.onlyOnline:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -60)
  frame.onlyOnline.label = createCheckLabel(frame.onlyOnline, "Only online")
  frame.onlyOnline:SetScript("OnClick", function(self)
    Store.SetUIFlag("onlyOnline", self:GetChecked() and true or false)
    UI.Refresh()
  end)

  frame.onlyAddon = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  frame.onlyAddon:SetPoint("LEFT", frame.onlyOnline.label, "RIGHT", 20, 0)
  frame.onlyAddon.label = createCheckLabel(frame.onlyAddon, "Only addon")
  frame.onlyAddon:SetScript("OnClick", function(self)
    Store.SetUIFlag("onlyAddon", self:GetChecked() and true or false)
    UI.Refresh()
  end)

  frame.searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  frame.searchBox:SetSize(160, 20)
  frame.searchBox:SetPoint("LEFT", frame.onlyAddon.label, "RIGHT", 30, 0)
  frame.searchBox:SetAutoFocus(false)
  frame.searchBox:SetTextInsets(6, 6, 0, 0)
  frame.searchBox:SetScript("OnEnterPressed", function(self)
    Store.SetUIFlag("search", self:GetText() or "")
    self:ClearFocus()
    UI.Refresh()
  end)
  frame.searchBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)

  frame.refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.refreshButton:SetSize(80, 20)
  frame.refreshButton:SetPoint("LEFT", frame.searchBox, "RIGHT", 10, 0)
  frame.refreshButton:SetText("Refresh")
  frame.refreshButton:SetScript("OnClick", function()
    ns.Channel.EnsureJoined()
    ns.Channel.ScanRoster()
    UI.Refresh()
  end)

  frame.debugButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.debugButton:SetSize(70, 20)
  frame.debugButton:SetPoint("LEFT", frame.refreshButton, "RIGHT", 8, 0)
  frame.debugButton:SetText("Debug")
  frame.debugButton:SetScript("OnClick", function()
    if ns.Core and ns.Core.RunDebug then
      ns.Core.RunDebug()
    end
  end)

  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.status:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -64)
  frame.status:SetText("")

  frame.emptyState = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.emptyState:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -140)
  frame.emptyState:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
  frame.emptyState:SetJustifyH("LEFT")
  frame.emptyState:SetJustifyV("TOP")
  frame.emptyState:SetText("")

  frame.rosterHeaders = {}
  local headers = {
    { text = "On", x = 12, width = 28 },
    { text = "Name", x = 44, width = 150 },
    { text = "A", x = 198, width = 42 },
    { text = "Lvl", x = 244, width = 40 },
    { text = "Class", x = 288, width = 90 },
    { text = "Zone", x = 382, width = 180 },
    { text = "Guild", x = 566, width = 170 },
    { text = "Last Seen", x = 740, width = 70 },
  }

  for _, header in ipairs(headers) do
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", header.x, -100)
    label:SetWidth(header.width)
    label:SetJustifyH("LEFT")
    label:SetText(header.text)
    frame.rosterHeaders[#frame.rosterHeaders + 1] = label
  end

  frame.historyHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.historyHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -96)
  frame.historyHeader:SetText("Channel Chat")

  for index = 1, VISIBLE_ROWS do
    UI.rows[index] = createRow(frame, index)
  end

  frame.scrollFrame = CreateFrame("ScrollFrame", "SodBalastRosterScrollFrame", frame, "FauxScrollFrameTemplate")
  frame.scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -116)
  frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 36)
  frame.scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UI.RefreshRoster)
  end)

  frame.historyBox = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  frame.historyBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -120)
  frame.historyBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 40)

  frame.historyText = CreateFrame("EditBox", nil, frame.historyBox)
  frame.historyText:SetMultiLine(true)
  frame.historyText:SetFontObject(ChatFontNormal)
  frame.historyText:SetWidth(800)
  frame.historyText:SetHeight(1)
  frame.historyText:SetAutoFocus(false)
  frame.historyText:EnableMouse(false)
  frame.historyText:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  frame.historyBox:SetScrollChild(frame.historyText)

  UI.frame = frame
  return frame
end

function UI.RefreshRoster()
  local frame = UI.Create()
  local data = Store.GetVisibleRoster()
  local total = #data
  local offset = FauxScrollFrame_GetOffset(frame.scrollFrame)
  local channelStatus = ns.Channel.DebugStatus()

  FauxScrollFrame_Update(frame.scrollFrame, total, VISIBLE_ROWS, ROW_HEIGHT)

  for index = 1, VISIBLE_ROWS do
    local row = UI.rows[index]
    local member = data[index + offset]
    row.member = member

    if member then
      setRowTexts(row, member)
      row:Show()
    else
      row:Hide()
    end
  end

  local online = 0
  local withAddon = 0
  for _, member in ipairs(data) do
    if member.isOnlineInChannel then
      online = online + 1
    end
    if member.hasAddon then
      withAddon = withAddon + 1
    end
  end

  local statusText = string.format("Online %d  Addon %d  Total %d", online, withAddon, total)
  frame.status:SetText(statusText)

  if total == 0 then
    frame.emptyState:Show()
    local message = string.format(
      "No hay miembros visibles en el roster local.\n\nCanal ID: %s\nDisplay Index: %s\nVisible Count: %s\nMember Count: %s\nResolved Count: %s\nLast Scan OK: %s\nReason: %s",
      tostring(channelStatus.channelId),
      tostring(channelStatus.displayIndex),
      tostring(channelStatus.visibleCount),
      tostring(channelStatus.lastMemberCount),
      tostring(channelStatus.lastResolvedCount),
      tostring(channelStatus.lastScanOk),
      tostring(channelStatus.lastScanReason)
    )

    if channelStatus.lastFallbackPlayer then
      message = message .. string.format("\nFallback candidate: %s", tostring(channelStatus.lastFallbackPlayer))
    end

    if channelStatus.lastScanReason == "roster_names_unresolved" then
      message = message .. "\n\nEl canal parece existir y tener miembros, pero la API no esta resolviendo nombres del roster."
    end

    message = message .. "\n\nPrueba `/sb debug` y pulsa `Refresh` dentro de SODBALAST."
    frame.emptyState:SetText(message)
  else
    frame.emptyState:Hide()
  end
end

function UI.RefreshHistory()
  local frame = UI.Create()
  local lines = {}
  local entries = ns.History.GetEntries()

  for index = 1, #entries do
    local entry = entries[index]
    lines[#lines + 1] = formatHistoryEntry(entry)
  end

  local text = #lines > 0 and table.concat(lines, "\n") or "No history yet."
  frame.historyText:SetText(text)
  frame.historyText:SetHeight(math.max(1, math.max(#lines, 1) * 14))
  frame.historyBox:SetVerticalScroll(0)
  frame.status:SetText(string.format("History entries %d", #entries))
end

function UI.Refresh()
  local frame = UI.Create()
  local uiState = Store.GetUIState()

  frame.onlyOnline:SetChecked(uiState.onlyOnline)
  frame.onlyAddon:SetChecked(uiState.onlyAddon)
  frame.searchBox:SetText(uiState.search or "")

  local rosterSelected = uiState.selectedTab ~= TAB_HISTORY
  frame.onlyOnline:SetShown(rosterSelected)
  frame.onlyOnline.label:SetShown(rosterSelected)
  frame.onlyAddon:SetShown(rosterSelected)
  frame.onlyAddon.label:SetShown(rosterSelected)
  frame.searchBox:SetShown(rosterSelected)
  frame.refreshButton:SetShown(rosterSelected)
  frame.debugButton:SetShown(rosterSelected)
  frame.historyHeader:SetShown(not rosterSelected)
  for _, header in ipairs(frame.rosterHeaders) do
    header:SetShown(rosterSelected)
  end

  for _, row in ipairs(UI.rows) do
    if rosterSelected then
      row:Show()
    else
      row:Hide()
    end
  end

  frame.scrollFrame:SetShown(rosterSelected)
  frame.historyBox:SetShown(not rosterSelected)
  frame.emptyState:SetShown(rosterSelected)

  if rosterSelected then
    UI.RefreshRoster()
  else
    frame.emptyState:Hide()
    UI.RefreshHistory()
  end
end

function UI.Toggle()
  local frame = UI.Create()
  if frame:IsShown() then
    frame:Hide()
    return
  end

  frame:Show()
  UI.Refresh()
end

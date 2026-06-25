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

local CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local function openFallbackMenu(anchor, member)
  UI.activeMenuMember = member

  local menu = {
    {
      text = member.name,
      isTitle = true,
      notCheckable = true,
    },
    {
      text = "Whisper",
      notCheckable = true,
      func = function()
        ChatFrame_SendTell(member.name)
      end,
    },
    {
      text = "Invite",
      notCheckable = true,
      func = function()
        InviteUnit(member.name)
      end,
    },
    {
      text = "Target",
      notCheckable = true,
      func = function()
        TargetByName(member.name, true)
      end,
    },
    {
      text = "Refresh Info",
      notCheckable = true,
      func = function()
        if member.hasAddon then
          ns.Comm.QueueProfileRequest(member.name)
        else
          ns.Who.RequestOneFromHardwareEvent(member.name)
        end
      end,
    },
  }

  if not UI.dropdown then
    UI.dropdown = CreateFrame("Frame", "SodBalastRosterDropdown", UIParent, "UIDropDownMenuTemplate")
    UI.dropdown:SetFrameStrata("FULLSCREEN_DIALOG")
  end

  EasyMenu(menu, UI.dropdown, "cursor", 0, 0, "MENU", 2)
end

local function openNameMenu(anchor, member)
  if not anchor or not member or not member.name then
    return
  end

  openFallbackMenu(anchor, member)
end

local function getClassColor(classFile)
  local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  return colors and colors[classFile or ""] or nil
end

local function getClassIconTag(classFile)
  local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile or ""]
  if not coords then
    return nil
  end

  return string.format(
    "|T%s:14:14:0:0:256:256:%d:%d:%d:%d|t",
    CLASS_ICON_TEXTURE,
    coords[1] * 256,
    coords[2] * 256,
    coords[3] * 256,
    coords[4] * 256
  )
end

local function colorizeName(name)
  local member = Store.GetMember(name)
  local classColor = member and getClassColor(member.classFile) or nil
  if not classColor then
    return name or "?"
  end

  return string.format("|cff%02x%02x%02x%s|r",
    math.floor((classColor.r or 1) * 255),
    math.floor((classColor.g or 1) * 255),
    math.floor((classColor.b or 1) * 255),
    name or "?"
  )
end

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
  local classColor = getClassColor(member.classFile)
  if classColor then
    row.name:SetTextColor(classColor.r, classColor.g, classColor.b)
  else
    row.name:SetTextColor(1, 1, 1)
  end

  row.addon:SetText(member.hasAddon and "Y" or "-")
  row.name:SetText(member.name or "")
  row.level:SetText(member.level and member.level > 0 and tostring(member.level) or "?")

  local classIcon = getClassIconTag(member.classFile)
  if classIcon then
    row.class:SetText(classIcon)
  else
    row.class:SetText(member.classFile ~= "" and member.classFile or "?")
  end

  row.zone:SetText(member.zone ~= "" and member.zone or "?")
  row.guild:SetText(member.guildName ~= "" and member.guildName or "?")
  row.lastSeen:SetText(member.isOnlineInChannel and "Online" or Utils.FormatLastSeen(member.lastSeenAt))
end

local function createRow(parent, index)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(820, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -120 - ((index - 1) * ROW_HEIGHT))
  row:EnableMouse(true)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  row.highlight = row:CreateTexture(nil, "BACKGROUND")
  row.highlight:SetAllPoints(row)
  row.highlight:SetColorTexture(1, 1, 1, 0.08)
  row.highlight:Hide()

  row.addon = createLabel(row, 28, "LEFT")
  row.addon:SetPoint("LEFT", row, "LEFT", 4, 0)

  row.name = createLabel(row, 150, "LEFT")
  row.name:SetPoint("LEFT", row.addon, "RIGHT", 4, 0)

  row.level = createLabel(row, 40, "LEFT")
  row.level:SetPoint("LEFT", row.name, "RIGHT", 4, 0)

  row.class = createLabel(row, 90, "LEFT")
  row.class:SetPoint("LEFT", row.level, "RIGHT", 4, 0)

  row.zone = createLabel(row, 180, "LEFT")
  row.zone:SetPoint("LEFT", row.class, "RIGHT", 4, 0)

  row.guild = createLabel(row, 170, "LEFT")
  row.guild:SetPoint("LEFT", row.zone, "RIGHT", 4, 0)

  row.lastSeen = createLabel(row, 70, "LEFT")
  row.lastSeen:SetPoint("LEFT", row.guild, "RIGHT", 4, 0)

  row:SetScript("OnEnter", function(self)
    self.highlight:Show()
  end)

  row:SetScript("OnLeave", function(self)
    self.highlight:Hide()
  end)

  row:SetScript("OnMouseUp", function(self, button)
    if not self.member then
      return
    end

    if button == "RightButton" then
      openNameMenu(self, self.member)
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
    return string.format("[%s] <%s> %s", date("%H:%M:%S", entry.at), colorizeName(entry.name), entry.details or "")
  end

  local label = HISTORY_LABELS[entry.type] or entry.type
  if entry.details and entry.details ~= "" then
    return string.format("[%s] %s: %s (%s)", date("%H:%M:%S", entry.at), colorizeName(entry.name), label, entry.details)
  end

  return string.format("[%s] %s: %s", date("%H:%M:%S", entry.at), colorizeName(entry.name), label)
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
  frame.title:SetText(string.format("SodBalastRoster v%s", ns.version or "dev"))

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
  frame.searchBox:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then
      return
    end

    Store.SetUIFlag("search", self:GetText() or "")
    if Store.GetUIState().selectedTab ~= TAB_HISTORY then
      UI.RefreshRoster()
    end
  end)
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
    { text = "A", x = 12, width = 28 },
    { text = "Name", x = 44, width = 150 },
    { text = "Lvl", x = 198, width = 40 },
    { text = "Class", x = 242, width = 90 },
    { text = "Zone", x = 336, width = 180 },
    { text = "Guild", x = 520, width = 170 },
    { text = "Last Seen", x = 694, width = 70 },
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
  local previousScroll = frame.historyBox:GetVerticalScroll() or 0

  for index = 1, #entries do
    local entry = entries[index]
    if entry.type == "channel_message" then
      lines[#lines + 1] = formatHistoryEntry(entry)
    end
  end

  local text = #lines > 0 and table.concat(lines, "\n") or "No history yet."
  frame.historyText:SetText(text)
  frame.historyText:SetHeight(math.max(1, math.max(#lines, 1) * 14))

  local maxScroll = math.max(0, frame.historyText:GetHeight() - frame.historyBox:GetHeight())
  frame.historyBox:SetVerticalScroll(math.min(previousScroll, maxScroll))
  frame.status:SetText(string.format("Chat messages %d", #lines))
end

function UI.Refresh()
  local frame = UI.Create()
  local uiState = Store.GetUIState()

  frame.onlyOnline:SetChecked(uiState.onlyOnline)
  frame.onlyAddon:SetChecked(uiState.onlyAddon)
  if not frame.searchBox:HasFocus() and frame.searchBox:GetText() ~= (uiState.search or "") then
    frame.searchBox:SetText(uiState.search or "")
  end

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

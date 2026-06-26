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
local TAB_ICON_SIZE = 40

local TAB_TEXTURES = {
  [TAB_ROSTER] = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
  [TAB_HISTORY] = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up",
}

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

local function runMenuAction(action, member)
  if not member or not member.name then
    return
  end

  if action == "whisper" then
    ChatFrame_SendTell(member.name)
  elseif action == "invite" then
    InviteUnit(member.name)
  elseif action == "target" then
    TargetByName(member.name, true)
  elseif action == "refresh" then
    if member.hasAddon then
      ns.Comm.QueueProfileRequest(member.name)
    else
      ns.Who.RequestOneFromHardwareEvent(member.name)
    end
  end

  if UI.contextMenu then
    UI.contextMenu:Hide()
  end
end

local function ensureContextMenu()
  if UI.contextMenu then
    return UI.contextMenu
  end

  local menu = CreateFrame("Frame", "SodBalastRosterContextMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate")
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetToplevel(true)
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  menu:SetSize(170, 132)

  if menu.SetBackdrop then
    menu:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    menu:SetBackdropColor(0.05, 0.05, 0.05, 0.96)
    menu:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  end

  menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -10)
  menu.title:SetPoint("RIGHT", menu, "RIGHT", -10, 0)
  menu.title:SetJustifyH("LEFT")

  local actions = {
    { key = "whisper", text = "Whisper" },
    { key = "invite", text = "Invite" },
    { key = "target", text = "Target" },
    { key = "refresh", text = "Refresh Info" },
  }

  menu.buttons = {}
  for index, action in ipairs(actions) do
    local button = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
    button:SetSize(146, 20)
    button:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -26 - ((index - 1) * 24))
    button:SetText(action.text)
    button.actionKey = action.key
    button:SetScript("OnClick", function()
      runMenuAction(action.key, menu.member)
    end)
    menu.buttons[#menu.buttons + 1] = button
  end

  menu:SetScript("OnMouseDown", function(_, button)
    if button == "RightButton" then
      menu:Hide()
    end
  end)

  UI.contextMenu = menu
  return menu
end

local function openFallbackMenu(anchor, member)
  local menu = ensureContextMenu()
  menu.member = member
  menu.title:SetText(member.name or "?")

  for _, button in ipairs(menu.buttons) do
    if button.actionKey == "refresh" then
      button:SetShown(not member.hasAddon)
    else
      button:SetShown(true)
    end
  end

  local scale = UIParent:GetEffectiveScale()
  local x, y = GetCursorPosition()
  x = x / scale
  y = y / scale

  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + 8, y + 8)
  menu:Show()
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

local function getProfessionIconsText(member)
  local icons = {}

  if member.profession1Icon and member.profession1Icon ~= "" and tostring(member.profession1Icon) ~= "0" then
    icons[#icons + 1] = string.format("|T%s:14:14:0:0|t", tostring(member.profession1Icon))
  end

  if member.profession2Icon and member.profession2Icon ~= "" and tostring(member.profession2Icon) ~= "0" then
    icons[#icons + 1] = string.format("|T%s:14:14:0:0|t", tostring(member.profession2Icon))
  end

  if #icons > 0 then
    return table.concat(icons, " ")
  end

  return nil
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
  local professions = member.hasAddon and "-" or "?"
  local professionIcons = getProfessionIconsText(member)
  if professionIcons then
    professions = professionIcons
  elseif member.profession1 ~= "" or member.profession2 ~= "" then
    professions = table.concat({ member.profession1 ~= "" and member.profession1 or "-", member.profession2 ~= "" and member.profession2 or "-" }, " / ")
  end
  row.profs:SetText(professions)
  row.lastSeen:SetText(member.isOnlineInChannel and "Online" or Utils.FormatLastSeen(member.lastSeenAt))
end

local function createRow(parent, index)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(848, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -120 - ((index - 1) * ROW_HEIGHT))
  row:EnableMouse(true)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  local function handleRightClick(anchor, button)
    if button ~= "RightButton" or not row.member then
      return
    end

    openNameMenu(anchor, row.member)
  end

  row.highlight = row:CreateTexture(nil, "BACKGROUND")
  row.highlight:SetAllPoints(row)
  row.highlight:SetColorTexture(1, 1, 1, 0.08)
  row.highlight:Hide()

  row.addon = createLabel(row, 28, "LEFT")
  row.addon:SetPoint("LEFT", row, "LEFT", 4, 0)

  row.name = createLabel(row, 150, "LEFT")
  row.name:SetPoint("LEFT", row.addon, "RIGHT", 4, 0)

  row.nameButton = CreateFrame("Button", nil, row)
  row.nameButton:SetSize(150, ROW_HEIGHT)
  row.nameButton:SetPoint("LEFT", row.addon, "RIGHT", 4, 0)
  row.nameButton:EnableMouse(true)
  row.nameButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.nameButton:SetScript("OnClick", handleRightClick)
  row.nameButton:SetScript("OnEnter", function()
    row.highlight:Show()
  end)
  row.nameButton:SetScript("OnLeave", function()
    row.highlight:Hide()
  end)

  row.level = createLabel(row, 40, "LEFT")
  row.level:SetPoint("LEFT", row.name, "RIGHT", 4, 0)

  row.class = createLabel(row, 90, "LEFT")
  row.class:SetPoint("LEFT", row.level, "RIGHT", 4, 0)

  row.zone = createLabel(row, 170, "LEFT")
  row.zone:SetPoint("LEFT", row.class, "RIGHT", 4, 0)

  row.guild = createLabel(row, 130, "LEFT")
  row.guild:SetPoint("LEFT", row.zone, "RIGHT", 4, 0)

  row.profs = createLabel(row, 130, "LEFT")
  row.profs:SetPoint("LEFT", row.guild, "RIGHT", 4, 0)

  row.lastSeen = createLabel(row, 70, "LEFT")
  row.lastSeen:SetPoint("LEFT", row.profs, "RIGHT", 4, 0)

  row:SetScript("OnEnter", function(self)
    self.highlight:Show()
  end)

  row:SetScript("OnLeave", function(self)
    self.highlight:Hide()
  end)

  row:SetScript("OnClick", handleRightClick)

  return row
end

local function updateTabButtonState(button, selected)
  if selected then
    button:SetBackdropColor(0.24, 0.32, 0.44, 0.95)
    button:SetBackdropBorderColor(0.85, 0.82, 0.58, 1)
    button.icon:SetAlpha(1)
  else
    button:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    button:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
    button.icon:SetAlpha(0.75)
  end
end

local function createTabButton(parent, x, y, tabName, tooltipText)
  local button = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
  button:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
  button:SetPoint("TOPLEFT", parent, "TOPRIGHT", x, y)
  button:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })

  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -6)
  button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6, 6)
  button.icon:SetTexture(TAB_TEXTURES[tabName])
  if tabName == TAB_HISTORY then
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  else
    button.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  end

  button:SetScript("OnClick", function()
    Store.SetUIFlag("selectedTab", tabName)
    UI.Refresh()
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(tooltipText)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
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

local function sendChatMessageFromInput()
  local frame = UI.Create()
  local text = Utils.Trim(frame.chatInput:GetText() or "")
  if text == "" then
    return
  end

  local channelId = ns.Channel.GetChannelId()
  if not channelId or channelId <= 0 then
    ns.Utils.Print("SODBALAST is not available.")
    return
  end

  SendChatMessage(text, "CHANNEL", nil, channelId)
  frame.chatInput:SetText("")
  frame.historyShouldScrollToBottom = true
end

local function scrollHistoryToBottom()
  if not UI.frame or not UI.frame.historyBox then
    return
  end

  if UI.frame.historyBox.ScrollToBottom then
    UI.frame.historyBox:ScrollToBottom()
  end

  UI.frame.historyScrollPosition = 0
  UI.frame.historyScrollMax = math.max(UI.frame.historyScrollMax or 0, 0)

  if UI.UpdateHistoryIndicator then
    UI.UpdateHistoryIndicator()
  end
end

local function restoreHistoryScroll(position)
  if not UI.frame or not UI.frame.historyBox or position == nil then
    return
  end

  local box = UI.frame.historyBox
  if position <= 0 then
    scrollHistoryToBottom()
    return
  end

  local current = UI.frame.historyScrollPosition or 0

  while current < position do
    if box.ScrollUp then
      box:ScrollUp()
    end
    current = current + 1
  end

  while current > position do
    if box.ScrollDown then
      box:ScrollDown()
    end
    current = current - 1
  end

  UI.frame.historyScrollPosition = position
  UI.frame.historyScrollMax = math.max(UI.frame.historyScrollMax or 0, position)

  if UI.UpdateHistoryIndicator then
    UI.UpdateHistoryIndicator()
  end
end

function UI.UpdateHistoryIndicator()
  if not UI.frame or not UI.frame.historyBox or not UI.frame.historyScrollBar then
    return
  end

  local box = UI.frame.historyBox
  local bar = UI.frame.historyScrollBar
  local total = box.GetNumMessages and box:GetNumMessages() or 0
  local visibleLines = math.max(1, math.floor((box:GetHeight() or 1) / 14))
  local estimatedMax = math.max(0, total - visibleLines)
  local maxValue = math.max(estimatedMax, UI.frame.historyScrollMax or 0)
  local current = math.min(UI.frame.historyScrollPosition or 0, maxValue)

  if maxValue <= 0 then
    bar:Hide()
    return
  end

  bar:Show()
  bar:SetMinMaxValues(0, maxValue)
  bar.updating = true
  bar:SetValue(maxValue - current)
  bar.updating = false
  bar.lastValue = maxValue - current

  if bar.ScrollUpButton then
    bar.ScrollUpButton:SetEnabled(current < maxValue)
  end
  if bar.ScrollDownButton then
    bar.ScrollDownButton:SetEnabled(current > 0)
  end
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

  frame.rosterTab = createTabButton(frame, 8, -56, TAB_ROSTER, "Roster")
  frame.historyTab = createTabButton(frame, 8, -102, TAB_HISTORY, "Chat")

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
    { text = "Zone", x = 336, width = 170 },
    { text = "Guild", x = 510, width = 130 },
    { text = "Profs", x = 644, width = 130 },
    { text = "Last Seen", x = 778, width = 70 },
  }

  for _, header in ipairs(headers) do
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", header.x, -100)
    label:SetWidth(header.width)
    label:SetJustifyH("LEFT")
    label:SetText(header.text)
    frame.rosterHeaders[#frame.rosterHeaders + 1] = label
  end

  for index = 1, VISIBLE_ROWS do
    UI.rows[index] = createRow(frame, index)
  end

  frame.scrollFrame = CreateFrame("ScrollFrame", "SodBalastRosterScrollFrame", frame, "FauxScrollFrameTemplate")
  frame.scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -116)
  frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 36)
  frame.scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UI.RefreshRoster)
  end)

  frame.historyBox = CreateFrame("ScrollingMessageFrame", nil, frame)
  frame.historyBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -96)
  frame.historyBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 68)
  frame.historyBox:SetFontObject(ChatFontNormal)
  frame.historyBox:SetJustifyH("LEFT")
  frame.historyBox:SetFading(false)
  frame.historyBox:SetIndentedWordWrap(false)
  frame.historyBox:SetMaxLines(1000)
  frame.historyScrollPosition = 0
  frame.historyScrollMax = 0
  frame.historyBox:EnableMouseWheel(true)
  frame.historyBox:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then
      self:ScrollUp()
      frame.historyScrollPosition = (frame.historyScrollPosition or 0) + 1
      if self.AtTop and self:AtTop() then
        frame.historyScrollMax = frame.historyScrollPosition
      else
        frame.historyScrollMax = math.max(frame.historyScrollMax or 0, frame.historyScrollPosition)
      end
    else
      self:ScrollDown()
      frame.historyScrollPosition = math.max(0, (frame.historyScrollPosition or 0) - 1)
    end

    UI.UpdateHistoryIndicator()
  end)

  frame.historyScrollBar = CreateFrame("Slider", nil, frame, "UIPanelScrollBarTemplate")
  frame.historyScrollBar:SetPoint("TOPLEFT", frame.historyBox, "TOPRIGHT", 4, -16)
  frame.historyScrollBar:SetPoint("BOTTOMLEFT", frame.historyBox, "BOTTOMRIGHT", 4, 16)
  frame.historyScrollBar:SetMinMaxValues(0, 0)
  frame.historyScrollBar:SetValueStep(1)
  frame.historyScrollBar:SetObeyStepOnDrag(true)
  frame.historyScrollBar:EnableMouse(false)
  frame.historyScrollBar:SetScript("OnValueChanged", function(self, value)
    if self.updating then
      return
    end

    self.updating = true
    self:SetValue(self.lastValue or value or 0)
    self.updating = false

    if not self.buttonScrolling then
      return
    end

    local box = frame.historyBox
    local total = box.GetNumMessages and box:GetNumMessages() or 0
    local visibleLines = math.max(1, math.floor((box:GetHeight() or 1) / 14))
    local maxValue = math.max(math.max(0, total - visibleLines), frame.historyScrollMax or 0)
    local targetPosition = math.max(0, math.min(maxValue, maxValue - math.floor((value or 0) + 0.5)))

    restoreHistoryScroll(targetPosition)
  end)

  frame.historyScrollBar.ScrollUpButton:SetScript("OnClick", function()
    local box = frame.historyBox
    frame.historyScrollBar.buttonScrolling = true
    box:ScrollUp()
    frame.historyScrollPosition = (frame.historyScrollPosition or 0) + 1
    if box.AtTop and box:AtTop() then
      frame.historyScrollMax = frame.historyScrollPosition
    else
      frame.historyScrollMax = math.max(frame.historyScrollMax or 0, frame.historyScrollPosition)
    end
    UI.UpdateHistoryIndicator()
    frame.historyScrollBar.buttonScrolling = false
  end)
  frame.historyScrollBar.ScrollUpButton:EnableMouse(true)
  frame.historyScrollBar.ScrollDownButton:SetScript("OnClick", function()
    local box = frame.historyBox
    frame.historyScrollBar.buttonScrolling = true
    box:ScrollDown()
    frame.historyScrollPosition = math.max(0, (frame.historyScrollPosition or 0) - 1)
    UI.UpdateHistoryIndicator()
    frame.historyScrollBar.buttonScrolling = false
  end)
  frame.historyScrollBar.ScrollDownButton:EnableMouse(true)

  frame.chatInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  frame.chatInput:SetSize(780, 20)
  frame.chatInput:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 34)
  frame.chatInput:SetAutoFocus(false)
  frame.chatInput:SetTextInsets(6, 6, 0, 0)
  frame.chatInput:SetScript("OnEnterPressed", function(self)
    sendChatMessageFromInput()
    self:ClearFocus()
  end)
  frame.chatInput:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)

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
  local previousScroll = frame.historyScrollPosition or 0
  local lastMessageId = nil

  for index = 1, #entries do
    local entry = entries[index]
    if entry.type == "channel_message" then
      lines[#lines + 1] = formatHistoryEntry(entry)
      lastMessageId = entry.id or index
    end
  end

  local signature = string.format("%d:%s", #lines, tostring(lastMessageId or "none"))
  if frame.historyLastSignature == signature and not frame.historyShouldScrollToBottom then
    frame.status:SetText("")
    return
  end

  frame.historyLastSignature = signature

  local text = #lines > 0 and table.concat(lines, "\n") or "No history yet."
  frame.historyBox:Clear()

  for line in string.gmatch(text, "([^\n]+)") do
    frame.historyBox:AddMessage(line)
  end

  C_Timer.After(0, UI.UpdateHistoryIndicator)

  if frame.historyShouldScrollToBottom then
    frame.historyShouldScrollToBottom = false
    C_Timer.After(0, scrollHistoryToBottom)
    C_Timer.After(0.05, scrollHistoryToBottom)
  else
    C_Timer.After(0, function()
      restoreHistoryScroll(previousScroll)
    end)
    C_Timer.After(0.05, function()
      restoreHistoryScroll(previousScroll)
    end)
  end
  frame.status:SetText("")
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
  updateTabButtonState(frame.rosterTab, rosterSelected)
  updateTabButtonState(frame.historyTab, not rosterSelected)
  frame.onlyOnline:SetShown(rosterSelected)
  frame.onlyOnline.label:SetShown(rosterSelected)
  frame.onlyAddon:SetShown(rosterSelected)
  frame.onlyAddon.label:SetShown(rosterSelected)
  frame.searchBox:SetShown(rosterSelected)
  frame.refreshButton:SetShown(rosterSelected)
  frame.debugButton:SetShown(rosterSelected)
  frame.chatInput:SetShown(not rosterSelected)
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
  frame.historyScrollBar:SetShown(not rosterSelected)
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

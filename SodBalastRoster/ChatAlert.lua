local addonName, ns = ...

local Store = ns.Store

local ChatAlert = {
  hasPendingChat = false,
}
ns.ChatAlert = ChatAlert

local function getClassColorHex(classFile)
  local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  local color = colors and colors[classFile or ""]
  if not color then
    return "ffffff"
  end

  return string.format("%02x%02x%02x",
    math.floor((color.r or 1) * 255),
    math.floor((color.g or 1) * 255),
    math.floor((color.b or 1) * 255)
  )
end

local function getLevelColorHex(level)
  if not level or level <= 0 then
    return "ffffff"
  end

  if GetCreatureDifficultyColor then
    local color = GetCreatureDifficultyColor(level)
    if color then
      return string.format("%02x%02x%02x",
        math.floor(color.r * 255),
        math.floor(color.g * 255),
        math.floor(color.b * 255)
      )
    end
  end

  local diff = level - (UnitLevel("player") or level)
  if diff <= -5 then
    return "9d9d9d"
  elseif diff <= 2 then
    return "1eff00"
  elseif diff <= 4 then
    return "ffff00"
  else
    return "ff1a1a"
  end
end

local function getOnlineCount()
  local count = 0

  for _, member in pairs(Store.GetRoster()) do
    if member.isOnlineInChannel then
      count = count + 1
    end
  end

  return count
end

local function updateVisualState(frame)
  if not frame then
    return
  end

  frame.onlineText:SetText(string.format("Online: %d", getOnlineCount()))

  if ChatAlert.hasPendingChat then
    frame.messageGlow:Show()
    frame:SetBackdropBorderColor(0.9, 0.82, 0.45, 1)
    frame.pulseTicker:Show()
  else
    frame.messageGlow:Hide()
    frame.messageIcon:SetAlpha(0.35)
    frame:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
    frame.pulseTicker:Hide()
    frame.pulseTime = 0
    frame.messageGlow:SetAlpha(0.14)
  end
end

function ChatAlert.Create()
  if ChatAlert.frame then
    return ChatAlert.frame
  end

  local state = Store.GetChatAlertState()
  local frame = CreateFrame("Button", "SodBalastRosterChatAlert", UIParent, BackdropTemplateMixin and "BackdropTemplate")
  frame:SetSize(128, 30)
  frame:SetPoint(state.point or "TOPRIGHT", UIParent, state.relativePoint or state.point or "TOPRIGHT", state.x or -220, state.y or -120)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
    frame:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
  end

  frame.messageGlow = frame:CreateTexture(nil, "BACKGROUND")
  frame.messageGlow:SetColorTexture(0.96, 0.78, 0.18, 0.14)
  frame.messageGlow:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
  frame.messageGlow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)

  frame.messageIcon = frame:CreateTexture(nil, "ARTWORK")
  frame.messageIcon:SetTexture("Interface\\Icons\\INV_Letter_15")
  frame.messageIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  frame.messageIcon:SetSize(16, 16)
  frame.messageIcon:SetPoint("LEFT", frame, "LEFT", 10, 0)

  frame.onlineText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.onlineText:SetPoint("LEFT", frame.messageIcon, "RIGHT", 8, 0)
  frame.onlineText:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
  frame.onlineText:SetJustifyH("LEFT")

  frame.pulseTicker = CreateFrame("Frame", nil, frame)
  frame.pulseTicker:Hide()
  frame.pulseTicker:SetScript("OnUpdate", function(_, elapsed)
    frame.pulseTime = (frame.pulseTime or 0) + elapsed * 3
    frame.messageGlow:SetAlpha(0.1 + math.max(0, math.sin(frame.pulseTime)) * 0.18)
    frame.messageIcon:SetAlpha(0.35 + (math.sin(frame.pulseTime) + 1) / 2 * 0.65)
  end)

  frame.dragHint = false
  frame.justDragged = false
  frame:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and IsShiftKeyDown() then
      self.dragHint = true
      self.justDragged = false
      self:StartMoving()
    end
  end)
  frame:SetScript("OnMouseUp", function(self)
    if self.dragHint then
      self.dragHint = false
      self.justDragged = true
      self:StopMovingOrSizing()
      Store.SaveChatAlertPosition(self)
    end
  end)
  frame:SetScript("OnHide", function(self)
    if self.dragHint then
      self.dragHint = false
      self:StopMovingOrSizing()
      Store.SaveChatAlertPosition(self)
    end
  end)
  frame:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      if ns.UI and ns.UI.OpenOnlineMenu then
        ns.UI.OpenOnlineMenu(self)
      end
      return
    end

    if frame.justDragged then
      frame.justDragged = false
      return
    end

    if IsShiftKeyDown() then
      return
    end

    if ns.UI and ns.UI.OpenChat then
      ns.UI.OpenChat()
    end
  end)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText("SODBALAST")
    GameTooltip:AddLine(string.format("Online: %d", getOnlineCount()), 1, 1, 1)
    if ChatAlert.hasPendingChat then
      GameTooltip:AddLine("New messages pending", 1, 0.82, 0.3)
    end
    GameTooltip:AddLine("Click to open chat", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click to invite or whisper", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift-drag to move", 0.8, 0.8, 0.8)

    local onlineMembers = {}
    for _, member in pairs(Store.GetRoster()) do
      if member.isOnlineInChannel then
        onlineMembers[#onlineMembers + 1] = member
      end
    end

    if #onlineMembers > 0 then
      table.sort(onlineMembers, function(left, right)
        return (left.name or "") < (right.name or "")
      end)

      GameTooltip:AddLine("----------------------------------------", 0.4, 0.4, 0.4)

      for _, member in ipairs(onlineMembers) do
        local levelText = member.level and member.level > 0 and tostring(member.level) or "?"
        local levelHex = getLevelColorHex(member.level)
        local nameHex = getClassColorHex(member.classFile)
        local nameColumn = string.format("|cff%s%-3s|r  |cff%s%s|r", levelHex, levelText, nameHex, member.name or "?")
        local zoneText = member.zone ~= "" and member.zone or "?"
        GameTooltip:AddDoubleLine(nameColumn, zoneText, 1, 1, 1, 0.8, 0.8, 0.8)
      end
    end

    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  ChatAlert.frame = frame
  updateVisualState(frame)
  return frame
end

function ChatAlert.MarkPendingChat()
  ChatAlert.hasPendingChat = true
end

function ChatAlert.ClearPendingChat()
  ChatAlert.hasPendingChat = false
end

function ChatAlert.Refresh()
  local frame = ChatAlert.Create()
  updateVisualState(frame)
  frame:Show()
end

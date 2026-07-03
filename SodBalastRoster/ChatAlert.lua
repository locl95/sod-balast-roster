local addonName, ns = ...

local Store = ns.Store

local ChatAlert = {
  hasPendingChat = false,
}
ns.ChatAlert = ChatAlert

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
  frame:RegisterForClicks("LeftButtonUp")
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
  frame:SetScript("OnClick", function()
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
    GameTooltip:AddLine("Shift-drag to move", 0.8, 0.8, 0.8)
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

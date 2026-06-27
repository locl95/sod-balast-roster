local addonName, ns = ...

local Store = ns.Store

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local BUTTON_RADIUS = 80

local function updatePosition(button)
  local state = Store.GetMinimapState()
  local angle = math.rad(state.angle or 220)
  local x = math.cos(angle) * BUTTON_RADIUS
  local y = math.sin(angle) * BUTTON_RADIUS

  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function MinimapButton.Create()
  if MinimapButton.frame then
    return MinimapButton.frame
  end

  local button = CreateFrame("Button", "SodBalastRosterMinimapButton", Minimap)
  button:SetSize(32, 32)
  button:SetFrameStrata("MEDIUM")
  button:SetMovable(true)
  button:EnableMouse(true)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  button.border = button:CreateTexture(nil, "OVERLAY")
  button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  button.border:SetSize(54, 54)
  button.border:SetPoint("TOPLEFT")

  button.background = button:CreateTexture(nil, "BACKGROUND")
  button.background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  button.background:SetSize(20, 20)
  button.background:SetPoint("CENTER")

  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetTexture("Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend")
  button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button.icon:SetSize(20, 20)
  button.icon:SetPoint("CENTER")

  button:SetScript("OnClick", function(_, buttonName)
    if buttonName == "LeftButton" then
      ns.UI.Toggle()
    end
  end)

  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function(frame)
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = UIParent:GetEffectiveScale()
      px = px / scale
      py = py / scale
      local angle = math.deg(math.atan2(py - my, px - mx))
      Store.GetMinimapState().angle = angle
      updatePosition(frame)
    end)
  end)

  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("SodBalastRoster")
    GameTooltip:AddLine("Left click: Toggle window", 1, 1, 1)
    GameTooltip:Show()
  end)

  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  MinimapButton.frame = button
  updatePosition(button)

  if Store.GetMinimapState().hidden then
    button:Hide()
  else
    button:Show()
  end

  return button
end
function MinimapButton.Show()
  local button = MinimapButton.Create()
  Store.GetMinimapState().hidden = false
  button:Show()
end

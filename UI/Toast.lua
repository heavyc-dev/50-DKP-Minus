-- Toast: a slip of parchment slides in top-centre with the wax seal, the feat
-- name, the fine and one line of flavor. Stock raid-warning sound; no bundled audio.
local _, ns = ...
local T = {}
ns.Toast = T
local Th = ns.Theme

local frame, queue, busy = nil, {}, false

local function Build()
    frame = CreateFrame("Frame", "FiftyDKPMinusToast", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(400, 92)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -150)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    Th.Cover(frame)

    local page = CreateFrame("Frame", nil, frame)
    page:SetPoint("TOPLEFT", 9, -9)
    page:SetPoint("BOTTOMRIGHT", -9, 9)
    Th.Parchment(page)

    frame.seal = Th.Seal(page, 62, -10)
    frame.seal:SetPoint("LEFT", 12, 0)

    frame.fine = Th.Text(page, "head", 30, Th.RED)
    frame.fine:SetPoint("TOPRIGHT", -16, -13)
    frame.fine:SetJustifyH("RIGHT")

    frame.kicker = Th.Text(page, "body", 10, Th.FADED)
    frame.kicker:SetPoint("TOPLEFT", 86, -12)

    frame.title = Th.Text(page, "head", 19)
    frame.title:SetPoint("TOPLEFT", 86, -24)
    frame.title:SetPoint("RIGHT", frame.fine, "LEFT", -8, 0)
    frame.title:SetWordWrap(false)

    frame.flavor = Th.Text(page, "body", 11, Th.FADED)
    frame.flavor:SetPoint("TOPLEFT", 86, -49)
    frame.flavor:SetPoint("RIGHT", -14, 0)
    frame.flavor:SetWordWrap(false)

    -- Clicking the toast is a hardware event, which is what lets this one line
    -- go to say or General. Right-click dismisses.
    local click = CreateFrame("Button", nil, frame)
    click:SetAllPoints()
    click:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    click:SetScript("OnClick", function(_, mouse)
        if mouse ~= "RightButton" and frame.item then ns.Herald:Reannounce(frame.item) end
        frame.show:Stop()
        frame:Hide()
        busy = false
        T.Next()
    end)
    frame.prompt = Th.Text(page, "body", 9, Th.FADED)
    frame.prompt:SetPoint("BOTTOMRIGHT", -12, 9)

    local show = frame:CreateAnimationGroup()
    local slide = show:CreateAnimation("Translation")
    slide:SetOffset(0, -40); slide:SetDuration(0.3); slide:SetSmoothing("OUT")
    local fadeIn = show:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.3)
    local fadeOut = show:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.6); fadeOut:SetStartDelay(4.8)
    fadeOut:SetOrder(2)
    show:SetScript("OnFinished", function()
        frame:Hide()
        busy = false
        T.Next()
    end)
    frame.show = show

    -- One shake, for the really bad ones.
    local shake = frame:CreateAnimationGroup()
    for i, dx in ipairs({ 12, -24, 20, -14, 6 }) do
        local a = shake:CreateAnimation("Translation")
        a:SetOffset(dx, 0); a:SetDuration(0.05); a:SetOrder(i)
    end
    frame.shake = shake
end

function T.Next()
    if busy or #queue == 0 then return end
    if not frame then Build() end
    local item = table.remove(queue, 1)
    busy = true
    local big = math.abs(item.fine) >= 500
    frame:SetScale(big and 1.3 or 1)
    frame.kicker:SetText(item.fine < 0 and "FORGIVEN" or (ns.TierOf(item.fine).name:upper() .. " FINE"))
    frame.item = item
    local where = ns.settings.shareChannel
    frame.prompt:SetText("Click to announce in " .. (where == "GENERAL" and "/1" or "/" .. where:lower()))
    frame.title:SetText(item.name)
    frame.fine:SetText(ns.FineText(item.fine))
    frame.flavor:SetText(big and "Removed from guild (not really)." or (item.flavor or ""))
    frame:Show()
    frame.show:Stop()
    frame.show:Play()
    if big then frame.shake:Play() end
    if ns.settings.sound and PlaySound and SOUNDKIT then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING or 8959, "Master")
    end
end

function T:Show(f, tier, name, fine)
    if not ns.settings.toast then return end
    if #queue >= 6 then return end      -- a burst of fines should not hold the screen hostage
    queue[#queue + 1] = { name = name, fine = fine, flavor = f.flavor }
    T.Next()
end

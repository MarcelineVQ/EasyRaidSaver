-- || Made by and for Weird Vibes of Turtle WoW || --

local function print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local function ers_print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00ERS:|r "..msg)
end

local function elem(t,item)
  for _,k in t do
    if item == k then
      return true
    end
  end
  return false
end

local function tsize(t)
  local c = 0
  for _ in pairs(t) do c = c + 1 end
  return c
end

-- Addon ---------------------

-- /// Util functions /// --

local function PostHookFunction(original,hook)
  return function(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10)
    original(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10)
    hook(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10)
  end
end

local function InGroup()
  return (GetNumPartyMembers() + GetNumRaidMembers() > 0)
end

local function PlayerCanRaidMark()
  return InGroup() and (IsRaidOfficer() or IsPartyLeader())
end

-- You may mark when you're a lead, assist, or you're doing soloplay
local function PlayerCanMark()
  return PlayerCanRaidMark() or not InGroup()
end

------------------------------
-- Vars
------------------------------

local saved_raid = nil
shuffle_queue = {}

------------------------------
-- Raid Functions
------------------------------

-- Function to get the current raid configuration
local function GetCurrentRaidConfiguration()
  local currentConfig = {}
  local raidUnits = {}
  local classes = {}
  for i = 1, GetNumRaidMembers() do
    local name, _, subgroup, _, class = GetRaidRosterInfo(i)
    currentConfig[name] = subgroup
    raidUnits[name] = i
    classes[name] = class
  end
  return currentConfig, raidUnits, classes
end

function MakeRaidConfiguration(config)
  local groups = {}
  for name,group in pairs(config) do
    if not groups[group] then groups[group] = {} end
    table.insert(groups[group], name)
    -- print(name  .. ">>".. group)
  end
  return groups
end

function StoreRaidConfiguration(name,config)
  local r = MakeRaidConfiguration(config)
  EasyRaidSaverDB.templates[name] = r
end

-- I need a dropdown to pick a config, I want a toggle box for live update, I want tooltips explaining things at cursor
-- can use "new template" in dropdown to make new entries
-- button for opening text editor
-- option to set assistants
-- option to auto-shift spriests around
-- option to autoswap dead melee out of shaman groups or swap a live shaman into dead spot
-- postal option to spit out items being sent and amount
-- rabuffs option to show item totals for consumes
-- fr trinket
-- fr gun
-- default templates to order people by class to make optimal groups automatically
-- make mc automarks

function StoredRaidConfigToTextRaw(name, temp)
  local config = temp
  local groups = {}

  for i=1,8 do
    table.insert(groups, "Group "..i..": " .. (config[i] and table.concat(config[i], ", ") or ""))
  end

  local sum = "Layout Name: " .. name .. "\n\n" .. table.concat(groups,"\n")
  return sum
end

function StoredRaidConfigToText(name)
  local config = EasyRaidSaverDB.templates[name]
  if not config then return end
  return StoredRaidConfigToTextRaw(name, config)
end

function ToSimpleConfig(config)
  local temp = {}
  for i,group in pairs(config) do
    for _,member in pairs(group) do
      temp[member] = i
      -- print(member .. "<<" .. i)
    end
  end

  return temp
end

function TextToBasicRaidConfig(text)
  if not text then return end

  local lower_text = string.lower(text)

  local s,e,template_name = string.find(lower_text,"layout%s*name%s*:%s*([%w _]+)\n*")
  if not s then return end
  -- grab the capitalized version
  local _,_,template_name = string.find(string.sub(text,s,e),":%s*([%w _]+)\n*")
  -- print("tn "..template_name)

  local rest = string.sub(lower_text,e)
  -- print(rest)
  local config = {}
  for gnum,members in string.gfind(rest,"[ ]*group%s*(%d+):([%w ,]+)") do
    -- print(gnum .. " _ ".. members)
    -- print("num:"..gnum)
    -- print("mem:"..members)
    if gnum ~= "" and members ~= "" then
      for member in string.gfind(members,"%s*(%w+)%s*[,]*%s*") do
        member = string.upper(string.sub(member,1,1)) .. string.lower(string.sub(member,2))
        -- print("member " .. member .. " : gnum " .. gnum)
        config[member] = tonumber(gnum)
      end
    end
  end

  -- local r = MakeRaidConfiguration(config)
  return config,template_name
end

test_line = "tEmplate Name:fOofer\nGroup2:wor\nGroup 5: wICK,WHACK"
function Runtest_line()
  TextToStoredRaidConfig(test_line)
end


function RandomizeRaid()
  local max = GetNumRaidMembers()
  for i=1,max do
    SwapRaidSubgroup(math.random(1,max),math.random(1,max))
  end
end

-- Function to find a member in a specific subgroup who is not in their desired subgroup
local function FindMisplacedMemberInSubgroup(subgroup, config, desiredConfig, excludeName)
  for name, group in pairs(config) do
    if group == subgroup and name ~= excludeName and desiredConfig[name] ~= subgroup then
      -- print(name)
      return name
    end
  end
  return nil
end

-- Function to move a member to their desired subgroup
local function MoveMemberSafely(name, desiredSubgroup, currentConfig, raidUnits, subgroupCount, desiredConfig, visited)
  local currentSubgroup = currentConfig[name]

  if currentSubgroup == desiredSubgroup then
    return true
  end

  -- Prevent infinite loops by tracking visited members
  if visited[name] then
    return false
  end
  visited[name] = true

  -- If the desired subgroup is not full, move directly
  if subgroupCount[desiredSubgroup] < 5 then
    SetRaidSubgroup(raidUnits[name], desiredSubgroup)
    subgroupCount[currentSubgroup] = subgroupCount[currentSubgroup] - 1
    subgroupCount[desiredSubgroup] = subgroupCount[desiredSubgroup] + 1
    currentConfig[name] = desiredSubgroup
    return true
  else
    -- Find a member in the desired subgroup to use as a temporary placeholder
    local tempName = FindMisplacedMemberInSubgroup(desiredSubgroup, currentConfig, desiredConfig, name)
    
    if not tempName then
      -- If no misplaced member is found, try to force a swap
      for candidateName, group in pairs(currentConfig) do
        if group == desiredSubgroup then
          tempName = candidateName
          break
        end
      end
    end

    -- Proceed with the swap if a member was found
    if tempName then
      SwapRaidSubgroup(raidUnits[name], raidUnits[tempName])
      currentConfig[name], currentConfig[tempName] = currentConfig[tempName], currentConfig[name]
      return MoveMemberSafely(tempName, desiredConfig[tempName], currentConfig, raidUnits, subgroupCount, desiredConfig, visited)
    end
  end
  
  return false
end

-- check raid for names, kick dupers
function RemoveDupes()
  local t = {}
  for i=1,GetNumRaidMembers() do
    local name = GetRaidRosterInfo(i)
    if t[name] then
      UninviteByName(name)
    else
      t[name] = true
    end
  end
end

local function ConfigureRaid(desiredConfig)
  local currentConfig, raidUnits = GetCurrentRaidConfiguration()
  local subgroupCount = {}

  if DEBUG then
    RemoveDupes()
  end

  -- copy desired config, prune missing names, add new names
  local tempDes = {}
  for name, _ in pairs(desiredConfig) do
      if currentConfig[name] then
          tempDes[name] = desiredConfig[name]
      end
  end
  for name, _ in pairs(currentConfig) do
      if not desiredConfig[name] then
          tempDes[name] = currentConfig[name]
      end
  end

  -- Initialize subgroup counts
  for i = 1, 8 do
      subgroupCount[i] = 0
  end

  -- Count the number of members in each current subgroup
  for _, subgroup in pairs(currentConfig) do
      subgroupCount[subgroup] = subgroupCount[subgroup] + 1
  end

  -- Process each member in the desired configuration
  local queue = {}
  local queue_size = 0
  for name, desiredSubgroup in pairs(tempDes) do
      table.insert(queue, {name = name, desiredSubgroup = desiredSubgroup})
      queue_size = queue_size + 1
  end

    -- Process each member in the desired configuration with cycle detection
    for name, desiredSubgroup in pairs(tempDes) do
      local visited = {}
      if not MoveMemberSafely(name, desiredSubgroup, currentConfig, raidUnits, subgroupCount, tempDes, visited) then
          ers_print("Failed to move " .. name .. " to the desired subgroup. Please screenshot the current raid and the raid layout.")
      end
  end
end


function DidRaidMatch(first,second)
  for name,subgroup in pairs(first) do
    -- print("f "..first[name] .. " ".. name)
    -- print("s "..second[name].. " ".. name)
    if second[name] and (first[name] ~= second[name]) then
        DEFAULT_CHAT_FRAME:AddMessage(name .. " not matched")
        return false
      end
  end
  DEFAULT_CHAT_FRAME:AddMessage("matched")
  return true
end

------------------------------
-- UI
------------------------------

-- Define a function to create the buttons
local function CreateRaidButtons()
  local AddButton = getglobal("RaidFrameAddMemberButton")
  AddButton:SetText("Add")
  AddButton:SetWidth(35)

  local ReadyButton = getglobal("RaidFrameReadyCheckButton")
  ReadyButton:SetText("Ready")
  ReadyButton:SetPoint("LEFT", AddButton,"RIGHT", 0, 0)
  ReadyButton:SetWidth(35)

  -- Create the Save Raid button
  local SaveRaidButton = CreateFrame("Button", "SaveRaidButton", AddButton, "UIPanelButtonTemplate")
  SaveRaidButton:SetWidth(35) -- Width, Height
  SaveRaidButton:SetHeight(22) -- Width, Height
  SaveRaidButton:SetPoint("LEFT", AddButton, "RIGHT", 35, 0) -- Position relative to RaidFrame
  SaveRaidButton:SetText("Save")
  SaveRaidButton:SetScript("OnClick", function()
      ERS_SaveRaid()
  end)
  -- Add a script to handle showing the tooltip
  SaveRaidButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Quick-Save Current Raid", 1, 1, 0)  -- Tooltip title
    GameTooltip:AddLine("Save the current raid to the quick-save slot", 1, 1, 1, true)  -- Tooltip description
    GameTooltip:Show()
  end)

  -- Add a script to handle hiding the tooltip
  SaveRaidButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- Create the Restore Raid button
  local RestoreRaidButton = CreateFrame("Button", "RestoreRaidButton", RaidFrame, "UIPanelButtonTemplate")
  RestoreRaidButton:SetWidth(35) -- Width, Height
  RestoreRaidButton:SetHeight(22) -- Width, Height
  RestoreRaidButton:SetPoint("LEFT", SaveRaidButton, "RIGHT", 0, 0) -- Position relative to RaidFrame
  RestoreRaidButton:SetText("Load")
  RestoreRaidButton:SetScript("OnClick", function()
      ERS_RestoreRaid()
  end)
  -- Add a script to handle showing the tooltip
  RestoreRaidButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Quick-Load Raid", 1, 1, 0)  -- Tooltip title
    GameTooltip:AddLine("Load the last quick-saved raid", 1, 1, 1, true)  -- Tooltip description
    GameTooltip:Show()
  end)

  -- Add a script to handle hiding the tooltip
  RestoreRaidButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  local InfoButton = getglobal("RaidFrameRaidInfoButton")
  InfoButton:SetText("Info")
  InfoButton:SetPoint("LEFT", RestoreRaidButton,"RIGHT", 0, 0)
  InfoButton.orig_width = InfoButton:GetWidth()
  InfoButton:SetWidth(35) -- Width, Height

  local f = InfoButton:GetScript("OnClick")
  InfoButton:SetScript("OnClick", function (a1,a2,a3,a4,a5,a6,a7,a8,a9)
    f(a1,a2,a3,a4,a5,a6,a7,a8,a9)
    if ESRConfigFrame:IsShown() then ESRConfigFrameButton:Click() end
  end)

  local function CreateConfigArea()

    local ConfigFrame = CreateFrame("Frame","ESRConfigFrame",RaidFrame)

    -- Create the button frame
    local rightArrowButton = CreateFrame("Button", "ESRConfigFrameButton", RaidFrame, "UIPanelButtonTemplate")
    rightArrowButton:SetWidth(24)  -- Width, Height
    rightArrowButton:SetHeight(24)  -- Width, Height
    rightArrowButton:SetPoint("TOPLEFT", RaidFrame, "TOPRIGHT",-30, -10)
    -- Add a script to handle showing the tooltip
    rightArrowButton:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      -- GameTooltip:SetText("Quick-Load Raid", 1, 1, 0)  -- Tooltip title
      GameTooltip:AddLine("Show/Hide the raid Layout Editor", 1, 1, 1, true)  -- Tooltip description
      GameTooltip:Show()
    end)

    -- Add a script to handle hiding the tooltip
    rightArrowButton:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    -- Create the arrow texture
    local arrowTextureUp = rightArrowButton:CreateTexture(nil, "ARTWORK")
    arrowTextureUp:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")  -- Path to the right arrow texture
    arrowTextureUp:SetAllPoints(rightArrowButton)  -- Make the texture fill the entire button

    local arrowTextureDown = rightArrowButton:CreateTexture(nil, "ARTWORK")
    arrowTextureDown:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")  -- Path to the right arrow texture
    arrowTextureDown:SetAllPoints(rightArrowButton)  -- Make the texture fill the entire button

    -- Set the normal and pushed textures for the button
    rightArrowButton:SetNormalTexture(arrowTextureUp)
    rightArrowButton:SetPushedTexture(arrowTextureDown)

    -- Add a script to handle the button click
    rightArrowButton:SetScript("OnClick", function()
      if ConfigFrame:IsShown() then
        ConfigFrame:Hide()
      else
        ConfigFrame:Show()
      end
    end)

    -- Show the button
    rightArrowButton:Show()
    ConfigFrame:SetPoint("TOPLEFT", rightArrowButton,"TOPRIGHT", 0, 0)

      
    local EditBox = CreateFrame("EditBox","ERSEditBox",ConfigFrame)
    EditBox:SetMultiLine(true)
    EditBox:SetAutoFocus(false) -- Prevent the box from auto-focusing
    EditBox:SetFontObject(GameFontNormal)
    EditBox:SetWidth(380)
    EditBox:SetHeight(140) -- Set a large height to enable scrolling
    EditBox:SetText("Raid Layout")
    EditBox:SetPoint("LEFT", RaidFrame,"RIGHT", 0, 150)
    EditBox:Hide()

    -- Add a background to the frame
    local bg = EditBox:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("LEFT", EditBox,"LEFT", 0, 0)
    bg:SetWidth(EditBox:GetWidth())
    bg:SetHeight(EditBox:GetHeight())
    bg:SetTexture(0, 0, 0, 0.7) -- Black background with some transparency

    EditBox:SetScript("OnEscapePressed", function ()
      EditBox:ClearFocus()
    end)

    local MyDropdown = CreateFrame("Frame", "MyDropdownMenu", ConfigFrame, "UIDropDownMenuTemplate")
    -- MyDropdown:SetPoint("CENTER", UIParent, "CENTER")
    MyDropdown:SetPoint("TOPLEFT", RaidFrame,"TOPRIGHT", -17, -7)
    -- MyDropdown:SetWidth(150)
    UIDropDownMenu_SetText("Select a Layout", MyDropdown)
    UIDropDownMenu_SetWidth(170,MyDropdown)

    MyDropdown:SetScript("OnShow", function ()
      if UIDropDownMenu_GetSelectedID(MyDropdown) then
        EditBox:Show()
      end
    end)

    -- local function MyDropdown_OnClick()
    --   UIDropDownMenu_SetSelectedValue(MyDropdown, this.value)
    --   print("Selected option: " .. this.value)
    -- end

    local function MyDropdown_Initialize(level)

      for k,_ in pairs(EasyRaidSaverDB.templates) do
        local name = k
        local info = {}
        info.text = name
        info.func = function ()
          local conf = StoredRaidConfigToText(name)
          if conf then
            EditBox:SetText(conf)
            UIDropDownMenu_SetSelectedName(MyDropdown, this:GetText())
            EditBox:Show()
          end
        end
        UIDropDownMenu_AddButton(info, level)
      end

      local info = {}
      info.text = "Current Quick-Saved Raid"
      info.textR = 1 -- yellow
      info.textG = 1 -- yellow
      info.textB = 0 -- yellow
      info.func = function ()
        if EasyRaidSaverDB.saved_raid then
          local config = MakeRaidConfiguration(EasyRaidSaverDB.saved_raid)
          EditBox:SetText(StoredRaidConfigToTextRaw("last_raid_quicksave", config))
          UIDropDownMenu_SetSelectedName(MyDropdown, this:GetText())
          EditBox:Show()
        end
      end
      UIDropDownMenu_AddButton(info, level)

      local info = {}
      info.text = "Shaman For Melee"
      info.textR = 0.14 -- yellow
      info.textG = 0.35 -- yellow
      info.textB = 1.0 -- yellow
      info.func = function ()
        -- organize shamans and melee here
        print("this layout template doesn't do anything yet")
      end
      UIDropDownMenu_AddButton(info, level)

      local info = {}
      info.text = "New Layout"
      -- info.value = "New Template"
      info.textR = 1 -- yellow
      info.textG = 1 -- yellow
      info.textB = 0 -- yellow
      info.func = function ()
        local config = MakeRaidConfiguration(GetCurrentRaidConfiguration())
        EditBox:SetText(StoredRaidConfigToTextRaw("new layout", config))
        UIDropDownMenu_SetSelectedName(MyDropdown, this:GetText())
        EditBox:Show()
      end
      UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(MyDropdown, MyDropdown_Initialize)
    -- UIDropDownMenu_SetSelectedValue(MyDropdown,"New Template")

    -- Create the Save Raid button
    local SaveTemplateButton = CreateFrame("Button", "SaveTemplateButton", ConfigFrame, "UIPanelButtonTemplate")
    SaveTemplateButton:SetWidth(35) -- Width, Height
    SaveTemplateButton:SetHeight(22) -- Width, Height
    SaveTemplateButton:SetPoint("LEFT", MyDropdown, "RIGHT", -10, 3) -- Position relative to RaidFrame
    SaveTemplateButton:SetText("Save")
    SaveTemplateButton:SetScript("OnClick", function()
      local conf,name = TextToBasicRaidConfig(EditBox:GetText())

      if conf then
        StoreRaidConfiguration(name, conf)
        UIDropDownMenu_Initialize(MyDropdown, MyDropdown_Initialize)
        UIDropDownMenu_SetSelectedName(MyDropdown, name)
        ers_print("Saving layout: " .. name)
      end
    end)

    -- Create the Restore Raid button
    local DeleteTemplateButton = CreateFrame("Button", "DeleteTemplateButton", ConfigFrame, "UIPanelButtonTemplate")
    DeleteTemplateButton:SetWidth(35) -- Width, Height
    DeleteTemplateButton:SetHeight(22) -- Width, Height
    DeleteTemplateButton:SetPoint("BOTTOMLEFT", SaveTemplateButton, "TOPLEFT", 0, 0) -- Position relative to RaidFrame
    DeleteTemplateButton:SetText("Delete")
    DeleteTemplateButton:SetScript("OnClick", function()
      local name = UIDropDownMenu_GetSelectedName(MyDropdown)
      local ix = UIDropDownMenu_GetSelectedID(MyDropdown)
      if EasyRaidSaverDB.templates[name] then
        EasyRaidSaverDB.templates[name] = nil
        ers_print("Deleted layout: " .. name)
        UIDropDownMenu_Initialize(MyDropdown, MyDropdown_Initialize)
        -- UIDropDownMenu_SetSelectedID(MyDropdown,ix-1)
      end
    end)
    -- Add a script to handle showing the tooltip
    DeleteTemplateButton:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText("Delete Current Layout", 1, 1, 0)  -- Tooltip title
      GameTooltip:AddLine("This operation will not ask for confirmation", 1, 1, 1, true)  -- Tooltip description
      GameTooltip:Show()
      -- TODO: Make it ask for confirmation
    end)

    -- Add a script to handle hiding the tooltip
    DeleteTemplateButton:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    -- Create the Restore Raid button
    local ApplyTemplateButton = CreateFrame("Button", "ApplyTemplateButton", ConfigFrame, "UIPanelButtonTemplate")
    ApplyTemplateButton:SetWidth(42) -- Width, Height
    ApplyTemplateButton:SetHeight(22) -- Width, Height
    ApplyTemplateButton:SetPoint("LEFT", SaveTemplateButton, "RIGHT", 0, 0) -- Position relative to RaidFrame
    ApplyTemplateButton:SetText("Apply")
    ApplyTemplateButton:SetScript("OnClick", function()
      local name = UIDropDownMenu_GetSelectedName(MyDropdown)
      if EasyRaidSaverDB.templates[name] then
        local simple = ToSimpleConfig(EasyRaidSaverDB.templates[name])
        ConfigureRaid(simple)
        ers_print("Applying layout: " .. name)
        if DEBUG then DidRaidMatch(simple,GetCurrentRaidConfiguration()) end
      end
    end)
    -- Add a script to handle showing the tooltip
    ApplyTemplateButton:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText("Apply Layout", 1, 1, 0)  -- Tooltip title
      GameTooltip:AddLine("Apply the current Layout, re-organising the raid to match", 1, 1, 1, true)  -- Tooltip description
      GameTooltip:Show()
    end)

    -- Add a script to handle hiding the tooltip
    ApplyTemplateButton:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

  end
  CreateConfigArea()
end

-- TODO change taunt resist report
-- make masterloot reminder more selective

local function UpdateInfoButton()
  if GetNumRaidMembers() > 0 then
    RaidFrameRaidInfoButton:SetText("Info")
    RaidFrameRaidInfoButton:SetWidth(35)
    RaidFrameRaidInfoButton:SetPoint("LEFT", RestoreRaidButton,"RIGHT", 0, 0)
  else
    RaidFrameRaidInfoButton:SetPoint("LEFT", RaidFrameConvertToRaidButton,"RIGHT", 65, 0)
    RaidFrameRaidInfoButton:SetText(RAID_INFO)
    RaidFrameRaidInfoButton:SetWidth(RaidFrameRaidInfoButton.orig_width)
  end
end

-- Function to update the button states based on raid status
local function UpdateButtonStates()
  if GetNumRaidMembers() > 0 then
    SaveRaidButton:Show()
    RestoreRaidButton:Show()
    if IsRaidOfficer() then
      ApplyTemplateButton:Enable()
    else
      ApplyTemplateButton:Disable()
    end

    ESRConfigFrame:Show()

    if EasyRaidSaverDB.saved_raid and IsRaidOfficer() then
      RestoreRaidButton:Enable()
    else
      RestoreRaidButton:Disable()
    end
  else
    SaveRaidButton:Hide()
    RestoreRaidButton:Hide()
    ApplyTemplateButton:Disable()

    ESRConfigFrame:Hide()
  end
  UpdateInfoButton()
end

-- Function to save the raid setup
function ERS_SaveRaid()
  ers_print("Quick-saving current raid layout.")
  saved_raid = GetCurrentRaidConfiguration()
  EasyRaidSaverDB.saved_raid = saved_raid

  UpdateButtonStates()
end

function ERS_RestoreRaid()
  ers_print("Quick-loading saved raid layout.")
  if EasyRaidSaverDB.saved_raid then
    ConfigureRaid(EasyRaidSaverDB.saved_raid)
  end
end

function Matches()
  DidRaidMatch(GetCurrentRaidConfiguration(),saved_raid)
end

-- Register the ADDON_LOADED event
local frame = CreateFrame("Frame","EasyRaidSaver")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function ()
  if event == "ADDON_LOADED" and arg1 == "EasyRaidSaver" then

    EasyRaidSaverDB = EasyRaidSaverDB or {}
    EasyRaidSaverDB.settings = EasyRaidSaverDB.settings or {}
    EasyRaidSaverDB.templates = EasyRaidSaverDB.templates or {}

    CreateRaidButtons()

    local rgfu = RaidGroupFrame_Update
    ERS_RaidGroupFrame_Update = function ()
      rgfu()
      UpdateInfoButton()
    end
    RaidGroupFrame_Update = ERS_RaidGroupFrame_Update

    local rgonshow = RaidFrame:GetScript("OnShow")
    RaidFrame:SetScript("OnShow", function ()
      if rgonshow then rgonshow() end
      UpdateButtonStates()
    end)

    UpdateButtonStates()
  elseif event == "RAID_ROSTER_UPDATE" then
    UpdateButtonStates()
    -- DoNextQueueItem()
  elseif event == "PLAYER_ENTERING_WORLD" then
    UpdateButtonStates()
  end
end)

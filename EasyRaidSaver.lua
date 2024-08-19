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
    print(name  .. ">>".. group)
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

  local sum = "Template Name: " .. name .. "\n\n" .. table.concat(groups,"\n")
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

  local s,e,template_name = string.find(lower_text,"template%s*name%s*:%s*([%w _]+)\n*")
  if not s then return end
  print("tn "..template_name)
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
      print(name)
      return name
    end
  end
  return nil
end

-- Function to move a member to their desired subgroup
local function MoveMember(name, desiredSubgroup, currentConfig, raidUnits, subgroupCount, desiredConfig)
  local currentSubgroup = currentConfig[name]

  if currentSubgroup == desiredSubgroup then
    print(name.."is in desired group")
    return true
  end

  -- If the desired subgroup is not full, move directly
  if subgroupCount[desiredSubgroup] < 5 then
    local a = raidUnits[name]
    local sg = desiredSubgroup

    SetRaidSubgroup(raidUnits[name], desiredSubgroup)
    subgroupCount[currentSubgroup] = subgroupCount[currentSubgroup] - 1
    subgroupCount[desiredSubgroup] = subgroupCount[desiredSubgroup] + 1
    currentConfig[name] = desiredSubgroup
    return true
  else
    -- Find a member in the desired subgroup to use as a temporary placeholder
    local tempName = FindMisplacedMemberInSubgroup(desiredSubgroup, currentConfig, desiredConfig, name)
    if tempName then
      local a = raidUnits[name]
      local b = raidUnits[tempName]
      -- Move the temporary member to the current subgroup
      currentConfig[name], currentConfig[tempName] = currentConfig[tempName], currentConfig[name]
      SwapRaidSubgroup(raidUnits[name], raidUnits[tempName])
      return MoveMember(tempName, desiredConfig[tempName], currentConfig, raidUnits, subgroupCount, desiredConfig)
    end
  end
  return false
end

-- Main function to configure the raid
local function ConfigureRaid(desiredConfig)
  local currentConfig, raidUnits = GetCurrentRaidConfiguration()
  local subgroupCount = {}

  local c = 0
  for k,_ in pairs(currentConfig) do
    c = c + 1
  end
  print(c)

  -- copy desired config, prune missing names, add new names
  local tempDes = {}
  for name,_ in pairs(desiredConfig) do
    if currentConfig[name] then
      tempDes[name] = desiredConfig[name]
    end
  end
  for name,_ in pairs(currentConfig) do
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

  for name, desiredSubgroup in pairs(tempDes) do
    MoveMember(name, desiredSubgroup, currentConfig, raidUnits, subgroupCount, tempDes)
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

  -- Create the Restore Raid button
  local RestoreRaidButton = CreateFrame("Button", "RestoreRaidButton", RaidFrame, "UIPanelButtonTemplate")
  RestoreRaidButton:SetWidth(35) -- Width, Height
  RestoreRaidButton:SetHeight(22) -- Width, Height
  RestoreRaidButton:SetPoint("LEFT", SaveRaidButton, "RIGHT", 0, 0) -- Position relative to RaidFrame
  RestoreRaidButton:SetText("Load")
  RestoreRaidButton:SetScript("OnClick", function()
      ERS_RestoreRaid()
  end)

  local InfoButton = getglobal("RaidFrameRaidInfoButton")
  InfoButton:SetText("Info")
  InfoButton:SetPoint("LEFT", RestoreRaidButton,"RIGHT", 0, 0)
  InfoButton.orig_width = InfoButton:GetWidth()
  InfoButton:SetWidth(35) -- Width, Height

  local ConfigFrame = CreateFrame("Frame","ESRConfigFrame",RaidFrame)
  ConfigFrame:SetPoint("TOPLEFT", RaidFrame,"TOPRIGHT", 0, 0)

  local EditBox = CreateFrame("EditBox","ERSEditBox",ConfigFrame)
  EditBox:SetMultiLine(true)
  EditBox:SetAutoFocus(false) -- Prevent the box from auto-focusing
  EditBox:SetFontObject(GameFontNormal)
  EditBox:SetWidth(380)
  EditBox:SetHeight(140) -- Set a large height to enable scrolling
  EditBox:SetText("Raid Layout")
  EditBox:SetPoint("LEFT", RaidFrame,"RIGHT", 0, 0)

  -- Add a background to the frame
  local bg = EditBox:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("LEFT", EditBox,"LEFT", 0, 0)
  bg:SetWidth(EditBox:GetWidth())
  bg:SetHeight(EditBox:GetHeight())
  bg:SetTexture(0, 0, 0, 0.5) -- Black background with some transparency

  EditBox:SetScript("OnEscapePressed", function ()
    EditBox:ClearFocus()
  end)

  local MyDropdown = CreateFrame("Frame", "MyDropdownMenu", ConfigFrame, "UIDropDownMenuTemplate")
  MyDropdown:SetPoint("CENTER", UIParent, "CENTER")
  MyDropdown:SetPoint("TOPLEFT", RaidFrame,"TOPRIGHT", 0, 0)
  MyDropdown:SetWidth(150)
  UIDropDownMenu_SetText("Select an option", MyDropdown)

  local function MyDropdown_OnClick()
    UIDropDownMenu_SetSelectedValue(MyDropdown, this.value)
    print("Selected option: " .. this.value)
  end

  local function MyDropdown_Initialize(level)

    local info = {}
    info.text = "Current Saved Raid"
    info.func = function ()
      if EasyRaidSaverDB.saved_raid then
        local config = MakeRaidConfiguration(EasyRaidSaverDB.saved_raid)
        EditBox:SetText(StoredRaidConfigToTextRaw("last_saved_raid", config))
        UIDropDownMenu_SetSelectedName(MyDropdown, this:GetText())
      end
    end
    UIDropDownMenu_AddButton(info, level)

    for k,_ in pairs(EasyRaidSaverDB.templates) do
      local name = k
      local info = {}
      info.text = name
      info.func = function ()
        local conf = StoredRaidConfigToText(name)
        if conf then
          EditBox:SetText(conf)
          UIDropDownMenu_SetSelectedName(MyDropdown, this:GetText())
        end
      end
      UIDropDownMenu_AddButton(info, level)
    end

    local info = {}
    info.text = "New Template"
    info.value = "New Template"
    info.func = function ()
      local config = MakeRaidConfiguration(GetCurrentRaidConfiguration())
      EditBox:SetText(StoredRaidConfigToTextRaw("new template", config))
      UIDropDownMenu_SetSelectedName(MyDropdown, this:GetText())
    end
    UIDropDownMenu_AddButton(info, level)
  end

  UIDropDownMenu_Initialize(MyDropdown, MyDropdown_Initialize)
  -- UIDropDownMenu_SetSelectedValue(MyDropdown,"New Template")

  -- Create the Save Raid button
  local SaveTemplateButton = CreateFrame("Button", "SaveTemplateButton", ConfigFrame, "UIPanelButtonTemplate")
  SaveTemplateButton:SetWidth(35) -- Width, Height
  SaveTemplateButton:SetHeight(22) -- Width, Height
  SaveTemplateButton:SetPoint("LEFT", MyDropdown, "RIGHT", 0, 0) -- Position relative to RaidFrame
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
  DeleteTemplateButton:SetPoint("LEFT", SaveTemplateButton, "RIGHT", 0, 0) -- Position relative to RaidFrame
  DeleteTemplateButton:SetText("Delete")
  DeleteTemplateButton:SetScript("OnClick", function()
    local name = UIDropDownMenu_GetSelectedName(MyDropdown)
    local ix = UIDropDownMenu_GetSelectedID(MyDropdown)
    if EasyRaidSaverDB.templates[name] then
      EasyRaidSaverDB.templates[name] = nil
      ers_print("Deleted layout: " .. name)
      UIDropDownMenu_Initialize(MyDropdown, MyDropdown_Initialize)
      UIDropDownMenu_SetSelectedID(MyDropdown,ix-1)
    end
  end)

  -- Create the Restore Raid button
  local ApplyTemplateButton = CreateFrame("Button", "ApplyTemplateButton", ConfigFrame, "UIPanelButtonTemplate")
  ApplyTemplateButton:SetWidth(35) -- Width, Height
  ApplyTemplateButton:SetHeight(22) -- Width, Height
  ApplyTemplateButton:SetPoint("LEFT", DeleteTemplateButton, "RIGHT", 0, 0) -- Position relative to RaidFrame
  ApplyTemplateButton:SetText("Apply")
  ApplyTemplateButton:SetScript("OnClick", function()
    local name = UIDropDownMenu_GetSelectedName(MyDropdown)
    if EasyRaidSaverDB.templates[name] then
      local simple = ToSimpleConfig(EasyRaidSaverDB.templates[name])
      -- for n,i in pairs(simple) do
      --   print(n .. " _ " .. i)
      -- end
      ConfigureRaid(simple)
      ers_print("Applying layout: " .. name)
      DidRaidMatch(simple,GetCurrentRaidConfiguration())
    end
  end)
end

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

    ESRConfigFrame:Show()

    if EasyRaidSaverDB.saved_raid and IsRaidOfficer() then
      RestoreRaidButton:Enable()
    else
      -- print(EasyRaidSaverDB.saved_raid and "yes1" or "no1")
      -- print(IsRaidOfficer() and "yes2" or "no2")
      RestoreRaidButton:Disable()
    end
  else
    SaveRaidButton:Hide()
    RestoreRaidButton:Hide()

    ESRConfigFrame:Hide()
  end
  UpdateInfoButton()
end

-- Function to save the raid setup
function ERS_SaveRaid()
  -- Your code to save the raid
  ers_print("Saving current raid layout.")
  saved_raid = GetCurrentRaidConfiguration()
  EasyRaidSaverDB.saved_raid = saved_raid
  -- StoreRaidConfiguration("current", saved_raid)
  -- for i,k in pairs(saved_raid) do
    -- print(i .. " " .. k)
  -- end
  UpdateButtonStates()
end

local now_empty = true
-- Function to restore the raid setup
function ERS_RestoreRaid()
  -- Your code to restore the raid
  ers_print("Restoring saved raid layout.")
  if EasyRaidSaverDB.saved_raid then
    -- shuffle_queue = {}
    -- ConfigureRaid(saved_raid)
    -- for i=1,3 do
    -- now_empty = false
    ConfigureRaid(EasyRaidSaverDB.saved_raid)
    -- ConfigureRaid(saved_raid)
    -- end
    -- print("configed")
    -- DoNextQueueItem()
    -- print("item one go")
  end
end

function DoNextQueueItem()
  -- if not next(shuffle_queue) then return end
  local step = table.remove(shuffle_queue)
  if step then
    step()
    print("another step")
  -- elseif not now_empty and saved_raid then
  --   now_empty = true
  --   ConfigureRaid(saved_raid)
  --   print("reconfigure")
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

    EasyRaidSaverDB = EasyRaidSaverDB or {}
    EasyRaidSaverDB.settings = EasyRaidSaverDB.settings or {}
    EasyRaidSaverDB.templates = EasyRaidSaverDB.templates or {}

    UpdateButtonStates()
  elseif event == "RAID_ROSTER_UPDATE" then
    UpdateButtonStates()
    -- DoNextQueueItem()
  elseif event == "PLAYER_ENTERING_WORLD" then
    UpdateButtonStates()
  end
end)

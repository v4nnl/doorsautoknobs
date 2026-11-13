local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local Settings = {
    AutoFarm        = false,
    AutoLoot        = true,
    AutoDoor        = true,
    TeleportSpeed   = 0.1,
    WalkSpeed       = 100,
    AutoRejoin      = true,
    NotifyOnFinish  = true,
}

local function notify(title, text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 4,
        })
    end)
end

local function getHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function tpTo(cf)
    local hrp = getHRP()
    if hrp then
        hrp.CFrame = cf
    end
end

local function getAllDoors()
    local doors = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "Door" or obj.Name == "DoorModel" then
            local hrp2 = obj:FindFirstChild("HumanoidRootPart") 
                or obj:FindFirstChild("Main")
                or obj:FindFirstChild("Door")
                or obj:FindFirstChildWhichIsA("BasePart")
            if hrp2 then
                table.insert(doors, hrp2)
            end
        end
    end
    local currentRooms = workspace:FindFirstChild("CurrentRooms")
    if currentRooms then
        for _, room in ipairs(currentRooms:GetChildren()) do
            for _, obj in ipairs(room:GetDescendants()) do
                if obj.Name == "Door" and obj:IsA("BasePart") then
                    table.insert(doors, obj)
                end
            end
        end
    end
    return doors
end

local lootNames = {
    "Drawer", "Chest", "Cabinet", "Nightstand", 
    "Desk", "Safe", "Locker", "Bookcase",
    "GoldPile", "GoldCoins", "Loot"
}

local lootedObjects = {}

local function getLootables()
    local loot = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        for _, name in ipairs(lootNames) do
            if obj.Name:find(name) and obj:IsA("Model") or obj:IsA("BasePart") then
                if not lootedObjects[obj] then
                    local part = obj:IsA("BasePart") and obj 
                        or obj:FindFirstChildWhichIsA("BasePart")
                    if part then
                        table.insert(loot, {obj = obj, part = part})
                    end
                end
                break
            end
        end
    end
    return loot
end

local function doAutoLoot()
    if not Settings.AutoLoot then return end
    local hrp = getHRP()
    if not hrp then return end

    local lootables = getLootables()
    for _, item in ipairs(lootables) do
        if not lootedObjects[item.obj] then
            tpTo(item.part.CFrame * CFrame.new(0, 0, -2))
            task.wait(0.1)

            local remote = ReplicatedStorage:FindFirstChild("Interact")
                or ReplicatedStorage:FindFirstChild("OpenDrawer") 
                or ReplicatedStorage:FindFirstChild("Loot")
                or ReplicatedStorage:FindFirstChild("InteractEvent")
            
            if remote and remote:IsA("RemoteEvent") then
                pcall(function() remote:FireServer(item.obj) end)
            end

            for _, pp in ipairs(item.obj:GetDescendants()) do
                if pp:IsA("ProximityPrompt") then
                    pcall(function()
                        fireproximityprompt(pp)
                    end)
                end
            end

            lootedObjects[item.obj] = true
            task.wait(0.05)
        end
    end
end

local currentDoorIndex = 0
local desyncActive = false
local lastRoomIndex = 0

local function setDesync(state)
    desyncActive = state
    local hrp = getHRP()
    if not hrp then return end
    pcall(function()
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        if state then
            hrp:SetNetworkOwner(nil)
        else
            hrp:SetNetworkOwner(LocalPlayer)
        end
        setreadonly(mt, true)
    end)
    pcall(function()
        if state then
            sethiddenproperty(hrp, "NetworkOwnershipRule", 2)
        else
            sethiddenproperty(hrp, "NetworkOwnershipRule", 0)
        end
    end)
end

local function getCurrentRoomIndex()
    local currentRooms = workspace:FindFirstChild("CurrentRooms")
    if not currentRooms then return 0 end
    local highest = 0
    for _, room in ipairs(currentRooms:GetChildren()) do
        local num = tonumber(room.Name:match("%d+"))
        if num and num > highest then
            highest = num
        end
    end
    return highest
end

local function getDistanceToDoor(door)
    local hrp = getHRP()
    if not hrp or not door then return math.huge end
    return (hrp.Position - door.Position).Magnitude
end

local doorQueue = {}
local processedDoors = {}

local function buildDoorQueue()
    local currentRooms = workspace:FindFirstChild("CurrentRooms")
    if not currentRooms then return end

    local roomList = {}
    for _, room in ipairs(currentRooms:GetChildren()) do
        local num = tonumber(room.Name:match("%d+"))
        if num then
            table.insert(roomList, {room = room, num = num})
        end
    end

    table.sort(roomList, function(a, b) return a.num < b.num end)

    for _, entry in ipairs(roomList) do
        if entry.num > currentDoorIndex then
            for _, obj in ipairs(entry.room:GetDescendants()) do
                if obj.Name == "Door" and obj:IsA("BasePart") then
                    local id = tostring(obj)
                    if not processedDoors[id] then
                        table.insert(doorQueue, {door = obj, num = entry.num})
                        processedDoors[id] = true
                    end
                end
            end
        end
    end

    table.sort(doorQueue, function(a, b) return a.num < b.num end)
end

local function findNextDoor()
    buildDoorQueue()

    for i, entry in ipairs(doorQueue) do
        if entry.num > currentDoorIndex then
            if entry.door and entry.door.Parent then
                return entry.door, entry.num
            else
                table.remove(doorQueue, i)
            end
        end
    end

    local doors = getAllDoors()
    if #doors > 0 then
        return doors[#doors], currentDoorIndex
    end

    return nil, currentDoorIndex
end

local function walkThroughDoor(door)
    local hrp = getHRP()
    if not hrp or not door then return end

    setDesync(true)

    tpTo(door.CFrame * CFrame.new(0, 0, -3))
    task.wait(Settings.TeleportSpeed)

    local distCheck = 0
    repeat
        task.wait(0.05)
        distCheck = distCheck + 1
    until getDistanceToDoor(door) <= 5 or distCheck > 20

    setDesync(false)

    for _, pp in ipairs(door.Parent:GetDescendants()) do
        if pp:IsA("ProximityPrompt") then
            pcall(function() fireproximityprompt(pp) end)
        end
    end

    tpTo(door.CFrame * CFrame.new(0, 0, 3))
    task.wait(Settings.TeleportSpeed)

    processedDoors[tostring(door)] = true
    for i, entry in ipairs(doorQueue) do
        if entry.door == door then
            table.remove(doorQueue, i)
            break
        end
    end

    local newRoom = getCurrentRoomIndex()
    if newRoom > lastRoomIndex then
        lastRoomIndex = newRoom
        task.wait(0.2)
        buildDoorQueue()
        setDesync(true)
    end
end

local function isRunComplete()
    local elevator = workspace:FindFirstChild("Elevator") 
        or workspace:FindFirstChild("EndElevator")
        or workspace:FindFirstChild("HotelEnd")
    if elevator then return true end

    local endGui = LocalPlayer.PlayerGui:FindFirstChild("EndScreen")
        or LocalPlayer.PlayerGui:FindFirstChild("DeathScreen")
        or LocalPlayer.PlayerGui:FindFirstChild("WinScreen")
    if endGui and endGui.Enabled then return true end

    return false
end

local function rejoinLobby()
    task.wait(3)
    local TeleportService = game:GetService("TeleportService")
    pcall(function()
        TeleportService:Teleport(6516141723, LocalPlayer)
    end)
end

RunService.Heartbeat:Connect(function()
    if Settings.AutoFarm then
        local hum = getHumanoid()
        if hum then
            hum.WalkSpeed = Settings.WalkSpeed
        end
    end
end)

local function watchNewRooms()
    local currentRooms = workspace:FindFirstChild("CurrentRooms")
    if not currentRooms then
        workspace.ChildAdded:Connect(function(child)
            if child.Name == "CurrentRooms" then
                child.ChildAdded:Connect(function()
                    buildDoorQueue()
                end)
            end
        end)
        return
    end
    currentRooms.ChildAdded:Connect(function()
        task.wait(0.3)
        buildDoorQueue()
    end)
end

task.spawn(watchNewRooms)

local farmRunning = false

local function startFarm()
    if farmRunning then return end
    farmRunning = true
    notify("DOORS Farm", "Auto farm started!")

    while Settings.AutoFarm do
        doAutoLoot()

        if Settings.AutoDoor then
            local nextDoor, doorNum = findNextDoor()
            if nextDoor then
                currentDoorIndex = doorNum
                walkThroughDoor(nextDoor)
            end
        end

        if isRunComplete() then
            notify("DOORS Farm", "Run complete! Farming knobs...")
            task.wait(5)
            if Settings.AutoRejoin then
                notify("DOORS Farm", "Rejoining lobby...")
                rejoinLobby()
                break
            end
        end

        task.wait(Settings.TeleportSpeed)
    end

    farmRunning = false
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DOORSFarm"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = game:GetService("CoreGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 220, 0, 180)
frame.Position = UDim2.new(0, 20, 0.5, -90)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner", frame)
corner.CornerRadius = UDim.new(0, 8)

local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(255, 206, 27)
stroke.Thickness = 1.5

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 35)
title.BackgroundTransparency = 1
title.Text = "DOORS KnobFarm"
title.TextColor3 = Color3.fromRGB(255, 206, 27)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.Parent = frame

local div = Instance.new("Frame")
div.Size = UDim2.new(1, -20, 0, 1)
div.Position = UDim2.new(0, 10, 0, 35)
div.BackgroundColor3 = Color3.fromRGB(255, 206, 27)
div.BackgroundTransparency = 0.7
div.BorderSizePixel = 0
div.Parent = frame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 25)
statusLabel.Position = UDim2.new(0, 10, 0, 42)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Status: Idle"
statusLabel.TextColor3 = Color3.fromRGB(170, 170, 160)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = frame

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -20, 0, 35)
toggleBtn.Position = UDim2.new(0, 10, 0, 75)
toggleBtn.BackgroundColor3 = Color3.fromRGB(255, 206, 27)
toggleBtn.Text = "START FARM"
toggleBtn.TextColor3 = Color3.fromRGB(18, 18, 22)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 13
toggleBtn.BorderSizePixel = 0
toggleBtn.Parent = frame

local btnCorner = Instance.new("UICorner", toggleBtn)
btnCorner.CornerRadius = UDim.new(0, 6)

local lootBtn = Instance.new("TextButton")
lootBtn.Size = UDim2.new(1, -20, 0, 28)
lootBtn.Position = UDim2.new(0, 10, 0, 118)
lootBtn.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
lootBtn.Text = "Auto Loot: ON"
lootBtn.TextColor3 = Color3.fromRGB(235, 235, 230)
lootBtn.Font = Enum.Font.Gotham
lootBtn.TextSize = 12
lootBtn.BorderSizePixel = 0
lootBtn.Parent = frame

local lootCorner = Instance.new("UICorner", lootBtn)
lootCorner.CornerRadius = UDim.new(0, 6)

local rejoinBtn = Instance.new("TextButton")
rejoinBtn.Size = UDim2.new(1, -20, 0, 28)
rejoinBtn.Position = UDim2.new(0, 10, 0, 150)
rejoinBtn.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
rejoinBtn.Text = "Auto Rejoin: ON"
rejoinBtn.TextColor3 = Color3.fromRGB(235, 235, 230)
rejoinBtn.Font = Enum.Font.Gotham
rejoinBtn.TextSize = 12
rejoinBtn.BorderSizePixel = 0
rejoinBtn.Parent = frame

local rejoinCorner = Instance.new("UICorner", rejoinBtn)
rejoinCorner.CornerRadius = UDim.new(0, 6)

frame.Size = UDim2.new(0, 220, 0, 212)

local desyncBtn = Instance.new("TextButton")
desyncBtn.Size = UDim2.new(1, -20, 0, 28)
desyncBtn.Position = UDim2.new(0, 10, 0, 182)
desyncBtn.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
desyncBtn.Text = "Desync: AUTO"
desyncBtn.TextColor3 = Color3.fromRGB(255, 206, 27)
desyncBtn.Font = Enum.Font.Gotham
desyncBtn.TextSize = 12
desyncBtn.BorderSizePixel = 0
desyncBtn.Parent = frame

local desyncCorner = Instance.new("UICorner", desyncBtn)
desyncCorner.CornerRadius = UDim.new(0, 6)

local dragging, dragInput, dragStart, startPos
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
frame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

toggleBtn.MouseButton1Click:Connect(function()
    Settings.AutoFarm = not Settings.AutoFarm
    if Settings.AutoFarm then
        toggleBtn.Text = "STOP FARM"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        statusLabel.Text = "Status: Running..."
        task.spawn(startFarm)
    else
        toggleBtn.Text = "START FARM"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(255, 206, 27)
        statusLabel.Text = "Status: Stopped"
        farmRunning = false
    end
end)

lootBtn.MouseButton1Click:Connect(function()
    Settings.AutoLoot = not Settings.AutoLoot
    lootBtn.Text = "Auto Loot: " .. (Settings.AutoLoot and "ON" or "OFF")
    lootBtn.BackgroundColor3 = Settings.AutoLoot and Color3.fromRGB(38, 38, 46) or Color3.fromRGB(60, 30, 30)
end)

rejoinBtn.MouseButton1Click:Connect(function()
    Settings.AutoRejoin = not Settings.AutoRejoin
    rejoinBtn.Text = "Auto Rejoin: " .. (Settings.AutoRejoin and "ON" or "OFF")
    rejoinBtn.BackgroundColor3 = Settings.AutoRejoin and Color3.fromRGB(38, 38, 46) or Color3.fromRGB(60, 30, 30)
end)

local desyncManual = false
desyncBtn.MouseButton1Click:Connect(function()
    desyncManual = not desyncManual
    if desyncManual then
        desyncBtn.Text = "Desync: ON"
        setDesync(true)
    else
        desyncBtn.Text = "Desync: AUTO"
        setDesync(false)
    end
end)

task.spawn(function()
    while true do
        task.wait(1)
        if Settings.AutoFarm then
            statusLabel.Text = "Status: Door " .. currentDoorIndex
        end
    end
end)

notify("DOORS Farm", "Script loaded! Press START FARM to begin.")

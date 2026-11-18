local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "ProbeUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false

local host = nil
pcall(function() host = gethui() end)
if not host then
  pcall(function() host = game:GetService("CoreGui") end)
end
if not host then host = LP:FindFirstChild("PlayerGui") end
gui.Parent = host

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(340, 420)
frame.Position = UDim2.new(0, 8, 0, 55)
frame.BackgroundColor3 = Color3.new(0, 0, 0)
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 2
frame.BorderColor3 = Color3.fromRGB(70, 240, 150)
frame.Parent = gui

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Font = Enum.Font.Code
label.TextSize = 9
label.TextColor3 = Color3.fromRGB(200, 255, 220)
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.TextWrapped = true
label.Text = "scanning..."
label.Parent = frame

local close = Instance.new("TextButton")
close.Text = "X"
close.Size = UDim2.fromOffset(26, 24)
close.Position = UDim2.new(1, -30, 0, 4)
close.BackgroundColor3 = Color3.fromRGB(190, 60, 70)
close.TextColor3 = Color3.new(1, 1, 1)
close.Parent = frame
close.MouseButton1Click:Connect(function() gui:Destroy() end)

local HITS = { "ball", "orb", "sphere", "marble" }

local function score(p)
  if not p:IsA("BasePart") then return 0 end
  if p.Anchored then return 0 end
  if p.Transparency >= 0.95 then return 0 end
  local sz = p.Size
  local mx = math.max(sz.X, sz.Y, sz.Z)
  if mx > 30 then return 0 end
  local n = string.lower(p.Name)
  local sc = 5
  for _, k in ipairs(HITS) do
    if string.find(n, k, 1, true) then
      sc = sc + 90
      break
    end
  end
  return sc
end

task.spawn(function()
  local out = {}

  local function put(s)
    out[#out + 1] = s
    label.Text = table.concat(out, "\n")
  end

  put("PROBE RUNNING - stay in the match")
  put("")

  local char = LP.Character
  put("char: " .. tostring(char and char.Name or "NIL"))

  if char then
    local kids = {}
    for _, c in ipairs(char:GetChildren()) do
      kids[#kids + 1] = c.ClassName .. ":" .. c.Name
    end
    put("char kids: " .. table.concat(kids, ", "))
    put("has humanoid: " .. tostring(
      char:FindFirstChildOfClass("Humanoid") ~= nil))
  end

  local cam = workspace.CurrentCamera
  local subj = cam and cam.CameraSubject
  put("camera subject: " .. tostring(subj and subj.Name))

  local total = 0
  local okCount = pcall(function()
    total = #workspace:GetDescendants()
  end)
  put("workspace parts: " .. tostring(total))
  put("")

  local cands = {}
  local okScan = pcall(function()
    for _, d in ipairs(workspace:GetDescendants()) do
      local sc = score(d)
      if sc > 0 then
        cands[#cands + 1] = { p = d, sc = sc }
      end
    end
  end)

  table.sort(cands, function(a, b)
    return a.sc > b.sc
  end)

  put("candidates: " .. tostring(#cands))
  put("--- top ---")

  for i = 1, math.min(8, #cands) do
    local c = cands[i]
    local p = c.p
    local par = p.Parent and p.Parent.Name or "?"
    put(string.format("%d sc=%d %s sz=%.0f par=%s",
      i, c.sc, p.Name, math.max(
        p.Size.X, p.Size.Y, p.Size.Z), par))
  end

  put("")

  if #cands == 0 then
    put("NO CANDIDATES AT ALL")
    return
  end

  local t = cands[1].p
  put("--- write test on: " .. t.Name .. " ---")

  local before = t.Position
  local rot = t.CFrame.Rotation

  pcall(function()
    t.CFrame = CFrame.new(before + Vector3.new(0, 0, 6)) * rot
  end)

  task.wait(0.35)

  local after = t.Position
  local moved = (after - before).Magnitude

  if moved > 3 then
    put("CFRAME WRITE: STICKS (" .. math.floor(moved) .. ")")
  else
    put("CFRAME WRITE: SNAPPED BACK (" ..
      math.floor(moved * 10) / 10 .. ")")
  end

  local vb = t.AssemblyLinearVelocity
  pcall(function()
    t.AssemblyLinearVelocity = Vector3.new(0, 0, -40)
  end)
  task.wait(0.25)
  local va = t.AssemblyLinearVelocity
  local kept = (va - Vector3.new(0, 0, -40)).Magnitude

  if kept < 25 then
    put("VELOCITY WRITE: STICKS")
  else
    put("VELOCITY WRITE: OVERWRITTEN")
  end

  local con = {}
  pcall(function()
    for _, d in ipairs(t:GetChildren()) do
      con[#con + 1] = d.ClassName
    end
  end)

  put("")
  put("part children: " .. table.concat(con, ", "))
  put("")
  put("DONE - screenshot this")
end)

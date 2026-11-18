local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Probe2UI"
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
frame.Size = UDim2.fromOffset(330, 430)
frame.Position = UDim2.new(0, 78, 0, 95)
frame.BackgroundColor3 = Color3.new(0, 0, 0)
frame.BackgroundTransparency = 0.12
frame.BorderSizePixel = 2
frame.BorderColor3 = Color3.fromRGB(70, 240, 150)
frame.Parent = gui

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 22)
bar.BackgroundColor3 = Color3.fromRGB(20, 40, 28)
bar.Parent = frame

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 1, -22)
label.Position = UDim2.new(0, 4, 0, 24)
label.BackgroundTransparency = 1
label.Font = Enum.Font.Code
label.TextSize = 9
label.TextColor3 = Color3.fromRGB(200, 255, 220)
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.TextWrapped = true
label.Text = "scanning..."
label.Parent = frame

local mv = Instance.new("TextButton")
mv.Text = "MOVE"
mv.Size = UDim2.fromOffset(50, 18)
mv.Position = UDim2.new(0, 4, 0, 2)
mv.BackgroundColor3 = Color3.fromRGB(40, 70, 50)
mv.TextColor3 = Color3.new(1, 1, 1)
mv.TextSize = 10
mv.Parent = bar

local close = Instance.new("TextButton")
close.Text = "X"
close.Size = UDim2.fromOffset(26, 18)
close.Position = UDim2.new(1, -30, 0, 2)
close.BackgroundColor3 = Color3.fromRGB(190, 60, 70)
close.TextColor3 = Color3.new(1, 1, 1)
close.Parent = bar
close.MouseButton1Click:Connect(function() gui:Destroy() end)

local dragging = false
local ds, sp
mv.InputBegan:Connect(function(i)
  if i.UserInputType == Enum.UserInputType.Touch
    or i.UserInputType == Enum.UserInputType.MouseButton1 then
    dragging = true
    ds = i.Position
    sp = frame.Position
  end
end)
game:GetService("UserInputService").InputChanged:Connect(function(i)
  if not dragging then return end
  local d = i.Position - ds
  frame.Position = UDim2.new(0, sp.X.Offset + d.X,
    0, sp.Y.Offset + d.Y)
end)
game:GetService("UserInputService").InputEnded:Connect(function(i)
  if i.UserInputType == Enum.UserInputType.Touch
    or i.UserInputType == Enum.UserInputType.MouseButton1 then
    dragging = false
  end
end)

task.spawn(function()
  local out = {}
  local function put(s)
    out[#out + 1] = s
    label.Text = table.concat(out, "\n")
  end

  put("SHAPE PROBE - stay in the match")
  put("")

  -- collect every character so we can skip them
  local skip = {}
  for _, p in ipairs(Players:GetPlayers()) do
    if p.Character then
      for _, d in ipairs(p.Character:GetDescendants()) do
        skip[d] = true
      end
    end
  end

  put("--- workspace top level ---")
  for _, c in ipairs(workspace:GetChildren()) do
    put(c.ClassName .. " : " .. c.Name)
  end
  put("")

  -- round, unanchored, not inside any character
  local found = {}
  pcall(function()
    for _, d in ipairs(workspace:GetDescendants()) do
      if d:IsA("BasePart") and not skip[d] then
        local s = d.Size
        local mx = math.max(s.X, s.Y, s.Z)
        local mn = math.min(s.X, s.Y, s.Z)
        if mx >= 1.5 and mx <= 12 and mn / mx > 0.6 then
          found[#found + 1] = { p = d, r = mn / mx, mx = mx }
        end
      end
    end
  end)

  table.sort(found, function(a, b)
    return a.r > b.r
  end)

  put("round parts found: " .. tostring(#found))
  put("--- top ---")

  for i = 1, math.min(10, #found) do
    local f = found[i]
    local p = f.p
    local path = "?"
    pcall(function() path = p:GetFullName() end)
    put(string.format("%d r=%.2f sz=%.1f anch=%s %s",
      i, f.r, f.mx, tostring(p.Anchored), path))
  end

  put("")

  if #found == 0 then
    put("NOTHING ROUND FOUND")
    return
  end

  local t = found[1].p

  local kids = {}
  pcall(function()
    for _, d in ipairs(t:GetChildren()) do
      kids[#kids + 1] = d.ClassName .. ":" .. d.Name
    end
  end)
  put("top kids: " .. table.concat(kids, ", "))
  put("")

  local before = t.Position
  local rot = t.CFrame.Rotation
  pcall(function()
    t.CFrame = CFrame.new(before + Vector3.new(0, 0, 6)) * rot
  end)
  task.wait(0.35)
  local moved = (t.Position - before).Magnitude

  if moved > 3 then
    put("CFRAME: STICKS " .. math.floor(moved))
  else
    put("CFRAME: SNAPPED " .. math.floor(moved * 10) / 10)
  end

  put("")
  put("DONE - screenshot this")
end)

TOOL.Category = "Construction"
TOOL.Name = "#Inertia"
TOOL.Command = nil
TOOL.ConfigName = nil
TOOL.ClientConVar["mode"] = "direct"
TOOL.ClientConVar["x"] = "10"
TOOL.ClientConVar["y"] = "10"
TOOL.ClientConVar["z"] = "10"
TOOL.ClientConVar["xyz"] = "10"
TOOL.ClientConVar["tooltipscale"] = "1"

if CLIENT then
    TOOL.Information = {
        {
            name = "left"
        },
        {
            name = "right"
        },
        {
            name = "reload"
        }
    }

    language.Add("tool.inertia.name", "Inertia")
    language.Add("tool.inertia.desc", "Sets an entity's rotational inertia (resistance to rotation) without changing its mass")
    language.Add("tool.inertia.left", "Set inertia")
    language.Add("tool.inertia.right", "Get inertia")
    language.Add("tool.inertia.reload", "Reset inertia to default")
    language.Add("tool.inertia.mode", "Mode")
    language.Add("tool.inertia.modehelp", "If mode is set to 'DIRECTLY SET', inertia is set per-axis according to each slider.\n\nIf mode is set to 'MULTIPLE OF DEFAULT', inertia is set per-axis as a multiple of the prop's default inertia.")
    language.Add("tool.inertia.note", "NOTE: You can use higher or lower values by typing them manually.")
    language.Add("tool.inertia.x", "X axis inertia")
    language.Add("tool.inertia.y", "Y axis inertia")
    language.Add("tool.inertia.z", "Z axis inertia")
    language.Add("tool.inertia.xyz", "XYZ (all axes) inertia")
    language.Add("tool.inertia.tooltipscale", "Tooltip Scale")
    language.Add("tool.inertia.warning", "WARNING: VERY HIGH VALUES ON ONE AXIS MAY CAUSE UNEXPECTED RESULTS!\nThis includes things such as props deleting themselves due to crazy physics. Be careful!")
end

local excluded = {"func_", "prop_dynamic", "prop_ragdoll", "prop_vehicle", "player", "npc"}
local entityMeta = FindMetaTable("Entity")

--Regular vectors are heavily compressed, have to do this for accuracy
function entityMeta:SetNWVectorPrecise(key, value)
    self:SetNWFloat(key .. "_x", value[1])
    self:SetNWFloat(key .. "_y", value[2])
    self:SetNWFloat(key .. "_z", value[3])
end

function entityMeta:GetNWVectorPrecise(key, fallback)
    local x = self:GetNWFloat(key .. "_x", fallback)
    local y = self:GetNWFloat(key .. "_y", fallback)
    local z = self:GetNWFloat(key .. "_z", fallback)

    return Vector(x, y, z)
end

if entityMeta.OldPhysicsInitSphere then
    entityMeta.PhysicsInitSphere = entityMeta.OldPhysicsInitSphere
end

entityMeta.OldPhysicsInitSphere = entityMeta.PhysicsInitSphere

function entityMeta:PhysicsInitSphere(...)
    local ret = self:OldPhysicsInitSphere(...)

    timer.Simple(0, function()
        self.defaultInertia = self:GetPhysicsObject():GetInertia() / self:GetPhysicsObject():GetMass()
        self:SetNWVectorPrecise("defaultinertia", self.defaultInertia)
    end)

    return ret
end

local function isReallyValid(ent)
    if not IsValid(ent) then return false end
    if not ent:IsValid() then return false end
    if ent:IsWorld() then return false end

    for _, v in pairs(excluded) do
        if string.find(ent:GetClass(), v) then return false end
    end

    if SERVER and not ent:GetPhysicsObject():IsValid() then return false end

    return true
end

local function vClamp(v, min, max)
    return Vector(math.Clamp(v.x, min, max), math.Clamp(v.y, min, max), math.Clamp(v.z, min, max))
end

if SERVER then
    hook.Add("OnEntityCreated", "Inertia::EntCreated", function(ent)
        timer.Simple(0, function()
            if isReallyValid(ent) then
                ent.defaultInertia = ent:GetPhysicsObject():GetInertia() / ent:GetPhysicsObject():GetMass()
                ent:SetNWVectorPrecise("defaultinertia", ent.defaultInertia)
            end
        end)
    end)
end

local function setInertia(player, entity, data)
    if CLIENT then return end

    --1 tick delay to ensure this is called after the OnEntityCreated hook
    timer.Simple(0, function()
        if entity:GetPhysicsObject():IsValid() and data.inertia and data.defaultInertia then
            entity:GetPhysicsObject():SetInertia(data.inertia)
            entity.defaultInertia = data.defaultInertia
            entity:SetNWVectorPrecise("defaultinertia", data.defaultInertia)
        end

        duplicator.StoreEntityModifier(entity, "inertia", data)
    end)
end

duplicator.RegisterEntityModifier("inertia", setInertia)

function TOOL:Think()
    if CLIENT then return end
    local owner = self:GetOwner()
    local ent = owner:GetEyeTrace().Entity
    if not isReallyValid(ent) then return end
    owner:SetNWVectorPrecise("inertia", ent:GetPhysicsObject():GetInertia())
    owner:SetNWFloat("inertiamass", ent:GetPhysicsObject():GetMass())
end

function TOOL:LeftClick(trace)
    if not isReallyValid(trace.Entity) then return false end

    if SERVER then
        local inertia = Vector(self:GetClientInfo("x"), self:GetClientInfo("y"), self:GetClientInfo("z"))

        if self:GetClientInfo("mode") == "direct" then
            setInertia(self:GetOwner(), trace.Entity, {
                inertia = vClamp(inertia, 0.1, 100000000),
                defaultInertia = trace.Entity.defaultInertia
            })
        else
            setInertia(self:GetOwner(), trace.Entity, {
                inertia = vClamp(trace.Entity.defaultInertia * inertia * trace.Entity:GetPhysicsObject():GetMass(), 0.1, 100000000),
                defaultInertia = trace.Entity.defaultInertia
            })
        end
    end

    return true
end

function TOOL:RightClick(trace)
    if not isReallyValid(trace.Entity) then return false end

    if SERVER then
        local inertia = self:GetOwner():GetNWVectorPrecise("inertia", Vector(1, 1, 1))
        local defaultInertia = trace.Entity:GetNWVectorPrecise("defaultinertia", Vector(1, 1, 1)) * trace.Entity:GetPhysicsObject():GetMass()

        --Return the inertia multiplier instead of raw inertia values if using mode 2
        if self:GetClientInfo("mode") == "multiplier" then
            inertia = Vector(inertia.x / defaultInertia.x, inertia.y / defaultInertia.y, inertia.z / defaultInertia.z)
        end

        self:GetOwner():ConCommand("inertia_x " .. inertia.x)
        self:GetOwner():ConCommand("inertia_y " .. inertia.y)
        self:GetOwner():ConCommand("inertia_z " .. inertia.z)
    end

    return true
end

function TOOL:Reload(trace)
    if not isReallyValid(trace.Entity) then return false end

    if SERVER and trace.Entity.defaultInertia then
        trace.Entity:GetPhysicsObject():SetInertia(trace.Entity.defaultInertia * trace.Entity:GetPhysicsObject():GetMass())
        duplicator.ClearEntityModifier(trace.Entity, "inertia")
    end

    return true
end

function TOOL.BuildCPanel(cp)
    cp:AddControl("Header", {
        Text = "#tool.inertia.name",
        Description = "#tool.inertia.desc"
    })

    cp:AddControl("ComboBox", {
        Label = "#tool.inertia.mode",
        MenuButton = 0,
        Options = {
            ["Directly set"] = {
                inertia_mode = "direct"
            },
            ["Multiple of default"] = {
                inertia_mode = "multiplier"
            }
        }
    })

    cp:ControlHelp("")
    cp:ControlHelp("#tool.inertia.modehelp")

    cp:AddControl("Slider", {
        Label = "#tool.inertia.x",
        Type = "Float",
        Min = "1",
        Max = "100",
        Command = "inertia_x"
    })

    cp:AddControl("Slider", {
        Label = "#tool.inertia.y",
        Type = "Float",
        Min = "1",
        Max = "100",
        Command = "inertia_y"
    })

    cp:AddControl("Slider", {
        Label = "#tool.inertia.z",
        Type = "Float",
        Min = "1",
        Max = "100",
        Command = "inertia_z"
    })

    cp:AddControl("Slider", {
        Label = "#tool.inertia.xyz",
        Type = "Float",
        Min = "1",
        Max = "100",
        Command = "inertia_xyz"
    })

    cp:ControlHelp("#tool.inertia.note")
    cp:ControlHelp("")
    cp:ControlHelp("#tool.inertia.warning")

    cp:AddControl("Slider", {
        Label = "#tool.inertia.tooltipscale",
        Type = "Float",
        Min = "0.25",
        Max = "4",
        Command = "inertia_tooltipscale"
    })
end

if CLIENT then
    cvars.RemoveChangeCallback("inertia_xyz", "inertia_changecallback")

    cvars.AddChangeCallback("inertia_xyz", function(_, _, newValue)
        LocalPlayer():ConCommand("inertia_x " .. newValue)
        LocalPlayer():ConCommand("inertia_y " .. newValue)
        LocalPlayer():ConCommand("inertia_z " .. newValue)
    end, "inertia_changecallback")

    surface.CreateFont("InertiaFont", {
        font = "coolvetica",
        size = 75,
        weight = 10,
        antialias = true
    })

    local function matrixToString(m)
        return "[" .. math.Round(m[1], 2) .. ", " .. math.Round(m[2], 2) .. ", " .. math.Round(m[3], 2) .. "]"
    end

    hook.Add("HUDPaint", "Inertia::HUD", function()
        local ply = LocalPlayer()
        if not ply:GetActiveWeapon():IsValid() or ply:GetActiveWeapon():GetClass() ~= "gmod_tool" or ply:GetInfo("gmod_toolmode") ~= "inertia" then return end
        local ent = LocalPlayer():GetEyeTrace().Entity
        if not isReallyValid(ent) then return end
        local obb = ent:OBBCenter()
        obb:Rotate(ent:GetAngles())
        local pos = (ent:GetPos() + obb):ToScreen()
        surface.SetFont("InertiaFont")
        local str = "Current: " .. matrixToString(ply:GetNWVectorPrecise("inertia"))
        local str2 = "Default: " .. matrixToString(ent:GetNWVectorPrecise("defaultinertia") * ply:GetNWFloat("inertiamass"))
        local w, h = surface.GetTextSize(str)
        local w2, _ = surface.GetTextSize(str2)
        surface.SetDrawColor(Color(0, 0, 0, 100))
        local mat = Matrix()
        mat:Translate(Vector(pos.x, pos.y))
        mat:Scale(Vector(1, 1, 1) * ply:GetInfoNum("inertia_tooltipscale", 1) / 2)
        mat:Translate(-Vector(pos.x, pos.y))
        cam.PushModelMatrix(mat)
            surface.DrawRect(pos.x - w / 2, pos.y - h, w, h)
            draw.DrawText(str, "InertiaFont", pos.x, pos.y - h, Color(255, 255, 255), 1)
            surface.DrawRect(pos.x - w2 / 2, pos.y, w2, h)
            draw.DrawText(str2, "InertiaFont", pos.x, pos.y, Color(255, 255, 255), 1)
        cam.PopModelMatrix()
    end)
end
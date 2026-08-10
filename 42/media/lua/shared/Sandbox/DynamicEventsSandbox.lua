if not SandboxVars then SandboxVars = {} end

SandboxVars.DynamicEvents = {
    Enabled              = true,
    MaxActiveEvents      = 3,
    MinHoursBetweenEvents = 1.0,
    EventChance          = 50,
    GracePeriodHours     = 1.0,
    EventCleanup         = true,
    Debug                = false,

    EventToggles = {
        heli_crash   = true,
        train_wreck  = true,
        convoy_crash = true,
        horde        = false,
    },
}
